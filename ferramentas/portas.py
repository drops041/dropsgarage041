"""PORTAS — acha as portas, o porta-malas/tampa da caçamba e o capô de um carro já importado
e deixa eles abrindo no jogo (botões ABRIR PORTAS / ABRIR PORTA-MALAS na garagem e a pé).

Uso:  python3 ferramentas/portas.py golfgti jetta ...   (ids do carros.json; os modelos já em modelos/carros)

Como funciona:
  - procura nós com nome de porta (door), porta-malas (trunk lid, tailgate, boot, hatch) e capô (hood, bonnet)
  - junta as peças da mesma porta (lado de fora + forro de dentro) pelo lado e pela posição
  - a dobradiça da porta fica na beirada da frente; a do porta-malas em cima (na tampa da caçamba, embaixo)
  - renomeia os nós com um prefixo (PFL__, PFR__, PRL__, PRR__, PTR__, PCA__) e grava "partes" no carros.json
"""
import json
import math
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB  # noqa: E402

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
NAO = ("limiter", "seal", "rubber", "support", "strut", "carpet", "shelf", "floor", "sill", "hinge", "dummy_helper")
RE_PORTA = re.compile(r"door|porta(?!.?malas)|puerta|tuer")
RE_TAMPA_FORTE = re.compile(r"trunk.?lid|tailgate|liftgate|boot|hatch|tampa")
RE_TAMPA = re.compile(r"trunk|porta.?malas")
RE_CAPO = re.compile(r"hood|bonnet|capo")


def quat(eixo, graus):
    a = math.radians(graus) / 2
    e = np.array(eixo, float)
    e /= np.linalg.norm(e)
    s = math.sin(a)
    return [round(float(e[0] * s), 5), round(float(e[1] * s), 5), round(float(e[2] * s), 5), round(math.cos(a), 5)]


def processar(cid, carro):
    arq = os.path.join(RAIZ, "modelos", "carros", cid + ".glb")
    g = GLB(arq)
    nos = g.j["nodes"]
    # pontos (coordenadas do carro) de cada nó e de toda a subárvore
    pais = {}
    for i, n in enumerate(nos):
        for f in n.get("children", []):
            pais[f] = i
    pts_no = {}
    for p in g.primitivas():
        pts_no.setdefault(p["no"], []).append(p["pw"])
    todos = np.concatenate([np.concatenate(v) for v in pts_no.values()])
    lo, hi = todos.min(0), todos.max(0)
    W, L = hi[0] - lo[0], hi[2] - lo[2]
    cache = {}

    def sub(i):
        if i in cache:
            return cache[i]
        arrs = list(pts_no.get(i, []))
        for f in nos[i].get("children", []):
            q = sub(f)
            if q is not None:
                arrs.append(q)
        r = np.concatenate(arrs) if arrs else None
        cache[i] = r
        return r

    alcancaveis = set()
    pilha = list(g.raizes())
    while pilha:
        i = pilha.pop()
        alcancaveis.add(i)
        pilha.extend(nos[i].get("children", []))

    def ancestral_em(i, conj):
        while i in pais:
            i = pais[i]
            if i in conj:
                return True
        return False

    def nome(i):
        return nos[i].get("name", "").lower()

    # ---- portas
    cand = []
    for i in sorted(alcancaveis):
        nm = nome(i)
        if not RE_PORTA.search(nm) or any(k in nm for k in NAO):
            continue
        q = sub(i)
        if q is None or len(q) < 30:
            continue
        a, b = q.min(0), q.max(0)
        cx = (a[0] + b[0]) / 2
        if (b[0] - a[0]) < 0.45 * W and (b[2] - a[2]) < 0.5 * L and (b[1] - a[1]) > 0.35 and abs(cx) > 0.2 * W:
            cand.append(i)
    portas = [i for i in cand if not ancestral_em(i, set(cand))]
    grupos = []   # [lado, cz, [nós]]
    for i in sorted(portas, key=lambda i: sub(i)[:, 2].mean()):
        q = sub(i)
        lado = 1 if q[:, 0].mean() > 0 else -1
        cz = (q[:, 2].min() + q[:, 2].max()) / 2
        for gr in grupos:
            if gr[0] == lado and abs(gr[1] - cz) < 0.35:
                gr[2].append(i)
                break
        else:
            grupos.append([lado, cz, [i]])
    partes = {}
    lista = []
    for lado in (-1, 1):
        gs = sorted([gr for gr in grupos if gr[0] == lado], key=lambda gr: -gr[1])
        for k, gr in enumerate(gs[:2]):
            q = np.concatenate([sub(i) for i in gr[2]])
            a, b = q.min(0), q.max(0)
            ext = b[0] if lado > 0 else a[0]
            piv = [round(float(ext - lado * 0.06), 3), round(float((a[1] + b[1]) / 2), 3), round(float(b[2] - 0.03), 3)]
            pref = "P%s%s" % ("F" if k == 0 else "R", "R" if lado > 0 else "L")
            for i in gr[2]:
                nos[i]["name"] = pref + "__" + nos[i].get("name", "")
            lista.append([pref, piv, quat([0, 1, 0], -lado * 62.0)])
    if lista:
        partes["portas"] = {"nome": "portas", "p": lista}

    # ---- porta-malas / tampa da caçamba
    def tampas(rx):
        cs = []
        for i in sorted(alcancaveis):
            nm = nome(i)
            if not rx.search(nm) or any(k in nm for k in NAO) or nm.startswith("p") and "__" in nm:
                continue
            if RE_PORTA.search(nm) and not RE_TAMPA_FORTE.search(nm):
                continue
            q = sub(i)
            if q is None or len(q) < 30:
                continue
            a, b = q.min(0), q.max(0)
            if (b[0] - a[0]) > 0.55 * W and (b[2] + a[2]) / 2 < lo[2] + 0.45 * L and (b[1] - a[1]) > 0.15:
                cs.append(i)
        return [i for i in cs if not ancestral_em(i, set(cs))]
    tr = tampas(RE_TAMPA_FORTE) or tampas(RE_TAMPA)
    if tr:
        q = np.concatenate([sub(i) for i in tr])
        a, b = q.min(0), q.max(0)
        if carro.get("picape"):
            emb = q[q[:, 1] < a[1] + 0.06]
            piv = [0.0, round(float(a[1] + 0.02), 3), round(float(emb[:, 2].mean()), 3)]
            rot = quat([1, 0, 0], -86.0)
            nome_p = "tampa"
        else:
            fr = q[q[:, 2] > b[2] - 0.06]
            piv = [0.0, round(float(fr[:, 1].max() - 0.01), 3), round(float(b[2] - 0.01), 3)]
            rot = quat([1, 0, 0], 68.0)
            nome_p = "porta-malas"
        for i in tr:
            nos[i]["name"] = "PTR__" + nos[i].get("name", "")
        partes["tras"] = {"nome": nome_p, "p": [["PTR", piv, rot]]}

    # ---- capô
    cs = []
    for i in sorted(alcancaveis):
        nm = nome(i)
        if not RE_CAPO.search(nm) or any(k in nm for k in NAO) or "__" in nm[:5]:
            continue
        q = sub(i)
        if q is None or len(q) < 30:
            continue
        a, b = q.min(0), q.max(0)
        if (b[0] - a[0]) > 0.55 * W and (a[2] + b[2]) / 2 > lo[2] + 0.55 * L and a[1] > lo[1] + 0.4:
            cs.append(i)
    cs = [i for i in cs if not ancestral_em(i, set(cs))]
    if cs:
        q = np.concatenate([sub(i) for i in cs])
        a, b = q.min(0), q.max(0)
        tr_ = q[q[:, 2] < a[2] + 0.06]
        piv = [0.0, round(float(tr_[:, 1].max()), 3), round(float(a[2] + 0.02), 3)]
        for i in cs:
            nos[i]["name"] = "PCA__" + nos[i].get("name", "")
        partes["frente"] = {"nome": "capô", "p": [["PCA", piv, quat([1, 0, 0], -52.0)]]}

    if partes:
        g.salvar(arq)
    return partes


def main():
    cj = os.path.join(RAIZ, "carros.json")
    carros = json.load(open(cj, encoding="utf8"))
    for cid in sys.argv[1:]:
        c = next((x for x in carros if x["id"] == cid), None)
        if c is None:
            print(cid, ": não está no carros.json")
            continue
        p = processar(cid, c)
        if p:
            c["partes"] = p
        else:
            c.pop("partes", None)
        print(cid, {k: (v["nome"], [x[0] for x in v["p"]]) for k, v in p.items()} or "sem portas separadas")
    json.dump(carros, open(cj, "w", encoding="utf8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
