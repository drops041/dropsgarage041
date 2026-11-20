"""Gravador mínimo de GLB (glTF 2.0 binário) sem dependências além do numpy."""
import json, struct
import numpy as np


class MeshBuilder:
    """Acumula triângulos com normal, UV e cor (linear) para um material."""

    def __init__(self):
        self.P, self.N, self.UV, self.C = [], [], [], []

    def tri(self, a, b, c, ua, ub, uc, col, n=None):
        a, b, c = np.asarray(a, float), np.asarray(b, float), np.asarray(c, float)
        nn = np.cross(b - a, c - a)
        l = np.linalg.norm(nn)
        if l < 1e-9:
            return
        nn = nn / l
        if n is not None and np.dot(nn, n) < 0:
            b, c, ub, uc, nn = c, b, uc, ub, -nn
        self.P += [a, b, c]
        self.N += [nn, nn, nn]
        self.UV += [ua, ub, uc]
        self.C += [col, col, col]

    def tri_n(self, a, b, c, na, nb, nc, ua, ub, uc, col):
        """triângulo com normal por vértice (copa de árvore em cards: normal "esférica" dá volume)"""
        self.P += [np.asarray(a, float), np.asarray(b, float), np.asarray(c, float)]
        self.N += [np.asarray(na, float), np.asarray(nb, float), np.asarray(nc, float)]
        self.UV += [ua, ub, uc]
        self.C += [col, col, col]

    def quad(self, p, uv, col, n=None):
        self.tri(p[0], p[1], p[2], uv[0], uv[1], uv[2], col, n)
        self.tri(p[0], p[2], p[3], uv[0], uv[2], uv[3], col, n)

    def empty(self):
        return len(self.P) == 0

    def arrays(self):
        P = np.asarray(self.P, np.float32).reshape(-1, 3)
        N = np.asarray(self.N, np.float32).reshape(-1, 3)
        UV = np.asarray(self.UV, np.float32).reshape(-1, 2)
        C = np.asarray(self.C, np.float32).reshape(-1, 4)
        # junta vértices idênticos para reduzir tamanho
        key = np.concatenate([np.round(P, 3), np.round(N, 2), np.round(UV, 3), np.round(C, 3)], 1)
        _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
        return P[first], N[first], UV[first], C[first], inv.astype(np.uint32).ravel()


def write_glb(path, nodes, materials):
    """nodes: lista de (nome, {nome_material: MeshBuilder ou arrays}).
    materials: dict nome -> dict(tex=uri|None, color=[r,g,b,a], rough=, double=, emissive=, clamp=)"""
    bin_parts, bufferViews, accessors = [], [], []
    offset = 0

    def add_view(arr, target=None):
        nonlocal offset
        b = arr.tobytes()
        pad = (-len(b)) % 4
        bin_parts.append(b + b"\0" * pad)
        bv = {"buffer": 0, "byteOffset": offset, "byteLength": len(b)}
        if target:
            bv["target"] = target
        bufferViews.append(bv)
        offset += len(b) + pad
        return len(bufferViews) - 1

    def add_acc(arr, comp, typ, target, minmax=False, normalized=False):
        v = add_view(arr, target)
        acc = {"bufferView": v, "componentType": comp, "count": int(arr.shape[0]), "type": typ}
        if normalized:
            acc["normalized"] = True
        if minmax:
            acc["min"] = arr.min(0).tolist()
            acc["max"] = arr.max(0).tolist()
        accessors.append(acc)
        return len(accessors) - 1

    used = []
    for nd in nodes:
        for m in nd[1]:
            if m not in used:
                used.append(m)
    images, textures, samplers, mats, mat_index = [], [], [], [], {}
    samplers.append({"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497})
    samplers.append({"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071})
    for m in used:
        d = materials[m]
        pbr = {"baseColorFactor": d.get("color", [1, 1, 1, 1]), "metallicFactor": d.get("metal", 0.0),
               "roughnessFactor": d.get("rough", 0.9)}
        if d.get("tex"):
            images.append({"uri": d["tex"]})
            textures.append({"source": len(images) - 1, "sampler": 1 if d.get("clamp") else 0})
            pbr["baseColorTexture"] = {"index": len(textures) - 1}
        md = {"name": m, "pbrMetallicRoughness": pbr}
        if d.get("double"):
            md["doubleSided"] = True
        if d.get("alpha"):
            md["alphaMode"] = "MASK"; md["alphaCutoff"] = 0.5
        if d.get("emissive"):
            md["emissiveFactor"] = d["emissive"]
        mat_index[m] = len(mats)
        mats.append(md)

    gl_nodes, meshes = [], []
    for nd in nodes:
        name, prims = nd[0], nd[1]
        trans = nd[2] if len(nd) > 2 else None
        plist = []
        for m, mb in prims.items():
            if isinstance(mb, MeshBuilder):
                if mb.empty():
                    continue
                P, N, UV, C, I = mb.arrays()
            else:
                P, N, UV, C, I = mb
            attrs = {"POSITION": add_acc(P, 5126, "VEC3", 34962, True),
                     "NORMAL": add_acc(N, 5126, "VEC3", 34962)}
            if materials[m].get("tex"):
                attrs["TEXCOORD_0"] = add_acc(UV, 5126, "VEC2", 34962)
            if C is not None:
                C8 = np.clip(np.round(np.asarray(C) * 255), 0, 255).astype(np.uint8)
                attrs["COLOR_0"] = add_acc(C8, 5121, "VEC4", 34962, normalized=True)
            ind = add_acc(I, 5125, "SCALAR", 34963)
            plist.append({"attributes": attrs, "indices": ind, "material": mat_index[m]})
        if not plist:
            continue
        meshes.append({"name": name, "primitives": plist})
        gn = {"name": name, "mesh": len(meshes) - 1}
        if trans is not None:
            gn["translation"] = [float(v) for v in trans]
        gl_nodes.append(gn)

    gltf = {"asset": {"version": "2.0", "generator": "Drops Garage OSM->Godot"},
            "scene": 0, "scenes": [{"nodes": list(range(len(gl_nodes)))}],
            "nodes": gl_nodes, "meshes": meshes, "materials": mats,
            "accessors": accessors, "bufferViews": bufferViews,
            "buffers": [{"byteLength": offset}], "samplers": samplers}
    if images:
        gltf["images"] = images
        gltf["textures"] = textures
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    binb = b"".join(bin_parts)
    total = 12 + 8 + len(js) + 8 + len(binb)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(binb), 0x004E4942) + binb)
