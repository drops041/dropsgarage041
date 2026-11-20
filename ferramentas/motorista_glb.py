"""MOTORISTA SENTADO: pega um personagem com esqueleto (nomes do Mixamo), põe sentado com as mãos no volante
e salva uma malha FIXA (sem esqueleto), já em metros com 1,75 m de altura em pé e o quadril na origem.
Custa quase nada no jogo: os carros do trânsito usam essa malha pronta.
Uso: python3 ferramentas/motorista_glb.py personagem.glb saida.glb"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB  # noqa: E402

# direção que cada osso aponta sentado ao volante (pessoa olhando pra +Z, esquerda dela = +X)
POSE = {
    "Spine": (0.0, 1.0, -0.14),
    "UpLeg": (0.0, 0.1, 1.0),       # coxa quase reta pra frente (banco de carro é baixo)
    "Leg": (0.0, -0.62, 1.0),       # canela pra frente, pé lá nos pedais
    "Foot": (0.0, 0.45, 1.0),
    "Arm": (0.22, -0.5, 0.84),      # (x do lado esquerdo; o direito espelha)
    "ForeArm": (-0.32, 0.22, 1.0),
}
FILHO = {"Spine": "Spine1", "UpLeg": "Leg", "Leg": "Foot", "Foot": "ToeBase", "Arm": "ForeArm", "ForeArm": "Hand"}


def chave(n):
    import re
    n = re.sub(r"_(\d+|Armature)$", "", n)          # sufixo do Sketchfab (mixamorigHips_42, _Armature)
    for p in ("mixamorig:", "mixamorig_", "mixamorig"):
        if n.startswith(p):
            return n[len(p):]
    return n


def girar(a, b):
    """matriz 3x3 que leva a direção a na b"""
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    v = np.cross(a, b)
    c = float(a @ b)
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3) if c > 0 else -np.eye(3)
    K = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + K + K @ K * (1.0 / (1.0 + c))


def converter(arq, saida, altura=1.75):
    g = GLB(arq)
    j = g.j
    nos = j["nodes"]
    G = {}
    pai = {}
    ordem = []
    for i, W, _ in g.percorrer():
        G[i] = W
    # ordem pai -> filho
    def visita(i, p):
        pai[i] = p
        ordem.append(i)
        for c in nos[i].get("children", []):
            visita(c, i)
    for r in g.raizes():
        visita(r, None)
    nome = {i: chave(nos[i].get("name", "")) for i in range(len(nos))}
    por_nome = {v: k for k, v in nome.items()}
    sk = j["skins"][0]
    juntas = sk["joints"]
    # pra onde a pessoa olha: braço esquerdo em +X = olha pra +Z
    sinal = 1.0
    if "LeftArm" in por_nome and G[por_nome["LeftArm"]][0, 3] < G[por_nome["Hips"]][0, 3]:
        sinal = -1.0
    N = {}
    for i in ordem:
        p = pai[i]
        N[i] = G[i].copy() if p is None else N[p] @ np.linalg.inv(G[p]) @ G[i]
        k = nome[i]
        lado = 1.0
        base = k
        for L, s in (("Left", 1.0), ("Right", -1.0)):
            if k.startswith(L):
                base, lado = k[len(L):], s
        if base in POSE and (L_f := (k[:-len(base)] + FILHO[base]) if base != "Spine" else "Spine1") in por_nome:
            c = por_nome[L_f]
            o = N[i][:3, 3]
            cur = (N[i] @ np.linalg.inv(G[i]) @ G[c])[:3, 3] - o
            t = np.array(POSE[base], float)
            t[0] *= lado
            t[0] *= sinal
            t[2] *= sinal
            R = np.eye(4)
            R[:3, :3] = girar(cur, t)
            T1 = np.eye(4); T1[:3, 3] = o
            T0 = np.eye(4); T0[:3, 3] = -o
            N[i] = T1 @ R @ T0 @ N[i]
    ibm = g.accessor(sk["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
    Jp = np.array([N[jn] @ ibm[q] for q, jn in enumerate(juntas)])       # pose sentada
    Jr = np.array([G[jn] @ ibm[q] for q, jn in enumerate(juntas)])       # em pé (pra medir a altura)
    # malhas com pele
    prims = []
    for i in ordem:
        if "mesh" in nos[i] and "skin" in nos[i]:
            prims.append(i)
    todos_r = []
    novos = []
    for ni in prims:
        for p in j["meshes"][nos[ni]["mesh"]]["primitives"]:
            a = p["attributes"]
            P = g.accessor(a["POSITION"])
            Nn = g.accessor(a["NORMAL"]) if "NORMAL" in a else None
            Jx = g.accessor(a["JOINTS_0"]).astype(int)
            Wt = g.accessor(a["WEIGHTS_0"]).astype(np.float64)
            Wt /= np.maximum(Wt.sum(1, keepdims=True), 1e-9)
            Ph = np.c_[P, np.ones(len(P))]
            Mp = np.einsum("vk,vkij->vij", Wt, Jp[Jx])
            Mr = np.einsum("vk,vkij->vij", Wt, Jr[Jx])
            Ps = np.einsum("vij,vj->vi", Mp, Ph)[:, :3]
            todos_r.append(np.einsum("vij,vj->vi", Mr, Ph)[:, :3])
            Ns = None
            if Nn is not None:
                Ns = np.einsum("vij,vj->vi", Mp[:, :3, :3], Nn)
                Ns /= np.maximum(np.linalg.norm(Ns, axis=1, keepdims=True), 1e-9)
            novos.append((p, Ps, Ns))
    R = np.concatenate(todos_r)
    k = altura / (R[:, 1].max() - R[:, 1].min())
    quadril = N[por_nome["Hips"]][:3, 3]
    for p, Ps, Ns in novos:
        Q = (Ps - quadril) * k
        if sinal < 0:
            Q[:, 0] *= -1
            Q[:, 2] *= -1
            if Ns is not None:
                Ns[:, 0] *= -1
                Ns[:, 2] *= -1
        a = p["attributes"]
        a["POSITION"] = g.add_accessor_vec3(Q)
        if Ns is not None:
            a["NORMAL"] = g.add_accessor_vec3(Ns)
        for x in ("JOINTS_0", "WEIGHTS_0", "JOINTS_1", "WEIGHTS_1"):
            a.pop(x, None)
    malhas = sorted({nos[ni]["mesh"] for ni in prims})
    j["nodes"] = [{"name": "Motorista", "children": list(range(1, 1 + len(malhas)))}] + [{"name": "Corpo%d" % q, "mesh": mi} for q, mi in enumerate(malhas)]
    j["scenes"] = [{"nodes": [0]}]
    j["scene"] = 0
    j.pop("skins", None)
    j.pop("animations", None)
    g.salvar(saida)
    print("%s -> %s (%s)" % (os.path.basename(arq), saida, "olhava pra -Z, virado" if sinal < 0 else "ok"))


if __name__ == "__main__":
    converter(sys.argv[1], sys.argv[2])
