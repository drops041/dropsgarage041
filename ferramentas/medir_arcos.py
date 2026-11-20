"""Mede o arco do para-lama de cada carro (topo do arco e borda) e grava em carros.json -> "arcos".
O jogo usa isso pra não deixar o pneu atravessar a lataria quando o carro está muito baixo."""
import json, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB
RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
cj = os.path.join(RAIZ, "carros.json")
carros = json.load(open(cj, encoding="utf8"))
for c in carros:
    arq = os.path.join(RAIZ, "modelos", "carros", c["id"] + ".glb")
    if not os.path.exists(arq):
        continue
    g = GLB(arq)
    mats = g.j.get("materials", [])
    ps = [p for p in g.primitivas() if not (p["mat"] is not None and mats[p["mat"]].get("name", "").split("__")[0] in ("PNEU", "ARO"))]
    P = np.concatenate([p["pw"] for p in ps])
    W, wy = float(c["W"]), float(c["wy"])
    res = {}
    for k, ax in (("f", float(c["axF"])), ("t", float(c["axR"]))):
        q = P[(np.abs(P[:, 2] - ax) < 0.06) & (np.abs(P[:, 0]) > W / 2 - 0.12) & (P[:, 1] > wy + max(0.05, 0.6 * float(c["ra"])))]
        if len(q) == 0:
            res[k] = None
            continue
        ay = float(q[:, 1].min())
        borda = q[q[:, 1] < ay + 0.03]
        res[k] = [round(ay, 3), round(float(np.abs(borda[:, 0]).max()), 3)]
    c["arcos"] = res
    print(c["id"], res)
json.dump(carros, open(cj, "w", encoding="utf8"), ensure_ascii=False, indent=1)
