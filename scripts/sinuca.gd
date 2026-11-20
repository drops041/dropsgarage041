class_name Sinuca
extends Node3D
## (v40) MESA DE SINUCA JOGÁVEL (mini-game da laje da Drops)
## - Bola 8 de bar contra a MÁQUINA: lisas (1-7), a preta (8) e listradas (9-15). Quem encaçapa primeiro fica com
##   o grupo daquela bola; encaçapou bola sua, joga de novo; falta (branca na caçapa, não bater em nada ou bater
##   primeiro em bola do outro) passa a vez. Ganha quem matar a 8 depois de limpar as suas; a 8 antes da hora perde.
## - Mira: arraste o dedo/mouse em cima da mesa (a linha mostra onde vai). Força: puxe a barra da direita pra baixo
##   e solte pra dar a tacada.
## - Física própria, 2D, no plano da mesa (u = largura, v = comprimento), com tabela, caçapa e atrito.

const L := 1.98            # comprimento do pano (no z da mesa)
const W := 0.99            # largura do pano (no x)
const R := 0.0286          # raio da bola (57 mm)
const ALT := 0.80          # altura do pano em relação ao chão
const ATRITO := 0.32       # desaceleração rolando (m/s²)
const TABELA := 0.78       # quanto sobra da velocidade batendo na tabela
const CHOQUE := 0.95       # bola com bola
const V_MAX := 4.2         # tacada mais forte (m/s)
const CORES := [Color("f2c418"), Color("1f4fc4"), Color("d42a22"), Color("6a2a9e"), Color("f07a18"), Color("1d8a3c"), Color("7a1420"), Color("111111")]

var m: Node                      # main.gd
var ativo := false
var pos: Array[Vector2] = []     # 0 = branca, 1..15
var vel: Array[Vector2] = []
var dentro: Array[bool] = []     # encaçapada
var bolas: Array[MeshInstance3D] = []
var pano: Node3D                 # origem no centro do pano, y = superfície
var mira := Vector2(0, 1)        # direção da tacada (no plano da mesa)
var forca := 0.0                 # 0..1 enquanto puxa a barra
var rodando := false             # bolas andando depois da tacada
var tacadas := 0
var _taco: MeshInstance3D
var _linha: MeshInstance3D
var _fantasma: MeshInstance3D
var _ui: Control
var _txt: Label
var _barra: ProgressBar
var _arrastando_mira := false
var _puxando := false
var _encacapou_na_tacada: Array = []
var vez := 0                     # 0 = você, 1 = máquina
var grupo := [-1, -1]            # grupo de cada um: 0 = lisas, 1 = listradas, -1 = mesa aberta
var primeiro_toque := -1         # primeira bola que a branca bateu na tacada
var _ia_t := 0.0                 # máquina "pensando"
var _ia_mira := Vector2(0, 1)
var _ia_forca := 0.5
var _ia_de := Vector2(0, 1)
const NOMES := ["VOCÊ", "MÁQUINA"]
const ERRO_IA := 1.6             # graus de erro de mira da máquina (mais = mais fácil)
var _cam_pos := Vector3.ZERO
var _hud_antes := {}
var esconder_jogando: Array = []   # coisas da laje que atrapalham a visão de cima (varal)


func montar(main_ref: Node) -> void:
	m = main_ref
	_mesa()
	_bolas()
	_arrumar()


# ----------------------------------------------------------------------- visual
func _mat(cor: Color, rug := 0.6, metal := 0.0) -> StandardMaterial3D:
	var s := StandardMaterial3D.new()
	s.albedo_color = cor
	s.roughness = rug
	s.metallic = metal
	return s


func _caixa(tam: Vector3, p: Vector3, mat: Material, pai: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = tam
	mi.mesh = bm
	mi.material_override = mat
	mi.position = p
	pai.add_child(mi)
	return mi


func _mesa() -> void:
	var madeira := _mat(Color(0.28, 0.13, 0.06), 0.45)
	var feltro := _mat(Color(0.05, 0.42, 0.2), 0.95)      # pano verde
	var borda := _mat(Color(0.04, 0.34, 0.16), 0.9)
	var preto := _mat(Color(0.02, 0.02, 0.02), 0.9)
	var ouro := _mat(Color(0.85, 0.65, 0.25), 0.35, 0.8)
	pano = Node3D.new()
	pano.position = Vector3(0, ALT, 0)
	add_child(pano)
	# tampo e saia de madeira
	_caixa(Vector3(W + 0.06, 0.12, L + 0.06), Vector3(0, ALT - 0.07, 0), feltro)
	_caixa(Vector3(W + 0.3, 0.2, L + 0.3), Vector3(0, ALT - 0.2, 0), madeira)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_caixa(Vector3(0.14, ALT - 0.25, 0.14), Vector3(sx * (W / 2.0 + 0.02), (ALT - 0.25) / 2.0, sz * (L / 2.0 - 0.1)), madeira)
	# tabelas (borracha verde) e moldura de madeira em cima
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_caixa(Vector3(0.05, 0.04, L / 2.0 - 0.13), Vector3(sx * (W / 2.0 + 0.025), ALT + 0.02, sz * L / 4.0), borda)
		_caixa(Vector3(W - 0.13, 0.04, 0.05), Vector3(0, ALT + 0.02, sx * (L / 2.0 + 0.025)), borda)
	for sx in [-1.0, 1.0]:
		_caixa(Vector3(0.1, 0.06, L + 0.22), Vector3(sx * (W / 2.0 + 0.1), ALT + 0.01, 0), madeira)
		_caixa(Vector3(W + 0.3, 0.06, 0.1), Vector3(0, ALT + 0.01, sx * (L / 2.0 + 0.1)), madeira)
	# caçapas (buraco preto + boca dourada)
	for p in _cacapas():
		var c := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.06
		cm.height = 0.05
		c.mesh = cm
		c.material_override = preto
		c.position = Vector3(p.x, ALT + 0.03, p.y)
		add_child(c)
		var aro := _caixa(Vector3(0.13, 0.008, 0.13), Vector3(p.x, ALT + 0.058, p.y), ouro)
		aro.visible = false
	# marca da cabeceira (linha branca fininha)
	_caixa(Vector3(W, 0.002, 0.004), Vector3(0, ALT + 0.001, -L / 4.0), _mat(Color(0.9, 0.9, 0.9)))
	# taco, linha de mira e bola-fantasma
	_taco = MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.006
	tm.bottom_radius = 0.014
	tm.height = 1.45
	_taco.mesh = tm
	_taco.material_override = _mat(Color(0.75, 0.55, 0.3), 0.4)
	pano.add_child(_taco)
	_linha = MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.006, 0.002, 1.0)
	_linha.mesh = lm
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.albedo_color = Color(1, 1, 1, 0.75)
	lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_linha.material_override = lmat
	pano.add_child(_linha)
	_fantasma = MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = R
	fm.height = R * 2.0
	_fantasma.mesh = fm
	var fmat := lmat.duplicate() as StandardMaterial3D
	fmat.albedo_color = Color(1, 1, 1, 0.3)
	_fantasma.material_override = fmat
	pano.add_child(_fantasma)
	_mostrar_mira(false)
	# corpo pra ninguém atravessar a mesa
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(W + 0.3, ALT + 0.05, L + 0.3)
	cs.shape = bx
	cs.position = Vector3(0, (ALT + 0.05) / 2.0, 0)
	sb.add_child(cs)
	add_child(sb)


func _cacapas() -> Array[Vector2]:
	var c: Array[Vector2] = []
	for su in [-1.0, 1.0]:
		for sv in [-1.0, 1.0]:
			c.append(Vector2(su * (W / 2.0 + 0.015), sv * (L / 2.0 + 0.015)))
		c.append(Vector2(su * (W / 2.0 + 0.035), 0.0))
	return c


var _sh_bola: Shader
func _bolas() -> void:
	_sh_bola = Shader.new()
	_sh_bola.code = """shader_type spatial;
uniform vec4 cor : source_color;
uniform bool listrada = false;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	vec3 c = cor.rgb;
	if (listrada && abs(lp.y) > 0.011) { c = vec3(0.95, 0.95, 0.92); }
	ALBEDO = c;
	ROUGHNESS = 0.18;
	SPECULAR = 0.7;
}"""
	var sm := SphereMesh.new()
	sm.radius = R
	sm.height = R * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	for i in 16:
		var b := MeshInstance3D.new()
		b.mesh = sm
		var mt := ShaderMaterial.new()
		mt.shader = _sh_bola
		if i == 0:
			mt.set_shader_parameter("cor", Color(0.96, 0.95, 0.9))
		else:
			mt.set_shader_parameter("cor", CORES[(i - 1) % 8])
			mt.set_shader_parameter("listrada", i > 8)
		b.material_override = mt
		pano.add_child(b)
		bolas.append(b)
		pos.append(Vector2.ZERO)
		vel.append(Vector2.ZERO)
		dentro.append(false)


## arruma o triângulo e a branca
func _arrumar() -> void:
	var ordem := [1, 9, 2, 10, 8, 3, 11, 4, 12, 5, 13, 6, 14, 7, 15]   # a 8 no meio da 3ª fileira
	ordem.shuffle()
	ordem.erase(8)
	ordem.insert(4, 8)
	var k := 0
	var dz := R * 2.0 * 0.866 + 0.0005
	for fila in 5:
		for j in fila + 1:
			var b: int = ordem[k]
			pos[b] = Vector2((j - fila / 2.0) * (R * 2.0 + 0.0005), L / 4.0 + fila * dz)
			k += 1
	pos[0] = Vector2(0, -L / 4.0)
	for i in 16:
		vel[i] = Vector2.ZERO
		dentro[i] = false
		bolas[i].visible = true
	tacadas = 0
	rodando = false
	vez = 0
	grupo = [-1, -1]
	_ia_t = 0.0
	mira = Vector2(0, 1)
	_atualizar_bolas(0.0)
	_texto()


# ----------------------------------------------------------------------- entrar / sair
func entrar() -> void:
	if ativo:
		return
	ativo = true
	# tela limpa: só a mesa e o placar (o resto do HUD volta quando sair)
	_hud_antes = {}
	for c in m.hud.get_children():
		if c is CanvasItem and c != _ui:
			_hud_antes[c] = (c as CanvasItem).visible
			(c as CanvasItem).visible = false
	if m.pessoa:
		m.pessoa.process_mode = Node.PROCESS_MODE_DISABLED
		m.pessoa.visible = false
	for n in esconder_jogando:
		(n as Node3D).visible = false
	_cam_pos = m.cam.global_position
	if _ui == null:
		_montar_ui()
	_ui.visible = true
	_mostrar_mira(not rodando)
	_texto()
	_posicionar_ui.call_deferred()


func sair() -> void:
	if not ativo:
		return
	ativo = false
	_ui.visible = false
	for c in _hud_antes:
		if is_instance_valid(c):
			(c as CanvasItem).visible = _hud_antes[c]
	if m.pessoa:
		m.pessoa.process_mode = Node.PROCESS_MODE_INHERIT
		m.pessoa.visible = true
	for n in esconder_jogando:
		(n as Node3D).visible = true
	_mostrar_mira(false)


func _montar_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.hud.add_child(_ui)
	var topo := PanelContainer.new()
	topo.name = "Topo"
	_ui.add_child(topo)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	topo.add_child(hb)
	_txt = Label.new()
	_txt.add_theme_font_size_override("font_size", 22)
	hb.add_child(_txt)
	for par in [["RECOMEÇAR", _arrumar], ["SAIR", sair]]:
		var b := Button.new()
		b.text = par[0]
		b.add_theme_font_size_override("font_size", 20)
		b.custom_minimum_size = Vector2(130, 46)
		b.pressed.connect(par[1])
		hb.add_child(b)
	var dica := Label.new()
	dica.text = "Arraste na mesa pra mirar  ·  Puxe a barra pra baixo e solte pra tacar  ·  Você contra a MÁQUINA"
	dica.add_theme_font_size_override("font_size", 17)
	dica.modulate = Color(1, 1, 1, 0.8)
	dica.name = "Dica"
	_ui.add_child(dica)
	# barra de força (puxar pra baixo e soltar)
	_barra = ProgressBar.new()
	_barra.fill_mode = ProgressBar.FILL_TOP_TO_BOTTOM
	_barra.show_percentage = false
	_barra.custom_minimum_size = Vector2(70, 340)
	_barra.max_value = 1.0
	_barra.mouse_filter = Control.MOUSE_FILTER_STOP
	var fundo := StyleBoxFlat.new()
	fundo.bg_color = Color(0, 0, 0, 0.55)
	fundo.set_corner_radius_all(14)
	fundo.border_color = Color(1, 0.83, 0.0)
	fundo.set_border_width_all(3)
	var cheio := StyleBoxFlat.new()
	cheio.bg_color = Color(1, 0.83, 0.0, 0.9)
	cheio.set_corner_radius_all(12)
	_barra.add_theme_stylebox_override("background", fundo)
	_barra.add_theme_stylebox_override("fill", cheio)
	_ui.add_child(_barra)
	var lb := Label.new()
	lb.text = "FORÇA"
	lb.add_theme_font_size_override("font_size", 18)
	lb.name = "Forca"
	_ui.add_child(lb)
	_barra.gui_input.connect(_barra_input)
	_posicionar_ui()
	m.get_viewport().size_changed.connect(_posicionar_ui)


func _posicionar_ui() -> void:
	if _barra == null:
		return
	var t: Vector2 = m.get_viewport().get_visible_rect().size
	_barra.position = Vector2(t.x - 110 - m._margem_segura(), t.y / 2.0 - 150)
	var lb := _ui.get_node("Forca") as Label
	lb.position = _barra.position + Vector2(4, -30)
	var topo := _ui.get_node("Topo") as Control
	topo.reset_size()
	topo.position = Vector2((t.x - topo.size.x) / 2.0, 14)
	var dica := _ui.get_node("Dica") as Control
	dica.reset_size()
	dica.position = Vector2((t.x - dica.size.x) / 2.0, t.y - 44)


func _texto() -> void:
	if _txt == null:
		return
	var n := 0
	for i in range(1, 16):
		if dentro[i]:
			n += 1
	var gn := func(k: int) -> String:
		if grupo[k] < 0:
			return ""
		return " (%s %d)" % ["lisas" if grupo[k] == 0 else "listradas", 7 - _restantes(grupo[k])]
	var v := int(Dados.dicas.get("sinuca_vitorias", 0))
	var d := int(Dados.dicas.get("sinuca_derrotas", 0))
	_txt.text = "VOCÊ%s  x  MÁQUINA%s   ·   Vez: %s   ·   Placar %d x %d" % [gn.call(0), gn.call(1), NOMES[vez], v, d]


# ----------------------------------------------------------------------- controles
func _barra_input(e: InputEvent) -> void:
	if rodando or not ativo or vez == 1:
		return
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_puxando = true
			forca = 0.0
		elif _puxando:
			_puxando = false
			if forca > 0.04:
				_tacar(forca)
			forca = 0.0
			_barra.value = 0.0
	elif e is InputEventMouseMotion and _puxando:
		forca = clampf((e as InputEventMouseMotion).position.y / _barra.size.y, 0.0, 1.0)
		_barra.value = forca


func _unhandled_input(e: InputEvent) -> void:
	if not ativo:
		return
	if e is InputEventKey and e.pressed and (e as InputEventKey).physical_keycode == KEY_ESCAPE:
		sair()
		return
	if rodando or vez == 1:
		return
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_arrastando_mira = e.pressed
		if e.pressed:
			_mirar((e as InputEventMouseButton).position)
	elif e is InputEventMouseMotion and _arrastando_mira:
		_mirar((e as InputEventMouseMotion).position)
	elif e is InputEventKey and e.pressed and not e.echo:
		var k := (e as InputEventKey).physical_keycode
		if k == KEY_ESCAPE:
			sair()
		elif k == KEY_SPACE:
			_tacar(0.55)


## ponto da tela -> ponto no pano; a mira aponta da branca pra lá
func _mirar(tela: Vector2) -> void:
	var cam: Camera3D = m.cam
	var o := cam.project_ray_origin(tela)
	var d := cam.project_ray_normal(tela)
	var inv := pano.global_transform.affine_inverse()
	var ol := inv * o
	var dl := (inv.basis * d)
	if absf(dl.y) < 1e-4:
		return
	var t := -ol.y / dl.y
	if t <= 0.0:
		return
	var p := ol + dl * t
	var alvo := Vector2(p.x, p.z) - pos[0]
	if alvo.length() > 0.01:
		mira = alvo.normalized()
		_mostrar_mira(true)


func _tacar(f: float) -> void:
	if rodando or dentro[0]:
		return
	vel[0] = mira * V_MAX * pow(f, 1.15)
	rodando = true
	tacadas += 1
	_encacapou_na_tacada = []
	primeiro_toque = -1
	_mostrar_mira(false)
	_texto()


# ----------------------------------------------------------------------- física
func _physics_process(dt: float) -> void:
	if not rodando:
		return
	var n := 10
	var h := dt / n
	for _s in n:
		_passo(h)
	var parado := true
	for i in 16:
		if not dentro[i] and vel[i].length() > 0.004:
			parado = false
	if parado:
		for i in 16:
			vel[i] = Vector2.ZERO
		rodando = false
		_fim_da_tacada()
	_atualizar_bolas(dt)


func _passo(h: float) -> void:
	for i in 16:
		if dentro[i]:
			continue
		var v := vel[i]
		var s := v.length()
		if s > 0.0:
			var ns := maxf(0.0, s - ATRITO * h)
			v = v * (ns / s)
		pos[i] += v * h
		vel[i] = v
	# bola com bola
	for i in 16:
		if dentro[i]:
			continue
		for j in range(i + 1, 16):
			if dentro[j]:
				continue
			var d := pos[j] - pos[i]
			var dist := d.length()
			if dist < R * 2.0 and dist > 1e-6:
				if i == 0 and primeiro_toque < 0:
					primeiro_toque = j
				var nrm := d / dist
				var sobra := R * 2.0 - dist
				pos[i] -= nrm * sobra * 0.5
				pos[j] += nrm * sobra * 0.5
				var vn := (vel[i] - vel[j]).dot(nrm)
				if vn > 0.0:
					var imp := nrm * vn * (1.0 + CHOQUE) * 0.5
					vel[i] -= imp
					vel[j] += imp
	# caçapas e tabelas
	var cac := _cacapas()
	for i in 16:
		if dentro[i]:
			continue
		var p := pos[i]
		var caiu := false
		for c in cac:
			var raio := 0.062 if absf(c.y) > 0.1 else 0.056
			if p.distance_to(c) < raio:
				caiu = true
		# passou da boca da caçapa (fora da tabela): caiu também
		if absf(p.x) > W / 2.0 + 0.03 or absf(p.y) > L / 2.0 + 0.03:
			caiu = true
		if caiu:
			dentro[i] = true
			vel[i] = Vector2.ZERO
			bolas[i].visible = false
			_encacapou_na_tacada.append(i)
			continue
		var perto_canto := absf(p.y) > L / 2.0 - 0.075
		var perto_meio := absf(p.y) < 0.06
		if absf(p.x) > W / 2.0 - R and not (perto_canto or perto_meio):
			p.x = signf(p.x) * (W / 2.0 - R)
			vel[i].x = -vel[i].x * TABELA
			vel[i].y *= 0.97
		var perto_canto_x := absf(p.x) > W / 2.0 - 0.075
		if absf(p.y) > L / 2.0 - R and not perto_canto_x:
			p.y = signf(p.y) * (L / 2.0 - R)
			vel[i].y = -vel[i].y * TABELA
			vel[i].x *= 0.97
		pos[i] = p


func _grupo_de(b: int) -> int:
	if b >= 1 and b <= 7:
		return 0
	if b >= 9 and b <= 15:
		return 1
	return -1


func _restantes(gr: int) -> int:
	var n := 0
	for b in range(1, 16):
		if _grupo_de(b) == gr and not dentro[b]:
			n += 1
	return n


func _fim_da_tacada() -> void:
	var quem := vez
	var pots: Array = _encacapou_na_tacada.duplicate()
	var falta := (0 in pots) or primeiro_toque < 0
	var motivo := "BRANCA NA CAÇAPA" if (0 in pots) else ("NÃO BATEU EM NADA" if primeiro_toque < 0 else "")
	if not falta and grupo[quem] >= 0:
		var ok: bool = _grupo_de(primeiro_toque) == grupo[quem] or (primeiro_toque == 8 and _restantes(grupo[quem]) == 0)
		if not ok:
			falta = true
			motivo = "BATEU PRIMEIRO NA BOLA DO OUTRO"
	# a 8 decide o jogo
	if 8 in pots:
		var limpou: bool = grupo[quem] >= 0 and _restantes(grupo[quem]) == 0
		_fim_jogo(quem if (limpou and not falta) else 1 - quem, "A 8 caiu antes da hora!" if not limpou else ("Falta na bola 8!" if falta else "Matou a 8!"))
		return
	# mesa aberta: a primeira bola encaçapada (sem falta) define os grupos
	if grupo[quem] < 0 and not falta:
		for b in pots:
			if _grupo_de(b) >= 0:
				grupo[quem] = _grupo_de(b)
				grupo[1 - quem] = 1 - grupo[quem]
				m.toast("%s FICOU COM AS %s" % [NOMES[quem], "LISAS" if grupo[quem] == 0 else "LISTRADAS"], 2.0)
				break
	var minhas := 0
	for b in pots:
		if _grupo_de(b) >= 0 and (grupo[quem] < 0 or _grupo_de(b) == grupo[quem]):
			minhas += 1
	if 0 in pots:
		_repor_branca()
	if falta:
		vez = 1 - quem
		m.toast("FALTA: %s! Vez d%s" % [motivo, "a MÁQUINA" if vez == 1 else "e VOCÊ"], 2.2)
	elif minhas == 0:
		vez = 1 - quem
		if vez == 1:
			m.toast("Vez da MÁQUINA", 1.2)
		else:
			m.toast("SUA VEZ!", 1.2)
	elif quem == 0:
		m.toast(["BOA!", "CAÇAPOU!", "QUE TACADA!", "ISSO AÍ!"].pick_random() + " Joga de novo.", 1.4)
	_ia_t = 0.0
	_texto()
	if ativo:
		_mostrar_mira(true)


func _repor_branca() -> void:
	dentro[0] = false
	bolas[0].visible = true
	var p := Vector2(0, -L / 4.0)
	var livre := false
	while not livre:
		livre = true
		for i in range(1, 16):
			if not dentro[i] and pos[i].distance_to(p) < R * 2.2:
				livre = false
		if not livre:
			p.x += R * 2.5
			if p.x > W / 2.0 - R:
				p = Vector2(-W / 2.0 + R * 2.0, p.y - R * 3.0)
	pos[0] = p
	vel[0] = Vector2.ZERO


func _fim_jogo(ganhou: int, txt: String) -> void:
	var k := "sinuca_vitorias" if ganhou == 0 else "sinuca_derrotas"
	Dados.dicas[k] = int(Dados.dicas.get(k, 0)) + 1
	Dados.salvar()
	m.toast("%s  %s" % [txt, "VOCÊ GANHOU! 🏆" if ganhou == 0 else "A MÁQUINA GANHOU."], 4.0)
	_arrumar()


# ----------------------------------------------------------------------- máquina
## escolhe a tacada: pra cada bola dela e cada caçapa, vê se o caminho tá livre e quão fechado é o corte
func _ia_planejar() -> void:
	var alvos: Array = []
	var g_ia: int = grupo[1]
	for b in range(1, 16):
		if dentro[b]:
			continue
		if b == 8:
			if g_ia >= 0 and _restantes(g_ia) == 0:
				alvos.append(b)
		elif g_ia < 0 or _grupo_de(b) == g_ia:
			alvos.append(b)
	var melhor := -1.0
	var c := pos[0]
	_ia_mira = mira
	_ia_forca = 0.45
	for b in alvos:
		for pc in _cacapas():
			var t: Vector2 = pos[b]
			var para := (pc - t)
			var d2 := para.length()
			if d2 < 1e-4:
				continue
			var fantasma := t - para / d2 * R * 2.0
			if absf(fantasma.x) > W / 2.0 - R or absf(fantasma.y) > L / 2.0 - R:
				continue
			var ida := fantasma - c
			var d1 := ida.length()
			if d1 < 1e-4:
				continue
			var corte := ida.normalized().dot(para / d2)
			if corte < 0.3:
				continue
			if not _livre(c, fantasma, [0, b]) or not _livre(t, pc, [0, b]):
				continue
			var nota := corte * corte / (0.3 + d1 + d2 * 1.4)
			if nota > melhor:
				melhor = nota
				_ia_mira = ida.normalized()
				var v_bola := sqrt(2.0 * ATRITO * (d2 + 0.3))
				var v_contato := v_bola / (corte * 0.975)
				var v0 := sqrt(v_contato * v_contato + 2.0 * ATRITO * d1) * 1.12
				_ia_forca = clampf(pow(v0 / V_MAX, 1.0 / 1.15), 0.18, 1.0)
	if melhor < 0.0:
		# sem tacada boa: bate firme na bola dela mais perto (pelo menos não faz falta)
		var perto := 99.0
		for b in alvos:
			var dd := pos[0].distance_to(pos[b])
			if dd < perto and _livre(c, pos[b], [0, b]):
				perto = dd
				_ia_mira = (pos[b] - c).normalized()
				_ia_forca = 0.6
	# ninguém é perfeito
	_ia_mira = _ia_mira.rotated(deg_to_rad(randfn(0.0, ERRO_IA)))
	_ia_forca = clampf(_ia_forca * randf_range(0.92, 1.1), 0.15, 1.0)
	_ia_de = mira


func _livre(a: Vector2, b: Vector2, fora: Array) -> bool:
	var ab := b - a
	var L2 := ab.length_squared()
	for k in 16:
		if dentro[k] or k in fora:
			continue
		var t := 0.0 if L2 < 1e-8 else clampf((pos[k] - a).dot(ab) / L2, 0.0, 1.0)
		if (a + ab * t).distance_to(pos[k]) < R * 2.0 * 0.98:
			return false
	return true


func _vez_da_maquina(dt: float) -> void:
	if not ativo or rodando or vez != 1 or dentro[0]:
		return
	if _ia_t == 0.0:
		_ia_planejar()
	_ia_t += dt
	# vira a mira devagar (dá pra ver o que ela vai fazer), puxa o taco e solta
	var k := clampf(_ia_t / 1.1, 0.0, 1.0)
	mira = _ia_de.slerp(_ia_mira, smoothstep(0.0, 1.0, k)).normalized()
	forca = clampf((_ia_t - 1.3) / 0.6, 0.0, 1.0) * _ia_forca
	_mostrar_mira(true)
	if _ia_t > 2.0:
		forca = 0.0
		_ia_t = 0.0
		_tacar(_ia_forca)


# ----------------------------------------------------------------------- desenho
func _atualizar_bolas(dt: float) -> void:
	for i in 16:
		var b := bolas[i]
		b.position = Vector3(pos[i].x, R, pos[i].y)
		var v := vel[i]
		if v.length() > 0.001 and dt > 0.0:
			var eixo := Vector3(v.y, 0, -v.x).normalized()
			b.global_rotate(pano.global_basis * eixo, v.length() * dt / R)
	if not rodando and ativo:
		_mostrar_mira(true)


func _mostrar_mira(sim: bool) -> void:
	if _taco == null:
		return
	_taco.visible = sim
	_linha.visible = sim
	_fantasma.visible = sim
	if not sim:
		return
	var b := Vector3(pos[0].x, R, pos[0].y)
	var dir := Vector3(mira.x, 0, mira.y)
	# taco atrás da branca, recuando com a força
	var recuo := 0.04 + forca * 0.28
	var meio := b - dir * (recuo + 1.45 / 2.0)
	_taco.position = meio + Vector3.UP * 0.03
	_taco.basis = Basis(Quaternion(Vector3.UP, (dir + Vector3.UP * 0.05).normalized()))
	# linha até a primeira bola ou tabela
	var dist := _alcance()
	_linha.transform = Transform3D(Basis.looking_at(dir, Vector3.UP) * Basis.from_scale(Vector3(1, 1, maxf(0.01, dist))), b + dir * dist / 2.0)
	_fantasma.position = b + dir * dist


## até onde a branca anda reto antes de bater em alguma coisa
func _alcance() -> float:
	var o := pos[0]
	var melhor := 3.0
	for i in range(1, 16):
		if dentro[i]:
			continue
		var c := pos[i] - o
		var proj := c.dot(mira)
		if proj <= 0.0:
			continue
		var perp2 := c.length_squared() - proj * proj
		var r2 := (R * 2.0) * (R * 2.0)
		if perp2 < r2:
			var t := proj - sqrt(r2 - perp2)
			if t < melhor:
				melhor = t
	for eixo in 2:
		var dv := mira[eixo]
		if absf(dv) < 1e-6:
			continue
		var lim := (W / 2.0 - R) if eixo == 0 else (L / 2.0 - R)
		var t2 := (signf(dv) * lim - o[eixo]) / dv
		if t2 > 0.0 and t2 < melhor:
			melhor = t2
	return maxf(0.0, melhor)


## câmera de cima da mesa (o comprimento da mesa fica deitado na tela)
func camera(dt: float) -> bool:
	if not ativo:
		return false
	var c := pano.global_position
	var lado: Vector3 = global_basis.x.normalized()
	var alvo := c + Vector3.UP * 1.75 - lado * 0.3
	_cam_pos = _cam_pos.lerp(alvo, 1.0 - exp(-dt * 5.0))
	m.cam.global_position = _cam_pos
	m.cam.look_at(c - lado * 0.05, lado)
	m.cam_pos = _cam_pos
	return true


func _process(dt: float) -> void:
	if ativo and _puxando:
		_mostrar_mira(true)
	_vez_da_maquina(dt)
