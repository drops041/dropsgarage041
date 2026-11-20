"""Desenha os telhados (vista de cima) no minimapa a partir dos blocos GLB."""
import sys, json, struct, glob, numpy as np, cv2
D = sys.argv[1]
meta = json.load(open(f"{D}/mapa_cic.json"))
mini = cv2.imread(f"{D}/minimapa.png")
X0, Z0 = meta["origem"]; k = mini.shape[1] / (meta["nx"] * meta["bloco_m"])
SS = 3  # supersample
big = cv2.resize(mini, None, fx=SS, fy=SS, interpolation=cv2.INTER_LINEAR)
big = (big * 0.8 + 30).astype(np.uint8)   # chão um pouco mais apagado, telhado em destaque
TEXCOL = {"telha": (205, 120, 85), "fibro": (185, 185, 180), "laje": (200, 198, 192), "parede": (235, 235, 230), "parede2": (235, 235, 230),
          "reboco": (235, 235, 230), "bloco": (180, 178, 170), "galpao": (215, 215, 215), "cor": (255, 255, 255), "placa": (220, 40, 40)}
tris_all = []
for f in sorted(glob.glob(f"{D}/blocos/bloco_*.glb")):
    b = open(f, "rb").read(); jl = struct.unpack("<I", b[12:16])[0]; js = json.loads(b[20:20 + jl]); binb = b[28 + jl:]
    def acc(i):
        a = js["accessors"][i]; bv = js["bufferViews"][a["bufferView"]]
        dt = {5126: np.float32, 5125: np.uint32, 5121: np.uint8}[a["componentType"]]
        nc = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        return np.frombuffer(binb, dt, a["count"] * nc, bv["byteOffset"]).reshape(-1, nc)
    for nd in js["nodes"]:
        if not nd["name"].startswith("Construcoes"): continue
        for pr in js["meshes"][nd["mesh"]]["primitives"]:
            mat = js["materials"][pr["material"]]["name"]
            P = acc(pr["attributes"]["POSITION"]); N = acc(pr["attributes"]["NORMAL"]); I = acc(pr["indices"]).ravel().reshape(-1, 3)
            C = acc(pr["attributes"]["COLOR_0"])[:, :3].astype(np.float32) / 255.0
            up = N[I[:, 0], 1] > 0.35   # só o que olha pra cima (telhado/laje)
            I = I[up]
            if len(I) == 0: continue
            col = (C[I[:, 0]] ** (1 / 2.2)) * np.array(TEXCOL.get(mat, (230, 230, 230)))
            ymax = P[I].max(1)[:, 1]
            tris_all.append((P[I][:, :, [0, 2]], col, ymax))
T = np.concatenate([t[0] for t in tris_all]); C = np.concatenate([t[1] for t in tris_all]); Y = np.concatenate([t[2] for t in tris_all])
ordem = np.argsort(Y)
px = np.round((T - [X0, Z0]) * k * SS * 4).astype(np.int32)
for i in ordem:
    c = C[i]
    cv2.fillConvexPoly(big, px[i], (float(c[2]), float(c[1]), float(c[0])), cv2.LINE_8, 2)
out = cv2.resize(big, (mini.shape[1], mini.shape[0]), interpolation=cv2.INTER_AREA)
cv2.imwrite(f"{D}/minimapa.png", out)
print("telhados:", len(T))
