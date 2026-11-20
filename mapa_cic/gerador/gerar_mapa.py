"""
Gera o mapa 3D (Godot 4.x) a partir de um export do OpenStreetMap.
uso: python3 gerar_mapa.py map.osm pasta_saida
Saída: pasta_saida/blocos/*.glb (+ tex/), mapa_cic.json, ruas.json, minimapa.png
"""
import sys, os, math, json, random, xml.etree.ElementTree as ET
import numpy as np, cv2
from scipy.spatial import cKDTree
from glb import MeshBuilder, write_glb
import texturas, pickle
from terreno import Terreno
LOTS_PKL = os.environ.get("LOTES", "/home/claude/geo/lots_local.pkl")
CURVAS_PKL = os.environ.get("CURVAS", "/home/claude/geo/curvas_local.pkl")
GEO_DESLOC = np.array([-1.0, -3.0])   # ajuste fino IPPUC (SAD69) -> OpenStreetMap, medido pelas ruas

OSM, OUT = sys.argv[1], sys.argv[2]
SEED = 2026
CH = 300.0           # tamanho do bloco (m)
TEX = 2048           # textura do chão por bloco
RES = CH / TEX       # m por pixel do chão
rnd = random.Random(SEED)
np_rng = np.random.default_rng(SEED)

# ----------------------------------------------------------------------------- leitura
root = ET.parse(OSM).getroot()
b = root.find("bounds")
minlat, maxlat = float(b.get("minlat")), float(b.get("maxlat"))
minlon, maxlon = float(b.get("minlon")), float(b.get("maxlon"))
lat0, lon0 = (minlat + maxlat) / 2, (minlon + maxlon) / 2
KX = 111320.0 * math.cos(math.radians(lat0)); KZ = 110574.0


def proj(lat, lon):
    return ((lon - lon0) * KX, -(lat - lat0) * KZ)


def unproj(x, z):
    return (lat0 - z / KZ, lon0 + x / KX)


XMIN, ZMIN = proj(maxlat, minlon)
XMAX, ZMAX = proj(minlat, maxlon)
NX, NZ = math.ceil((XMAX - XMIN) / CH), math.ceil((ZMAX - ZMIN) / CH)
print(f"área {XMAX-XMIN:.0f} x {ZMAX-ZMIN:.0f} m -> {NX} x {NZ} blocos")

nodes, ntags = {}, {}
for n in root.findall("node"):
    i = n.get("id")
    nodes[i] = proj(float(n.get("lat")), float(n.get("lon")))
    t = {x.get("k"): x.get("v") for x in n.findall("tag")}
    if t:
        ntags[i] = t
ways = {}
for w in root.findall("way"):
    nd = [x.get("ref") for x in w.findall("nd") if x.get("ref") in nodes]
    ways[w.get("id")] = (nd, {x.get("k"): x.get("v") for x in w.findall("tag")})
rels = []
for r in root.findall("relation"):
    t = {x.get("k"): x.get("v") for x in r.findall("tag")}
    mem = [(m.get("ref"), m.get("role")) for m in r.findall("member") if m.get("type") == "way"]
    rels.append((t, mem))


def coords(nd):
    return np.array([nodes[i] for i in nd], float)


def assemble_rings(wids):
    segs = [list(ways[w][0]) for w in wids if w in ways and len(ways[w][0]) > 1]
    rings = []
    while segs:
        ring = segs.pop(0)
        changed = True
        while ring[0] != ring[-1] and changed:
            changed = False
            for k, s in enumerate(segs):
                if s[0] == ring[-1]: ring += s[1:]
                elif s[-1] == ring[-1]: ring += s[::-1][1:]
                elif s[-1] == ring[0]: ring = s + ring[1:]
                elif s[0] == ring[0]: ring = s[::-1] + ring[1:]
                else: continue
                segs.pop(k); changed = True; break
        if len(ring) >= 4:
            rings.append(coords(ring))
    return rings


def lin(rgb, a=1.0):
    return [(c / 255.0) ** 2.2 for c in rgb] + [a]


def jitter(rgb, amt=12):
    return tuple(max(0, min(255, c + rnd.randint(-amt, amt))) for c in rgb)


# ----------------------------------------------------------------------------- ruas
ROAD = {  # largura pista, calçada, prioridade
    "motorway": (7.6, 0, 9), "motorway_link": (5.0, 0, 8), "trunk": (10, 0, 8), "trunk_link": (5, 0, 7),
    "primary": (11, 2.5, 7), "primary_link": (6, 1.5, 6), "secondary": (10, 2.5, 6), "secondary_link": (6, 1.5, 5),
    "tertiary": (8.5, 2.5, 5), "tertiary_link": (6, 1.5, 4), "unclassified": (7, 2.0, 3),
    "residential": (7, 2.2, 3), "living_street": (6, 1.5, 2), "busway": (7, 0, 4), "service": (4.5, 0, 2),
    "track": (3.5, 0, 1), "pedestrian": (4, 0, 0), "footway": (1.8, 0, 0), "path": (1.5, 0, 0),
    "cycleway": (2.2, 0, 0), "steps": (1.8, 0, 0),
}
CAR = {"motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link", "secondary", "secondary_link",
       "tertiary", "tertiary_link", "unclassified", "residential", "living_street", "busway", "service", "track"}
HOUSE_ROADS = {"residential", "tertiary", "secondary", "primary", "unclassified", "living_street", "tertiary_link"}
UNPAVED = {"unpaved", "dirt", "ground", "gravel", "earth", "grass", "sand", "fine_gravel", "compacted", "mud"}

roads = []
for wid, (nd, t) in ways.items():
    hw = t.get("highway")
    if hw not in ROAD or t.get("area") == "yes" or len(nd) < 2:
        continue
    w, sw, rank = ROAD[hw]
    lt = t.get("lanes", "").split(";")[0]
    if lt.isdigit() and hw in CAR and int(lt) > 0:
        ln = int(lt)
        if not (hw in ("residential", "unclassified", "service") and ln <= 2):
            w = max(w if hw.startswith("motorway") else 6.0, ln * 3.4)
    if t.get("sidewalk") == "no": sw = 0
    surf = t.get("surface", "")
    if hw == "track" and not surf: surf = "unpaved"
    kind = "asfalto"
    if surf in UNPAVED: kind = "terra_rua"
    elif surf in ("sett", "cobblestone", "unhewn_cobblestone", "paving_stones"): kind = "paralelepipedo"
    elif hw == "busway": kind = "concreto"
    if hw not in CAR:
        kind = "trilha" if surf in UNPAVED else "concreto"
    if kind == "terra_rua": sw = 0
    pts = coords(nd)
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    if seg.sum() < 0.5: continue
    roads.append(dict(id=wid, nd=nd, pts=pts, cls=hw, w=float(w), sw=float(sw), rank=rank, kind=kind,
                      car=hw in CAR, oneway=t.get("oneway") in ("yes", "1") or hw in ("motorway",),
                      lanes=int(t["lanes"]) if t.get("lanes", "").isdigit() else None,
                      name=t.get("name", ""), cum=np.concatenate([[0], np.cumsum(seg)]),
                      bridge=t.get("bridge") == "yes"))
print("ruas:", len(roads))

# nós de cruzamento (usados por 2+ ruas de carro ou no meio de outra)
use = {}
for r in roads:
    if not r["car"]: continue
    for k, i in enumerate(r["nd"]):
        use.setdefault(i, []).append(r)
junction = {i: max(rr["w"] for rr in rs) for i, rs in use.items() if len(rs) >= 2}
jpts = np.array([nodes[i] for i in junction]) if junction else np.zeros((0, 2))
jrad = np.array([junction[i] for i in junction])
jtree = cKDTree(jpts)


def near_junction(p, extra=1.5):
    if len(jpts) == 0: return False
    idx = jtree.query_ball_point(p, 14)
    for k in idx:
        if np.linalg.norm(jpts[k] - p) < jrad[k] / 2 + extra: return True
    return False


def point_at(r, s):
    cum = r["cum"]; s = min(max(s, 0), cum[-1])
    k = min(np.searchsorted(cum, s, side="right") - 1, len(cum) - 2)
    p0, p1 = r["pts"][k], r["pts"][k + 1]
    L = cum[k + 1] - cum[k]
    t = (p1 - p0) / L if L > 1e-9 else np.array([1.0, 0])
    return p0 + t * (s - cum[k]), t


def perp(t):
    return np.array([-t[1], t[0]])


# ----------------------------------------------------------------------------- áreas
AREA_CLASS = [  # ordem de pintura
    ("landuse", "residential", "terreno"), ("landuse", "industrial", "industrial"), ("landuse", "commercial", "concreto"),
    ("landuse", "landfill", "aterro"), ("landuse", "grass", "grama"), ("leisure", "park", "grama"),
    ("landuse", "forest", "mata"), ("natural", "wood", "mata"), ("natural", "scrub", "mata"),
    ("leisure", "pitch", "campo"), ("amenity", "parking", "estacionamento"), ("amenity", "school", "terreno"),
    ("natural", "water", "agua"), ("landuse", "reservoir", "agua"), ("landuse", "basin", "agua"),
]
NOHOUSE_KIND = {"grama", "mata", "campo", "estacionamento", "agua", "aterro"}
areas = []  # (class, outer rings, inner rings, tags)


def area_class(t):
    c = None
    for k, v, cls in AREA_CLASS:
        if t.get(k) == v: c = cls
    return c


for wid, (nd, t) in ways.items():
    c = area_class(t)
    if c and len(nd) >= 4 and nd[0] == nd[-1]:
        areas.append((c, [coords(nd)], [], t))
for t, mem in rels:
    c = area_class(t)
    if c and t.get("type") == "multipolygon":
        outer = assemble_rings([w for w, ro in mem if ro in ("outer", "")])
        inner = assemble_rings([w for w, ro in mem if ro == "inner"])
        if outer: areas.append((c, outer, inner, t))
order = {cls: i for i, (_, _, cls) in enumerate(AREA_CLASS)}
areas.sort(key=lambda a: order.get(a[0], 0))
waterways = []
for wid, (nd, t) in ways.items():
    ww = t.get("waterway")
    if ww in ("stream", "river", "canal", "ditch", "drain") and len(nd) > 1:
        waterways.append((coords(nd), {"river": 9, "canal": 6}.get(ww, 2.5)))
print("áreas:", len(areas), "rios/córregos:", len(waterways))

# ----------------------------------------------------------------------------- raster de ocupação (1 m)
OR = 1.0
OW, OH = int(math.ceil((XMAX - XMIN) / OR)) + 1, int(math.ceil((ZMAX - ZMIN) / OR)) + 1
occ = np.zeros((OH, OW), np.uint8)
B_ROAD, B_CARR, B_BUILD, B_WATER, B_NOHOUSE, B_INDUS, B_TREE, B_RESERV = 1, 2, 4, 8, 16, 32, 64, 128
SH = 4


def opx(pts):
    return np.round((np.asarray(pts) - [XMIN, ZMIN]) / OR * (1 << SH)).astype(np.int32)


def occ_or(bit, draw):
    tmp = np.zeros_like(occ); draw(tmp); occ[tmp > 0] |= bit


for cls, outs, ins, t in areas:
    bit = B_NOHOUSE if cls in NOHOUSE_KIND or t.get("amenity") == "school" else (B_INDUS if cls == "industrial" else 0)
    if cls == "agua": bit |= B_WATER
    if bit:
        occ_or(bit, lambda m: cv2.fillPoly(m, [opx(o) for o in outs], 1, cv2.LINE_8, SH))
for pts, w in waterways:
    occ_or(B_WATER | B_NOHOUSE, lambda m: cv2.polylines(m, [opx(pts)], False, 1, max(1, int(w + 4)), cv2.LINE_8, SH))
for r in roads:
    tw = r["w"] + 2 * r["sw"]
    if r["cls"] in ("footway", "path", "cycleway", "steps"):   # calçada/caminho mapeado à parte não impede casa
        continue
    occ_or(B_ROAD, lambda m: cv2.polylines(m, [opx(r["pts"])], False, 1, max(1, int(round(tw / OR))), cv2.LINE_8, SH))
    if r["car"]:
        occ_or(B_CARR, lambda m: cv2.polylines(m, [opx(r["pts"])], False, 1, max(1, int(round(r["w"] / OR))), cv2.LINE_8, SH))


def occ_get(p):
    x = int((p[0] - XMIN) / OR); z = int((p[1] - ZMIN) / OR)
    if x < 2 or z < 2 or x >= OW - 2 or z >= OH - 2: return 255
    return occ[z, x]


def rect_pts(c, a, la, lb):
    bb = perp(a)
    return np.array([c - a * la / 2 - bb * lb / 2, c + a * la / 2 - bb * lb / 2,
                     c + a * la / 2 + bb * lb / 2, c - a * la / 2 + bb * lb / 2])


def rect_free(c, a, la, lb, bits, step=1.2):
    bb = perp(a)
    for u in np.linspace(-la / 2, la / 2, max(2, int(la / step) + 1)):
        for v in np.linspace(-lb / 2, lb / 2, max(2, int(lb / step) + 1)):
            if occ_get(c + a * u + bb * v) & bits: return False
    return True


def mark(poly, bit=B_BUILD):
    occ_or(bit, lambda m: cv2.fillConvexPoly(m, opx(poly), 1, cv2.LINE_8, SH))


# ----------------------------------------------------------------------------- objetos
objs = []          # especificações (dict com 'ref' = ponto 2D p/ escolher o bloco)
extra_ground = []  # (poligono, classe) pintados no chão
foot = []          # pegadas p/ sombra (poligono)
PAL_CASA_FOTOS = [(245, 245, 242), (245, 245, 242), (238, 238, 235), (205, 207, 208), (64, 168, 178), (95, 190, 195), (185, 214, 168),
                  (240, 200, 160), (230, 160, 90), (215, 172, 70), (200, 220, 230), (232, 228, 214)]
PAL_CASA = [(240, 238, 230), (238, 225, 190), (240, 220, 140), (232, 170, 140), (240, 195, 160), (190, 215, 170),
            (175, 205, 225), (205, 190, 220), (195, 195, 190), (235, 180, 190), (205, 130, 95), (170, 220, 200),
            (250, 250, 248), (225, 210, 175), (160, 190, 140), (120, 160, 200)]
PAL_MURO_FOTOS = [(242, 242, 240), (242, 242, 240), (178, 180, 180), (160, 163, 165), (205, 205, 200), (230, 220, 190), (196, 150, 50)]
PAL_MURO = [(235, 235, 230), (200, 200, 195), (230, 220, 190), (180, 175, 170), (225, 200, 160), (215, 170, 150)]
PAL_TELHA = [(190, 95, 60), (175, 85, 55), (200, 110, 70), (160, 80, 55), (185, 100, 75)]
PAL_GALPAO = [(225, 225, 225), (200, 205, 210), (110, 140, 180), (170, 170, 170), (220, 215, 200), (90, 120, 90)]

# --- prédios mapeados no OSM
osm_build = 0
for wid, (nd, t) in ways.items():
    if "building" not in t or len(nd) < 4 or nd[0] != nd[-1]: continue
    poly = coords(nd[:-1])
    c = poly.mean(0)
    if not (XMIN < c[0] < XMAX and ZMIN < c[1] < ZMAX): continue
    area = 0.5 * abs(np.dot(poly[:, 0], np.roll(poly[:, 1], -1)) - np.dot(poly[:, 1], np.roll(poly[:, 0], -1)))
    lv = t.get("building:levels")
    big = area > 450 or t["building"] in ("industrial", "warehouse", "roof") or (occ_get(c) & B_INDUS)
    if t.get("height"):
        try: h = float(t["height"].split()[0])
        except ValueError: h = 4
    elif lv and lv.replace(".", "").isdigit():
        h = float(lv) * 3.0 + 0.6
    else:
        h = rnd.uniform(7, 11) if big else rnd.choice([3.2, 3.2, 3.4, 6.2])
    roof_only = t["building"] == "roof"
    objs.append(dict(type="osm", ref=c, poly=poly, h=h, big=big, roof_only=roof_only,
                     wall="galpao" if big else "parede", col=rnd.choice(PAL_GALPAO if big else PAL_CASA),
                     roof="fibro" if big else rnd.choice(["laje", "fibro", "laje"])))
    foot.append(poly); mark(poly) if len(poly) < 5 else occ_or(B_BUILD, lambda m: cv2.fillPoly(m, [opx(poly)], 1, cv2.LINE_8, SH))
    osm_build += 1
print("prédios do OSM:", osm_build)

# --- localiza Rua Raul Pompéia, 1701 (numeração métrica de Curitiba)
CENTRO = proj(-25.4284, -49.2733)
shop = None
RP_SPAWN = None
rp = [r for r in roads if r["name"] == "Rua Raul Pompéia"]
if rp:
    # encadeia os trechos
    chain = [rp[0]["nd"][:]]; rest = rp[1:]
    seq = rp[0]["nd"][:]
    changed = True
    while changed and rest:
        changed = False
        for k, r in enumerate(rest):
            nd = r["nd"]
            if nd[0] == seq[-1]: seq += nd[1:]
            elif nd[-1] == seq[-1]: seq += nd[::-1][1:]
            elif nd[-1] == seq[0]: seq = nd + seq[1:]
            elif nd[0] == seq[0]: seq = nd[::-1] + seq[1:]
            else: continue
            rest.pop(k); changed = True; break
    P = coords(seq)
    if np.linalg.norm(P[0] - CENTRO) > np.linalg.norm(P[-1] - CENTRO): P = P[::-1]
    cum = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    ref_s, ref_n = None, 2673
    for wid, (nd, t) in ways.items():
        if t.get("addr:street") == "Rua Raul Pompéia" and t.get("addr:housenumber", "").isdigit():
            c = coords(nd).mean(0)
            d = np.linalg.norm(P - c, axis=1); k = int(d.argmin())
            ref_s, ref_n = cum[k], int(t["addr:housenumber"])
    fake = dict(pts=P, cum=cum, w=7.0, sw=2.2)
    s1701 = (ref_s - (ref_n - 1701)) if ref_s is not None else 1701 - (2673 - cum[-1])
    SHOP_INFO = dict(s1701=float(s1701), comprimento=float(cum[-1]))
    if not (5 < s1701 < cum[-1] - 5):
        if s1701 <= 5:
            p, t = point_at(fake, 25.0)
        else:
            p, t = point_at(fake, cum[-1] - 25.0); t = -t
        RP_SPAWN = (p, t)
        print("Raul Pompéia 1701 fica fora do recorte; distância além da borda (m):", round(-s1701 if s1701 < 0 else s1701 - cum[-1]))
    if 5 < s1701 < cum[-1] - 5:
        p, t = point_at(fake, s1701)
        side = -1.0   # ímpar à esquerda no sentido crescente (perp() aponta pra direita)
        nrm = perp(t) * side
        a = t
        fo = 3.5 + 2.2
        L, D, H = 14.0, 20.0, 6.5
        c = p + nrm * (fo + D / 2)
        bb = nrm
        shop = dict(type="loja", ref=c, c=c, a=a, b=bb, L=L, D=D, H=H, street_pt=p, t=t)
        objs.append(shop)
        poly = np.array([c - a * L / 2 - bb * D / 2, c + a * L / 2 - bb * D / 2, c + a * L / 2 + bb * D / 2, c - a * L / 2 + bb * D / 2])
        foot.append(poly); mark(np.array([c - a * (L / 2 + 3) - bb * D / 2, c + a * (L / 2 + 3) - bb * D / 2,
                                          c + a * (L / 2 + 3) + bb * (D / 2 + 3), c - a * (L / 2 + 3) + bb * (D / 2 + 3)]))
        print("loja (aprox.):", c.round(1), unproj(*c))


def nearest_road(p, car=True, maxd=60):
    best = None
    for r in roads:
        if car and not r["car"] or r["cls"] in ("service", "track"): continue
        P = r["pts"]
        a, bq = P[:-1], P[1:]
        d = bq - a; L2 = (d ** 2).sum(1) + 1e-9
        u = np.clip(((p - a) * d).sum(1) / L2, 0, 1)
        q = a + d * u[:, None]
        dist = np.linalg.norm(q - p, axis=1); k = int(dist.argmin())
        if dist[k] < maxd and (best is None or dist[k] < best[0]):
            t = d[k] / math.sqrt(L2[k])
            best = (dist[k], r, q[k], t)
    return best


# --- posto de gasolina e pontos de ônibus
POIS = {}
RESERVAS = []   # (nome, polígono a aplainar, chave do POI)
for i, t in ntags.items():
    p = np.array(nodes[i])
    if not (XMIN < p[0] < XMAX and ZMIN < p[1] < ZMAX): continue
    if t.get("amenity") == "fuel":
        nr = nearest_road(p)
        if not nr: continue
        _, r, q, tt = nr
        nrm = perp(tt); nrm = nrm if np.dot(p - q, nrm) >= 0 else -nrm
        fo_ = r["w"] / 2 + r["sw"]
        org = q + nrm * (fo_ + 16.5)
        POIS["posto"] = dict(pos=[float(org[0]), 0.0, float(org[1])], yaw=float(math.atan2(-nrm[0], -nrm[1])), nome=t.get("name", ""))
        pad = rect_pts(q + nrm * (fo_ + 19), tt, 86, 38)
        extra_ground.append((pad, "concreto")); mark(pad, B_BUILD | B_RESERV); RESERVAS.append(("posto", rect_pts(q + nrm * (fo_ + 19), tt, 90, 42), "posto"))
    elif t.get("highway") == "bus_stop":
        nr = nearest_road(p, maxd=25)
        if not nr: continue
        _, r, q, tt = nr
        nrm = perp(tt); nrm = nrm if np.dot(p - q, nrm) >= 0 else -nrm
        c = q + nrm * (r["w"] / 2 + max(r["sw"], 1.6) * 0.65)
        if occ_get(c) & B_CARR: continue
        objs.append(dict(type="ponto", ref=c, c=c, a=tt, b=nrm))

# --- Drops Garage (endereço real, numeração métrica a partir da ponta mais perto do centro)
DROPS_RUA, DROPS_NUM = "Rua Engenheiro Luiz Gastão Mendes Lima", 55
drops = None
dr = [r for r in roads if r["name"] == DROPS_RUA]
if dr:
    r0 = max(dr, key=lambda r: r["cum"][-1])
    P = r0["pts"].copy()
    if np.linalg.norm(P[0] - CENTRO) > np.linalg.norm(P[-1] - CENTRO): P = P[::-1]
    cum = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    fk = dict(pts=P, cum=cum)
    p, t = point_at(fk, min(DROPS_NUM, cum[-1] - 6))
    nrm = -perp(t)   # número ímpar = lado esquerdo
    fo = r0["w"] / 2 + r0["sw"]
    front = p + nrm * fo
    lot = rect_pts(p + nrm * (fo + 15.1), t, 12.4, 30.6)   # v31: oficina 5 m mais funda
    mark(lot, B_BUILD | B_RESERV); RESERVAS.append(("drops", rect_pts(p + nrm * (fo + 15.5), t, 14, 32), None)); foot.append(rect_pts(p + nrm * (fo + 14.5), t, 10.4, 29.0))
    extra_ground.append((rect_pts(p + nrm * (fo - r0["sw"] / 2) + t * 2.3, t, 4.2, r0["sw"]), "concreto"))
    drops = dict(front=front, nrm=nrm, t=t, street=p, w=r0["w"])
    print("Drops Garage:", front.round(1), unproj(*front))

# --- delegacia (PMPR do mapa), hangar do encontro e lombadas
for i, t in ntags.items():
    if t.get("amenity") == "police":
        p = np.array(nodes[i]); nr = nearest_road(p)
        if not nr: continue
        _, r, q, tt = nr
        nrm = perp(tt); nrm = nrm if np.dot(p - q, nrm) >= 0 else -nrm
        fo_ = r["w"] / 2 + r["sw"]
        # delegacia "É o Frank" (prédio de 59 x 37 m com pátio e grade): escorrega ao longo da rua até caber
        achou = False
        esc_del = 1.0
        for esc_del in (1.0, 0.85, 0.75, 0.65):
            for ds in [0] + [s * k for k in range(8, 100, 8) for s in (1, -1)]:
                for lado in (1, -1):
                    n2 = nrm * lado
                    q2 = q + tt * ds
                    if rect_free(q2 + n2 * (fo_ + 1.5 + 18.5 * esc_del), tt, 60 * esc_del, 37 * esc_del, B_ROAD | B_WATER, 2.0):
                        q, nrm, achou = q2, n2, True
                        break
                if achou:
                    break
            if achou:
                print("delegacia: lote livre a", ds, "m do ponto da PMPR, escala", esc_del)
                break
        if not achou:
            esc_del = 0.65
            print("delegacia: não achei lote livre (fica no lugar original)")
        org = q + nrm * (fo_ + 7.5)
        POIS["delegacia"] = dict(pos=[float(org[0]), 0.0, float(org[1])], yaw=float(math.atan2(nrm[1], -nrm[0])),
                                 rua=[float(q[0]), 0.0, float(q[1])], dir=[float(tt[0]), 0.0, float(tt[1])], hw=float(r["w"] / 2))
        # delegacia "É o Frank" (prédio de 59 x 37 m com pátio e grade): lote maior
        POIS["delegacia"]["escala"] = float(esc_del)
        lot = rect_pts(q + nrm * (fo_ + 0.5 + 19 * esc_del), tt, 62 * esc_del, 39 * esc_del)
        mark(lot, B_BUILD | B_RESERV); extra_ground.append((lot, "concreto")); RESERVAS.append(("delegacia", rect_pts(q + nrm * (fo_ + 0.5 + 19 * esc_del), tt, 62 * esc_del + 4, 39 * esc_del + 4), "delegacia"))
        break
# hangar: procura um terrenão livre (de preferência área industrial) a 300-1200 m da Drops
best = None
ref_d = drops["front"] if drops else np.array([0.0, 0.0])
for r in roads:
    if not r["car"] or r["cls"] in ("motorway", "motorway_link", "track", "busway", "service"): continue
    for s in np.arange(40, r["cum"][-1] - 40, 15):
        q, tt = point_at(r, s)
        dd = np.linalg.norm(q - ref_d)
        if not (300 < dd < 1200): continue
        for side in (1, -1):
            nrm = perp(tt) * side
            fo_ = r["w"] / 2 + r["sw"]
            cc = q + nrm * (fo_ + 46)
            if not rect_free(cc, tt, 66, 90, B_ROAD | B_BUILD | B_WATER | B_NOHOUSE, 3.0): continue
            score = dd - (400 if occ_get(cc) & B_INDUS else 0) + (0 if r["cls"] in ("tertiary", "secondary", "primary") else 150)
            if best is None or score < best[0]:
                best = (score, q, tt, nrm, fo_)
if best:
    _, q, tt, nrm, fo_ = best
    org = q + nrm * 58.0
    POIS["hangar"] = dict(pos=[float(org[0]), 0.036, float(org[1])], yaw=float(math.atan2(-nrm[0], -nrm[1])),
                          rua=[float(q[0]), 0.0, float(q[1])])
    mark(rect_pts(q + nrm * (fo_ + 46), tt, 66, 90), B_BUILD | B_RESERV); RESERVAS.append(("hangar", rect_pts(q + nrm * (fo_ + 46), tt, 70, 94), "hangar"))
    extra_ground.append((rect_pts(q + nrm * (fo_ + 46), tt, 66, 90), "concreto"))
    print("hangar em", org.round(1), "dist drops", round(float(np.linalg.norm(org - ref_d))))
# concessionária e prédio de escritório: terreno livre de frente pra avenida, não muito longe da Drops
def lugar_predio(chave, recuo, largura, fundo, dmin, dmax, classes, longe_de=()):
    melhor = None
    for r in roads:
        if not r["car"] or r["cls"] not in classes: continue
        for s in np.arange(30, r["cum"][-1] - 30, 10):
            q, tt = point_at(r, s)
            dd = np.linalg.norm(q - ref_d)
            if not (dmin < dd < dmax): continue
            if any(np.linalg.norm(q - np.array(o)) < 150 for o in longe_de): continue
            for side in (1, -1):
                nrm = perp(tt) * side
                fo_ = r["w"] / 2 + r["sw"]
                cc = q + nrm * (fo_ + 0.5 + (recuo + fundo) / 2)
                if not rect_free(q + nrm * (fo_ + 1.5 + (recuo + fundo) / 2), tt, largura + 2, recuo + fundo, B_ROAD | B_BUILD | B_WATER | B_NOHOUSE, 2.0): continue
                score = dd + (0 if r["cls"] in ("primary", "trunk", "secondary") else 250)
                if melhor is None or score < melhor[0]:
                    melhor = (score, q, tt, nrm, fo_, cc)
    if not melhor:
        print(chave, ": sem terreno livre")
        return None
    _, q, tt, nrm, fo_, cc = melhor
    org = q + nrm * (fo_ + 0.5 + recuo)
    POIS[chave] = dict(pos=[float(org[0]), 0.0, float(org[1])], yaw=float(math.atan2(-nrm[0], -nrm[1])), rua=[float(q[0]), 0.0, float(q[1])])
    lote = rect_pts(cc, tt, largura, recuo + fundo)
    mark(lote, B_BUILD | B_RESERV)
    RESERVAS.append((chave, rect_pts(cc, tt, largura + 4, recuo + fundo + 4), chave))
    extra_ground.append((lote, "concreto"))
    print(chave, "em", org.round(1), "dist drops", round(float(np.linalg.norm(org - ref_d))))
    return org
_avs = ("primary", "secondary", "trunk", "tertiary")
_cc = lugar_predio("concessionaria", 7.0, 34.0, 18.0, 150, 1000, _avs)
# lombadas: na rua da Drops e em ruas perto
LOMB = []
def add_lomb(r, s):
    q, tt = point_at(r, s)
    for l in LOMB:
        if np.hypot(l[0] - q[0], l[1] - q[1]) < 110: return False
    if near_junction(q, 12): return False
    LOMB.append([round(float(q[0]), 2), round(float(q[1]), 2), round(float(tt[0]), 4), round(float(tt[1]), 4), round(r["w"] / 2, 2)])
    return True
if drops:
    rd = [r for r in roads if r["name"] == DROPS_RUA][0]
    for s in (DROPS_NUM + 35, DROPS_NUM + 90, DROPS_NUM - 30):
        if 10 < s < rd["cum"][-1] - 10: add_lomb(rd, s)
for r in sorted(roads, key=lambda r: np.linalg.norm(r["pts"].mean(0) - ref_d)):
    if r["cls"] not in ("residential", "tertiary", "unclassified") or r["cum"][-1] < 70 or r["kind"] != "asfalto": continue
    if np.linalg.norm(r["pts"].mean(0) - ref_d) > 900 or len(LOMB) >= 22: break
    add_lomb(r, r["cum"][-1] / 2)
POIS["lombadas"] = LOMB
print("lombadas:", len(LOMB))

ncasa = ngalp = 0
# --- casas nos LOTES REAIS do IPPUC (cadastro da prefeitura)
nlote = 0
if os.path.exists(LOTS_PKL):
    lots = pickle.load(open(LOTS_PKL, "rb"))
    rs_pts, rs_info = [], []
    for ri, r in enumerate(roads):
        if not r["car"] or r["cls"] in ("motorway", "motorway_link", "busway"): continue
        for s in np.arange(0, r["cum"][-1] + 0.1, 2.0):
            q, t = point_at(r, s); rs_pts.append(q); rs_info.append(ri)
    rtree = cKDTree(np.array(rs_pts))
    edges_done = set()
    def ekey(a, b):
        k1 = (round(a[0] * 2), round(a[1] * 2)); k2 = (round(b[0] * 2), round(b[1] * 2))
        return (k1, k2) if k1 < k2 else (k2, k1)
    for P, dd in lots:
        P = np.asarray(P, float) + GEO_DESLOC
        if np.allclose(P[0], P[-1]): P = P[:-1]
        if len(P) < 3: continue
        area = 0.5 * abs(np.dot(P[:, 0], np.roll(P[:, 1], -1)) - np.dot(P[:, 1], np.roll(P[:, 0], -1)))
        if not (45 < area < 1500): continue
        c = P.mean(0)
        if not (XMIN + 5 < c[0] < XMAX - 5 and ZMIN + 5 < c[1] < ZMAX - 5): continue
        cnt = P.astype(np.float32)
        amostras = [c] + [c + (v - c) * 0.7 for v in P]
        bits = 0
        for q in amostras: bits |= occ_get(q)
        if bits & (B_CARR | B_WATER | B_RESERV | B_NOHOUSE): continue
        tem_osm = bool(bits & B_BUILD)
        best = None
        n = len(P)
        for k in range(n):
            a, b = P[k], P[(k + 1) % n]
            L = np.linalg.norm(b - a)
            if L < 3: continue
            dist, idx = rtree.query((a + b) / 2)
            if best is None or dist < best[0]: best = (dist, k, idx)
        if best is None or best[0] > 22: continue
        dist, k, idx = best
        r = roads[rs_info[idx]]
        a, b = P[k], P[(k + 1) % n]
        ax = (b - a) / np.linalg.norm(b - a)
        inward = perp(ax)
        if np.dot(c - (a + b) / 2, inward) < 0: inward = -inward
        front_len = float(np.linalg.norm(b - a))
        depth = float(max(np.dot(v - a, inward) for v in P))
        dentro = lambda q, m=0.25: cv2.pointPolygonTest(cnt, (float(q[0]), float(q[1])), True) >= m
        if not tem_osm:
            comercio = r["cls"] in ("secondary", "tertiary", "primary") and rnd.random() < 0.45
            setback = 0.4 if comercio else rnd.choice([0.5, 1.5, 3.0, 4.0])
            L = min(front_len - (0.3 if comercio else rnd.uniform(0.8, 2.0)), 14.0)
            W = min(depth - setback - (1.0 if comercio else rnd.uniform(2.5, 6.0)), 18.0 if comercio else 13.0)
            ok = False
            for tent in range(5):
                if L < 3.5 or W < 3.5:
                    if setback > 0.5: setback = 0.5; L = min(front_len - 0.8, 14.0); W = min(depth - 1.5, 12.0); continue
                    break
                lado = rnd.uniform(-1, 1) * max(0.0, front_len - L) / 2
                hc = (a + b) / 2 + ax * lado + inward * (setback + W / 2)
                cs = rect_pts(hc, ax, L, W)
                if all(dentro(q) for q in cs):
                    ok = True; break
                L *= 0.85; W *= 0.85
            if ok:
                floors = 2 if rnd.random() < 0.22 else 1
                rt = rnd.random()
                roof = "laje" if (rt < 0.22 or comercio and rnd.random() < 0.6) else ("hip" if rt < 0.45 else ("gable_a" if rt < 0.8 else "gable_b"))
                rmat = "fibro" if rnd.random() < 0.3 else "telha"
                wall = "parede" if comercio else ("bloco" if rnd.random() < 0.16 else ("parede" if rnd.random() < 0.6 else "parede2"))
                col = rnd.choice(PAL_CASA) if wall != "bloco" else (235, 232, 225)
                o = dict(type="casa", ref=hc, c=hc, a=ax, b=inward, L=L, W=W, h=2.9 * floors, wall=wall, col=jitter(col, 8),
                         roof=roof, roofmat=rmat, roofcol=jitter(rnd.choice(PAL_TELHA) if rmat == "telha" else (165, 165, 160), 10),
                         pitch=rnd.uniform(17, 26), door=not comercio, caixa=roof == "laje" and rnd.random() < 0.8, uoff=rnd.uniform(0, 3.5))
                if comercio:
                    o["comercio"] = True
                    o["placa"] = jitter(rnd.choice([(200, 30, 30), (30, 80, 170), (250, 200, 0), (20, 130, 60), (240, 120, 0), (230, 230, 230)]), 10)
                objs.append(o); foot.append(cs); ncasa += 1
                # edícula no fundo
                fundo = depth - setback - W
                if fundo > 8 and rnd.random() < 0.5:
                    ec = (a + b) / 2 + inward * (setback + W + 1.0 + 2.6) + ax * rnd.uniform(-front_len / 4, front_len / 4)
                    el = min(front_len - 2.0, rnd.uniform(4.0, 6.5)); ew = rnd.uniform(3.8, 5.2)
                    if el > 3 and all(dentro(q) for q in rect_pts(ec, ax, el, ew)):
                        objs.append(dict(type="casa", ref=ec, c=ec, a=ax, b=inward, L=el, W=ew, h=2.7, wall="parede" if rnd.random() < 0.7 else "bloco",
                                         col=jitter(rnd.choice(PAL_CASA), 8), roof=rnd.choice(["laje", "gable_a", "gable_a"]),
                                         roofmat=rnd.choice(["fibro", "telha"]), roofcol=jitter((170, 168, 160), 12), pitch=12,
                                         door=False, caixa=False, uoff=rnd.uniform(0, 3)))
                        foot.append(rect_pts(ec, ax, el, ew))
                elif fundo > 5 and rnd.random() < 0.3:
                    tp = (a + b) / 2 + inward * (setback + W + fundo * 0.6)
                    if dentro(tp, 1.0): objs.append(dict(type="arvore", ref=tp, p=tp, kind="copa" if rnd.random() < 0.9 else "araucaria", s=rnd.uniform(0.7, 1.1)))
            else:
                comercio = False
        else:
            comercio = False
        # muros do lote (frente com portão; laterais e fundo inteiros, sem repetir divisa)
        for kk in range(n):
            p0, p1 = P[kk], P[(kk + 1) % n]
            if np.linalg.norm(p1 - p0) < 0.8: continue
            key = ekey(p0, p1)
            if key in edges_done: continue
            edges_done.add(key)
            if kk == k:
                if comercio: continue
                mt = rnd.random()
                if mt < 0.85:
                    objs.append(dict(type="muro", ref=(p0 + p1) / 2, p0=p0, p1=p1, h=rnd.uniform(1.7, 2.2) if mt < 0.62 else 1.0,
                                     col=jitter(rnd.choice(PAL_MURO), 6), gate=rnd.uniform(0.2, 0.8), gatew=min(3.0, np.linalg.norm(p1 - p0) * 0.4),
                                     out=-inward, grade=mt >= 0.62))
                    foot.append(np.array([p0, p1, p1 + inward * 0.15, p0 + inward * 0.15]))
            else:
                objs.append(dict(type="muro", ref=(p0 + p1) / 2, p0=p0, p1=p1, h=2.0, col=(205, 203, 198), gate=None, out=None))
        occ_or(B_BUILD, lambda m: cv2.fillPoly(m, [opx(P)], 1, cv2.LINE_8, SH))
        nlote += 1
print("lotes reais usados:", nlote)

# --- casas e galpões ao longo das ruas (onde não tem lote no cadastro)
REJ={}
for r in sorted(roads, key=lambda r: -r["rank"]):
    if r["cls"] not in HOUSE_ROADS: continue
    Ltot = r["cum"][-1]
    for side in (1, -1):
        s = rnd.uniform(0, 6)
        while s < Ltot - 4:
            p, t = point_at(r, s + 6)
            nrm = perp(t) * side
            fo = r["w"] / 2 + r["sw"] + 0.3
            indus = occ_get(p + nrm * (fo + 15)) & B_INDUS
            if indus:
                lotw = rnd.uniform(28, 55); depth = rnd.uniform(22, 40); setback = rnd.uniform(4, 10)
            else:
                lotw = rnd.uniform(8.0, 12.0); depth = rnd.uniform(8, 13); setback = rnd.choice([0.4, 1.5, 3, 4, 5])
                comercio = r["cls"] in ("secondary", "tertiary", "primary") and rnd.random() < 0.45
                if comercio: setback = 0.4; depth = rnd.uniform(10, 16)
            if s + lotw > Ltot - 3: break
            p, t = point_at(r, s + lotw / 2)
            nrm = perp(t) * side
            ok = False
            tries = [(setback, depth, rnd.uniform(9, 14) if not indus else 4), (setback, depth, rnd.uniform(3, 7))]
            if not indus:
                tries += [(min(setback, 1.5), depth, 1.0), (0.4, min(depth, 7.5), 0.5), (0.4, 6.0, 0.3)]
            else:
                tries += [(3, depth * 0.6, 2), (2, 14, 1)]
            # metade do quarteirão: deixa espaço pras casas da rua de trás (os dois lados da rua ficam com casa)
            meio = 99.0
            for dd in np.arange(fo + 3, fo + 80, 1.5):
                if occ_get(p + nrm * dd) & B_ROAD:
                    meio = (dd - fo - 1.0) / 2.0
                    break
            if not indus and meio < 99:
                tries = [(sb, min(dp, max(5.0, meio - sb - min(bk, 2.0))), min(bk, max(0.3, meio - sb - dp))) for sb, dp, bk in tries]
            for setback, depth, back in tries:
                Dlot = setback + depth + back
                lc = p + nrm * (fo + Dlot / 2)
                fr = 2.0   # a máscara de rua (polyline rasterizada) sobra ~1 m além da calçada
                chk = p + nrm * (fo + fr + (Dlot - fr) / 2)
                if rect_free(chk, t, lotw - 0.6, Dlot - fr - 0.2, B_ROAD | B_BUILD | B_WATER | B_NOHOUSE):
                    ok = True; break
            if ok and not indus:
                for e in (-lotw / 2, lotw / 2):
                    if near_junction(p + t * e, 0.5): ok = False
            if not ok:
                s += 1.5; continue
            lot = rect_pts(lc, t, lotw, Dlot)
            mark(lot)
            hc = p + nrm * (fo + setback + depth / 2)
            if indus:
                L = lotw - rnd.uniform(4, 10); W = depth
                h = rnd.uniform(7, 11)
                objs.append(dict(type="casa", ref=hc, c=hc, a=t, b=nrm, L=L, W=W, h=h, wall="galpao",
                                 col=rnd.choice(PAL_GALPAO), roof="gable_a" if L > W else "gable_b",
                                 roofmat="fibro", roofcol=jitter((175, 175, 172), 15), pitch=8, door=False))
                foot.append(rect_pts(hc, t, L, W)); ngalp += 1
                if rnd.random() < 0.7:
                    objs.append(dict(type="muro", ref=p, p0=p + nrm * fo - t * lotw / 2, p1=p + nrm * fo + t * lotw / 2,
                                     h=2.2, col=rnd.choice(PAL_MURO), gate=rnd.uniform(0.3, 0.7), gatew=8, out=-nrm))
            else:
                L = lotw - (rnd.uniform(0.0, 2.6) if not comercio else 0.3)
                W = depth
                floors = 2 if rnd.random() < 0.22 else 1
                h = 2.9 * floors
                rt = rnd.random()
                roof = "laje" if rt < 0.22 else ("hip" if rt < 0.45 else ("gable_a" if rt < 0.8 else "gable_b"))
                rmat = "fibro" if rnd.random() < 0.3 else "telha"
                wall = "bloco" if rnd.random() < 0.16 else ("parede" if rnd.random() < 0.6 else "parede2")
                col = rnd.choice(PAL_CASA) if wall != "bloco" else (235, 232, 225)
                objs.append(dict(type="casa", ref=hc, c=hc - t * (lotw - L) / 2 * rnd.choice([-1, 1]) * 0.9, a=t, b=nrm,
                                 L=L, W=W, h=h, wall=wall, col=jitter(col, 8), roof=roof, roofmat=rmat,
                                 roofcol=jitter(rnd.choice(PAL_TELHA) if rmat == "telha" else (165, 165, 160), 10),
                                 pitch=rnd.uniform(17, 26), door=True, caixa=roof == "laje" and rnd.random() < 0.8,
                                 uoff=rnd.uniform(0, 3.5)))
                if comercio:
                    o = objs[-1]; o["c"] = hc; o["comercio"] = True; o["wall"] = "parede"
                    if o["roof"] != "laje" and rnd.random() < 0.6: o["roof"] = "laje"; o["caixa"] = rnd.random() < 0.5
                    o["placa"] = jitter(rnd.choice([(200, 30, 30), (30, 80, 170), (250, 200, 0), (20, 130, 60), (240, 120, 0), (230, 230, 230)]), 10)
                foot.append(rect_pts(objs[-1]["c"], t, L, W)); ncasa += 1
                # edícula no fundo
                if back > 7 and rnd.random() < 0.55:
                    ec = p + nrm * (fo + setback + depth + 0.8 + 3.0) + t * rnd.uniform(-lotw / 4, lotw / 4)
                    el = min(lotw - 1.5, rnd.uniform(4.5, 7)); ew = rnd.uniform(4, 6)
                    objs.append(dict(type="casa", ref=ec, c=ec, a=t, b=nrm, L=el, W=ew, h=2.7, wall="parede" if rnd.random() < 0.7 else "bloco",
                                     col=jitter(rnd.choice(PAL_CASA), 8), roof=rnd.choice(["laje", "gable_a", "gable_a"]),
                                     roofmat=rnd.choice(["fibro", "telha"]), roofcol=jitter((170, 168, 160), 12), pitch=12,
                                     door=False, caixa=False, uoff=rnd.uniform(0, 3)))
                    foot.append(rect_pts(ec, t, el, ew))
                if comercio:
                    s += lotw; continue
                mt = rnd.random()
                if mt < 0.82:
                    mh = rnd.uniform(1.7, 2.3) if mt < 0.6 else 1.0
                    objs.append(dict(type="muro", ref=p, p0=p + nrm * fo - t * lotw / 2, p1=p + nrm * fo + t * lotw / 2,
                                     h=mh, col=jitter(rnd.choice(PAL_MURO + [col]), 6), gate=rnd.uniform(0.2, 0.8),
                                     gatew=rnd.choice([2.6, 3.0, 3.2]), out=-nrm, grade=mt >= 0.6))
                    # muro lateral (divisa)
                    e = -lotw / 2
                    objs.append(dict(type="muro", ref=p, p0=p + nrm * fo + t * e, p1=p + nrm * (fo + Dlot) + t * e,
                                     h=2.0, col=(205, 203, 198), gate=None, out=t))
                    foot.append(np.array([p + nrm * fo - t * lotw / 2, p + nrm * fo + t * lotw / 2,
                                          p + nrm * (fo + 0.15) + t * lotw / 2, p + nrm * (fo + 0.15) - t * lotw / 2]))
                # árvore na calçada / quintal
                if r["sw"] >= 2 and rnd.random() < 0.18:
                    tp = p + nrm * (r["w"] / 2 + r["sw"] - 0.7) + t * rnd.uniform(-3, 3)
                    if not (occ_get(tp) & B_CARR):
                        objs.append(dict(type="arvore", ref=tp, p=tp, kind="copa", s=rnd.uniform(0.7, 1.0)))
                if rnd.random() < 0.35:
                    tp = p + nrm * (fo + setback + depth + 2.0) + t * rnd.uniform(-lotw / 3, lotw / 3)
                    objs.append(dict(type="arvore", ref=tp, p=tp, kind="copa" if rnd.random() < 0.9 else "araucaria",
                                     s=rnd.uniform(0.7, 1.15)))
            s += lotw
print("casas:", ncasa, "galpões:", ngalp, REJ)
if os.environ.get("SOCASAS"):
    np.save("/tmp/occ.npy", occ); sys.exit()

# --- detalhes das casas da região (pelas fotos da rua: sobrados, grade branca, laje de tijolo, lixeira de ferro)
nlix = 0
for o in list(objs):
    if o["type"] == "casa" and o.get("wall") != "galpao" and o.get("h", 3) < 7:
        if o["L"] > 6 and o["h"] < 3.0 and not o.get("comercio") and rnd.random() < 0.18:
            o["h"] = 5.8
        if rnd.random() < 0.55: o["col"] = jitter(rnd.choice(PAL_CASA_FOTOS), 6)
        if o["h"] > 3:
            o["sacada"] = rnd.random() < 0.6
            o["lateral_cinza"] = rnd.random() < 0.5
        if o["roof"] == "laje":
            o["tijolo"] = rnd.random() < 0.45
            o["torre"] = o.get("caixa") and rnd.random() < 0.4
        elif o.get("roofmat") == "telha" and rnd.random() < 0.3:
            o["roofcol"] = jitter((112, 112, 114), 8)    # telha de concreto cinza
        o["garagem_porta"] = (not o.get("comercio")) and o["L"] > 7 and rnd.random() < 0.25
    elif o["type"] == "muro" and o.get("gate") is not None and o.get("out") is not None:
        o["portao"] = "grade" if rnd.random() < 0.6 else "chapa"
        if rnd.random() < 0.5: o["col"] = jitter(rnd.choice(PAL_MURO_FOTOS), 5)
        if o.get("grade") or (o["h"] > 1.5 and rnd.random() < 0.3):
            o["grade"] = True; o["h"] = rnd.uniform(0.5, 0.95)
            o["grade_cor"] = rnd.choice([(245, 245, 245), (245, 245, 245), (150, 152, 155), (40, 40, 42)])
        if rnd.random() < 0.55:
            p0, p1 = np.asarray(o["p0"]), np.asarray(o["p1"]); L = np.linalg.norm(p1 - p0)
            a = (p1 - p0) / max(L, 1e-6)
            q = p0 + a * rnd.uniform(0.15, 0.85) * L + np.asarray(o["out"]) * 0.55
            if not (occ_get(q) & B_CARR):
                objs.append(dict(type="lixeira", ref=q, p=q, a=a, out=np.asarray(o["out"]), cor=rnd.choice([(40, 40, 42), (30, 70, 40), (230, 230, 230)])))
                nlix += 1
    elif o["type"] == "fios":
        o["n"] = rnd.randint(5, 10)
print("lixeiras:", nlix)

# --- árvores em parques/matas e do OSM
ntree = 0
for cls, outs, ins, t in areas:
    dens = {"grama": 1 / 260, "mata": 1 / 28, "terreno": 0}.get(cls, 0)
    if t.get("leisure") == "pitch": dens = 0
    if not dens: continue
    for o in outs:
        mn, mx = o.min(0), o.max(0)
        area = 0.5 * abs(np.dot(o[:, 0], np.roll(o[:, 1], -1)) - np.dot(o[:, 1], np.roll(o[:, 0], -1)))
        n = int(area * dens)
        cnt = o.astype(np.float32)
        for _ in range(min(n, 4000)):
            q = np.array([rnd.uniform(mn[0], mx[0]), rnd.uniform(mn[1], mx[1])])
            if cv2.pointPolygonTest(cnt, (float(q[0]), float(q[1])), False) < 0: continue
            if occ_get(q) & (B_ROAD | B_BUILD | B_WATER | B_TREE): continue
            k = "araucaria" if rnd.random() < (0.18 if cls == "mata" else 0.12) else "copa"
            objs.append(dict(type="arvore", ref=q, p=q, kind=k, s=rnd.uniform(0.75, 1.3)))
            x = int((q[0] - XMIN) / OR); z = int((q[1] - ZMIN) / OR)
            occ[max(0, z - 2):z + 3, max(0, x - 2):x + 3] |= B_TREE
            ntree += 1
for i, t in ntags.items():
    if t.get("natural") == "tree":
        q = np.array(nodes[i]); objs.append(dict(type="arvore", ref=q, p=q, kind="copa", s=1.1)); ntree += 1
print("árvores (parques/matas):", ntree)

# --- postes com fiação e iluminação
npole = 0
for r in roads:
    if not r["car"] or r["cls"] in ("motorway", "motorway_link", "track", "busway", "service"): continue
    Ltot = r["cum"][-1]
    side = 1 if (int(r["id"]) % 2) else -1
    prev = None
    s = rnd.uniform(3, 15)
    while s < Ltot - 2:
        p, t = point_at(r, s)
        nrm = perp(t) * side
        q = p + nrm * (r["w"] / 2 + (0.45 if r["sw"] > 0 else 1.0))
        if (occ_get(q) & (B_CARR | B_WATER)) or near_junction(q, 0.5):
            s += 6; prev = None; continue
        # não colocar dentro de prédio: empurra um pouco
        lamp = q + (-nrm) * 1.7
        objs.append(dict(type="poste", ref=q, p=q, n=-nrm, t=t, trafo=rnd.random() < 0.08, lamp=lamp))
        if prev is not None and np.linalg.norm(prev[0] - q) < 48:
            objs.append(dict(type="fios", ref=(prev[0] + q) / 2, a=prev, b=(q, t)))
        prev = (q, t)
        npole += 1
        s += rnd.uniform(30, 38)
print("postes:", npole)

# ----------------------------------------------------------------------------- terreno real (curvas de nível IPPUC)
T = None
if os.path.exists(CURVAS_PKL):
    T = Terreno(CURVAS_PKL, XMIN, ZMIN, NX * CH, NZ * CH, 2.0, GEO_DESLOC)
    T.ruas([r for r in roads if r["car"] or r["cls"] in ("footway", "path", "pedestrian")], lambda r: r["rank"])
    for nome, poly, chave in RESERVAS:
        if nome == "drops":
            niv = T.aplainar(poly, 6.0, T.alt(*drops["street"]))
            drops["y"] = niv
        else:
            niv = T.aplainar(poly, 10.0)
            if chave in POIS:
                POIS[chave]["pos"][1] = float(niv + (0.036 if chave == "hangar" else 0.0))
                if chave == "delegacia": POIS[chave]["nivel"] = float(niv)


def ALT(x, z):
    return 0.0 if T is None else T.alt(x, z)


# ----------------------------------------------------------------------------- sinalização horizontal (mundo)
marks_w, marks_y, marks_poly = [], [], []   # segmentos (p0,p1) brancos / amarelos; polígonos brancos


def offset_line(P, off):
    d = np.diff(P, axis=0); d /= (np.linalg.norm(d, axis=1)[:, None] + 1e-9)
    n = np.stack([-d[:, 1], d[:, 0]], 1)
    vn = np.zeros_like(P); vn[:-1] += n; vn[1:] += n
    vn /= (np.linalg.norm(vn, axis=1)[:, None] + 1e-9)
    return P + vn * off


def dashes(P, on, off, out, skip_j=True):
    seg = np.linalg.norm(np.diff(P, axis=0), axis=1); cum = np.concatenate([[0], np.cumsum(seg)])
    fake = dict(pts=P, cum=cum)
    s = 0.0
    while s < cum[-1]:
        e = min(s + on, cum[-1])
        a, _ = point_at(fake, s); bq, _ = point_at(fake, e)
        if not (skip_j and (near_junction(a, 2.5) or near_junction(bq, 2.5))):
            out.append((a, bq))
        s += on + off


for r in roads:
    if not r["car"] or r["kind"] != "asfalto" or r["cls"] in ("service", "track", "residential", "living_street"): continue
    P = r["pts"]; w = r["w"]
    if r["oneway"]:
        ln = r["lanes"] or max(1, int(round(w / 3.4)))
        for k in range(1, ln):
            dashes(offset_line(P, -w / 2 + k * w / ln), 4, 6, marks_w)
        if r["cls"].startswith(("motorway", "primary", "secondary", "trunk")):
            dashes(offset_line(P, w / 2 - 0.35), 2, 0, marks_w); dashes(offset_line(P, -w / 2 + 0.35), 2, 0, marks_y)
    else:
        if r["cls"] in ("primary", "secondary", "trunk"):
            dashes(offset_line(P, 0.12), 2, 0, marks_y); dashes(offset_line(P, -0.12), 2, 0, marks_y)
            dashes(offset_line(P, w / 2 - 0.35), 2, 0, marks_w); dashes(offset_line(P, -w / 2 + 0.35), 2, 0, marks_w)
        elif w >= 7:
            dashes(P, 4, 6, marks_y)
# faixas de pedestre
road_by_node = {}
for r in roads:
    if r["car"]:
        for k, i in enumerate(r["nd"]): road_by_node.setdefault(i, (r, k))
for i, t in ntags.items():
    if t.get("highway") in ("crossing",) and i in road_by_node:
        r, k = road_by_node[i]
        p = np.array(nodes[i]); P = r["pts"]
        d = P[min(k + 1, len(P) - 1)] - P[max(k - 1, 0)]; d /= np.linalg.norm(d) + 1e-9
        n = perp(d)
        for o in np.arange(-r["w"] / 2 + 0.6, r["w"] / 2 - 0.4, 0.9):
            c = p + n * o
            marks_poly.append(np.array([c - d * 1.6 - n * 0.22, c + d * 1.6 - n * 0.22, c + d * 1.6 + n * 0.22, c - d * 1.6 + n * 0.22]))
# ruas de bairro mão dupla: linha amarela tracejada no meio (como em Curitiba)
for r in roads:
    if not r["car"] or r["kind"] != "asfalto" or r["oneway"] or r["cls"] not in ("residential", "unclassified", "living_street"): continue
    if r["w"] >= 6.0 and r["cum"][-1] > 25:
        dashes(r["pts"], 3, 5, marks_y)

# cruzamentos: rua menor que chega numa maior ganha linha de PARE, "PARE" pintado e placa (e placa com nome das ruas)
node_roads = {}
for r in roads:
    if r["car"] and r["cls"] not in ("track",):
        for k, i in enumerate(r["nd"]): node_roads.setdefault(i, []).append((r, k))
marks_txt = []      # (centro, dir, largura, comprimento) "PARE" no chão
SINAIS = []         # placas verticais
NOMES = []          # postes com o nome das ruas (o jogo escreve o nome)
nstop = 0
for r in roads:
    if not r["car"] or r["kind"] not in ("asfalto", "paralelepipedo") or r["cls"] in ("service", "track", "motorway", "trunk", "primary"): continue
    if r["cum"][-1] < 28: continue
    for ponta in (0, -1):
        i = r["nd"][ponta]
        outros = [o for o, _ in node_roads.get(i, []) if o is not r]
        if not outros: continue
        maior = max(outros, key=lambda o: (o["rank"], o["cum"][-1]))
        if maior["rank"] < r["rank"] or (maior["rank"] == r["rank"] and maior["cum"][-1] <= r["cum"][-1]): continue
        P = r["pts"]
        j = P[0] if ponta == 0 else P[-1]
        viz = P[1] if ponta == 0 else P[-2]
        d = j - viz; d = d / (np.linalg.norm(d) + 1e-9)          # sentido de quem chega no cruzamento
        dist = maior["w"] / 2 + maior["sw"] + 1.2
        if dist > r["cum"][-1] * 0.4: continue
        dir_ = np.array([-d[1], d[0]])                             # direita de quem chega
        c = j - d * dist
        w = r["w"]
        meia = w / 2 if not r["oneway"] else w
        ini = 0.0 if not r["oneway"] else -w / 2
        # linha de retenção (0,4 m) do meio até o meio-fio da direita
        a0 = c + dir_ * ini; a1 = c + dir_ * (ini + meia - 0.2)
        marks_poly.append(np.array([a0 - d * 0.2, a1 - d * 0.2, a1 + d * 0.2, a0 + d * 0.2]))
        # "PARE" escrito antes da linha, na faixa da direita
        marks_txt.append((c - d * 3.2 + dir_ * (ini + meia / 2), d, min(2.6, meia - 0.4), 2.6))
        # placa na calçada da direita
        sp = c + dir_ * (w / 2 + max(0.6, r["sw"] * 0.55)) - d * 0.6
        SINAIS.append(dict(type="placa", ref=sp, p=sp, kind="pare", face=-d))
        if r["name"] and maior["name"] and r["name"] != maior["name"]:
            # orientação das duas placas de nome (cada uma paralela à sua rua)
            Pm = maior["pts"]; k = int(np.argmin(np.linalg.norm(Pm - j, axis=1)))
            dm = Pm[min(k + 1, len(Pm) - 1)] - Pm[max(k - 1, 0)]; dm = dm / (np.linalg.norm(dm) + 1e-9)
            NOMES.append([sp, math.atan2(d[0], d[1]), r["name"], math.atan2(dm[0], dm[1]), maior["name"]])
            SINAIS[-1]["nomes"] = True
        nstop += 1
# placas de lombada (25 m antes, nos dois sentidos) e de velocidade nas avenidas
for l in LOMB:
    q = np.array(l[:2]); tt = np.array(l[2:4]); half = l[4]
    for sg in (1, -1):
        dd = tt * sg
        sp = q - dd * 25 + np.array([-dd[1], dd[0]]) * (half + 1.0)
        SINAIS.append(dict(type="placa", ref=sp, p=sp, kind="lombada", face=-dd))
for r in roads:
    if not r["car"] or r["cls"] not in ("primary", "secondary", "tertiary", "trunk") or r["cum"][-1] < 200: continue
    kind = "v40" if r["cls"] == "tertiary" else "v60"
    s = 60.0
    while s < r["cum"][-1] - 60:
        for sg in ((1,) if r["oneway"] else (1, -1)):
            q, tt = point_at(r, s)
            dd = np.asarray(tt) * sg
            if not near_junction(q, 15):
                sp = q + np.array([-dd[1], dd[0]]) * (r["w"] / 2 + max(0.6, r["sw"] * 0.55))
                SINAIS.append(dict(type="placa", ref=sp, p=sp, kind=kind, face=-dd))
        s += 380.0
objs.extend(SINAIS)
print("marcas:", len(marks_w), len(marks_y), len(marks_poly), "PARE:", nstop, "placas:", len(SINAIS), "nomes:", len(NOMES))

# ----------------------------------------------------------------------------- geometria
UVS = {"parede": (3.5, 2.9), "parede2": (3.5, 2.9), "reboco": (4, 4), "bloco": (2, 2), "galpao": (4, 4), "telha": (2, 2),
       "fibro": (2, 2), "laje": (4, 4), "cor": (1, 1), "grade": (1, 1), "tijolo": (2, 2), "lampada": (1, 1), "fio": (1, 1), "placa": (1, 1)}
UP = np.array([0, 1.0, 0])


def v3(p2, y):
    return np.array([p2[0], y, p2[1]])


def wall(mb, p0, p1, y0, y1, col, out, mat, uoff=0.0):
    us, vs = UVS[mat]
    L = float(np.linalg.norm(np.asarray(p1) - p0))
    u0, u1 = uoff / us, (uoff + L) / us
    vv = lambda y: 1 - y / vs
    mb.quad([v3(p0, y0), v3(p1, y0), v3(p1, y1), v3(p0, y1)],
            [(u0, vv(y0)), (u1, vv(y0)), (u1, vv(y1)), (u0, vv(y1))], col, np.array([out[0], 0, out[1]]))


def box(B, mat, c, a, la, lb, y0, y1, col, top=True, uoff=0.0):
    a = np.asarray(a, float); bb = perp(a)
    cs = [c - a * la / 2 - bb * lb / 2, c + a * la / 2 - bb * lb / 2, c + a * la / 2 + bb * lb / 2, c - a * la / 2 + bb * lb / 2]
    outs = [-bb, a, bb, -a]
    mb = B[mat]
    for k in range(4):
        wall(mb, cs[k], cs[(k + 1) % 4], y0, y1, col, outs[k], mat, uoff)
    if top:
        mb.quad([v3(q, y1) for q in cs], [(q[0] / 4, q[1] / 4) for q in cs], col, UP)


def cyl(mb, c, r, y0, y1, col, n=8, top=True):
    ang = [2 * math.pi * k / n for k in range(n)]
    ps = [c + np.array([math.cos(t), math.sin(t)]) * r for t in ang]
    for k in range(n):
        p0, p1 = ps[k], ps[(k + 1) % n]
        o = (p0 + p1) / 2 - c
        wall(mb, p0, p1, y0, y1, col, o, "cor")
    if top:
        for k in range(n):
            mb.tri(v3(c, y1), v3(ps[k], y1), v3(ps[(k + 1) % n], y1), (0, 0), (0, 0), (0, 0), col, UP)


def grade(B, c, a, L, y0, y1, col, out=None):
    """painel de grade (barras verticais) com textura transparente, visto dos dois lados"""
    a = np.asarray(a, float)
    p0, p1 = c - a * L / 2, c + a * L / 2
    o2 = perp(a) if out is None else np.asarray(out, float)
    us = L / 1.0; vs = (y1 - y0) / 1.0
    B["grade"].quad([v3(p0, y0), v3(p1, y0), v3(p1, y1), v3(p0, y1)], [(0, vs), (us, vs), (us, 0), (0, 0)], col, np.array([o2[0], 0, o2[1]]))
    for yy in (y0 + 0.06, y1 - 0.05):
        box(B, "cor", c, a, L, 0.05, yy - 0.025, yy + 0.025, col)


def triangulate(poly):
    P = [np.asarray(p) for p in poly]
    n = len(P)
    if n < 3: return []
    area = sum(P[i][0] * P[(i + 1) % n][1] - P[(i + 1) % n][0] * P[i][1] for i in range(n))
    idx = list(range(n)) if area > 0 else list(range(n))[::-1]
    def cr(a, b, c): return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    tris, guard = [], 0
    while len(idx) > 3 and guard < 5000:
        guard += 1; found = False
        m = len(idx)
        for k in range(m):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % m]
            a, bq, c = P[i0], P[i1], P[i2]
            if cr(a, bq, c) <= 1e-9: continue
            ok = True
            for j in idx:
                if j in (i0, i1, i2): continue
                q = P[j]
                if cr(a, bq, q) >= 0 and cr(bq, c, q) >= 0 and cr(c, a, q) >= 0: ok = False; break
            if ok:
                tris.append((i0, i1, i2)); idx.pop(k); found = True; break
        if not found: break
    if len(idx) == 3: tris.append(tuple(idx))
    elif len(idx) > 3:
        for k in range(1, len(idx) - 1): tris.append((idx[0], idx[k], idx[k + 1]))
    return tris


ICO_V = None


def ico():
    global ICO_V
    if ICO_V is None:
        t = (1 + 5 ** 0.5) / 2
        v = np.array([(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
                      (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)], float)
        v /= np.linalg.norm(v, axis=1)[:, None]
        f = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
             (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
        ICO_V = (v, f)
    return ICO_V


def copa_card(mb, cen, ang, lu, lv, col, centro_luz, deitado=False, incl=0.0):
    """um card de folhas (quadrado com textura de copa). Normais apontando pra fora do centro da copa = parece volume."""
    if deitado:
        u = np.array([math.cos(ang), math.sin(incl), math.sin(ang)]) * lu / 2
        v = np.array([-math.sin(ang), 0.0, math.cos(ang)]) * lv / 2
    else:
        u = np.array([math.cos(ang), 0.0, math.sin(ang)]) * lu / 2
        v = np.array([0.0, lv / 2, 0.0])
    cs = [cen - u - v, cen + u - v, cen + u + v, cen - u + v]
    uv = [(0, 1), (1, 1), (1, 0), (0, 0)]
    ns = []
    for q in cs:
        n = q - centro_luz
        n = n / (np.linalg.norm(n) + 1e-9)
        n = n * 0.75 + np.array([0, 0.45, 0])
        ns.append(n / np.linalg.norm(n))
    mb.tri_n(cs[0], cs[1], cs[2], ns[0], ns[1], ns[2], uv[0], uv[1], uv[2], col)
    mb.tri_n(cs[0], cs[2], cs[3], ns[0], ns[2], ns[3], uv[0], uv[2], uv[3], col)


def blob(mb, c3, rx, ry, rz, rgb):
    v, f = ico()
    V = v * [rx, ry, rz] + c3
    for (i, j, k) in f:
        sh = rnd.uniform(0.82, 1.12)
        col = lin(tuple(min(255, int(x * sh)) for x in rgb))
        n = (V[i] + V[j] + V[k]) / 3 - c3
        mb.tri(V[i], V[j], V[k], (0, 0), (0, 0), (0, 0), col, n)


def roof(B, o):
    c, a, bb = o["c"], o["a"], o["b"]
    L, W, h = o["L"], o["W"], o["h"]
    kind, mat = o["roof"], o["roofmat"]
    rc = lin(o["roofcol"]); wc = lin(o["col"])
    ov = 0.45
    if kind == "laje":
        cs = [c - a * L / 2 - bb * W / 2, c + a * L / 2 - bb * W / 2, c + a * L / 2 + bb * W / 2, c - a * L / 2 + bb * W / 2]
        B["laje"].quad([v3(q, h) for q in cs], [(q[0] / 4, q[1] / 4) for q in cs], lin((205, 202, 196)), UP)
        # platibanda
        tij = o.get("tijolo", False)
        for k in range(4):
            p0, p1 = cs[k], cs[(k + 1) % 4]
            o2 = (p0 + p1) / 2 - c
            if tij:
                wall(B["tijolo"], p0, p1, h, h + 0.9, lin((255, 255, 255)), o2, "tijolo")
                wall(B["tijolo"], p1, p0, h, h + 0.9, lin((235, 235, 235)), -o2, "tijolo")
            else:
                wall(B["reboco"], p0, p1, h, h + 0.35, wc, o2, "reboco")
        if o.get("caixa"):
            q = c + a * rnd.uniform(-L / 4, L / 4) + bb * rnd.uniform(-W / 4, W / 4)
            yb = h
            if o.get("torre"):
                box(B, "reboco", q, a, 1.4, 1.4, h, h + 1.2, lin((175, 175, 172)))
                yb = h + 1.2
            cyl(B["cor"], q, 0.65, yb, yb + 0.95, lin((40, 95, 175)), 10)
        return
    if kind in ("gable_a", "hip"):
        ar, as_, Lr, Ws = a, bb, L, W
    else:
        ar, as_, Lr, Ws = bb, a, W, L
    tp = math.tan(math.radians(o["pitch"]))
    yr = h + Ws / 2 * tp; ye = h - ov * tp
    P = lambda r, s, y: np.array([c[0] + ar[0] * r + as_[0] * s, y, c[1] + ar[1] * r + as_[1] * s])
    sl = math.hypot(Ws / 2 + ov, (Ws / 2 + ov) * tp)
    if kind == "hip" and Lr > Ws * 0.6:
        rr = max(0.0, Lr / 2 - Ws / 2)
        for sg in (1, -1):
            n = np.array([as_[0] * sg, 1.5, as_[1] * sg])
            B[mat].quad([P(-Lr / 2 - ov, sg * (Ws / 2 + ov), ye), P(Lr / 2 + ov, sg * (Ws / 2 + ov), ye), P(rr, 0, yr), P(-rr, 0, yr)],
                        [(0, 0), (Lr / 2, 0), ((Lr / 2 + ov + rr) / 2, sl / 2), ((Lr / 2 + ov - rr) / 2, sl / 2)], rc, n)
            n2 = np.array([ar[0] * sg, 1.5, ar[1] * sg])
            B[mat].tri(P(sg * (Lr / 2 + ov), -(Ws / 2 + ov), ye), P(sg * (Lr / 2 + ov), Ws / 2 + ov, ye), P(sg * rr, 0, yr),
                       (0, 0), ((Ws + 2 * ov) / 2, 0), ((Ws / 2 + ov) / 2, sl / 2), rc, n2)
    else:
        for sg in (1, -1):
            n = np.array([as_[0] * sg, 1.5, as_[1] * sg])
            B[mat].quad([P(-Lr / 2 - ov, sg * (Ws / 2 + ov), ye), P(Lr / 2 + ov, sg * (Ws / 2 + ov), ye),
                          P(Lr / 2 + ov, 0, yr), P(-Lr / 2 - ov, 0, yr)],
                         [(0, 0), ((Lr + 2 * ov) / 2, 0), ((Lr + 2 * ov) / 2, sl / 2), (0, sl / 2)], rc, n)
            # oitão (empena)
            e = sg * Lr / 2
            B["reboco"].tri(P(e, -Ws / 2, h), P(e, Ws / 2, h), P(e, 0, yr), (0, 1 - h / 4), (Ws / 4, 1 - h / 4),
                            (Ws / 8, 1 - yr / 4), wc, np.array([ar[0] * sg, 0, ar[1] * sg]))


def build(o, B):
    ty = o["type"]
    if ty == "casa":
        c, a, bb, L, W, h = o["c"], o["a"], o["b"], o["L"], o["W"], o["h"]
        cs = [c - a * L / 2 - bb * W / 2, c + a * L / 2 - bb * W / 2, c + a * L / 2 + bb * W / 2, c - a * L / 2 + bb * W / 2]
        outs = [-bb, a, bb, -a]
        col = lin(o["col"])
        for k in range(4):
            mat = o["wall"]
            ck = col
            if k in (1, 3) and mat in ("parede", "parede2") and rnd.random() < 0.6: mat = "reboco"
            if k in (1, 3) and o.get("lateral_cinza"):
                mat = "reboco"; ck = lin((158, 160, 160))
            wall(B[mat], cs[k], cs[(k + 1) % 4], 0, h, ck, outs[k], mat, o.get("uoff", 0) if k == 0 else 0)
        if o.get("sacada") and h > 3:
            sw_ = min(L * 0.7, 6.0)
            sc = c - bb * (W / 2 + 0.6)
            box(B, "reboco", sc, a, sw_, 1.2, 2.78, 2.92, col)
            grade(B, sc - bb * 0.58, a, sw_, 2.92, 3.95, lin((245, 245, 245)), -bb)
            for sg in (-1, 1):
                grade(B, sc + a * (sw_ / 2 - 0.02) * sg, bb, 1.16, 2.92, 3.95, lin((245, 245, 245)), a * sg)
        if o.get("garagem_porta"):
            gp = c - bb * (W / 2 + 0.03) + a * (L / 2 - 1.6)
            box(B, "cor", gp, a, 2.6, 0.05, 0, 2.2, lin((242, 242, 242)))
        roof(B, o)
        if o.get("comercio"):
            fp = c - bb * (W / 2 + 0.04)
            nd = max(1, int(L // 4))
            for k in range(nd):
                dp = fp + a * (-L / 2 + (k + 0.5) * L / nd)
                box(B, "cor", dp, a, min(3.2, L / nd - 0.6), 0.06, 0, 3.0, lin(rnd.choice([(150, 152, 155), (120, 122, 125), (175, 175, 178)])))
            box(B, "cor", c - bb * (W / 2 + 0.15), a, L, 0.3, 3.05, 3.9, lin(o["placa"]), top=True)
            if rnd.random() < 0.5:  # toldo
                box(B, "cor", c - bb * (W / 2 + 0.9), a, L * 0.8, 1.6, 2.95, 3.0, lin(jitter(o["placa"], 30)))
        elif o.get("door"):
            fp = c - bb * (W / 2 + 0.03)
            dpos = fp + a * rnd.uniform(-L / 2 + 1.0, -0.6)
            box(B, "cor", dpos, a, 0.95, 0.06, 0, 2.1, lin(rnd.choice([(90, 60, 40), (60, 60, 65), (140, 100, 60), (200, 200, 200)])))
            if o["wall"] == "bloco":
                for k in range(int(L // 3.5)):
                    wp = fp + a * (-L / 2 + 2 + k * 3.5)
                    box(B, "cor", wp, a, 1.2, 0.06, 1.0, 2.1, lin((45, 55, 65)))
            pass
    elif ty == "osm":
        poly = o["poly"]; h = o["h"]
        area2 = sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))
        sg = 1 if area2 > 0 else -1
        col = lin(o["col"])
        if o["roof_only"]:
            for q in poly:
                cyl(B["cor"], q, 0.12, 0, h, lin((120, 120, 120)), 6, False)
        else:
            u = 0.0
            for k in range(len(poly)):
                p0, p1 = poly[k], poly[(k + 1) % len(poly)]
                d = p1 - p0
                out = np.array([d[1], -d[0]]) * sg
                wall(B[o["wall"]], p0, p1, 0, h, col, out, o["wall"], u)
                u += np.linalg.norm(d)
        rm = "laje" if o["roof"] == "laje" else "fibro"
        rcol = lin((205, 202, 196)) if rm == "laje" else lin(jitter((178, 178, 174), 10))
        for (i, j, k) in triangulate(poly):
            B[rm].tri(v3(poly[i], h), v3(poly[j], h), v3(poly[k], h), tuple(poly[i] / 4), tuple(poly[j] / 4), tuple(poly[k] / 4), rcol, UP)
    elif ty == "muro":
        p0, p1 = np.asarray(o["p0"]), np.asarray(o["p1"])
        L = float(np.linalg.norm(p1 - p0)); a = (p1 - p0) / max(L, 1e-6)
        col = lin(o["col"]); h = o["h"]
        if o.get("gate") is not None:
            g0 = L * o["gate"] - o["gatew"] / 2
            g0 = min(max(g0, 0.3), L - o["gatew"] - 0.3)
            pieces = [(0, g0), (g0 + o["gatew"], L)]
            # portão
            gc = p0 + a * (g0 + o["gatew"] / 2)
            gh = max(h, 1.95)
            if o.get("portao") == "grade":
                gcol = lin(rnd.choice([(245, 245, 245), (245, 245, 245), (150, 152, 155), (40, 40, 42)]))
                grade(B, gc, a, o["gatew"], 0.08, gh, gcol, o["out"])
            else:
                gcol = lin(rnd.choice([(235, 235, 235), (40, 40, 42), (90, 90, 95), (150, 150, 150), (60, 70, 90), (110, 75, 50)]))
                box(B, "cor", gc, a, o["gatew"], 0.06, 0, gh, gcol)
        else:
            pieces = [(0, L)]
        for s0, s1 in pieces:
            if s1 - s0 < 0.2: continue
            c = p0 + a * (s0 + s1) / 2
            box(B, "reboco", c, a, s1 - s0, 0.16, 0, h, col, uoff=s0)
            if o.get("grade"):
                gcol = lin(o.get("grade_cor", (245, 245, 245)))
                grade(B, c, a, s1 - s0, h, 2.05, gcol, o["out"])
                for e in np.arange(0.0, s1 - s0 + 0.01, max(1.0, (s1 - s0) / max(1, round((s1 - s0) / 2.6)))):   # pilares
                    box(B, "reboco", p0 + a * (s0 + e), a, 0.24, 0.24, 0, 2.15, col)
    elif ty == "lixeira":   # cesto de lixo de ferro no poste (bem de Curitiba)
        p, a = o["p"], o["a"]
        cyl(B["cor"], p, 0.035, 0, 1.15, lin((60, 60, 62)), 6, False)
        cb = p + o["out"] * 0.18
        bb = perp(a)
        for (d0, d1, nn) in ((-0.25, 0.25, None),):
            pass
        cor = lin(o["cor"])
        for sg in (-1, 1):
            grade(B, cb + bb * 0.17 * sg, a, 0.5, 1.15, 1.45, cor, bb * sg)
        for sg in (-1, 1):
            grade(B, cb + a * 0.25 * sg, bb, 0.34, 1.15, 1.45, cor, a * sg)
        box(B, "cor", cb, a, 0.5, 0.34, 1.13, 1.16, cor, top=True)
    elif ty == "arvore":
        p, s = o["p"], o["s"]
        m = B["cor"]
        if o["kind"] == "araucaria":
            H = 14 * s
            cyl(m, p, 0.28 * s, 0, H + 0.4, lin((95, 70, 50)), 6, False)
            tint = lin((150, 175, 140))
            for (dy, r_) in ((-2.2, 4.6), (-0.9, 5.2), (0.3, 4.4), (1.2, 2.8)):
                cen = v3(p, H + dy * s)
                for k in range(2):
                    a = rnd.uniform(0, math.pi) + k * math.pi / 2
                    copa_card(B["araucaria"], cen, a, r_ * s, r_ * s, tint, cen - np.array([0, 3.0 * s, 0]), deitado=True,
                              incl=rnd.uniform(-0.18, 0.18))
        else:
            H = 2.3 * s
            r0 = rnd.uniform(1.8, 2.6) * s
            cyl(m, p, 0.17 * s, 0, H + r0 * 0.6, lin((90, 68, 48)), 6, False)
            g = rnd.choice([(62, 100, 45), (75, 115, 50), (50, 88, 40), (90, 120, 55), (70, 105, 60)])
            tint = lin(tuple(min(255, int(c * 2.1)) for c in g))
            cen = v3(p, H + r0 * 0.8)
            a0 = rnd.uniform(0, math.pi)
            for k in range(3):
                copa_card(B["folhas"], cen, a0 + k * math.pi / 3, r0 * 2.3, r0 * 2.1, tint, cen)
            copa_card(B["folhas"], cen + np.array([0, r0 * 0.2, 0]), a0, r0 * 2.2, r0 * 2.2, tint, cen - np.array([0, r0, 0]), deitado=True)
            copa_card(B["folhas"], cen + np.array([0, r0 * 0.65, 0]), a0 + 0.7, r0 * 1.4, r0 * 1.4, tint, cen - np.array([0, r0, 0]), deitado=True)
    elif ty == "placa":
        p, f = o["p"], o["face"]
        m = B["cor"]
        alto = 2.95 if o.get("nomes") else 2.35
        cyl(m, p, 0.035, 0, alto, lin((150, 150, 155)), 6, True)
        cel = {"pare": 0, "lombada": 1, "v40": 2, "v60": 3}[o["kind"]]
        tam = 0.62 if o["kind"] != "lombada" else 0.75
        yc = 2.0
        lado = np.array([f[1], -f[0]])
        c3 = v3(p + f * 0.05, yc)
        e = np.array([lado[0], 0, lado[1]]) * tam / 2
        u = np.array([0, tam / 2, 0])
        nf = np.array([f[0], 0, f[1]])
        u0, u1 = cel / 8.0, (cel + 1) / 8.0
        B["placas"].quad([c3 - e - u, c3 + e - u, c3 + e + u, c3 - e + u], [(u0, 1), (u1, 1), (u1, 0), (u0, 0)], lin((255, 255, 255)), nf)
        c4 = c3 - nf * 0.02
        v0, v1 = 5 / 8.0 + 0.01, 6 / 8.0 - 0.01
        B["placas"].quad([c4 + e - u, c4 - e - u, c4 - e + u, c4 + e + u], [(v0, 1), (v1, 1), (v1, 0), (v0, 0)], lin((255, 255, 255)), -nf)
    elif ty == "poste":
        p, n, t = o["p"], o["n"], o["t"]
        m = B["cor"]; cc = lin((172, 172, 166))
        # poste de concreto (afina pra cima)
        for (y0, y1, wd) in ((0, 4.5, 0.30), (4.5, 9.0, 0.22)):
            box(B, "cor", p, t, wd, wd, y0, y1, cc, top=(y1 == 9.0))
        box(B, "cor", p, n, 1.5, 0.10, 8.15, 8.27, lin((150, 120, 90)))      # cruzeta
        box(B, "cor", p + n * 0.9, n, 1.9, 0.07, 7.15, 7.25, lin((140, 140, 140)))  # braço
        lp = p + n * 1.8
        box(B, "cor", lp, n, 0.65, 0.28, 6.95, 7.2, lin((120, 120, 125)))
        box(B, "lampada", lp, n, 0.5, 0.2, 6.92, 6.96, lin((255, 220, 160)), top=False)
        if o["trafo"]:
            cyl(m, p - n * 0.55, 0.38, 5.6, 6.9, lin((140, 145, 140)), 8)
    elif ty == "fios":
        (q0, t0), (q1, t1) = o["a"], o["b"]
        n0, n1 = perp(t0), perp(t1)
        if np.dot(n0, n1) < 0: n1 = -n1
        m = B["fio"]; col = lin((25, 25, 25))
        fios = [(-0.6, 8.27, 0.5), (0.0, 8.27, 0.5), (0.6, 8.27, 0.5)] + [(rnd.uniform(-0.3, 0.5), rnd.uniform(5.6, 6.6), rnd.uniform(0.5, 1.2)) for _ in range(o.get("n", 6))]
        for off, y, sag in fios:
            a = v3(q0 + n0 * off, y); bq = v3(q1 + n1 * off, y)
            segs = 6
            pts = [a + (bq - a) * (k / segs) - np.array([0, sag * 4 * (k / segs) * (1 - k / segs), 0]) for k in range(segs + 1)]
            for k in range(segs):
                p0, p1 = pts[k], pts[k + 1]
                m.quad([p0 + [0, 0.02, 0], p1 + [0, 0.02, 0], p1 - [0, 0.02, 0], p0 - [0, 0.02, 0]], [(0, 0)] * 4, col)
    elif ty == "ponto":
        c, a, bb = o["c"], o["a"], o["b"]
        for e in (-1.6, 1.6):
            box(B, "cor", c + a * e + bb * 0.5, a, 0.08, 0.08, 0, 2.6, lin((60, 60, 65)))
        box(B, "cor", c, a, 3.8, 1.6, 2.6, 2.72, lin((190, 190, 195)))
        box(B, "cor", c + bb * 0.6, a, 3.4, 0.05, 0.5, 2.5, lin((150, 175, 190)))
        box(B, "cor", c + bb * 0.3, a, 2.8, 0.35, 0.45, 0.5, lin((120, 120, 125)))
    elif ty == "posto":
        c, a, bb = o["c"], o["a"], o["b"]
        box(B, "cor", c, a, 22, 13, 5.0, 5.9, lin((240, 240, 240)))
        box(B, "cor", c, a, 22.1, 13.1, 5.45, 5.75, lin((20, 80, 170)), top=False)
        for ea in (-7, 7):
            for eb in (-3.5, 3.5):
                box(B, "cor", c + a * ea + bb * eb, a, 0.5, 0.5, 0, 5.0, lin((220, 220, 220)))
        for ea in (-5, 5):
            box(B, "cor", c + a * ea, a, 6, 1.2, 0, 0.2, lin((200, 200, 200)))
            for k in (-1.6, 1.6):
                box(B, "cor", c + a * (ea + k), a, 0.7, 0.5, 0.2, 1.9, lin((230, 230, 235)))
                box(B, "cor", c + a * (ea + k) - bb * 0.26, a, 0.5, 0.02, 1.2, 1.7, lin((30, 30, 35)))
        sc = c + bb * 13
        box(B, "reboco", sc, a, 12, 8, 0, 4, lin((240, 240, 235)))
        box(B, "cor", sc - bb * 4.05, a, 8, 0.05, 0.3, 2.6, lin((60, 80, 95)))
        box(B, "cor", c - bb * 9 + a * 13, a, 0.4, 0.4, 0, 7, lin((200, 200, 200)))
        box(B, "cor", c - bb * 9 + a * 13, a, 2.2, 0.3, 6, 8.5, lin((20, 80, 170)))
    elif ty == "loja":
        c, a, bb, L, D, H = o["c"], o["a"], o["b"], o["L"], o["D"], o["H"]
        cs = [c - a * L / 2 - bb * D / 2, c + a * L / 2 - bb * D / 2, c + a * L / 2 + bb * D / 2, c - a * L / 2 + bb * D / 2]
        outs = [-bb, a, bb, -a]
        for k in range(4):
            wall(B["reboco"], cs[k], cs[(k + 1) % 4], 0, H, lin((238, 236, 230)), outs[k], "reboco")
        B["laje"].quad([v3(q, H) for q in cs], [(q[0] / 4, q[1] / 4) for q in cs], lin((200, 200, 195)), UP)
        front = c - bb * (D / 2 + 0.05)
        for e in (-4.4, 0, 4.4):
            box(B, "cor", front + a * e, a, 3.4, 0.08, 0, 3.6, lin((150, 152, 155)))
        # placa
        f2 = c - bb * (D / 2 + 0.25)
        p0, p1 = f2 - a * (L / 2 - 0.3), f2 + a * (L / 2 - 0.3)
        B["placa"].quad([v3(p0, 4.1), v3(p1, 4.1), v3(p1, 5.9), v3(p0, 5.9)], [(0, 1), (1, 1), (1, 0), (0, 0)],
                        lin((255, 255, 255)), np.array([-bb[0], 0, -bb[1]]))
        box(B, "cor", f2 + bb * 0.12, a, L - 0.4, 0.2, 4.0, 6.0, lin((60, 60, 60)), top=True)


def pegada(o):
    t = o["type"]
    if t == "casa": return rect_pts(o["c"], o["a"], o["L"], o["W"])
    if t == "osm": return o["poly"]
    if t in ("loja",): return rect_pts(o["c"], o["a"], o["L"], o["D"])
    if t in ("posto", "ponto"): return np.array([o["c"]])
    if t in ("arvore", "poste", "placa"): return np.array([o["p"]])
    return np.array([o["ref"]])


def build_y(o, B):
    """monta o objeto e coloca em cima do terreno (casas inteiras; muro e fio acompanham o chão)"""
    if T is None:
        build(o, B); return
    marcas = {k: len(mb.P) for k, mb in B.items()}
    build(o, B)
    seguir = o["type"] in ("muro", "fios")
    if not seguir:
        pts = pegada(o)
        hs = T.alt(pts[:, 0], pts[:, 1])
        base = float(np.mean(hs)); drop = base - float(np.min(hs)) + 0.35
    for k, mb in B.items():
        s0 = marcas[k]
        if len(mb.P) == s0: continue
        A = np.array(mb.P[s0:])
        baixo = A[:, 1] < 0.01
        if seguir:
            A[:, 1] += T.alt(A[:, 0], A[:, 2]) - baixo * 0.35
        else:
            A[:, 1] += base - baixo * drop
        mb.P[s0:] = list(A)


MATS = {
    "parede": dict(tex="tex/parede.png"), "parede2": dict(tex="tex/parede2.png"), "reboco": dict(tex="tex/reboco.png"), "bloco": dict(tex="tex/bloco.png"),
    "galpao": dict(tex="tex/galpao.png", rough=0.6), "telha": dict(tex="tex/telha.png", double=True),
    "fibro": dict(tex="tex/fibro.png", double=True), "laje": dict(tex="tex/laje.png"), "cor": dict(),
    "fio": dict(double=True), "lampada": dict(emissive=[1.0, 0.85, 0.6]), "placa": dict(tex="tex/placa_show.png"),
    "grade": dict(tex="tex/grade.png", alpha=True, double=True, rough=0.5), "tijolo": dict(tex="tex/tijolo.png"),
    "folhas": dict(tex="tex/folhas.png", alpha=True, double=True, rough=0.85),
    "araucaria": dict(tex="tex/araucaria.png", alpha=True, double=True, rough=0.85),
    "placas": dict(tex="tex/placas.png", alpha=True, rough=0.45),
    "marca": dict(rough=0.7), "marca_txt": dict(tex="tex/placas.png", alpha=True, rough=0.7),
}

# ----------------------------------------------------------------------------- chão por bloco
GT = texturas.ground_tiles(SEED)
GCLS = ["terreno", "grama", "mata", "agua", "industrial", "aterro", "calcada", "meiofio", "asfalto", "paralelepipedo",
        "terra_rua", "trilha", "campo", "estacionamento", "concreto"]
GI = {k: i for i, k in enumerate(GCLS)}
WEAR = 0.75 + 0.25 * np.tile(texturas.fbm(512, np_rng, 8), (TEX // 512, TEX // 512))
GT4 = {k: np.tile(GT[k], (TEX // 512, TEX // 512, 1)) for k in GCLS + ["terreno_terra"]}
FIELDS = {sp: np_rng.random((int((ZMAX - ZMIN) / sp) + 8, int((XMAX - XMIN) / sp) + 8)).astype(np.float32) for sp in (4, 13, 45)}


def wfield(ox, oz, sp):
    g = FIELDS[sp]
    xs = ((ox + (np.arange(TEX) + 0.5) * RES) - XMIN) / sp + 2
    zs = ((oz + (np.arange(TEX) + 0.5) * RES) - ZMIN) / sp + 2
    mx, mz = np.meshgrid(np.clip(xs, 0, g.shape[1] - 1), np.clip(zs, 0, g.shape[0] - 1))
    return cv2.remap(g, mx.astype(np.float32), mz.astype(np.float32), cv2.INTER_CUBIC, borderMode=cv2.BORDER_REFLECT)
GSH = 4


def ground(cx, cz):
    ox, oz = XMIN + cx * CH, ZMIN + cz * CH
    def px(pts, s=1.0): return np.round((np.asarray(pts) - [ox, oz]) / RES * s * (1 << GSH)).astype(np.int32)
    def thick(m, s=1.0): return max(1, int(round(m / RES * s)))
    bx0, bz0, bx1, bz1 = ox - 40, oz - 40, ox + CH + 40, oz + CH + 40
    def vis(pts):
        mn, mx = pts.min(0), pts.max(0)
        return not (mx[0] < bx0 or mn[0] > bx1 or mx[1] < bz0 or mn[1] > bz1)
    C = np.full((TEX, TEX), GI["terreno"], np.uint8)
    for cls, outs, ins, t in areas:
        if not any(vis(o) for o in outs): continue
        cv2.fillPoly(C, [px(o) for o in outs], GI[cls], cv2.LINE_8, GSH)
        if ins: cv2.fillPoly(C, [px(o) for o in ins], GI["terreno"], cv2.LINE_8, GSH)
    for poly, cls in extra_ground:
        if vis(poly): cv2.fillPoly(C, [px(poly)], GI[cls], cv2.LINE_8, GSH)
    for pts, w in waterways:
        if vis(pts):
            cv2.polylines(C, [px(pts)], False, GI["grama"], thick(w + 5), cv2.LINE_8, GSH)
    for pts, w in waterways:
        if vis(pts):
            cv2.polylines(C, [px(pts)], False, GI["agua"], thick(w), cv2.LINE_8, GSH)
    vr = [r for r in roads if vis(r["pts"])]
    for r in vr:
        if r["car"] and r["sw"] > 0:
            cv2.polylines(C, [px(r["pts"])], False, GI["calcada"], thick(r["w"] + 2 * r["sw"]), cv2.LINE_8, GSH)
        elif r["cls"] in ("motorway", "busway", "motorway_link"):
            cv2.polylines(C, [px(r["pts"])], False, GI["grama"], thick(r["w"] + 3), cv2.LINE_8, GSH)
    for r in vr:
        if not r["car"]:
            cv2.polylines(C, [px(r["pts"])], False, GI[r["kind"]], thick(r["w"]), cv2.LINE_8, GSH)
    for r in vr:
        if r["car"] and r["sw"] > 0:
            cv2.polylines(C, [px(r["pts"])], False, GI["meiofio"], thick(r["w"] + 0.5), cv2.LINE_8, GSH)
    for r in sorted(vr, key=lambda r: r["rank"]):
        if r["car"]:
            cv2.polylines(C, [px(r["pts"])], False, GI[r["kind"]], thick(r["w"]), cv2.LINE_8, GSH)
    f1, f2, f3 = wfield(ox, oz, 4), wfield(ox, oz, 13), wfield(ox, oz, 45)
    fmix = 0.2 * f1 + 0.45 * f2 + 0.35 * f3
    img = np.zeros((TEX, TEX, 3), np.float32)
    for k, i in GI.items():
        m = C == i
        if not m.any(): continue
        if k == "terreno":
            mm = np.clip((fmix[m] - 0.52) * 4 + 0.5, 0, 1)[:, None]
            img[m] = GT4[k][m] * (1 - mm) + GT4["terreno_terra"][m] * mm
        else:
            img[m] = GT4[k][m]
    img *= (0.9 + 0.2 * (0.5 * f2 + 0.5 * f3))[..., None]
    img = cv2.GaussianBlur(img, (0, 0), 0.7)
    # sombra de contato (prédios, muros, árvores)
    F = np.zeros((TEX, TEX), np.float32)
    for poly in foot:
        if vis(poly): cv2.fillPoly(F, [px(poly)], 1.0, cv2.LINE_8, GSH)
    ao = cv2.GaussianBlur(F, (0, 0), 7)
    shade = 1 - 0.42 * np.clip(ao * 1.6, 0, 1) * (1 - F)
    T = np.zeros((TEX, TEX), np.float32)
    for o in tree_list:
        if bx0 < o["p"][0] < bx1 and bz0 < o["p"][1] < bz1:
            q = px(o["p"][None])[0]
            rad = thick(2.2 * o["s"] * (2.0 if o["kind"] == "araucaria" else 1.0))
            cv2.circle(T, (int(q[0]), int(q[1])), rad, 1.0, -1, cv2.LINE_8, GSH)
    T = cv2.GaussianBlur(T, (0, 0), 10)
    shade *= 1 - 0.28 * np.clip(T, 0, 1)
    img *= shade[..., None]
    if not PINTAR_MARCAS:
        return np.clip(img, 0, 255).astype(np.uint8)
    # sinalização (2x supersample)
    S2 = 2
    MW = np.zeros((TEX * S2, TEX * S2), np.uint8); MY = np.zeros_like(MW)
    for lst, M in ((marks_w, MW), (marks_y, MY)):
        for (a, bq) in lst:
            if not (bx0 < a[0] < bx1 and bz0 < a[1] < bz1): continue
            pa, pb = px(a[None], S2)[0], px(bq[None], S2)[0]
            cv2.line(M, (int(pa[0]), int(pa[1])), (int(pb[0]), int(pb[1])), 255, thick(0.15, S2), cv2.LINE_AA, GSH)
    for poly in marks_poly:
        if vis(poly): cv2.fillPoly(MW, [px(poly, S2)], 255, cv2.LINE_AA, GSH)
    MW = cv2.resize(MW, (TEX, TEX), interpolation=cv2.INTER_AREA).astype(np.float32) / 255.0
    MY = cv2.resize(MY, (TEX, TEX), interpolation=cv2.INTER_AREA).astype(np.float32) / 255.0
    aw, ay = MW * WEAR, MY * WEAR
    img = img * (1 - aw[..., None]) + np.array([225, 225, 222]) * aw[..., None]
    img = img * (1 - ay[..., None]) + np.array([225, 175, 40]) * ay[..., None]
    return np.clip(img, 0, 255).astype(np.uint8)


PINTAR_MARCAS = False   # v24: faixas/PARE viraram geometria (ficam nítidas de perto)


def chao_y(X, Z):
    """altura exata da malha do chão (grade de 4 m, triângulos com diagonal i01-i10)"""
    X = np.asarray(X, float); Z = np.asarray(Z, float)
    gx = (X - XMIN) / 4.0; gz = (Z - ZMIN) / 4.0
    i0 = np.floor(gx); j0 = np.floor(gz)
    u = gx - i0; v = gz - j0
    x0 = XMIN + i0 * 4.0; z0 = ZMIN + j0 * 4.0
    y00 = ALT(x0, z0); y10 = ALT(x0 + 4.0, z0); y01 = ALT(x0, z0 + 4.0); y11 = ALT(x0 + 4.0, z0 + 4.0)
    baixo = (u + v) <= 1.0
    ya = y00 + u * (y10 - y00) + v * (y01 - y00)
    yb = y11 + (1 - u) * (y01 - y11) + (1 - v) * (y10 - y11)
    return np.where(baixo, ya, yb)


def sinalizacao_bloco(ox, oz):
    """faixas, linhas de PARE, zebras e PARE escrito no chão deste bloco (como geometria em cima do asfalto)"""
    mb = MeshBuilder(); mt = MeshBuilder()
    def dentro(q): return ox <= q[0] < ox + CH and oz <= q[1] < oz + CH
    def assentar(cs):
        cs = np.asarray(cs, float)
        ys = chao_y(cs[:, 0], cs[:, 1]) + 0.03
        return [np.array([c[0], y, c[1]]) for c, y in zip(cs, ys)]
    for lst, cor, larg in ((marks_w, lin((236, 236, 230)), 0.12), (marks_y, lin((250, 208, 64)), 0.12)):
        for (a, bq) in lst:
            meio = (np.asarray(a) + bq) / 2
            if not dentro(meio): continue
            dd = np.asarray(bq) - a; L = np.linalg.norm(dd)
            if L < 0.05: continue
            dd = dd / L; nn = np.array([-dd[1], dd[0]]) * larg / 2
            mb.quad(assentar([a - nn, bq - nn, bq + nn, a + nn]), [(0, 0)] * 4, cor, UP)
    for poly in marks_poly:
        if not dentro(poly.mean(0)): continue
        mb.quad(assentar(poly), [(0, 0)] * 4, lin((236, 236, 230)), UP)
    for (c, d, W, L) in marks_txt:
        if not dentro(c): continue
        dr = np.array([-d[1], d[0]])
        cs = [c - d * L / 2 - dr * W / 2, c - d * L / 2 + dr * W / 2, c + d * L / 2 + dr * W / 2, c + d * L / 2 - dr * W / 2]
        u0, u1 = 4 / 8.0, 5 / 8.0
        mt.quad(assentar(cs), [(u0, 1), (u1, 1), (u1, 0), (u0, 0)], lin((255, 255, 255)), UP)
    return {"marca": mb, "marca_txt": mt}


tree_list = [o for o in objs if o["type"] == "arvore"]
os.makedirs(f"{OUT}/blocos/tex", exist_ok=True)
texturas.build_all(f"{OUT}/blocos/tex")
import texturas2
texturas2.salvar_todas(f"{OUT}/blocos/tex")

# distribui objetos nos blocos
buckets = {}
for o in objs:
    cx = int((o["ref"][0] - XMIN) // CH); cz = int((o["ref"][1] - ZMIN) // CH)
    if 0 <= cx < NX and 0 <= cz < NZ:
        buckets.setdefault((cx, cz), []).append(o)

meta = dict(bloco_m=CH, nx=NX, nz=NZ, origem=[XMIN, ZMIN], limites=[XMIN, ZMIN, XMAX, ZMAX],
            lat0=lat0, lon0=lon0, blocos={}, fonte="© OpenStreetMap contributors (ODbL)")
mini = np.zeros((NZ * 256, NX * 256, 3), np.uint8)
tot_v = 0
for cz in range(NZ):
    for cx in range(NX):
        name = f"bloco_{cx}_{cz}"
        img = ground(cx, cz)
        texturas.save(f"{OUT}/blocos/tex/chao_{cx}_{cz}.jpg", img, q=86)
        mini[cz * 256:(cz + 1) * 256, cx * 256:(cx + 1) * 256] = cv2.resize(img, (256, 256), interpolation=cv2.INTER_AREA)
        ox, oz = XMIN + cx * CH, ZMIN + cz * CH
        # chão: malha de 4 em 4 m seguindo o terreno (com colisão)
        PASSO = 4.0; ng = int(CH / PASSO) + 1
        gx = ox + np.arange(ng) * PASSO; gz = oz + np.arange(ng) * PASSO
        GX, GZ = np.meshgrid(gx, gz)
        GY = ALT(GX, GZ) if T is not None else np.zeros_like(GX)
        dzz, dxx = np.gradient(GY, PASSO)
        Nn = np.stack([-dxx, np.ones_like(GY), -dzz], -1); Nn /= np.linalg.norm(Nn, axis=-1, keepdims=True)
        P = np.stack([GX, GY, GZ], -1).reshape(-1, 3).astype(np.float32)
        N = Nn.reshape(-1, 3).astype(np.float32)
        UV = np.stack([(GX - ox) / CH, (GZ - oz) / CH], -1).reshape(-1, 2).astype(np.float32)
        ii, jj = np.meshgrid(np.arange(ng - 1), np.arange(ng - 1))
        i00 = (jj * ng + ii).ravel(); i10 = i00 + 1; i01 = i00 + ng; i11 = i01 + 1
        I = np.stack([i00, i01, i10, i10, i01, i11], -1).ravel().astype(np.uint32)
        mats = dict(MATS); mats[f"chao_{cx}_{cz}"] = dict(tex=f"tex/chao_{cx}_{cz}.jpg", clamp=True, rough=0.95)
        Bc = {k: MeshBuilder() for k in ("grade", "tijolo", "parede", "parede2", "reboco", "bloco", "galpao", "telha", "fibro", "laje", "cor", "placa")}
        Bv = {k: MeshBuilder() for k in ("cor", "folhas", "araucaria")}
        Bp = {k: MeshBuilder() for k in ("cor", "fio", "lampada", "placas")}
        lamps = []
        obst = []
        CEL = 50.0   # árvores de copa em células de 50 m: de perto o jogo troca pela árvore 3D de verdade
        Bcel = {}
        arv_meta = []
        for o in buckets.get((cx, cz), []):
            if o["type"] == "arvore" and o["kind"] == "copa":
                ci = int(min(CH / CEL - 1, max(0, (o["p"][0] - ox) // CEL))); ck = int(min(CH / CEL - 1, max(0, (o["p"][1] - oz) // CEL)))
                if (ci, ck) not in Bcel:
                    Bcel[(ci, ck)] = {k: MeshBuilder() for k in ("cor", "folhas")}
                build_y(o, Bcel[(ci, ck)])
                arv_meta.append([round(float(o["p"][0]), 2), round(float(ALT(*o["p"])), 2), round(float(o["p"][1]), 2), round(float(o["s"]), 2), ci, ck])
                obst.append([round(float(o["p"][0]), 2), round(float(o["p"][1]), 2), round(0.2 * o["s"], 2), round(ALT(*o["p"]), 2)])
                continue
            if o["type"] == "arvore":
                build_y(o, Bv)
                obst.append([round(float(o["p"][0]), 2), round(float(o["p"][1]), 2), round(0.3 * o["s"] if o["kind"] == "araucaria" else 0.2 * o["s"], 2),
                             round(ALT(*o["p"]), 2)])
            elif o["type"] == "placa":
                build_y(o, Bp)
                obst.append([round(float(o["p"][0]), 2), round(float(o["p"][1]), 2), 0.07, round(ALT(*o["p"]), 2)])
            elif o["type"] in ("poste", "fios"):
                build_y(o, Bp)
                if o["type"] == "poste":
                    yb = ALT(*o["p"])
                    obst.append([round(float(o["p"][0]), 2), round(float(o["p"][1]), 2), 0.18, round(yb, 2)])
                    lamps.append([round(float(o["p"][0] + o["n"][0] * 1.8), 2), round(yb + 6.6, 2), round(float(o["p"][1] + o["n"][1] * 1.8), 2)])
            else:
                build_y(o, Bc)
        Bs = sinalizacao_bloco(ox, oz)
        nodes_out = [("Chao-col", {f"chao_{cx}_{cz}": (P, N, UV, None, I)}),
                     ("Construcoes-col", Bc), ("Arvores", Bv), ("Postes", Bp), ("Sinalizacao", Bs)]
        for (ci, ck), bb in sorted(Bcel.items()):
            nodes_out.append((f"ArvoresC_{ci}_{ck}", bb))
        tot_v += sum(len(mb.P) for d in [Bc, Bv, Bp] + list(Bcel.values()) for mb in d.values())
        write_glb(f"{OUT}/blocos/{name}.glb", nodes_out, mats)
        nomes = [[round(float(q[0][0]), 2), round(float(ALT(*q[0])), 2), round(float(q[0][1]), 2), round(q[1], 3), q[2], round(q[3], 3), q[4]]
                 for q in NOMES if ox <= q[0][0] < ox + CH and oz <= q[0][1] < oz + CH]
        meta["blocos"][name] = dict(cx=cx, cz=cz, centro=[ox + CH / 2, oz + CH / 2], luzes=lamps, obst=obst, nomes=nomes,
                                    arvores=arv_meta)
    print(f"linha {cz+1}/{NZ} ok")

# ponto de partida: na rua, em frente ao portão da Drops
if drops:
    fr, n_, t_ = drops["front"], drops["nrm"], drops["t"]
    yaw_dg = math.atan2(n_[0], n_[1])
    meta["drops_garage"] = dict(pos=[float(fr[0]), float(drops.get("y", 0.0)), float(fr[1])], yaw=float(yaw_dg),
                                endereco=f"{DROPS_RUA}, {DROPS_NUM}")
    # portão fica 2,3 m pra esquerda de quem olha da rua (eixo +X local do modelo)
    gate = fr + np.array([math.cos(yaw_dg), -math.sin(yaw_dg)]) * 2.3
    sp = drops["street"] + (gate - fr) + n_ * 1.8
    meta["spawn"] = dict(pos=[float(sp[0]), ALT(*sp) + 0.6, float(sp[1])], yaw=float(math.atan2(t_[0], t_[1])),
                         obs="em frente ao portão da Drops Garage")
    meta["portao_drops"] = [float(gate[0]), 0.0, float(gate[1])]
elif shop:
    sp = shop["street_pt"]; t = shop["t"]
    meta["spawn"] = dict(pos=[float(sp[0]), 0.6, float(sp[1])], yaw=float(math.atan2(-t[0], -t[1])))
    meta["loja_show_de_ferragens"] = [float(shop["c"][0]), 0, float(shop["c"][1])]
elif RP_SPAWN is not None:
    sp, t = RP_SPAWN
    meta["spawn"] = dict(pos=[float(sp[0] + perp(t)[0] * 1.8), 0.6, float(sp[1] + perp(t)[1] * 1.8)], yaw=float(math.atan2(-t[0], -t[1])),
                         obs="Rua Raul Pompéia, ponta mais perto da loja (o nº 1701 ficou fora do recorte)")
else:
    meta["spawn"] = dict(pos=[0, 0.6, 0], yaw=0)
meta.update(POIS)
if T is not None:
    T.salvar(f"{OUT}/terreno.bin")
    meta["terreno"] = dict(arquivo="terreno.bin", res=T.res, nx=T.nx, nz=T.nz, x0=T.x0, z0=T.z0, altitude_base=T.base,
                           fonte="Curvas de nível IPPUC/Prefeitura de Curitiba")
    meta["fonte"] += " · Lotes e curvas de nível: IPPUC / Prefeitura de Curitiba"
meta["pois"] = [dict(nome=t.get("name", ""), tipo=t.get("amenity") or t.get("shop") or t.get("highway"),
                     pos=[round(nodes[i][0], 1), 0, round(nodes[i][1], 1)]) for i, t in ntags.items()
                if t.get("name") and (t.get("amenity") or t.get("shop"))]
json.dump(meta, open(f"{OUT}/mapa_cic.json", "w"), ensure_ascii=False, indent=1)
ruas = [dict(nome=r["name"], tipo=r["cls"], largura=r["w"], pts=np.round(r["pts"], 1).tolist())
        for r in roads if r["car"]]
json.dump(ruas, open(f"{OUT}/ruas.json", "w"), ensure_ascii=False)
cv2.imwrite(f"{OUT}/minimapa.png", cv2.cvtColor(mini, cv2.COLOR_RGB2BGR))
print("vértices totais:", tot_v)
