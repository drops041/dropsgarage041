"""PRÉDIO OBJ — converte um prédio .obj (sem .mtl/texturas) em .glb pro mapa, com cor por material.
Origem do .glb: no chão, no meio da FACHADA (frente = +Z), pra encostar na calçada.

Uso no código: converter(obj, glb, escala, cores, pular=(), frente="+z")
  cores: nome_do_material -> (r, g, b, metal, aspereza[, alfa])
"""
import json
import os
import struct
import sys

import numpy as np


def ler(caminho, pular=()):
    V, VN = [], []
    faces = {}
    m = "default"
    with open(caminho, "r", errors="ignore") as f:
        for ln in f:
            if ln.startswith("v "):
                V.append([float(x) for x in ln.split()[1:4]])
            elif ln.startswith("vn "):
                VN.append([float(x) for x in ln.split()[1:4]])
            elif ln.startswith("usemtl "):
                m = ln.split(None, 1)[1].strip()
            elif ln.startswith("f ") and m not in pular:
                ids = []
                for t in ln.split()[1:]:
                    p = (t.split("/") + ["", ""])[:3]
                    v = int(p[0])
                    v = v - 1 if v > 0 else len(V) + v
                    n = int(p[2]) if p[2] else 0
                    n = (n - 1 if n > 0 else len(VN) + n) if p[2] else -1
                    ids.append((v, n))
                lst = faces.setdefault(m, [])
                for k in range(1, len(ids) - 1):
                    lst.append((ids[0], ids[k], ids[k + 1]))
    return np.array(V), np.array(VN) if VN else np.zeros((0, 3)), faces


def converter(obj, glb, escala, cores, pular=(), frente="+z", padrao=(150, 150, 150, 0.0, 0.8)):
    V, VN, faces = ler(obj, pular)
    V = V * escala
    usados = np.unique(np.array([c[0] for fs in faces.values() for t in fs for c in t]))
    lo, hi = V[usados].min(0), V[usados].max(0)
    # frente pra +Z
    giro = {"+z": 0, "-z": 2, "+x": 1, "-x": 3}[frente]
    def gira(a):
        for _ in range(giro):
            a = np.stack([-a[:, 2], a[:, 1], a[:, 0]], 1) if a.ndim == 2 else a
        return a
    V = gira(V)
    VN = gira(VN) if len(VN) else VN
    lo, hi = V[usados].min(0), V[usados].max(0)
    origem = np.array([(lo[0] + hi[0]) / 2, lo[1], hi[2]])
    V = V - origem
    j = {"asset": {"version": "2.0", "generator": "Drops Garage predio_obj"}, "scene": 0, "scenes": [{"nodes": []}],
         "nodes": [], "meshes": [], "materials": [], "accessors": [], "bufferViews": [], "buffers": []}
    bin_ = bytearray()

    def view(b, alvo):
        while len(bin_) % 4:
            bin_.append(0)
        j["bufferViews"].append({"buffer": 0, "byteOffset": len(bin_), "byteLength": len(b), "target": alvo})
        bin_.extend(b)
        return len(j["bufferViews"]) - 1

    def acc(arr, tipo, comp, mm=False):
        a = {"bufferView": view(arr.tobytes(), 34963 if tipo == "SCALAR" else 34962), "componentType": comp,
             "count": len(arr), "type": tipo}
        if mm:
            a["min"] = arr.min(0).tolist()
            a["max"] = arr.max(0).tolist()
        j["accessors"].append(a)
        return len(j["accessors"]) - 1
    tot = 0
    for m, fs in faces.items():
        c = cores.get(m, padrao)
        lin = [((x / 255.0 + 0.055) / 1.055) ** 2.4 for x in c[:3]]
        mat = {"name": m, "pbrMetallicRoughness": {"baseColorFactor": lin + [c[5] if len(c) > 5 else 1.0],
                                                   "metallicFactor": c[3], "roughnessFactor": c[4]}, "doubleSided": True}
        if len(c) > 5 and c[5] < 1.0:
            mat["alphaMode"] = "BLEND"
        j["materials"].append(mat)
        fa = np.array(fs).reshape(-1, 2)   # (v, n) por canto
        P = V[fa[:, 0]].astype(np.float32)
        tri = P.reshape(-1, 3, 3)
        fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-9)
        N = np.repeat(fn, 3, 0)
        if len(VN):
            tem = fa[:, 1] >= 0
            N[tem] = VN[fa[tem, 1]]
        N = (N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)).astype(np.float32)
        idx = np.arange(len(P), dtype=np.uint32)
        j["meshes"].append({"name": m, "primitives": [{"attributes": {"POSITION": acc(P, "VEC3", 5126, True),
                            "NORMAL": acc(N, "VEC3", 5126)}, "indices": acc(idx, "SCALAR", 5125),
                            "material": len(j["materials"]) - 1}]})
        j["nodes"].append({"name": m, "mesh": len(j["meshes"]) - 1})
        j["scenes"][0]["nodes"].append(len(j["nodes"]) - 1)
        tot += len(P) // 3
    while len(bin_) % 4:
        bin_.append(0)
    j["buffers"].append({"byteLength": len(bin_)})
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    with open(glb, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(bin_)))
        f.write(struct.pack("<I4s", len(js), b"JSON"))
        f.write(js)
        f.write(struct.pack("<I4s", len(bin_), b"BIN\0"))
        f.write(bytes(bin_))
    tam = V[usados].max(0) - V[usados].min(0)
    print("%s: %d triângulos, %d materiais, tamanho %.1f x %.1f x %.1f m" % (os.path.basename(glb), tot, len(faces), tam[0], tam[1], tam[2]))
    return tam


if __name__ == "__main__":
    print(__doc__)
