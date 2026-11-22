"""Desfaz a parte de FORA da caixa de roda preta (caixa_de_roda.py às vezes pegava pedaço da lataria
branca em volta do para-lama e deixava ele preto). Triângulos pretos virados pra fora (normal apontando
pro lado de fora do carro ou pra cima) voltam pro material original. Uso: python3 ferramentas/caixa_de_roda_fora.py id1 id2"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB  # noqa: E402

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
NOME_PRETO = "INTERIOR__caixa_roda"


def processar(cid):
    arq = os.path.join(RAIZ, "modelos", "carros", cid + ".glb")
    g = GLB(arq)
    j = g.j
    preto = [i for i, m in enumerate(j["materials"]) if m.get("name") == NOME_PRETO]
    if not preto:
        print(cid, ": sem caixa de roda preta")
        return
    preto = preto[0]
    total = 0
    por_prim = {id(p["prim"]): p for p in g.primitivas()}
    for p in list(por_prim.values()):
        prim = p["prim"]
        if prim.get("material") != preto:
            continue
        malha = j["meshes"][j["nodes"][p["no"]]["mesh"]]
        orig = None
        for q in malha["primitives"]:
            if q is not prim and q["attributes"].get("POSITION") == prim["attributes"].get("POSITION") and q.get("material") != preto:
                orig = q
        if orig is None:
            continue
        idx = p["idx"].reshape(-1, 3)
        T = p["pw"][idx]
        n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
        n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-12
        cx = T[:, :, 0].mean(1)
        fora = (n[:, 0] * np.sign(cx) > 0.35) | (n[:, 1] > 0.6)   # (o material é dos dois lados: vale o sentido do modelo)
        if not fora.any():
            continue
        total += int(fora.sum())
        oi = g.accessor(orig["indices"]).reshape(-1, 3) if "indices" in orig else np.zeros((0, 3), np.uint32)
        novo_o = np.concatenate([oi, idx[fora]]).astype(np.uint32).ravel()
        fica = idx[~fora].astype(np.uint32).ravel()
        if len(fica) == 0:
            fica = np.zeros(3, np.uint32)
        for alvo, dados in ((orig, novo_o), (prim, fica)):
            vi = g.add_view(dados.tobytes(), 34963)
            j["accessors"].append({"bufferView": vi, "componentType": 5125, "count": int(len(dados)), "type": "SCALAR"})
            alvo["indices"] = len(j["accessors"]) - 1
    print("%s: %d triângulos de fora voltaram pra cor original" % (cid, total))
    if total:
        g.salvar(arq)


for a in sys.argv[1:]:
    processar(a)
