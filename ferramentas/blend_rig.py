"""Lê armadura + pesos de um .blend (Blender 3.x) — base pra converter personagem com esqueleto pro jogo."""
import struct
import numpy as np
from blend_io import Blend


def ossos(b):
    """dict nome -> (pai_nome, arm_mat 4x4 (espaço da armadura), deforma?, head, tail) e a matriz do objeto rig"""
    out = {}
    rig_mat = None
    for bl in b.blocos:
        if bl["cod"] != "OB" or b.campo("Object", bl["ini"], "type") != 25:
            continue
        o = bl["ini"]
        rig_mat = np.array(b.campo("Object", o, "obmat"), np.float64).reshape(4, 4).T
        arm = b.por_ptr.get(b.campo("Object", o, "data"))
        def visita(ptr_lista_off, pai):
            for bo in b.listbase(ptr_lista_off, "Bone"):
                nome = b.campo("Bone", bo, "name")
                M = np.array(b.campo("Bone", bo, "arm_mat"), np.float64).reshape(4, 4).T
                flag = b.campo("Bone", bo, "flag")
                head = np.array(b.campo("Bone", bo, "arm_head"))
                tail = np.array(b.campo("Bone", bo, "arm_tail"))
                out[nome] = (pai, M, not (flag & (1 << 22)), head, tail)
                visita(bo + b.off_campo("Bone", "childbase"), nome)
        visita(arm["ini"] + b.off_campo("bArmature", "bonebase"), None)
        break
    return out, rig_mat


def grupos(b, me_ini):
    nomes = []
    for g in b.listbase(me_ini + b.off_campo("Mesh", "vertex_group_names"), "bDeformGroup"):
        nomes.append(b.campo("bDeformGroup", g, "name"))
    return nomes


def pesos(b, me_ini, nv):
    """lista por vértice de [(grupo, peso), ...]"""
    bd = b.por_ptr.get(b.campo("Mesh", me_ini, "dvert"))
    if bd is None:
        return None
    t = b.tlen[b.tipos.index("MDeformVert")]
    tw = b.tlen[b.tipos.index("MDeformWeight")]
    out = []
    for i in range(nv):
        o = bd["ini"] + i * t
        dw = b.campo("MDeformVert", o, "dw")
        n = b.campo("MDeformVert", o, "totweight")
        lst = []
        bw = b.por_ptr.get(dw)
        if bw and n:
            raw = b.d[bw["ini"]:bw["ini"] + n * tw]
            for k in range(n):
                g, w = struct.unpack(b.e + "if", raw[k * tw:k * tw + 8])
                lst.append((g, w))
        out.append(lst)
    return out
