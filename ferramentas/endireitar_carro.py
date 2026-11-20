#!/usr/bin/env python3
"""Endireita um carro que veio torto no modelo (girado no eixo vertical e/ou fora do centro).
Mede o ângulo pela lataria (PAINT) e gira a geometria inteira + as dobradiças (carros.json "partes").
uso: endireitar_carro.py id [--grau G] [--so-medir]
"""
import argparse, json, os, sys, copy
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from glb_io import GLB

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ap = argparse.ArgumentParser()
ap.add_argument('id')
ap.add_argument('--grau', type=float)
ap.add_argument('--so-medir', action='store_true')
a = ap.parse_args()
arq = os.path.join(R, 'modelos', 'carros', a.id + '.glb')
g = GLB(arq)
mats = g.j.get('materials', [])
pr = g.primitivas()
pint = [p for p in pr if p['mat'] is not None and mats[p['mat']].get('name', '').startswith('PAINT')]
P = np.vstack([p['pw'] for p in pint])
xz = P[:, [0, 2]] - P[:, [0, 2]].mean(0)
w, v = np.linalg.eigh(xz.T @ xz)
eixo = v[:, np.argmax(w)]            # direção do comprimento (x, z)
if eixo[1] < 0:
    eixo = -eixo
ang = np.degrees(np.arctan2(eixo[0], eixo[1]))
giro = -ang if a.grau is None else a.grau
c, s = np.cos(np.radians(giro)), np.sin(np.radians(giro))
Rg = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
Q = P @ Rg.T
meio = Q[np.abs(Q[:, 2] - np.median(Q[:, 2])) < 0.6]
dx = -(meio[:, 0].max() + meio[:, 0].min()) / 2.0
print('%s: torto %.2f° -> giro %.2f°, desloca x %.3f m' % (a.id, ang, giro, dx))
if a.so_medir:
    sys.exit()
T = np.eye(4)
T[:3, :3] = Rg
T[0, 3] = dx
usos = {}
for p in pr:
    usos.setdefault(p['malha'], set()).add(p['no'])
feitos = {}
for p in pr:
    no = g.j['nodes'][p['no']]
    mi = no['mesh']
    if len(usos[mi]) > 1 and (mi, p['no']) not in feitos:
        # malha usada por mais de um nó: cada nó ganha a sua cópia
        g.j['meshes'].append(copy.deepcopy(g.j['meshes'][mi]))
        no['mesh'] = len(g.j['meshes']) - 1
        usos[mi].discard(p['no'])
        usos[no['mesh']] = {p['no']}
    feitos[(mi, p['no'])] = True
    Wm = p['W']
    M = np.linalg.inv(Wm) @ T @ Wm          # local -> mundo -> gira -> volta pro local
    prim = g.j['meshes'][no['mesh']]['primitives'][p['k']]
    at = prim['attributes']
    pos = g.accessor(at['POSITION'])
    at['POSITION'] = g.add_accessor_vec3(pos @ M[:3, :3].T + M[:3, 3])
    L = M[:3, :3]
    for nm in ('NORMAL',):
        if nm in at:
            n = g.accessor(at[nm]) @ np.linalg.inv(L)
            n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
            at[nm] = g.add_accessor_vec3(n)
    if 'TANGENT' in at:
        t4 = g.accessor(at['TANGENT']).copy()
        t3 = t4[:, :3] @ L.T
        t4[:, :3] = t3 / np.maximum(np.linalg.norm(t3, axis=1, keepdims=True), 1e-9)
        arr = np.ascontiguousarray(t4, np.float32)
        vi = g.add_view(arr.tobytes(), 34962)
        g.j['accessors'].append({'bufferView': vi, 'componentType': 5126, 'count': len(arr), 'type': 'VEC4'})
        at['TANGENT'] = len(g.j['accessors']) - 1
g.salvar(arq)
cj = os.path.join(R, 'carros.json')
carros = json.load(open(cj, encoding='utf8'))
for cc in carros:
    if cc['id'] == a.id:
        for k, parte in cc.get('partes', {}).items():
            for e in parte['p']:
                pv = Rg @ np.array(e[1]) + np.array([dx, 0, 0])
                e[1] = [round(float(x), 3) for x in pv]
json.dump(carros, open(cj, 'w', encoding='utf8'), ensure_ascii=False, indent=1)
print('ok')
