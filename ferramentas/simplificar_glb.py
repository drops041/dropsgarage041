"""SIMPLIFICAR MODELO (.glb pesado demais pro celular) — junta vértices que caem na mesma "casinha" de uma grade 3D.
- Não mistura os dois lados de uma chapa fina: a direção da normal entra na chave (frente e verso ficam separados).
- Em material com textura, a UV também entra na chave (a textura não escorrega nas emendas).
- Tira triângulo que virou linha/ponto. Mantém materiais, texturas e a hierarquia de nós.
- Peças em --tirar (regex no nome do nó) somem antes (ex.: pinças de freio de 900 mil triângulos).
Uso: python3 ferramentas/simplificar_glb.py entrada.glb saida.glb --cel 0.004 [--tirar "Pinça|node#6"] [--cel-int 0.01 --int "seat|leather"]
  --cel     tamanho da casinha em metros do MUNDO do modelo (do jeito que ele está no arquivo)
  --int     regex de peças de dentro (interior) que podem ser mais simplificadas, com --cel-int
"""
import argparse
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB  # noqa: E402


def agrupar(P, N, UV, idx, cel, usar_uv):
    """vertex clustering: devolve P2, N2, UV2, idx2"""
    q = np.floor(P / cel).astype(np.int64)
    chave = [q[:, 0], q[:, 1], q[:, 2]]
    if N is not None:
        nb = np.round(N * 1.4).astype(np.int64)       # ~26 direções: não junta frente com verso
        chave += [nb[:, 0], nb[:, 1], nb[:, 2]]
    if UV is not None and usar_uv:
        ub = np.floor(UV / 0.01).astype(np.int64)
        chave += [ub[:, 0], ub[:, 1]]
    K = np.stack(chave, 1)
    _, rep, inv = np.unique(K, axis=0, return_index=True, return_inverse=True)
    inv = inv.ravel()
    n = len(rep)
    cnt = np.bincount(inv, minlength=n).astype(np.float64)
    P2 = np.stack([np.bincount(inv, P[:, k], n) / cnt for k in range(3)], 1)
    N2 = None
    if N is not None:
        N2 = np.stack([np.bincount(inv, N[:, k], n) for k in range(3)], 1)
        N2 /= np.maximum(np.linalg.norm(N2, axis=1, keepdims=True), 1e-9)
    UV2 = UV[rep] if UV is not None else None
    T = inv[idx.reshape(-1, 3)]
    ok = (T[:, 0] != T[:, 1]) & (T[:, 1] != T[:, 2]) & (T[:, 0] != T[:, 2])
    T = T[ok]
    # triângulo repetido (mesmos 3 vértices) sai também
    Ts = np.sort(T, 1)
    _, u = np.unique(Ts, axis=0, return_index=True)
    T = T[np.sort(u)]
    # só os vértices usados
    usados, T2 = np.unique(T.ravel(), return_inverse=True)
    return P2[usados], (N2[usados] if N2 is not None else None), (UV2[usados] if UV2 is not None else None), T2.astype(np.uint32)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("entrada")
    ap.add_argument("saida")
    ap.add_argument("--cel", type=float, default=0.004)
    ap.add_argument("--tirar", default="")
    ap.add_argument("--int", default="")
    ap.add_argument("--cel-int", type=float, default=0.012)
    a = ap.parse_args()
    g = GLB(a.entrada)
    j = g.j
    nos = j["nodes"]
    tirar = re.compile(a.tirar, re.I) if a.tirar else None
    inter = re.compile(a.int, re.I) if a.int else None
    # nós a tirar
    if tirar:
        for i, W, nome in list(g.percorrer()):
            if tirar.search(nos[i].get("name", "")):
                nos[i].pop("mesh", None)
                nos[i]["children"] = []
    antes = depois = 0
    feitas = {}
    for i, W, nome in g.percorrer():
        no = nos[i]
        if "mesh" not in no:
            continue
        mi = no["mesh"]
        esc = float(np.cbrt(abs(np.linalg.det(W[:3, :3])))) or 1.0
        cel = (a.cel_int if (inter and inter.search(no.get("name", ""))) else a.cel) / esc
        if mi in feitas:
            continue
        feitas[mi] = True
        for p in j["meshes"][mi]["primitives"]:
            at = p["attributes"]
            if p.get("mode", 4) != 4 or "POSITION" not in at:
                continue
            P = g.accessor(at["POSITION"])
            idx = g.accessor(p["indices"]).ravel().astype(np.int64) if "indices" in p else np.arange(len(P))
            N = g.accessor(at["NORMAL"]) if "NORMAL" in at else None
            UV = g.accessor(at["TEXCOORD_0"]) if "TEXCOORD_0" in at else None
            mat = j["materials"][p["material"]] if p.get("material") is not None else {}
            com_tex = "baseColorTexture" in mat.get("pbrMetallicRoughness", {}) or "normalTexture" in mat
            antes += len(idx) // 3
            P2, N2, UV2, T = agrupar(P, N, UV, idx, cel, com_tex)
            if len(T) == 0:
                p["_vazia"] = True      # peça minúscula que sumiu inteira
                continue
            depois += len(T) // 3
            novo = {"POSITION": g.add_accessor_vec3(P2)}
            if N2 is not None:
                novo["NORMAL"] = g.add_accessor_vec3(N2)
            if UV2 is not None:
                uv = np.ascontiguousarray(UV2, np.float32)
                vi = g.add_view(uv.tobytes(), 34962)
                j["accessors"].append({"bufferView": vi, "componentType": 5126, "count": len(uv), "type": "VEC2"})
                novo["TEXCOORD_0"] = len(j["accessors"]) - 1
            T = np.ascontiguousarray(T.ravel(), np.uint32)
            vi = g.add_view(T.tobytes(), 34963)
            j["accessors"].append({"bufferView": vi, "componentType": 5125, "count": len(T), "type": "SCALAR"})
            p["indices"] = len(j["accessors"]) - 1
            p["attributes"] = novo
    for mesh in j["meshes"]:
        mesh["primitives"] = [p for p in mesh["primitives"] if not p.get("_vazia")]
    for no in nos:
        if "mesh" in no and not j["meshes"][no["mesh"]]["primitives"]:
            no.pop("mesh")
    g.salvar(a.saida)
    print("%s: %d -> %d triângulos (%.0f%%), %.1f MB" % (os.path.basename(a.saida), antes, depois, 100.0 * depois / max(1, antes), os.path.getsize(a.saida) / 1e6))


if __name__ == "__main__":
    main()
