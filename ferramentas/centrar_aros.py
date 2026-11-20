"""CENTRAR AROS — tira o "bambo" das rodas: alguns aros vieram levemente tortos (a face não fica em pé
no eixo) ou fora de centro (extraídos de carros com cambagem/convergência no modelo original). Girando,
isso aparece como roda empenada. Aqui mede a borda de fora em 36 setores e corrige:
  - inclinação: x' = x - b*y - c*z (a face volta a ficar perpendicular ao eixo X)
  - excentricidade: y' = y - d, z' = z - e (o anel volta pro centro do eixo)
Uso: python3 ferramentas/centrar_aros.py [id ...]   (sem id = todos)
"""
import glob
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB  # noqa: E402

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def medir(P):
    r = np.hypot(P[:, 1], P[:, 2])
    th = np.arctan2(P[:, 2], P[:, 1])
    s = r > 0.9
    xs, ts, rs = [], [], []
    for k in range(36):
        a = -np.pi + k * np.pi / 18
        m = s & (th >= a) & (th < a + np.pi / 18)
        if m.sum() > 0:
            xs.append(P[m, 0].max())
            ts.append(a + np.pi / 36)
            rs.append(r[m].max())
    if len(xs) < 24:
        return None
    xs, ts, rs = map(np.array, (xs, ts, rs))
    A = np.c_[np.ones_like(ts), np.cos(ts), np.sin(ts)]
    cx = np.linalg.lstsq(A, xs, rcond=None)[0]
    cr = np.linalg.lstsq(A, rs, rcond=None)[0]
    return cx[1], cx[2], cr[1], cr[2], cr[0]


def corrigir(arq):
    g = GLB(arq)
    prims = list(g.primitivas())
    P = np.vstack([p["pw"] for p in prims])
    m = medir(P)
    if m is None:
        return None
    b, c, d, e, r0 = m
    if np.hypot(b, c) < 0.004 and np.hypot(d, e) < 0.003:
        return False
    for p in prims:
        at = p["prim"]["attributes"]
        W = p["W"]
        pw = p["pw"].copy()
        pw[:, 1] -= d
        pw[:, 2] -= e
        pw[:, 0] -= b * pw[:, 1] / r0 + c * pw[:, 2] / r0
        loc = (np.c_[pw, np.ones(len(pw))] @ np.linalg.inv(W).T)[:, :3]
        at["POSITION"] = g.add_accessor_vec3(loc.astype(np.float32))
        if "NORMAL" in at:
            n = g.accessor(at["NORMAL"]).astype(np.float64)
            if n.max() > 2:     # normal quantizada (int8/int16 normalizada)
                n = n / np.abs(n).max()
            R = W[:3, :3]
            nw = n @ np.linalg.inv(R)
            nw2 = np.stack([nw[:, 0], nw[:, 1] + b / r0 * nw[:, 0], nw[:, 2] + c / r0 * nw[:, 0]], 1)
            nl = nw2 @ R
            nl /= np.maximum(np.linalg.norm(nl, axis=1, keepdims=True), 1e-9)
            at["NORMAL"] = g.add_accessor_vec3(nl.astype(np.float32))
    g.salvar(arq)
    return (b, c, d, e)


def main():
    ids = sys.argv[1:]
    arqs = [os.path.join(RAIZ, "modelos", "rodas", i + ".glb") for i in ids] if ids else sorted(glob.glob(os.path.join(RAIZ, "modelos", "rodas", "*.glb")))
    for a in arqs:
        r = corrigir(a)
        nome = os.path.basename(a)
        if r is None:
            print(nome, ": não deu pra medir")
        elif r is False:
            print(nome, ": ok (já reto)")
        else:
            print(nome, ": corrigido inclinação %.3f excentricidade %.3f" % (np.hypot(r[0], r[1]), np.hypot(r[2], r[3])))


if __name__ == "__main__":
    main()
