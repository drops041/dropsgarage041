"""TIRAR EMBLEMAS — some com os emblemas das montadoras (logo da grade, da tampa traseira e letreiros)
pra publicar o jogo sem problema com marca registrada.

Como acha: em cada malha do carro separa as "ilhas" (pedaços soltos de triângulos). Emblema é uma ilha
pequena (até ~30 cm), fina, perto do meio do carro (|x| pequeno) e na frente ou na traseira. Também
some com malhas cujo nome/material diz que é letreiro/logo.

Uso: python3 ferramentas/tirar_emblemas.py [--ver] [id ...]
  --ver: só mostra o que tiraria, não grava
"""
import json
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB  # noqa: E402

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
NOME_LOGO = re.compile(r"letter|logo|badge|emblem|for_badge", re.I)


def ilhas(F, P):
    """componentes conexos dos triângulos (vértices soldados por posição)"""
    ch = np.round(P / 2e-4).astype(np.int64)
    _, inv = np.unique(ch, axis=0, return_inverse=True)
    inv = inv.ravel()
    Fv = inv[F]
    n = inv.max() + 1
    pai = np.arange(n)

    def raiz(a):
        while pai[a] != a:
            pai[a] = pai[pai[a]]
            a = pai[a]
        return a
    for a, b, c in Fv:
        ra, rb, rc = raiz(a), raiz(b), raiz(c)
        if ra != rb:
            pai[rb] = ra
        rc = raiz(c)
        ra = raiz(a)
        if ra != rc:
            pai[rc] = ra
    r = np.array([raiz(v) for v in range(n)])
    return r[Fv[:, 0]]


def processar(arq, ver):
    g = GLB(arq)
    prims = list(g.primitivas())
    todos = np.vstack([p["pw"] for p in prims])
    lo, hi = todos.min(0), todos.max(0)
    comp = hi[2] - lo[2]
    larg = hi[0] - lo[0]
    cx = (lo[0] + hi[0]) / 2
    tirados = 0
    for p in prims:
        mat = g.j["materials"][p["mat"]].get("name", "") if p.get("mat") is not None else ""
        no = p.get("nome", "") or ""
        F = p["idx"].reshape(-1, 3)
        P = p["pw"]
        if len(F) == 0:
            continue
        apagar = np.zeros(len(F), bool)
        if NOME_LOGO.search(mat) or NOME_LOGO.search(no):
            apagar[:] = True
        else:
            if mat.upper().startswith(("INTERIOR", "VIDRO", "PNEU", "ARO", "RODA")):
                continue
            lab = ilhas(F, P)
            # pedaços repetidos (colmeia da grade, frisos, parafusos) não são emblema: guarda a "forma" de cada ilha
            formas = {}
            for k in np.unique(lab):
                V = P[np.unique(F[lab == k])]
                f_ = tuple(np.round(np.sort(V.max(0) - V.min(0)) / 0.01).astype(int))
                formas.setdefault(f_, []).append(k)
            repetida = set()
            for f_, ks in formas.items():
                if len(ks) >= 4:
                    repetida.update(ks)
            for k in np.unique(lab):
                if k in repetida:
                    continue
                sel = lab == k
                V = P[np.unique(F[sel])]
                a, b = V.min(0), V.max(0)
                t = b - a
                c = (a + b) / 2
                pequeno = t.max() < 0.30 and t.min() < 0.07 and np.sort(t)[1] < 0.2
                meio = abs(c[0] - cx) < 0.18 * larg
                ponta = c[2] > hi[2] - 0.16 * comp or c[2] < lo[2] + 0.16 * comp
                altura = lo[1] + 0.25 < c[1] < lo[1] + 1.25
                if pequeno and meio and ponta and altura and sel.sum() >= 12:
                    apagar |= sel
        if apagar.any():
            tirados += int(apagar.sum())
            if not ver:
                nova = np.ascontiguousarray(F[~apagar].ravel().astype(np.uint32))
                if len(nova) == 0:
                    nova = np.zeros(3, np.uint32)
                vi = g.add_view(nova.tobytes(), 34963)
                g.j["accessors"].append({"bufferView": vi, "componentType": 5125, "count": int(len(nova)), "type": "SCALAR"})
                p["prim"]["indices"] = len(g.j["accessors"]) - 1
    if tirados and not ver:
        g.salvar(arq)
    return tirados


def main():
    args = sys.argv[1:]
    ver = "--ver" in args
    ids = [a for a in args if not a.startswith("--")] or [c["id"] for c in json.load(open(os.path.join(RAIZ, "carros.json")))]
    for i in ids:
        arq = os.path.join(RAIZ, "modelos", "carros", i + ".glb")
        print(i, ":", processar(arq, ver), "triângulos de emblema", "(só vendo)" if ver else "")


if __name__ == "__main__":
    main()
