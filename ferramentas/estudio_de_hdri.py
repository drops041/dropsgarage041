#!/usr/bin/env python3
"""Transforma um HDRI de estúdio (Poly Haven, CC0) no estúdio da garagem: escurece paredes e chão (fica só a luz
dos softboxes, o "showroom escuro" dos jogos de carro) e soma uma faixa de luz em cima (marca capô e teto).
uso: estudio_de_hdri.py entrada.hdr pasta_saida [giro_graus]"""
import sys, os
import numpy as np, cv2
from PIL import Image

ent, saida = sys.argv[1], sys.argv[2]
giro = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
im = cv2.imread(ent, cv2.IMREAD_ANYDEPTH | cv2.IMREAD_COLOR)[:, :, ::-1].astype(np.float32)
H, W = im.shape[:2]
if giro:
    im = np.roll(im, int(round(giro / 360.0 * W)), axis=1)
L = im @ np.array([0.2126, 0.7152, 0.0722], np.float32)
t = np.clip((L - 1.5) / 3.5, 0, 1)
k = 0.12 + 0.88 * t * t * (3 - 2 * t)
im = im * k[..., None]
# faixa de softbox em cima (comprida, de frente pra trás) e um ponto forte no topo
v = (np.arange(H) + 0.5) / H
u = (np.arange(W) + 0.5) / W
U, V = np.meshgrid(u, v)
lat = (0.5 - V) * 180.0
lon = (U - 0.5) * 360.0
faixa = (np.abs(lat - 62) < 4.0) & ((np.abs(lon) < 50) | (np.abs(np.abs(lon) - 180) < 50))
im[faixa] += 6.0
im[lat > 84] += 4.0


def salvar_hdr(caminho, x):
    m = x.max(-1)
    e = np.ceil(np.log2(np.maximum(m, 1e-32)))
    esc = np.where(m > 1e-32, 256.0 / np.exp2(e), 0.0)
    rgbe = np.zeros(x.shape[:2] + (4,), np.uint8)
    rgbe[..., :3] = np.clip(x * esc[..., None], 0, 255).astype(np.uint8)
    rgbe[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8)
    with open(caminho, 'wb') as f:
        f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % x.shape[:2])
        f.write(rgbe.tobytes())


salvar_hdr(os.path.join(saida, 'estudio.hdr'), im)
ldr = im / (1.0 + im) * 1.6
Image.fromarray(np.uint8(np.clip(ldr ** (1 / 2.2), 0, 1) * 255)).save(os.path.join(saida, 'estudio_ldr.png'))
print('ok', im.shape, float(im.max()), float(im.mean()))
