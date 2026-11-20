"""Leitura e escrita de GLB (glTF binário) só com numpy — sem Blender, sem bibliotecas extras."""
import json
import struct
import numpy as np

COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


class GLB:
    def __init__(self, caminho):
        b = open(caminho, "rb").read()
        if b[:4] != b"glTF":
            raise ValueError("não é um .glb (exporte do Blender/Sketchfab como glTF Binary .glb)")
        n = struct.unpack("<I", b[12:16])[0]
        self.j = json.loads(b[20:20 + n])
        self.bin = b""
        o = 20 + n
        if o < len(b):
            ln = struct.unpack("<I", b[o:o + 4])[0]
            self.bin = b[o + 8:o + 8 + ln]
        req = set(self.j.get("extensionsRequired", []))
        ruins = req & {"KHR_draco_mesh_compression", "EXT_meshopt_compression", "KHR_mesh_quantization"}
        if ruins:
            raise ValueError("modelo comprimido (%s): o Godot não abre. Exporte de novo sem compressão." % ", ".join(sorted(ruins)))
        for buf in self.j.get("buffers", [])[1:]:
            raise ValueError("glTF com mais de um arquivo .bin: exporte como .glb único")
        self.extra_views = {}     # índice da view -> bytes novos (substitui o conteúdo)

    # ---------------------------------------------------------- acesso
    def view_bytes(self, vi):
        if vi in self.extra_views:
            return self.extra_views[vi]
        v = self.j["bufferViews"][vi]
        o = v.get("byteOffset", 0)
        return self.bin[o:o + v["byteLength"]]

    def accessor(self, ai):
        a = self.j["accessors"][ai]
        dt = COMP[a["componentType"]]
        nc = NCOMP[a["type"]]
        cnt = a["count"]
        if "bufferView" not in a:
            return np.zeros((cnt, nc), dt)
        v = self.j["bufferViews"][a["bufferView"]]
        raw = self.view_bytes(a["bufferView"])
        o = a.get("byteOffset", 0)
        esz = np.dtype(dt).itemsize * nc
        stride = v.get("byteStride", esz)
        if stride == esz:
            arr = np.frombuffer(raw, dt, cnt * nc, o).reshape(cnt, nc)
        else:
            arr = np.lib.stride_tricks.as_strided(np.frombuffer(raw, np.uint8, len(raw) - o, o).view(np.uint8),
                                                  (cnt, esz), (stride, 1)).copy().view(dt).reshape(cnt, nc)
        arr = arr.astype(np.float64) if dt == np.float32 else arr
        if a.get("normalized"):
            mx = float(np.iinfo(dt).max)
            arr = np.maximum(arr.astype(np.float64) / mx, -1.0)
        return arr

    def add_view(self, data: bytes, target=None):
        v = {"buffer": 0, "byteOffset": 0, "byteLength": len(data)}
        if target:
            v["target"] = target
        self.j.setdefault("bufferViews", []).append(v)
        vi = len(self.j["bufferViews"]) - 1
        self.extra_views[vi] = data
        return vi

    def add_accessor_vec3(self, arr):
        arr = np.ascontiguousarray(arr, np.float32)
        vi = self.add_view(arr.tobytes(), 34962)
        self.j["accessors"].append({"bufferView": vi, "componentType": 5126, "count": len(arr), "type": "VEC3",
                                    "min": arr.min(0).tolist(), "max": arr.max(0).tolist()})
        return len(self.j["accessors"]) - 1

    # ---------------------------------------------------------- cena
    @staticmethod
    def matriz_no(no):
        if "matrix" in no:
            return np.array(no["matrix"], np.float64).reshape(4, 4).T
        t = np.array(no.get("translation", [0, 0, 0]), np.float64)
        x, y, z, w = no.get("rotation", [0, 0, 0, 1])
        s = np.array(no.get("scale", [1, 1, 1]), np.float64)
        R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                      [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                      [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
        M = np.eye(4)
        M[:3, :3] = R * s[None, :]
        M[:3, 3] = t
        return M

    def raizes(self):
        cenas = self.j.get("scenes", [{"nodes": list(range(len(self.j.get("nodes", []))))}])
        return cenas[self.j.get("scene", 0)]["nodes"]

    def percorrer(self):
        """(índice do nó, matriz no mundo, caminho de nomes) de todos os nós da cena"""
        nos = self.j.get("nodes", [])
        pilha = [(r, np.eye(4), "") for r in self.raizes()]
        while pilha:
            i, M, cam = pilha.pop()
            no = nos[i]
            W = M @ self.matriz_no(no)
            nome = cam + "/" + no.get("name", "")
            yield i, W, nome
            for f in no.get("children", []):
                pilha.append((f, W, nome))

    def primitivas(self):
        """lista de dicts: nó, malha, índice da primitiva, material, posições no mundo, índices dos triângulos"""
        out = []
        for i, W, nome in self.percorrer():
            no = self.j["nodes"][i]
            if "mesh" not in no:
                continue
            for k, p in enumerate(self.j["meshes"][no["mesh"]]["primitives"]):
                if p.get("mode", 4) != 4 or "POSITION" not in p.get("attributes", {}):
                    continue
                pos = self.accessor(p["attributes"]["POSITION"]).astype(np.float64)
                pw = pos @ W[:3, :3].T + W[:3, 3]
                idx = self.accessor(p["indices"]).ravel().astype(np.int64) if "indices" in p else np.arange(len(pos))
                out.append(dict(no=i, nome=nome, malha=no["mesh"], k=k, mat=p.get("material"), pos=pos, pw=pw, idx=idx, W=W, prim=p))
        return out

    # ---------------------------------------------------------- limpeza
    def limpar(self):
        """tira do arquivo o que ninguém usa: malhas de nós fora da cena (rodas removidas),
        normais antigas trocadas pelas lisas etc. Mantém materiais e imagens."""
        j = self.j
        alc = set(i for i, _, _ in self.percorrer())
        malhas_usadas = sorted({j["nodes"][i]["mesh"] for i in alc if "mesh" in j["nodes"][i]})
        mapa_m = {o: n for n, o in enumerate(malhas_usadas)}
        j["meshes"] = [j["meshes"][o] for o in malhas_usadas]
        for i, no in enumerate(j["nodes"]):
            if "mesh" in no:
                if no["mesh"] in mapa_m:
                    no["mesh"] = mapa_m[no["mesh"]]
                else:
                    del no["mesh"]
        usados = set()
        for m in j["meshes"]:
            for p in m["primitives"]:
                usados.update(p.get("attributes", {}).values())
                if "indices" in p:
                    usados.add(p["indices"])
                for t in p.get("targets", []):
                    usados.update(t.values())
        for s in j.get("skins", []):
            if "inverseBindMatrices" in s:
                usados.add(s["inverseBindMatrices"])
        for a in j.get("animations", []):
            for s in a.get("samplers", []):
                usados.update([s["input"], s["output"]])
        ordem = sorted(usados)
        mapa_a = {o: n for n, o in enumerate(ordem)}
        j["accessors"] = [j["accessors"][o] for o in ordem]
        for m in j["meshes"]:
            for p in m["primitives"]:
                p["attributes"] = {k: mapa_a[v] for k, v in p["attributes"].items()}
                if "indices" in p:
                    p["indices"] = mapa_a[p["indices"]]
                if "targets" in p:
                    p["targets"] = [{k: mapa_a[v] for k, v in t.items()} for t in p["targets"]]
        for s in j.get("skins", []):
            if "inverseBindMatrices" in s:
                s["inverseBindMatrices"] = mapa_a[s["inverseBindMatrices"]]
        for a in j.get("animations", []):
            for s in a.get("samplers", []):
                s["input"], s["output"] = mapa_a[s["input"]], mapa_a[s["output"]]
        views = {a["bufferView"] for a in j["accessors"] if "bufferView" in a}
        for a in j["accessors"]:   # acessores esparsos (formas/morph) apontam pra mais duas views
            sp = a.get("sparse")
            if sp:
                views |= {sp["indices"]["bufferView"], sp["values"]["bufferView"]}
        views |= {im["bufferView"] for im in j.get("images", []) if "bufferView" in im}
        ordem_v = sorted(views)
        mapa_v = {o: n for n, o in enumerate(ordem_v)}
        dados = {n: self.view_bytes(o) for o, n in mapa_v.items()}
        j["bufferViews"] = [j["bufferViews"][o] for o in ordem_v]
        for a in j["accessors"]:
            if "bufferView" in a:
                a["bufferView"] = mapa_v[a["bufferView"]]
            sp = a.get("sparse")
            if sp:
                sp["indices"]["bufferView"] = mapa_v[sp["indices"]["bufferView"]]
                sp["values"]["bufferView"] = mapa_v[sp["values"]["bufferView"]]
        for im in j.get("images", []):
            if "bufferView" in im:
                im["bufferView"] = mapa_v[im["bufferView"]]
        self.extra_views = dados

    # ---------------------------------------------------------- gravar
    def salvar(self, caminho):
        self.limpar()
        j = self.j
        partes = []
        o = 0
        for vi, v in enumerate(j.get("bufferViews", [])):
            data = self.view_bytes(vi)
            pad = (-o) % 4
            partes.append(b"\0" * pad)
            o += pad
            v["byteOffset"] = o
            v["byteLength"] = len(data)
            v["buffer"] = 0
            partes.append(data)
            o += len(data)
        binario = b"".join(partes)
        binario += b"\0" * ((-len(binario)) % 4)
        j["buffers"] = [{"byteLength": len(binario)}]
        js = json.dumps(j, separators=(",", ":"), ensure_ascii=False).encode("utf8")
        js += b" " * ((-len(js)) % 4)
        total = 12 + 8 + len(js) + 8 + len(binario)
        with open(caminho, "wb") as f:
            f.write(struct.pack("<4sII", b"glTF", 2, total))
            f.write(struct.pack("<I4s", len(js), b"JSON"))
            f.write(js)
            f.write(struct.pack("<I4s", len(binario), b"BIN\0"))
            f.write(binario)


def normais_lisas(pos, idx, normais=None):
    """Mesma regra do jogo: junta as normais de vértices no mesmo lugar, sem arredondar quinas vivas (vinco, borda de janela)."""
    pos = np.asarray(pos, np.float64)
    tri = idx.reshape(-1, 3)
    a, b, c = pos[tri[:, 0]], pos[tri[:, 1]], pos[tri[:, 2]]
    fn = np.cross(b - a, c - a)                       # normal da face com peso pela área
    chave = np.round(pos * 400.0).astype(np.int64)
    _, grupo = np.unique(chave, axis=0, return_inverse=True)
    grupo = grupo.ravel()
    cant_g = grupo[tri.ravel()]                       # grupo de cada canto de triângulo
    cant_n = np.repeat(fn, 3, axis=0)
    ordem = np.argsort(cant_g, kind="stable")
    cant_g, cant_n = cant_g[ordem], cant_n[ordem]
    ng = grupo.max() + 1
    ini = np.searchsorted(cant_g, np.arange(ng))
    fim = np.searchsorted(cant_g, np.arange(ng), side="right")
    tem_ref = normais is not None and len(normais) == len(pos)
    if tem_ref:
        ref = np.asarray(normais, np.float64)
        ref = ref / np.maximum(np.linalg.norm(ref, axis=1, keepdims=True), 1e-12)
    else:
        ref = None
    nova = np.zeros_like(pos)
    kmax = int((fim - ini).max()) if ng else 0
    # matriz grupo x cantos (preenchida com zero) — pra fazer tudo de uma vez
    G = np.zeros((ng, kmax, 3))
    lin = np.repeat(np.arange(ng), fim - ini)
    col = np.arange(len(cant_g)) - np.repeat(ini, fim - ini)
    G[lin, col] = cant_n
    n = np.zeros_like(pos)
    for s in range(0, len(pos), 20000):            # em pedaços pra não estourar a memória
        gs = grupo[s:s + 20000]
        Gv = G[gs]                                  # vértice x cantos x 3
        if tem_ref:
            r = ref[s:s + 20000]
            un = Gv / np.maximum(np.linalg.norm(Gv, axis=2, keepdims=True), 1e-12)
            al = np.einsum("vkc,vc->vk", un, r)
            sinal = np.where(al < 0, -1.0, 1.0)
            usa = (np.abs(al) >= 0.35)
            n[s:s + 20000] = (Gv * (sinal * usa)[..., None]).sum(1)
        else:
            n[s:s + 20000] = Gv.sum(1)
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    nova = np.where(ln > 1e-9, n / np.maximum(ln, 1e-12), ref if tem_ref else np.array([0, 1.0, 0]))
    return nova
