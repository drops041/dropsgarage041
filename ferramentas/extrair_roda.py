"""EXTRAIR RODA — tira o aro original de um carro .glb e grava no formato das rodas do jogo
(modelos/rodas/<id>.glb): eixo em X, face de fora pra +X, largura 1 (-0.5..0.5), raio 1 na borda,
materiais RIM (raios), LIP (borda), BARREL (tambor de dentro) e BOLT (miolo/parafusos).

Uso: python3 ferramentas/extrair_roda.py CARRO.glb --id jerez --nome "Golf Jerez 19"
     [--material NOME] (só os triângulos desse material)  [--sem MAT1,MAT2] (ignora esses materiais)
"""
import argparse
import json
import os
import re
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB  # noqa: E402

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FORA = re.compile(r"tire|tyre|pneu|rubber|brake|caliper|rotor|disc|steer|wheelhouse|logo_?text|valve")


def coletar(a):
    g = GLB(a.modelo)
    mats = g.j.get("materials", [])
    sem = set((a.sem or "").split(",")) - {""}
    tris = []   # (p0,p1,p2), (n0,n1,n2)
    for p in g.primitivas():
        caminho = p["nome"].lower()
        mn = mats[p["mat"]].get("name", "") if p["mat"] is not None else ""
        if a.material:
            if mn != a.material:
                continue
        else:
            eh = re.search(r"(?<![tp])rim(?!ary)|wheel|roda|llanta|felge", caminho) or re.search(r"(?<![tp])rim(?!ary)|wheel", mn.lower())
            if not eh or FORA.search(caminho) or FORA.search(mn.lower()) or mn in sem:
                continue
            if re.search(r"tire|tyre", caminho):
                continue
        at = p["prim"]["attributes"]
        if "NORMAL" not in at:
            continue
        n = g.accessor(at["NORMAL"])
        R = p["W"][:3, :3]
        Rn = np.linalg.inv(R).T
        nw = n @ Rn.T
        nw /= np.maximum(np.linalg.norm(nw, axis=1, keepdims=True), 1e-9)
        idx = p["idx"].reshape(-1, 3)
        tris.append((p["pw"][idx], nw[idx]))
    if not tris:
        raise SystemExit("não achei peças de roda (use --material)")
    P = np.concatenate([t[0] for t in tris])
    N = np.concatenate([t[1] for t in tris])
    return P, N


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("modelo")
    ap.add_argument("--id", required=True)
    ap.add_argument("--nome", required=True)
    ap.add_argument("--material")
    ap.add_argument("--sem")
    a = ap.parse_args()
    P, N = coletar(a)
    cen = P.mean(1)                     # centro de cada triângulo
    c0 = (cen.min(0) + cen.max(0)) / 2
    ext = cen.max(0) - cen.min(0)
    # separa as rodas: grade de células ligadas (cada roda = um pedaço contínuo); estepe fica separado
    ordem = np.argsort(ext)
    vert = ordem[0]
    cel = max(ext.max() / 24.0, 1e-6)
    chaves = np.floor(cen / cel).astype(np.int64)
    mapa = {}
    for k, ch in enumerate(map(tuple, chaves)):
        mapa.setdefault(ch, []).append(k)
    comp = {}
    grupos = []
    for ch in mapa:
        if ch in comp:
            continue
        gid = len(grupos)
        fila = [ch]
        comp[ch] = gid
        membros = []
        while fila:
            c_ = fila.pop()
            membros.extend(mapa[c_])
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for dz in (-1, 0, 1):
                        v = (c_[0] + dx, c_[1] + dy, c_[2] + dz)
                        if v in mapa and v not in comp:
                            comp[v] = gid
                            fila.append(v)
        grupos.append(np.array(membros))
    chao = cen[:, vert].min()
    no_chao = [m for m in grupos if cen[m, vert].min() < chao + 0.15 * ext[vert] + cel]
    melhor = max(no_chao or grupos, key=len)
    sel = np.zeros(len(cen), bool)
    sel[melhor] = True
    print("  pedaços: %d (no chão %d), usando %d de %d triângulos" % (len(grupos), len(no_chao), sel.sum(), len(sel)))
    T, TN = P[sel], N[sel]
    pts = T.reshape(-1, 3)
    lo, hi = pts.min(0), pts.max(0)
    tam = hi - lo
    eixo = int(np.argmin(tam))
    c = (lo + hi) / 2
    outros = [i for i in range(3) if i != eixo]
    # face de fora: lado do carro onde está a roda (em relação ao centro de todas as rodas)
    fora = 1.0 if c[eixo] > c0[eixo] else -1.0
    if len(grupos) == 1:   # uma roda só: a face é o lado onde os raios estão
        r_ = np.hypot(pts[:, outros[0]] - c[outros[0]], pts[:, outros[1]] - c[outros[1]])
        miolo = pts[r_ < 0.6 * r_.max(), eixo]
        fora = 1.0 if miolo.mean() > c[eixo] else -1.0
    R = max(tam[outros[0]], tam[outros[1]]) / 2
    Wd = tam[eixo]

    def conv(v, normal=False):
        x = v[..., eixo] * fora
        y = v[..., outros[0]]
        z = v[..., outros[1]]
        out = np.stack([x, y, z], -1)
        if normal:
            out = out * np.array([1.0 / Wd, 1.0 / R, 1.0 / R])
            return out / np.maximum(np.linalg.norm(out, axis=-1, keepdims=True), 1e-9)
        out = out - np.array([c[eixo] * fora, c[outros[0]], c[outros[1]]])
        return out * np.array([1.0 / Wd, 1.0 / R, 1.0 / R])
    V = conv(T)
    VN = conv(TN, True)
    # troca de mão (o eixo pode ter virado): mantém a frente dos triângulos
    perm = np.zeros((3, 3))
    perm[0, eixo] = fora
    perm[1, outros[0]] = 1
    perm[2, outros[1]] = 1
    if np.linalg.det(perm) < 0:
        V = V[:, ::-1]
        VN = VN[:, ::-1]
    # classes
    cen2 = V.mean(1)
    r = np.hypot(cen2[:, 1], cen2[:, 2])
    x = cen2[:, 0]
    nr = np.abs(VN.mean(1)[:, 0])
    cls = np.full(len(V), "RIM", object)
    cls[(r > 0.84) & (x <= 0.12)] = "BARREL"
    cls[(r > 0.84) & (x > 0.12)] = "LIP"
    cls[(r < 0.16) & (x > 0.0)] = "BOLT"
    # grava o glb
    blobs = []
    acc = []
    views = []
    prims = []
    nomes = ["RIM", "LIP", "BARREL", "BOLT"]
    off = 0

    def add(arr, comp, tipo_alvo, mm=False):
        nonlocal off
        b = arr.astype(np.float32 if comp != "SCALAR" else np.uint32).tobytes()
        pad = (-len(b)) % 4
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(b), "target": tipo_alvo})
        blobs.append(b + b"\0" * pad)
        off += len(b) + pad
        d = {"bufferView": len(views) - 1, "componentType": 5126 if comp != "SCALAR" else 5125,
             "count": int(len(arr)), "type": comp}
        if mm:
            d["min"] = arr.min(0).tolist()
            d["max"] = arr.max(0).tolist()
        acc.append(d)
        return len(acc) - 1
    for mi, nm in enumerate(nomes):
        s = cls == nm
        if not s.any():
            continue
        v = V[s].reshape(-1, 3)
        n = VN[s].reshape(-1, 3)
        ia = add(v, "VEC3", 34962, True)
        na = add(n, "VEC3", 34962)
        ii = add(np.arange(len(v), dtype=np.uint32), "SCALAR", 34963)
        prims.append({"attributes": {"POSITION": ia, "NORMAL": na}, "indices": ii, "material": mi})
    j = {"asset": {"version": "2.0", "generator": "Drops Garage extrair_roda.py"},
         "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": a.id, "mesh": 0}],
         "meshes": [{"name": a.id, "primitives": prims}],
         "materials": [{"name": nm, "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.8, 0.82, 1], "metallicFactor": 1.0, "roughnessFactor": 0.3}} for nm in nomes],
         "accessors": acc, "bufferViews": views, "buffers": [{"byteLength": off}]}
    js = json.dumps(j).encode()
    js += b" " * ((-len(js)) % 4)
    binb = b"".join(blobs)
    destino = os.path.join(RAIZ, "modelos", "rodas", a.id + ".glb")
    with open(destino, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binb)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(binb), 0x004E4942) + binb)
    print("%s: %d triângulos (%s) raio orig %.3f m largura %.3f m -> %s" % (
        a.id, len(V), ", ".join("%s=%d" % (k, (cls == k).sum()) for k in nomes), R, Wd, os.path.relpath(destino, RAIZ)))


if __name__ == "__main__":
    main()
