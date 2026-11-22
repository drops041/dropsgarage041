"""CAIXA DE RODA — escurece por dentro do para-lama (a "caixa de roda") de um carro já importado.

Muitos modelos têm o forro de dentro do para-lama claro (cinza/branco) ou a chapa pintada virada pra dentro.
Com o carro socado, isso aparece em volta do pneu como uns "dentes" brancos.
Aqui os triângulos de dentro da caixa de roda passam pra um material preto fosco (não apaga nada).

Uso: python3 ferramentas/caixa_de_roda.py [--salvar] [--raio 1.45] [--xmin 0.45] [--xmax 0.85] [--pular door] id1 id2 ...
Região (coordenadas do carro): distância até o centro da roda original (y=wy, z=eixo) < raio * wy
e |x| entre W/2 - 0.42 e a pele de fora do para-lama menos 3 cm.
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB  # noqa: E402

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
NAO_MEXE = ("GLASS", "LENS", "TAIL", "LUZ", "MASCARA", "REFLETOR", "LENTE", "PISCA", "RE", "CROMO", "ARO", "PNEU")
NOME_PRETO = "INTERIOR__caixa_roda"


def material_preto(j):
    for i, m in enumerate(j["materials"]):
        if m.get("name") == NOME_PRETO:
            return i
    j["materials"].append({"name": NOME_PRETO, "pbrMetallicRoughness": {"baseColorFactor": [0.03, 0.03, 0.035, 1.0],
                           "metallicFactor": 0.0, "roughnessFactor": 0.9}, "doubleSided": True})
    return len(j["materials"]) - 1


def claro(m):
    c = m.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])
    tem_tex = "baseColorTexture" in m.get("pbrMetallicRoughness", {})
    return tem_tex or (0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]) > 0.2


def processar(cid, c, raio, salvar, xmin=None, xmax=None, pular=None, centro=False, caixa=None):
    arq = os.path.join(RAIZ, "modelos", "carros", cid + ".glb")
    g = GLB(arq)
    j = g.j
    W, wy = float(c["W"]), float(c["wy"])
    eixos = (float(c["axF"]), float(c["axR"]))
    prims = []
    feitos = set()
    for p in g.primitivas():
        if id(p["prim"]) in feitos or "indices" not in p["prim"]:
            continue
        feitos.add(id(p["prim"]))
        prims.append(p)
    mats = j["materials"]
    # pele de fora do para-lama: |x| da lataria pintada perto das rodas
    xs = []
    for p in prims:
        nome = mats[p["prim"]["material"]].get("name", "") if p["prim"].get("material") is not None else ""
        if nome.startswith("PAINT"):
            P = p["pw"]
            for ax in eixos:
                r = np.hypot(P[:, 1] - wy, P[:, 2] - ax)
                xs.append(np.abs(P[(r < raio * wy) & (r > 1.0 * wy), 0]))
    xs = np.concatenate(xs) if xs else np.array([W / 2])
    xo = float(np.percentile(xs, 95)) - 0.03 if len(xs) else W / 2 - 0.05
    if xmax is not None:
        xo = xmax
    preto = material_preto(j) if salvar else -1
    total = 0
    for p in prims:
        prim = p["prim"]
        mi = prim.get("material")
        m = mats[mi] if mi is not None else {}
        nome = m.get("name", "")
        if nome.split("__")[0] in NAO_MEXE or nome.startswith(("LUZ", "INTERIOR")) or nome == NOME_PRETO:
            continue
        if nome.startswith("PAINT") or not claro(m):
            continue
        if pular and any(k in p["nome"] for k in pular):
            continue   # ex.: portas (o forro da porta passa perto da roda mas é da porta)   # lataria pintada não: por fora ela também passa perto da roda (o topo do para-lama)
        T = p["pw"][p["idx"].reshape(-1, 3)]
        s = np.zeros(len(T), bool)
        for ax in eixos:
            r = np.hypot(T[:, :, 1] - wy, T[:, :, 2] - ax)
            ax_ = np.abs(T[:, :, 0])
            dentro = (r < raio * wy) & (ax_ < xo) & (ax_ > (W / 2 - 0.42 if xmin is None else xmin))
            s |= dentro.sum(1) >= (2 if centro else 3)   # --centro: basta 2 cantos dentro (parede grande da caixa de roda)
            if caixa:   # --caixa xmin,meio_z,ymax: caixa reta em volta do eixo (paredes fundas, ex.: G5 Cross)
                C = T.mean(1)
                s |= (np.abs(C[:, 0]) > caixa[0]) & (np.abs(C[:, 0]) < xo) & (np.abs(C[:, 2] - ax) < caixa[1]) & (C[:, 1] < caixa[2])
        n = int(s.sum())
        if not n:
            continue
        total += n
        print("  %s: %d triângulos (%s)" % (cid, n, nome))
        if not salvar:
            continue
        idx = p["idx"].reshape(-1, 3)
        fica = idx[~s].astype(np.uint32).ravel()
        vai = idx[s].astype(np.uint32).ravel()
        if len(fica) == 0:
            fica = np.zeros(3, np.uint32)
        vi = g.add_view(fica.tobytes(), 34963)
        j["accessors"].append({"bufferView": vi, "componentType": 5125, "count": int(len(fica)), "type": "SCALAR"})
        prim["indices"] = len(j["accessors"]) - 1
        vi = g.add_view(vai.tobytes(), 34963)
        j["accessors"].append({"bufferView": vi, "componentType": 5125, "count": int(len(vai)), "type": "SCALAR"})
        novo = {"attributes": dict(prim["attributes"]), "indices": len(j["accessors"]) - 1, "material": preto}
        malha = j["meshes"][j["nodes"][p["no"]]["mesh"]]
        malha["primitives"].append(novo)
    print("%s: pele de fora |x|=%.3f, %d triângulos pra caixa de roda preta" % (cid, xo + 0.03, total))
    if salvar and total:
        g.salvar(arq)


def main():
    args = sys.argv[1:]
    salvar = "--salvar" in args
    raio = 1.45
    if "--raio" in args:
        raio = float(args[args.index("--raio") + 1])
    xmin = None   # --xmin 0.45: pega também suspensão/braço mais pra dentro (picape larga)
    if "--xmin" in args:
        xmin = float(args[args.index("--xmin") + 1])
    xmax = float(args[args.index("--xmax") + 1]) if "--xmax" in args else None   # (G5 Cross) parede até perto da pele
    pular = args[args.index("--pular") + 1].split(",") if "--pular" in args else None   # --pular door
    caixa = [float(v) for v in args[args.index("--caixa") + 1].split(",")] if "--caixa" in args else None
    ids = [a for i, a in enumerate(args) if not a.startswith("--") and (i == 0 or args[i - 1] not in ("--raio", "--xmin", "--xmax", "--pular", "--caixa"))]
    carros = {c["id"]: c for c in json.load(open(os.path.join(RAIZ, "carros.json"), encoding="utf8"))}
    for cid in ids:
        processar(cid, carros[cid], raio, salvar, xmin, xmax, pular, "--centro" in args, caixa)


if __name__ == "__main__":
    main()
