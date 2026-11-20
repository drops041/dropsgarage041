"""Leitura mínima de shapefile + conversão SAD69 / UTM 22S -> WGS84 (sem dependências)."""
import struct, math
import numpy as np

# elipsoides
GRS67 = (6378160.0, 1 / 298.25)
WGS84 = (6378137.0, 1 / 298.257223563)
SAD69_TO_WGS = (-67.35, 3.88, -38.22)   # IBGE (SAD69 -> SIRGAS2000 ~ WGS84)


def tm_inverse(E, N, a, f, lon0=-51.0, k0=0.9996, FE=500000.0, FN=10000000.0):
    """UTM (sul) -> lat/lon em graus. Vetorizado (Snyder)."""
    e2 = f * (2 - f); ep2 = e2 / (1 - e2)
    x = (np.asarray(E) - FE) / k0
    M = (np.asarray(N) - FN) / k0
    mu = M / (a * (1 - e2 / 4 - 3 * e2 ** 2 / 64 - 5 * e2 ** 3 / 256))
    e1 = (1 - math.sqrt(1 - e2)) / (1 + math.sqrt(1 - e2))
    phi1 = (mu + (3 * e1 / 2 - 27 * e1 ** 3 / 32) * np.sin(2 * mu) + (21 * e1 ** 2 / 16 - 55 * e1 ** 4 / 32) * np.sin(4 * mu)
            + (151 * e1 ** 3 / 96) * np.sin(6 * mu) + (1097 * e1 ** 4 / 512) * np.sin(8 * mu))
    C1 = ep2 * np.cos(phi1) ** 2; T1 = np.tan(phi1) ** 2
    N1 = a / np.sqrt(1 - e2 * np.sin(phi1) ** 2); R1 = a * (1 - e2) / (1 - e2 * np.sin(phi1) ** 2) ** 1.5
    D = x / N1
    lat = phi1 - (N1 * np.tan(phi1) / R1) * (D ** 2 / 2 - (5 + 3 * T1 + 10 * C1 - 4 * C1 ** 2 - 9 * ep2) * D ** 4 / 24
                                             + (61 + 90 * T1 + 298 * C1 + 45 * T1 ** 2 - 252 * ep2 - 3 * C1 ** 2) * D ** 6 / 720)
    lon = math.radians(lon0) + (D - (1 + 2 * T1 + C1) * D ** 3 / 6 + (5 - 2 * C1 + 28 * T1 - 3 * C1 ** 2 + 8 * ep2 + 24 * T1 ** 2) * D ** 5 / 120) / np.cos(phi1)
    return np.degrees(lat), np.degrees(lon)


def datum_shift(lat, lon, src, dst, d):
    lat = np.radians(lat); lon = np.radians(lon)
    a, f = src; e2 = f * (2 - f)
    N = a / np.sqrt(1 - e2 * np.sin(lat) ** 2)
    X = N * np.cos(lat) * np.cos(lon) + d[0]
    Y = N * np.cos(lat) * np.sin(lon) + d[1]
    Z = N * (1 - e2) * np.sin(lat) + d[2]
    a2, f2 = dst; e22 = f2 * (2 - f2)
    p = np.sqrt(X ** 2 + Y ** 2); lon2 = np.arctan2(Y, X)
    lat2 = np.arctan2(Z, p * (1 - e22))
    for _ in range(5):
        N2 = a2 / np.sqrt(1 - e22 * np.sin(lat2) ** 2)
        lat2 = np.arctan2(Z + e22 * N2 * np.sin(lat2), p)
    return np.degrees(lat2), np.degrees(lon2)


def utm_sad69_to_wgs(E, N):
    la, lo = tm_inverse(E, N, *GRS67)
    return datum_shift(la, lo, GRS67, WGS84, SAD69_TO_WGS)


def wgs_to_utm_sad69_approx(lat, lon):
    """inversa aproximada (só pra recortar a área): iteração simples."""
    E, N = 670000.0, 7180000.0
    for _ in range(6):
        la, lo = utm_sad69_to_wgs(np.array([E]), np.array([N]))
        E += (lon - lo[0]) * 111320 * math.cos(math.radians(lat))
        N += (lat - la[0]) * 110574
    return E, N


# ------------------------------------------------------------------ shapefile
def ler_dbf(path, campos=None):
    f = open(path, "rb"); h = f.read(32)
    n = struct.unpack("<I", h[4:8])[0]; hl, rl = struct.unpack("<HH", h[8:12])
    fields = []
    while True:
        d = f.read(32)
        if d[0] == 0x0D: break
        fields.append((d[:11].split(b"\0")[0].decode(), chr(d[11]), d[16]))
    f.seek(hl)
    raw = f.read(n * rl)
    out = []
    offs = []; o = 1
    for nm, t, ln in fields:
        offs.append((nm, o, ln, t)); o += ln
    want = [x for x in offs if campos is None or x[0] in campos]
    for i in range(n):
        r = raw[i * rl:(i + 1) * rl]
        rec = {}
        for nm, o, ln, t in want:
            v = r[o:o + ln].decode("latin-1").strip()
            if t in "NF":
                try: v = float(v) if v else None
                except ValueError: v = None
            rec[nm] = v
        out.append(rec)
    return out


def ler_shp(path, bbox=None):
    """retorna lista de (indice, partes[list of Nx2]) para registros que cruzam bbox (xmin,ymin,xmax,ymax)."""
    shx = open(path[:-4] + ".shx", "rb").read()
    n = (len(shx) - 100) // 8
    offs = np.frombuffer(shx[100:], dtype=">i4").reshape(n, 2)[:, 0] * 2
    f = open(path, "rb")
    res = []
    for i in range(n):
        f.seek(int(offs[i]) + 8)
        hdr = f.read(44)
        t = struct.unpack("<i", hdr[:4])[0]
        if t == 0: continue
        bb = struct.unpack("<4d", hdr[4:36])
        if bbox and (bb[2] < bbox[0] or bb[0] > bbox[2] or bb[3] < bbox[1] or bb[1] > bbox[3]):
            continue
        npart, npt = struct.unpack("<2i", hdr[36:44])
        parts = np.frombuffer(f.read(4 * npart), "<i4")
        pts = np.frombuffer(f.read(16 * npt), "<f8").reshape(npt, 2)
        bounds = list(parts) + [npt]
        res.append((i, [pts[bounds[k]:bounds[k + 1]] for k in range(npart)]))
    return res
