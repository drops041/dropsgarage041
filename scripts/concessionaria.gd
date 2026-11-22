class_name Concessionaria
extends Node
## (v37) Concessionária DRAFAEL MOTORS (antes DROPS CAR; o dono é o Drafael), feita aqui no jogo (no lugar do modelo antigo, que vinha bugado e com
## logos de montadoras). Prédio com fachada de vidro, letreiro DRAFAEL MOTORS na faixa da fachada (letras
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
	# FAIXA DA FACHADA com o letreiro DRAFAEL MOTORS (letras acesas presas na faixa, não soltas)
	var faixa_y := ALT - 0.5
	_caixa(Vector3(0, faixa_y, 0.1), Vector3(LARG + 0.6, 1.0, 0.5), grafite)
	_caixa(Vector3(0, faixa_y - 0.52, 0.12), Vector3(LARG + 0.6, 0.06, 0.52), _mat("filete", AMARELO, 0.4, 0.0, 1.5))
	var placa := _caixa(Vector3(0, faixa_y + 0.1, 0.37), Vector3(14.6, 1.5, 0.08), _mat("placa", Color(0.04, 0.04, 0.05), 0.3, 0.2))
	placa.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var t := Label3D.new()
	t.text = "DRAFAEL MOTORS"
	t.font_size = 190
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
	t2.text = "DRAFAEL\nMOTORS"
	t2.font_size = 64
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
	t3.text = "DRAFAEL MOTORS"
	t3.font_size = 62
	t3.pixel_size = 0.006
	t3.modulate = Color(0.12, 0.12, 0.13)
	t3.font = f
	t3.layers = 1 << (CAMADA_DENTRO - 1)
	add_child(t3)
	t3.global_transform = xf * Transform3D(Basis(), Vector3(0, 3.4, -FUNDO + 0.35))


# ---------------------------------------------------------------- exposição: UM DE CADA CARRO (22/11)
## 31 carros: 2 fileiras dentro do salão (os menores) e 1 no pátio (os compridos: picapes e SUVs), com o
## meio do pátio livre (porta e lugar de entregar carro). Os carros só carregam quando você chega perto
## (um por vez, pra não travar) e somem quando você vai longe.
const PERTO := 140.0
const LONGE := 280.0
var vagas: Array = []          # [{id, i, pos (local), cv}]
var _tick := 0.0
var drafael: Node3D
var _anim: AnimationPlayer
var _rota := [Vector3(-11.5, 0, -7.3), Vector3(-4.0, 0, -7.3), Vector3(4.0, 0, -7.3), Vector3(11.5, 0, -7.3)]
var _alvo_k := 1
var _parado := 2.0
var _falando_com: Node3D


func _carros() -> void:
	var lista := []
	for i in Dados.carros.size():
		var d: Dictionary = Dados.carros[i]
		var comp := float(d.get("axF", 1.3)) - float(d.get("axR", -1.3)) + 1.75
		lista.append([comp, i])
	lista.sort_custom(func(a, b): return a[0] < b[0])
	var pos := []
	for k in 11:
		pos.append(Vector3(-13.0 + 2.6 * k, 0.04, -3.9))     # fileira da frente do salão
	for k in 11:
		pos.append(Vector3(-13.0 + 2.6 * k, 0.04, -10.6))    # fileira do fundo
	for x in [-13.0, -10.0, -7.0, -4.0, 4.0, 7.0, 10.0, 13.0, 16.0]:   # (o totem fica na ponta esquerda)
		pos.append(Vector3(x, 0.05, 3.5))                     # pátio (os mais compridos)
	for k in mini(lista.size(), pos.size()):
		var i: int = lista[k][1]
		vagas.append({"id": str(Dados.carros[i]["id"]), "i": i, "pos": pos[k], "cv": null})


func _process(dt: float) -> void:
	_tick += dt
	if _tick >= 0.25:
		_tick = 0.0
		_carregar_perto()
	_andar(dt)


func _voce() -> Vector3:
	if m.pe and m.pessoa:
		return m.pessoa.global_position
	return m.carro.global_position if m.carro else Vector3(1e9, 0, 1e9)


func _carregar_perto() -> void:
	if vagas.is_empty():
		return
	var dist := _voce().distance_to(xf.origin)
	if dist > LONGE:
		for v in vagas:
			if v["cv"]:
				(v["cv"] as Node).queue_free()
				v["cv"] = null
		if drafael:
			drafael.queue_free()
			drafael = null
		return
	if dist > PERTO:
		return
	if drafael == null:
		_criar_drafael()
	for v in vagas:   # um carro por vez
		if v["cv"] == null:
			_expor(v)
			return


func _expor(v: Dictionary) -> void:
	var d: Dictionary = Dados.carros[int(v["i"])]
	var cfg: Dictionary = (d["padrao"] as Dictionary).duplicate(true)
	cfg["neon"] = "off"
	cfg["som"] = "off"
	cfg["acabamento"] = "brilho"
	var cv := CarroVisual.new()
	add_child(cv)
	cv.montar(d, cfg, true)
	cv.alcance(90.0)
	var centro := (cv.frente_z + cv.tras_z) / 2.0
	var p: Vector3 = v["pos"]
	cv.global_transform = xf * Transform3D(Basis(), p - Vector3(0, 0, centro))
	var corpo := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(float(d["W"]), 1.3, cv.comprimento)
	col.shape = box
	col.position = Vector3(0, 0.65, centro)
	corpo.add_child(col)
	cv.add_child(corpo)
	var placa := Label3D.new()   # nome e preço em cima do carro
	placa.text = "%s\n%s" % [d["nome"], Dados.reais(int(d.get("preco", 0)))]
	placa.font_size = 44
	placa.pixel_size = 0.004
	placa.outline_size = 10
	placa.modulate = AMARELO
	placa.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	placa.visibility_range_end = 16.0
	placa.position = Vector3(0, 2.1, centro)
	cv.add_child(placa)
	v["cv"] = cv


## carro em exposição mais perto do ponto (até 'raio' metros), ou {} se nenhum
func carro_perto(p: Vector3, raio := 3.2) -> Dictionary:
	var melhor := {}
	var md := raio
	for v in vagas:
		if v["cv"] == null:
			continue
		var c: Vector3 = xf * (v["pos"] as Vector3)
		var dd := Vector2(p.x - c.x, p.z - c.z).length()
		if dd < md:
			md = dd
			melhor = v
	return melhor


# ---------------------------------------------------------------- o Drafael andando pela loja
func _criar_drafael() -> void:
	drafael = Pessoa.criar("res://modelos/personagens/protagonista.glb", 1.80)
	add_child(drafael)
	Pessoa.vestir(drafael, Historia.VISUAL_DRAFAEL)
	drafael.global_position = xf * _rota[0]
	_anim = drafael.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var nome := Label3D.new()
	nome.text = "DRAFAEL"
	nome.font_size = 48
	nome.pixel_size = 0.005
	nome.modulate = AMARELO
	nome.outline_size = 8
	nome.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nome.visibility_range_end = 40.0
	nome.position = Vector3(0, 2.15, 0)
	drafael.add_child(nome)
	_tocar("drops/parado")


func _tocar(a: String, vel := 1.0) -> void:
	if _anim and _anim.has_animation(a):
		if _anim.current_animation != a:
			_anim.play(a, 0.25)
		_anim.speed_scale = vel


## com você do lado ele para e vira pra você; senão anda de um lado pro outro olhando os carros
func atender(quem: Node3D) -> void:
	_falando_com = quem


func _andar(dt: float) -> void:
	if drafael == null:
		return
	# (história) quando ele está lá na Drops te esperando com um serviço, não está na loja
	var fora: bool = m.historia != null and m.historia.drafael != null
	drafael.visible = not fora
	if fora:
		return
	if _falando_com and is_instance_valid(_falando_com) and _falando_com.global_position.distance_to(drafael.global_position) < 4.0:
		var o := _falando_com.global_position - drafael.global_position
		drafael.rotation.y = lerp_angle(drafael.rotation.y, atan2(o.x, o.z), minf(1.0, dt * 6.0))
		_tocar("drops/parado")
		return
	_falando_com = null
	if _parado > 0.0:
		_parado -= dt
		_tocar("drops/parado")
		if _parado <= 0.0:
			_alvo_k = (_alvo_k + 1) % _rota.size()
		return
	var alvo: Vector3 = xf * (_rota[_alvo_k] as Vector3)
	var d := Vector3(alvo.x - drafael.global_position.x, 0, alvo.z - drafael.global_position.z)
	if d.length() < 0.15:
		_parado = randf_range(2.0, 5.0)
		# para olhando pra um carro do lado
		drafael.rotation.y += PI / 2.0 * (1.0 if randf() < 0.5 else -1.0)
		if _alvo_k == _rota.size() - 1 or _alvo_k == 0:
			_rota.reverse()
			_alvo_k = 0
		return
	var passo := minf(d.length(), Pessoa.UAL_PASSO_ANDA * dt)
	drafael.global_position += d.normalized() * passo
	drafael.rotation.y = lerp_angle(drafael.rotation.y, atan2(d.x, d.z), minf(1.0, dt * 8.0))
	_tocar("drops/anda")
