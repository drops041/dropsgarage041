"""Texturas novas (v24): detalhe do chão, folhas das árvores e placas de trânsito."""
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import cv2

FONTE = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def _tileable_noise(n, cells, rng):
    g = rng.random((cells, cells)).astype(np.float32)
    g = np.tile(g, (3, 3))
    big = cv2.resize(g, (n * 3, n * 3), interpolation=cv2.INTER_CUBIC)
    return big[n:2 * n, n:2 * n]


def _fbm(n, rng, base=4, oct=5):
    out = np.zeros((n, n), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(oct):
        out += _tileable_noise(n, base * 2 ** o, rng) * amp
        tot += amp
        amp *= 0.55
    out /= tot
    return (out - out.min()) / (out.max() - out.min() + 1e-6)


def detalhe_chao(rng, n=512):
    """R = asfalto (brita, remendos, rachaduras, marcas de pneu), G = calçada (petit-pavé/pedrinhas), B = grama.
    Valor 128 = neutro; o shader multiplica a cor do chão por isso."""
    # --- asfalto
    brita = rng.random((n, n)).astype(np.float32)
    brita = cv2.GaussianBlur(brita, (0, 0), 0.6)
    remendo = _fbm(n, rng, 3, 4)
    a = 0.5 + (brita - 0.5) * 0.55 + (remendo - 0.5) * 0.35
    # pedrinhas claras soltas
    pts = rng.integers(0, n, (2600, 2))
    for x, y in pts:
        a[y, x] = min(1.0, a[y, x] + rng.uniform(0.15, 0.35))
    # rachaduras finas
    img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    for _ in range(9):
        x, y = rng.integers(0, n, 2)
        ang = rng.uniform(0, np.pi)
        pts = [(int(x), int(y))]
        for _ in range(rng.integers(6, 14)):
            ang += rng.uniform(-0.7, 0.7)
            x = x + np.cos(ang) * rng.uniform(6, 18)
            y = y + np.sin(ang) * rng.uniform(6, 18)
            pts.append((int(x) % n, int(y) % n))
        for p0, p1 in zip(pts[:-1], pts[1:]):
            if abs(p0[0] - p1[0]) < n / 2 and abs(p0[1] - p1[1]) < n / 2:
                d.line([p0, p1], fill=40, width=1)
    a = np.asarray(img).astype(np.float32) / 255.0
    # --- calçada: pedrinhas irregulares (petit-pavé de Curitiba) com rejunte escuro
    pedras = np.full((n, n), 0.62, np.float32)
    k = 0
    pi = Image.new("L", (n, n), 70)
    dp = ImageDraw.Draw(pi)
    passo = 14
    for gy in range(0, n, passo):
        for gx in range(0, n, passo):
            cx = gx + rng.uniform(-3, 3) + passo / 2
            cy = gy + rng.uniform(-3, 3) + passo / 2
            r = passo * rng.uniform(0.38, 0.5)
            poly = []
            for t in range(6):
                an = t / 6 * 2 * np.pi + rng.uniform(-0.3, 0.3)
                rr = r * rng.uniform(0.75, 1.1)
                poly.append((cx + np.cos(an) * rr, cy + np.sin(an) * rr))
            v = int(rng.uniform(140, 205))
            for ox in (-n, 0, n):
                for oy in (-n, 0, n):
                    dp.polygon([(px + ox, py + oy) for px, py in poly], fill=v)
    c = np.asarray(pi.filter(ImageFilter.GaussianBlur(0.7))).astype(np.float32) / 255.0
    c = 0.5 + (c - 0.55) * 0.9
    # --- grama: lâminas finas + manchas
    gr = _fbm(n, rng, 6, 5)
    lam = rng.random((n, n)).astype(np.float32)
    lam = cv2.GaussianBlur(lam, (1, 7), 0)
    g = 0.5 + (gr - 0.5) * 0.45 + (lam - 0.5) * 0.7
    out = np.stack([np.clip(a, 0, 1), np.clip(c, 0, 1), np.clip(g, 0, 1)], -1)
    return (out * 255).astype(np.uint8)


def folhas(rng, n=512):
    """copa de árvore em cards: cachos de folhas com transparência (verde claro neutro, a cor vem do vértice)"""
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = n / 2
    for _ in range(4200):
        # mais folha no meio, borda irregular
        r = (rng.random() ** 0.6) * n * 0.47
        an = rng.uniform(0, 2 * np.pi)
        x = c + np.cos(an) * r
        y = c + np.sin(an) * r * 0.92
        borda = r / (n * 0.47)
        if borda > 0.82 and rng.random() < 0.45:
            continue
        s = rng.uniform(5, 11)
        ang = rng.uniform(0, np.pi)
        luz = 1.0 - 0.45 * ((y - (c - n * 0.4)) / (n * 0.9))   # mais claro em cima
        v = rng.uniform(0.55, 1.0) * luz
        cor = (int(150 * v + 40), int(205 * v + 30), int(120 * v + 25), 255)
        dx, dy = np.cos(ang) * s, np.sin(ang) * s * 0.45
        d.ellipse([x - abs(dx) - 2, y - abs(dy) - 2, x + abs(dx) + 2, y + abs(dy) + 2], fill=cor)
    # galhos aparecendo no meio
    for _ in range(7):
        an = rng.uniform(0, 2 * np.pi)
        d.line([(c, c + n * 0.12), (c + np.cos(an) * n * 0.25, c + np.sin(an) * n * 0.2)], fill=(70, 55, 40, 255), width=4)
    return np.asarray(img)


def araucaria(rng, n=512):
    """galhos de araucária vistos de cima (candelabro): tufos nas pontas dos galhos"""
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = n / 2
    for k in range(14):
        an = k / 14 * 2 * np.pi + rng.uniform(-0.1, 0.1)
        ex, ey = c + np.cos(an) * n * 0.42, c + np.sin(an) * n * 0.42
        d.line([(c, c), (ex, ey)], fill=(80, 62, 45, 255), width=5)
        for _ in range(170):
            t = rng.uniform(0.5, 1.0)
            x = c + (ex - c) * t + rng.normal(0, 9)
            y = c + (ey - c) * t + rng.normal(0, 9)
            v = rng.uniform(0.6, 1.0)
            d.line([(x, y), (x + rng.normal(0, 5), y + rng.normal(0, 5))], fill=(int(70 * v), int(120 * v), int(60 * v), 255), width=4)
    return np.asarray(img)


def _fonte(t):
    return ImageFont.truetype(FONTE, t)


def placas(n=256):
    """atlas 8x1: 0 PARE, 1 LOMBADA, 2 vel 40, 3 vel 60, 4 PARE no chão, 5 verso de placa, 6 faixa (zebra), 7 livre"""
    atlas = Image.new("RGBA", (n * 8, n), (0, 0, 0, 0))
    # 0 PARE (octógono)
    a = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(a)
    oc = [(n / 2 + np.cos(np.pi / 8 + k * np.pi / 4) * n * 0.48, n / 2 + np.sin(np.pi / 8 + k * np.pi / 4) * n * 0.48) for k in range(8)]
    d.polygon(oc, fill=(245, 245, 245, 255))
    oc2 = [(n / 2 + np.cos(np.pi / 8 + k * np.pi / 4) * n * 0.44, n / 2 + np.sin(np.pi / 8 + k * np.pi / 4) * n * 0.44) for k in range(8)]
    d.polygon(oc2, fill=(200, 22, 30, 255))
    f = _fonte(int(n * 0.27))
    w = d.textlength("PARE", font=f)
    d.text((n / 2 - w / 2, n / 2 - n * 0.16), "PARE", font=f, fill=(255, 255, 255, 255))
    atlas.paste(a, (0, 0))
    # 1 LOMBADA (losango amarelo)
    a = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(a)
    d.polygon([(n / 2, 4), (n - 4, n / 2), (n / 2, n - 4), (4, n / 2)], fill=(20, 20, 20, 255))
    d.polygon([(n / 2, 14), (n - 14, n / 2), (n / 2, n - 14), (14, n / 2)], fill=(250, 200, 20, 255))
    d.arc([n * 0.28, n * 0.42, n * 0.72, n * 0.82], 200, 340, fill=(20, 20, 20, 255), width=int(n * 0.05))
    d.line([(n * 0.24, n * 0.6), (n * 0.76, n * 0.6)], fill=(20, 20, 20, 255), width=int(n * 0.03))
    f = _fonte(int(n * 0.085))
    w = d.textlength("LOMBADA", font=f)
    d.text((n / 2 - w / 2, n * 0.3), "LOMBADA", font=f, fill=(20, 20, 20, 255))
    atlas.paste(a, (n, 0))
    # 2,3 velocidade
    for i, v in ((2, "40"), (3, "60")):
        a = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        d = ImageDraw.Draw(a)
        d.ellipse([4, 4, n - 4, n - 4], fill=(205, 25, 30, 255))
        d.ellipse([n * 0.13, n * 0.13, n * 0.87, n * 0.87], fill=(250, 250, 250, 255))
        f = _fonte(int(n * 0.36))
        w = d.textlength(v, font=f)
        d.text((n / 2 - w / 2, n / 2 - n * 0.22), v, font=f, fill=(20, 20, 20, 255))
        f2 = _fonte(int(n * 0.08))
        w2 = d.textlength("km/h", font=f2)
        d.text((n / 2 - w2 / 2, n * 0.66), "km/h", font=f2, fill=(20, 20, 20, 255))
        atlas.paste(a, (n * i, 0))
    # 4 PARE pintado no chão (letras compridas: o motorista vê de longe)
    a = Image.new("RGBA", (n, n * 3), (0, 0, 0, 0))
    d = ImageDraw.Draw(a)
    f = _fonte(int(n * 0.36))
    w = d.textlength("PARE", font=f)
    d.text((n / 2 - w / 2, n * 0.05), "PARE", font=f, fill=(240, 240, 238, 255))
    a = a.crop((0, 0, n, int(n * 0.5))).resize((n, n))
    atlas.paste(a, (n * 4, 0))
    # 5 verso cinza (metal) — 6 zebra branca
    a = Image.new("RGBA", (n, n), (150, 152, 156, 255))
    atlas.paste(a, (n * 5, 0))
    a = Image.new("RGBA", (n, n), (240, 240, 236, 255))
    atlas.paste(a, (n * 6, 0))
    return np.asarray(atlas)


def salvar_todas(pasta, seed=11):
    rng = np.random.default_rng(seed)
    Image.fromarray(detalhe_chao(rng)).save(f"{pasta}/detalhe.png")
    Image.fromarray(folhas(rng)).save(f"{pasta}/folhas.png")
    Image.fromarray(araucaria(rng)).save(f"{pasta}/araucaria.png")
    Image.fromarray(placas()).save(f"{pasta}/placas.png")


if __name__ == "__main__":
    import sys
    salvar_todas(sys.argv[1])
