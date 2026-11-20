"""Fotos dos projetos da Drops (do dono da oficina) -> quadros das paredes dos encontros e tela da TV da sala gamer.
- tira as faixas pretas dos prints do celular
- quadros: 1280 de altura, proporção da foto (projeto_1..5.jpg em modelos/cenario; o jogo faz a moldura do tamanho certo)
- TV: recorte 16:9 do Corsa com o "Keep the style" (ferramentas/fontes/tv_corsa.jpg; o criar_sala_gamer.py usa)
Uso: python3 ferramentas/fotos_projetos.py foto1.jpg ... foto5.jpg --tv foto_tv.jpg"""
import os
import sys

import numpy as np
from PIL import Image

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def sem_faixas(im):
    a = np.asarray(im.convert("L"), np.float32)
    col = a.mean(0)
    lin = a.mean(1)
    xs = np.where(col > 14)[0]
    ys = np.where(lin > 14)[0]
    return im.crop((int(xs[0]), int(ys[0]), int(xs[-1]) + 1, int(ys[-1]) + 1))


def recorte(im, prop, cy=0.5):
    w, h = im.size
    if w / h > prop:
        nw = int(h * prop)
        x = (w - nw) // 2
        return im.crop((x, 0, x + nw, h))
    nh = int(w / prop)
    y = int(np.clip(cy * h - nh / 2, 0, h - nh))
    return im.crop((0, y, w, y + nh))


def main(fotos, tv):
    cen = os.path.join(RAIZ, "modelos", "cenario")
    for i, f in enumerate(fotos, 1):
        im = sem_faixas(Image.open(f).convert("RGB"))
        im.resize((int(round(im.size[0] * 1280 / im.size[1])), 1280), Image.LANCZOS).save(os.path.join(cen, "projeto_%d.jpg" % i), quality=86)
        print("projeto_%d.jpg <- %s %s" % (i, os.path.basename(f), im.size))
    if tv:
        im = sem_faixas(Image.open(tv).convert("RGB"))
        # o carro + o grafite DROPS GARAGE ficam entre 28% e 60% da altura da foto
        recorte(im, 16 / 9, 0.445).resize((1280, 720), Image.LANCZOS).save(os.path.join(RAIZ, "ferramentas", "fontes", "tv_corsa.jpg"), quality=90)
        print("tv_corsa.jpg <-", os.path.basename(tv))


if __name__ == "__main__":
    a = sys.argv[1:]
    tv = None
    if "--tv" in a:
        i = a.index("--tv")
        tv = a[i + 1]
        a = a[:i] + a[i + 2:]
    main(a, tv)
