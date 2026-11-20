"""Converte .blend (2.8x–3.x) em .glb sem Blender: malhas em coordenadas do mundo (Y pra cima),
uma malha por material, modificador Espelho aplicado, Subdivisão aplicada (1 nível, Catmull-Clark
simplificado) e cor/metal/rugosidade/emissão do Principled.

Uso: python3 ferramentas/blend_para_glb.py entrada.blend saida.glb [escala]
"""
import json
import os
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from blend_io import Blend  # noqa: E402

MIRROR, SUBSURF = 5, 1


def poligonos(o):
    """lista de (indices dos vértices, indices dos loops, material) por face"""
    out = []
    for ls, tl, mn in zip(o["ls"], o["tl"], o["mn"]):
        out.append((o["lv"][ls:ls + tl].tolist(), list(range(ls, ls + tl)), int(mn)))
    return out


def subdividir(co, faces, uv):
    """um nível de Catmull-Clark (sem tratamento de vincos/bordas especiais além do básico)"""
    nv = len(co)
    arestas = {}
    fp = []
    for fi, (vs, ls, mn) in enumerate(faces):
        fp.append(co[vs].mean(0))
        for k in range(len(vs)):
            a, b = vs[k], vs[(k + 1) % len(vs)]
            arestas.setdefault((min(a, b), max(a, b)), []).append(fi)
    fp = np.array(fp)
    ep = {}
    for (a, b), fs in arestas.items():
        if len(fs) == 2:
            ep[(a, b)] = (co[a] + co[b] + fp[fs[0]] + fp[fs[1]]) / 4.0
        else:
            ep[(a, b)] = (co[a] + co[b]) / 2.0
    # vértices originais
    f_de_v = [[] for _ in range(nv)]
    e_de_v = [[] for _ in range(nv)]
    for fi, (vs, _, _) in enumerate(faces):
        for v in vs:
            f_de_v[v].append(fi)
    borda = np.zeros(nv, bool)
    for (a, b), fs in arestas.items():
        e_de_v[a].append((a, b))
        e_de_v[b].append((a, b))
        if len(fs) != 2:
            borda[a] = borda[b] = True
    novo = co.copy()
    for v in range(nv):
        n = len(f_de_v[v])
        if n == 0:
            continue
        if borda[v]:
            bs = [(co[a] + co[b]) / 2 for (a, b) in e_de_v[v] if len(arestas[(a, b)]) != 2]
            novo[v] = (co[v] * 2 + sum(bs)) / (2 + len(bs)) if bs else co[v]
            continue
        F = fp[f_de_v[v]].mean(0)
        R = np.mean([(co[a] + co[b]) / 2 for (a, b) in e_de_v[v]], 0)
        novo[v] = (F + 2 * R + (n - 3) * co[v]) / n
    pts = list(novo)
    idx_e = {}
    for k, p in ep.items():
        idx_e[k] = len(pts)
        pts.append(p)
    idx_f = []
    for p in fp:
        idx_f.append(len(pts))
        pts.append(p)
    nf = []
    nuv = []
    for fi, (vs, ls, mn) in enumerate(faces):
        m = len(vs)
        for k in range(m):
            a, b, c = vs[(k - 1) % m], vs[k], vs[(k + 1) % m]
            e1 = idx_e[(min(a, b), max(a, b))]
            e2 = idx_e[(min(b, c), max(b, c))]
            nf.append(([b, e2, idx_f[fi], e1], None, mn))
            if uv is not None:
                ua, ub, uc = uv[ls[(k - 1) % m]], uv[ls[k]], uv[ls[(k + 1) % m]]
                uf = uv[ls].mean(0)
                nuv.append([ub, (ub + uc) / 2, uf, (ua + ub) / 2])
    return np.array(pts), nf, nuv if uv is not None else None


def converter(entrada, saida, escala=1.0, subdiv=True, so_objetos=None, xf=None, corta=None, tons=None, imagens=None, pular=(), subdiv_max=3000):
    """xf(P)->P: transforma (já em Y pra cima e na escala); corta(tri 3x3)->bool: descarta o triângulo;
    tons: {nome_material: (r,g,b)} troca a cor de materiais (ex.: tela/quadros sem a imagem original)"""
    b = Blend(entrada)
    por_mat = {}
    mats = {}
    for o in b.objetos():
        if so_objetos and o["nome"] not in so_objetos:
            continue
        if o["nome"] in pular:
            continue
        co = o["co"].astype(np.float64)
        faces = poligonos(o)
        uv = o["uv"]
        uvs_face = [[uv[l] for l in ls] for (_, ls, _) in faces] if uv is not None else None
        if SUBSURF in o["mods"] and subdiv and len(faces) < subdiv_max:
            co, faces2, nuv = subdividir(co, faces, uv)
            faces = faces2
            uvs_face = nuv
        # espelho (no espaço local do objeto)
        for md in b.listbase(_off_obj(b, o), "ModifierData"):
            if b.campo("ModifierData", md, "type") != MIRROR:
                continue
            flag = b.campo("MirrorModifierData", md, "flag")
            eixos = [i for i, bit in enumerate((8, 16, 32)) if flag & bit] or [0]
            for ax in eixos:
                n = len(co)
                c2 = co.copy()
                c2[:, ax] *= -1
                co = np.vstack([co, c2])
                novas = [([v + n for v in reversed(vs)], None, mn) for (vs, _, mn) in faces]
                if uvs_face is not None:
                    uvs_face = uvs_face + [list(reversed(u)) for u in uvs_face]
                faces = faces + novas
        M = o["mat"].T
        P = (np.c_[co, np.ones(len(co))] @ M.T)[:, :3]
        P = np.stack([P[:, 0], P[:, 2], -P[:, 1]], 1) * escala      # Z pra cima -> Y pra cima
        if xf is not None:
            P = xf(P)
        espelhado = np.linalg.det(M[:3, :3]) < 0
        for fi, (vs, _, mn) in enumerate(faces):
            if len(vs) < 3:
                continue
            mat = o["mats"][mn] if mn < len(o["mats"]) else dict(nome="padrao", cor=(0.7, 0.7, 0.7, 1), rug=0.6, met=0, emis=None, img=None)
            chave = mat["nome"]
            mats[chave] = mat
            L = por_mat.setdefault(chave, ([], []))
            pts = P[vs]
            uvf = uvs_face[fi] if uvs_face is not None else [np.zeros(2)] * len(vs)
            if espelhado:
                pts = pts[::-1]
                uvf = uvf[::-1]
            for k in range(1, len(vs) - 1):
                tri = [pts[0], pts[k], pts[k + 1]]
                if corta is not None and corta(np.array(tri)):
                    continue
                L[0].extend(tri)
                L[1].extend([uvf[0], uvf[k], uvf[k + 1]])
    if tons:
        for nome, cor in tons.items():
            if nome in mats:
                mats[nome] = dict(mats[nome], cor=tuple(cor) + (1.0,))
    for nome, arq in (imagens or {}).items():
        if nome in mats:
            mats[nome] = dict(mats[nome], cor=(1.0, 1.0, 1.0, 1.0), tex=arq)
    escrever_glb(saida, por_mat, mats)


def _off_obj(b, o):
    for bl in b.blocos:
        if bl["cod"] == "OB" and b.campo("ID", bl["ini"] + b.off_campo("Object", "id"), "name")[2:] == o["nome"]:
            return bl["ini"] + b.off_campo("Object", "modifiers")
    return 0


def lin(c):
    return c   # Principled já guarda cor linear


def escrever_glb(saida, por_mat, mats):
    buf = bytearray()
    views, accs, meshes_prims, materials = [], [], [], []
    imagens_j, texturas_j = [], []
    def add(arr, tipo, comp, alvo, mm=False):
        while len(buf) % 4:
            buf.append(0)
        off = len(buf)
        bt = np.ascontiguousarray(arr).tobytes()
        buf.extend(bt)
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(bt), "target": alvo})
        a = {"bufferView": len(views) - 1, "componentType": comp, "count": int(len(arr)), "type": tipo}
        if mm:
            a["min"] = arr.min(0).tolist()
            a["max"] = arr.max(0).tolist()
        accs.append(a)
        return len(accs) - 1
    for nome, (pts, uvs) in por_mat.items():
        if not pts:
            continue
        P = np.array(pts, np.float32)
        T = P.reshape(-1, 3, 3)
        n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        N = np.repeat(n, 3, axis=0).astype(np.float32)
        UV = np.array(uvs, np.float32).reshape(-1, 2)
        UV[:, 1] = 1.0 - UV[:, 1]
        m = mats[nome]
        cor = list(m["cor"][:3]) + [1.0]
        mat = {"name": nome, "pbrMetallicRoughness": {"baseColorFactor": [float(x) for x in cor], "metallicFactor": float(m.get("met", 0)),
                                                     "roughnessFactor": float(max(0.05, m.get("rug", 0.6)))}, "doubleSided": True}
        if m.get("tex"):
            dados = open(m["tex"], "rb").read()
            while len(buf) % 4:
                buf.append(0)
            views.append({"buffer": 0, "byteOffset": len(buf), "byteLength": len(dados)})
            buf.extend(dados)
            imagens_j.append({"bufferView": len(views) - 1, "mimeType": "image/png" if m["tex"].endswith(".png") else "image/jpeg"})
            texturas_j.append({"source": len(imagens_j) - 1})
            mat["pbrMetallicRoughness"]["baseColorTexture"] = {"index": len(texturas_j) - 1}
            if m.get("emis"):
                mat["emissiveTexture"] = {"index": len(texturas_j) - 1}
                mat["emissiveFactor"] = [0.55, 0.55, 0.55]
        elif m.get("emis"):
            mat["emissiveFactor"] = [float(min(1, x)) for x in m["emis"][:3]]
        materials.append(mat)
        P, N, UV = np.nan_to_num(P), np.nan_to_num(N), np.nan_to_num(UV)
        # solda vértices iguais (posição+normal+uv) e usa índices: arquivo bem menor
        chave = np.round(np.c_[P / 1e-4, N / 1e-3, UV / 1e-4]).astype(np.int64)
        _, iu, inv = np.unique(chave, axis=0, return_index=True, return_inverse=True)
        P, N, UV = P[iu], N[iu], UV[iu]
        meshes_prims.append({"attributes": {"POSITION": add(P, "VEC3", 5126, 34962, True), "NORMAL": add(N, "VEC3", 5126, 34962),
                                            "TEXCOORD_0": add(UV, "VEC2", 5126, 34962)},
                             "indices": add(inv.ravel().astype(np.uint32), "SCALAR", 5125, 34963), "material": len(materials) - 1})
    j = {"asset": {"version": "2.0", "generator": "blend_para_glb (Drops)"}, "scene": 0, "scenes": [{"nodes": [0]}],
         "nodes": [{"name": "cena", "mesh": 0}], "meshes": [{"name": "cena", "primitives": meshes_prims}],
         "materials": materials, "accessors": accs, "bufferViews": views, "buffers": [{"byteLength": len(buf)}]}
    if imagens_j:
        j["images"] = imagens_j
        j["textures"] = texturas_j
    js = json.dumps(j).encode()
    while len(js) % 4:
        js += b" "
    while len(buf) % 4:
        buf.append(0)
    total = 12 + 8 + len(js) + 8 + len(buf)
    with open(saida, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(buf), 0x004E4942) + bytes(buf))
    print("glb ok:", saida, len(por_mat), "materiais", sum(len(p[0]) for p in por_mat.values()) // 3, "triângulos")


if __name__ == "__main__":
    converter(sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 1.0)
