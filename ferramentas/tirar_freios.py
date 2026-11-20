"""TIRAR FREIOS — apaga do modelo do carro tudo que fica dentro da roda (disco, pinça, cubo, mola...),
pra não brigar com as rodas do jogo (que mudam de tamanho e de aro).

Uso: python3 ferramentas/tirar_freios.py [--salvar] id1 id2 ...   (sem --salvar só mostra quanto sairia)
Região apagada (coordenadas do carro): |x| > W/2 - 0.42 e distância até o centro da roda (y=wy, z=eixo) < 0.9 * wy,
só triângulos com os 3 cantos dentro.
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB  # noqa: E402

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def main():
    args = sys.argv[1:]
    salvar = "--salvar" in args
    ids = [a for a in args if not a.startswith("--")]
    carros = {c["id"]: c for c in json.load(open(os.path.join(RAIZ, "carros.json"), encoding="utf8"))}
    for cid in ids:
        c = carros[cid]
        arq = os.path.join(RAIZ, "modelos", "carros", cid + ".glb")
        g = GLB(arq)
        j = g.j
        W, wy = float(c["W"]), float(c["wy"])
        eixos = (float(c["axF"]), float(c["axR"]))
        tirados = 0
        total = 0
        feitos = set()
        for p in g.primitivas():
            prim = p["prim"]
            if id(prim) in feitos or "indices" not in prim:
                continue
            feitos.add(id(prim))
            P = p["pw"]
            idx = p["idx"].reshape(-1, 3)
            total += len(idx)
            dentro = np.zeros(len(P), bool)
            for ax in eixos:
                r = np.hypot(P[:, 1] - wy, P[:, 2] - ax)
                dentro |= (np.abs(P[:, 0]) > W / 2 - 0.42) & (r < 0.9 * wy)
            sai = dentro[idx].all(1)
            n = int(sai.sum())
            if n == 0:
                continue
            tirados += n
            if salvar:
                novo = idx[~sai].astype(np.uint32).ravel()
                if len(novo) == 0:
                    novo = np.zeros(3, np.uint32)
                vi = g.add_view(novo.tobytes(), 34963)
                j["accessors"].append({"bufferView": vi, "componentType": 5125, "count": int(len(novo)), "type": "SCALAR"})
                prim["indices"] = len(j["accessors"]) - 1
        if salvar and tirados:
            g.salvar(arq)
        print("%s: %d de %d triângulos dentro das rodas%s" % (cid, tirados, total, " (apagados)" if salvar and tirados else ""))


if __name__ == "__main__":
    main()
