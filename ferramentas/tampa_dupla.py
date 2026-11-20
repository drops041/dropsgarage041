#!/usr/bin/env python3
"""TAMPA DUPLA — capô e porta-malas/tampa: a chapa pintada ganha o avesso (triângulo copiado ao contrário).
Muitos modelos só têm a chapa de fora: com o capô aberto, olhando de baixo, ele some (só a borda aparece).
uso: tampa_dupla.py [id ...]   (sem id = todos os carros com capô/tampa que abrem)"""
import json, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def processar(cid):
    arq = os.path.join(RAIZ, "modelos", "carros", cid + ".glb")
    g = GLB(arq)
    mats = [m.get("name", "") for m in g.j.get("materials", [])]
    feitos = set()
    n = 0
    for p in g.primitivas():
        if not any(("/" + k + "__") in p["nome"] for k in ("PCA", "PTR")):
            continue
        pp = p["prim"]
        if pp.get("material") is None or not mats[pp["material"]].startswith("PAINT") or id(pp) in feitos:
            continue
        if pp.get("extras", {}).get("dupla"):
            continue
        feitos.add(id(pp))
        at = pp["attributes"]
        P = g.accessor(at["POSITION"])
        N = g.accessor(at["NORMAL"]) if "NORMAL" in at else None
        T = g.accessor(pp["indices"]).reshape(-1, 3).astype(np.int64)
        nv = len(P)
        at["POSITION"] = g.add_accessor_vec3(np.concatenate([P, P]).astype(np.float32))
        if N is not None:
            at["NORMAL"] = g.add_accessor_vec3(np.concatenate([N, -N]).astype(np.float32))
        for nome in list(at.keys()):
            if nome in ("POSITION", "NORMAL"):
                continue
            a = g.j["accessors"][at[nome]]
            arr = g.accessor(at[nome])
            dt = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}[a["componentType"]]
            if a.get("normalized"):
                arr = np.round(arr * np.iinfo(dt).max)
            arr = np.ascontiguousarray(np.concatenate([arr, arr]).astype(dt))
            if nome == "TANGENT":
                arr[nv:, :3] *= -1
            vi = g.add_view(arr.tobytes(), 34962)
            na = {"bufferView": vi, "componentType": a["componentType"], "count": len(arr), "type": a["type"]}
            if a.get("normalized"):
                na["normalized"] = True
            g.j["accessors"].append(na)
            at[nome] = len(g.j["accessors"]) - 1
        T2 = np.concatenate([T, T[:, ::-1] + nv]).ravel().astype(np.uint32)
        vi = g.add_view(T2.tobytes(), 34963)
        g.j["accessors"].append({"bufferView": vi, "componentType": 5125, "count": len(T2), "type": "SCALAR"})
        pp["indices"] = len(g.j["accessors"]) - 1
        pp.setdefault("extras", {})["dupla"] = True
        n += len(T)
    if n:
        g.salvar(arq)
    return n


if __name__ == "__main__":
    carros = json.load(open(os.path.join(RAIZ, "carros.json"), encoding="utf8"))
    ids = set(sys.argv[1:])
    for c in carros:
        p = c.get("partes") or {}
        if (ids and c["id"] not in ids) or not ("frente" in p or "tras" in p):
            continue
        if os.path.exists(os.path.join(RAIZ, "modelos", "carros", c["id"] + ".glb")):
            n = processar(c["id"])
            if n:
                print(c["id"], "chapa com avesso:", n, "triângulos")
