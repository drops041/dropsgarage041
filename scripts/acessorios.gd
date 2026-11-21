class_name Acessorios
extends RefCounted
## (20/11) DESLIGADO a pedido: o body kit estava feio. Fica sem até achar peças novas (aí é só pôr true).
const LIGADO := false
## Body kit e acessórios do carro, por ENCAIXE (slot). Cada encaixe tem opções; "off" = sem peça.
##
## Como cada peça é montada (na ordem):
##  1. modelo pronto do carro:   res://modelos/acessorios/<id do carro>/<encaixe>_<opção>.glb  (já na posição do carro)
##  2. modelo genérico:          res://modelos/acessorios/<encaixe>_<opção>.glb  (posicionado pelo encaixe)
##  3. peça gerada aqui mesmo, medindo a lataria do carro (funciona em qualquer carro, até nos importados)
## No carros.json dá pra acertar a posição de um encaixe:  "encaixes": {"kit_aerofolio": {"pos": [0, 0.05, -0.1], "escala": 1.1}}
## (pos soma na posição calculada; rot em graus).

## [chave, nome no menu, opções [valor, texto], só pra picape (true) / só pra carro (false) / todos (null)]
const ENCAIXES := [
	["kit_lip", "Lip dianteiro", [["off", "Sem"], ["preto", "Preto"], ["cor", "Da cor"], ["carbono", "Carbono"]], null],
	["kit_saias", "Saias laterais", [["off", "Sem"], ["cor", "Da cor"], ["preto", "Preto"], ["carbono", "Carbono"]], null],
	["kit_aerofolio", "Aerofólio", [["off", "Sem"], ["cor", "Da cor"], ["preto", "Preto"], ["carbono", "Carbono"]], false],
	["kit_santo", "Santo antônio", [["off", "Sem"], ["cromado", "Cromado"], ["preto", "Preto"]], true],
	["kit_capota", "Capota marítima (sem som na caçamba)", [["off", "Sem"], ["on", "Preta"]], true],
	["kit_rack", "Rack de teto", [["off", "Sem"], ["preto", "Preto"], ["cromado", "Cromado"]], null],
]

static var _forma := {}   # medidas da lataria por carro (calculadas uma vez)


static func encaixes_do(d: Dictionary) -> Array:
	var out := []
	for e in ENCAIXES:
		if e[3] == null or bool(e[3]) == bool(d.get("picape", false)):
			out.append(e)
	return out


## monta (ou remonta) todas as peças escolhidas embaixo de 'cv.corpo'
static func montar(cv: CarroVisual) -> void:
	var velho := cv.corpo.get_node_or_null("kit")
	if velho:
		velho.free()
	var algum := false
	for e in encaixes_do(cv.d):
		if str(cv.c.get(e[0], "off")) != "off":
			algum = true
	if not algum:
		return
	var kit := Node3D.new()
	kit.name = "kit"
	cv.corpo.add_child(kit)
	var f := forma(cv)
	for e in encaixes_do(cv.d):
		var op := str(cv.c.get(e[0], "off"))
		if op == "off":
			continue
		var peca := _peca(cv, f, e[0], op)
		if peca == null:
			continue
		var aj = cv.d.get("encaixes", {}).get(e[0])
		if aj is Dictionary:
			var p: Array = aj.get("pos", [0, 0, 0])
			peca.position += Vector3(p[0], p[1], p[2])
			var r: Array = aj.get("rot", [0, 0, 0])
			peca.rotation_degrees += Vector3(r[0], r[1], r[2])
			peca.scale *= float(aj.get("escala", 1.0))
		kit.add_child(peca)


# ---------------------------------------------------------------- medidas da lataria
## perfil de cima (altura máxima a cada 5 cm), bico de baixo do para-choque e largura da soleira
static func forma(cv: CarroVisual) -> Dictionary:
	var id := str(cv.d["id"])
	if _forma.has(id):
		return _forma[id]
	var z0 := cv.tras_z
	var z1 := cv.frente_z
	var nb := maxi(8, int((z1 - z0) / 0.05) + 1)
	var topo := PackedFloat32Array()
	topo.resize(nb)
	topo.fill(-10.0)
	var piso := cv.piso
	var frente_baixo := -INF
	var tras_baixo := INF
	var soleira := 0.0
	var axF := float(cv.d["axF"])
	var axR := float(cv.d["axR"])
	var ra := float(cv.d.get("ra", 0.33))
	var baixo := PackedVector3Array()   # pontos rentes ao chão (pra largura do para-choque)
	var fundo := PackedVector3Array()   # pontos da traseira (pra largura onde vai o aerofólio)
	for n in cv.modelo.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh == null or not m.visible:
			continue
		var t := _ate(m, cv.modelo)
		for s in m.mesh.get_surface_count():
			var vs: PackedVector3Array = m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			var passo := maxi(1, vs.size() / 20000)
			for i in range(0, vs.size(), passo):
				var p := t * vs[i]
				var b := clampi(int((p.z - z0) / 0.05), 0, nb - 1)
				if p.y > topo[b]:
					topo[b] = p.y
				if p.y < piso + 0.14:
					frente_baixo = maxf(frente_baixo, p.z)
					tras_baixo = minf(tras_baixo, p.z)
					baixo.append(p)
				if p.z < z0 + 1.8 and p.y > piso + 0.5:
					fundo.append(p)
				if p.y < piso + 0.3 and p.z < axF - ra - 0.05 and p.z > axR + ra + 0.05:
					soleira = maxf(soleira, absf(p.x))
	# buracos (fatias sem vértice) pegam a vizinha
	for i in nb:
		if topo[i] < -5.0:
			topo[i] = topo[i - 1] if i > 0 else piso + 1.0
	if soleira <= 0.0:
		soleira = float(cv.d["W"]) / 2.0 - 0.08
	var fb := frente_baixo if frente_baixo > -INF else z1
	var meia_frente := 0.0
	for p in baixo:
		if p.z > fb - 0.3:
			meia_frente = maxf(meia_frente, absf(p.x))
	if meia_frente <= 0.0:
		meia_frente = float(cv.d["W"]) / 2.0 - 0.1
	# tira pontas finas (antena, retrovisor) do perfil: abertura morfológica de 25 cm
	var er := PackedFloat32Array()
	er.resize(nb)
	for i in nb:
		var mn := INF
		for k in range(maxi(0, i - 2), mini(nb, i + 3)):
			mn = minf(mn, topo[k])
		er[i] = mn
	for i in nb:
		var mx := -INF
		for k in range(maxi(0, i - 2), mini(nb, i + 3)):
			mx = maxf(mx, er[k])
		topo[i] = mx
	var teto: float = Array(topo).max()
	# fim do teto (pra trás) e se tem porta-malas (patamar baixo atrás do vidro) = sedã; senão hatch/SUV
	var fim_teto := z1
	var i_fim := nb - 1
	for i in nb:
		if topo[i] > teto - 0.15:
			fim_teto = z0 + i * 0.05
			i_fim = i
			break
	var patamar := 0
	var melhor := 0
	for i in range(i_fim - 1, -1, -1):
		var plano := i > 0 and absf(topo[i] - topo[i - 1]) < 0.025 and topo[i] < teto - 0.25
		patamar = patamar + 1 if plano else 0
		melhor = maxi(melhor, patamar)
	var sedan := melhor * 0.05 >= 0.3
	var f := {"z0": z0, "z1": z1, "topo": topo, "piso": piso, "frente_baixo": fb, "meia_frente": meia_frente,
		"tras_baixo": tras_baixo, "soleira": soleira, "teto": teto, "fim_teto": fim_teto, "sedan": sedan, "fundo": fundo}
	_forma[id] = f
	return f


## meia largura da lataria perto de (z, y) — usa os pontos da traseira
static func meia_largura(f: Dictionary, z: float, y: float) -> float:
	var m := 0.0
	for p in (f["fundo"] as PackedVector3Array):
		if absf(p.z - z) < 0.12 and absf(p.y - y) < 0.12:
			m = maxf(m, absf(p.x))
	return m


static func altura(f: Dictionary, z: float) -> float:
	var topo: PackedFloat32Array = f["topo"]
	return topo[clampi(int((z - float(f["z0"])) / 0.05), 0, topo.size() - 1)]


static func _ate(n: Node3D, raiz: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var x: Node = n
	while x != null and x != raiz:
		if x is Node3D:
			t = (x as Node3D).transform * t
		x = x.get_parent()
	return t


# ---------------------------------------------------------------- peças
static func _peca(cv: CarroVisual, f: Dictionary, chave: String, op: String) -> Node3D:
	var id := str(cv.d["id"])
	for arq in ["res://modelos/acessorios/%s/%s_%s.glb" % [id, chave, op], "res://modelos/acessorios/%s_%s.glb" % [chave, op]]:
		if ResourceLoader.exists(arq):
			var n: Node3D = load(arq).instantiate()
			if arq.contains("/%s/" % id):
				return n   # modelo feito pra esse carro: já vem no lugar
			var raiz := Node3D.new()
			raiz.add_child(n)
			raiz.position = _ponto(cv, f, chave)
			return raiz
	var mat := _mat(cv, op)
	var W := float(cv.d["W"])
	var r := Node3D.new()
	r.name = chave
	match chave:
		"kit_lip":
			var fb: float = f["frente_baixo"]
			var lw: float = float(f["meia_frente"]) * 2.0 - 0.08
			r.add_child(_caixa(Vector3(lw - 0.06, 0.018, 0.16), Vector3(0, float(f["piso"]) + 0.012, fb - 0.11), mat))
		"kit_saias":
			var axF := float(cv.d["axF"])
			var axR := float(cv.d["axR"])
			var ra := float(cv.d.get("ra", 0.33))
			var z_a := axR + ra + 0.08
			var z_b := axF - ra - 0.08
			var x: float = f["soleira"] - 0.01
			for s in [-1.0, 1.0]:
				r.add_child(_caixa(Vector3(0.05, 0.11, z_b - z_a), Vector3(s * x, float(f["piso"]) + 0.07, (z_a + z_b) / 2.0), mat))
		"kit_aerofolio":
			var fim_teto: float = f["fim_teto"]
			if not bool(f["sedan"]):
				# hatch/SUV: aerofólio de teto, deitado no fim do teto, avançando por cima do vidro traseiro
				var z := fim_teto
				var y := altura(f, z + 0.08)
				var mw := meia_largura(f, z + 0.06, y - 0.04)
				var sw: float = clampf(mw * 2.0 - 0.1, 0.7, W - 0.35)
				var asa := MeshInstance3D.new()
				asa.mesh = _asa(sw, 0.3, 0.035)
				asa.material_override = mat
				asa.position = Vector3(0, y + 0.012, z - 0.06)
				asa.rotation.x = deg_to_rad(8.0)
				r.add_child(asa)
			else:
				# sedã/porta-malas: asa em cima da tampa, com dois pés
				var z := cv.tras_z + 0.2
				var y := altura(f, z)
				var mw := meia_largura(f, z, y - 0.05)
				var sw: float = clampf(mw * 2.0 - 0.15, 0.8, W - 0.25)
				var asa := MeshInstance3D.new()
				asa.mesh = _asa(sw, 0.3, 0.045)
				asa.material_override = mat
				asa.position = Vector3(0, y + 0.15, z)
				asa.rotation.x = deg_to_rad(-7.0)
				r.add_child(asa)
				for s in [-1.0, 1.0]:
					r.add_child(_caixa(Vector3(0.025, 0.16, 0.1), Vector3(s * (sw / 2.0 - 0.3), y + 0.07, z + 0.02), mat))
					r.add_child(_caixa(Vector3(0.012, 0.11, 0.34), Vector3(s * (sw / 2.0 - 0.006), y + 0.16, z), mat))
		"kit_santo":
			var tp = cv.d.get("tampa")
			var bed = cv.d.get("bed")
			var z1: float = float(tp["z1"]) if tp != null else float(bed["z"]) + 0.55
			var y0: float = float(tp["y"]) if tp != null else float(bed["y"]) + 0.25
			var xs := W / 2.0 - 0.16
			var zb := z1 - 0.12
			var h := 0.40
			var rt := 0.03
			var pts := [Vector3(-xs, y0, zb), Vector3(-xs + 0.05, y0 + h, zb - 0.06), Vector3(xs - 0.05, y0 + h, zb - 0.06), Vector3(xs, y0, zb)]
			for i in 3:
				r.add_child(_tubo(pts[i], pts[i + 1], rt, mat))
			for i in 4:
				r.add_child(_junta(pts[i], rt * 1.1, mat))
			# mãos-francesas pra trás
			for s in [-1.0, 1.0]:
				r.add_child(_tubo(Vector3(s * (xs - 0.04), y0 + h - 0.02, zb - 0.06), Vector3(s * xs, y0, zb - 0.62), rt * 0.85, mat))
				r.add_child(_junta(Vector3(s * xs, y0, zb - 0.62), rt, mat))
			# barra do meio
			r.add_child(_tubo(Vector3(-xs + 0.03, y0 + h * 0.55, zb - 0.035), Vector3(xs - 0.03, y0 + h * 0.55, zb - 0.035), rt * 0.75, mat))
		"kit_capota":
			var tp = cv.d.get("tampa")
			if tp == null or str(cv.c.get("som", "off")) != "off":
				return null   # com som na caçamba a capota fica guardada
			var z0 := float(tp["z0"])
			var z1 := float(tp["z1"])
			var lona := StandardMaterial3D.new()
			lona.albedo_color = Color("141416")
			lona.roughness = 0.62
			r.add_child(_caixa(Vector3(W - 0.2, 0.025, z1 - z0 - 0.04), Vector3(0, float(tp["y"]) + 0.012, (z0 + z1) / 2.0), lona))
			r.add_child(_caixa(Vector3(W - 0.16, 0.035, 0.03), Vector3(0, float(tp["y"]) + 0.01, z0 + 0.02), _mat(cv, "preto")))
		"kit_rack":
			var teto: float = f["teto"]
			# acha onde o teto é teto (até 6 cm abaixo do ponto mais alto)
			var za := INF
			var zb := -INF
			var z := float(f["z0"])
			while z < float(f["z1"]):
				if altura(f, z) > teto - 0.06:
					za = minf(za, z)
					zb = maxf(zb, z)
				z += 0.05
			var zm := (za + zb) / 2.0
			var meio := maxf(0.18, (zb - za) * 0.32)
			for dz in [-meio, meio]:
				r.add_child(_caixa(Vector3(W * 0.78, 0.03, 0.05), Vector3(0, teto + 0.075, zm + dz), mat))
				for s in [-1.0, 1.0]:
					r.add_child(_caixa(Vector3(0.05, 0.07, 0.07), Vector3(s * W * 0.36, teto + 0.03, zm + dz), _mat(cv, "preto")))
	return r


static func _ponto(cv: CarroVisual, f: Dictionary, chave: String) -> Vector3:
	match chave:
		"kit_lip": return Vector3(0, float(f["piso"]), float(f["frente_baixo"]))
		"kit_aerofolio": return Vector3(0, altura(f, cv.tras_z + 0.2), cv.tras_z + 0.2)
		"kit_rack": return Vector3(0, float(f["teto"]), 0)
		"kit_santo", "kit_capota":
			var tp = cv.d.get("tampa")
			return Vector3(0, float(tp["y"]), float(tp["z1"])) if tp != null else Vector3.ZERO
	return Vector3(0, float(f["piso"]), 0)


static var _carbono_tex: ImageTexture
static func _mat(cv: CarroVisual, op: String) -> Material:
	match op:
		"cor":
			return cv.mat_pintura
		"cromado":
			var m := ShaderMaterial.new()
			m.shader = load("res://scripts/shaders/cromo.gdshader")
			m.set_shader_parameter("reflexo", CarroVisual.reflexo)
			m.set_shader_parameter("forca_reflexo", CarroVisual.forca_reflexo)
			m.set_shader_parameter("aspereza", 0.04)
			return m
		"carbono":
			if _carbono_tex == null:
				var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
				for y in 64:
					for x in 64:
						var tw := ((x / 8 + y / 8) % 2 == 0)   # trama sarja
						var k := 0.11 if tw else 0.05
						k += 0.04 * sin(float(x if tw else y) * 0.8)
						img.set_pixel(x, y, Color(k, k, k * 1.08))
				img.generate_mipmaps()
				_carbono_tex = ImageTexture.create_from_image(img)
			var c := StandardMaterial3D.new()
			c.albedo_texture = _carbono_tex
			c.uv1_triplanar = true
			c.uv1_scale = Vector3(6, 6, 6)
			c.metallic = 0.35
			c.roughness = 0.22
			c.clearcoat_enabled = true
			c.clearcoat = 1.0
			return c
	var p := StandardMaterial3D.new()
	p.albedo_color = Color("101012")
	p.roughness = 0.45
	p.metallic = 0.1
	return p


static func _caixa(tam: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = tam
	m.mesh = b
	m.material_override = mat
	m.position = pos
	return m


static func _tubo(a: Vector3, b: Vector3, raio: float, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = raio
	c.bottom_radius = raio
	c.height = a.distance_to(b)
	c.radial_segments = 14
	c.rings = 1
	m.mesh = c
	m.material_override = mat
	var dir := (b - a).normalized()
	var eixo := Vector3.UP.cross(dir)
	var ang := acos(clampf(Vector3.UP.dot(dir), -1.0, 1.0))
	m.position = (a + b) / 2.0
	if eixo.length() > 1e-5:
		m.quaternion = Quaternion(eixo.normalized(), ang)
	elif dir.y < 0:
		m.rotation.x = PI
	return m


static func _junta(p: Vector3, raio: float, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = raio
	s.height = raio * 2.0
	s.radial_segments = 12
	s.rings = 6
	m.mesh = s
	m.material_override = mat
	m.position = p
	return m


## asa com perfil de aerofólio (corda c, espessura e) estendida no X, com as pontas fechadas
static func _asa(largura: float, c: float, e: float) -> ArrayMesh:
	var cima := PackedVector2Array()
	var baixo := PackedVector2Array()
	var n := 12
	for i in n + 1:
		var t := float(i) / n
		var zz := c * 0.5 - t * c                     # bordo de ataque na frente (+z), fuga atrás
		var esp := e * 5.0 * (0.2969 * sqrt(t) - 0.126 * t - 0.3516 * t * t + 0.2843 * t * t * t - 0.1015 * t * t * t * t)
		cima.append(Vector2(zz, esp * 0.75))
		baixo.append(Vector2(zz, -esp * 0.25))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := -largura / 2.0
	var x1 := largura / 2.0
	for lado in [cima, baixo]:
		for i in n:
			var a: Vector2 = lado[i]
			var b: Vector2 = lado[i + 1]
			var q := [Vector3(x0, a.y, a.x), Vector3(x1, a.y, a.x), Vector3(x1, b.y, b.x), Vector3(x0, b.y, b.x)]
			if lado == baixo:
				q.reverse()
			for k in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(q[k])
	# tampas das pontas
	for x in [x0, x1]:
		for i in n:
			var a: Vector2 = cima[i]
			var b: Vector2 = cima[i + 1]
			var c2: Vector2 = baixo[i + 1]
			var d2: Vector2 = baixo[i]
			var q := [Vector3(x, a.y, a.x), Vector3(x, b.y, b.x), Vector3(x, c2.y, c2.x), Vector3(x, d2.y, d2.x)]
			if x == x0:
				q.reverse()
			for k in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(q[k])
	st.generate_normals()
	return st.commit()
