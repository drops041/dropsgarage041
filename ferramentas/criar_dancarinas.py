"""CRIAR DANÇARINAS — a partir do Thuess dançando (mesmo esqueleto e animação):
1) conserta o Thuess: as coordenadas de textura vieram em 0..65535 (deviam ser 0..1) e o boneco ficava
   todo marrom liso -> modelos/personagens/dancarino.glb (com roupa e rosto de verdade)
2) cria mulheres: corpo afinado (ombro, cintura), quadril e busto, sem boné, cabelo comprido e roupa
   recolorida -> modelos/personagens/mulher_a.glb, mulher_b.glb, mulher_c.glb

Uso: python3 ferramentas/criar_dancarinas.py
"""
import io
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB  # noqa: E402

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ORIG = os.path.join(RAIZ, "modelos", "personagens", "dancarino.glb")   # o Thuess original, já com a textura consertada
# malhas do Thuess: 0 cílios, 1 jaqueta (Tops), 2 boné (Hats), 3 corpo, 4 calça, 5 tênis
CILIOS, TOP, BONE, CORPO, CALCA, TENIS = range(6)

# variações: cor da blusa, da calça/short, do tênis, do cabelo, tom de pele (multiplica)
MULHERES = {
    "mulher_a": dict(top=(232, 40, 120), calca=(28, 28, 34), tenis=(240, 240, 240), cabelo=(28, 18, 12), pele=(1.0, 1.0, 1.0), comprido=1.0, barra=113, manga=42, short=72),
    "mulher_b": dict(top=(245, 245, 245), calca=(70, 110, 170), tenis=(30, 30, 30), cabelo=(150, 95, 45), pele=(0.78, 0.66, 0.58), comprido=0.75, barra=110, manga=30),
    "mulher_c": dict(top=(255, 196, 0), calca=(20, 20, 24), tenis=(255, 255, 255), cabelo=(12, 10, 10), pele=(0.6, 0.47, 0.4), comprido=1.15, barra=114, manga=48, short=58),
}


def lin(c):
    return [((x / 255.0 + 0.055) / 1.055) ** 2.4 for x in c]


def consertar_uv(g):
    for m in g.j["meshes"]:
        for p in m["primitives"]:
            ai = p["attributes"]["TEXCOORD_0"]
            uv = g.accessor(ai)
            if uv.max() > 2.0:
                uv = (uv / 65535.0).astype(np.float32)
                vi = g.add_view(np.ascontiguousarray(uv).tobytes(), 34962)
                g.j["accessors"][ai] = {"bufferView": vi, "componentType": 5126, "count": int(len(uv)), "type": "VEC2",
                                        "min": uv.min(0).tolist(), "max": uv.max(0).tolist()}


def suave(v, a, b, c, d):
    """0 antes de a, sobe até 1 em b, fica 1 até c, desce até 0 em d"""
    return np.clip(np.minimum((v - a) / (b - a), (d - v) / (d - c)), 0, 1)


def corpo_feminino(P):
    """deforma posições (cm, y pra cima, frente +z, pose T). Mesma função em todas as malhas: nada atravessa."""
    P = P.copy()
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    ax = np.abs(x)
    # ombros mais estreitos: o tronco encolhe e o braço inteiro vem junto pra dentro
    w_omb = suave(y, 112, 126, 160, 166)
    enc = 0.13 * w_omb
    novo_x = np.where(ax < 21, x * (1 - enc), np.sign(x) * (ax - 21 * enc))
    # cintura fina e quadril largo (só o tronco/coxa, não os braços esticados)
    tronco = ax < 26
    w_cint = suave(y, 92, 102, 108, 120)
    w_quad = suave(y, 70, 80, 90, 97)
    fator = 1 - 0.14 * w_cint + 0.07 * w_quad
    novo_x = np.where(tronco, novo_x * fator, novo_x)
    z2 = np.where(tronco, z * (1 - 0.1 * w_cint), z)
    # bumbum
    z2 = np.where(tronco & (z < 0), z2 - 2.2 * w_quad * np.exp(-((ax - 8) / 7) ** 2), z2)
    # busto
    for sx in (-1, 1):
        g = np.exp(-((x - sx * 8.5) / 5.5) ** 2 - ((y - 128.5) / 6.0) ** 2)
        z2 = np.where(z > 2, z2 + 6.5 * g, z2)
    P[:, 0] = novo_x
    P[:, 2] = z2
    return P


def nomes_juntas(g, skin):
    return [g.j["nodes"][n].get("name", "") for n in g.j["skins"][skin]["joints"]]


def textura_mulher(img, cfg):
    """pinta a jaqueta (camuflada) de cor lisa, a calça e o tênis; tom de pele"""
    T = np.array(img.convert("RGB")).astype(float)
    h, w = T.shape[:2]
    out = T.copy()
    yy, xx = np.mgrid[0:h, 0:w] / np.array([h, w])[:, None, None]
    from PIL import ImageFilter
    lum0 = (T[..., 0] * 0.3 + T[..., 1] * 0.59 + T[..., 2] * 0.11)
    borrado = np.array(Image.fromarray(lum0.astype(np.uint8)).filter(ImageFilter.GaussianBlur(9))).astype(float)
    lum = (0.25 * lum0 + 0.75 * borrado) / 255.0     # tira o desenho da camuflagem, fica só a dobra
    def pinta(mask, cor, base=0.55):
        k = np.clip(lum[mask] / base, 0.35, 1.35)[:, None]
        out[mask] = np.clip(np.array(cor, float)[None, :] * k, 0, 255)
    # regiões do atlas (em fração): jaqueta canto sup. dir., calça inferior dir., tênis meio sup.
    jaqueta = (xx > 0.745) & (yy > 0.24) & (yy < 0.5)
    calca = (xx > 0.5) & (xx < 0.97) & (yy > 0.5)
    tenis = (xx > 0.5) & (xx < 0.745) & (yy > 0.24) & (yy < 0.5)
    pinta(jaqueta, cfg["top"], 0.42)
    pinta(calca, cfg["calca"], 0.3)
    pinta(tenis, cfg["tenis"], 0.25)
    pele = (xx < 0.5) & (yy > 0.5)
    out[pele] = np.clip(out[pele] * np.array(cfg["pele"])[None, :], 0, 255)
    # maquiagem: batom (a boca no atlas fica em ~(128, 909) de 1024, de cabeça pra baixo) e olho marcado
    X, Y = xx * w, yy * h
    s = w / 1024.0
    boca = (((X - 128 * s) / (25 * s)) ** 2 + ((Y - 909 * s) / (10 * s)) ** 2) < 1
    verm = np.clip(((T[..., 0] - T[..., 1]) - 55) / 25.0, 0, 1) * boca
    batom = np.array(cfg.get("batom", (175, 25, 60)), float)
    out = out * (1 - 0.85 * verm[..., None]) + batom[None, None, :] * (0.85 * verm[..., None]) * np.clip(lum[..., None] / 0.5, 0.6, 1.2)
    for ex in (100, 160):
        olho = (((X - ex * s) / (24 * s)) ** 2 + ((Y - 961 * s) / (7 * s)) ** 2) < 1
        out[olho] *= 0.72
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def cabelo(g, P_corpo, J_corpo, W_corpo, juntas, cfg, P_fora=None):
    """cabelo comprido: casca do couro cabeludo + cortina atrás + mechas dos lados. Preso na cabeça e no pescoço."""
    i_cab = juntas.index(next(n for n in juntas if n.endswith("Head_Armature") or n.endswith("Head")))
    i_pes = juntas.index(next(n for n in juntas if "Neck" in n))
    i_cos = juntas.index(next(n for n in juntas if "Spine2" in n))
    cab = P_corpo[(J_corpo[:, 0] == i_cab) & (W_corpo[:, 0] > 0.5)]
    alto = cab[cab[:, 1] > np.percentile(cab[:, 1], 60)]
    cx, cz = 0.0, float((alto[:, 2].min() + alto[:, 2].max()) / 2.0)
    topo = float(cab[:, 1].max())
    base_cab = float(np.percentile(cab[:, 1], 3))
    # perfil da cabeça: raio por altura e ângulo (pra casca colar na cabeça)
    fora = cab if P_fora is None else np.vstack([cab, P_fora[np.abs(P_fora[:, 0]) < 16]])
    def raio(yv, ang):
        perto = (cab if yv > base_cab else fora)
        perto = perto[np.abs(perto[:, 1] - yv) < 1.5]
        if len(perto) < 5:
            return 3.0
        a = np.arctan2(perto[:, 0] - cx, perto[:, 2] - cz)
        d = np.abs((a - ang + np.pi) % (2 * np.pi) - np.pi)
        sel = perto[d < 0.35]
        if len(sel) == 0:
            sel = perto
        return float(np.max(np.hypot(sel[:, 0] - cx, sel[:, 2] - cz)))
    L = cfg["comprido"]
    vs, js, ws, fs = [], [], [], []
    # grade em (ângulo, altura): ângulo 0 = frente. Cabelo cobre de -150° a 150° por trás (deixa o rosto livre)
    angs = np.radians(np.linspace(-160, 160, 33))
    alt_rosto = base_cab + (topo - base_cab) * 0.62     # acima da testa
    linhas = []
    ys = list(np.linspace(topo + 0.6, base_cab - 1.5, 15))
    for li, yv in enumerate(ys):
        linha = []
        for ang in angs:
            frente = np.cos(ang)
            r = raio(min(max(yv, base_cab + 0.5), topo - 0.4), ang) + 0.45 + 0.35 * (1 - frente)
            if frente > 0.55 and yv < base_cab + (topo - base_cab) * 0.7:
                linha.append(-1)      # rosto livre (testa aparecendo: cabelo puxado pra trás)
                continue
            if frente > -0.25 and yv < base_cab + (topo - base_cab) * 0.42:
                linha.append(-1)      # orelha pra baixo só atrás
                continue
            if frente > 0.0 and yv < base_cab + 3:
                linha.append(-1)      # não desce na frente do pescoço
                continue
            linha.append(len(vs))
            vs.append((cx + r * np.sin(ang), min(yv, topo + 0.6), cz + r * np.cos(ang)))
            js.append((i_cab, 0, 0, 0)); ws.append((1, 0, 0, 0))
        linhas.append(linha)
    for li in range(len(linhas) - 1):
        a_, b_ = linhas[li], linhas[li + 1]
        for k in range(len(angs) - 1):
            q = [a_[k], a_[k + 1], b_[k + 1], b_[k]]
            if min(q) < 0:
                continue
            fs += [(q[0], q[2], q[1]), (q[0], q[3], q[2])]
    # rabo de cavalo: tubo saindo de trás da cabeça, caindo pra baixo e um pouco pra trás (preso na cabeça)
    y0 = base_cab + (topo - base_cab) * 0.55
    r_tras = raio(y0, np.pi)
    p0 = np.array([cx, y0, cz - r_tras + 0.8])
    n_seg, n_anel = 12, 10
    comp = 24.0 * L
    centro = p0.copy()
    aneis = []
    for s in range(n_seg + 1):
        t = s / n_seg
        if s > 0:
            d = np.array([0.0, -1.0, -0.75 + 0.6 * t])
            centro = centro + d / np.linalg.norm(d) * (comp / n_seg)
        rr = (2.2 + 1.6 * np.sin(np.pi * min(1.0, t * 1.6))) * (1 - 0.75 * t ** 2.5) if s < n_seg else 0.25
        anel = []
        for k in range(n_anel):
            a2 = 2 * np.pi * k / n_anel
            off = np.array([np.cos(a2) * rr * 1.15, 0.0, np.sin(a2) * rr])
            anel.append(len(vs))
            vs.append(tuple(centro + off))
            js.append((i_cab, 0, 0, 0)); ws.append((1, 0, 0, 0))
        aneis.append(anel)
    for s in range(n_seg):
        for k in range(n_anel):
            k2 = (k + 1) % n_anel
            q = [aneis[s][k], aneis[s][k2], aneis[s + 1][k2], aneis[s + 1][k]]
            fs += [(q[0], q[1], q[2]), (q[0], q[2], q[3])]
    # elástico (laço) na base do rabo
    for k in range(n_anel):
        pass
    # tampa de cima (leque até o topo)
    c0 = len(vs)
    vs.append((cx, topo + 1.0, cz)); js.append((i_cab, 0, 0, 0)); ws.append((1, 0, 0, 0))
    l0 = linhas[0]
    for k in range(len(angs) - 1):
        if l0[k] >= 0 and l0[k + 1] >= 0:
            fs.append((c0, l0[k + 1], l0[k]))
    W = np.array(ws, np.float32)
    W /= np.maximum(W.sum(1, keepdims=True), 1e-6)
    return np.array(vs, np.float32), np.array(fs, np.uint32), np.array(js), W


def fazer(destino, cfg=None):
    g = GLB(ORIG)
    j = g.j
    consertar_uv(g)
    if cfg is None:
        g.salvar(destino)
        return
    # sem boné
    for n in j["nodes"]:
        if n.get("mesh") == BONE:
            n.pop("mesh", None)
            n.pop("skin", None)
    # corpo feminino em todas as malhas
    for mi, m in enumerate(j["meshes"]):
        if mi == BONE:
            continue
        p = m["primitives"][0]
        P = g.accessor(p["attributes"]["POSITION"])
        p["attributes"]["POSITION"] = g.add_accessor_vec3(corpo_feminino(P))
    # sem capuz (o capuz escondia o cabelo comprido)
    pt = j["meshes"][TOP]["primitives"][0]
    Pt = g.accessor(pt["attributes"]["POSITION"])
    It = g.accessor(pt["indices"]).reshape(-1, 3)
    capuz = (Pt[:, 1] > 143) & (Pt[:, 2] < -2.5) & (np.abs(Pt[:, 0]) < 15)
    manter = ~capuz[It].all(1)     # (o corpo por baixo da roupa não existe: não dá pra cortar manga/barra)
    vi = g.add_view(np.ascontiguousarray(It[manter], np.uint32).tobytes(), 34963)
    j["accessors"].append({"bufferView": vi, "componentType": 5125, "count": int(manter.sum() * 3), "type": "SCALAR"})
    pt["indices"] = len(j["accessors"]) - 1
    if False and cfg.get("short"):
        pb = j["meshes"][CALCA]["primitives"][0]
        Pb = g.accessor(pb["attributes"]["POSITION"])
        Ib = g.accessor(pb["indices"]).reshape(-1, 3)
        mb = ~(Pb[:, 1] < cfg["short"])[Ib].any(1)
        vb = g.add_view(np.ascontiguousarray(Ib[mb], np.uint32).tobytes(), 34963)
        j["accessors"].append({"bufferView": vb, "componentType": 5125, "count": int(mb.sum() * 3), "type": "SCALAR"})
        pb["indices"] = len(j["accessors"]) - 1
    # textura recolorida (blusa, calça, tênis, pele)
    tex_i = j["materials"][1]["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    img_i = j["textures"][tex_i]["source"]
    im = Image.open(io.BytesIO(g.view_bytes(j["images"][img_i]["bufferView"])))
    nova = textura_mulher(im, cfg)
    b = io.BytesIO()
    nova.save(b, "JPEG", quality=90)
    vi = g.add_view(b.getvalue())
    j["images"].append({"bufferView": vi, "mimeType": "image/jpeg", "name": "mulher"})
    j["textures"].append({"source": len(j["images"]) - 1, "sampler": j["textures"][tex_i].get("sampler", 0)})
    j["materials"][1] = dict(j["materials"][1])
    j["materials"][1]["pbrMetallicRoughness"] = dict(j["materials"][1]["pbrMetallicRoughness"])
    j["materials"][1]["pbrMetallicRoughness"]["baseColorTexture"] = {"index": len(j["textures"]) - 1}
    # cabelo (preso no esqueleto do corpo)
    pc = j["meshes"][CORPO]["primitives"][0]
    skin_corpo = next(n["skin"] for n in j["nodes"] if n.get("mesh") == CORPO)
    juntas = nomes_juntas(g, skin_corpo)
    Pc = g.accessor(pc["attributes"]["POSITION"])
    Jc = g.accessor(pc["attributes"]["JOINTS_0"]).astype(int)
    Wc = g.accessor(pc["attributes"]["WEIGHTS_0"])
    Pt2 = g.accessor(pt["attributes"]["POSITION"])[np.unique(It[manter])]
    V, F, Jn, Wn = cabelo(g, Pc, Jc, Wc, juntas, cfg, np.vstack([Pc, Pt2]))
    Nn = np.zeros_like(V)
    tri = V[F.astype(int)]
    fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    for c in range(3):
        np.add.at(Nn, F[:, c].astype(int), fn)
    Nn /= np.maximum(np.linalg.norm(Nn, axis=1, keepdims=True), 1e-9)
    tipo_j = j["accessors"][pc["attributes"]["JOINTS_0"]]["componentType"]
    np_j = {5121: np.uint8, 5123: np.uint16}[tipo_j]
    def acc(arr, tipo, comp, alvo=34962, mm=False):
        v = g.add_view(np.ascontiguousarray(arr).tobytes(), alvo)
        a = {"bufferView": v, "componentType": comp, "count": int(len(arr)), "type": tipo}
        if mm:
            a["min"] = arr.min(0).tolist()
            a["max"] = arr.max(0).tolist()
        j["accessors"].append(a)
        return len(j["accessors"]) - 1
    # textura de fios
    rng = np.random.default_rng(3)
    fio = np.array(Image.fromarray((rng.random((256, 48)) * 255).astype(np.uint8)).resize((256, 256), Image.BILINEAR)) / 255.0
    bf = io.BytesIO()
    Image.fromarray(np.clip((0.55 + 0.6 * fio) * 255, 0, 255).astype(np.uint8)).convert("RGB").save(bf, "PNG")
    vfio = g.add_view(bf.getvalue())
    j["images"].append({"bufferView": vfio, "mimeType": "image/png", "name": "fios"})
    j.setdefault("samplers", []).append({"wrapS": 10497, "wrapT": 10497})
    j["textures"].append({"source": len(j["images"]) - 1, "sampler": len(j["samplers"]) - 1})
    ang = np.arctan2(V[:, 0], V[:, 2] - np.median(V[:, 2]))
    UVn = np.stack([ang * 2.0, V[:, 1] * 0.03], 1).astype(np.float32)
    atr = {"POSITION": acc(V, "VEC3", 5126, mm=True), "NORMAL": acc(Nn.astype(np.float32), "VEC3", 5126),
           "TEXCOORD_0": acc(UVn, "VEC2", 5126), "JOINTS_0": acc(Jn.astype(np_j), "VEC4", tipo_j),
           "WEIGHTS_0": acc(Wn.astype(np.float32), "VEC4", 5126)}
    ii = acc(np.ascontiguousarray(F, np.uint32).ravel(), "SCALAR", 5125, 34963)
    j["materials"].append({"name": "cabelo", "pbrMetallicRoughness": {"baseColorFactor": lin(cfg["cabelo"]) + [1.0], "metallicFactor": 0.0,
                           "roughnessFactor": 0.8, "baseColorTexture": {"index": len(j["textures"]) - 1}}, "doubleSided": True})
    j["meshes"][CORPO]["primitives"].append({"attributes": atr, "indices": ii, "material": len(j["materials"]) - 1})
    g.salvar(destino)


def main():
    pasta = os.path.join(RAIZ, "modelos", "personagens")
    if not os.path.exists(ORIG):
        raise SystemExit("falta modelos/personagens/dancarino.glb")
    for nome, cfg in MULHERES.items():
        fazer(os.path.join(pasta, nome + ".glb"), cfg)
    print("ok: dancarino +", ", ".join(MULHERES))


if __name__ == "__main__":
    main()
