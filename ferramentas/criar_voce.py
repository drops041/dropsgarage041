"""CRIAR VOCÊ — personagem do dono da Drops a partir do mecânico (mesmo esqueleto e animações):
moicano, barba média estilo viking, laterais raspadas e roupa de skatista (camiseta larga escura,
calça jeans clara, tênis preto de sola branca). Saída: modelos/personagens/voce.glb

Uso: python3 ferramentas/criar_voce.py
"""
import io
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB  # noqa: E402

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CAMISETA = np.array([38, 38, 42.0])       # camiseta preta/grafite lavada
CALCA = np.array([96, 128, 168.0])        # jeans claro largo
TENIS = np.array([24, 24, 26.0])          # tênis preto
SOLA = np.array([232, 230, 222.0])        # sola branca
CABELO = np.array([34, 24, 18.0])         # moicano castanho bem escuro
BARBA = np.array([52, 34, 22.0])          # barba castanha escura (puxa pro avermelhado de viking)
# cabeça (unidades do modelo; o modelo tem ~0.978 de altura)
Y_NARIZ, Y_BOCA, Y_QUEIXO, Y_OLHO = 0.862, 0.846, 0.812, 0.889
MOI_LARG = 0.021


def lum(c):
    return c[..., 0] * 0.3 + c[..., 1] * 0.59 + c[..., 2] * 0.11


def main():
    g = GLB(os.path.join(RAIZ, "modelos", "personagens", "mecanico.glb"))
    j = g.j
    prim = j["meshes"][0]["primitives"][0]
    at = prim["attributes"]
    P = g.accessor(at["POSITION"])
    N = g.accessor(at["NORMAL"])
    UV = g.accessor(at["TEXCOORD_0"])
    J = g.accessor(at["JOINTS_0"]).astype(int)
    W = g.accessor(at["WEIGHTS_0"])
    idx = g.accessor(prim["indices"]).reshape(-1, 3)
    # ---- corpo mais magro: tira a barriga do mecânico (frente da barriga e cintura), afina um pouco o tronco
    def suave(y, a, b2, c):
        return np.clip(np.minimum((y - a) / (b2 - a), (c - y) / (c - b2)), 0, 1)
    P = P.copy()
    tronco = (np.abs(P[:, 0]) < 0.135) & (P[:, 1] > 0.44) & (P[:, 1] < 0.76)
    k = suave(P[:, 1], 0.44, 0.56, 0.76)
    frente = tronco & (P[:, 2] > -0.005)
    P[frente, 2] = -0.005 + (P[frente, 2] + 0.005) * (1.0 - 0.45 * k[frente])
    costas = tronco & (P[:, 2] <= -0.005)
    P[costas, 2] = -0.005 + (P[costas, 2] + 0.005) * (1.0 - 0.08 * k[costas])
    # cintura mais fina (vista de frente), com transição suave até os braços
    ax = np.abs(P[:, 0])
    wx = np.clip((0.2 - ax) / 0.07, 0, 1) * suave(P[:, 1], 0.40, 0.55, 0.74)
    P[:, 0] *= 1.0 - 0.13 * wx
    # rosto menos redondo: afina as bochechas (só a cabeça, entrando suave pelo pescoço)
    wh = np.clip((P[:, 1] - 0.855) / 0.03, 0, 1) * (np.abs(P[:, 0]) < 0.13)
    P[:, 0] *= 1.0 - 0.08 * wh
    vi_p = g.add_view(np.ascontiguousarray(P, np.float32).tobytes(), 34962)
    j["accessors"].append({"bufferView": vi_p, "componentType": 5126, "count": int(len(P)), "type": "VEC3",
                           "min": P.min(0).tolist(), "max": P.max(0).tolist()})
    at["POSITION"] = len(j["accessors"]) - 1
    nomes = [j["nodes"][i]["name"] for i in j["skins"][0]["joints"]]
    dom = np.array([nomes[d] for d in J[np.arange(len(J)), W.argmax(1)]])
    cabeca_j = next(k for k, n in enumerate(nomes) if "Head" in n and "Top" not in n)
    # textura base
    tex_i = j["textures"][j["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["source"]
    vb = j["images"][tex_i]["bufferView"]
    T = np.array(Image.open(io.BytesIO(g.view_bytes(vb))).convert("RGB")).astype(float)
    S = T.shape[0]
    # ---- região de cada triângulo
    C3 = P[idx].mean(1)
    dt = np.array([dom[t[0]] for t in idx])
    ycint = 0.535   # cintura (abaixo: calça)
    reg = np.zeros(len(idx), int)
    for k, (c, b) in enumerate(zip(C3, dt)):
        if "Head" in b or "Neck" in b:
            if c[1] < 0.825 and "Neck" in b:
                reg[k] = 5                                   # pescoço (gola vira camiseta, pele fica)
            elif c[2] > 0.0 and c[1] < Y_NARIZ + 0.004 and abs(c[0]) < 0.06 and not (abs(c[0]) < 0.016 and Y_BOCA - 0.006 < c[1] < Y_BOCA + 0.004 and c[2] > 0.06):
                reg[k] = 7                                   # barba + bigode (sem os lábios)
            elif c[2] > -0.005 and c[2] < 0.045 and Y_NARIZ - 0.01 < c[1] < Y_OLHO + 0.01 and abs(c[0]) > 0.045:
                reg[k] = 7                                   # costeleta ligando na barba
            elif abs(c[0]) < MOI_LARG and c[1] > 0.925:
                reg[k] = 8                                   # faixa do moicano
            elif c[1] > Y_NARIZ:
                reg[k] = 6                                   # laterais e nuca raspadas
            else:
                reg[k] = 5
        elif "Foot" in b or "Toe" in b:
            reg[k] = 4 if c[1] < 0.022 else 3
        elif "UpLeg" in b or "Leg" in b:
            reg[k] = 2
        elif "Hips" in b:
            reg[k] = 2 if c[1] < ycint else 1
        elif "Hand" in b:
            reg[k] = 9
        else:
            reg[k] = 1                                       # tronco, ombro, braço
    # ---- mapa de regiões na textura (rasteriza os triângulos no espaço UV)
    mapa = Image.new("I", (S, S), 0)
    d = ImageDraw.Draw(mapa)
    for t, r in zip(idx, reg):
        pts = [(float(UV[v, 0] * S), float(UV[v, 1] * S)) for v in t]
        d.polygon(pts, fill=int(r), outline=int(r))
    M = np.array(mapa)
    # dilata as bordas (evita costura com a cor velha)
    for _ in range(3):
        Mi = Image.fromarray(M.astype(np.uint8))
        Md = np.array(Mi.filter(ImageFilter.MaxFilter(3)))
        M = np.where(M == 0, Md, M)
    r, gg, b = T[..., 0], T[..., 1], T[..., 2]
    laranja = (r > 170) & (gg < 150) & (b < 90)
    pele = (r > 90) & (r > gg) & (gg > b) & ((r - b) > 22) & ((r - b) < 130) & ~laranja
    L = lum(T) / 255.0
    out = T.copy()

    def pinta(mask, base, ganho=1.0, teto=1.25):
        if not mask.any():
            return
        med = max(np.median(L[mask]), 0.05)
        f = np.clip(0.7 + 0.32 * (L[mask] / med - 1.0) * ganho + 0.3, 0.45, teto)[:, None]   # tira logo/estampa velha, mantém as dobras
        out[mask] = np.clip(base[None, :] * f, 0, 255)
    # camiseta lisa: some logo, letreiro e friso laranja da roupa velha (só fica a dobra do pano)
    # pele "de verdade" = perto do tom das mãos (letreiro/friso laranja-escuro parecia pele e ficava)
    Tf = T.astype(float)
    laranja = ((Tf[..., 0] - Tf[..., 2]) > 125) & (Tf[..., 1] < 0.62 * Tf[..., 0])   # friso/letreiro laranja saturado
    pele_v = pele & ~(laranja & (M == 1))
    cam_m = ((M == 1) | (M == 5) | (M == 9)) & ~pele_v
    if cam_m.any():
        med = max(np.median(L[cam_m]), 0.05)
        Ls = np.array(Image.fromarray((np.clip(L, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.MedianFilter(7))).astype(float) / 255.0
        f = np.clip(0.9 + 0.25 * (Ls[cam_m] / med - 1.0), 0.72, 1.08)[:, None]
        out[cam_m] = np.clip(CAMISETA[None, :] * f, 0, 255)
    pinta((M == 2), CALCA)
    pinta((M == 3), TENIS)
    pinta((M == 4), SOLA, 0.4)
    cabelo_px = ~pele | (L < 0.32)
    pinta((M == 8), CABELO, 0.6)
    # raspado: cabelo vira pele com um sombreado de máquina zero
    tom_pele = np.median(T[(pele) & (M == 5)], axis=0) if ((pele) & (M == 5)).any() else np.array([190, 140, 115.0])
    rasp = (M == 6) & cabelo_px
    if rasp.any():
        ruido = np.random.default_rng(3).normal(0, 6, (rasp.sum(), 1))
        out[rasp] = np.clip(tom_pele * 0.82 + np.array([-8, -6, -2]) + ruido, 0, 255)
    # barba: castanha com fios (ruído direcional)
    barba = (M == 7)
    if barba.any():
        rng = np.random.default_rng(7)
        fios = Image.fromarray((rng.random((S, S)) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))
        fios = np.array(fios.resize((S, S))).astype(float) / 255.0
        out[barba] = np.clip(BARBA[None, :] * (0.65 + 0.7 * fios[barba][:, None]), 0, 255)
    # pele do rosto: tira as manchas brancas de luz que vieram pintadas na textura
    claro = ((M == 5) | (M == 6) | (M == 7)) & (L > 0.62) & ~((M == 7))
    out[claro] = tom_pele[None, :] * 0.95
    rosto = ((M == 5) | (M == 6)) & pele
    if rosto.any():
        Lr = L[rosto]
        lim = np.percentile(Lr, 70)
        k = np.clip((Lr - lim) / 0.25, 0, 1)[:, None]
        out[rosto] = out[rosto] * (1 - k) + tom_pele[None, :] * k
    # estampa "DROPS" amarela no peito da camiseta (projetada de frente no corpo)
    from PIL import ImageFont
    larg, alt = 0.13, 0.034
    cx, cy = 0.0, 0.705
    txt = Image.new("L", (520, 136), 0)
    try:
        fonte = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 120)
    except Exception:
        fonte = ImageFont.load_default()
    ImageDraw.Draw(txt).text((260, 68), "DROPS", fill=255, font=fonte, anchor="mm")
    TM = np.array(txt) > 128
    for t, rr in zip(idx, reg):
        if rr != 1:
            continue
        pv = P[t]
        if pv[:, 2].mean() < 0.02 or abs(pv[:, 0].mean() - cx) > larg or abs(pv[:, 1].mean() - cy) > alt * 1.5:
            continue
        uv = UV[t] * S
        x0, y0 = np.floor(uv.min(0)).astype(int)
        x1, y1 = np.ceil(uv.max(0)).astype(int)
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        q = np.stack([xs.ravel() + 0.5, ys.ravel() + 0.5], 1)
        a, b_, c_ = uv
        m_ = np.array([[b_[0] - a[0], c_[0] - a[0]], [b_[1] - a[1], c_[1] - a[1]]])
        if abs(np.linalg.det(m_)) < 1e-9:
            continue
        l12 = np.linalg.solve(m_, (q - a).T).T
        l0 = 1 - l12.sum(1)
        dentro_t = (l0 >= -0.01) & (l12[:, 0] >= -0.01) & (l12[:, 1] >= -0.01)
        pos = l0[:, None] * pv[0] + l12[:, :1] * pv[1] + l12[:, 1:] * pv[2]
        u = ((pos[:, 0] - cx) / larg + 0.5) * TM.shape[1]
        v = (0.5 - (pos[:, 1] - cy) / (alt * 2)) * TM.shape[0]
        ok = dentro_t & (u >= 0) & (u < TM.shape[1]) & (v >= 0) & (v < TM.shape[0])
        if not ok.any():
            continue
        ui, vi = u[ok].astype(int), v[ok].astype(int)
        acerto = TM[vi, ui]
        px, py = xs.ravel()[ok][acerto], ys.ravel()[ok][acerto]
        px, py = np.clip(px, 0, S - 1), np.clip(py, 0, S - 1)
        out[py, px] = np.array([250, 205, 20.0])
    nova = Image.fromarray(out.astype(np.uint8))
    buf = io.BytesIO()
    nova.save(buf, "JPEG", quality=93)
    g.extra_views[vb] = buf.getvalue()

    # ---- peças novas presas na cabeça: moicano e o volume da barba
    cab = np.isin(dom, [n for n in set(dom) if "Head" in n])
    H = P[cab]
    tipo_j = j["accessors"][at["JOINTS_0"]]["componentType"]
    np_j = {5121: np.uint8, 5123: np.uint16}[tipo_j]
    novas = []

    # moicano: crista ao longo do meio da cabeça, com pontas
    zs = np.linspace(H[:, 2].max() - 0.02, H[:, 2].min() + 0.012, 18)
    meio = H[np.abs(H[:, 0]) < 0.014]
    topo = []
    for z in zs:
        perto = meio[np.abs(meio[:, 2] - z) < 0.012]
        y = perto[:, 1].max() if len(perto) else H[:, 1].max()
        topo.append((z, y))
    vs, fs = [], []
    rng = np.random.default_rng(11)
    for off in (-0.0075, 0.0, 0.0075):     # três lâminas = crista cheia
        ini = len(vs)
        for k, (z, y) in enumerate(topo):
            t = k / (len(topo) - 1)
            alt = 0.03 * (0.5 + 0.5 * np.sin(np.pi * min(1.0, t * 1.2))) * (1.0 - abs(off) * 30) * rng.uniform(0.75, 1.15)
            base = y - 0.006
            for sx in (-1, 1):
                vs.append((off + sx * 0.007, base, z))
            vs.append((off * 1.4, y + alt, z + 0.008))
        for k in range(len(topo) - 1):
            a, b2 = ini + k * 3, ini + (k + 1) * 3
            fs += [(a, b2, a + 2), (b2, b2 + 2, a + 2), (a + 1, a + 2, b2 + 1), (b2 + 1, a + 2, b2 + 2)]
        fs += [(ini, ini + 2, ini + 1), (len(vs) - 3, len(vs) - 2, len(vs) - 1)]
    vs = np.array(vs)
    novas.append(("moicano", vs, np.array(fs), CABELO, None))

    # barba com volume: casca da área da barba empurrada pra fora e puxada pra baixo no queixo
    tri_b = idx[reg == 7]
    usados = np.unique(tri_b)
    mapa_v = {v: i for i, v in enumerate(usados)}
    Vb = P[usados].copy()
    Nb = N[usados]
    queixo = np.clip((Y_NARIZ - Vb[:, 1]) / (Y_NARIZ - Y_QUEIXO), 0, 1)
    frente = np.clip(Vb[:, 2] / 0.08, 0, 1)
    Vb += Nb * (0.0035 + 0.006 * queixo[:, None])
    Vb[:, 1] -= 0.024 * queixo ** 2 * (0.5 + 0.5 * frente)       # cai pra baixo: barba de viking
    Vb[:, 2] += 0.006 * queixo ** 2 * frente
    fb = np.vectorize(mapa_v.get)(tri_b)
    Jb, Wb = J[usados], W[usados]
    for _ in range(2):   # subdivide cada triângulo em 4 e alisa
        meio_map = {}
        V2 = list(Vb)
        J2, W2 = list(Jb), list(Wb)
        F2 = []
        def mid(a, b3):
            k2 = (min(a, b3), max(a, b3))
            if k2 not in meio_map:
                meio_map[k2] = len(V2)
                V2.append((Vb[a] + Vb[b3]) / 2)
                J2.append(Jb[a])
                W2.append(Wb[a])
            return meio_map[k2]
        for a, b3, c3 in fb:
            ab, bc, ca = mid(a, b3), mid(b3, c3), mid(c3, a)
            F2 += [(a, ab, ca), (ab, b3, bc), (ca, bc, c3), (ab, bc, ca)]
        Vb = np.array(V2)
        Jb, Wb = np.array(J2), np.array(W2)
        fb = np.array(F2)
        viz = [set() for _ in range(len(Vb))]
        for a, b3, c3 in fb:
            viz[a] |= {b3, c3}; viz[b3] |= {a, c3}; viz[c3] |= {a, b3}
        borda = set()
        from collections import Counter
        ar = Counter()
        for a, b3, c3 in fb:
            for e in ((a, b3), (b3, c3), (c3, a)):
                ar[(min(e), max(e))] += 1
        for (a, b3), n in ar.items():
            if n == 1:
                borda |= {a, b3}
        Vs = Vb.copy()
        for i in range(len(Vb)):
            if i not in borda and viz[i]:
                Vs[i] = Vb[i] * 0.5 + np.mean([Vb[v] for v in viz[i]], 0) * 0.5
        Vb = Vs
    novas.append(("barba", Vb, fb, BARBA, (Jb, Wb)))

    sk_mesh = j["meshes"][0]
    # textura de fios (riscos verticais) pra barba e moicano
    rng2 = np.random.default_rng(5)
    fio = rng2.random((256, 64))
    fio = np.array(Image.fromarray((fio * 255).astype(np.uint8)).resize((256, 256), Image.BILINEAR)).astype(float) / 255.0
    fio = 0.55 + 0.6 * fio
    img_fio = Image.fromarray(np.clip(fio * 255, 0, 255).astype(np.uint8)).convert("RGB")
    bf = io.BytesIO()
    img_fio.save(bf, "PNG")
    vfio = g.add_view(bf.getvalue())
    j["images"].append({"bufferView": vfio, "mimeType": "image/png", "name": "fios"})
    j.setdefault("samplers", []).append({"wrapS": 10497, "wrapT": 10497})
    j["textures"].append({"source": len(j["images"]) - 1, "sampler": len(j["samplers"]) - 1})
    tex_fio = len(j["textures"]) - 1
    for nome, V, F, cor, pesos in novas:
        V = np.ascontiguousarray(V, np.float32)
        # normais simples
        Nn = np.zeros_like(V)
        tri = V[F]
        fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        for c in range(3):
            np.add.at(Nn, F[:, c], fn)
        Nn /= np.maximum(np.linalg.norm(Nn, axis=1, keepdims=True), 1e-9)
        if pesos is None:
            Jn = np.zeros((len(V), 4), np_j)
            Jn[:, 0] = cabeca_j
            Wn = np.zeros((len(V), 4), np.float32)
            Wn[:, 0] = 1.0
        else:
            Jn = pesos[0].astype(np_j)
            Wn = pesos[1].astype(np.float32)
        def acc(arr, tipo, comp, alvo=34962, mm=False):
            vi = g.add_view(np.ascontiguousarray(arr).tobytes(), alvo)
            a = {"bufferView": vi, "componentType": comp, "count": int(len(arr)), "type": tipo}
            if mm:
                a["min"] = arr.min(0).tolist()
                a["max"] = arr.max(0).tolist()
            j["accessors"].append(a)
            return len(j["accessors"]) - 1
        UVn = np.stack([V[:, 0] * 30.0, V[:, 1] * 30.0], 1).astype(np.float32)
        atr = {"POSITION": acc(V, "VEC3", 5126, mm=True), "NORMAL": acc(Nn.astype(np.float32), "VEC3", 5126),
               "TEXCOORD_0": acc(UVn, "VEC2", 5126),
               "JOINTS_0": acc(Jn, "VEC4", tipo_j), "WEIGHTS_0": acc(Wn, "VEC4", 5126)}
        ii = acc(np.ascontiguousarray(F, np.uint32).ravel(), "SCALAR", 5125, 34963)
        lin = [((x / 255.0 + 0.055) / 1.055) ** 2.4 for x in cor]
        j["materials"].append({"name": "cabelo_" + nome, "pbrMetallicRoughness": {"baseColorFactor": lin + [1.0], "metallicFactor": 0.0,
                               "roughnessFactor": 0.85, "baseColorTexture": {"index": tex_fio}}, "doubleSided": True})
        sk_mesh["primitives"].append({"attributes": atr, "indices": ii, "material": len(j["materials"]) - 1})
    destino = os.path.join(RAIZ, "modelos", "personagens", "voce.glb")
    g.salvar(destino)
    nova.save("/tmp/voce_textura.png")
    print("voce.glb ok:", os.path.getsize(destino) // 1024, "KB; triângulos da barba:", len(tri_b))


if __name__ == "__main__":
    main()
