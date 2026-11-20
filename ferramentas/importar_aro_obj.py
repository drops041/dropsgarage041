"""IMPORTAR ARO DE .OBJ — grava no formato das rodas do jogo (modelos/rodas/<id>.glb):
eixo X, face de fora pra +X, largura 1 (-0.5..0.5), raio 1 na borda; materiais RIM, LIP, BARREL, BOLT.

- Peças "torneadas" (tambor/borda) podem ser refeitas como sólido de revolução a partir do corte da
  malha original (--torno): fica liso e leve em vez de 100 mil triângulos.
- Peças muito pesadas (raios trançados) passam por redução por agrupamento de vértices (--reduzir).

Uso (exemplos no fim do arquivo: python3 ferramentas/importar_aro_obj.py bbs | antera)
"""
import json
import os
import struct
import sys

import numpy as np

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
UP = "/mnt/user-data/uploads/"


def ler(caminho, grupos):
    """grupos: {(grupo_ou_None, material_ou_None): classe}. Devolve {classe: tris (n,3,3)}"""
    V = []
    out = {}
    g = m = None
    with open(caminho, errors="ignore") as f:
        for ln in f:
            if ln.startswith("v "):
                V.append([float(x) for x in ln.split()[1:4]])
            elif ln.startswith("g ") or ln.startswith("o "):
                g = ln.split(None, 1)[1].strip()
            elif ln.startswith("usemtl"):
                m = ln.split(None, 1)[1].strip()
            elif ln.startswith("f "):
                cls = grupos.get((g, m)) or grupos.get((g, None)) or grupos.get((None, m))
                if not cls:
                    continue
                ids = [int(t.split("/")[0]) for t in ln.split()[1:]]
                ids = [i - 1 if i > 0 else len(V) + i for i in ids]
                lst = out.setdefault(cls, [])
                for k in range(1, len(ids) - 1):
                    lst.append((ids[0], ids[k], ids[k + 1]))
    V = np.array(V)
    return {k: V[np.array(v)] for k, v in out.items()}


def normalizar(tris, eixo, face, centro, R, W):
    """leva pro padrão: X = eixo (face de fora +X), raio R -> 1, largura W -> 1"""
    outros = [i for i in range(3) if i != eixo]
    res = {}
    for k, T in tris.items():
        x = (T[..., eixo] - centro[eixo]) * face / W
        y = (T[..., outros[0]] - centro[outros[0]]) / R
        z = (T[..., outros[1]] - centro[outros[1]]) / R
        P = np.stack([x, y, z], -1)
        perm = np.zeros((3, 3))
        perm[0, eixo] = face
        perm[1, outros[0]] = 1
        perm[2, outros[1]] = 1
        if np.linalg.det(perm) < 0:
            P = P[:, ::-1]
        res[k] = P
    return res


def normais_suaves(T, angulo=40.0):
    """normais suaves por vértice (soldando por posição), respeitando quinas acima de 'angulo'"""
    P = T.reshape(-1, 3)
    fn = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    chave = np.round(P / 1e-4).astype(np.int64)
    _, inv = np.unique(chave, axis=0, return_inverse=True)
    inv = inv.ravel()
    acc = np.zeros((inv.max() + 1, 3))
    np.add.at(acc, inv, np.repeat(fn, 3, axis=0))
    vn = acc[inv]
    vn /= np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-12)
    fr = np.repeat(fn, 3, axis=0)
    quina = (vn * fr).sum(1) < np.cos(np.radians(angulo))
    vn[quina] = fr[quina]
    return vn.reshape(-1, 3, 3)


def reduzir(T, cel):
    """agrupamento de vértices numa grade: junta vértices da mesma célula (média), descarta triângulos que somem"""
    P = T.reshape(-1, 3)
    ch = np.floor(P / cel).astype(np.int64)
    _, inv = np.unique(ch, axis=0, return_inverse=True)
    inv = inv.ravel()
    soma = np.zeros((inv.max() + 1, 3))
    np.add.at(soma, inv, P)
    cnt = np.bincount(inv)
    novos = soma / cnt[:, None]
    F = inv.reshape(-1, 3)
    ok = (F[:, 0] != F[:, 1]) & (F[:, 1] != F[:, 2]) & (F[:, 0] != F[:, 2])
    F = F[ok]
    # tira triângulos repetidos
    Fs = np.sort(F, axis=1)
    _, u = np.unique(Fs, axis=0, return_index=True)
    F = F[np.sort(u)]
    return novos[F]


def torno(T, segs=60):
    """refaz a peça como sólido de revolução em torno de X: corta no plano z=0 (y>0), encadeia o perfil e gira"""
    a, b, c = T[:, 0], T[:, 1], T[:, 2]
    segs_l = []
    for p, q, r in zip(a, b, c):
        pts = []
        for u, v in ((p, q), (q, r), (r, p)):
            if (u[2] > 0) != (v[2] > 0):
                t = u[2] / (u[2] - v[2])
                w = u + (v - u) * t
                if w[1] > 0:
                    pts.append((w[0], w[1]))
        if len(pts) == 2:
            segs_l.append(pts)
    if not segs_l:
        return T
    S = np.array(segs_l)
    # encadeia segmentos em polilinhas (pontas que coincidem)
    q = 1e-3
    pontas = {}
    for i, (u, v) in enumerate(S):
        for j, pt in enumerate((u, v)):
            pontas.setdefault(tuple(np.round(pt / q).astype(int)), []).append((i, j))
    usado = np.zeros(len(S), bool)
    linhas = []
    for i0 in range(len(S)):
        if usado[i0]:
            continue
        usado[i0] = True
        linha = [S[i0][0], S[i0][1]]
        for lado in (1, 0):
            while True:
                pt = linha[-1] if lado == 1 else linha[0]
                viz = [(i, j) for (i, j) in pontas.get(tuple(np.round(pt / q).astype(int)), []) if not usado[i]]
                if not viz:
                    break
                i, j = viz[0]
                usado[i] = True
                nxt = S[i][1 - j]
                if lado == 1:
                    linha.append(nxt)
                else:
                    linha.insert(0, nxt)
        if len(linha) >= 3:
            linhas.append(np.array(linha))
    tris = []
    ang = np.linspace(0, 2 * np.pi, segs + 1)
    for L in linhas:
        # simplifica o perfil (tira pontos quase colineares)
        keep = [0]
        for k in range(1, len(L) - 1):
            d1 = L[k] - L[keep[-1]]
            d2 = L[k + 1] - L[k]
            cr = abs(d1[0] * d2[1] - d1[1] * d2[0]) / max(np.linalg.norm(d1) * np.linalg.norm(d2), 1e-12)
            if cr > 0.06 or np.linalg.norm(L[k] - L[keep[-1]]) > 0.15:
                keep.append(k)
        keep.append(len(L) - 1)
        L = L[keep]
        for k in range(len(L) - 1):
            (x0, r0), (x1, r1) = L[k], L[k + 1]
            for s in range(segs):
                c0, s0, c1, s1 = np.cos(ang[s]), np.sin(ang[s]), np.cos(ang[s + 1]), np.sin(ang[s + 1])
                A = (x0, r0 * c0, r0 * s0)
                B = (x1, r1 * c0, r1 * s0)
                C = (x1, r1 * c1, r1 * s1)
                D = (x0, r0 * c1, r0 * s1)
                tris += [(A, B, C), (A, C, D)]
    return np.array(tris, np.float64)


def disco_textura(T, res=1024, espessura=0.025):
    """raios trançados (quase planos) viram um disco com recorte (alfa) + relevo (normal map).
    Fica com o desenho fino do original e só 8 triângulos."""
    import io
    from PIL import Image, ImageDraw, ImageFilter
    P = T.reshape(-1, 3)
    x0, x1 = P[:, 0].min(), P[:, 0].max()
    rr = np.hypot(P[:, 1], P[:, 2]).max() * 1.002
    ordem = np.argsort(T[:, :, 0].mean(1))
    alt = Image.new("L", (res, res), 0)
    msk = Image.new("L", (res, res), 0)
    da, dm = ImageDraw.Draw(alt), ImageDraw.Draw(msk)
    for t in T[ordem]:
        pts = [((p[1] / rr + 1) * 0.5 * res, (p[2] / rr + 1) * 0.5 * res) for p in t]
        h = int(40 + 215 * (t[:, 0].mean() - x0) / max(x1 - x0, 1e-9))
        da.polygon(pts, fill=h)
        dm.polygon(pts, fill=255)
    msk = msk.filter(ImageFilter.MaxFilter(3))
    H = np.array(alt.filter(ImageFilter.GaussianBlur(1.2))).astype(float) / 255.0
    gy, gx = np.gradient(H)
    k = 9.0
    n = np.dstack([-gx * k, -gy * k, np.ones_like(H)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    nimg = Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8))
    rgba = Image.new("RGBA", (res, res), (255, 255, 255, 0))
    rgba.putalpha(msk)
    b1, b2 = io.BytesIO(), io.BytesIO()
    rgba.save(b1, "PNG")
    nimg.save(b2, "PNG")
    # dois discos (frente e um pouco atrás) pra ter espessura vista de lado
    tris, uvs = [], []
    for xx in (x1, x1 - espessura):
        A = (xx, -rr, -rr); B = (xx, rr, -rr); C = (xx, rr, rr); D = (xx, -rr, rr)
        ua, ub, uc, ud = (0, 0), (1, 0), (1, 1), (0, 1)
        tris += [(A, C, B), (A, D, C)]
        uvs += [(ua, uc, ub), (ua, ud, uc)]
    return dict(T=np.array(tris, float), UV=np.array(uvs, float), tex=b1.getvalue(), nrm=b2.getvalue())


def prato_textura(T, res=1024, segs=64, espessura=0.03):
    """raios trançados num "prato" raso: a geometria vira um prato liso (perfil médio dos raios) e o desenho
    dos raios vai numa textura recortada (alfa) + relevo (normal map). Leve e com o desenho fino do original."""
    import io
    from PIL import Image, ImageDraw, ImageFilter
    cen = T.mean(1)
    rc = np.hypot(cen[:, 1], cen[:, 2])
    r0, r1 = max(0.0, rc.min() - 0.02), rc.max() + 0.02
    bins = np.linspace(r0, r1, 24)
    xm = []
    for a, b in zip(bins[:-1], bins[1:]):
        s = (rc >= a) & (rc < b)
        xm.append(np.percentile(cen[s, 0], 70) if s.sum() > 5 else np.nan)
    xm = np.array(xm)
    rb = (bins[:-1] + bins[1:]) / 2
    ok = ~np.isnan(xm)
    perfil = lambda r: np.interp(r, rb[ok], xm[ok])
    rr = r1
    ordem = np.argsort(T[:, :, 0].mean(1) - perfil(rc))
    alt = Image.new("L", (res, res), 0)
    msk = Image.new("L", (res, res), 0)
    da, dm = ImageDraw.Draw(alt), ImageDraw.Draw(msk)
    rel = cen[:, 0] - perfil(rc)
    lo_, hi_ = np.percentile(rel, 2), np.percentile(rel, 98)
    for k in ordem:
        t = T[k]
        pts = [((p[1] / rr + 1) * 0.5 * res, (p[2] / rr + 1) * 0.5 * res) for p in t]
        h = int(np.clip(30 + 225 * (rel[k] - lo_) / max(hi_ - lo_, 1e-9), 0, 255))
        da.polygon(pts, fill=h)
        dm.polygon(pts, fill=255)
    H = np.array(alt.filter(ImageFilter.GaussianBlur(1.0))).astype(float) / 255.0
    gy, gx = np.gradient(H)
    k = 6.0
    n = np.dstack([-gx * k, -gy * k, np.ones_like(H)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    nimg = Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8))
    rgba = Image.new("RGBA", (res, res), (255, 255, 255, 0))
    rgba.putalpha(msk)
    b1, b2 = io.BytesIO(), io.BytesIO()
    rgba.save(b1, "PNG")
    nimg.save(b2, "PNG")
    tris, uvs = [], []
    raios = np.linspace(r0, r1, 14)
    ang = np.linspace(0, 2 * np.pi, segs + 1)
    def pt(r, a, dx):
        y, z = r * np.cos(a), r * np.sin(a)
        return (float(perfil(r)) + dx, y, z), ((y / rr + 1) * 0.5, (z / rr + 1) * 0.5)
    for dx in (0.0, -espessura):
        for i in range(len(raios) - 1):
            for s in range(segs):
                (A, ua), (B, ub) = pt(raios[i], ang[s], dx), pt(raios[i + 1], ang[s], dx)
                (C, uc), (D, ud) = pt(raios[i + 1], ang[s + 1], dx), pt(raios[i], ang[s + 1], dx)
                tris += [(A, C, B), (A, D, C)]
                uvs += [(ua, uc, ub), (ua, ud, uc)]
    return dict(T=np.array(tris, float), UV=np.array(uvs, float), tex=b1.getvalue(), nrm=b2.getvalue())


def gravar(destino, nome_id, pecas):
    nomes = ["RIM", "LIP", "BARREL", "BOLT"]
    blobs, acc, views, prims = [], [], [], []
    off = 0

    def add(arr, comp, alvo, mm=False):
        nonlocal off
        b = arr.astype(np.float32 if comp != "SCALAR" else np.uint32).tobytes()
        pad = (-len(b)) % 4
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(b), "target": alvo})
        blobs.append(b + b"\0" * pad)
        off += len(b) + pad
        d = {"bufferView": len(views) - 1, "componentType": 5126 if comp != "SCALAR" else 5125, "count": int(len(arr)), "type": comp}
        if mm:
            d["min"] = arr.min(0).tolist()
            d["max"] = arr.max(0).tolist()
        acc.append(d)
        return len(acc) - 1
    total = 0
    imagens, texturas = [], []
    mats = [{"name": nm, "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.8, 0.82, 1], "metallicFactor": 0.3, "roughnessFactor": 0.4}, "doubleSided": True} for nm in nomes]

    def img(dados):
        nonlocal off
        pad = (-len(dados)) % 4
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(dados)})
        blobs.append(dados + b"\0" * pad)
        off += len(dados) + pad
        imagens.append({"bufferView": len(views) - 1, "mimeType": "image/png"})
        texturas.append({"source": len(imagens) - 1})
        return len(texturas) - 1
    for mi, nm in enumerate(nomes):
        if nm not in pecas or len(pecas[nm]) == 0:
            continue
        pc = pecas[nm]
        if isinstance(pc, dict):
            T = pc["T"]
            v = T.reshape(-1, 3)
            n = np.tile([1.0, 0, 0], (len(v), 1))
            uv = pc["UV"].reshape(-1, 2)
            attrs = {"POSITION": add(v, "VEC3", 34962, True), "NORMAL": add(n, "VEC3", 34962), "TEXCOORD_0": add(uv, "VEC2", 34962)}
            mats[mi]["pbrMetallicRoughness"]["baseColorTexture"] = {"index": img(pc["tex"])}
            mats[mi]["normalTexture"] = {"index": img(pc["nrm"])}
            mats[mi]["alphaMode"] = "MASK"
            mats[mi]["alphaCutoff"] = 0.5
            prims.append({"attributes": attrs, "indices": add(np.arange(len(v), dtype=np.uint32), "SCALAR", 34963), "material": mi})
            total += len(T)
            continue
        T = pc.astype(np.float64)
        N = normais_suaves(T)
        v = T.reshape(-1, 3)
        n = N.reshape(-1, 3)
        # solda vértices iguais (com a mesma normal) pra ficar leve
        k = np.round(np.c_[v / 1e-5, n / 1e-3]).astype(np.int64)
        _, idx_u, inv = np.unique(k, axis=0, return_index=True, return_inverse=True)
        prims.append({"attributes": {"POSITION": add(v[idx_u], "VEC3", 34962, True), "NORMAL": add(n[idx_u], "VEC3", 34962)},
                      "indices": add(inv.ravel().astype(np.uint32), "SCALAR", 34963), "material": mi})
        total += len(T)
    j_extra = {"images": imagens, "textures": texturas} if imagens else {}
    j = {"asset": {"version": "2.0", "generator": "Drops Garage importar_aro_obj.py"}, "scene": 0, "scenes": [{"nodes": [0]}],
         "nodes": [{"name": nome_id, "mesh": 0}], "meshes": [{"name": nome_id, "primitives": prims}],
         "materials": mats, "accessors": acc, "bufferViews": views, "buffers": [{"byteLength": off}]}
    j.update(j_extra)
    js = json.dumps(j).encode()
    js += b" " * ((-len(js)) % 4)
    binb = b"".join(blobs)
    with open(destino, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binb)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(binb), 0x004E4942) + binb)
    print("%s: %d triângulos (%s)" % (destino, total, ", ".join("%s=%d" % (k, len(v["T"]) if isinstance(v, dict) else len(v)) for k, v in pecas.items())))


def separar_lip_barrel(T, x_lip=0.36, r_min=0.86):
    cen = T.mean(1)
    r = np.hypot(cen[:, 1], cen[:, 2])
    lip = (cen[:, 0] > x_lip) & (r > r_min)
    return T[lip], T[~lip]


def bbs():
    arq = UP + "752b77c6-BBS-Rims.obj"
    # a 2ª roda do arquivo (deitada, eixo Y): tambor/borda, raios trançados, miolo e escrita
    t = ler(arq, {("Cylinder098", None): "TAMBOR", ("Cylinder099", None): "PARAF", ("Cylinder097", None): "BOLT", ("Text003", None): "BOLT"})
    tudo = np.concatenate([v.reshape(-1, 3) for v in t.values()])
    lo, hi = t["TAMBOR"].reshape(-1, 3).min(0), t["TAMBOR"].reshape(-1, 3).max(0)
    centro = (lo + hi) / 2
    R = max(hi[0] - lo[0], hi[2] - lo[2]) / 2
    W = hi[1] - lo[1]
    # face de fora: lado dos raios
    face = 1.0 if t["PARAF"].reshape(-1, 3)[:, 1].mean() > centro[1] else -1.0
    n = normalizar(t, 1, face, centro, R, W)
    T = n["TAMBOR"]
    cen = T.mean(1)
    rc = np.hypot(cen[:, 1], cen[:, 2])
    raios_sel = (rc < 0.75) & (cen[:, 0] > 0.15)          # os raios trançados (o resto é tambor/borda torneados)
    rim = prato_textura(T[raios_sel])
    tamb = torno(T[~raios_sel])
    lip, barrel = separar_lip_barrel(tamb)
    bolt = np.concatenate([reduzir(n["BOLT"], 0.004), reduzir(n["PARAF"], 0.009)])
    gravar(os.path.join(RAIZ, "modelos", "rodas", "sfn.glb"), "sfn", {"RIM": rim, "LIP": lip, "BARREL": barrel, "BOLT": bolt})


def antera():
    arq = UP + "c8638493-Antera_Type_109.obj"
    t = ler(arq, {(None, "Material"): "RIM", (None, "Material.002"): "TAMBOR", (None, "Material.001"): "BOLT"})
    lo, hi = t["TAMBOR"].reshape(-1, 3).min(0), t["TAMBOR"].reshape(-1, 3).max(0)
    centro = (lo + hi) / 2
    R = max(hi[1] - lo[1], hi[2] - lo[2]) / 2
    W = hi[0] - lo[0]
    face = 1.0 if t["RIM"].reshape(-1, 3)[:, 0].mean() > centro[0] else -1.0
    n = normalizar(t, 0, face, centro, R, W)
    lip, barrel = separar_lip_barrel(n["TAMBOR"])
    gravar(os.path.join(RAIZ, "modelos", "rodas", "antera.glb"), "antera", {"RIM": n["RIM"], "LIP": lip, "BARREL": barrel, "BOLT": n["BOLT"]})


if __name__ == "__main__":
    {"bbs": bbs, "antera": antera}[sys.argv[1]]()
