#!/usr/bin/env python3
"""Gera o ambiente de estúdio (HDR equirretangular) que ilumina e reflete nos carros da garagem:
fundo grafite, chão escuro, softbox grande em cima, duas faixas de luz nas laterais, luz quente na frente
e contraluz atrás — o "showroom" dos jogos de carro. Também sai uma versão PNG pro modo Compatibilidade.
uso: gerar_estudio_hdr.py pasta_saida"""
import sys, os
import numpy as np
from PIL import Image

W, H = 1024, 512
saida = sys.argv[1]
u = (np.arange(W) + 0.5) / W
v = (np.arange(H) + 0.5) / H
U, V = np.meshgrid(u, v)
lon = (U - 0.5) * 2 * np.pi          # -pi..pi  (0 = frente, -z)
lat = (0.5 - V) * np.pi              # +pi/2 em cima
d = np.stack([np.cos(lat) * np.sin(lon), np.sin(lat), -np.cos(lat) * np.cos(lon)], -1)

img = np.zeros((H, W, 3), np.float32)
# fundo: grafite com degradê (mais claro no horizonte), chão bem escuro
ceu = 0.035 + 0.03 * np.exp(-np.abs(lat) * 4.0)
img[:] = ceu[..., None] * np.array([1.0, 1.0, 1.05])
chao = lat < 0
img[chao] = (0.018 + 0.02 * np.exp(lat[chao] * 6.0))[..., None] * np.array([1.0, 1.0, 1.0])


def softbox(centro, largura, altura, forca, cor=(1, 1, 1), borda=0.02):
    """retângulo de luz no céu: centro = (lon, lat) em graus, largura/altura em graus"""
    lo0, la0 = np.radians(centro[0]), np.radians(centro[1])
    dl = (lon - lo0 + np.pi) % (2 * np.pi) - np.pi
    dla = lat - la0
    w2, h2 = np.radians(largura) / 2, np.radians(altura) / 2
    # borda suave
    mx = np.clip((w2 - np.abs(dl * np.cos(lat))) / np.radians(max(borda * 100, 0.5)), 0, 1)
    my = np.clip((h2 - np.abs(dla)) / np.radians(max(borda * 100, 0.5)), 0, 1)
    m = (mx * my)[..., None]
    img[:] += m * forca * np.array(cor, np.float32)


softbox((0, 80), 360, 12, 3.5)                    # teto de softbox (faixa em volta do zênite)
softbox((0, 58), 90, 7, 9.0)                      # softbox comprido em cima, na frente (a faixa no capô)
softbox((180, 58), 90, 7, 8.0)                    # e atrás
softbox((90, 22), 50, 6, 6.0)                     # faixa comprida na lateral direita (linha na porta)
softbox((-90, 22), 50, 6, 6.0)                    # e na esquerda
softbox((35, 10), 22, 14, 2.4, (1.0, 0.86, 0.68)) # luz quente na frente-esquerda
softbox((-150, 12), 26, 10, 2.0, (0.75, 0.85, 1.0))   # contraluz azulado atrás
softbox((0, 2), 360, 1.2, 0.6)                    # risco de luz no horizonte (linha de reflexo na lataria)
img[:] += np.where(d[..., 1:2] > 0.985, 9.0, 0.0)    # ponto forte bem em cima


def salvar_hdr(caminho, im):
    m = im.max(-1)
    e = np.ceil(np.log2(np.maximum(m, 1e-32)))
    esc = np.where(m > 1e-32, 256.0 / np.exp2(e), 0.0)
    rgbe = np.zeros(im.shape[:2] + (4,), np.uint8)
    rgbe[..., :3] = np.clip(im * esc[..., None], 0, 255).astype(np.uint8)
    rgbe[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8)
    with open(caminho, 'wb') as f:
        f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (im.shape[0], im.shape[1]))
        f.write(rgbe.tobytes())


salvar_hdr(os.path.join(saida, 'estudio.hdr'), img)
ldr = img / (1.0 + img) * 1.6                     # versão PNG (tonemap simples) pro modo Compatibilidade
Image.fromarray(np.uint8(np.clip(ldr ** (1 / 2.2), 0, 1) * 255)).save(os.path.join(saida, 'estudio_ldr.png'))
print('ok', img.max(), img.mean())
