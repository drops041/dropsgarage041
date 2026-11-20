"""IMPORTADOR DE CARROS — Drops Garage Racha
Pega qualquer carro em .glb (Sketchfab, CGTrader, Blender...) e deixa pronto pro jogo:
  - acerta escala (metros) e direção (frente pra +Z, como o jogo usa)
  - acha as rodas originais (pelo nome ou pelo formato), mede os eixos, a bitola e o raio
    e marca elas pra sumir (as rodas do jogo entram no lugar, com aro/tala/cambagem trocáveis)
  - etiqueta os materiais: PAINT (lataria, recebe a pintura), GLASS, LUZ (farol), TAIL (lanterna),
    CROMO, PNEU, ARO, INTERIOR — todo o resto fica com o material PBR original do modelo
  - alisa as normais da lataria aqui mesmo (o Godot gera os níveis de detalhe/LOD em cima disso)
  - diminui texturas gigantes (padrão: no máximo 2048 px) pra rodar no celular
  - grava modelos/carros/<id>.glb e cria/atualiza o carro no carros.json
  - gera uma imagem de conferência (lado e cima, com as rodas achadas) em ferramentas/conferencia/<id>.png

Uso:
  python3 ferramentas/importar_carro.py MODELO.glb --id saveirog5 --nome "Saveiro G5 Cross" [opções]
Opções:
  --sub "VW · Cross · suspensão a ar"   texto embaixo do nome
  --picape                              tem caçamba (som deitado/em pé, tampão, santo antônio, capota)
  --comprimento 4.49                    comprimento real em metros (acerta a escala se o modelo vier errado)
  --virar                               se a conferência mostrar o carro de ré, roda 180°
  --pintura NOME                        força qual material é a lataria (nome do material no modelo)
  --max-textura 2048                    lado máximo das texturas
  --base saveiro                        copia o "padrão" (cor, roda, som...) de outro carro do jogo
Também:
  python3 ferramentas/importar_carro.py --alisar modelos/carros/x.glb   (só alisa a lataria de um modelo que já está no jogo)
"""
import argparse
import io
import re
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB, normais_lisas  # noqa: E402

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

CHAVES = [
    ("PAINT", ["paint", "carpaint", "car_paint", "body", "lataria", "carroceria", "karosserie", "exterior_color", "bodycolor"]),
    ("GLASS", ["glass", "window", "vidro", "janela", "windshield", "parabrisa", "windscreen"]),
    ("TAIL", ["tail", "lanterna", "rear_light", "rearlight", "brake", "freio"]),
    ("LUZ", ["headlight", "head_light", "farol", "lamp", "light", "pisca", "indicator", "blinker"]),
    ("CROMO", ["chrome", "cromo", "cromado", "mirror", "espelho", "polished"]),
    ("PNEU", ["tire", "tyre", "pneu", "rubber"]),
    ("ARO", ["rim", "wheel", "aro", "llanta", "felge"]),
    ("INTERIOR", ["interior", "seat", "banco", "dash", "painel", "carpet", "couro", "leather", "steering", "volante"]),
]
TAGS = {"PAINT", "GLASS", "LENS", "TAIL", "TAILGLASS", "CROMO", "PNEU", "ARO", "INTERIOR"}


NAO_RODA = ("wheelhouse", "wheel_house", "wheelarch", "wheel_arch", "brake", "rotor", "caliper", "steer", "volante", "freio", "pinça")
FREIO = ("brake", "rotor", "caliper", "disc_brake", "freio", "pinça")


def etiqueta_nome(nome):
    n = nome.lower()
    if "steering" in n or "volante" in n:
        return "INTERIOR"
    if any(k in n for k in NAO_RODA):
        return None
    for tag, ks in CHAVES:
        if any((re.search(r"(?<!t)rim", n) if k == "rim" else k in n) for k in ks):
            return tag
    return None


def etiqueta_existente(nome):
    t = nome.split("__")[0]
    if t in TAGS or t.startswith("LUZ"):
        return t
    return None


def textura(mat):
    return "baseColorTexture" in mat.get("pbrMetallicRoughness", {})


def cor_base(mat):
    return mat.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])


def area(pw, idx):
    t = idx.reshape(-1, 3)
    a, b, c = pw[t[:, 0]], pw[t[:, 1]], pw[t[:, 2]]
    return float(np.linalg.norm(np.cross(b - a, c - a), axis=1).sum() / 2)


# ------------------------------------------------------------------ alisar lataria
def alisar(g: GLB, so_paint=True):
    feitos = 0
    mats = g.j.get("materials", [])
    vistos = set()
    for m in g.j.get("meshes", []):
        for p in m["primitives"]:
            mi = p.get("material")
            if mi is None:
                continue
            nome = mats[mi].get("name", "")
            if nome.split("__")[0] != "PAINT" or "__liso" in nome:
                continue   # não é lataria, ou já foi alisada antes
            at = p["attributes"]
            pos = g.accessor(at["POSITION"])
            idx = g.accessor(p["indices"]).ravel().astype(np.int64) if "indices" in p else np.arange(len(pos))
            ref = g.accessor(at["NORMAL"]) if "NORMAL" in at else None
            if len(pos) > 60000:
                vistos.add(mi)   # modelo detalhado já vem liso: só marca (igual o jogo fazia)
                continue
            n = normais_lisas(pos, idx, ref)
            at["NORMAL"] = g.add_accessor_vec3(n)
            at.pop("TANGENT", None)   # o Godot recalcula
            feitos += 1
            vistos.add(mi)
    for mi in vistos:
        nome = mats[mi].get("name", "PAINT")
        if "__liso" not in nome:
            mats[mi]["name"] = nome + "__liso" if "__" in nome else "PAINT__liso"
    return feitos


# ------------------------------------------------------------------ texturas
def reduzir_texturas(g: GLB, lado_max):
    from PIL import Image
    ganho = 0
    for im in g.j.get("images", []):
        if "bufferView" not in im:
            continue
        vi = im["bufferView"]
        raw = g.view_bytes(vi)
        try:
            pic = Image.open(io.BytesIO(raw))
            pic.load()
        except Exception:
            continue
        if max(pic.size) <= lado_max:
            continue
        k = lado_max / max(pic.size)
        nova = pic.resize((max(1, int(pic.size[0] * k)), max(1, int(pic.size[1] * k))), Image.LANCZOS)
        out = io.BytesIO()
        tem_alfa = nova.mode in ("RGBA", "LA") or "transparency" in nova.info
        if tem_alfa or im.get("mimeType") == "image/png":
            nova.save(out, "PNG", optimize=True)
            im["mimeType"] = "image/png"
        else:
            nova.convert("RGB").save(out, "JPEG", quality=90)
            im["mimeType"] = "image/jpeg"
        ganho += len(raw) - len(out.getvalue())
        g.extra_views[vi] = out.getvalue()
    return ganho


# ------------------------------------------------------------------ rodas
def achar_rodas(prims, mats_tag, C):
    """devolve (lista de 4 rodas [centro x,y,z, raio, largura], nós a esconder, como achou)"""
    pts_roda = []
    nos_esconder = set()
    # 1) materiais de pneu/aro
    for p in prims:
        if p["mat"] is not None and mats_tag.get(p["mat"]) in ("PNEU", "ARO"):
            pts_roda.append(p["pc"])
    como = "material de pneu/aro" if pts_roda else ""
    # 2) peças com nome de roda/pneu, ou com formato de roda (redonda, de pé, nos cantos de baixo)
    zmin, zmax = C["zmin"], C["zmax"]
    L = zmax - zmin
    for p in prims:
        pc = p["pc"]
        lo, hi = pc.min(0), pc.max(0)
        tam = hi - lo
        cen = (lo + hi) / 2
        nome = p["nome"].lower().split("/")[-1]
        por_nome = (any(k in nome for k in ("wheel", "tire", "tyre", "pneu", "roda", "llanta")) or re.search(r"(?<!t)rim", nome)) and not any(k in nome for k in NAO_RODA)
        if any(k in nome for k in FREIO) and tam[1] < 0.9 and cen[1] < 0.7:
            nos_esconder.add(p["no"])   # disco/pinça de freio original: some junto (a roda do jogo pode ser menor)
            continue
        redonda = (0.35 * L * 0.12 < tam[1] < 0.95 and abs(tam[1] - tam[2]) < 0.25 * tam[1] and tam[0] < 0.5
                   and cen[1] < 0.6 and abs(cen[0]) > 0.3 and (cen[2] - zmin < 0.42 * L or zmax - cen[2] < 0.42 * L))
        if (por_nome and tam[1] < 1.0 and cen[1] < 0.7) or (redonda and tam[1] > 0.3):
            pts_roda.append(pc)
            nos_esconder.add(p["no"])
            como = como or ("nome das peças" if por_nome else "formato das peças")
    if not pts_roda:
        return None, set(), "não achei"
    ychao = min(q[:, 1].min() for q in pts_roda)
    pts_roda = [q for q in pts_roda if q[:, 1].min() < ychao + 0.3]   # estepe na caçamba / no teto não conta
    P = np.concatenate(pts_roda)
    zc = (zmin + zmax) / 2
    rodas = []
    for sx in (-1, 1):
        for sz in (1, -1):
            q = P[(np.sign(P[:, 0] + 1e-9) == sx) & (np.sign(P[:, 2] - zc + 1e-9) == sz)]
            if len(q) < 8:
                return None, set(), "rodas incompletas (%s)" % como
            lo, hi = q.min(0), q.max(0)
            r = max(hi[1] - lo[1], hi[2] - lo[2]) / 2
            rodas.append([(lo[0] + hi[0]) / 2, lo[1] + r, (lo[2] + hi[2]) / 2, r, hi[0] - lo[0], lo[0], hi[0]])
    return rodas, nos_esconder, como


# ------------------------------------------------------------------ conferência
def conferencia(prims, rodas, C, arq):
    from PIL import Image, ImageDraw
    esc = 120
    L = C["zmax"] - C["zmin"]
    Wd = C["xmax"] - C["xmin"]
    Hh = C["ymax"] - C["ymin"]
    w = int((L + 0.6) * esc)
    img = Image.new("RGB", (w, int((Hh + Wd + 1.2) * esc)), (24, 24, 28))
    d = ImageDraw.Draw(img)
    for p in prims:
        pc = p["pc"][:: max(1, len(p["pc"]) // 4000)]
        cor = {"PAINT": (240, 200, 0), "GLASS": (90, 160, 230), "LUZ": (255, 255, 255), "TAIL": (230, 40, 40),
               "CROMO": (190, 190, 200), "PNEU": (60, 60, 60), "ARO": (120, 120, 130)}.get(p.get("tag"), (110, 110, 120))
        for x, y, z in pc:
            u = (z - C["zmin"] + 0.3) * esc
            d.point((u, (C["ymax"] - y + 0.3) * esc), cor)                       # lado (frente pra direita)
            d.point((u, (Hh + 0.9 + x - C["xmin"]) * esc), cor)                  # cima
    if rodas:
        for x, y, z, r, *_ in rodas:
            u = (z - C["zmin"] + 0.3) * esc
            v = (C["ymax"] - y + 0.3) * esc
            d.ellipse((u - r * esc, v - r * esc, u + r * esc, v + r * esc), outline=(0, 255, 120), width=3)
    d.text((8, 8), "FRENTE ->", fill=(0, 255, 120))
    img.save(arq)


# ------------------------------------------------------------------ importar
def importar(a):
    g = GLB(a.modelo)
    mats = g.j.setdefault("materials", [])
    prims = g.primitivas()
    if not prims:
        raise SystemExit("o modelo não tem malhas")
    todos = np.concatenate([p["pw"] for p in prims])
    lo, hi = todos.min(0), todos.max(0)
    tam = hi - lo
    avisos = []
    # ---- direção: comprimento no X? gira 90°
    R = np.eye(3)
    if tam[0] > tam[2] * 1.15:
        R = np.array([[0, 0, -1], [0, 1, 0], [1, 0, 0]], float)   # +X vira +Z
    # ---- etiquetas dos materiais
    tags = {}
    for mi, m in enumerate(mats):
        nome = m.get("name", "")
        t = etiqueta_existente(nome) or etiqueta_nome(nome)
        if t is None:
            bc = cor_base(m)
            pm = m.get("pbrMetallicRoughness", {})
            if m.get("alphaMode") == "BLEND" and bc[3] < 0.9 and not textura(m):
                t = "GLASS"
            elif pm.get("metallicFactor", 1.0) > 0.85 and pm.get("roughnessFactor", 1.0) < 0.3 and not textura(m):
                t = "CROMO"
            elif any(v > 0.5 for v in m.get("emissiveFactor", [0, 0, 0])):
                t = "TAIL" if bc[0] > 0.5 and bc[1] < 0.3 else "LUZ"
        if a.pintura:   # lista "mat1,mat2": só essas são lataria
            if nome in a.pintura.split(","):
                t = "PAINT"
            elif t == "PAINT":
                t = None
        if t:
            tags[mi] = "LUZ" if t.startswith("LUZ") else {"TAILGLASS": "TAIL", "LENS": "GLASS"}.get(t, t)
            nm_ = mats[mi].get("name", "")
            if tags[mi] == "LUZ" and re.search(r"wheelhouse|shadow|leather|lighter|lightgrey|light_grey|metallight|button", nm_, re.I):
                tags[mi] = "INTERIOR"   # "light" no nome mas não é farol (cor clara, sombra do para-lama...)
            elif tags[mi] == "LUZ" and re.search(r"red|stoplight", nm_, re.I):
                tags[mi] = "TAIL"
    # ---- escala
    def aplicar(pw, Rm, s):
        return (pw @ Rm.T) * s
    s = 1.0
    L0 = max(tam[0], tam[2])
    if a.comprimento:
        s = a.comprimento / L0
    elif not (2.8 < L0 < 7.5):
        for k in (0.01, 0.001, 0.1, 0.0254, 1 / 39.37):
            if 2.8 < L0 * k < 7.5:
                s = k
                break
        else:
            s = 4.3 / L0
        avisos.append("escala ajustada x%g (o modelo tinha %.2f de comprimento)" % (s, L0))
    for p in prims:
        p["pc"] = aplicar(p["pw"], R, s)
        p["tag"] = tags.get(p["mat"])
    # ---- frente/trás pelo farol e lanterna
    zc = np.mean([p["pc"][:, 2].mean() for p in prims])
    def media_z(tag):
        zs = [p["pc"][:, 2].mean() for p in prims if p["tag"] == tag]
        return np.mean(zs) if zs else None
    zf, zt = media_z("LUZ"), media_z("TAIL")
    if zf is None and zt is None:
        def media_nome(ks):
            zs = [p["pc"][:, 2].mean() for p in prims if any(k in p["nome"].lower() for k in ks)]
            return np.mean(zs) if zs else None
        zf = media_nome(("headlight", "head light", "headlamp", "farol"))
        zt = media_nome(("taillight", "tailight", "tail light", "lanterna"))
    virar = False
    if zf is not None and zt is not None:
        virar = zf < zt
    elif zf is not None:
        virar = zf < zc
    elif zt is not None:
        virar = zt > zc
    else:
        avisos.append("não achei farol nem lanterna: considerei a frente do modelo como +Z (confira a imagem; se estiver de ré use --virar)")
    if a.virar:
        virar = not virar
    if virar:
        R = np.diag([-1.0, 1.0, -1.0]) @ R
        for p in prims:
            p["pc"] = aplicar(p["pw"], R, s)
    allc = np.concatenate([p["pc"] for p in prims])
    lo, hi = allc.min(0), allc.max(0)
    C = dict(xmin=lo[0], xmax=hi[0], ymin=lo[1], ymax=hi[1], zmin=lo[2], zmax=hi[2])
    # centraliza no X antes de procurar as rodas
    dx = -(lo[0] + hi[0]) / 2
    for p in prims:
        p["pc"][:, 0] += dx
    C["xmin"] += dx
    C["xmax"] += dx
    # ---- lataria pelo nome da PEÇA ("...#Car_Paint", "Door_Carpaint"...) quando o material tem nome de cor
    if "PAINT" not in tags.values():
        for p in prims:
            nn = p["nome"].lower().replace(" ", "_")
            if p["mat"] is not None and any(k in nn for k in ("car_paint", "carpaint", "bodypaint", "body_paint")):
                tags[p["mat"]] = "PAINT"
        if "PAINT" in tags.values():
            for p in prims:
                p["tag"] = tags.get(p["mat"])
            avisos.append("lataria pelo nome das peças: " + ", ".join(sorted({mats[m].get("name", "?") for m, t in tags.items() if t == "PAINT"})))
    # ---- lataria: se nenhum material tem nome de lataria, pega o maior material opaco que cobre o carro todo
    if "PAINT" not in tags.values():
        cand = {}
        for p in prims:
            if p["mat"] is None or tags.get(p["mat"]):
                continue
            m = mats[p["mat"]]
            if m.get("alphaMode") == "BLEND":
                continue
            cand.setdefault(p["mat"], []).append(p)
        melhor, ma = None, 0
        for mi, ps in cand.items():
            pc = np.concatenate([q["pc"] for q in ps])
            cobre = (pc[:, 2].max() - pc[:, 2].min()) / (C["zmax"] - C["zmin"])
            ar = sum(area(q["pc"], q["idx"]) for q in ps)
            if cobre > 0.7 and ar > ma:
                melhor, ma = mi, ar
        if melhor is not None:
            tags[melhor] = "PAINT"
            for p in prims:
                if p["mat"] == melhor:
                    p["tag"] = "PAINT"
            avisos.append("lataria escolhida pelo tamanho: material '%s' (se errou, use --pintura NOME)" % mats[melhor].get("name", melhor))
        else:
            avisos.append("não achei a lataria: a cor não vai mudar (use --pintura NOME)")
    # ---- rodas
    rodas, esconder, como = achar_rodas(prims, tags, C)
    if rodas is None:
        L = C["zmax"] - C["zmin"]
        ra = 0.31
        rodas = []
        for sx in (-1, 1):
            for z in (C["zmax"] - 0.2 * L, C["zmin"] + 0.21 * L):
                x = sx * (C["xmax"] - 0.1)
                rodas.append([x, C["ymin"] + ra, z, ra, 0.2, x - 0.1, x + 0.1])
        avisos.append("rodas: %s — usei medidas estimadas (confira a imagem e ajuste axF/axR/wy no carros.json)" % como)
    else:
        avisos.append("rodas achadas por %s" % como)
    rd = np.array(rodas)
    chao = float((rd[:, 1] - rd[:, 3]).min())
    axF = float(rd[rd[:, 2] > 0, 2].mean() if (rd[:, 2] > 0).any() else rd[:, 2].max())
    zfrente = rd[:, 2].max()
    zr = rd[:, 2].min()
    axF = float(rd[np.isclose(rd[:, 2], zfrente, atol=0.4), 2].mean())
    axR = float(rd[np.isclose(rd[:, 2], zr, atol=0.4), 2].mean())
    dz = -(axF + axR) / 2
    axF += dz
    axR += dz
    dy = -chao
    wy = float(rd[:, 1].mean() + dy)
    ra = float(rd[:, 3].mean())
    Wb = float(rd[:, 6].max() - rd[:, 5].min())
    for p in prims:
        p["pc"] += [0, dy, dz]
    for r in rodas:
        r[1] += dy
        r[2] += dz
    for k in ("zmin", "zmax"):
        C[k] += dz
    C["ymin"] += dy
    C["ymax"] += dy
    # ---- aplica a transformação: um nó raiz novo em volta da cena
    M = np.eye(4)
    M[:3, :3] = R * s
    M[:3, 3] = (np.array([dx, dy, dz]))
    # a translação acontece depois da rotação/escala: (R*s*p) + t
    raizes = list(g.raizes())
    # esconde as rodas que eram peças separadas
    for no in g.j["nodes"]:
        if "children" in no:
            no["children"] = [c for c in no["children"] if c not in esconder]
    raizes = [r for r in raizes if r not in esconder]
    g.j["nodes"].append({"name": "CarroImportado", "matrix": M.T.ravel().tolist(), "children": raizes})
    novo = len(g.j["nodes"]) - 1
    g.j["scenes"] = [{"name": "carro", "nodes": [novo]}]
    g.j["scene"] = 0
    # ---- renomeia materiais com a etiqueta (o nome original fica depois do "__")
    for mi, t in tags.items():
        nome = mats[mi].get("name", "m%d" % mi)
        if etiqueta_existente(nome) is None:
            mats[mi]["name"] = "%s__%s" % (t if t != "LUZ" else "LUZ_head", nome)
    # ---- lataria lisa + texturas menores
    n_lisas = alisar(g)
    ganho = reduzir_texturas(g, a.max_textura)
    g.j.setdefault("asset", {})["generator"] = "Drops Garage importar_carro.py"
    destino = os.path.join(RAIZ, "modelos", "carros", a.id + ".glb")
    g.salvar(destino)
    # ---- caçamba (picape): onde a altura cai atrás da cabine
    entrada = dict(id=a.id, nome=a.nome or a.id, sub=a.sub or "importado", W=round(Wb, 3), axF=round(axF, 3), axR=round(axR, 3),
                   wy=round(wy, 3), ra=round(ra, 3), bed=None, som=None, tampao=False, trio=None, picape=bool(a.picape),
                   vmax=50, acc=8.5)
    allc = np.concatenate([p["pc"] for p in prims if p["tag"] not in ("PNEU", "ARO")])
    zs = np.linspace(C["zmin"], C["zmax"], 60)
    perfil = []
    for z0, z1 in zip(zs[:-1], zs[1:]):
        q = allc[(allc[:, 2] >= z0) & (allc[:, 2] < z1)]
        perfil.append(q[:, 1].max() if len(q) else 0)
    perfil = np.array(perfil)
    zmeio = (zs[:-1] + zs[1:]) / 2
    if a.picape:
        teto = perfil.max()
        atras = (zmeio < axR + 0.6)
        borda = float(np.median(perfil[atras & (zmeio > C["zmin"] + 0.15)])) if atras.any() else wy + 0.75
        cab = zmeio[(perfil > borda + 0.25)]
        z1 = float(cab.min()) - 0.05 if len(cab) else axR + 0.6
        z0 = float(C["zmin"]) + 0.08
        piso = borda - 0.25
        entrada.update(bed={"y": round(piso, 3), "z": round((z0 + z1) / 2, 3)}, tampao=True,
                       trio={"y": round(piso, 3), "z": round((z0 + z1) / 2 - 0.05, 3), "w": round(Wb - 0.38, 3), "d": 1.08},
                       tampa={"z0": round(z0, 3), "z1": round(z1, 3), "y": round(borda, 3)})
        avisos.append("caçamba estimada: borda %.2f m, de z=%.2f até %.2f (teto da cabine %.2f)" % (borda, z0, z1, teto))
    else:
        entrada["som"] = {"z": round(axR - 0.15, 3), "y": round(wy + 0.55, 3)}
    # ---- carros.json
    cj = os.path.join(RAIZ, "carros.json")
    carros = json.load(open(cj, encoding="utf8"))
    base = next((c for c in carros if c["id"] == (a.base or ("saveiro" if a.picape else "golg5"))), carros[0])
    entrada["padrao"] = dict(base["padrao"])
    entrada["padrao"]["placa"] = (a.id.upper().replace("_", "") + "0000000")[:7]
    velho = next((c for c in carros if c["id"] == a.id), None)
    if velho:
        for k in ("padrao", "vmax", "acc", "partes", "encaixes", "sub", "nome"):
            if k in velho and not (k in ("sub", "nome") and getattr(a, k)):
                entrada[k] = velho[k]
        carros[carros.index(velho)] = entrada
    else:
        carros.append(entrada)
    with open(cj, "w", encoding="utf8") as f:
        json.dump(carros, f, ensure_ascii=False, indent=1)
    os.makedirs(os.path.join(RAIZ, "ferramentas", "conferencia"), exist_ok=True)
    conf = os.path.join(RAIZ, "ferramentas", "conferencia", a.id + ".png")
    conferencia(prims, rodas, C, conf)
    print("== %s importado ==" % entrada["nome"])
    print("  arquivo: modelos/carros/%s.glb" % a.id)
    print("  comprimento %.2f m | largura nas rodas %.2f m | entre-eixos %.2f m | raio da roda original %.2f m"
          % (C["zmax"] - C["zmin"], Wb, axF - axR, ra))
    print("  materiais: " + ", ".join("%s=%d" % (t, list(tags.values()).count(t)) for t in sorted(set(tags.values()))))
    print("  lataria alisada em %d partes; texturas: %.1f MB a menos" % (n_lisas, ganho / 1e6))
    for av in avisos:
        print("  * " + av)
    print("  conferência: " + os.path.relpath(conf, RAIZ))


def main():
    ap = argparse.ArgumentParser(description="Importa um carro .glb pro jogo")
    ap.add_argument("modelo", nargs="?")
    ap.add_argument("--id")
    ap.add_argument("--nome")
    ap.add_argument("--sub")
    ap.add_argument("--picape", action="store_true")
    ap.add_argument("--comprimento", type=float)
    ap.add_argument("--virar", action="store_true")
    ap.add_argument("--pintura")
    ap.add_argument("--max-textura", type=int, default=2048)
    ap.add_argument("--base")
    ap.add_argument("--alisar")
    a = ap.parse_args()
    if a.alisar:
        g = GLB(a.alisar)
        n = alisar(g)
        g.salvar(a.alisar)
        print("%s: lataria alisada em %d partes" % (a.alisar, n))
        return
    if not a.modelo or not a.id:
        ap.error("informe o MODELO.glb e o --id")
    importar(a)


if __name__ == "__main__":
    main()
