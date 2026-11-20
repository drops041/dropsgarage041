"""Modelo da fachada da Drops Garage feito a partir da foto (estilo GTA, low-poly).
Coordenadas locais: fachada virada pra -Z (rua), lote cresce pra +Z, origem no centro da
frente do lote, no alinhamento do muro. xr = direita de quem olha da rua (vira -X no modelo).
uso: python3 drops_garage.py pasta_blocos
"""
import sys, math
import numpy as np, cv2
from PIL import Image, ImageDraw
from glb import MeshBuilder, write_glb
import texturas

OUT = sys.argv[1]
rng = np.random.default_rng(55)


def lin(rgb, a=1.0):
    return [(c / 255.0) ** 2.2 for c in rgb] + [a]


def P(xr, y, z):
    return np.array([-xr, y, z], float)


UVS = {"epoxi": (3, 3), "parede_preta": (3.0, 3.0), "drops_logo": (1, 1), "drops_spray": (1, 1), "madeira": (2, 2), "fibro": (2, 2),
       "luz": (1, 1), "azulejo": (1.2, 1.2), "drops_muro": (2.0, 2.0), "reboco": (4, 4), "parede": (3.5, 2.9), "laje": (4, 4), "telha": (2, 2),
       "forro": (2, 2), "cor": (1, 1), "metal": (1, 1), "drops_fachada": (1, 1)}


def face(mb, mat, corners, n, col):
    """corners em (xr,y,z); UV planar em metros conforme a normal"""
    us, vs = UVS[mat]
    uv = []
    for (xr, y, z) in corners:
        if abs(n[2]) > 0.5: uv.append((xr / us, 1 - y / vs))
        elif abs(n[0]) > 0.5: uv.append((z / us, 1 - y / vs))
        else: uv.append((xr / us, z / vs))
    mb.quad([P(*c) for c in corners], uv, col, P(*n))


def box(B, mat, x0, x1, y0, y1, z0, z1, col, skip=()):
    c = lin(col) if isinstance(col, tuple) else col
    mb = B[mat]
    if "f" not in skip: face(mb, mat, [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)], (0, 0, -1), c)
    if "b" not in skip: face(mb, mat, [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (0, 0, 1), c)
    if "l" not in skip: face(mb, mat, [(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)], (-1, 0, 0), c)
    if "r" not in skip: face(mb, mat, [(x1, y0, z0), (x1, y0, z1), (x1, y1, z1), (x1, y1, z0)], (1, 0, 0), c)
    if "t" not in skip: face(mb, mat, [(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], (0, 1, 0), c)
    if "d" in skip or True:
        pass


def cyl(mb, xr, z, r, y0, y1, col, n=8):
    c = lin(col)
    for k in range(n):
        a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        p0 = (xr + r * math.cos(a0), z + r * math.sin(a0)); p1 = (xr + r * math.cos(a1), z + r * math.sin(a1))
        nm = ((p0[0] + p1[0]) / 2 - xr, 0, (p0[1] + p1[1]) / 2 - z)
        mb.quad([P(p0[0], y0, p0[1]), P(p1[0], y0, p1[1]), P(p1[0], y1, p1[1]), P(p0[0], y1, p0[1])], [(0, 0)] * 4, c, P(*nm))


# ------------------------------------------------------------------ texturas da foto
def tex_muro(n=512):
    base = texturas.colorize(texturas.fbm(n, rng, 5), (172, 126, 32), (204, 156, 50))
    base += texturas.fine(n, rng, 12)[..., None]
    y = np.linspace(0, 1, n)[:, None]
    # escorrido escuro vindo de cima
    streak = cv2.resize(rng.random((1, 48)).astype(np.float32), (n, n), interpolation=cv2.INTER_CUBIC)
    base *= (1 - 0.18 * streak * np.clip(1 - y * 1.6, 0, 1))[..., None]
    # sujeira no pé do muro
    base *= (1 - 0.25 * np.clip((y - 0.86) / 0.14, 0, 1))[..., None]
    # reboco descascado (manchas claras)
    m = texturas.fbm(n, rng, 10)
    chip = (m > 0.86).astype(np.float32)
    chip = cv2.GaussianBlur(chip, (0, 0), 1.0)
    base = base * (1 - chip[..., None]) + np.array([214, 210, 198]) * chip[..., None]
    return np.clip(base, 0, 255).astype(np.uint8)


def tex_forro(n=512):
    t = np.full((n, n, 3), 236, np.float32) + texturas.fine(n, rng, 6)[..., None]
    for x in range(0, n, n // 20):    # réguas de PVC de 10 cm
        t[:, x:x + 2] = 205
    return np.clip(t, 0, 255).astype(np.uint8)


X0F, X1F, Y0F, Y1F = -4.6, 5.2, 2.75, 5.6
PXM = 200


def tex_fachada():
    w, h = int((X1F - X0F) * PXM), int((Y1F - Y0F) * PXM)
    base = texturas.colorize(texturas.fbm(512, rng, 5), (226, 226, 222), (246, 246, 243))
    base = cv2.resize(base, (w, h)) + rng.normal(0, 3, (h, w, 1))
    img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    def X(xr): return (xr - X0F) * PXM
    def Y(y): return (Y1F - y) * PXM
    for (cx, yb, cols, rows) in ((-2.0, 3.05, 4, 3), (1.95, 2.75, 4, 4)):
        wd, yt, ya = 1.95, 4.35, 4.95
        x0, x1 = X(cx - wd / 2), X(cx + wd / 2)
        # requadro branco
        d.rectangle([x0 - 10, Y(yt), x1 + 10, Y(yb)], fill=(250, 250, 250))
        d.ellipse([x0 - 10, Y(ya) - 10, x1 + 10, Y(yt) + (Y(yt) - Y(ya)) + 10], fill=(250, 250, 250))
        # vidro (escuro com reflexo)
        glass = (52, 60, 70)
        d.rectangle([x0, Y(yt), x1, Y(yb)], fill=glass)
        d.ellipse([x0, Y(ya), x1, Y(yt) + (Y(yt) - Y(ya))], fill=glass)
        d.rectangle([x0, Y(yt), x1, Y(yb)], fill=glass)
        # reflexo
        d.polygon([(x0 + 20, Y(yb)), (x0 + 90, Y(yb)), (x1 - 40, Y(yt) + 20), (x1 - 110, Y(yt) + 20)], fill=(78, 90, 104))
        fr = (245, 245, 245)
        # quadriculado (caixilho)
        for k in range(cols + 1):
            xx = x0 + (x1 - x0) * k / cols
            d.line([(xx, Y(yt)), (xx, Y(yb))], fill=fr, width=7)
        for k in range(rows + 1):
            yy = Y(yt) + (Y(yb) - Y(yt)) * k / rows
            d.line([(x0, yy), (x1, yy)], fill=fr, width=7)
        # bandeira em arco com raios
        cxp, cyp = (x0 + x1) / 2, Y(yt)
        rx, ry = (x1 - x0) / 2, Y(yt) - Y(ya)
        d.arc([x0, Y(ya), x1, Y(yt) + ry], 180, 360, fill=fr, width=9)
        d.arc([x0 + rx * 0.45, Y(yt) - ry * 0.45, x1 - rx * 0.45, Y(yt) + ry * 0.45], 180, 360, fill=fr, width=7)
        for ang in (180 + 36, 180 + 72, 180 + 108, 180 + 144):
            a = math.radians(ang)
            d.line([(cxp + rx * 0.45 * math.cos(a), cyp + ry * 0.45 * math.sin(a)),
                    (cxp + rx * math.cos(a), cyp + ry * math.sin(a))], fill=fr, width=6)
    # luminária de parede e tomada de ar
    d.rectangle([X(0.0) - 12, Y(4.6), X(0.0) + 12, Y(4.4)], fill=(210, 210, 200))
    return np.array(img)


texturas.save(f"{OUT}/tex/drops_muro.png", tex_muro())
FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FBO = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-BoldOblique.ttf"
import os
if not os.path.exists(FBO): FBO = FB
from PIL import ImageFont, ImageFilter


def tex_logo(w=1024, h=512):
    """o grafite DROPS GARAGE da parede do fundo (estrela amarela, letras brancas, pistola de pintura)"""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    r = np.random.default_rng(7)
    pts = []
    for k in range(34):
        a = 2 * math.pi * k / 34
        rr = (0.92 if k % 2 == 0 else 0.72) + r.uniform(-0.06, 0.06)
        pts.append((w * 0.54 + math.cos(a) * w * 0.44 * rr, h * 0.5 + math.sin(a) * h * 0.47 * rr))
    d.polygon(pts, fill=(255, 205, 0, 255))
    d.polygon([(x * 0.97 + w * 0.016, y * 0.95 + h * 0.025) for x, y in pts], fill=(24, 24, 26, 255))
    f = ImageFont.truetype(FBO, 150)
    for txt, (x, y) in (("DROPS", (w * 0.28, h * 0.08)), ("GARAGE", (w * 0.25, h * 0.47))):
        d.text((x, y), txt, font=f, fill=(250, 250, 250, 255), stroke_width=10, stroke_fill=(255, 205, 0, 255))
    # pistola de pintura (silhueta)
    d.rectangle([w * 0.05, h * 0.12, w * 0.2, h * 0.28], fill=(250, 250, 250, 255), outline=(255, 205, 0, 255), width=6)
    d.rectangle([w * 0.1, h * 0.28, w * 0.15, h * 0.62], fill=(250, 250, 250, 255), outline=(255, 205, 0, 255), width=6)
    d.ellipse([w * 0.06, h * 0.6, w * 0.19, h * 0.78], fill=(250, 250, 250, 255), outline=(255, 205, 0, 255), width=6)
    d.rectangle([w * 0.115, h * 0.78, w * 0.135, h * 0.95], fill=(250, 250, 250, 255))
    return np.array(img.filter(ImageFilter.GaussianBlur(0.8)))


def tex_spray(w=1024, h=320):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FB, 120)
    d.text((40, 10), "DROPS", font=f, fill=(245, 245, 245, 255))
    d.text((40, 160), "GARAGE.", font=f, fill=(245, 245, 245, 255))
    img = img.filter(ImageFilter.GaussianBlur(2.2))   # borrado de spray
    a = np.array(img); a[..., 3] = np.clip(a[..., 3] * 1.6, 0, 255)
    return a


def tex_epoxi(n=512):
    t = texturas.colorize(texturas.fbm(n, rng, 4), (150, 154, 158), (172, 176, 180)) + texturas.fine(n, rng, 5)[..., None]
    return np.clip(t, 0, 255).astype(np.uint8)


def tex_preta(n=512):
    t = texturas.colorize(texturas.fbm(n, rng, 6), (16, 16, 18), (40, 40, 44)) + texturas.fine(n, rng, 6)[..., None]
    return np.clip(t, 0, 255).astype(np.uint8)


def tex_madeira(n=256):
    y = np.arange(n)[:, None]; x = np.arange(n)[None, :]
    v = 0.75 + 0.25 * np.sin(x / n * 40 + 3 * np.sin(y / n * 6))
    t = (np.stack([v * 255, v * 225, v * 200], -1)) * (0.85 + 0.15 * texturas.fbm(n, rng, 8))[..., None]
    return np.clip(t, 0, 255).astype(np.uint8)


def tex_azulejo(n=512):
    t = np.full((n, n, 3), 246, np.float32) + texturas.fine(n, rng, 4)[..., None]
    q = n // 4
    t[::q] = 205; t[:, ::q] = 205
    return np.clip(t, 0, 255).astype(np.uint8)


# logo da parede: tirado da foto do grafite de verdade (recortado, fundo transparente) — ver drops_logo_foto.png
_foto_logo = os.path.join(os.path.dirname(os.path.abspath(__file__)), "drops_logo_foto.png")
if os.path.exists(_foto_logo):
    Image.open(_foto_logo).save(f"{OUT}/tex/drops_logo.png")
else:
    texturas.save(f"{OUT}/tex/drops_logo.png", tex_logo())
texturas.save(f"{OUT}/tex/drops_spray.png", tex_spray())
texturas.save(f"{OUT}/tex/epoxi.png", tex_epoxi())
texturas.save(f"{OUT}/tex/parede_preta.png", tex_preta())
texturas.save(f"{OUT}/tex/madeira.png", tex_madeira())
texturas.save(f"{OUT}/tex/azulejo.png", tex_azulejo())
texturas.save(f"{OUT}/tex/forro.png", tex_forro())
texturas.save(f"{OUT}/tex/drops_fachada.png", tex_fachada())

# ------------------------------------------------------------------ geometria
B = {k: MeshBuilder() for k in ("drops_muro", "reboco", "parede", "laje", "telha", "forro", "cor", "drops_fachada", "epoxi", "parede_preta",
                                 "drops_logo", "drops_spray", "madeira", "fibro", "luz", "azulejo")}
BRANCO, CINZA, AMARELO = (246, 246, 242), (178, 178, 175), (255, 255, 255)
LOT0, LOT1, DEP = -5.2, 5.2, 12.5
G0, G1, GH = -4.25, -0.35, 2.25      # vão do portão
MH = 2.62                           # altura do muro

# muro cinza do vizinho/pilar (esquerda) com padrão de luz
box(B, "reboco", LOT0, -4.6, 0, 2.95, -0.02, 0.3, CINZA)
box(B, "reboco", LOT0 - 0.05, -4.55, 2.95, 3.05, -0.07, 0.35, (200, 200, 198))
box(B, "cor", -5.12, -4.68, 1.25, 1.95, -0.09, -0.02, (196, 200, 205))
box(B, "cor", -5.02, -4.9, 1.75, 1.85, -0.1, -0.09, (40, 45, 50))
# muro amarelo: ombreira esquerda, verga, lado direito
box(B, "drops_muro", -4.6, G0, 0, MH, 0, 0.22, AMARELO)
box(B, "drops_muro", G0, G1, GH, MH, 0, 0.22, AMARELO)
box(B, "drops_muro", G1, LOT1, 0, MH, 0, 0.22, AMARELO, skip=())
box(B, "drops_muro", -4.65, LOT1, MH, MH + 0.06, -0.04, 0.26, (230, 220, 190))   # pingadeira
# abertura escura à direita (vão do muro)
box(B, "cor", 4.45, 4.85, 1.15, 2.1, -0.01, 0.0, (28, 26, 22))
# ================== POR DENTRO (pelas fotos): corredor descoberto -> oficina coberta no fundo + cabine branca
ZS = 6.0            # fundo do sobrado da frente (laje cobre o começo do corredor)
ZO0, ZO1 = 13.5, 28.5   # oficina (v31: 5 m mais funda no fundo)
ZC1 = 23.5              # fundo da cabine branca (atrás dela a oficina continua)
XC0, XC1 = -4.6, 0.8    # corredor (entre o muro da esquerda e a casa da direita)
XO1 = 0.2               # parede entre oficina e cabine (fase 2: recuada 1,4 m pra cabine caber o carro inteiro)
CINZA_ESC = (92, 94, 98)
PRETO = (24, 24, 27)
# piso: corredor de concreto, oficina com epóxi cinza
face(B["laje"], "laje", [(XC0, 0.02, 0.0), (XC1, 0.02, 0.0), (XC1, 0.02, ZO0), (XC0, 0.02, ZO0)], (0, 1, 0), lin((178, 176, 170)))
face(B["epoxi"], "epoxi", [(XC0, 0.025, ZO0), (XO1, 0.025, ZO0), (XO1, 0.025, ZO1), (XC0, 0.025, ZO1)], (0, 1, 0), lin((150, 154, 158)))
face(B["laje"], "laje", [(XO1, 0.02, ZO0), (LOT1, 0.02, ZO0), (LOT1, 0.02, ZC1), (XO1, 0.02, ZC1)], (0, 1, 0), lin((214, 214, 210)))
face(B["epoxi"], "epoxi", [(XO1, 0.025, ZC1), (LOT1, 0.025, ZC1), (LOT1, 0.025, ZO1), (XO1, 0.025, ZO1)], (0, 1, 0), lin((150, 154, 158)))
box(B, "cor", -2.0, -1.0, 0.026, 0.035, 9.0, 9.3, (30, 30, 30))      # ralo
# muro alto da esquerda (cinza escuro) e parede de fora
box(B, "reboco", XC0 - 0.2, XC0, 0, 3.3, 0.22, ZO1 + 0.2, CINZA_ESC)
# casa da direita: parede cinza com janela e porta, beiral branco
face(B["reboco"], "reboco", [(XC1, 0, ZS), (XC1, 0, ZO0), (XC1, 3.0, ZO0), (XC1, 3.0, ZS)], (-1, 0, 0), lin((150, 152, 155)))
face(B["reboco"], "reboco", [(XC1, 0, 0.22), (XC1, 0, ZS), (XC1, 2.62, ZS), (XC1, 2.62, 0.22)], (-1, 0, 0), lin((150, 152, 155)))
box(B, "cor", XC1 - 0.04, XC1, 1.0, 2.15, 9.6, 11.4, (205, 212, 218))   # janela de alumínio
box(B, "cor", XC1 - 0.05, XC1 - 0.03, 1.08, 2.07, 9.68, 11.32, (60, 75, 88))
box(B, "cor", XC1 - 0.04, XC1, 0, 2.1, 7.0, 7.9, (230, 230, 228))       # porta
box(B, "reboco", XC1, LOT1, 0, 3.0, ZS, ZO0, (150, 152, 155), skip=("l", "t"))
face(B["forro"], "forro", [(XC1 - 0.7, 3.0, ZS), (XC1, 3.0, ZS), (XC1, 3.0, ZO0), (XC1 - 0.7, 3.0, ZO0)], (0, -1, 0), lin((255, 255, 255)))
face(B["fibro"], "fibro", [(XC1 - 0.7, 3.0, ZS), (LOT1, 3.4, ZS), (LOT1, 3.4, ZO0), (XC1 - 0.7, 3.0, ZO0)], (0, 1, 0), lin((150, 150, 148)))
# escada encostada na casa
for dx in (0.0, 0.45):
    box(B, "cor", XC1 - 0.35 - dx, XC1 - 0.31 - dx, 0, 2.9, 12.6, 12.65, (35, 35, 38))
for k in range(9):
    box(B, "cor", XC1 - 0.8, XC1 - 0.31, 0.3 + k * 0.3, 0.33 + k * 0.3, 12.61, 12.64, (35, 35, 38))
# térreo da frente (embaixo do sobrado), lado da casa
box(B, "reboco", XC1, LOT1, 0, 2.62, 0.22, ZS, BRANCO, skip=("f", "t", "l"))
# ---- oficina: paredes pretas, frente aberta com viga, telhado de fibrocimento em tesouras de madeira
HO = 3.4
face(B["cor"], "cor", [(XC0, 0, ZO0), (XC0, 0, ZO1), (XC0, HO, ZO1), (XC0, HO, ZO0)], (1, 0, 0), lin(PRETO))
face(B["parede_preta"], "parede_preta", [(XC0, 0, ZO1), (LOT1, 0, ZO1), (LOT1, HO, ZO1), (XC0, HO, ZO1)], (0, 0, -1), lin((255, 255, 255)))
# parede oficina|cabine com vão grande (como na foto da moto)
face(B["cor"], "cor", [(XO1, 0, ZO0), (XO1, 0, 15.0), (XO1, HO, 15.0), (XO1, HO, ZO0)], (-1, 0, 0), lin(PRETO))
face(B["cor"], "cor", [(XO1, 0, 21.0), (XO1, 0, ZC1), (XO1, HO, ZC1), (XO1, HO, 21.0)], (-1, 0, 0), lin(PRETO))
# fundo da oficina atrás da cabine: parede preta do lado de fora da cabine e parede da direita
face(B["cor"], "cor", [(XO1, 0, ZC1 + 0.02), (LOT1, 0, ZC1 + 0.02), (LOT1, HO, ZC1 + 0.02), (XO1, HO, ZC1 + 0.02)], (0, 0, 1), lin(PRETO))
face(B["cor"], "cor", [(LOT1, 0, ZC1), (LOT1, 0, ZO1), (LOT1, HO, ZO1), (LOT1, HO, ZC1)], (-1, 0, 0), lin(PRETO))
face(B["cor"], "cor", [(XO1, 2.55, 15.0), (XO1, 2.55, 21.0), (XO1, HO, 21.0), (XO1, HO, 15.0)], (-1, 0, 0), lin(PRETO))
# pichação "DROPS GARAGE" (spray) na parede da esquerda + faixa mostarda em cima
# (v30) parede da esquerda toda preta, sem pichação: agora é a parede das rodas (o jogo monta a prateleira)
# logo grande no fundo
B["drops_logo"].quad([P(-3.1, 0.68, ZO1 - 0.02), P(0.5, 0.68, ZO1 - 0.02), P(0.5, 3.265, ZO1 - 0.02), P(-3.1, 3.265, ZO1 - 0.02)],
                     [(0, 1), (1, 1), (1, 0), (0, 0)], lin((255, 255, 255)), P(0, 0, -1))
# viga da frente e telhado
box(B, "madeira", XC0, LOT1, HO - 0.3, HO, ZO0 - 0.15, ZO0 + 0.05, (40, 32, 26))
face(B["fibro"], "fibro", [(XC0 - 0.2, HO + 0.05, ZO0 - 0.6), (LOT1 + 0.2, HO + 0.05, ZO0 - 0.6), (LOT1 + 0.2, HO + 0.55, ZO1 + 0.2), (XC0 - 0.2, HO + 0.55, ZO1 + 0.2)],
     (0, 1, 0), lin((120, 122, 120)))
for k in range(9):   # caibros/tesouras de madeira escura
    zz = ZO0 + 0.6 + k * 1.75
    box(B, "madeira", XC0, XO1 if zz < ZC1 else LOT1, HO - 0.12, HO, zz, zz + 0.12, (58, 44, 32))
for xx in (-3.2, -1.2, 0.6):
    box(B, "madeira", xx, xx + 0.1, HO - 0.25, HO - 0.12, ZO0, ZO1, (52, 40, 30))
# luminárias de tubo (em X, triângulo e reta)
LUZ = (255, 255, 255)
def tubo(x0, z0, x1, z1, y=HO - 0.45):
    c = ((x0 + x1) / 2, (z0 + z1) / 2); L = math.hypot(x1 - x0, z1 - z0); ang = math.atan2(z1 - z0, x1 - x0)
    ax = np.array([math.cos(ang), math.sin(ang)]); bx = np.array([-ax[1], ax[0]])
    cs = [np.array(c) + ax * s1 * L / 2 + bx * s2 * 0.035 for s1, s2 in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    for (y0, nn) in ((y, (0, -1, 0)), (y + 0.06, (0, 1, 0))):
        B["luz"].quad([P(q[0], y0, q[1]) for q in cs], [(0, 0)] * 4, lin(LUZ), P(*nn))
    for k2 in range(4):
        q0, q1 = cs[k2], cs[(k2 + 1) % 4]
        B["luz"].quad([P(q0[0], y, q0[1]), P(q1[0], y, q1[1]), P(q1[0], y + 0.06, q1[1]), P(q0[0], y + 0.06, q0[1])], [(0, 0)] * 4, lin(LUZ))
tubo(-0.4, 16.0, 1.2, 17.6); tubo(-0.4, 17.6, 1.2, 16.0)          # X
# quadrado (4 tubos) no lugar da reta
for (a0, b0, a1, b1) in ((-3.5, 15.6, -2.1, 15.6), (-2.1, 15.6, -2.1, 17.0), (-2.1, 17.0, -3.5, 17.0), (-3.5, 17.0, -3.5, 15.6)):
    tubo(a0, b0, a1, b1)
# bolinha: anel de fita de LED
def anel(cx, cz, r, y, w=0.05, n=40):
    for k in range(n):
        a0 = 2 * math.pi * k / n; a1 = 2 * math.pi * (k + 1) / n
        p0 = (cx + math.cos(a0) * r, cz + math.sin(a0) * r); p1 = (cx + math.cos(a1) * r, cz + math.sin(a1) * r)
        q0 = (cx + math.cos(a0) * (r + w), cz + math.sin(a0) * (r + w)); q1 = (cx + math.cos(a1) * (r + w), cz + math.sin(a1) * (r + w))
        for (y0, nn) in ((y, (0, -1, 0)), (y + 0.02, (0, 1, 0))):
            B["luz"].quad([P(p0[0], y0, p0[1]), P(p1[0], y0, p1[1]), P(q1[0], y0, q1[1]), P(q0[0], y0, q0[1])], [(0, 0)] * 4, lin(LUZ), P(*nn))
        B["luz"].quad([P(q0[0], y, q0[1]), P(q1[0], y, q1[1]), P(q1[0], y + 0.02, q1[1]), P(q0[0], y + 0.02, q0[1])], [(0, 0)] * 4, lin(LUZ))
anel(-2.8, 19.8, 0.62, HO - 0.9)
# fundo novo: dois tubos compridos
tubo(-3.4, 24.6, -0.6, 24.6); tubo(-3.4, 26.8, -0.6, 26.8); tubo(2.4, 25.6, 4.6, 25.6)
tubo(-1.0, 20.2, 0.4, 20.2, HO - 0.9); tubo(-1.0, 20.2, -0.3, 19.2, HO - 0.9); tubo(0.4, 20.2, -0.3, 19.2, HO - 0.9)   # triângulo
# quadro branco, bancada, armário, tambor
# (v30) quadro branco da parede da esquerda tirado (parede das rodas)
box(B, "cor", -0.2, 1.5, 0, 0.95, ZO1 - 0.7, ZO1 - 0.05, (30, 30, 32))
box(B, "cor", -0.2, 1.5, 0.95, 1.0, ZO1 - 0.75, ZO1 - 0.02, (170, 140, 60))
# (quadro branco do fundo tirado: cobria o logo)
# ---- ambiente do fundo (v31): gaveteiro de ferramentas, pneus, compressor, estante com latas, lixeira, tapete
VERM = (178, 28, 30)
box(B, "cor", -3.9, -2.7, 0, 1.05, ZO1 - 0.62, ZO1 - 0.05, VERM)                 # gaveteiro vermelho
for k in range(5):
    box(B, "cor", -3.86, -2.74, 0.12 + k * 0.18, 0.13 + k * 0.18, ZO1 - 0.64, ZO1 - 0.62, (35, 35, 38))   # frisos das gavetas
box(B, "cor", -3.92, -2.68, 1.05, 1.09, ZO1 - 0.66, ZO1 - 0.02, (40, 40, 44))      # tampo
box(B, "cor", -3.85, -2.75, 1.09, 1.42, ZO1 - 0.5, ZO1 - 0.08, VERM)              # baú de cima
for (px, pz, n) in ((2.4, 27.6, 4), (3.2, 27.6, 3), (4.4, 27.4, 5), (4.4, 26.5, 2)):   # pilhas de pneus
    for k in range(n):
        cyl(B["cor"], px, pz, 0.33, k * 0.22, k * 0.22 + 0.2, (22, 22, 24))
        cyl(B["cor"], px, pz, 0.2, k * 0.22 + 0.2, k * 0.22 + 0.205, (55, 55, 58))
cyl(B["cor"], 2.3, 24.5, 0.22, 0.25, 0.85, (190, 30, 30))                          # compressor (tanque)
box(B, "cor", 2.0, 2.6, 0, 0.25, 24.25, 24.75, (40, 40, 42))
box(B, "cor", 2.15, 2.45, 0.85, 1.05, 24.35, 24.65, (60, 60, 64))
for (y0) in (0.0, 0.6, 1.2, 1.8):                                                   # estante de aço com latas
    box(B, "cor", 4.6, 5.15, y0 + 0.4, y0 + 0.43, 24.0, 25.6, (120, 122, 126))
for xx in (4.62, 5.12):
    for zz in (24.02, 25.56):
        box(B, "cor", xx - 0.02, xx + 0.02, 0, 2.3, zz - 0.02, zz + 0.02, (120, 122, 126))
for y0 in (0.43, 1.03, 1.63):
    for k in range(5):
        cor = [(200, 40, 40), (240, 240, 235), (40, 90, 200), (240, 200, 40), (30, 30, 30)][(k + int(y0 * 10)) % 5]
        cyl(B["cor"], 4.85, 24.2 + k * 0.3, 0.09, y0, y0 + 0.24, cor)
cyl(B["cor"], -0.6, 28.1, 0.25, 0.0, 0.8, (30, 90, 40))                            # lixeira
# (armário preto do meio e tambor tirados: atrapalhavam manobrar o carro)
# ---- cabine (sala branca de azulejo com forro de PVC)
HC = 2.8
face(B["azulejo"], "azulejo", [(LOT1, 0, ZO0), (LOT1, 0, ZC1), (LOT1, HC, ZC1), (LOT1, HC, ZO0)], (-1, 0, 0), lin((255, 255, 255)))
face(B["azulejo"], "azulejo", [(XO1, 0, ZC1 - 0.01), (LOT1, 0, ZC1 - 0.01), (LOT1, HC, ZC1 - 0.01), (XO1, HC, ZC1 - 0.01)], (0, 0, -1), lin((255, 255, 255)))
face(B["cor"], "cor", [(XO1, HC, ZC1 + 0.03), (LOT1, HC, ZC1 + 0.03), (LOT1, HO, ZC1 + 0.03), (XO1, HO, ZC1 + 0.03)], (0, 0, -1), lin(PRETO))
face(B["azulejo"], "azulejo", [(XO1, 0, ZO0 + 0.01), (LOT1, 0, ZO0 + 0.01), (LOT1, HC, ZO0 + 0.01), (XO1, HC, ZO0 + 0.01)], (0, 0, 1), lin((255, 255, 255)))
for (z0, z1) in ((ZO0, 15.0), (21.0, ZC1)):
    face(B["azulejo"], "azulejo", [(XO1 + 0.01, 0, z0), (XO1 + 0.01, 0, z1), (XO1 + 0.01, HC, z1), (XO1 + 0.01, HC, z0)], (1, 0, 0), lin((255, 255, 255)))
face(B["forro"], "forro", [(XO1, HC, ZO0), (LOT1, HC, ZO0), (LOT1, HC, ZC1), (XO1, HC, ZC1)], (0, -1, 0), lin((255, 255, 255)))
box(B, "luz", 3.2, 3.6, HC - 0.05, HC - 0.01, 17.5, 17.9, LUZ)
box(B, "cor", 4.6, 5.15, 0, 2.1, 22.0, 22.9, (230, 230, 228))     # porta branca do fundo
# paredes de fora da oficina/cabine (quem vê de fora não vê buraco)
box(B, "reboco", XC0 - 0.2, LOT1 + 0.2, 0, HO, ZO1, ZO1 + 0.2, CINZA_ESC, skip=("f",))
box(B, "reboco", LOT1, LOT1 + 0.2, 0, 3.0, 0.22, ZO1, (165, 165, 162), skip=("l",))
# laje da frente cobre só o começo do corredor (sobrado)
box(B, "laje", -4.6, LOT1, 2.62, 2.75, 0.0, ZS, (190, 186, 178), skip=())
face(B["cor"], "cor", [(XC0, 2.6, 0.22), (XC1, 2.6, 0.22), (XC1, 2.6, ZS), (XC0, 2.6, ZS)], (0, -1, 0), lin((215, 200, 160)))
# sobrado: fachada com as janelas em arco (textura própria) + laterais/fundo
DEP = ZS
ZF = 1.65
fb = B["drops_fachada"]
cs = [(X0F, Y0F, ZF), (X1F, Y0F, ZF), (X1F, Y1F, ZF), (X0F, Y1F, ZF)]
fb.quad([P(*c) for c in cs], [(0, 1), (1, 1), (1, 0), (0, 0)], lin((255, 255, 255)), P(0, 0, -1))
box(B, "parede", X0F, X1F, Y0F, Y1F, ZF, DEP, BRANCO, skip=("f", "t"))
# guarda-corpo com balaústres
ZB0, ZB1 = 0.08, 0.32
box(B, "cor", -4.6, LOT1, 2.75, 2.88, ZB0 - 0.02, ZB1 + 0.02, BRANCO)
xr = -4.45
while xr < LOT1 - 0.1:
    box(B, "cor", xr - 0.055, xr + 0.055, 2.88, 3.05, ZB0 + 0.07, ZB1 - 0.07, BRANCO)
    box(B, "cor", xr - 0.075, xr + 0.075, 3.05, 3.3, ZB0 + 0.05, ZB1 - 0.05, (240, 240, 236))
    box(B, "cor", xr - 0.04, xr + 0.04, 3.3, 3.5, ZB0 + 0.08, ZB1 - 0.08, BRANCO)
    box(B, "cor", xr - 0.065, xr + 0.065, 3.5, 3.6, ZB0 + 0.06, ZB1 - 0.06, BRANCO)
    xr += 0.215
box(B, "cor", -4.6, LOT1, 3.6, 3.66, ZB0 - 0.02, ZB1 + 0.02, (238, 236, 230))
box(B, "cor", -4.62, LOT1 + 0.02, 3.66, 3.74, ZB0 - 0.05, ZB1 + 0.05, (160, 82, 58))   # corrimão de cerâmica
# beiral com forro de PVC + testeira
face(B["forro"], "forro", [(X0F - 0.2, 5.58, -0.35), (X1F + 0.2, 5.58, -0.35), (X1F + 0.2, 5.58, ZF), (X0F - 0.2, 5.58, ZF)], (0, -1, 0), lin((255, 255, 255)))
box(B, "cor", X0F - 0.2, X1F + 0.2, 5.45, 5.72, -0.38, -0.33, (238, 238, 236))
# telhado de 4 águas
ov = 0.35
rx0, rx1, rz0, rz1, ye = X0F - 0.2, X1F + 0.2, -0.35, ZS + ov, 5.7
tp = math.tan(math.radians(20)); zm = (rz0 + rz1) / 2; yr = ye + (rz1 - rz0) / 2 * tp
tc = lin((172, 88, 58))
mb = B["telha"]
Wr = rx1 - rx0; Dr = (rz1 - rz0) / 2
mb.quad([P(rx0, ye, rz0), P(rx1, ye, rz0), P(rx1, yr, zm), P(rx0, yr, zm)], [(0, 0), (Wr / 2, 0), (Wr / 2, Dr / 2), (0, Dr / 2)], tc, P(0, 1.5, -1))
mb.quad([P(rx0, ye, rz1), P(rx1, ye, rz1), P(rx1, yr, zm), P(rx0, yr, zm)], [(0, 0), (Wr / 2, 0), (Wr / 2, Dr / 2), (0, Dr / 2)], tc, P(0, 1.5, 1))
for xx, sg in ((X0F, -1), (X1F, 1)):   # oitões
    B["reboco"].tri(P(xx, Y1F, ZF - 0.1), P(xx, Y1F, ZS), P(xx, yr - 0.15, zm), (0, 0), (1, 0), (0.5, 0.4), lin(BRANCO), P(sg, 0, 0))
# cano de descida e fios do padrão
cyl(B["cor"], -4.72, -0.12, 0.055, 0, 5.6, (150, 150, 150))
cyl(B["cor"], -0.15, -0.2, 0.05, 2.62, 5.45, (205, 205, 200))

# ------------------------------------------------------------------ portão (2 folhas que abrem)
def folha(x_a, x_b):
    m = MeshBuilder()
    Bf = {"metal": m}
    lo, hi = min(x_a, x_b), max(x_a, x_b)
    zc0, zc1 = 0.08, 0.13
    gal = (138, 143, 147)
    box(Bf, "metal", lo, lo + 0.05, 0.05, 2.2, zc0, zc1, gal)
    box(Bf, "metal", hi - 0.05, hi, 0.05, 2.2, zc0, zc1, gal)
    for yy in (0.08, 1.86, 2.15):
        box(Bf, "metal", lo, hi, yy, yy + 0.045, zc0, zc1, gal)
    xb = lo + 0.12
    while xb < hi - 0.08:
        box(Bf, "metal", xb - 0.017, xb + 0.017, 0.08, 2.2, zc0 + 0.005, zc1 - 0.005, gal)
        xb += 0.105
    # trinco no meio
    if abs(x_b - (G0 + G1) / 2) < 0.01:
        box(Bf, "metal", x_b - 0.1, x_b - 0.02, 0.9, 1.1, zc0 - 0.04, zc0, (120, 80, 50))
    return m


def node_arrays(mb, hinge_xr):
    Pp, N, UV, C, I = mb.arrays()
    t = P(hinge_xr, 0, 0.105)
    return (Pp - t.astype(np.float32), N, UV, C, I), t


mid = (G0 + G1) / 2
aE, tE = node_arrays(folha(G0, mid), G0)
aD, tD = node_arrays(folha(mid, G1), G1)

MATS = {"drops_muro": dict(tex="tex/drops_muro.png"), "reboco": dict(tex="tex/reboco.png"),
        "parede": dict(tex="tex/parede.png"), "laje": dict(tex="tex/laje.png"), "telha": dict(tex="tex/telha.png", double=True),
        "forro": dict(tex="tex/forro.png"), "cor": dict(), "drops_fachada": dict(tex="tex/drops_fachada.png"),
        "metal": dict(metal=0.7, rough=0.35), "epoxi": dict(tex="tex/epoxi.png", rough=0.22), "parede_preta": dict(tex="tex/parede_preta.png"),
        "drops_logo": dict(tex="tex/drops_logo.png", alpha=True), "drops_spray": dict(tex="tex/drops_spray.png", alpha=True),
        "madeira": dict(tex="tex/madeira.png"), "fibro": dict(tex="tex/fibro.png", double=True), "luz": dict(emissive=[1.0, 1.0, 1.0]),
        "azulejo": dict(tex="tex/azulejo.png", rough=0.3)}
write_glb(f"{OUT}/drops_garage.glb",
          [("Casa-col", B), ("PortaoEsquerdo", {"metal": aE}, tE), ("PortaoDireito", {"metal": aD}, tD)], MATS)
print("drops_garage.glb ok")
