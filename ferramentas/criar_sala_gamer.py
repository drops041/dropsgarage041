"""SALA GAMER no fundo da oficina da Drops (a partir do GAMINGROOMLOWPOLYLESTRIX.blend que o dono mandou).
- converte o .blend sem Blender (blend_para_glb), já na posição da Drops (coordenadas locais da oficina)
- parede da TV encostada no fundo, parede dos quadros encostada na esquerda; corta o pedaço que entraria na cabine
- as imagens originais não vieram no arquivo: TV mostra a tela do jogo, quadros viram grafites do galpão
Saída: modelos/cenario/sala_gamer.glb

Uso: python3 ferramentas/criar_sala_gamer.py
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
from blend_para_glb import converter  # noqa: E402

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BLEND = "/mnt/user-data/uploads/48f142e3-GAMINGROOMLOWPOLYLESTRIX.blend"
ESC = 2.6                 # o modelo é uma maquete (~0,85 de pé-direito)
OX = -5.2 + 1.1 * ESC     # parede dos quadros (z do modelo = -1,1) na parede esquerda da oficina (x = -5,2)
OZ = 28.5 - 0.41 * ESC    # parede da TV (x do modelo = -0,41) no fundo (z = 28,5)
OY = 0.03 - 0.02 * ESC    # piso da sala rente ao epóxi
TMP = "/tmp/sala_gamer"
FONTE = "/usr/share/fonts/opentype/inter/Inter-Black.otf"


def tela_tv(arq):
    W, H = 1280, 720
    img = Image.new("RGB", (W, H))
    a = np.zeros((H, W, 3))
    t = np.linspace(0, 1, H)[:, None]
    a[..., 0] = 20 + 40 * t
    a[..., 1] = 10 + 10 * t
    a[..., 2] = 45 + 60 * (1 - t)
    img = Image.fromarray(a.astype(np.uint8)).convert("RGBA")
    logo = Image.open(os.path.join(RAIZ, "mapa_cic", "blocos", "tex", "drops_logo.png")).convert("RGBA")
    lh = 380
    logo = logo.resize((int(logo.size[0] * lh / logo.size[1]), lh), Image.LANCZOS)
    brilho = Image.new("RGBA", logo.size, (255, 212, 0, 255))
    brilho.putalpha(logo.split()[3].filter(ImageFilter.GaussianBlur(18)))
    x = (W - logo.size[0]) // 2
    img.alpha_composite(brilho, (x, 70))
    img.alpha_composite(logo, (x, 70))
    d = ImageDraw.Draw(img)
    f1 = ImageFont.truetype(FONTE, 74)
    f2 = ImageFont.truetype(FONTE, 34)
    for txt, f, y, cor in (("RACHA", f1, 470, (255, 212, 0)), ("APERTE  START", f2, 600, (255, 255, 255))):
        w = d.textlength(txt, font=f)
        d.text(((W - w) / 2 + 4, y + 4), txt, font=f, fill=(0, 0, 0))
        d.text(((W - w) / 2, y), txt, font=f, fill=cor)
    img.convert("RGB").save(arq, quality=90)


def quadro(origem, arq, recorte):
    im = Image.open(origem)
    w, h = im.size
    im.crop((int(recorte[0] * w), 0, int(recorte[1] * w), h)).resize((512, 680)).save(arq, quality=88)


def main():
    os.makedirs(TMP, exist_ok=True)
    tv = os.path.join(TMP, "tv.jpg")
    # (v38) na TV vai a foto do Corsa na Drops ("Keep the style") — feita pelo fotos_projetos.py
    foto = os.path.join(RAIZ, "ferramentas", "fontes", "tv_corsa.jpg")
    if os.path.exists(foto):
        Image.open(foto).convert("RGB").save(tv, quality=92)
    else:
        tela_tv(tv)
    cen = os.path.join(RAIZ, "modelos", "cenario")
    q1, q2, q3 = (os.path.join(TMP, "q%d.jpg" % k) for k in (1, 2, 3))
    quadro(os.path.join(cen, "grafite_1.jpg"), q1, (0.42, 0.82))
    quadro(os.path.join(cen, "grafite_3.jpg"), q2, (0.0, 0.42))
    quadro(os.path.join(cen, "grafite_4.jpg"), q3, (0.3, 0.7))
    logo = os.path.join(TMP, "logo.png")
    Image.open(os.path.join(RAIZ, "mapa_cic", "blocos", "tex", "drops_logo.png")).save(logo)
    # as telas/quadros do modelo têm a coordenada de textura espelhada: espelha as imagens antes
    for arq in (tv, logo):
        Image.open(arq).transpose(Image.FLIP_LEFT_RIGHT).save(arq)

    def xf(P):
        # giro de 90° (parede da TV vai pro fundo, a dos quadros pra esquerda) + posição na oficina
        return np.stack([P[:, 2] * ESC + OX, P[:, 1] * ESC + OY, -P[:, 0] * ESC + OZ], 1)

    def corta(t):
        # o que entraria na cabine de pintura (atrás dela)
        return bool((t[:, 2] < 23.55).all() and (t[:, 0] < -1.6).all())

    converter(BLEND, os.path.join(cen, "sala_gamer.glb"), 1.0, xf=xf, corta=corta,
              pular=("GA_stones",), subdiv_max=400,
              tons={"cactus_gasteria": (0.12, 0.35, 0.12), "vase_gasteria": (0.1, 0.25, 0.6), "Material.018": (0.05, 0.05, 0.06)},
              imagens={"Material.021": tv, "Material.022": tv, "Material.003": q1, "Material.005": q2, "Material.007": q3,
                       "Material.009": logo})


if __name__ == "__main__":
    main()
