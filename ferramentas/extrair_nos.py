"""Tira só alguns objetos de um .glb grande (ex.: uma árvore de um pacote com várias) e grava um .glb leve.
Uso: python3 ferramentas/extrair_nos.py ENTRADA.glb SAIDA.glb "Leaf_6.001,Bark_9.001" [--textura 1024]
- junta os objetos escolhidos, põe o pé no chão (y=0) e centraliza no x/z
- só leva os materiais, texturas e imagens que esses objetos usam (e diminui as imagens)"""
import argparse, io, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB


def _indices_textura(obj, achados):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k.endswith("Texture") and isinstance(v, dict) and "index" in v:
                achados.append(v)
            else:
                _indices_textura(v, achados)
    elif isinstance(obj, list):
        for v in obj:
            _indices_textura(v, achados)
    return achados


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("entrada"); ap.add_argument("saida"); ap.add_argument("nos")
    ap.add_argument("--textura", type=int, default=1024)
    a = ap.parse_args()
    g = GLB(a.entrada)
    j = g.j
    nomes = [n.strip() for n in a.nos.split(",")]
    idx = [i for i, n in enumerate(j["nodes"]) if n.get("name") in nomes]
    if len(idx) != len(nomes):
        raise SystemExit("não achei todos: " + str([n.get("name") for n in j["nodes"]]))
    # caixa dos objetos escolhidos (no mundo) pra centralizar e pôr no chão
    mundo = {i: W for i, W, _ in g.percorrer()}
    pts = []
    for i in idx:
        W = mundo[i]
        for p in j["meshes"][j["nodes"][i]["mesh"]]["primitives"]:
            pos = g.accessor(p["attributes"]["POSITION"])
            pts.append(pos @ W[:3, :3].T + W[:3, 3])
    P = np.concatenate(pts)
    lo, hi = P.min(0), P.max(0)
    centro = np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2])
    novos = []
    for i in idx:
        W = mundo[i].copy()
        W[:3, 3] -= centro
        n = {"name": j["nodes"][i]["name"], "mesh": j["nodes"][i]["mesh"], "matrix": W.T.ravel().tolist()}
        j["nodes"].append(n)
        novos.append(len(j["nodes"]) - 1)
    j["scenes"] = [{"nodes": novos}]
    j["scene"] = 0
    j.pop("animations", None); j.pop("skins", None)
    for n in j["nodes"]:
        n.pop("skin", None)
    # materiais usados -> texturas -> imagens/amostradores
    usadas = sorted({p["material"] for i in novos for p in j["meshes"][j["nodes"][i]["mesh"]]["primitives"] if "material" in p})
    mapa_m = {o: k for k, o in enumerate(usadas)}
    j["materials"] = [j["materials"][o] for o in usadas]
    for i in novos:
        for p in j["meshes"][j["nodes"][i]["mesh"]]["primitives"]:
            if "material" in p:
                p["material"] = mapa_m[p["material"]]
    refs = _indices_textura(j["materials"], [])
    tex_usadas = sorted({r["index"] for r in refs})
    mapa_t = {o: k for k, o in enumerate(tex_usadas)}
    j["textures"] = [j["textures"][o] for o in tex_usadas]
    for r in refs:
        r["index"] = mapa_t[r["index"]]
    img_usadas = sorted({t["source"] for t in j["textures"] if "source" in t})
    mapa_i = {o: k for k, o in enumerate(img_usadas)}
    j["images"] = [j["images"][o] for o in img_usadas]
    for t in j["textures"]:
        if "source" in t:
            t["source"] = mapa_i[t["source"]]
    if "samplers" in j:
        sa = sorted({t["sampler"] for t in j["textures"] if "sampler" in t})
        mapa_s = {o: k for k, o in enumerate(sa)}
        j["samplers"] = [j["samplers"][o] for o in sa]
        for t in j["textures"]:
            if "sampler" in t:
                t["sampler"] = mapa_s[t["sampler"]]
    # diminui as imagens
    from importar_carro import reduzir_texturas
    reduzir_texturas(g, a.textura)
    g.salvar(a.saida)
    print("ok", a.saida, round(os.path.getsize(a.saida) / 1e6, 2), "MB", "altura %.2f m" % (hi[1] - lo[1]), "largura %.2f m" % (hi[0] - lo[0]))


if __name__ == "__main__":
    main()
