"""Gera os panoramas (2:1) que os carros refletem: estúdio da garagem e fim de tarde da rua.
Uso: python3 ferramentas/panoramas.py   (grava em imagens/reflexo/)"""
import numpy as np
from PIL import Image, ImageFilter
import os

W, H = 1024, 512
DEST = os.path.join(os.path.dirname(__file__), "..", "imagens", "reflexo")
u = (np.arange(W) + 0.5) / W
v = (np.arange(H) + 0.5) / H
U, V = np.meshgrid(u, v)
lon = (U - 0.5) * 2 * np.pi          # 0 = -z (frente)
lat = (0.5 - V) * np.pi              # +90 = cima
dx, dy, dz = np.cos(lat) * np.sin(lon), np.sin(lat), -np.cos(lat) * np.cos(lon)


def caixa_luz(img, lon0, lat0, w, h, cor, borda=0.02):
    """retângulo de luz (softbox) em graus"""
    a = np.abs(((np.degrees(lon) - lon0 + 180) % 360) - 180)
    b = np.abs(np.degrees(lat) - lat0)
    m = np.clip((w / 2 - a) / (w * borda + 0.5), 0, 1) * np.clip((h / 2 - b) / (h * borda + 0.5), 0, 1)
    img += m[..., None] * np.array(cor)


def salvar(img, nome, blur=1.2):
    im = Image.fromarray((np.clip(img, 0, 1) ** (1 / 2.2) * 255).astype(np.uint8))
    im = im.filter(ImageFilter.GaussianBlur(blur))
    im.save(os.path.join(DEST, nome))
    print("ok", nome)


# ---------------------------------------------------------------- estúdio (garagem)
est = np.zeros((H, W, 3))
teto = np.clip(dy, 0, 1)
chao = np.clip(-dy, 0, 1)
est += (0.018 + 0.03 * teto)[..., None]                       # parede escura
est += (np.exp(-np.abs(dy) * 5) * 0.22)[..., None] * np.array([1.0, 0.97, 0.92])   # faixa clara no horizonte (paredes iluminadas)
est[dy < 0] = (0.035 + 0.07 * np.exp(-chao * 3))[dy < 0][..., None] * np.array([1, 1, 1.02])  # chão de cimento claro
# softbox grande em cima + duas tiras laterais longas (o "risco" de luz que marca a lataria)
caixa_luz(est, 0, 72, 120, 18, [3.0, 3.0, 3.0])
caixa_luz(est, 180, 72, 120, 18, [2.6, 2.6, 2.7])
for lo in (-90, 90):
    caixa_luz(est, lo, 28, 150, 7, [2.2, 2.2, 2.25])
    caixa_luz(est, lo, 8, 70, 30, [0.35, 0.36, 0.40])
# toque da marca (amarelo) no fundo e porta de enrolar
caixa_luz(est, 180, 30, 40, 22, [0.55, 0.42, 0.0])
caixa_luz(est, 0, 18, 70, 36, [0.10, 0.10, 0.11])
salvar(est, "estudio.png")

# ---------------------------------------------------------------- rua (fim de tarde, mesmo céu do jogo)
rua = np.zeros((H, W, 3))
topo = np.array([0x3d, 0x5f, 0x9e]) / 255.0
hor = np.array([0xf2, 0xa5, 0x6b]) / 255.0
c = np.clip(dy, 0, 1) ** 0.45
ceu = hor[None, None] * (1 - c[..., None]) + topo[None, None] * c[..., None]
rua[:] = ceu
# sol baixo
sol_dir = np.array([np.cos(np.radians(8)) * np.sin(np.radians(-60)), np.sin(np.radians(8)), -np.cos(np.radians(8)) * np.cos(np.radians(-60))])
cs = dx * sol_dir[0] + dy * sol_dir[1] + dz * sol_dir[2]
rua += (np.clip(cs, 0, 1) ** 400 * 6 + np.clip(cs, 0, 1) ** 12 * 0.5)[..., None] * np.array([1.0, 0.8, 0.55])
# casas e muros no horizonte (silhueta com cores variadas)
rng = np.random.default_rng(3)
alt = np.zeros(W)
x = 0
while x < W:
    w = rng.integers(14, 40)
    alt[x:x + w] = rng.uniform(2.5, 9.0) * (1.5 if rng.random() < 0.15 else 1.0)
    x += w
cores = rng.uniform(0.25, 0.75, (W, 3)) * np.array([1.0, 0.9, 0.8])
for x in range(0, W, 30):
    cores[x:x + 30] = rng.uniform(0.25, 0.8, 3) * np.array([1.0, 0.92, 0.82])
lat_d = np.degrees(lat)
casa = (lat_d > -2) & (lat_d < alt[None, :])
rua[casa] = (cores[None, :, :].repeat(H, 0) * 0.45)[casa]
# poste/fio ocasional
# chão: asfalto escuro perto, calçada mais clara no horizonte
ch = lat_d <= -2
g = np.clip(-dy, 0, 1)
asfalto = (0.05 + 0.10 * np.exp(-g * 4))[..., None] * np.array([0.95, 0.9, 0.95])
rua[ch] = asfalto[ch]
salvar(rua, "rua.png", blur=0.8)
