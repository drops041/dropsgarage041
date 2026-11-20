"""Converte .obj (+ grupos) em .glb, separando por grupo/material. Uso no código: ler_obj(caminho) -> lista de pedaços."""
import numpy as np
import struct, json


def ler_obj(caminho):
    V, VT, VN = [], [], []
    pedacos = {}      # (grupo, material) -> lista de faces [(v, vt, vn) x3]
    g, m = "default", "default"
    with open(caminho, "r", errors="ignore") as f:
        for ln in f:
            if ln.startswith("v "):
                V.append(ln.split()[1:4])
            elif ln.startswith("vt "):
                VT.append(ln.split()[1:3])
            elif ln.startswith("vn "):
                VN.append(ln.split()[1:4])
            elif ln.startswith("g "):
                g = ln.split(None, 1)[1].strip()
            elif ln.startswith("usemtl "):
                m = ln.split(None, 1)[1].strip()
            elif ln.startswith("f "):
                ids = []
                for t in ln.split()[1:]:
                    p = (t.split("/") + ["", ""])[:3]
                    ids.append(tuple(int(x) if x else 0 for x in p))
                lst = pedacos.setdefault((g, m), [])
                for k in range(1, len(ids) - 1):
                    lst.append((ids[0], ids[k], ids[k + 1]))
    V = np.array(V, np.float64)
    VT = np.array(VT, np.float64) if VT else np.zeros((1, 2))
    VN = np.array(VN, np.float64) if VN else np.zeros((1, 3))
    out = []
    for (g, m), faces in pedacos.items():
        fa = np.array(faces, np.int64).reshape(-1, 3)        # canto: v, vt, vn
        def ix(a, n):
            return np.where(a > 0, a - 1, n + a)
        cv = ix(fa[:, 0], len(V)); ct = ix(fa[:, 1], len(VT)); cn = ix(fa[:, 2], len(VN))
        chave = np.stack([cv, ct, cn], 1)
        uni, inv = np.unique(chave, axis=0, return_inverse=True)
        out.append(dict(grupo=g, mat=m, pos=V[uni[:, 0]], uv=VT[uni[:, 1]], nrm=VN[uni[:, 2]], idx=inv.ravel().astype(np.uint32)))
    return out


def gravar_glb(pecas, materiais, caminho):
    """pecas: lista de (nome_do_no, [(pos, nrm, idx, nome_material)]) ; materiais: nome -> dict pbr"""
    nomes_m = list(materiais.keys())
    j = {"asset": {"version": "2.0", "generator": "Drops Garage obj_para_glb"}, "scene": 0, "scenes": [{"nodes": []}],
         "nodes": [], "meshes": [], "materials": [], "accessors": [], "bufferViews": [], "buffers": []}
    for n in nomes_m:
        m = dict(materiais[n]); m["name"] = n
        j["materials"].append(m)
    bin_ = bytearray()

    def view(b, alvo):
        while len(bin_) % 4:
            bin_.append(0)
        j["bufferViews"].append({"buffer": 0, "byteOffset": len(bin_), "byteLength": len(b), "target": alvo})
        bin_.extend(b)
        return len(j["bufferViews"]) - 1

    def acc(arr, tipo, comp):
        b = arr.tobytes()
        a = {"bufferView": view(b, 34963 if tipo == "SCALAR" else 34962), "componentType": comp, "count": len(arr), "type": tipo}
        if tipo == "VEC3":
            a["min"] = arr.min(0).tolist(); a["max"] = arr.max(0).tolist()
        j["accessors"].append(a)
        return len(j["accessors"]) - 1

    for nome, prims in pecas:
        ps = []
        for pos, nrm, idx, mat in prims:
            pos = np.ascontiguousarray(pos, np.float32)
            nrm = np.asarray(nrm, np.float64)
            ln = np.linalg.norm(nrm, axis=1, keepdims=True)
            nrm = np.ascontiguousarray(np.where(ln > 1e-9, nrm / np.maximum(ln, 1e-12), [0, 1, 0]), np.float32)
            idx = np.ascontiguousarray(idx, np.uint32)
            ps.append({"attributes": {"POSITION": acc(pos, "VEC3", 5126), "NORMAL": acc(nrm, "VEC3", 5126)},
                       "indices": acc(idx, "SCALAR", 5125), "material": nomes_m.index(mat)})
        j["meshes"].append({"name": nome, "primitives": ps})
        j["nodes"].append({"name": nome, "mesh": len(j["meshes"]) - 1})
        j["scenes"][0]["nodes"].append(len(j["nodes"]) - 1)
    while len(bin_) % 4:
        bin_.append(0)
    j["buffers"].append({"byteLength": len(bin_)})
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    with open(caminho, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(bin_)))
        f.write(struct.pack("<I4s", len(js), b"JSON")); f.write(js)
        f.write(struct.pack("<I4s", len(bin_), b"BIN\0")); f.write(bytes(bin_))
