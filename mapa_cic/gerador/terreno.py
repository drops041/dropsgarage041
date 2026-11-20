"""Terreno real a partir das curvas de nível do IPPUC (1 em 1 m)."""
import pickle, math
import numpy as np, cv2
from scipy.interpolate import griddata
from scipy.ndimage import gaussian_filter, distance_transform_edt


class Terreno:
    def __init__(self, curvas_pkl, x0, z0, largura, altura, res=2.0, desloc=(0.0, 0.0)):
        self.x0, self.z0, self.res = x0, z0, res
        self.nx, self.nz = int(math.ceil(largura / res)) + 1, int(math.ceil(altura / res)) + 1
        curvas = pickle.load(open(curvas_pkl, "rb"))
        pts, vals = [], []
        for P, e in curvas:
            P = np.asarray(P, np.float64) + np.asarray(desloc)
            # reamostra a cada ~3 m
            seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
            cum = np.concatenate([[0], np.cumsum(seg)])
            s = np.arange(0, cum[-1] + 0.01, 3.0)
            xs = np.interp(s, cum, P[:, 0]); zs = np.interp(s, cum, P[:, 1])
            pts.append(np.stack([xs, zs], 1)); vals.append(np.full(len(s), e))
        pts = np.concatenate(pts); vals = np.concatenate(vals)
        gx = x0 + np.arange(self.nx) * res; gz = z0 + np.arange(self.nz) * res
        GX, GZ = np.meshgrid(gx, gz)
        H = griddata(pts, vals, (GX, GZ), method="linear")
        nan = np.isnan(H)
        if nan.any():   # fora das curvas: valor do vizinho mais próximo
            idx = distance_transform_edt(nan, return_distances=False, return_indices=True)
            H = H[tuple(idx)]
        H = gaussian_filter(H, 1.6)     # ~3 m: tira os degraus entre curvas
        self.base = float(np.floor(H.min()))
        self.H = (H - self.base).astype(np.float32)
        print(f"terreno: {self.base:.0f} a {H.max():.0f} m ({self.nx}x{self.nz})")

    # ---------------------------------------------------------------
    def alt(self, x, z):
        """altura (y do jogo) em x,z — aceita escalar ou array"""
        fx = (np.asarray(x, np.float64) - self.x0) / self.res
        fz = (np.asarray(z, np.float64) - self.z0) / self.res
        fx = np.clip(fx, 0, self.nx - 1.001); fz = np.clip(fz, 0, self.nz - 1.001)
        ix = fx.astype(int); iz = fz.astype(int); tx = fx - ix; tz = fz - iz
        H = self.H
        v = (H[iz, ix] * (1 - tx) * (1 - tz) + H[iz, ix + 1] * tx * (1 - tz) +
             H[iz + 1, ix] * (1 - tx) * tz + H[iz + 1, ix + 1] * tx * tz)
        return float(v) if np.ndim(v) == 0 else v

    def _px(self, pts):
        return np.round((np.asarray(pts) - [self.x0, self.z0]) / self.res * 16).astype(np.int32)

    def aplainar(self, poligono, borda=8.0, nivel=None):
        """deixa o terreno plano dentro do polígono (com rampa suave na borda)"""
        m = np.zeros(self.H.shape, np.uint8)
        cv2.fillPoly(m, [self._px(poligono)], 1, cv2.LINE_8, 4)
        if not m.any():
            return 0.0
        if nivel is None:
            nivel = float(np.median(self.H[m > 0]))
        d = distance_transform_edt(m == 0) * self.res
        w = np.clip(1 - d / borda, 0, 1)
        w = w * w * (3 - 2 * w)
        self.H = (self.H * (1 - w) + nivel * w).astype(np.float32)
        return nivel

    def ruas(self, ruas, ordem):
        """pista sem inclinação de lado: cada trecho da rua usa a altura do eixo"""
        V = np.zeros(self.H.shape, np.float32); M = np.zeros(self.H.shape, np.float32)
        Hs = gaussian_filter(self.H, 3.0)
        for r in sorted(ruas, key=ordem):
            P = r["pts"]; w = r["w"] + 2 * r["sw"] + 2.0
            seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
            cum = np.concatenate([[0], np.cumsum(seg)])
            s = np.arange(0, cum[-1] + 0.01, 3.0)
            if len(s) < 2: s = np.array([0, cum[-1]])
            xs = np.interp(s, cum, P[:, 0]); zs = np.interp(s, cum, P[:, 1])
            fx = np.clip((xs - self.x0) / self.res, 0, self.nx - 1).astype(int)
            fz = np.clip((zs - self.z0) / self.res, 0, self.nz - 1).astype(int)
            hs = Hs[fz, fx]
            # suaviza a altura ao longo da rua
            if len(hs) > 5:
                k = np.ones(5) / 5
                hs = np.convolve(np.pad(hs, 2, mode="edge"), k, mode="valid")
            for k in range(len(s) - 1):
                a = self._px([[xs[k], zs[k]]])[0]; b = self._px([[xs[k + 1], zs[k + 1]]])[0]
                th = max(1, int(round(w / self.res)))
                tmp = np.zeros((1, 1))
                cv2.line(V, tuple(map(int, a)), tuple(map(int, b)), float((hs[k] + hs[k + 1]) / 2), th, cv2.LINE_8, 4)
                cv2.line(M, tuple(map(int, a)), tuple(map(int, b)), 1.0, th, cv2.LINE_8, 4)
        Mb = cv2.GaussianBlur(M, (0, 0), 2.0)
        Vb = cv2.GaussianBlur(V, (0, 0), 2.0) / np.maximum(Mb, 1e-3)
        w = np.clip(Mb * 1.4, 0, 1)
        self.H = (self.H * (1 - w) + Vb * w).astype(np.float32)

    def salvar(self, path):
        self.H.astype("<f4").tofile(path)
