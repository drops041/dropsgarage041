#!/usr/bin/env python3
"""Monta o protagonista a partir do Universal Base Characters (Quaternius, CC0).

O kit grátis vem só de roupa de baixo, então aqui as roupas são FEITAS em cima do próprio corpo:
pega os triângulos da região (tronco, coxa, pé...), alisa (some o tanquinho), afasta uns milímetros
da pele e mantém os mesmos pesos do esqueleto -> a roupa mexe junto, sem atravessar.
O corpo é cortado nas mesmas regiões; o jogo esconde o pedaço de pele que a roupa cobre.

uso: personagem_ual.py PASTA_DO_KIT saida.glb [--corpo Superhero_Male]
"""
import argparse, json, struct, io, os, sys
import numpy as np
from PIL import Image

CT = {5126: ('<f4', 4), 5123: ('<u2', 2), 5125: ('<u4', 4), 5121: ('u1', 1)}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


class Gltf:
    def __init__(self, caminho):
        self.dir = os.path.dirname(caminho)
        self.g = json.load(open(caminho))
        self.bin = open(os.path.join(self.dir, self.g['buffers'][0]['uri']), 'rb').read()

    def acc(self, i):
        a = self.g['accessors'][i]
        v = self.g['bufferViews'][a['bufferView']]
        dt, s = CT[a['componentType']]
        n = NC[a['type']]
        off = v.get('byteOffset', 0) + a.get('byteOffset', 0)
        st = v.get('byteStride', s * n)
        if st == s * n:
            arr = np.frombuffer(self.bin, dtype=dt, count=a['count'] * n, offset=off).reshape(a['count'], n)
        else:
            raw = np.frombuffer(self.bin, dtype='u1', count=a['count'] * st, offset=off).reshape(a['count'], st)
            arr = raw[:, :s * n].copy().view(dt).reshape(a['count'], n)
        arr = arr.astype(np.float32) if dt == '<f4' else arr.astype(np.int64)
        if a.get('normalized') and dt != '<f4':
            arr = arr / (255.0 if s == 1 else 65535.0)
        return arr

    def prim(self, mi):
        p = self.g['meshes'][mi]['primitives'][0]
        at = p['attributes']
        d = {k: self.acc(at[k]) for k in ('POSITION', 'NORMAL', 'TEXCOORD_0', 'JOINTS_0', 'WEIGHTS_0') if k in at}
        d['idx'] = self.acc(p['indices']).reshape(-1, 3)
        d['mat'] = p.get('material')
        return d

    def juntas(self):
        sk = self.g['skins'][0]
        return [self.g['nodes'][j]['name'] for j in sk['joints']]


class Saida:
    """glTF novo: esqueleto copiado do corpo + malhas novas, tudo num .glb"""
    def __init__(self, base: Gltf):
        g = base.g
        self.buf = bytearray()
        self.views, self.accs, self.meshes, self.mats, self.texs, self.imgs = [], [], [], [], [], []
        # nós: copia tudo que não é malha (esqueleto); as malhas novas entram como filhas do Armature
        self.nodes = []
        mapa = {}
        for i, n in enumerate(g['nodes']):
            if 'mesh' in n:
                continue
            mapa[i] = len(self.nodes)
            self.nodes.append({k: v for k, v in n.items() if k != 'children'})
        for i, n in enumerate(g['nodes']):
            if i in mapa and 'children' in n:
                ch = [mapa[c] for c in n['children'] if c in mapa]
                if ch:
                    self.nodes[mapa[i]]['children'] = ch
        self.armature = mapa[g['scenes'][0]['nodes'][0]]
        sk = g['skins'][0]
        ibm = base.acc(sk['inverseBindMatrices']).astype(np.float32)
        self.skin = {'joints': [mapa[j] for j in sk['joints']], 'inverseBindMatrices': self.acc_raw(ibm, 'MAT4')}
        if 'skeleton' in sk:
            self.skin['skeleton'] = mapa[sk['skeleton']]

    def view(self, data: bytes, target=None):
        while len(self.buf) % 4:
            self.buf.append(0)
        v = {'buffer': 0, 'byteOffset': len(self.buf), 'byteLength': len(data)}
        if target:
            v['target'] = target
        self.buf += data
        self.views.append(v)
        return len(self.views) - 1

    def acc_raw(self, arr, tipo, comp=5126, target=None, minmax=False):
        dt = {5126: '<f4', 5123: '<u2', 5125: '<u4', 5121: 'u1'}[comp]
        a = np.ascontiguousarray(arr.astype(dt))
        n = NC[tipo]
        cnt = a.size // n
        d = {'bufferView': self.view(a.tobytes(), target), 'componentType': comp, 'count': cnt, 'type': tipo}
        if minmax:
            r = a.reshape(cnt, n)
            d['min'] = r.min(0).tolist()
            d['max'] = r.max(0).tolist()
        self.accs.append(d)
        return len(self.accs) - 1

    def imagem(self, caminho, lado, qualidade=88, normal=False):
        im = Image.open(caminho).convert('RGB')
        if im.size[0] > lado:
            im = im.resize((lado, lado), Image.LANCZOS)
        b = io.BytesIO()
        im.save(b, 'JPEG', quality=qualidade)
        self.imgs.append({'bufferView': self.view(b.getvalue()), 'mimeType': 'image/jpeg'})
        self.texs.append({'source': len(self.imgs) - 1})
        return len(self.texs) - 1

    def material(self, nome, cor=(1, 1, 1, 1), tex=None, normal=None, rough=0.85, rough_tex=None, duplo=False):
        m = {'name': nome, 'pbrMetallicRoughness': {'baseColorFactor': list(cor), 'metallicFactor': 0.0, 'roughnessFactor': rough}}
        if tex is not None:
            m['pbrMetallicRoughness']['baseColorTexture'] = {'index': tex}
        if rough_tex is not None:
            m['pbrMetallicRoughness']['metallicRoughnessTexture'] = {'index': rough_tex}
            m['pbrMetallicRoughness']['roughnessFactor'] = 1.0
        if normal is not None:
            m['normalTexture'] = {'index': normal}
        if duplo:
            m['doubleSided'] = True
        self.mats.append(m)
        return len(self.mats) - 1

    def malha(self, nome, P, N, UV, J, W, idx, mat):
        if len(idx) == 0:
            return
        at = {
            'POSITION': self.acc_raw(P, 'VEC3', target=34962, minmax=True),
            'NORMAL': self.acc_raw(N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9), 'VEC3', target=34962),
            'TEXCOORD_0': self.acc_raw(UV, 'VEC2', target=34962),
            'JOINTS_0': self.acc_raw(J, 'VEC4', comp=5123, target=34962),
            'WEIGHTS_0': self.acc_raw(W / np.maximum(W.sum(1, keepdims=True), 1e-9), 'VEC4', target=34962),
        }
        ind = self.acc_raw(idx.reshape(-1), 'SCALAR', comp=5125, target=34963)
        self.meshes.append({'name': nome, 'primitives': [{'attributes': at, 'indices': ind, 'material': mat}]})
        self.nodes.append({'name': nome, 'mesh': len(self.meshes) - 1, 'skin': 0})
        self.nodes[self.armature].setdefault('children', []).append(len(self.nodes) - 1)

    def salvar(self, caminho):
        g = {'asset': {'version': '2.0', 'generator': 'drops personagem_ual.py'},
             'scene': 0, 'scenes': [{'nodes': [self.armature]}], 'nodes': self.nodes, 'skins': [self.skin],
             'meshes': self.meshes, 'materials': self.mats, 'textures': self.texs, 'images': self.imgs,
             'accessors': self.accs, 'bufferViews': self.views, 'buffers': [{'byteLength': len(self.buf)}]}
        js = json.dumps(g, separators=(',', ':')).encode()
        while len(js) % 4:
            js += b' '
        while len(self.buf) % 4:
            self.buf.append(0)
        tot = 12 + 8 + len(js) + 8 + len(self.buf)
        with open(caminho, 'wb') as f:
            f.write(struct.pack('<III', 0x46546C67, 2, tot))
            f.write(struct.pack('<II', len(js), 0x4E4F534A) + js)
            f.write(struct.pack('<II', len(self.buf), 0x004E4942) + bytes(self.buf))


# ---------------------------------------------------------------- regiões do corpo
def regioes(P, J, W, juntas, pos_osso):
    """região de cada vértice pelo osso que mais manda nele (+ corte ao longo do braço/canela)"""
    dom = J[np.arange(len(J)), W.argmax(1)]
    nomes = [juntas[d] for d in dom]
    r = []
    for i, n in enumerate(nomes):
        lado = n[-2:] if n[-2:] in ('_l', '_r') else ''
        if n in ('Head', 'neck_01'):
            r.append('cabeca')
        elif n.startswith('spine') or n.startswith('clavicle'):
            r.append('tronco')
        elif n in ('pelvis', 'root'):
            r.append('quadril')
        elif n.startswith('upperarm'):
            a, b = pos_osso['upperarm' + lado], pos_osso['lowerarm' + lado]
            t = np.dot(P[i] - a, b - a) / np.dot(b - a, b - a)
            r.append('ombro' if t < 0.42 else 'braco')
        elif n.startswith('thigh'):
            r.append('coxa')
        elif n.startswith('calf'):
            a, b = pos_osso['calf' + lado], pos_osso['foot' + lado]
            t = np.dot(P[i] - a, b - a) / np.dot(b - a, b - a)
            r.append('joelho' if t < 0.16 else ('canela' if t < 0.86 else 'tornozelo'))
        elif n.startswith('foot') or n.startswith('ball'):
            r.append('pe')
        else:
            r.append('mao')   # antebraço, mão e dedos
    return np.array(r)


def regiao_tri(rv, idx):
    a, b, c = rv[idx[:, 0]], rv[idx[:, 1]], rv[idx[:, 2]]
    return np.where(b == c, b, a)   # maioria (se os 3 forem diferentes, fica o primeiro)


# ---------------------------------------------------------------- roupa: casca alisada em cima do corpo
def casca(P, N, UV, J, W, idx, sel, afasta, alisa, puxa_fora=1.0, chao=None, folga=None):
    """sel: máscara dos triângulos. Devolve P,N,UV,J,W,idx da roupa (com a "barra" que fecha até a pele)"""
    tri = idx[sel]
    usados = np.unique(tri)
    novo = -np.ones(len(P), np.int64)
    novo[usados] = np.arange(len(usados))
    t = novo[tri]
    p0 = P[usados].astype(np.float64)
    n0 = N[usados].astype(np.float64)
    n0 /= np.maximum(np.linalg.norm(n0, axis=1, keepdims=True), 1e-9)
    # solda os vértices repetidos (costura de UV) pra alisar sem rasgar
    chave = np.round(p0 / 1e-5).astype(np.int64)
    _, sold, inv = np.unique(chave, axis=0, return_index=True, return_inverse=True)
    inv = inv.reshape(-1)
    ns = len(sold)
    ts = inv[t]
    # borda: aresta usada por um triângulo só
    ar = np.sort(np.concatenate([ts[:, [0, 1]], ts[:, [1, 2]], ts[:, [2, 0]]]), axis=1)
    u, cnt = np.unique(ar, axis=0, return_counts=True)
    borda_ar = u[cnt == 1]
    borda = np.zeros(ns, bool)
    borda[borda_ar.reshape(-1)] = True
    # vizinhos
    viz = [[] for _ in range(ns)]
    for a, b in u:
        viz[a].append(b)
        viz[b].append(a)
    ps = np.zeros((ns, 3))
    nsol = np.zeros((ns, 3))
    np.add.at(ps, inv, p0)
    np.add.at(nsol, inv, n0)
    cont = np.bincount(inv, minlength=ns)[:, None]
    ps /= cont
    nsol /= np.maximum(np.linalg.norm(nsol, axis=1, keepdims=True), 1e-9)
    orig = ps.copy()
    # distância (em anéis) até a borda: perto da borda a roupa encosta na pele aos poucos
    anel = np.full(ns, 99)
    anel[borda] = 0
    frente = list(np.nonzero(borda)[0])
    k = 0
    while frente and k < 4:
        k += 1
        prox = []
        for a in frente:
            for b in viz[a]:
                if anel[b] > k:
                    anel[b] = k
                    prox.append(b)
        frente = prox
    # bordas retas: cada borda (manga, gola, barra) vira um anel plano, puxado pro lado de FORA da roupa
    # (cobre o serrilhado dos triângulos em vez de abrir buraco)
    pai = list(range(ns))
    def raiz(x):
        while pai[x] != x:
            pai[x] = pai[pai[x]]
            x = pai[x]
        return x
    for a2, b2 in borda_ar:
        pai[raiz(a2)] = raiz(b2)
    grupos = {}
    for v in np.nonzero(borda)[0]:
        grupos.setdefault(raiz(v), []).append(v)
    dentro = ps[~borda].mean(0) if (~borda).any() else ps.mean(0)
    for lp in grupos.values():
        if len(lp) < 6:
            continue
        pts = ps[lp]
        c = pts.mean(0)
        n = np.linalg.svd(pts - c)[2][-1]
        if np.dot(dentro - c, n) > 0:
            n = -n
        s = (pts - c) @ n
        mover = np.clip(s.max() - s, 0.0, 0.06)
        ps[lp] += n[None, :] * mover[:, None]
    for _ in range(alisa):
        media = np.array([ps[v].mean(0) if v else ps[i] for i, v in enumerate(viz)])
        ps = np.where(borda[:, None], ps, ps + 0.6 * (media - ps))
        # nunca entra na pele: o que afundou volta pra fora (enche o vão do tanquinho)
        d = ((ps - orig) * nsol).sum(1)
        ps -= nsol * np.minimum(d, 0.0)[:, None] * puxa_fora
    if folga is not None:
        ps = folga(ps)
    ps += nsol * afasta
    if chao is not None:
        ps[:, 1] = np.maximum(ps[:, 1], chao)
    # normais novas (da superfície alisada)
    tri_p = ps[ts]
    fn = np.cross(tri_p[:, 1] - tri_p[:, 0], tri_p[:, 2] - tri_p[:, 0])
    nn = np.zeros((ns, 3))
    for c in range(3):
        np.add.at(nn, ts[:, c], fn)
    nn /= np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-9)
    Pr, Nr = ps[inv], nn[inv]
    UVr, Jr, Wr = UV[usados], J[usados], W[usados]
    out_idx = t.copy()
    # barra: liga a borda da roupa até a pele (sem buraco na manga, na gola e na barra da calça)
    extraP, extraN, extraUV, extraJ, extraW, extraI = [], [], [], [], [], []
    base = len(Pr)
    rep = {}
    for i_loc, s in enumerate(inv):
        rep.setdefault(s, i_loc)
    direto = set()
    for tr in ts:
        direto.update(((tr[0], tr[1]), (tr[1], tr[2]), (tr[2], tr[0])))
    for a, b in borda_ar:
        # orientação da aresta como aparece no triângulo (pra barra virar pro lado certo)
        if (a, b) not in direto:
            a, b = b, a
        ia, ib = rep[a], rep[b]
        pa_in = orig[a] - nsol[a] * 0.002
        pb_in = orig[b] - nsol[b] * 0.002
        q = [Pr[ia], Pr[ib], pb_in, pa_in]
        fnq = np.cross(q[1] - q[0], q[3] - q[0])
        for k2, (pp, src) in enumerate(zip(q, [ia, ib, ib, ia])):
            extraP.append(pp)
            extraN.append(fnq)
            extraUV.append(UVr[src])
            extraJ.append(Jr[src])
            extraW.append(Wr[src])
        o = base + len(extraP) - 4
        extraI += [[o, o + 2, o + 1], [o, o + 3, o + 2]]
    if extraP:
        Pr = np.vstack([Pr, extraP])
        Nr = np.vstack([Nr, extraN])
        UVr = np.vstack([UVr, extraUV])
        Jr = np.vstack([Jr, extraJ])
        Wr = np.vstack([Wr, extraW])
        out_idx = np.vstack([out_idx, np.array(extraI)])
    return Pr.astype(np.float32), Nr.astype(np.float32), UVr.astype(np.float32), Jr, Wr.astype(np.float32), out_idx


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('kit')
    ap.add_argument('saida')
    ap.add_argument('--corpo', default='Superhero_Male')
    a = ap.parse_args()
    kit = a.kit
    base = Gltf(os.path.join(kit, 'Base Characters', 'Godot - UE', a.corpo + '_FullBody.gltf'))
    juntas = base.juntas()
    ibm = base.acc(base.g['skins'][0]['inverseBindMatrices']).reshape(-1, 4, 4)
    pos_osso = {n: np.linalg.inv(ibm[k].T)[:3, 3] for k, n in enumerate(juntas)}
    out = Saida(base)
    tex = os.path.join(kit, 'Base Characters', 'Textures')
    tex_cab = os.path.join(kit, 'Hairstyles', 'Textures')
    nome_tex = 'T_Superhero_Male_Ligh.png' if 'Male' in a.corpo else 'T_Superhero_Female_Light_BaseColor.png'
    t_pele = out.imagem(os.path.join(tex, nome_tex), 1024)
    t_pele_n = out.imagem(os.path.join(tex, nome_tex.replace('Ligh.png', 'Normal.png').replace('Light_BaseColor', 'Normal')), 1024)
    t_pele_r = out.imagem(os.path.join(tex, nome_tex.replace('Ligh.png', 'Roughness.png').replace('Light_BaseColor', 'Roughness')), 512)
    m_pele = out.material('Pele', tex=t_pele, normal=t_pele_n, rough_tex=t_pele_r)
    t_cab1 = out.imagem(os.path.join(tex_cab, 'T_Hair_1_BaseColor.png'), 1024)
    t_cab1n = out.imagem(os.path.join(tex_cab, 'Normals Unity - Godot', 'T_Hair_1_Normal.png'), 1024)
    t_cab2 = out.imagem(os.path.join(tex_cab, 'T_Hair_2_BaseColor.png'), 1024)
    t_cab2n = out.imagem(os.path.join(tex_cab, 'Normals Unity - Godot', 'T_Hair_2_Normal.png'), 1024)
    m_cab = {1: out.material('Cabelo', tex=t_cab1, normal=t_cab1n, rough=0.8, duplo=True),
             2: out.material('Cabelo2', tex=t_cab2, normal=t_cab2n, rough=0.8, duplo=True)}
    eye = os.path.join(kit, 'Base Characters', 'Godot - UE', 'T_Eye_Brown.png')
    m_olho = out.material('Olhos', tex=out.imagem(eye, 256), rough=0.3)
    m_camiseta = out.material('Camiseta', cor=(0.08, 0.08, 0.09, 1), rough=0.9)
    m_calca = out.material('Calca', cor=(0.16, 0.22, 0.36, 1), rough=0.88)
    m_bermuda = out.material('Bermuda', cor=(0.23, 0.24, 0.20, 1), rough=0.9)
    m_tenis = out.material('Tenis', cor=(0.93, 0.93, 0.92, 1), rough=0.65)
    m_sola = out.material('Sola', cor=(0.12, 0.12, 0.13, 1), rough=0.7)

    # malhas do corpo (olhos, sobrancelha que já vem nele, corpo)
    corpo = None
    for mi, m in enumerate(base.g['meshes']):
        d = base.prim(mi)
        nm = base.g['materials'][d['mat']]['name']
        if 'Eye' in nm:
            out.malha('olhos', d['POSITION'], d['NORMAL'], d['TEXCOORD_0'], d['JOINTS_0'], d['WEIGHTS_0'], d['idx'], m_olho)
        elif 'Hair' in nm:
            out.malha('sobrancelha', d['POSITION'], d['NORMAL'], d['TEXCOORD_0'], d['JOINTS_0'], d['WEIGHTS_0'], d['idx'], m_cab[1])
        else:
            corpo = d
    P, N, UV, J, W, idx = corpo['POSITION'], corpo['NORMAL'], corpo['TEXCOORD_0'], corpo['JOINTS_0'], corpo['WEIGHTS_0'], corpo['idx']
    rv = regioes(P, J, W, juntas, pos_osso)
    rt = regiao_tri(rv, idx)
    cy = P[idx].mean(1)[:, 1]
    for r in sorted(set(rt)):
        out.malha('corpo_' + r, P, N, UV, J, W, idx[rt == r], m_pele)
    print({r: int((rt == r).sum()) for r in sorted(set(rt))})

    def roupa(nome, sel, mat, **kw):
        out.malha('roupa_' + nome, *casca(P, N, UV, J, W, idx, sel, **kw), mat)

    em = lambda *rs: np.isin(rt, rs)
    # camiseta: tronco + começo do braço + desce um pouco por cima da cintura da calça
    BARRA = 0.93   # altura (em pé) onde termina a camiseta, por cima da cintura da calça
    tronco = em('tronco', 'quadril', 'coxa') & (cy > BARRA)
    roupa('camiseta', tronco | em('ombro'), m_camiseta, afasta=0.026, alisa=22)
    roupa('regata', tronco, m_camiseta, afasta=0.024, alisa=22)

    # perna de calça reta (jeans/bermuda): nada fica mais fino que a "boca" da perna
    def perna_reta(ps):
        ps = ps.copy()
        for lado, sx in (('_l', 1), ('_r', -1)):
            cadeia = [pos_osso['thigh' + lado], pos_osso['calf' + lado], pos_osso['foot' + lado]]
            raios = [0.092, 0.074, 0.066]
            m = (np.sign(ps[:, 0]) == sx) & (ps[:, 1] < 0.86)
            for i in np.nonzero(m)[0]:
                p = ps[i]
                melhor = None
                for k in range(2):
                    a2, b2 = cadeia[k], cadeia[k + 1]
                    u = np.clip(np.dot(p - a2, b2 - a2) / np.dot(b2 - a2, b2 - a2), 0, 1)
                    q = a2 + u * (b2 - a2)
                    d = np.linalg.norm(p - q)
                    if melhor is None or d < melhor[0]:
                        melhor = (d, q, raios[k] + u * (raios[k + 1] - raios[k]))
                d, q, rmin = melhor
                if 1e-6 < d < rmin:
                    ps[i] = q + (p - q) * (rmin / d)
        return ps
    roupa('calca', em('quadril', 'coxa', 'joelho', 'canela'), m_calca, afasta=0.014, alisa=30, folga=perna_reta)
    roupa('bermuda', em('quadril', 'coxa', 'joelho'), m_bermuda, afasta=0.016, alisa=30, folga=perna_reta)
    # tênis: pé + tornozelo, bem alisado (some os dedos); sola embaixo
    pe = em('pe', 'tornozelo')
    tri_p = P[idx]
    fny = np.cross(tri_p[:, 1] - tri_p[:, 0], tri_p[:, 2] - tri_p[:, 0])
    fny = fny[:, 1] / np.maximum(np.linalg.norm(fny, axis=1), 1e-12)
    sola = pe & (cy < 0.03) & (fny < -0.2)
    roupa('tenis', pe & ~sola, m_tenis, afasta=0.02, alisa=18)
    roupa('sola', sola, m_sola, afasta=0.02, alisa=18, chao=-0.012)

    # cabelos e barba (já vêm presos no osso da cabeça, mesmo esqueleto)
    pasta_cab = os.path.join(kit, 'Hairstyles', 'Rigged to Head Bone', 'glTF (Godot -Unreal)')
    for arq, nome in [('Hair_Buzzed', 'cabelo_raspado'), ('Hair_SimpleParted', 'cabelo_social'), ('Hair_Long', 'cabelo_comprido'),
                      ('Hair_Beard', 'barba')]:
        h = Gltf(os.path.join(pasta_cab, arq + '.gltf'))
        jh = h.juntas()
        remap = np.array([juntas.index(n) for n in jh])
        d = h.prim(0)
        qual = 2 if 'Hair_2' in h.g['materials'][d['mat']]['name'] else 1
        out.malha(nome, d['POSITION'], d['NORMAL'], d['TEXCOORD_0'], remap[d['JOINTS_0']], d['WEIGHTS_0'], d['idx'], m_cab[qual])
    out.salvar(a.saida)
    print('ok', a.saida, os.path.getsize(a.saida) // 1024, 'KB')


if __name__ == '__main__':
    main()
