#!/usr/bin/env python3
"""LUZES — separa as peças dos faróis e lanternas de um carro em materiais com etiqueta,
pra o jogo (visual 2) usar material próprio em cada uma:

  MASCARA__   fundo do farol (máscara negra)          REFLETOR__  parábola cromada (acende um pouco)
  LENTE__     lente de fora, transparente             TAIL__      lente vermelha da lanterna (acende / freio)
  PISCA__     lente âmbar do pisca                    RE__        lente clara da luz de ré

Muitos modelos usam o MESMO material no vidro da janela e na lente do farol, ou o fundo do farol
sem cor (fica branco). Por isso a regra pode valer só dentro de uma caixa (região do farol/lanterna):
os triângulos de dentro vão pra uma primitiva nova com o material novo, o resto fica como estava.

uso: luzes.py id [id ...]      (regras na tabela REGRAS abaixo; roda uma vez por modelo)
"""
import copy
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB  # noqa: E402

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# caixas em metros, no espaço do carro (x = lado, y = altura, z = frente +); |x| usa o valor absoluto
FAROL = dict(ax=(0.42, 1.0), y=(0.45, 0.80), z=(1.55, 2.25))
LANTERNA = dict(ax=(0.50, 1.0), y=(0.55, 0.98), z=(-2.30, -1.95))

# (material original, caixa ou None, nome novo — None = apaga os triângulos, ex.: lente duplicada)
REGRAS = {
    "saveirog5": [
        ("Matte__FF4B4B4B1", None, "MASCARA__farol"),
        ("Matte__FFFFAF1", None, "REFLETOR__farol"),
        ("Matte__FF00FFC1", FAROL, "REFLETOR__farol"),
        ("GLASS__Translucent_Glass_Gray_1", FAROL, "LENTE__farol"),
        ("GLASS__preto__spec_tra1", FAROL, None),            # a mesma lente de novo, por cima
        ("Diego1", None, "PISCA__ambar"),
        ("Rosso_Alfa", None, "TAIL__vermelho"),
        ("LUZ_head__0132_LightGray", None, "RE__lente"),
        ("GLASS__preto__trans_1", LANTERNA, "LENTE__lanterna"),
        ("material_0", LANTERNA, "REFLETOR__lanterna"),
        ("Matte__FFCC1", None, "TAIL__brake"),
    ],
}


def dentro(C, cx):
    if cx is None:
        return np.ones(len(C), bool)
    ax = np.abs(C[:, 0])
    return (ax >= cx["ax"][0]) & (ax <= cx["ax"][1]) & (C[:, 1] >= cx["y"][0]) & (C[:, 1] <= cx["y"][1]) \
        & (C[:, 2] >= cx["z"][0]) & (C[:, 2] <= cx["z"][1])


def indices(g, tri):
    ind = np.ascontiguousarray(tri.ravel().astype(np.uint32))
    vi = g.add_view(ind.tobytes(), 34963)
    g.j["accessors"].append({"bufferView": vi, "componentType": 5125, "count": len(ind), "type": "SCALAR"})
    return len(g.j["accessors"]) - 1


def processar(cid):
    arq = os.path.join(RAIZ, "modelos", "carros", cid + ".glb")
    g = GLB(arq)
    mats = g.j["materials"]
    nomes = [m.get("name", "") for m in mats]
    if any(n.startswith(("MASCARA__", "REFLETOR__", "LENTE__")) for n in nomes):
        print(cid, ": já separado (rode no modelo original)")
        return
    novo_mat = {}

    def mat_para(orig, nome):
        if nome not in novo_mat:
            m = copy.deepcopy(mats[orig])
            m["name"] = nome
            m.pop("alphaMode", None)
            mats.append(m)
            novo_mat[nome] = len(mats) - 1
        return novo_mat[nome]

    contagem = {}
    malhas_feitas = set()
    for p in g.primitivas():
        if (p["malha"], p["k"]) in malhas_feitas or p["mat"] is None:
            continue
        nome = nomes[p["mat"]]
        regras = [r for r in REGRAS[cid] if r[0] == nome]
        if not regras:
            continue
        T = p["idx"].reshape(-1, 3)
        C = p["pw"][T].mean(1)
        livre = np.ones(len(T), bool)
        novas = []
        for _, cx, alvo in regras:
            m = livre & dentro(C, cx)
            if not m.any():
                continue
            livre &= ~m
            contagem[(nome, alvo)] = contagem.get((nome, alvo), 0) + int(m.sum())
            if alvo is not None:
                np_ = copy.deepcopy(p["prim"])
                np_["indices"] = indices(g, T[m])
                np_["material"] = mat_para(p["mat"], alvo)
                novas.append(np_)
        if not novas and livre.all():
            continue
        prims = g.j["meshes"][p["malha"]]["primitives"]
        if livre.any():
            p["prim"]["indices"] = indices(g, T[livre])
        else:
            prims.remove(p["prim"])
        prims.extend(novas)
        malhas_feitas.add((p["malha"], p["k"]))   # (malha usada por vários nós: as posições do primeiro nó decidem)
    g.salvar(arq)
    for (a, b), n in sorted(contagem.items(), key=str):
        print("  %-34s -> %-20s %5d triângulos" % (a, b or "(apagado)", n))


def main():
    for cid in sys.argv[1:]:
        if cid not in REGRAS:
            print(cid, ": sem regras em REGRAS")
            continue
        print(cid)
        processar(cid)


if __name__ == "__main__":
    main()
