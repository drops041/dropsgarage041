class_name Policia
extends Node3D
## Polícia na rua: policiais na delegacia e no posto (com viatura), viaturas patrulhando no trânsito
## e algumas blitz pela CIC (marcadas com "B" no mapa).

const ARQ_POLICIAL := "res://modelos/personagens/soldado.glb"
const CARRO_VIATURA := "golg5"     # viatura da patrulha (Gol: leve pro celular)
const N_BLITZ := 3

var m                     # main.gd
var blitz: Array[Vector3] = []          # centro de cada blitz (pro mapa)
var _blitz_dir: Array[Vector3] = []
var _avisada := {}
var _andantes: Array = []               # [nó, a, b, t, indo, pausa, ap]
var _giroflex: Array = []               # [mat_vermelho, mat_azul, fase]
var _t := 0.0


func montar(main_ref) -> void:
	m = main_ref
	_delegacia()
	_posto()
	_blitz()


# ---------------------------------------------------------------- gente
func policial(pos: Vector3, giro: float, patrulha_ate := Vector3.INF) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = _no_chao(pos)
	n.rotation.y = giro
	var mod := Pessoa.criar(ARQ_POLICIAL, 1.8)
	n.add_child(mod)
	var ap := mod.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap and ap.has_animation("drops/parado"):
		ap.play("drops/parado")
		ap.seek(randf() * 2.0, true)
	for gi in n.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = 120.0
	if patrulha_ate != Vector3.INF:
		_andantes.append([n, n.global_position, _no_chao(patrulha_ate), 0.0, true, randf() * 3.0, ap])
	return n


func _no_chao(p: Vector3) -> Vector3:
	if m and m.mapa:
		return Vector3(p.x, m.mapa.altura(p.x, p.z), p.z)
	return p


# ---------------------------------------------------------------- viatura (carro do jogo com giroflex e adesivo)
func viatura(pos: Vector3, giro: float, parada := true) -> CarroVisual:
	var i := 0
	for k in Dados.carros.size():
		if Dados.carros[k]["id"] == CARRO_VIATURA:
			i = k
	var cv := CarroVisual.new()
	add_child(cv)
	cv.montar(Dados.carros[i], cfg_viatura(Dados.carros[i]), true)
	vestir(cv)
	cv.global_position = _no_chao(pos)
	cv.rotation.y = giro
	cv.alcance(160.0)
	if parada:
		var corpo := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(cv.d["W"]), 1.3, cv.comprimento)
		col.shape = box
		col.position = Vector3(0, 0.7, (cv.frente_z + cv.tras_z) / 2.0)
		corpo.add_child(col)
		cv.add_child(corpo)
	return cv


static func cfg_viatura(d: Dictionary) -> Dictionary:
	var c: Dictionary = (d["padrao"] as Dictionary).duplicate()
	c.merge({"cor": "#f3f4f6", "acabamento": "brilho", "roda": "vwrim", "aro": 15, "tala": 6, "flanco": 9.5, "cor_roda": "#2a2c30",
		"borda": "pintada", "camber": 0, "neon": "off", "som": "off", "rebaixo": 0, "rebaixo_tras": 0, "placa": "PMPR190"}, true)
	return c


## adesivo POLÍCIA nas portas, faixa azul e giroflex no teto
func vestir(cv: CarroVisual) -> void:
	var W := float(cv.d["W"])
	var f := Acessorios.forma(cv)
	var teto: float = f["teto"]
	# onde o teto é teto
	var za := INF
	var zb := -INF
	var z := float(f["z0"])
	while z < float(f["z1"]):
		if Acessorios.altura(f, z) > teto - 0.05:
			za = minf(za, z)
			zb = maxf(zb, z)
		z += 0.05
	var zm := (za + zb) / 2.0 if za < INF else 0.0
	var base := Node3D.new()
	base.name = "giroflex"
	cv.corpo.add_child(base)
	base.position = Vector3(0, teto + 0.005, zm)
	var preto := StandardMaterial3D.new()
	preto.albedo_color = Color("16171a")
	preto.roughness = 0.4
	var caixa := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(minf(1.1, W * 0.66), 0.05, 0.26)
	caixa.mesh = bm
	caixa.material_override = preto
	caixa.position.y = 0.025
	base.add_child(caixa)
	var mv := StandardMaterial3D.new()
	mv.albedo_color = Color(0.5, 0.02, 0.03)
	mv.emission_enabled = true
	mv.emission = Color(1, 0.05, 0.05)
	mv.emission_energy_multiplier = 3.0
	var ma := StandardMaterial3D.new()
	ma.albedo_color = Color(0.02, 0.05, 0.5)
	ma.emission_enabled = true
	ma.emission = Color(0.1, 0.25, 1)
	ma.emission_energy_multiplier = 3.0
	for lado in [-1.0, 1.0]:
		var luz := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(bm.size.x * 0.46, 0.07, 0.22)
		luz.mesh = lm
		luz.material_override = mv if lado < 0 else ma
		luz.position = Vector3(lado * bm.size.x * 0.25, 0.085, 0)
		base.add_child(luz)
	_giroflex.append([mv, ma, randf() * 2.0])
	# adesivo e faixa nas laterais (na meia altura da porta)
	var y := float(cv.d["wy"]) + 0.42
	for lado in [-1.0, 1.0]:
		var x: float = (float(f["soleira"]) + 0.035) * lado
		var faixa := MeshInstance3D.new()
		var fm := QuadMesh.new()
		fm.size = Vector2(cv.comprimento * 0.62, 0.11)
		faixa.mesh = fm
		var azul := StandardMaterial3D.new()
		azul.albedo_color = Color("143a8c")
		azul.roughness = 0.35
		azul.cull_mode = BaseMaterial3D.CULL_DISABLED
		faixa.material_override = azul
		faixa.position = Vector3(x, y - 0.12, 0.0)
		faixa.rotation.y = PI / 2.0 * lado
		cv.corpo.add_child(faixa)
		var txt := Label3D.new()
		txt.text = "POLÍCIA"
		txt.font_size = 64
		txt.pixel_size = 0.0035
		txt.outline_size = 0
		txt.modulate = Color("0f2a6e")
		txt.position = Vector3(x + 0.004 * lado, y + 0.03, 0.1)
		txt.rotation.y = PI / 2.0 * lado
		cv.corpo.add_child(txt)


# ---------------------------------------------------------------- lugares
func _delegacia() -> void:
	if not m.mapa.tem("delegacia"):
		return
	var x: Transform3D = m.del_xf
	var giro: float = x.basis.get_euler().y
	policial(x * Vector3(-69.0, 0, -12.4), giro + 0.4)                             # do lado da viatura
	policial(x * Vector3(-64.5, 0, -9.0), giro + 0.2)   # na calçada (parado: o andar do modelo do soldado não ficou bom)


func _posto() -> void:
	if not m.mapa.tem("posto"):
		return
	var px: Transform3D = m.mapa.xf("posto")
	var giro: float = px.basis.get_euler().y
	viatura(px * Vector3(9.0, 0, 7.5), giro + PI / 2.0)
	policial(px * Vector3(7.0, 0, 9.6), giro + 0.3)
	policial(px * Vector3(8.4, 0, 10.4), giro - 0.5)


## blitz: sempre nos mesmos lugares (sorteio com semente fixa), longe da Drops e longe umas das outras
func _blitz() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 190
	var drops: Vector3 = m.mapa.drops_ponto(Vector3.ZERO)
	var tent := 0
	while blitz.size() < N_BLITZ and tent < 400:
		tent += 1
		var a := rng.randf() * TAU
		var dist := rng.randf_range(350.0, 1200.0)
		var p := Vector3(drops.x + cos(a) * dist, 0, drops.z + sin(a) * dist)
		var lim: Array = m.mapa.dados["limites"]
		if p.x < float(lim[0]) + 200.0 or p.x > float(lim[2]) - 200.0 or p.z < float(lim[1]) + 200.0 or p.z > float(lim[3]) - 200.0:
			continue   # dentro do mapa
		var mp: Dictionary = m.rede.mais_perto(p, 40.0)
		if mp.is_empty():
			continue
		var r: Dictionary = m.rede.ruas[mp["i"]]
		if not (str(r["tipo"]) in ["tertiary", "secondary", "primary", "residential"]) or float(r["L"]) < 80.0:
			continue
		var s := clampf(float(mp["s"]), 30.0, float(r["L"]) - 30.0)
		var c2: Vector2 = m.rede.ponto(mp["i"], s)
		var centro := Vector3(c2.x, 0, c2.y)
		var longe := true
		for b in blitz:
			if b.distance_to(centro) < 450.0:
				longe = false
		if not longe:
			continue
		var d2: Vector2 = m.rede.direcao(mp["i"], s)
		var dir := Vector3(d2.x, 0, d2.y).normalized()
		_montar_blitz(centro, dir, float(r["w"]))
		if OS.has_environment("DROPS_TESTE"):
			print("blitz ", centro)
		blitz.append(centro)
		_blitz_dir.append(dir)


func _montar_blitz(centro: Vector3, dir: Vector3, largura: float) -> void:
	var lado := Vector3(dir.z, 0, -dir.x)
	var meia := largura / 2.0
	var giro := atan2(dir.x, dir.z)
	# viatura parada no acostamento, cones afunilando a faixa e dois policiais
	viatura(centro + lado * (meia - 1.1) + dir * 4.0, giro)
	for k in 5:
		_cone(centro + lado * (meia - 0.4 - k * 0.45) - dir * (6.0 + k * 2.2))
	policial(centro + lado * (meia - 1.6) - dir * 1.5, giro + PI + 0.4)
	policial(centro + lado * (meia + 0.6) - dir * 3.0, giro + PI - 0.3)
	# placa BLITZ
	var placa := Label3D.new()
	placa.text = "BLITZ"
	placa.font_size = 96
	placa.pixel_size = 0.008
	placa.outline_size = 16
	placa.modulate = Color("ffd400")
	placa.outline_modulate = Color.BLACK
	placa.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	add_child(placa)
	placa.global_position = _no_chao(centro + lado * (meia + 0.3) - dir * 12.0) + Vector3.UP * 1.6
	placa.visibility_range_end = 140.0


static var _cone_malha: Mesh
static var _cone_mat: StandardMaterial3D
func _cone(p: Vector3) -> void:
	if _cone_malha == null:
		var c := CylinderMesh.new()
		c.top_radius = 0.03
		c.bottom_radius = 0.17
		c.height = 0.6
		c.radial_segments = 12
		c.rings = 1
		_cone_malha = c
		_cone_mat = StandardMaterial3D.new()
		_cone_mat.albedo_color = Color("ff5a12")
		_cone_mat.roughness = 0.5
	var mi := MeshInstance3D.new()
	mi.mesh = _cone_malha
	mi.material_override = _cone_mat
	add_child(mi)
	mi.global_position = _no_chao(p) + Vector3.UP * 0.3
	mi.visibility_range_end = 120.0


# ---------------------------------------------------------------- todo quadro
func _process(dt: float) -> void:
	_t += dt
	# giroflex piscando (vermelho e azul alternando, com duas piscadas rápidas)
	for g in _giroflex:
		var f := fmod(_t * 2.2 + float(g[2]), 2.0)
		var v := f < 1.0 and fmod(f, 0.5) < 0.3
		var a := f >= 1.0 and fmod(f - 1.0, 0.5) < 0.3
		(g[0] as StandardMaterial3D).emission_energy_multiplier = 4.0 if v else 0.15
		(g[1] as StandardMaterial3D).emission_energy_multiplier = 4.0 if a else 0.15
	# policiais que andam de um lado pro outro na calçada
	for a in _andantes:
		var n: Node3D = a[0]
		var ap: AnimationPlayer = a[6]
		if float(a[5]) > 0.0:
			a[5] = float(a[5]) - dt
			if ap and ap.current_animation != "drops/parado":
				ap.play("drops/parado", 0.3)
			continue
		var de: Vector3 = a[1] if a[4] else a[2]
		var ate: Vector3 = a[2] if a[4] else a[1]
		var dist := de.distance_to(ate)
		a[3] = float(a[3]) + dt * 1.25 / maxf(dist, 0.1)
		if float(a[3]) >= 1.0:
			a[3] = 0.0
			a[4] = not a[4]
			a[5] = 2.5 + randf() * 3.0
			continue
		n.global_position = _no_chao(de.lerp(ate, float(a[3])))
		var d := ate - de
		n.rotation.y = lerp_angle(n.rotation.y, atan2(d.x, d.z), 1.0 - exp(-dt * 6.0))
		if ap and ap.current_animation != "drops/anda":
			ap.play("drops/anda", 0.3)
	# chegou perto de uma blitz
	if m == null or m.carro == null:
		return
	var p: Vector3 = m.carro.global_position
	for i in blitz.size():
		var d := Vector2(p.x - blitz[i].x, p.z - blitz[i].z).length()
		if d < 45.0 and not _avisada.get(i, false):
			_avisada[i] = true
			m.toast("BLITZ! Maneira na velocidade, piá", 2.4)
		elif d > 90.0:
			_avisada[i] = false
