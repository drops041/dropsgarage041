"""Deixa um .glb leve: as imagens PNG viram JPEG (as que não precisam de transparência) e as maiores
que --max px diminuem. Godot lê JPEG dentro do .glb sem problema.
Uso: python3 ferramentas/imagens_jpg.py entrada.glb saida.glb [--max 1024] [--q 85]"""
import io
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB  # noqa: E402


def main():
    a = sys.argv[1:]
    ent, sai = a[0], a[1]
    mx = int(a[a.index("--max") + 1]) if "--max" in a else 1024
    q = int(a[a.index("--q") + 1]) if "--q" in a else 85
    g = GLB(ent)
    j = g.j
    alfa = set()   # imagens usadas como cor de material transparente
    for m in j.get("materials", []):
        if m.get("alphaMode", "OPAQUE") != "OPAQUE":
            t = m.get("pbrMetallicRoughness", {}).get("baseColorTexture")
            if t is not None:
                alfa.add(j["textures"][t["index"]]["source"])
    antes = depois = 0
    for k, im in enumerate(j.get("images", [])):
        if "bufferView" not in im:
            continue
        b = g.view_bytes(im["bufferView"])
        antes += len(b)
        img = Image.open(io.BytesIO(b))
        img.load()
        if max(img.size) > mx:
            f = mx / max(img.size)
            img = img.resize((max(1, int(img.size[0] * f)), max(1, int(img.size[1] * f))), Image.LANCZOS)
        out = io.BytesIO()
        if k in alfa:
            img.save(out, "PNG", optimize=True)
            im["mimeType"] = "image/png"
        else:
            img.convert("RGB").save(out, "JPEG", quality=q, optimize=True)
            im["mimeType"] = "image/jpeg"
        im.pop("uri", None)
        im["bufferView"] = g.add_view(out.getvalue())
        depois += len(out.getvalue())
    g.salvar(sai)
    print("imagens: %.1f MB -> %.1f MB" % (antes / 1e6, depois / 1e6))


main()
