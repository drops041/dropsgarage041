"""Leitor mínimo de arquivo .blend (Blender 2.8x–3.x, sem compressão), sem precisar do Blender.
Lê o SDNA, os blocos e devolve objetos de malha com posições, faces, UV, materiais (cor base do
Principled e imagem embutida, se houver) e a matriz do objeto no mundo.
"""
import struct

import numpy as np


class Blend:
    def __init__(self, caminho):
        d = open(caminho, "rb").read()
        assert d[:7] == b"BLENDER", "não é .blend (ou está comprimido)"
        self.p = 8 if d[7:8] == b"-" else 4
        self.e = "<" if d[8:9] == b"v" else ">"
        self.d = d
        self.blocos = []
        self.por_ptr = {}
        o = 12
        P = "Q" if self.p == 8 else "I"
        while o < len(d):
            cod = d[o:o + 4]
            tam, ptr, sdna, cnt = struct.unpack(self.e + "i" + P + "ii", d[o + 4:o + 4 + 4 + self.p + 8])
            ini = o + 4 + 4 + self.p + 8
            b = dict(cod=cod.rstrip(b"\0").decode("latin1"), tam=tam, ptr=ptr, sdna=sdna, cnt=cnt, ini=ini)
            self.blocos.append(b)
            if ptr:
                self.por_ptr[ptr] = b
            if cod == b"DNA1":
                self._dna(ini)
            if cod == b"ENDB":
                break
            o = ini + tam

    # ------------------------------------------------------------------ SDNA
    def _dna(self, o):
        d, e = self.d, self.e
        assert d[o:o + 4] == b"SDNA"
        base = o                                   # (v40) alinhamento é contado do começo do SDNA (Blender 4.x)
        al = lambda x: base + ((x - base + 3) & ~3)
        o += 4
        def bloco_nomes(o, tag):
            assert d[o:o + 4] == tag, tag
            n = struct.unpack(e + "i", d[o + 4:o + 8])[0]
            o += 8
            out = []
            for _ in range(n):
                f = d.index(b"\0", o)
                out.append(d[o:f].decode("latin1"))
                o = f + 1
            return out, al(o)
        self.nomes, o = bloco_nomes(o, b"NAME")
        self.tipos, o = bloco_nomes(o, b"TYPE")
        assert d[o:o + 4] == b"TLEN"
        o += 4
        self.tlen = list(struct.unpack(e + "%dh" % len(self.tipos), d[o:o + 2 * len(self.tipos)]))
        o = al(o + 2 * len(self.tipos))
        assert d[o:o + 4] == b"STRC"
        n = struct.unpack(e + "i", d[o + 4:o + 8])[0]
        o += 8
        self.structs = []
        self.struct_de_tipo = {}
        for i in range(n):
            t, nf = struct.unpack(e + "hh", d[o:o + 4])
            o += 4
            campos = {}
            off = 0
            for _ in range(nf):
                ft, fn = struct.unpack(e + "hh", d[o:o + 4])
                o += 4
                nome = self.nomes[fn]
                tam, base, arr = self._tam_campo(ft, nome)
                campos[base] = (off, self.tipos[ft], nome, arr)
                off += tam
            self.structs.append((self.tipos[t], campos))
            self.struct_de_tipo[self.tipos[t]] = i

    def _tam_campo(self, ft, nome):
        arr = 1
        dims = []
        i = nome.find("[")
        while i >= 0:
            j = nome.index("]", i)
            dims.append(int(nome[i + 1:j]))
            i = nome.find("[", j)
        for x in dims:
            arr *= x
        base = nome.split("[")[0].replace("*", "").replace("(", "").replace(")", "")
        if "*" in nome:
            return self.p * arr, base, dims
        return self.tlen[ft] * arr, base, dims

    # ------------------------------------------------------------------ leitura de campos
    def campo(self, tipo, base_off, nome):
        campos = self.structs[self.struct_de_tipo[tipo]][1]
        off, ft, fnome, dims = campos[nome]
        o = base_off + off
        if "*" in fnome:
            return struct.unpack(self.e + ("Q" if self.p == 8 else "I"), self.d[o:o + self.p])[0]
        fmt = {"char": "b", "uchar": "B", "short": "h", "ushort": "H", "int": "i", "float": "f", "double": "d",
               "int64_t": "q", "uint64_t": "Q", "int8_t": "b", "uint8_t": "B", "int16_t": "h", "int32_t": "i", "uint32_t": "I"}.get(ft)
        n = 1
        for x in dims:
            n *= x
        if ft == "char" and dims:
            s = self.d[o:o + n]
            return s.split(b"\0")[0].decode("latin1", "replace")
        if fmt is None:
            return o   # struct embutido: devolve o deslocamento
        v = struct.unpack(self.e + fmt * n, self.d[o:o + struct.calcsize(fmt) * n])
        return v if n > 1 else v[0]

    def off_campo(self, tipo, nome):
        return self.structs[self.struct_de_tipo[tipo]][1][nome][0]

    def tipo_bloco(self, b):
        return self.structs[b["sdna"]][0]

    def array(self, ptr, tipo, campos_float=None):
        """bloco apontado por ptr como array do struct 'tipo' → lista de deslocamentos"""
        b = self.por_ptr.get(ptr)
        if b is None:
            return []
        t = self.tlen[self.tipos.index(tipo)]
        return [b["ini"] + i * t for i in range(b["tam"] // t)]

    def listbase(self, off, tipo):
        """percorre ListBase (first) de structs com next"""
        out = []
        ptr = struct.unpack(self.e + "Q", self.d[off:off + 8])[0]
        vis = set()
        while ptr and ptr not in vis:
            vis.add(ptr)
            b = self.por_ptr.get(ptr)
            if b is None:
                break
            out.append(b["ini"])
            ptr = self.campo(tipo, b["ini"], "next")
        return out

    # ------------------------------------------------------------------ malhas
    def material(self, ptr):
        b = self.por_ptr.get(ptr)
        if b is None:
            return dict(nome="?", cor=(0.8, 0.8, 0.8, 1.0), img=None, rug=0.6, met=0.0, emis=None)
        o = b["ini"]
        nome = self.campo("ID", o + self.off_campo("Material", "id"), "name")[2:]
        cor = (self.campo("Material", o, "r"), self.campo("Material", o, "g"), self.campo("Material", o, "b"), 1.0)
        out = dict(nome=nome, cor=cor, img=None, rug=0.6, met=0.0, emis=None)
        nt = self.campo("Material", o, "nodetree")
        if nt and self.campo("Material", o, "use_nodes"):
            bt = self.por_ptr.get(nt)
            if bt:
                for no in self.listbase(bt["ini"] + self.off_campo("bNodeTree", "nodes"), "bNode"):
                    idn = self.campo("bNode", no, "idname")
                    if idn == "ShaderNodeBsdfPrincipled":
                        for s in self.listbase(no + self.off_campo("bNode", "inputs"), "bNodeSocket"):
                            nm = self.campo("bNodeSocket", s, "name")
                            dv = self.campo("bNodeSocket", s, "default_value")
                            bd = self.por_ptr.get(dv)
                            if not bd:
                                continue
                            if nm == "Base Color":
                                out["cor"] = struct.unpack(self.e + "4f", self.d[bd["ini"]:bd["ini"] + 16])
                            elif nm == "Roughness":
                                out["rug"] = struct.unpack(self.e + "f", self.d[bd["ini"]:bd["ini"] + 4])[0]
                            elif nm == "Metallic":
                                out["met"] = struct.unpack(self.e + "f", self.d[bd["ini"]:bd["ini"] + 4])[0]
                            elif nm == "Emission":
                                c = struct.unpack(self.e + "4f", self.d[bd["ini"]:bd["ini"] + 16])
                                if max(c[:3]) > 0.01:
                                    out["emis"] = c
                    elif idn == "ShaderNodeEmission":
                        for s in self.listbase(no + self.off_campo("bNode", "inputs"), "bNodeSocket"):
                            if self.campo("bNodeSocket", s, "name") == "Color":
                                bd = self.por_ptr.get(self.campo("bNodeSocket", s, "default_value"))
                                if bd:
                                    out["emis"] = struct.unpack(self.e + "4f", self.d[bd["ini"]:bd["ini"] + 16])
                    elif idn == "ShaderNodeTexImage":
                        im = self.campo("bNode", no, "id")
                        bi = self.por_ptr.get(im)
                        if bi:
                            pf = self.campo("Image", bi["ini"], "packedfile")
                            bp = self.por_ptr.get(pf)
                            if bp is None and "packedfiles" in self.structs[self.struct_de_tipo["Image"]][1]:
                                for ipf in self.listbase(bi["ini"] + self.off_campo("Image", "packedfiles"), "ImagePackedFile"):
                                    bp = self.por_ptr.get(self.campo("ImagePackedFile", ipf, "packedfile"))
                                    if bp:
                                        break
                            campos_im = self.structs[self.struct_de_tipo["Image"]][1]
                            arq = self.campo("Image", bi["ini"], "filepath" if "filepath" in campos_im else "name")
                            dados = None
                            if bp:
                                dp = self.campo("PackedFile", bp["ini"], "data")
                                tam = self.campo("PackedFile", bp["ini"], "size")
                                bdd = self.por_ptr.get(dp)
                                if bdd:
                                    dados = self.d[bdd["ini"]:bdd["ini"] + tam]
                            out["img"] = (arq, dados)
        return out

    def objetos(self):
        out = []
        for b in self.blocos:
            if b["cod"] != "OB":
                continue
            o = b["ini"]
            if self.campo("Object", o, "type") != 1:
                continue
            nome = self.campo("ID", o + self.off_campo("Object", "id"), "name")[2:]
            if "obmat" in self.structs[self.struct_de_tipo["Object"]][1]:
                mat = np.array(self.campo("Object", o, "obmat"), np.float64).reshape(4, 4)   # coluna-maior
            else:
                mat = self.matriz_mundo(o).T     # Blender 4.x não grava a matriz do mundo: calcula
            me = self.por_ptr.get(self.campo("Object", o, "data"))
            if me is None:
                continue
            m = me["ini"]
            nv = self.campo("Mesh", m, "totvert")
            if not self.campo("Mesh", m, "mvert"):
                r = self._malha4(m)
                if r is None:
                    continue
                co, ls, tl_, mn, lv, uv = r
                out.append(self._fim_objeto(o, m, nome, mat, co, ls, tl_, mn, lv, uv))
                continue
            vs = self.array(self.campo("Mesh", m, "mvert"), "MVert")
            if not vs:
                continue
            bv = self.por_ptr[self.campo("Mesh", m, "mvert")]
            tv = self.tlen[self.tipos.index("MVert")]
            raw = np.frombuffer(self.d, np.uint8, bv["tam"], bv["ini"]).reshape(-1, tv)
            co = raw[:, 0:12].copy().view(np.float32).reshape(-1, 3)[:nv]
            bp = self.por_ptr.get(self.campo("Mesh", m, "mpoly"))
            bl = self.por_ptr.get(self.campo("Mesh", m, "mloop"))
            if bp is None or bl is None:
                continue
            tp = self.tlen[self.tipos.index("MPoly")]
            tl = self.tlen[self.tipos.index("MLoop")]
            op = self.off_campo("MPoly", "loopstart"), self.off_campo("MPoly", "totloop"), self.off_campo("MPoly", "mat_nr")
            rp = np.frombuffer(self.d, np.uint8, bp["tam"], bp["ini"]).reshape(-1, tp)
            ls = rp[:, op[0]:op[0] + 4].copy().view(np.int32).ravel()
            tl_ = rp[:, op[1]:op[1] + 4].copy().view(np.int32).ravel()
            mn = rp[:, op[2]:op[2] + 2].copy().view(np.int16).ravel()
            rl = np.frombuffer(self.d, np.uint8, bl["tam"], bl["ini"]).reshape(-1, tl)
            lv = rl[:, 0:4].copy().view(np.int32).ravel()
            # UV (CustomData ldata, camada tipo 16 = CD_MLOOPUV)
            uv = None
            ldata = m + self.off_campo("Mesh", "ldata")
            lay = self.campo("CustomData", ldata, "layers")
            nl = self.campo("CustomData", ldata, "totlayer")
            bly = self.por_ptr.get(lay)
            if bly:
                tly = self.tlen[self.tipos.index("CustomDataLayer")]
                for k in range(nl):
                    lo = bly["ini"] + k * tly
                    if self.campo("CustomDataLayer", lo, "type") == 16:
                        bu = self.por_ptr.get(self.campo("CustomDataLayer", lo, "data"))
                        if bu:
                            tu = self.tlen[self.tipos.index("MLoopUV")]
                            ru = np.frombuffer(self.d, np.uint8, bu["tam"], bu["ini"]).reshape(-1, tu)
                            uv = ru[:, 0:8].copy().view(np.float32).reshape(-1, 2)
                        break
            out.append(self._fim_objeto(o, m, nome, mat, co, ls, tl_, mn, lv, uv))
        return out

    def _fim_objeto(self, o, m, nome, mat, co, ls, tl_, mn, lv, uv):
        if True:
            # materiais (do objeto ou da malha)
            totcol = self.campo("Mesh", m, "totcol")
            mats_ptr = []
            bm = self.por_ptr.get(self.campo("Mesh", m, "mat"))
            if bm:
                mats_ptr = list(struct.unpack(self.e + "%dQ" % totcol, self.d[bm["ini"]:bm["ini"] + 8 * totcol]))
            bom = self.por_ptr.get(self.campo("Object", o, "mat"))
            mats_ob = []
            if bom:
                tc = self.campo("Object", o, "totcol")
                mats_ob = list(struct.unpack(self.e + "%dQ" % tc, self.d[bom["ini"]:bom["ini"] + 8 * tc]))
                for k, pt in enumerate(mats_ob):
                    if pt and k < len(mats_ptr):
                        mats_ptr[k] = pt
            mods = []
            for md in self.listbase(o + self.off_campo("Object", "modifiers"), "ModifierData"):
                mods.append(self.campo("ModifierData", md, "type"))
            return dict(nome=nome, mat=mat, co=co, ls=ls, tl=tl_, mn=mn, lv=lv, uv=uv, ob_ini=o, me_ini=m,
                        mats=[self.material(p) for p in mats_ptr], mods=mods, visivel=True)

    # ------------------------------------------------------------------ Blender 4.x
    def camadas(self, cd_off):
        """camadas de um CustomData: lista (tipo, nome, ptr dos dados)"""
        out = []
        lay = self.campo("CustomData", cd_off, "layers")
        n = self.campo("CustomData", cd_off, "totlayer")
        bly = self.por_ptr.get(lay)
        if not bly:
            return out
        t = self.tlen[self.tipos.index("CustomDataLayer")]
        for k in range(n):
            lo = bly["ini"] + k * t
            out.append((self.campo("CustomDataLayer", lo, "type"), self.campo("CustomDataLayer", lo, "name"),
                        self.campo("CustomDataLayer", lo, "data")))
        return out

    def _dados(self, ptr, dt, nc, n):
        b = self.por_ptr.get(ptr)
        if b is None:
            return None
        a = np.frombuffer(self.d, dt, n * nc, b["ini"])
        return a.reshape(n, nc) if nc > 1 else a

    def _malha4(self, m):
        nv = self.campo("Mesh", m, "totvert")
        npol = self.campo("Mesh", m, "totpoly")
        nl = self.campo("Mesh", m, "totloop")
        co = None
        for t, nm, p in self.camadas(m + self.off_campo("Mesh", "vdata")):
            if nm == "position":
                co = self._dados(p, np.float32, 3, nv)
        if co is None:
            return None
        lv = None
        uv = None
        for t, nm, p in self.camadas(m + self.off_campo("Mesh", "ldata")):
            if nm == ".corner_vert":
                lv = self._dados(p, np.int32, 1, nl)
            elif t == 49 and uv is None and not nm.startswith("."):
                uv = self._dados(p, np.float32, 2, nl)
        if lv is None:
            return None
        off = self._dados(self.campo("Mesh", m, "poly_offset_indices"), np.int32, 1, npol + 1)
        if off is None:
            return None
        mn = np.zeros(npol, np.int16)
        for t, nm, p in self.camadas(m + self.off_campo("Mesh", "pdata")):
            if nm == "material_index":
                x = self._dados(p, np.int32, 1, npol)
                if x is not None:
                    mn = x.astype(np.int16)
        ls = off[:-1].astype(np.int32)
        tl_ = np.diff(off).astype(np.int32)
        return np.array(co), ls, tl_, mn, np.array(lv), (np.array(uv) if uv is not None else None)

    def matriz_mundo(self, o):
        """matriz 4x4 (linhas) do objeto no mundo: pai @ parentinv @ local"""
        import math
        loc = np.array(self.campo("Object", o, "loc"))
        sc = np.array(self.campo("Object", o, "size"))
        modo = self.campo("Object", o, "rotmode")
        if modo == 0:
            w, x, y, z = self.campo("Object", o, "quat")
            n = math.sqrt(w * w + x * x + y * y + z * z) or 1.0
            w, x, y, z = w / n, x / n, y / n, z / n
            R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                          [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                          [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
        else:
            rx, ry, rz = self.campo("Object", o, "rot")
            X = np.array([[1, 0, 0], [0, math.cos(rx), -math.sin(rx)], [0, math.sin(rx), math.cos(rx)]])
            Y = np.array([[math.cos(ry), 0, math.sin(ry)], [0, 1, 0], [-math.sin(ry), 0, math.cos(ry)]])
            Z = np.array([[math.cos(rz), -math.sin(rz), 0], [math.sin(rz), math.cos(rz), 0], [0, 0, 1]])
            ordem = {1: Z @ Y @ X, 2: Y @ Z @ X, 3: Z @ X @ Y, 4: X @ Z @ Y, 5: Y @ X @ Z, 6: X @ Y @ Z}
            R = ordem.get(modo, Z @ Y @ X)
        L = np.eye(4)
        L[:3, :3] = R * sc[None, :]
        L[:3, 3] = loc
        pai = self.campo("Object", o, "parent")
        bp = self.por_ptr.get(pai)
        if bp:
            pinv = np.array(self.campo("Object", o, "parentinv"), np.float64).reshape(4, 4).T
            return self.matriz_mundo(bp["ini"]) @ pinv @ L
        return L
