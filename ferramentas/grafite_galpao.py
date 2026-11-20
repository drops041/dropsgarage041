"""GRAFITE DO GALPÃO — gera as texturas das paredes do galpão do encontro (tudo desenhado aqui, sem imagem de fora):
- modelos/cenario/grafite_1..4.jpg: painéis das paredes laterais (letras de grafite + carro rebaixado)
- modelos/cenario/mural_drops.jpg: parede do fundo com a logo da Drops grafitada

Uso: python3 ferramentas/grafite_galpao.py
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SAIDA = os.path.join(RAIZ, "modelos", "cenario")
FONTE = "/usr/share/fonts/opentype/inter/Inter-Black.otf"
rng = np.random.default_rng(41)


def parede(w, h, base=(58, 58, 62)):
    """reboco/bloco pintado com sujeira"""
    a = np.ones((h, w, 3)) * np.array(base, float)
    ruido = rng.normal(0, 1, (h // 4 + 1, w // 4 + 1))
    ruido = np.array(Image.fromarray(((ruido + 3) * 40).clip(0, 255).astype(np.uint8)).resize((w, h), Image.BILINEAR)) / 255.0
    a *= (0.85 + 0.3 * ruido)[..., None]
    # blocos
    for y in range(0, h, 38):
        a[y:y + 2] *= 0.82
        off = 0 if (y // 38) % 2 == 0 else 46
        for x in range(off, w, 92):
            a[y:y + 38, x:x + 2] *= 0.85
    # sujeira escorrendo de baixo
    g = np.linspace(0, 1, h)[:, None] ** 3
    a *= (1 - 0.25 * g)[..., None]
    return Image.fromarray(a.clip(0, 255).astype(np.uint8)).convert("RGBA")


def spray(img, xy, raio, cor, alfa=180):
    camada = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(camada)
    x, y = xy
    d.ellipse((x - raio, y - raio, x + raio, y + raio), fill=cor + (alfa,))
    camada = camada.filter(ImageFilter.GaussianBlur(raio * 0.45))
    img.alpha_composite(camada)


def respingos(img, cx, cy, larg, alt, cor, n=120):
    d = ImageDraw.Draw(img)
    for _ in range(n):
        x = cx + rng.normal(0, larg)
        y = cy + rng.normal(0, alt)
        r = rng.uniform(0.6, 2.6)
        d.ellipse((x - r, y - r, x + r, y + r), fill=cor + (int(rng.uniform(120, 230)),))


def escorridos(img, mascara, cor, n=14):
    """tinta escorrendo da parte de baixo das letras"""
    d = ImageDraw.Draw(img)
    m = np.array(mascara) > 128
    ys, xs = np.nonzero(m)
    if len(xs) == 0:
        return
    for _ in range(n):
        x = int(rng.choice(xs))
        col = np.nonzero(m[:, x])[0]
        y0 = col.max()
        comp = rng.uniform(12, 55)
        lw = rng.uniform(2, 4.5)
        d.line((x, y0, x, y0 + comp), fill=cor + (255,), width=int(lw))
        d.ellipse((x - lw, y0 + comp - lw, x + lw, y0 + comp + lw * 1.4), fill=cor + (255,))


def letras(img, texto, centro, altura, cores, contorno=(15, 15, 18), inclina=-6):
    """letra de grafite: sombra 3D, contorno grosso, preenchimento em degradê, brilho"""
    w, h = img.size
    fonte = ImageFont.truetype(FONTE, altura)
    tmp = Image.new("L", (w * 2, h * 2), 0)
    d = ImageDraw.Draw(tmp)
    bb = d.textbbox((0, 0), texto, font=fonte, stroke_width=0)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    pos = (w - tw // 2 - bb[0], h - th // 2 - bb[1])
    d.text(pos, texto, font=fonte, fill=255)
    tmp = tmp.rotate(inclina, resample=Image.BICUBIC, center=(w, h))
    # letras "gordinhas"
    tmp = tmp.filter(ImageFilter.MaxFilter(5))
    ox, oy = centro[0] - w, centro[1] - h
    def colar(mask, cor, dx=0, dy=0):
        camada = Image.new("RGBA", (w * 2, h * 2), cor + (255,))
        camada.putalpha(mask)
        img.alpha_composite(camada.transform((w, h), Image.AFFINE, (1, 0, -ox - dx, 0, 1, -oy - dy)))
    grosso = tmp.filter(ImageFilter.MaxFilter(15))
    # sombra 3D (várias camadas deslocadas)
    for k in range(10, 0, -1):
        colar(grosso, tuple(int(c * 0.35) for c in cores[1]), k, k)
    colar(grosso, contorno)
    # preenchimento em degradê (de cima pra baixo)
    grad = Image.new("RGBA", (w * 2, h * 2))
    ga = np.zeros((h * 2, w * 2, 4), np.uint8)
    t = np.linspace(0, 1, h * 2)[:, None]
    for c in range(3):
        ga[..., c] = (cores[0][c] * (1 - t) + cores[1][c] * t).astype(np.uint8)
    ga[..., 3] = np.array(tmp)
    grad = Image.fromarray(ga, "RGBA")
    img.alpha_composite(grad.transform((w, h), Image.AFFINE, (1, 0, -ox, 0, 1, -oy)))
    # brilho em cima de cada letra
    brilho = Image.fromarray((np.array(tmp) > 128).astype(np.uint8) * 255).filter(ImageFilter.MinFilter(9))
    br = np.array(brilho).astype(float)
    sombra_b = np.roll(br, 10, axis=0)
    br = np.clip(br - sombra_b, 0, 255).astype(np.uint8)
    colar(Image.fromarray(br).filter(ImageFilter.GaussianBlur(1.5)), (255, 255, 255))
    mask_final = Image.fromarray(np.array(grosso)).transform((w, h), Image.AFFINE, (1, 0, -ox, 0, 1, -oy))
    return mask_final


def carro(img, x, y, larg, cor, contorno=(12, 12, 14), aro=(210, 210, 215)):
    """carro rebaixado de lado (genérico), estilo desenho de grafite"""
    d = ImageDraw.Draw(img)
    s = larg / 100.0
    def P(pts):
        return [(x + px * s, y + py * s) for px, py in pts]
    corpo = P([(0, 20), (2, 12), (10, 9), (28, 7), (40, -6), (66, -7), (82, 5), (97, 8), (100, 14), (99, 22), (0, 22)])
    janela = P([(32, 6), (42, -3), (64, -4), (76, 6)])
    d.polygon(P([(0 + 2, 20 + 2), (2 + 2, 12 + 2), (10, 11), (97, 10), (102, 24), (0, 24)]), fill=(0, 0, 0, 120))
    d.polygon(corpo, fill=contorno + (255,))
    corpo_i = P([(1.8, 19.5), (3.5, 13), (11, 10.5), (29, 8.5), (41, -4.5), (65, -5.5), (81, 6.2), (96, 9.3), (98.4, 14.5), (97.6, 20.5), (1.8, 20.5)])
    d.polygon(corpo_i, fill=cor + (255,))
    d.polygon(janela, fill=(30, 40, 52, 255))
    d.line(P([(53, -4), (53, 7)]), fill=contorno + (255,), width=max(2, int(1.2 * s)))
    d.line(P([(5, 15), (95, 15)]), fill=tuple(min(255, c + 70) for c in cor) + (255,), width=max(2, int(1.0 * s)))   # friso de luz
    for cx in (20, 81):     # rodas grandes, coladas no para-lama (rebaixado)
        r = 10.5 * s
        X, Y = x + cx * s, y + 19.5 * s
        d.ellipse((X - r, Y - r, X + r, Y + r), fill=(18, 18, 20, 255))
        r2 = r * 0.68
        d.ellipse((X - r2, Y - r2, X + r2, Y + r2), fill=aro + (255,))
        for k in range(10):
            a = k * np.pi / 5
            d.line((X, Y, X + np.cos(a) * r2 * 0.95, Y + np.sin(a) * r2 * 0.95), fill=(120, 120, 128, 255), width=max(2, int(0.9 * s)))
        d.ellipse((X - r2 * 0.25, Y - r2 * 0.25, X + r2 * 0.25, Y + r2 * 0.25), fill=(40, 40, 44, 255))
    # linhas de velocidade
    for k in range(4):
        yy = y + (2 + k * 5) * s
        d.line((x - (12 + k * 6) * s, yy, x - 2 * s, yy), fill=(255, 255, 255, 170), width=max(2, int(1.1 * s)))


def estrela(img, x, y, r, cor):
    d = ImageDraw.Draw(img)
    pts = []
    for k in range(8):
        a = k * np.pi / 4
        rr = r if k % 2 == 0 else r * 0.3
        pts.append((x + np.cos(a) * rr, y + np.sin(a) * rr))
    d.polygon(pts, fill=cor + (255,))


def painel(nome, texto, cores, cor_carro, lado_carro, extra):
    W, H = 1024, 420
    img = parede(W, H, extra.get("base", (60, 60, 64)))
    for _ in range(9):
        spray(img, (rng.uniform(0, W), rng.uniform(40, H - 40)), rng.uniform(40, 110), tuple(int(c) for c in rng.choice(np.array(cores + [cor_carro]))), 70)
    cx = W * (0.62 if lado_carro == "esq" else 0.38)
    mask = letras(img, texto, (int(cx), 150), extra.get("tam", 150), cores, inclina=extra.get("incl", -6))
    escorridos(img, mask, cores[1])
    respingos(img, cx, 150, 160, 60, cores[0])
    xc = 40 if lado_carro == "esq" else W - 40 - 330
    carro(img, xc, 270, 330, cor_carro)
    for _ in range(6):
        estrela(img, rng.uniform(20, W - 20), rng.uniform(20, 110), rng.uniform(8, 18), (255, 255, 255))
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FONTE, 26)
    d.text((W - 210, H - 44), extra.get("assina", "CWB  41"), font=f, fill=(250, 250, 250, 220))
    img.convert("RGB").save(os.path.join(SAIDA, nome), quality=88)


def mural():
    W, H = 2048, 340
    img = parede(W, H, (28, 28, 32))
    for _ in range(26):
        spray(img, (rng.uniform(0, W), rng.uniform(20, H - 20)), rng.uniform(50, 130),
              tuple(int(c) for c in [(255, 212, 0), (230, 40, 120), (0, 200, 255), (130, 60, 255)][rng.integers(0, 4)]), 60)
    logo = Image.open(os.path.join(RAIZ, "mapa_cic", "blocos", "tex", "drops_logo.png")).convert("RGBA")
    lh = 300
    lw = int(logo.size[0] * lh / logo.size[1])
    logo = logo.resize((lw, lh), Image.LANCZOS)
    # sombra e brilho em volta da logo
    a = np.array(logo)[..., 3]
    sombra = Image.fromarray(a).filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(6))
    camada = Image.new("RGBA", logo.size, (0, 0, 0, 255))
    camada.putalpha(sombra)
    img.alpha_composite(camada, ((W - lw) // 2 + 10, (H - lh) // 2 + 10))
    brilho = Image.new("RGBA", logo.size, (255, 212, 0, 255))
    brilho.putalpha(Image.fromarray(a).filter(ImageFilter.MaxFilter(15)).filter(ImageFilter.GaussianBlur(14)).point(lambda v: v * 0.6))
    img.alpha_composite(brilho, ((W - lw) // 2, (H - lh) // 2))
    img.alpha_composite(logo, ((W - lw) // 2, (H - lh) // 2))
    respingos(img, W / 2, H / 2, 300, 90, (255, 212, 0), 260)
    carro(img, 90, 200, 380, (255, 212, 0))
    carro(img, W - 90 - 380, 200, 380, (230, 40, 120))
    letras(img, "ENCONTRO", (300, 80), 70, [(255, 255, 255), (0, 200, 255)], inclina=-4)
    letras(img, "REBAIXADOS", (W - 330, 80), 64, [(255, 255, 255), (255, 120, 0)], inclina=4)
    img.convert("RGB").save(os.path.join(SAIDA, "mural_drops.jpg"), quality=88)


def main():
    painel("grafite_1.jpg", "SOCADO", [(255, 230, 40), (255, 90, 0)], (0, 190, 255), "esq", dict(assina="DROPS 41"))
    painel("grafite_2.jpg", "CIC", [(120, 255, 200), (0, 150, 255)], (230, 40, 120), "dir", dict(tam=200, incl=4, base=(70, 66, 60)))
    painel("grafite_3.jpg", "NO CHÃO", [(255, 120, 220), (150, 30, 230)], (255, 212, 0), "esq", dict(tam=120, incl=-3, base=(52, 56, 66)))
    painel("grafite_4.jpg", "CWB", [(255, 255, 255), (255, 40, 60)], (40, 220, 90), "dir", dict(tam=190, incl=-8, assina="REBAIXA"))
    mural()
    print("ok: grafite_1..4.jpg e mural_drops.jpg em", SAIDA)


if __name__ == "__main__":
    main()
