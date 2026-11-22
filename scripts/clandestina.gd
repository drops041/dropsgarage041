extends Node
class_name Clandestina
## (modo história) CLANDESTINA: arrancada de 500 m na Avenida Juscelino Kubitschek contra um rival.
## O PC da oficina libera; aparece o ponto no mapa e o rival esperando. Ganhou = prêmio; perdeu = tenta de novo.
## A primeira é fácil (o rival é fraco); da segunda em diante só ganha quem prepara o motor (PC da oficina).

const AMARELO := Color("ffd400")
## trecho reto da Av. Juscelino Kubitschek (medido no ruas.json): largada e direção da corrida
const LARGADA := Vector3(179.6, 0.0, -417.8)
const DIR := Vector2(-0.2706, -0.9627)
const RECUO := 25.0          # a largada fica 25 m pra dentro do trecho reto
const DISTANCIA := 500.0
const FAIXA := 2.0           # meia distância entre os dois carros

var m                        # Main
var ativa := false           # o ponto da corrida está no mapa
var correndo := false
var contagem := 0.0
var t := 0.0
var rival: Node3D
var rival_s := 0.0
var _rua := -1               # índice da Av. Juscelino na rede de ruas (a corrida segue a avenida, com as curvas)
var _s0 := 0.0               # onde é a largada (metros ao longo da avenida)
var _feixe: MeshInstance3D
var _seta: MeshInstance3D
var _resultado := ""
var placar: Label
var conta: Label


func _ready() -> void:
	_feixe = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.0
	cm.bottom_radius = 3.0
	cm.height = 40.0
	cm.cap_top = false
	cm.cap_bottom = false
	_feixe.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1, 0.15, 0.1, 0.28)
	_feixe.material_override = mat
	_feixe.visible = false
	m.add_child(_feixe)
	# (22/11) seta EM PÉ (de lado, não deitada), grossa e maior: dá pra ver pra onde aponta de trás do carro
	_seta = MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(1.1, 1.3, 0.3)
	_seta.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(1, 0.22, 0.16)
	sm.emission_enabled = true
	sm.emission = Color(1, 0.2, 0.12)
	sm.emission_energy_multiplier = 1.4
	sm.no_depth_test = true
	sm.render_priority = 10
	_seta.material_override = sm
	_seta.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cabo := MeshInstance3D.new()   # cabinho da seta
	var bm := BoxMesh.new()
	bm.size = Vector3(0.42, 0.8, 0.3)
	cabo.mesh = bm
	cabo.material_override = sm
	cabo.position = Vector3(0, -0.95, 0)
	cabo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_seta.add_child(cabo)
	_seta.visible = false
	m.add_child(_seta)
	var camada := CanvasLayer.new()
	camada.layer = 7
	add_child(camada)
	placar = Label.new()
	placar.add_theme_font_size_override("font_size", 26)
	placar.add_theme_color_override("font_outline_color", Color.BLACK)
	placar.add_theme_constant_override("outline_size", 8)
	placar.position = Vector2(260, 90)
	camada.add_child(placar)
	conta = Label.new()
	conta.add_theme_font_size_override("font_size", 120)
	conta.add_theme_color_override("font_color", AMARELO)
	conta.add_theme_color_override("font_outline_color", Color.BLACK)
	conta.add_theme_constant_override("outline_size", 16)
	conta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	conta.set_anchors_preset(Control.PRESET_CENTER)
	conta.size = Vector2(400, 160)
	camada.add_child(conta)


func _achar_rua() -> void:
	if _rua >= 0:
		return
	var mp: Dictionary = m.rede.mais_perto(LARGADA, 30.0)
	if mp.is_empty():
		return
	_rua = int(mp["i"])
	_s0 = float(mp["s"]) + RECUO


## ponto da avenida a s metros da largada, deslocado pro lado (lateral > 0 = direita)
func na_pista(s: float, lateral := 0.0) -> Vector3:
	_achar_rua()
	if _rua < 0:
		return LARGADA + dir3() * (RECUO + s)
	var p: Vector2 = m.rede.ponto(_rua, _s0 + s)
	var d: Vector2 = m.rede.direcao(_rua, _s0 + s)
	return Vector3(p.x, 0, p.y) + Vector3(-d.y, 0, d.x) * lateral


func dir3(s := 0.0) -> Vector3:
	_achar_rua()
	if _rua < 0:
		return Vector3(DIR.x, 0, DIR.y)
	var d: Vector2 = m.rede.direcao(_rua, _s0 + s)
	return Vector3(d.x, 0, d.y)


func ponto_largada() -> Vector3:
	return na_pista(0.0)


## quanto o carro já andou na avenida desde a largada (e quão longe está do meio da pista)
func progresso(p: Vector3) -> Vector2:
	_achar_rua()
	var mp: Dictionary = m.rede.mais_perto(p, 40.0)
	if _rua < 0 or mp.is_empty() or int(mp["i"]) != _rua:
		return Vector2((p - ponto_largada()).dot(dir3()), 99.0 if mp.is_empty() else float(mp["d"]))
	return Vector2(float(mp["s"]) - _s0, float(mp["d"]))


func indice() -> int:
	return int(Dados.historia.get("clandestina", 0))


func dados_rival() -> Array:
	return Dados.CLANDESTINAS[mini(indice(), Dados.CLANDESTINAS.size() - 1)]


## liga o ponto da corrida no mapa e põe o rival esperando
func ativar() -> void:
	ativa = true
	_feixe.visible = true
	_feixe.global_position = m.mapa.no_chao(ponto_largada(), 0.0) + Vector3.UP * 20.0
	_seta.visible = true
	_por_rival_parado()


func _por_rival_parado() -> void:
	if rival:
		rival.queue_free()
	var dr := dados_rival()
	var i := Dados.indice_de(str(dr[1]))
	var cv := CarroVisual.new()
	m.add_child(cv)
	var c := Dados.cfg(i)
	c["cor"] = "#16171a"
	c["neon"] = "vermelho"
	cv.montar(Dados.carros[i], c)
	rival = cv
	var nome := Label3D.new()
	nome.text = str(dr[0])
	nome.font_size = 56
	nome.pixel_size = 0.006
	nome.modulate = Color(1, 0.35, 0.3)
	nome.outline_size = 10
	nome.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nome.no_depth_test = true
	nome.position = Vector3(0, 2.3, 0)
	cv.add_child(nome)
	rival_s = 0.0
	_mover_rival(0.0)


func _mover_rival(s: float) -> void:
	if rival == null:
		return
	var p: Vector3 = m.mapa.no_chao(na_pista(s, -FAIXA), 0.0)
	var d := dir3(s)
	rival.global_transform = Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), p)


## o rival anda pela curva de um carro acelerando até a final; chega aos 500 m em exatamente T segundos
func _s_rival(tt: float, T: float) -> float:
	var tau := T * 0.28
	var f := func(x: float) -> float: return x - tau * (1.0 - exp(-x / tau))
	var vmax := DISTANCIA / float(f.call(T))
	return vmax * float(f.call(tt))


func pode_largar() -> bool:
	if not ativa or correndo or m.pe or m.carro == null:
		return false
	var p: Vector3 = m.carro.global_position
	return Vector2(p.x - ponto_largada().x, p.z - ponto_largada().z).length() < 14.0 and m.carro.linear_velocity.length() < 2.0


func largar() -> void:
	correndo = true
	_resultado = ""
	_por_rival_parado()
	var d := dir3()
	m.teletransportar(m.mapa.no_chao(na_pista(0.0, FAIXA), 0.6), atan2(d.x, d.z))
	limpar_pista()
	m.congelado = true
	contagem = 3.6
	t = 0.0
	_feixe.visible = false


## tira o trânsito da avenida durante a corrida (clandestina de verdade fecha a rua)
func limpar_pista() -> void:
	if m.role == null or _rua < 0:
		return
	for tr in m.role.transito:
		if int(tr.get("i", -1)) == _rua:
			m.role._reposicionar(tr, m.carro.global_position, 700.0, 1000.0)


func _process(dt: float) -> void:
	if ativa and not correndo and m.carro:
		var p: Vector3 = m.carro.global_position
		var alvo := ponto_largada()
		_seta.global_position = p + Vector3.UP * (2.9 + sin(Time.get_ticks_msec() / 260.0) * 0.12)
		var dir := Vector3(alvo.x - p.x, 0, alvo.z - p.z)
		_seta.visible = dir.length() > 15.0 and not m.pe
		if dir.length() > 0.1:
			_seta.look_at(_seta.global_position + dir, Vector3.UP)
			_seta.rotate_object_local(Vector3.RIGHT, -PI / 2.0)   # ponta pra frente (pro alvo)
			_seta.rotate_object_local(Vector3.UP, PI / 2.0)       # e em pé: o triângulo fica de lado
		placar.text = "CLANDESTINA · Av. Juscelino · %d m" % int(dir.length()) if dir.length() > 15.0 else ""
	if not correndo:
		return
	if contagem > 0.0:
		contagem -= dt
		var c := ceili(contagem)
		conta.text = str(c) if c > 0 and c <= 3 else ""
		if contagem <= 0.0:
			conta.text = "VAI!"
			m.congelado = false
			get_tree().create_timer(0.7).timeout.connect(func(): conta.text = "")
		return
	t += dt
	limpar_pista()
	var dr := dados_rival()
	rival_s = minf(_s_rival(t, float(dr[2])), DISTANCIA + 40.0)
	_mover_rival(rival_s)
	var pr := progresso(m.carro.global_position)
	var s: float = pr.x
	var lat: float = pr.y
	placar.text = "%.1f s · você %d m · %s %d m" % [t, int(clampf(s, 0, DISTANCIA)), str(dr[0]), int(minf(rival_s, DISTANCIA))]
	if s >= DISTANCIA:
		_terminar(rival_s < DISTANCIA)
	elif rival_s >= DISTANCIA:
		_terminar(false)
	elif lat > 30.0 or m.pe:
		_terminar(false)


func _terminar(ganhou: bool) -> void:
	correndo = false
	var dr := dados_rival()
	placar.text = ""
	if ganhou:
		Dados.ganhar(int(dr[3]))
		Dados.historia["clandestina"] = indice() + 1
		Dados.historia["xp"] = int(Dados.historia.get("xp", 0)) + 50
		Dados.salvar()
		ativa = false
		_feixe.visible = false
		_seta.visible = false
		if rival:
			rival.queue_free()
			rival = null
		var prox := "" if indice() >= Dados.CLANDESTINAS.size() else "\n\nA próxima clandestina já tá no PC da oficina. Mas o próximo rival é brabo: prepara esse motor antes!"
		m.historia._falar("Ganhou de " + str(dr[0]) + " em %.1f s!\n+%s  ·  +50 XP" % [t, Dados.reais(int(dr[3]))] + prox, [["BORA!", func(): pass]], "CLANDESTINA")
	else:
		m.historia._falar(str(dr[0]) + " chegou primeiro. Não foi dessa vez!\nDá pra tentar de novo quantas vezes quiser. Se o carro tá perdendo no fim, prepara o motor no PC da oficina.",
			[["TENTAR DE NOVO", largar], ["DEPOIS", func(): _por_rival_parado(); _feixe.visible = true, false]], "CLANDESTINA")
