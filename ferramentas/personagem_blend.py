"""PERSONAGEM COM ESQUELETO (.blend do Blender 3.x, rig Auto-Rig Pro ou Mixamo) -> .glb do jogo.

- Lê os ossos que deformam a malha, monta um esqueleto simples com nomes do Mixamo (Hips, Spine, LeftArm...),
  assim o jogo usa as animações que já tem (parado, andar, correr, dançar).
- Lê os pesos de cada vértice, as malhas presas na armadura (as soltas/escondidas ficam de fora), UV e
  materiais; as texturas vêm da pasta de texturas (pelo nome do material), reduzidas pra 1024/2048.
Uso: python3 ferramentas/personagem_blend.py arquivo.blend pasta_texturas saida.glb [--pular obj1,obj2]
"""
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from blend_io import Blend  # noqa: E402
from blend_rig import grupos, pesos  # noqa: E402

C3 = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], np.float64)   # Z pra cima (Blender) -> Y pra cima (glTF)
C4 = np.eye(4)
C4[:3, :3] = C3

# Auto-Rig Pro -> Mixamo: candidatos em ordem (o primeiro que existir na armadura)
ARP = {
    "Hips": ["root.x"], "Spine": ["spine_01.x"], "Spine1": ["spine_02.x"], "Spine2": ["spine_03.x"],
    "Neck": ["neck.x"], "Head": ["head.x"],
}
for L, s in (("Left", "l"), ("Right", "r")):
    ARP.update({
        L + "Shoulder": ["shoulder." + s], L + "Arm": ["c_arm_twist_offset." + s, "arm_twist." + s, "arm_stretch." + s],
        L + "ForeArm": ["forearm_stretch." + s], L + "Hand": ["hand." + s],
        L + "UpLeg": ["thigh_twist." + s, "thigh_stretch." + s], L + "Leg": ["leg_stretch." + s],
        L + "Foot": ["foot." + s], L + "ToeBase": ["toes_01." + s],
        L + "HandThumb1": ["thumb1." + s], L + "HandThumb2": ["c_thumb2." + s], L + "HandThumb3": ["c_thumb3." + s],
    })
    for d in ("Index", "Middle", "Ring", "Pinky"):
        dl = d.lower()
        ARP.update({L + "Hand" + d + "1": [dl + "1." + s], L + "Hand" + d + "2": ["c_" + dl + "2." + s],
                    L + "Hand" + d + "3": ["c_" + dl + "3." + s]})
PAI_MIXAMO = {"Spine": "Hips", "Spine1": "Spine", "Spine2": "Spine1", "Neck": "Spine2", "Head": "Neck"}
for L in ("Left", "Right"):
    PAI_MIXAMO.update({L + "Shoulder": "Spine2", L + "Arm": L + "Shoulder", L + "ForeArm": L + "Arm", L + "Hand": L + "ForeArm",
                       L + "UpLeg": "Hips", L + "Leg": L + "UpLeg", L + "Foot": L + "Leg", L + "ToeBase": L + "Foot"})
    for d in ("Thumb", "Index", "Middle", "Ring", "Pinky"):
        PAI_MIXAMO[L + "Hand" + d + "1"] = L + "Hand"
        PAI_MIXAMO[L + "Hand" + d + "2"] = L + "Hand" + d + "1"
        PAI_MIXAMO[L + "Hand" + d + "3"] = L + "Hand" + d + "2"


def armadura(b, ob_ptr):
    bo = b.por_ptr[ob_ptr]
    o = bo["ini"]
    rig = np.array(b.campo("Object", o, "obmat"), np.float64).reshape(4, 4).T
    arm = b.por_ptr.get(b.campo("Object", o, "data"))
    out = {}

    def visita(off, pai):
        for x in b.listbase(off, "Bone"):
            n = b.campo("Bone", x, "name")
            M = np.array(b.campo("Bone", x, "arm_mat"), np.float64).reshape(4, 4).T
            out[n] = (pai, rig @ M)
            visita(x + b.off_campo("Bone", "childbase"), n)
    visita(arm["ini"] + b.off_campo("bArmature", "bonebase"), None)
    return out


def textura(pasta, mat, img_blend, tam):
    """procura a textura de cor (e de transparência) pelo nome do material"""
    if not pasta:
        return None
    arqs = {f.lower(): os.path.join(r, f) for r, _, fs in os.walk(pasta) for f in fs}
    def ach(*suf):
        for s in suf:
            for ext in (".png", ".jpg", ".jpeg", ".tga"):
                k = (mat + s + ext).lower()
                if k in arqs:
                    return arqs[k]
        return None
    cor = ach("_diffuse", "_basecolor", "_alb", "_diffuse_001")
    if cor is None and img_blend:
        nome = img_blend.replace("\\", "/").split("/")[-1].lower()
        for troca in ("_specular", "_normal", "_bump", "_metallicroughness", "_opacity"):
            nome = nome.replace(troca, "_diffuse")
        base = os.path.splitext(nome)[0]
        for ext in (".png", ".jpg", ".jpeg", ".tga"):
            if base + ext in arqs:
                cor = arqs[base + ext]
                break
        if cor is None:
            for ext in (".png", ".jpg", ".jpeg", ".tga"):
                if base.replace("_diffuse", "_basecolor") + ext in arqs:
                    cor = arqs[base.replace("_diffuse", "_basecolor") + ext]
    opa = ach("_opacity", "_transparency")
    if cor is None and opa is None:
        return None
    im = Image.open(cor).convert("RGB") if cor else Image.new("RGB", (256, 256), (40, 30, 25))
    if max(im.size) > tam:
        k = tam / max(im.size)
        im = im.resize((int(im.size[0] * k), int(im.size[1] * k)), Image.LANCZOS)
    alfa = None
    if opa:
        alfa = Image.open(opa).convert("L").resize(im.size, Image.LANCZOS)
    elif cor and cor.lower().endswith((".png", ".tga")):
        a = Image.open(cor)
        if a.mode in ("RGBA", "LA"):
            alfa = a.getchannel("A").resize(im.size, Image.LANCZOS)
            if np.array(alfa).min() > 250:
                alfa = None
    buf = io.BytesIO()
    if alfa is not None:
        im.putalpha(alfa)
        im.save(buf, "PNG", optimize=True)
        return buf.getvalue(), "image/png", True
    im.save(buf, "JPEG", quality=88)
    return buf.getvalue(), "image/jpeg", False


def converter(arq, pasta_tex, saida, pular=(), tam_tex=1024, tam_pele=2048, ocultar=None, folga=0.035):
    b = Blend(arq)
    objs = []
    rig_ptr = None
    for o in b.objetos():
        if o["nome"] in pular or o["nome"].startswith("cs_"):
            continue
        arm = None
        for md in b.listbase(o["ob_ini"] + b.off_campo("Object", "modifiers"), "ModifierData"):
            if b.campo("ModifierData", md, "type") == 8:
                arm = b.campo("ArmatureModifierData", md, "object")
        if not arm:
            continue
        rig_ptr = rig_ptr or arm
        objs.append(o)
    ossos = armadura(b, rig_ptr)
    # grupos usados
    usados = set()
    dados = []
    for o in objs:
        gn = grupos(b, o["me_ini"])
        pw = pesos(b, o["me_ini"], len(o["co"]))
        dados.append((o, gn, pw))
        for lst in pw or []:
            for g, w in lst:
                if w > 0 and g < len(gn) and gn[g] in ossos:
                    usados.add(gn[g])
    mixamo_direto = "Hips" in ossos
    # nome final de cada osso usado
    nome_final = {}
    if mixamo_direto:
        for n in ossos:
            nome_final[n] = n
    else:
        for mx, cands in ARP.items():
            for cnd in cands:
                if cnd in ossos:
                    nome_final[cnd] = mx
                    break
    sel = set(usados) | set(nome_final)
    if mixamo_direto:
        sel = set(ossos)
    # pai de cada osso escolhido: pai Mixamo se for papel conhecido, senão o ancestral escolhido mais perto
    final_de = {}
    for n in sel:
        final_de[n] = nome_final.get(n, n)
    por_final = {v: k for k, v in final_de.items()}
    # osso solto (pendurado no controle raiz do Auto-Rig Pro): vai pro osso do Mixamo em cujo segmento ele fica
    segs = []
    for f, n in por_final.items():
        h = ossos[n][1][:3, 3]
        filhos = [por_final[c] for c, pf in PAI_MIXAMO.items() if pf == f and c in por_final]
        if not filhos:
            segs.append((n, h, h))
        for c in filhos:
            segs.append((n, h, ossos[c][1][:3, 3]))

    def segmento_mais_perto(pt, fora=None):
        melhor, dm = None, 1e9
        for n, h, t in segs:
            if n == fora:
                continue
            v = t - h
            k = 0.0 if v @ v < 1e-12 else float(np.clip((pt - h) @ v / (v @ v), 0, 1))
            d = np.linalg.norm(pt - (h + k * v))
            if d < dm - 1e-6:
                melhor, dm = n, d
        return melhor

    pai = {}
    for n in sel:
        f = final_de[n]
        if f in PAI_MIXAMO and PAI_MIXAMO[f] in por_final:
            pai[n] = por_final[PAI_MIXAMO[f]]
            continue
        if f == "Hips":
            pai[n] = None
            continue
        q = ossos[n][0]
        while q is not None and q not in sel:
            q = ossos[q][0]
        if q is None and not mixamo_direto:
            q = segmento_mais_perto(ossos[n][1][:3, 3], n)
        pai[n] = q
    # ordem: pais antes dos filhos
    ordem = []
    vis = set()
    def add(n):
        if n in vis:
            return
        if pai[n] is not None:
            add(pai[n])
        vis.add(n)
        ordem.append(n)
    for n in sorted(sel):
        add(n)
    idx = {n: i for i, n in enumerate(ordem)}
    G = {n: C4 @ ossos[n][1] for n in ordem}
    # ---------------- malhas
    prims = []
    mats_j, imgs_j, texs_j = [], [], []
    mat_idx = {}
    blobs = []
    off = 0
    views, accs = [], []

    def add_view(dados_b, alvo=None):
        nonlocal off
        pad = (-len(dados_b)) % 4
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(dados_b)}
        if alvo:
            v["target"] = alvo
        views.append(v)
        blobs.append(dados_b + b"\0" * pad)
        off += len(dados_b) + pad
        return len(views) - 1

    def acc(arr, tipo, comp, alvo=34962, mm=False, norm=False):
        vi = add_view(np.ascontiguousarray(arr).tobytes(), alvo)
        a = {"bufferView": vi, "componentType": comp, "count": int(len(arr)), "type": tipo}
        if norm:
            a["normalized"] = True
        if mm:
            a["min"] = np.asarray(arr).min(0).tolist()
            a["max"] = np.asarray(arr).max(0).tolist()
        accs.append(a)
        return len(accs) - 1

    def material(m):
        nome = m["nome"]
        if nome in mat_idx:
            return mat_idx[nome]
        pele = "skin" in nome.lower() or "avatar" in nome.lower()
        t = textura(pasta_tex, nome, m["img"][0] if m["img"] else None, tam_pele if pele else tam_tex)
        mj = {"name": nome, "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.7,
                                                    "baseColorFactor": [float(x) for x in list(m["cor"][:3]) + [1.0]]}}
        if t:
            vi = add_view(t[0])
            imgs_j.append({"bufferView": vi, "mimeType": t[1]})
            texs_j.append({"source": len(imgs_j) - 1})
            mj["pbrMetallicRoughness"]["baseColorTexture"] = {"index": len(texs_j) - 1}
            mj["pbrMetallicRoughness"]["baseColorFactor"] = [1, 1, 1, 1]
            if t[2]:
                mj["alphaMode"] = "MASK" if not any(k in nome.lower() for k in ("lash", "tear", "occlusion", "hair", "beard", "lente")) else "BLEND"
                mj["alphaCutoff"] = 0.4
                mj["doubleSided"] = True
        if any(k in nome.lower() for k in ("cornea", "occlusion", "tearline", "lente")):
            mj["alphaMode"] = "BLEND"
            mj["pbrMetallicRoughness"]["baseColorFactor"][3] = 0.25 if "cornea" in nome.lower() or "lente" in nome.lower() else 0.0
        mats_j.append(mj)
        mat_idx[nome] = len(mats_j) - 1
        return mat_idx[nome]

    total = 0
    mundo = {}
    for o, gn, pw in dados:
        M = C4 @ (o["mat"].T)
        mundo[o["nome"]] = (np.c_[o["co"], np.ones(len(o["co"]))] @ M.T)[:, :3]
    # pele escondida embaixo da roupa: sai (senão fura a roupa quando o corpo mexe)
    tira_vert = {}
    if ocultar:
        from scipy.spatial import cKDTree
        for corpo, roupas in ocultar.items():
            if corpo not in mundo:
                continue
            cobre = np.zeros(len(mundo[corpo]), bool)
            for r in roupas:
                if r not in mundo:
                    continue
                ro = next(o for o, _, _ in dados if o["nome"] == r)
                conta = {}
                for ls, tl in zip(ro["ls"], ro["tl"]):
                    ids = [int(ro["lv"][q]) for q in range(ls, ls + tl)]
                    for k in range(tl):
                        e = tuple(sorted((ids[k], ids[(k + 1) % tl])))
                        conta[e] = conta.get(e, 0) + 1
                borda = sorted({v for e, c in conta.items() if c == 1 for v in e})
                d1, _ = cKDTree(mundo[r]).query(mundo[corpo])
                d2 = cKDTree(mundo[r][borda]).query(mundo[corpo])[0] if borda else np.full(len(mundo[corpo]), 9.0)
                cobre |= (d1 < folga) & (d2 > 0.05)
            tira_vert[corpo] = cobre
            print("  %s: %d de %d vértices escondidos pela roupa" % (corpo, cobre.sum(), len(cobre)))
    for o, gn, pw in dados:
        co = mundo[o["nome"]]
        # pesos -> 4 maiores
        J = np.zeros((len(co), 4), np.uint16)
        W = np.zeros((len(co), 4), np.float32)
        for i, lst in enumerate(pw or []):
            l2 = [(idx[gn[g]], w) for g, w in lst if w > 0.0 and g < len(gn) and gn[g] in idx]
            if not l2 and gn:
                continue
            l2.sort(key=lambda x: -x[1])
            l2 = l2[:4]
            s = sum(w for _, w in l2) or 1.0
            for k, (j, w) in enumerate(l2):
                J[i, k] = j
                W[i, k] = w / s
        sem = W.sum(1) == 0
        if sem.any():   # vértice sem peso: preso no osso mais perto
            hp = np.array([G[n][:3, 3] for n in ordem])
            d = np.linalg.norm(co[sem][:, None, :] - hp[None], axis=2)
            J[sem, 0] = d.argmin(1)
            W[sem, 0] = 1.0
        # faces por material
        por_mat = {}
        tv = tira_vert.get(o["nome"])
        for p_i, (ls, tl, mn) in enumerate(zip(o["ls"], o["tl"], o["mn"])):
            if tv is not None and all(tv[int(o["lv"][q])] for q in range(ls, ls + tl)):
                continue
            por_mat.setdefault(int(mn), []).append((ls, tl))
        for mn, polis in por_mat.items():
            if mn >= len(o["mats"]):
                continue
            vs, uvs = [], []
            for ls, tl in polis:
                ids = list(range(ls, ls + tl))
                for k in range(1, tl - 1):
                    for q in (ids[0], ids[k], ids[k + 1]):
                        vs.append(o["lv"][q])
                        uvs.append(o["uv"][q] if o["uv"] is not None else (0.0, 0.0))
            vs = np.array(vs)
            UV = np.array(uvs, np.float32).reshape(-1, 2)
            UV[:, 1] = 1.0 - UV[:, 1]
            P = co[vs].astype(np.float32)
            T = P.reshape(-1, 3, 3)
            fn = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
            # normal suave por vértice original
            nv = np.zeros((len(co), 3))
            np.add.at(nv, vs.reshape(-1, 3)[:, 0], fn)
            np.add.at(nv, vs.reshape(-1, 3)[:, 1], fn)
            np.add.at(nv, vs.reshape(-1, 3)[:, 2], fn)
            N = nv[vs]
            N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
            chave = np.round(np.c_[P / 1e-5, UV / 1e-5, vs[:, None]]).astype(np.int64)
            _, iu, inv = np.unique(chave, axis=0, return_index=True, return_inverse=True)
            prims.append({"attributes": {"POSITION": acc(P[iu], "VEC3", 5126, mm=True), "NORMAL": acc(N[iu].astype(np.float32), "VEC3", 5126),
                                         "TEXCOORD_0": acc(UV[iu], "VEC2", 5126), "JOINTS_0": acc(J[vs][iu], "VEC4", 5123),
                                         "WEIGHTS_0": acc(W[vs][iu], "VEC4", 5126)},
                          "indices": acc(inv.ravel().astype(np.uint32), "SCALAR", 5125, 34963), "material": material(o["mats"][mn])})
            total += len(vs) // 3
    # ---------------- nós
    nodes = [{"name": "Personagem", "children": [1, 2]}, {"name": "Corpo", "mesh": 0, "skin": 0}, {"name": "Armature", "children": []}]
    base = 3
    for i, n in enumerate(ordem):
        Gi = G[n]
        Lm = Gi if pai[n] is None else np.linalg.inv(G[pai[n]]) @ Gi
        t = Lm[:3, 3]
        R = Lm[:3, :3]
        s = np.linalg.norm(R, axis=0)
        R = R / s
        from scipy.spatial.transform import Rotation as Rot
        q = Rot.from_matrix(R).as_quat()
        nd = {"name": "mixamorig:" + final_de[n] if final_de[n] in PAI_MIXAMO or final_de[n] == "Hips" else final_de[n],
              "translation": t.tolist(), "rotation": q.tolist()}
        if np.abs(s - 1).max() > 1e-3:
            nd["scale"] = s.tolist()
        filhos = [base + idx[c] for c in ordem if pai[c] == n]
        if filhos:
            nd["children"] = filhos
        nodes.append(nd)
    nodes[2]["children"] = [base + idx[n] for n in ordem if pai[n] is None]
    ibm = np.array([np.linalg.inv(G[n]).T.ravel() for n in ordem], np.float32)
    skin = {"joints": [base + i for i in range(len(ordem))], "inverseBindMatrices": acc(ibm, "MAT4", 5126, alvo=None), "skeleton": 2}
    views[accs[skin["inverseBindMatrices"]]["bufferView"]].pop("target", None)
    j = {"asset": {"version": "2.0", "generator": "Drops personagem_blend.py"}, "scene": 0, "scenes": [{"nodes": [0]}],
         "nodes": nodes, "meshes": [{"name": "Corpo", "primitives": prims}], "skins": [skin],
         "materials": mats_j, "accessors": accs, "bufferViews": views, "buffers": [{"byteLength": off}]}
    if imgs_j:
        j["images"] = imgs_j
        j["textures"] = texs_j
    js = json.dumps(j).encode()
    js += b" " * ((-len(js)) % 4)
    binb = b"".join(blobs)
    with open(saida, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binb)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(binb), 0x004E4942) + binb)
    print("%s: %d ossos, %d triângulos, %d materiais, %.1f MB" % (saida, len(ordem), total, len(mats_j), os.path.getsize(saida) / 1e6))


if __name__ == "__main__":
    a = sys.argv[1:]
    pul = ()
    if "--pular" in a:
        i = a.index("--pular")
        pul = tuple(a[i + 1].split(","))
        a = a[:i] + a[i + 2:]
    oc = None
    if "--ocultar" in a:   # corpo:roupa1+roupa2
        i = a.index("--ocultar")
        c, r = a[i + 1].split(":")
        oc = {c: r.split("+")}
        a = a[:i] + a[i + 2:]
    converter(a[0], a[1], a[2], pul, ocultar=oc)
