"""JUNTAR MALHAS — deixa um carro bem mais leve pro jogo: junta todas as peças que usam o mesmo material
numa malha só (menos "chamadas de desenho"), mantendo separadas as portas/porta-malas/capô que abrem
(nós com prefixo PFL__, PFR__, PRL__, PRR__, PTR__, PCA__ feitos pelo portas.py).

Uso: python3 ferramentas/juntar_malhas.py santacruz lexusnx ...   (depois do importar_carro.py e do portas.py)
"""
import json
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB  # noqa: E402

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
# mesmas palavras do jogo (carro_visual.gd), menos "lataria": o nome da peça ajuda a achar farol/lanterna/vidro
CHAVES = [
    ("vidro", ["glass", "window", "vidro", "janela", "windshield", "parabrisa", "windscreen"]),
    ("tail", ["tail", "lanterna", "rear_light", "rearlight", "brake", "freio", "stop"]),
    ("light", ["luz", "headlight", "head_light", "farol", "lamp", "light", "pisca", "indicator", "blinker"]),
    ("chrome", ["chrome", "cromo", "cromado", "mirror", "espelho", "polished"]),
    ("interior", ["interior", "seat", "banco", "dash", "painel", "carpet", "couro", "leather", "steering", "volante"]),
]
RE_GRUPO = re.compile(r"^(P[FR][LR]|PTR|PCA)__")


def classe_no(nome):
    n = nome.lower()
    for c, ks in CHAVES:
        if any(k in n for k in ks):
            return c
    return ""


def main():
    for cid in sys.argv[1:]:
        arq = os.path.join(RAIZ, "modelos", "carros", cid + ".glb")
        g = GLB(arq)
        j = g.j
        nos = j["nodes"]
        pais = {f: i for i, n in enumerate(nos) for f in n.get("children", [])}
        mats = j.get("materials", [])
        usa_uv1 = {i for i, m in enumerate(mats) if '"texCoord": 1' in __import__("json").dumps(m)}

        def grupo(i):
            while True:
                m = RE_GRUPO.match(nos[i].get("name", ""))
                if m:
                    return m.group(1)
                if i not in pais:
                    return ""
                i = pais[i]

        pinturas = [i for i, m in enumerate(mats) if m.get("name", "").startswith("PAINT__")]
        pintura_unica = next((i for i in pinturas if "__liso" in mats[i]["name"]), pinturas[0] if pinturas else None)
        lisos = {}

        def liso(m):
            pm = m.get("pbrMetallicRoughness", {})
            if any(k in pm for k in ("baseColorTexture", "metallicRoughnessTexture")):
                return False
            if any(k in m for k in ("emissiveTexture", "occlusionTexture")) or set(m.get("extensions", {})) - {"KHR_materials_specular", "KHR_materials_ior"}:
                return False
            if m.get("alphaMode", "OPAQUE") != "OPAQUE" or any(x > 0 for x in m.get("emissiveFactor", [0, 0, 0])):
                return False
            return True

        def material_liso(tag, met, rug, duplo, normal):
            nt = json.dumps(normal, sort_keys=True) if normal else ""
            k = (tag, round(float(met) * 4) / 4, round(float(rug) * 4) / 4, bool(duplo), nt)
            if k not in lisos:
                nome = ("INTERIOR__" if tag == "INTERIOR" else "") + "cor_m%d_a%d%s_%d" % (k[1] * 100, k[2] * 100, "_2l" if duplo else "", len(lisos))
                novo = {"name": nome, "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": k[1], "roughnessFactor": k[2]},
                        "doubleSided": k[3]}
                if normal:
                    novo["normalTexture"] = normal
                mats.append(novo)
                lisos[k] = len(mats) - 1
            return lisos[k]
        juntos = {}   # (grupo, material, classe) -> listas
        antes = 0
        for p in g.primitivas():
            antes += 1
            at = p["prim"]["attributes"]
            W = p["W"]
            pos = p["pw"]
            if "NORMAL" in at:
                n = g.accessor(at["NORMAL"]) @ np.linalg.inv(W[:3, :3]).T
                n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
            else:
                n = None
            uv0 = g.accessor(at["TEXCOORD_0"])[:, :2] if "TEXCOORD_0" in at else np.zeros((len(pos), 2))
            uv1 = g.accessor(at["TEXCOORD_1"])[:, :2] if "TEXCOORD_1" in at else None
            col = None
            if "COLOR_0" in at:
                col = g.accessor(at["COLOR_0"]).astype(np.float64)
                if col.shape[1] == 3:
                    col = np.hstack([col, np.ones((len(col), 1))])
            idx = p["idx"].reshape(-1, 3)
            if np.linalg.det(W[:3, :3]) < 0:
                idx = idx[:, ::-1]
            mi = p["mat"]
            mn = mats[mi].get("name", "") if mi is not None else ""
            tag = mn.split("__")[0] if "__" in mn else ""
            if tag in ("PNEU", "ARO"):
                continue   # roda original: o jogo põe as rodas dele (e esconderia isso de qualquer jeito)
            if tag == "PAINT":
                mi = pintura_unica   # toda lataria usa o mesmo material no jogo -> uma malha só
            cls = "" if tag else classe_no(p["nome"].split("/")[-1] + " " + p["nome"])
            cor_vert = None
            if mi is not None and cls == "" and tag in ("", "INTERIOR") and liso(mats[mi]):
                # material de cor lisa (sem textura): a cor vai pro vértice e junta com os outros iguais
                pm = mats[mi].get("pbrMetallicRoughness", {})
                cor_vert = pm.get("baseColorFactor", [1, 1, 1, 1])
                mi = material_liso(tag, pm.get("metallicFactor", 1.0), pm.get("roughnessFactor", 1.0), mats[mi].get("doubleSided", False), mats[mi].get("normalTexture"))
            chave = (grupo(p["no"]), mi, cls)
            if cor_vert is not None:
                cv = np.tile(np.array(cor_vert, np.float64), (len(pos), 1))
                col = cv if col is None else col * cv
            juntos.setdefault(chave, []).append((pos, n, uv0, uv1, col, idx))
        # monta as malhas novas
        novos_nos = []
        malhas = []
        for k, ((gr, mat, cls), partes) in enumerate(sorted(juntos.items(), key=lambda x: (x[0][0], x[0][1] or -1, x[0][2]))):
            P, N, U0, U1, C, I = [], [], [], [], [], []
            base = 0
            tem_n = all(x[1] is not None for x in partes)
            tem_uv1 = mat in usa_uv1 and any(x[3] is not None for x in partes)
            tem_c = any(x[4] is not None for x in partes)
            for pos, n, uv0, uv1, col, idx in partes:
                P.append(pos)
                if tem_n:
                    N.append(n)
                U0.append(uv0)
                if tem_uv1:
                    U1.append(uv1 if uv1 is not None else np.zeros((len(pos), 2)))
                if tem_c:
                    C.append(col if col is not None else np.ones((len(pos), 4)))
                I.append(idx.ravel() + base)
                base += len(pos)
            P = np.concatenate(P).astype(np.float32)
            atr = {"POSITION": g.add_accessor_vec3(P)}
            if tem_n:
                atr["NORMAL"] = g.add_accessor_vec3(np.concatenate(N))
                j["accessors"][atr["NORMAL"]].pop("min", None)
                j["accessors"][atr["NORMAL"]].pop("max", None)

            def vec(arr, tipo):
                arr = np.ascontiguousarray(arr, np.float32)
                vi = g.add_view(arr.tobytes(), 34962)
                j["accessors"].append({"bufferView": vi, "componentType": 5126, "count": len(arr), "type": tipo})
                return len(j["accessors"]) - 1
            atr["TEXCOORD_0"] = vec(np.concatenate(U0), "VEC2")
            if tem_uv1:
                atr["TEXCOORD_1"] = vec(np.concatenate(U1), "VEC2")
            if tem_c:
                atr["COLOR_0"] = vec(np.concatenate(C), "VEC4")
            I = np.concatenate(I).astype(np.uint32)
            vi = g.add_view(I.tobytes(), 34963)
            j["accessors"].append({"bufferView": vi, "componentType": 5125, "count": len(I), "type": "SCALAR"})
            prim = {"attributes": atr, "indices": len(j["accessors"]) - 1}
            if mat is not None:
                prim["material"] = mat
            malhas.append({"name": "m%d" % k, "primitives": [prim]})
            nome = ("%s__" % gr if gr else "") + "m%d%s" % (k, ("_" + cls) if cls else "")
            novos_nos.append({"name": nome, "mesh": len(j["meshes"]) + len(malhas) - 1})
        j["meshes"].extend(malhas)
        ini = len(nos)
        nos.extend(novos_nos)
        nos.append({"name": cid, "children": list(range(ini, ini + len(novos_nos)))})
        j["scenes"] = [{"nodes": [len(nos) - 1]}]
        j["scene"] = 0
        j.pop("animations", None)
        j.pop("skins", None)
        g.salvar(arq)
        # tira os nós velhos (ficaram fora da cena)
        g = GLB(arq)
        j = g.j
        alc = [i for i, _, _ in g.percorrer()]
        novo = {o: n for n, o in enumerate(alc)}
        j["nodes"] = [j["nodes"][o] for o in alc]
        for n in j["nodes"]:
            if "children" in n:
                n["children"] = [novo[c] for c in n["children"]]
        j["scenes"] = [{"nodes": [novo[r] for r in j["scenes"][0]["nodes"]]}]
        g.salvar(arq)
        print("%s: %d peças -> %d malhas (%.1f MB)" % (cid, antes, len(novos_nos), os.path.getsize(arq) / 1e6))


if __name__ == "__main__":
    main()
