#!/usr/bin/env python3
"""AFINAR PERSONAGEM — deixa o protagonista (corpo "Superhero" do kit) menos musculoso, direto no .glb.

O corpo e as roupas (que são cascas em cima do corpo, com os mesmos pesos) encolhem juntos:
  · braço e antebraço: puxa os vértices pro eixo do osso (bíceps/tríceps/antebraço mais finos)
  · ombro (deltoide): um pouco menos
  · peito e costas (spine_02/03 e clavícula): menos largo e menos peitoral
  · pescoço: um pouco mais fino
Mão, cabeça, cabelo e pernas não mudam. Como é só a malha, as animações continuam iguais.

uso: python3 ferramentas/afinar_personagem.py entrada.glb saida.glb [--forca 1.0]
"""
import os
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB  # noqa: E402

# fator (1 = igual): braço, antebraço, ombro, tronco largura (x), tronco profundidade (z), pescoço
F = {"upperarm": 0.80, "lowerarm": 0.86, "ombro": 0.88, "tronco_x": 0.92, "tronco_z": 0.90, "pescoco": 0.9}


def main():
    ent, sai = sys.argv[1], sys.argv[2]
    forca = float(sys.argv[sys.argv.index("--forca") + 1]) if "--forca" in sys.argv else 1.0
    f = {k: 1.0 - (1.0 - v) * forca for k, v in F.items()}
    g = GLB(ent)
    j = g.j
    sk = j["skins"][0]
    juntas = [j["nodes"][k]["name"] for k in sk["joints"]]
    ibm = g.accessor(sk["inverseBindMatrices"]).reshape(-1, 4, 4)
    pos = {n: np.linalg.inv(ibm[k].T)[:3, 3] for k, n in enumerate(juntas)}
    J = {n: k for k, n in enumerate(juntas)}
    segs = {}
    for lado in ("_l", "_r"):
        segs["upperarm" + lado] = (pos["upperarm" + lado], pos["lowerarm" + lado], f["upperarm"])
        segs["lowerarm" + lado] = (pos["lowerarm" + lado], pos["hand" + lado], f["lowerarm"])
        segs["clavicle" + lado] = (pos["clavicle" + lado], pos["upperarm" + lado], f["ombro"])
    segs["neck_01"] = (pos["neck_01"], pos["Head"], f["pescoco"])
    tronco = {"spine_02": 0.7, "spine_03": 1.0}
    feitos = set()
    total = 0
    for mi, m in enumerate(j["meshes"]):
        for p in m["primitives"]:
            at = p["attributes"]
            if "JOINTS_0" not in at or at["POSITION"] in feitos:
                continue
            feitos.add(at["POSITION"])
            P = g.accessor(at["POSITION"]).astype(np.float64).reshape(-1, 3)
            JJ = g.accessor(at["JOINTS_0"]).astype(np.int64).reshape(-1, 4)
            WW = g.accessor(at["WEIGHTS_0"]).astype(np.float64).reshape(-1, 4)
            if WW.max() > 1.5:   # pesos normalizados em inteiro
                WW = WW / (255.0 if WW.max() <= 255 else 65535.0)
            novo = P.copy()
            desl = np.zeros_like(P)
            for nome, (a, b, fator) in segs.items():
                w = (WW * (JJ == J[nome])).sum(1)
                if nome == "neck_01":   # rosto e queixo não: só o pescoço de verdade
                    w = w * np.clip(1.0 - 3.0 * (WW * (JJ == J["Head"])).sum(1), 0.0, 1.0)
                sel = w > 0.001
                if not sel.any():
                    continue
                ab = b - a
                u = np.clip(((P[sel] - a) @ ab) / (ab @ ab), 0.0, 1.0)
                q = a + u[:, None] * ab
                desl[sel] += w[sel, None] * ((q + (P[sel] - q) * fator) - P[sel])
            for nome, peso in tronco.items():
                w = (WW * (JJ == J[nome])).sum(1) * peso
                sel = w > 0.001
                if not sel.any():
                    continue
                c = pos[nome]
                alvo = P[sel].copy()
                alvo[:, 0] = c[0] + (P[sel, 0] - c[0]) * f["tronco_x"]
                alvo[:, 2] = c[2] + (P[sel, 2] - c[2]) * f["tronco_z"]
                desl[sel] += w[sel, None] * (alvo - P[sel])
            novo += desl
            mexidos = int((np.linalg.norm(desl, axis=1) > 1e-5).sum())
            total += mexidos
            print("  %-16s %5d vértices mexidos de %d" % (m.get("name", mi), mexidos, len(P)))
            a_info = j["accessors"][at["POSITION"]]
            n_ai = g.add_accessor_vec3(novo.astype(np.float32))
            # troca em todas as primitivas que usavam esse POSITION
            for m2 in j["meshes"]:
                for p2 in m2["primitives"]:
                    if p2["attributes"].get("POSITION") == at["POSITION"] and p2 is not p:
                        p2["attributes"]["POSITION"] = n_ai
            at["POSITION"] = n_ai
            del a_info
    g.salvar(sai)
    print("ok:", total, "vértices afinados ->", sai)


if __name__ == "__main__":
    main()
