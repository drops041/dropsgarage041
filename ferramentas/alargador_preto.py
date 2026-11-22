"""Alargador de para-lama (ex.: G5 Cross) sem a lataria atravessando: em alguns pontos a lataria do
para-lama passa por cima do plástico preto do alargador e aparece "rasgando" ele (faixas brancas).
Olhando o carro de lado, todo triângulo pintado que fica DENTRO do contorno do alargador e perto dele
(até --fundo m pra dentro/fora) vira plástico preto também. Só mexe perto das rodas.
Uso: python3 ferramentas/alargador_preto.py id --plastico Color_008 [--fundo 0.08] [--fresta 0.04] [--salvar]"""
import json
import os
import sys

import numpy as np
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB  # noqa: E402

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CEL = 0.01   # grade de 1 cm (z, y) vista de lado


def rasterizar(T, grade, z0, y0, nz, ny):
    """marca na grade (vista de lado) o x mais pra fora de cada triângulo do plástico"""
    for t in T:
        zs, ys = t[:, 2], t[:, 1]
        i0, i1 = int((zs.min() - z0) / CEL), int((zs.max() - z0) / CEL) + 1
        j0, j1 = int((ys.min() - y0) / CEL), int((ys.max() - y0) / CEL) + 1
        i0, j0 = max(i0, 0), max(j0, 0)
        i1, j1 = min(i1, nz - 1), min(j1, ny - 1)
        if i1 < i0 or j1 < j0:
            continue
        a, b, c = t[0], t[1], t[2]
        zz, yy = np.meshgrid(z0 + (np.arange(i0, i1 + 1) + 0.5) * CEL, y0 + (np.arange(j0, j1 + 1) + 0.5) * CEL, indexing="ij")
        d = (b[2] - a[2]) * (c[1] - a[1]) - (c[2] - a[2]) * (b[1] - a[1])
        if abs(d) < 1e-10:
            continue
        u = ((zz - a[2]) * (c[1] - a[1]) - (c[2] - a[2]) * (yy - a[1])) / d
        v = ((b[2] - a[2]) * (yy - a[1]) - (zz - a[2]) * (b[1] - a[1])) / d
        den = (u >= -0.05) & (v >= -0.05) & (u + v <= 1.05)
        x = np.abs(a[0] + u * (b[0] - a[0]) + v * (c[0] - a[0]))
        sub = grade[i0:i1 + 1, j0:j1 + 1]
        grade[i0:i1 + 1, j0:j1 + 1] = np.where(den, np.maximum(sub, x), sub)


def main():
    a = sys.argv[1:]
    cid = a[0]
    plast = a[a.index("--plastico") + 1]
    fundo = float(a[a.index("--fundo") + 1]) if "--fundo" in a else 0.08
    fresta = float(a[a.index("--fresta") + 1]) if "--fresta" in a else 0.0
    c = [x for x in json.load(open(os.path.join(RAIZ, "carros.json"), encoding="utf8")) if x["id"] == cid][0]
    W, wy, eixos = float(c["W"]), float(c["wy"]), (float(c["axF"]), float(c["axR"]))
    arq = os.path.join(RAIZ, "modelos", "carros", cid + ".glb")
    g = GLB(arq)
    j = g.j
    mi = [i for i, m in enumerate(j["materials"]) if m.get("name") == plast][0]
    prims, vistos = [], set()
    for p in g.primitivas():
        if id(p["prim"]) in vistos or "indices" not in p["prim"] or p["prim"].get("material") is None:
            continue
        vistos.add(id(p["prim"]))
        prims.append(p)
    z0, y0 = -3.5, -0.2
    nz, ny = int(7.0 / CEL), int(2.0 / CEL)

    def perto_roda(C):
        s = np.zeros(len(C), bool)
        for ax in eixos:
            s |= (np.abs(C[:, 2] - ax) < 2.2 * wy) & (C[:, 1] < 2.6 * wy) & (np.abs(C[:, 0]) > W / 2 - 0.3)
        return s

    grades = {}
    for lado in (1, -1):
        gr = np.full((nz, ny), -1.0)
        for p in prims:
            if p["prim"]["material"] != mi:
                continue
            T = p["pw"][p["idx"].reshape(-1, 3)]
            C = T.mean(1)
            n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
            n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-12
            s = perto_roda(C) & (np.sign(C[:, 0]) == lado) & (n[:, 0] * lado > 0.15)   # face de fora do alargador
            rasterizar(T[s], gr, z0, y0, nz, ny)
        # fecha as frestas entre os pedaços do alargador (até --fresta m): o de verdade é uma peça só
        if fresta > 0:
            r = max(1, int(round(fresta / CEL)))
            el = np.ones((2 * r + 1, 2 * r + 1), bool)
            cheio = ndimage.binary_closing(gr >= 0, structure=el, iterations=1)
            gr = np.where(gr >= 0, gr, np.where(cheio, ndimage.grey_dilation(gr, footprint=el), -1.0))
        grades[lado] = gr
    # raio de dentro do alargador em cada ângulo em volta de cada roda (0 = sem alargador ali)
    PASSO = 4.0
    raio_dentro = {}
    for ax in eixos:
        for lado in (1, -1):
            rin = np.zeros(int(360 / PASSO))
            for p in prims:
                if p["prim"]["material"] != mi:
                    continue
                V = p["pw"][p["idx"].reshape(-1, 3)].reshape(-1, 3)
                V = V[(np.sign(V[:, 0]) == lado) & (np.abs(V[:, 0]) > W / 2 - 0.3)]
                r = np.hypot(V[:, 1] - wy, V[:, 2] - ax)
                V, r = V[r < 2.0 * wy], r[r < 2.0 * wy]
                ang = np.degrees(np.arctan2(V[:, 1] - wy, V[:, 2] - ax))
                b = np.clip(((ang + 180) / PASSO).astype(int), 0, len(rin) - 1)
                for k in range(len(rin)):
                    rr = r[b == k]
                    if len(rr) and rr.min() > wy * 0.9:
                        rin[k] = rr.min() if rin[k] == 0 else min(rin[k], rr.min())
            raio_dentro[(ax, lado)] = rin
    total = 0
    for p in prims:
        if not j["materials"][p["prim"]["material"]].get("name", "").startswith("PAINT"):
            continue
        idx = p["idx"].reshape(-1, 3)
        T = p["pw"][idx]
        vira = np.zeros(len(idx), bool)
        s = perto_roda(T.mean(1))
        # borda de dentro do para-lama (a dobra que entra pra caixa de roda): fica por dentro do raio do
        # alargador; vira preta também senão aparece um filete branco entre o alargador e o pneu
        C = T.mean(1)
        for (ax, lado), rin in raio_dentro.items():
            ang = np.degrees(np.arctan2(C[:, 1] - wy, C[:, 2] - ax))
            b = np.clip(((ang + 180) / PASSO).astype(int), 0, len(rin) - 1)
            r = np.hypot(C[:, 1] - wy, C[:, 2] - ax)
            nr = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
            nr /= np.linalg.norm(nr, axis=1, keepdims=True) + 1e-12
            pra_roda = -(nr[:, 1] * (C[:, 1] - wy) + nr[:, 2] * (C[:, 2] - ax)) / (r + 1e-9)   # face virada pro pneu
            vira |= (s & (np.sign(C[:, 0]) == lado) & (rin[b] > 0) & (rin[b] < 1.6 * wy) & (r < rin[b] + 0.012)
                     & (r > rin[b] - 0.08) & (np.abs(C[:, 2] - ax) < 1.6 * wy) & (np.abs(pra_roda) > 0.6))
        for k in np.nonzero(s)[0]:
            lado = 1 if T[k, :, 0].mean() > 0 else -1
            gr = grades[lado]
            ok = True
            for q in (T[k].mean(0), T[k, 0], T[k, 1], T[k, 2]):   # centro e cantos dentro do contorno do alargador
                i, jj = int((q[2] - z0) / CEL), int((q[1] - y0) / CEL)
                xf = gr[i, jj] if 0 <= i < nz and 0 <= jj < ny else -1.0
                if xf < 0 or abs(abs(q[0]) - xf) > fundo:
                    ok = False
                    break
            vira[k] = vira[k] or ok
        n = int(vira.sum())
        if not n:
            continue
        total += n
        print("  %s: %d triângulos pintados viram %s" % (p["nome"][-40:], n, plast))
        if "--salvar" not in a:
            continue
        malha = j["meshes"][j["nodes"][p["no"]]["mesh"]]
        for alvo, dados in ((p["prim"], idx[~vira]), (None, idx[vira])):
            dados = dados.astype(np.uint32).ravel()
            if len(dados) == 0:
                dados = np.zeros(3, np.uint32)
            vi = g.add_view(dados.tobytes(), 34963)
            j["accessors"].append({"bufferView": vi, "componentType": 5125, "count": int(len(dados)), "type": "SCALAR"})
            if alvo is None:
                alvo = {"attributes": dict(p["prim"]["attributes"]), "material": mi}
                malha["primitives"].append(alvo)
            alvo["indices"] = len(j["accessors"]) - 1
    print("%s: %d no total" % (cid, total))
    if "--salvar" in a and total:
        g.salvar(arq)


main()
