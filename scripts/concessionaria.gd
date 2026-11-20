class_name Concessionaria
extends Node
## (v37) Concessionária DROPS CAR, feita aqui no jogo (no lugar do modelo antigo, que vinha bugado e com
## logos de montadoras). Prédio com fachada de vidro, letreiro DROPS CAR na faixa da fachada (letras
## amarelas acesas), salão com piso claro brilhante e carros em exposição, pátio na frente com 2 carros.
## Coordenadas locais: origem no meio da frente do prédio; +Z = pátio/rua (0..7), o prédio vai de z 0 a -18.

const LARG := 30.0
const FUNDO := 16.0
const ALT := 6.0
const CAMADA_DENTRO := 2
const AMARELO := Color("ffd400")

var m: Node
var xf := Transform3D.IDENTITY
var _mats := {}


func _ready() -> void:
	if not m.mapa.tem("concessionaria"):
		return
	xf = m.mapa.xf("concessionaria")
	_predio()
	_carros()


func _mat(nome: String, cor: Color, rug := 0.85, metal := 0.0, emis := 0.0) -> StandardMaterial3D:
	if _mats.has(nome):
		return _mats[nome]
	var s := StandardMaterial3D.new()
	s.albedo_color = cor
	s.roughness = rug
	s.metallic = metal
	if cor.a < 1.0:
		s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		s.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emis > 0.0:
		s.emission_enabled = true
		s.emission = Color(cor.r, cor.g, cor.b)
		s.emission_energy_multiplier = emis
	_mats[nome] = s
	return s


func _caixa(pos: Vector3, tam: Vector3, mat: Material, dentro := false, colide := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = tam
	mi.mesh = bm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if (dentro or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED) else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if dentro:
		mi.layers = 1 << (CAMADA_DENTRO - 1)
	mi.visibility_range_end = 300.0
	add_child(mi)
	mi.global_transform = xf * Transform3D(Basis(), pos)
	if colide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = tam
		cs.shape = bx
		sb.add_child(cs)
		add_child(sb)
		sb.global_transform = mi.global_transform
	return mi


func _predio() -> void:
	var branco := _mat("branco", Color(0.93, 0.93, 0.92), 0.6)
	var grafite := _mat("grafite", Color(0.1, 0.1, 0.11), 0.45, 0.3)
	var vidro := _mat("vidro", Color(0.55, 0.7, 0.8, 0.28), 0.05, 0.2)
	var caixilho := _mat("caixilho", Color(0.08, 0.08, 0.09), 0.4, 0.6)
	var piso := _mat("piso", Color(0.82, 0.82, 0.83), 0.12, 0.0)
	var luz := _mat("luz", Color(1, 0.98, 0.92), 0.3, 0.0, 3.0)
	var parede_in := _mat("parede_in", Color(0.85, 0.85, 0.86), 0.8)
	var hx := LARG / 2.0
	var zc := -FUNDO / 2.0
	# piso do salão e calçada do pátio
	_caixa(Vector3(0, -0.15, zc), Vector3(LARG, 0.36, FUNDO), piso, true, true)
	_caixa(Vector3(0, -0.2, 3.5), Vector3(LARG + 4.0, 0.42, 7.0), _mat("patio", Color(0.55, 0.55, 0.56), 0.85), false, true)
	# paredes: laterais e fundo brancas por fora, claras por dentro
	for s in [-1.0, 1.0]:
		_caixa(Vector3(s * (hx - 0.15), ALT / 2.0, zc), Vector3(0.3, ALT, FUNDO), branco, false, true)
		_caixa(Vector3(s * (hx - 0.32), ALT / 2.0, zc), Vector3(0.02, ALT, FUNDO - 0.4), parede_in, true)
	_caixa(Vector3(0, ALT / 2.0, -FUNDO + 0.15), Vector3(LARG, ALT, 0.3), branco, false, true)
	_caixa(Vector3(0, ALT / 2.0, -FUNDO + 0.32), Vector3(LARG - 0.6, ALT, 0.02), parede_in, true)
	# laje e forro com luminárias
	_caixa(Vector3(0, ALT + 0.2, zc + 0.5), Vector3(LARG + 0.6, 0.4, FUNDO + 1.0), branco)
	_caixa(Vector3(0, ALT - 0.02, zc), Vector3(LARG - 0.6, 0.04, FUNDO - 0.4), _mat("forro", Color(0.9, 0.9, 0.9), 0.9), true)
	for zz in [-4.0, -8.0, -12.0]:
		for xx in [-9.0, 0.0, 9.0]:
			_caixa(Vector3(xx, ALT - 0.06, zz), Vector3(4.0, 0.04, 0.3), luz, true)
	for xx in [-8.0, 0.0, 8.0]:
		var l := OmniLight3D.new()
		l.light_color = Color(1, 0.97, 0.92)
		l.light_energy = 2.0
		l.omni_range = 13.0
		l.shadow_enabled = false
		add_child(l)
		l.global_position = xf * Vector3(xx, ALT - 1.0, -8.0)
	# fachada de vidro com caixilhos e porta de vidro no meio (aberta pra entrar a pé)
	var porta := 2.4
	var n_pain := 8
	var lp := LARG / n_pain
	for k in n_pain:
		var x0 := -hx + k * lp
		var x1 := x0 + lp
		var cx := (x0 + x1) / 2.0
		if absf(cx) < porta / 2.0 + 0.1 and false:
			continue
		var ini := x0
		var fim := x1
		if x0 < porta / 2.0 and x1 > -porta / 2.0:   # painel do meio: vão da porta
			if x0 < -porta / 2.0:
				_caixa(Vector3((x0 - porta / 2.0) / 2.0, (ALT - 1.0) / 2.0, -0.05), Vector3(-porta / 2.0 - x0, ALT - 1.0, 0.04), vidro, false, true)
			if x1 > porta / 2.0:
				_caixa(Vector3((x1 + porta / 2.0) / 2.0, (ALT - 1.0) / 2.0, -0.05), Vector3(x1 - porta / 2.0, ALT - 1.0, 0.04), vidro, false, true)
		else:
			_caixa(Vector3(cx, (ALT - 1.0) / 2.0, -0.05), Vector3(fim - ini, ALT - 1.0, 0.04), vidro, false, true)
		_caixa(Vector3(x0, (ALT - 1.0) / 2.0, -0.05), Vector3(0.1, ALT - 1.0, 0.14), caixilho)
	_caixa(Vector3(hx, (ALT - 1.0) / 2.0, -0.05), Vector3(0.1, ALT - 1.0, 0.14), caixilho)
	_caixa(Vector3(0, 0.03, -0.05), Vector3(LARG, 0.06, 0.16), caixilho)
	for s in [-1.0, 1.0]:
		_caixa(Vector3(s * (porta / 2.0 + 0.04), (ALT - 1.0) / 2.0, -0.05), Vector3(0.08, ALT - 1.0, 0.16), caixilho)
	# FAIXA DA FACHADA com o letreiro DROPS CAR (letras acesas presas na faixa, não soltas)
	var faixa_y := ALT - 0.5
	_caixa(Vector3(0, faixa_y, 0.1), Vector3(LARG + 0.6, 1.0, 0.5), grafite)
	_caixa(Vector3(0, faixa_y - 0.52, 0.12), Vector3(LARG + 0.6, 0.06, 0.52), _mat("filete", AMARELO, 0.4, 0.0, 1.5))
	var placa := _caixa(Vector3(0, faixa_y + 0.1, 0.37), Vector3(9.6, 1.5, 0.08), _mat("placa", Color(0.04, 0.04, 0.05), 0.3, 0.2))
	placa.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var t := Label3D.new()
	t.text = "DROPS CAR"
	t.font_size = 220
	t.outline_size = 0
	t.pixel_size = 0.0072
	t.modulate = AMARELO
	t.shaded = false
	t.double_sided = false
	t.visibility_range_end = 320.0
	var f := SystemFont.new()
	f.font_weight = 900
	t.font = f
	add_child(t)
	t.global_transform = xf * Transform3D(Basis(), Vector3(0, faixa_y + 0.12, 0.42))
	var l2 := OmniLight3D.new()     # o letreiro ilumina a frente à noite
	l2.light_color = AMARELO
	l2.light_energy = 1.2
	l2.omni_range = 8.0
	l2.shadow_enabled = false
	add_child(l2)
	l2.global_position = xf * Vector3(0, faixa_y, 2.0)
	# totem na esquerda do pátio
	_caixa(Vector3(-hx - 0.8, 3.0, 6.0), Vector3(1.4, 6.0, 0.5), grafite, false, true)
	var t2 := Label3D.new()
	t2.text = "DROPS\nCAR"
	t2.font_size = 120
	t2.pixel_size = 0.005
	t2.modulate = AMARELO
	t2.shaded = false
	t2.font = f
	t2.visibility_range_end = 220.0
	add_child(t2)
	t2.global_transform = xf * Transform3D(Basis(), Vector3(-hx - 0.8, 4.6, 6.27))
	# balcão de atendimento no fundo
	_caixa(Vector3(0, 0.55, -FUNDO + 2.2), Vector3(5.0, 1.1, 0.8), grafite, true, true)
	_caixa(Vector3(0, 1.13, -FUNDO + 2.2), Vector3(5.2, 0.06, 0.9), _mat("tampo", AMARELO, 0.4), true)
	var t3 := Label3D.new()
	t3.text = "DROPS CAR"
	t3.font_size = 90
	t3.pixel_size = 0.006
	t3.modulate = Color(0.12, 0.12, 0.13)
	t3.font = f
	t3.layers = 1 << (CAMADA_DENTRO - 1)
	add_child(t3)
	t3.global_transform = xf * Transform3D(Basis(), Vector3(0, 3.4, -FUNDO + 0.35))


func _carros() -> void:
	# [id, posição local, giro, cor]
	var lugares := [["golfgti", Vector3(-8.5, 0.05, 3.6), 0.55, ""], ["jetta", Vector3(8.0, 0.05, 3.6), -0.55, ""],
		["tiguan", Vector3(-9.5, 0.04, -7.5), 0.5, "#16171a"], ["id4", Vector3(-2.8, 0.04, -6.0), -0.35, "#f2f2f2"],
		["santacruz", Vector3(4.0, 0.04, -8.0), 0.35, "#b5121b"], ["taigun", Vector3(10.0, 0.04, -6.5), -0.6, "#3b6470"]]
	for l in lugares:
		var i := -1
		for k in Dados.carros.size():
			if Dados.carros[k]["id"] == l[0]:
				i = k
		if i < 0:
			continue
		var d: Dictionary = Dados.carros[i]
		var cfg: Dictionary = (d["padrao"] as Dictionary).duplicate(true)
		cfg["neon"] = "off"
		cfg["som"] = "off"
		if str(l[3]) != "":
			cfg["cor"] = l[3]
			cfg["acabamento"] = "brilho"
		var cv := CarroVisual.new()
		add_child(cv)
		cv.montar(d, cfg, true)
		cv.alcance(110.0)
		cv.global_transform = xf * Transform3D(Basis(Vector3.UP, float(l[2])), l[1])
		var corpo := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(d["W"]), 1.3, cv.comprimento)
		col.shape = box
		col.position = Vector3(0, 0.65, (cv.frente_z + cv.tras_z) / 2.0)
		corpo.add_child(col)
		cv.add_child(corpo)
