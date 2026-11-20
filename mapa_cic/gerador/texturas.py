"""Texturas procedurais (sem fotos de terceiros) no estilo GTA."""
import numpy as np, cv2
from PIL import Image, ImageDraw, ImageFont

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def tnoise(n, cells, rng):
    """ruído suave que repete sem emenda (tileable)"""
    g = rng.random((cells, cells)).astype(np.float32)
    g = np.pad(g, 3, mode="wrap")
    s = n / cells
    big = cv2.resize(g, (int(round((cells + 6) * s)),) * 2, interpolation=cv2.INTER_CUBIC)
    o = int(round(3 * s))
    return big[o:o + n, o:o + n]


def fbm(n, rng, base=4, oct=5, gain=0.55):
    out = np.zeros((n, n), np.float32); a = 1.0; tot = 0
    c = base
    for _ in range(oct):
        if c > n: break
        out += a * tnoise(n, c, rng); tot += a; a *= gain; c *= 2
    out /= tot
    return (out - out.min()) / (out.max() - out.min() + 1e-6)


def colorize(noise, c0, c1):
    c0 = np.array(c0, np.float32); c1 = np.array(c1, np.float32)
    return (c0[None, None] * (1 - noise[..., None]) + c1[None, None] * noise[..., None])


def fine(n, rng, amt):
    return (rng.random((n, n)).astype(np.float32) - 0.5) * amt


# --------------------------------------------------------------- chão (tiles de 512 px, 0.146 m/px)
def ground_tiles(seed=1, n=512):
    rng = np.random.default_rng(seed)
    T = {}
    def mk(c0, c1, base=4, grain=14, extra=None):
        t = colorize(fbm(n, rng, base), c0, c1) + fine(n, rng, grain)[..., None]
        if extra is not None:
            t = extra(t)
        return np.clip(t, 0, 255).astype(np.uint8)

    def asfalto_extra(t):
        p = fbm(n, rng, 3)
        t *= (0.88 + 0.2 * p)[..., None]
        # remendos
        m = (fbm(n, rng, 6) > 0.78).astype(np.float32)
        m = cv2.GaussianBlur(m, (0, 0), 1.0)
        t = t * (1 - 0.18 * m[..., None])
        return t
    T["asfalto"] = mk((52, 52, 55), (78, 77, 78), 6, 16, asfalto_extra)
    T["estacionamento"] = mk((70, 70, 72), (95, 94, 93), 6, 14)

    def juntas(step_px, col):
        def f(t):
            t[::step_px, :] = t[::step_px, :] * 0.82
            t[:, ::step_px] = t[:, ::step_px] * 0.82
            return t
        return f
    T["calcada"] = mk((150, 147, 140), (182, 178, 170), 8, 12, juntas(8, None))   # placas ~1.2 m
    T["meiofio"] = mk((185, 183, 176), (205, 203, 196), 8, 8)
    T["concreto"] = mk((145, 143, 136), (175, 172, 165), 5, 10, juntas(32, None))
    def para(t):
        # paralelepípedo: mosaico irregular
        cell = (rng.random((n // 2, n // 2)) * 40 - 20).astype(np.float32)
        cell = cv2.resize(cell, (n, n), interpolation=cv2.INTER_NEAREST)
        t += cell[..., None]
        return t
    T["paralelepipedo"] = mk((92, 88, 82), (125, 118, 106), 8, 30, para)
    T["terra_rua"] = mk((128, 98, 70), (160, 128, 92), 5, 20)
    T["trilha"] = mk((150, 135, 110), (175, 160, 135), 6, 16)

    def mistura_grama_terra(t):
        d = colorize(fbm(n, rng, 5), (112, 92, 64), (140, 115, 80))
        m = np.clip((fbm(n, rng, 4) - 0.55) * 4, 0, 1)
        return t * (1 - m[..., None]) + d * m[..., None]
    T["terreno"] = mk((74, 98, 48), (112, 130, 64), 6, 22)
    T["terreno_terra"] = mk((112, 92, 64), (146, 120, 84), 6, 22)
    T["grama"] = mk((66, 104, 42), (104, 140, 62), 6, 20)
    T["mata"] = mk((38, 64, 32), (66, 92, 46), 6, 20)
    T["agua"] = mk((44, 70, 72), (66, 92, 90), 3, 6)
    T["industrial"] = mk((128, 126, 120), (160, 157, 150), 4, 14)
    T["aterro"] = mk((112, 98, 78), (146, 130, 104), 4, 18)
    T["campo"] = mk((70, 122, 52), (92, 142, 64), 8, 12)
    return T


# --------------------------------------------------------------- materiais de construção
def tex_parede(rng, n=512, variante=0):
    """1 vão de 3.5 m x 2.9 m (um andar), reboco claro com janela. Tingido pela cor do vértice."""
    t = colorize(fbm(n, rng, 6), (222, 220, 214), (246, 245, 240)) + fine(n, rng, 10)[..., None]
    H = n / 2.9; W = n / 3.5
    # sujeira no rodapé
    y = np.linspace(0, 1, n)[:, None]
    t *= (1 - 0.18 * np.clip((y - 0.85) / 0.15, 0, 1))[..., None]
    if variante == 0:
        x0, x1 = int(1.05 * W), int(2.45 * W)
        y0, y1 = int((2.9 - 2.15) * H), int((2.9 - 1.0) * H)
    else:  # janela de banheiro/basculante mais alta e estreita
        x0, x1 = int(1.35 * W), int(2.15 * W)
        y0, y1 = int((2.9 - 2.2) * H), int((2.9 - 1.6) * H)
    t[y0 - 4:y1 + 10, x0 - 6:x1 + 6] = (205, 204, 200)          # requadro
    t[y1:y1 + 10, x0 - 10:x1 + 10] = (190, 188, 182)              # peitoril
    g = colorize(fbm(n, rng, 3)[y0:y1, x0:x1], (34, 44, 52), (70, 88, 100))
    t[y0:y1, x0:x1] = g
    fr = (170, 172, 176)
    t[y0:y1, x0:x0 + 5] = fr; t[y0:y1, x1 - 5:x1] = fr
    t[y0:y0 + 5, x0:x1] = fr; t[y1 - 5:y1, x0:x1] = fr
    xm = (x0 + x1) // 2
    t[y0:y1, xm - 3:xm + 3] = fr
    if variante == 0:  # grade de janela (muito comum)
        for xx in range(x0 + 14, x1 - 6, 18):
            t[y0:y1, xx:xx + 2] = (40, 40, 40)
    else:
        for yy in range(y0 + 12, y1 - 4, 14):
            t[yy:yy + 2, x0:x1] = (175, 178, 182)
    return np.clip(t, 0, 255).astype(np.uint8)


def tex_reboco(rng, n=512):
    t = colorize(fbm(n, rng, 5), (218, 216, 210), (246, 245, 240)) + fine(n, rng, 10)[..., None]
    y = np.linspace(0, 1, n)[:, None]
    # escorrido de chuva
    s = cv2.resize(rng.random((1, 64)).astype(np.float32), (n, n), interpolation=cv2.INTER_CUBIC)
    t *= (1 - 0.08 * s * y)[..., None]
    return np.clip(t, 0, 255).astype(np.uint8)


def tex_bloco(rng, n=512):
    """bloco de concreto aparente, 2 m x 2 m: 5 x 10 blocos"""
    t = np.zeros((n, n, 3), np.float32)
    bw, bh = n // 5, n // 10
    for r in range(10):
        off = (bw // 2) * (r % 2)
        for c in range(-1, 6):
            v = rng.uniform(150, 185)
            x0 = c * bw + off; y0 = r * bh
            t[y0:y0 + bh, max(0, x0):max(0, min(n, x0 + bw))] = v
    t += fine(n, rng, 26)[..., None]
    t[::bh, :] = 120
    for r in range(10):
        off = (bw // 2) * (r % 2)
        for c in range(0, 6):
            x = c * bw + off
            if 0 <= x < n:
                t[r * bh:(r + 1) * bh, x:x + 3] = 120
    t[:, :, 0] *= 0.98; t[:, :, 2] *= 0.95
    return np.clip(t, 0, 255).astype(np.uint8)


def tex_galpao(rng, n=512):
    """telha metálica ondulada vertical, 4 m x 4 m"""
    x = np.arange(n)
    w = 0.5 + 0.5 * np.sin(x / n * 2 * np.pi * 20)
    t = (200 + 40 * w)[None, :, None].repeat(n, 0).repeat(3, 2).astype(np.float32)
    t *= (0.9 + 0.1 * fbm(n, rng, 4))[..., None]
    t[n // 2 - 2:n // 2 + 2] *= 0.8
    return np.clip(t, 0, 255).astype(np.uint8)


def tex_telha(rng, n=512):
    """telha cerâmica (colonial) 2 m x 2 m — tons claros pra ser tingida"""
    y = np.arange(n)[:, None]; x = np.arange(n)[None, :]
    rows = 2 * 2 / 0.4  # fiadas de 40 cm
    cols = 2 / 0.2
    a = np.sin(x / n * np.pi * 2 * cols) ** 2
    b = (y * rows / n) % 1.0
    v = 0.65 + 0.35 * a - 0.25 * (b > 0.88)
    t = (v * 235)[..., None].repeat(3, 2).astype(np.float32)
    t *= (0.85 + 0.25 * fbm(n, rng, 6))[..., None]
    return np.clip(t, 0, 255).astype(np.uint8)


def tex_fibro(rng, n=512):
    x = np.arange(n)[None, :]
    w = np.sin(x / n * 2 * np.pi * 11) * 0.5 + 0.5
    t = (180 + 50 * w).repeat(n, 0)[..., None].repeat(3, 2).astype(np.float32)
    t *= (0.8 + 0.25 * fbm(n, rng, 5))[..., None]
    # limo
    m = np.clip((fbm(n, rng, 4) - 0.6) * 3, 0, 1)
    t = t * (1 - 0.3 * m[..., None]) + np.array([60, 70, 40]) * 0.3 * m[..., None]
    return np.clip(t, 0, 255).astype(np.uint8)


def tex_laje(rng, n=512):
    t = colorize(fbm(n, rng, 4), (150, 148, 142), (195, 192, 186)) + fine(n, rng, 16)[..., None]
    m = np.clip((fbm(n, rng, 6) - 0.65) * 3, 0, 1)
    t *= (1 - 0.35 * m)[..., None]
    return np.clip(t, 0, 255).astype(np.uint8)


def tex_placa(texto, sub, n=(2048, 256)):
    img = Image.new("RGB", n, (200, 20, 25))
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FONT, 150); f2 = ImageFont.truetype(FONT, 52)
    d.rectangle([0, 0, n[0] - 1, n[1] - 1], outline=(250, 200, 0), width=14)
    w = d.textlength(texto, font=f)
    d.text(((n[0] - w) / 2, 8), texto, fill=(255, 255, 255), font=f, stroke_width=4, stroke_fill=(30, 30, 30))
    w2 = d.textlength(sub, font=f2)
    d.text(((n[0] - w2) / 2, 180), sub, fill=(255, 220, 0), font=f2)
    return np.array(img)


def tex_grade(n=256):
    """1 m x 1 m de barras verticais (fundo transparente)"""
    a = np.zeros((n, n, 4), np.uint8)
    passo = int(n * 0.105); larg = max(3, int(n * 0.028))
    for x in range(passo // 2, n, passo):
        a[:, x:x + larg, :3] = 235
        a[:, x:x + 1, :3] = 255
        a[:, x + larg - 1:x + larg, :3] = 170
        a[:, x:x + larg, 3] = 255
    return a


def tex_tijolo(rng, n=512):
    """tijolo baiano/maciço aparente, 2 m x 2 m"""
    t = np.zeros((n, n, 3), np.float32)
    bw, bh = n // 10, n // 20
    for r in range(20):
        off = (bw // 2) * (r % 2)
        for c in range(-1, 11):
            base = np.array([rng.uniform(150, 190), rng.uniform(70, 95), rng.uniform(45, 65)])
            x0 = c * bw + off; y0 = r * bh
            t[y0:y0 + bh, max(0, x0):max(0, min(n, x0 + bw))] = base
    t += fine(n, rng, 20)[..., None]
    t[::bh, :] = (165, 160, 150)
    for r in range(20):
        off = (bw // 2) * (r % 2)
        for c in range(0, 11):
            x = c * bw + off
            if 0 <= x < n: t[r * bh:(r + 1) * bh, x:x + 3] = (165, 160, 150)
    return np.clip(t, 0, 255).astype(np.uint8)


def save(path, arr, q=None):
    im = Image.fromarray(arr)
    if q:
        im.save(path, quality=q, optimize=True)
    else:
        im.save(path, optimize=True)


def build_all(folder, seed=7):
    rng = np.random.default_rng(seed)
    save(f"{folder}/parede.png", tex_parede(rng))
    save(f"{folder}/parede2.png", tex_parede(rng, variante=1))
    save(f"{folder}/grade.png", tex_grade())
    save(f"{folder}/tijolo.png", tex_tijolo(rng))
    # grão do chão (detalhe de perto, repete a cada 2 m no shader)
    g = (fbm(256, rng, 16, 4) * 0.6 + rng.random((256, 256)).astype(np.float32) * 0.4)
    g = (g - g.min()) / (g.max() - g.min())
    save(f"{folder}/grao.png", (np.stack([g] * 3, -1) * 255).astype(np.uint8))
    save(f"{folder}/reboco.png", tex_reboco(rng))
    save(f"{folder}/bloco.png", tex_bloco(rng))
    save(f"{folder}/galpao.png", tex_galpao(rng))
    save(f"{folder}/telha.png", tex_telha(rng))
    save(f"{folder}/fibro.png", tex_fibro(rng))
    save(f"{folder}/laje.png", tex_laje(rng))
    save(f"{folder}/placa_show.png", tex_placa("SHOW DE FERRAGENS", "FERRAMENTAS • TINTAS • ELÉTRICA • EPI • CONSTRUÇÃO"))
