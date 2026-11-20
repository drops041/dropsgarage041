#!/usr/bin/env python3
"""VIDROS NAS PORTAS — prende na porta o vidro lateral que fica dentro dela.
Em muitos modelos o vidro da janela é uma peça separada da porta (às vezes todos os vidros numa malha só):
aí a porta abre/sai e o vidro fica no ar. Aqui cada triângulo de vidro que está dentro do contorno de uma porta
(e virado pro lado, como janela lateral) vai pra um nó novo "<PORTA>__vidro", que o jogo pendura junto com a porta.

uso: vidros_portas.py id [id ...]   (sem id = todos os carros com portas)
"""
import copy
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB  # noqa: E402

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def compactar(g, prim, tri):
    """primitiva nova só com os triângulos 'tri' (índices de vértice originais) e só os vértices usados"""
    us = np.unique(tri)
    mapa = -np.ones(int(tri.max()) + 1, np.int64)
    mapa[us] = np.arange(len(us))
    novo = copy.deepcopy(prim)
    for nome, ai in list(prim["attributes"].items()):
        a = g.j["accessors"][ai]
        arr = g.accessor(ai)[us]
        dt = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8, 5122: np.int16, 5120: np.int8}[a["componentType"]]
        if a.get("normalized"):
            arr = np.round(arr * np.iinfo(dt).max)
        arr = np.ascontiguousarray(arr.astype(dt))
        vi = g.add_view(arr.tobytes(), 34962)
        na = {"bufferView": vi, "componentType": a["componentType"], "count": len(arr), "type": a["type"]}
        if a.get("normalized"):
            na["normalized"] = True
        if nome == "POSITION":
            na["min"] = arr.min(0).tolist()
            na["max"] = arr.max(0).tolist()
        g.j["accessors"].append(na)
        novo["attributes"][nome] = len(g.j["accessors"]) - 1
    ind = mapa[tri.ravel()].astype(np.uint32)
    vi = g.add_view(ind.tobytes(), 34963)
    g.j["accessors"].append({"bufferView": vi, "componentType": 5125, "count": len(ind), "type": "SCALAR"})
    novo["indices"] = len(g.j["accessors"]) - 1
    return novo


def processar(c):
    portas = [e[0] for e in c.get("partes", {}).get("portas", {}).get("p", [])]
    if not portas:
        return 0
    arq = os.path.join(RAIZ, "modelos", "carros", c["id"] + ".glb")
    g = GLB(arq)
    mats = g.j.get("materials", [])
    pr = g.primitivas()
    # contorno de cada porta (todas as malhas com o prefixo dela)
    caixas = {}
    for p in pr:
        for id in portas:
            if id + "__" in p["nome"]:
                q = p["pw"]
                lo, hi = q.min(0), q.max(0)
                if id in caixas:
                    caixas[id] = (np.minimum(caixas[id][0], lo), np.maximum(caixas[id][1], hi))
                else:
                    caixas[id] = (lo, hi)
    novos = {id: [] for id in caixas}
    total = 0
    for p in pr:
        nm = mats[p["mat"]].get("name", "") if p["mat"] is not None else ""
        if not nm.startswith("GLASS") or any(id + "__" in p["nome"] for id in portas):
            continue
        T = p["idx"].reshape(-1, 3)
        V = p["pw"][T]
        C = V.mean(1)
        fn = np.cross(V[:, 1] - V[:, 0], V[:, 2] - V[:, 0])
        lateral = np.abs(fn[:, 0]) > 0.55 * np.maximum(np.linalg.norm(fn, axis=1), 1e-12)
        pega = np.zeros(len(T), bool)
        dono = np.full(len(T), "", object)
        for id, (lo, hi) in caixas.items():
            lado = np.sign((lo[0] + hi[0]) / 2)
            m = lateral & (np.sign(C[:, 0]) == lado) & (np.abs(C[:, 0]) > 0.35) \
                & (C[:, 2] > lo[2] - 0.03) & (C[:, 2] < hi[2] + 0.03) \
                & (C[:, 1] > lo[1] + 0.25 * (hi[1] - lo[1])) & (C[:, 1] < hi[1] + 0.05) \
                & (np.abs(C[:, 0]) > min(abs(lo[0]), abs(hi[0])) - 0.12)
            m &= ~pega
            pega |= m
            dono[m] = id
        if not pega.any():
            continue
        resto = T[~pega].ravel().astype(np.uint32)
        vi = g.add_view(resto.tobytes(), 34963)
        g.j["accessors"].append({"bufferView": vi, "componentType": 5125, "count": len(resto), "type": "SCALAR"})
        original = copy.deepcopy(p["prim"])
        p["prim"]["indices"] = len(g.j["accessors"]) - 1
        for id in caixas:
            sel = T[pega & (dono == id)]
            if len(sel):
                novos[id].append((compactar(g, original, sel), p["W"]))
                total += len(sel)
    raiz = g.j["scenes"][g.j.get("scene", 0)]["nodes"]
    for id, itens in novos.items():
        for k, (prim, W) in enumerate(itens):
            g.j["meshes"].append({"primitives": [prim]})
            g.j["nodes"].append({"name": "%s__vidro_%d" % (id, k), "mesh": len(g.j["meshes"]) - 1, "matrix": W.T.ravel().tolist()})
            raiz.append(len(g.j["nodes"]) - 1)
    if total:
        g.salvar(arq)
    print(c["id"], {id: sum(len(x[0]["attributes"]) and 1 for x in v) for id, v in novos.items()}, "triângulos de vidro presos nas portas:", total)
    return total


def main():
    carros = json.load(open(os.path.join(RAIZ, "carros.json"), encoding="utf8"))
    ids = set(sys.argv[1:])
    for c in carros:
        if ids and c["id"] not in ids:
            continue
        if not os.path.exists(os.path.join(RAIZ, "modelos", "carros", c["id"] + ".glb")):
            continue
        processar(c)


if __name__ == "__main__":
    main()
