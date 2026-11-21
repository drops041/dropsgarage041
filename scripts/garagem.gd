extends Node3D
## Garagem da Drops: o carro no meio da oficina, câmera girando em volta e o menu pra mexer em tudo.
## Arraste na tela pra girar, roda do mouse / pinça pra aproximar.

const AMARELO := Color("ffd400")
const ESCURO := Color("141418")

var visual: CarroVisual
var cam: Camera3D
var yaw := 2.5
var pitch := 0.1
var dist := 6.6
var alvo := Vector3(-0.35, 0.6, 0.2)
var aba := "medidas"
var painel: VBoxContainer
var conteudo: VBoxContainer
var nome_l: Label
var sub_l: Label
var abas := {}
var toques := {}
var parado := 0.0
var partes_box: HBoxContainer
var fundo: PanelContainer
var _foto := OS.get_environment("DROPS_FOTO")
var _giro := OS.get_environment("DROPS_GIRO")
var _t := 0.0
var _passo := 0


func _ready() -> void:
	CarroVisual.detalhe_total = true   # na garagem o carro aparece com todos os detalhes
	_sala()
	cam = Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.current = true
	_ui()
	if Dados.modo == "historia" and (Dados.historia.get("garagem", []) as Array).is_empty():
		get_tree().change_scene_to_file.call_deferred("res://cenas/historia_abertura.tscn")
		return
	_trocar_carro(0)
	if OS.has_environment("DROPS_CAM"):   # testes: "pitch,dist"
		pitch = float(OS.get_environment("DROPS_CAM").get_slice(",", 0))
		dist = float(OS.get_environment("DROPS_CAM").get_slice(",", 1))
	if OS.has_environment("DROPS_ABA"):   # testes: abre numa aba (ex.: personagem)
		aba = OS.get_environment("DROPS_ABA")
		_montar_aba()
	if OS.has_environment("DROPS_KIT"):   # testes: liga peças do kit (ex.: kit_lip=preto,kit_saias=cor)
		for par in OS.get_environment("DROPS_KIT").split(","):
			Dados.mudar(par.get_slice("=", 0), par.get_slice("=", 1))
		visual.atualizar(Dados.cfg())
		aba = "kit"
		_montar_aba()


# ---------------------------------------------------------------- a oficina
func _sala() -> void:
	CarroVisual.usar_reflexo("res://imagens/reflexo/estudio.png", 1.0)   # luz de estúdio refletindo na lataria
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0c0c0f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8a8f9c")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.ssao_enabled = true
	env.ssr_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.1
	# (visual 2) estúdio: o HDR de softboxes reflete na lataria (verniz) — é ele que dá o brilho de showroom
	# HDRI de oficina de verdade (Poly Haven, imagens/hdri/oficina.hdr); sem ele, o estúdio antigo
	var hdr := "res://imagens/hdri/oficina.hdr" if ResourceLoader.exists("res://imagens/hdri/oficina.hdr") else "res://imagens/estudio/estudio.hdr"
	if ResourceLoader.exists(hdr):
		var ps := PanoramaSkyMaterial.new()
		ps.panorama = load(hdr)
		ps.energy_multiplier = 0.55 if hdr.contains("oficina") else 1.0
		var sk := Sky.new()
		sk.sky_material = ps
		sk.radiance_size = Sky.RADIANCE_SIZE_512
		env.sky = sk
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 0.3 if hdr.contains("oficina") else 0.55   # parte da luz ambiente vem do estúdio (a lateral não fica cinza)
		env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# chão de cimento, paredes escuras e forro (mesmas medidas da Drops: 7,44 x 10,1 x 4,6 m)
	var w := 7.44
	var dep := 10.1
	var h := 4.6
	# texturas de verdade (texturas/): cimento da oficina no chão, cimento pintado escuro nas paredes
	var chao := Texturas.material("garage_floor", 2.2, Color(0.95, 0.95, 0.95), 0.85)
	var parede := Texturas.material("painted_concrete_02", 3.0, Color(0.42, 0.42, 0.46), 1.0)
	_caixa(Vector3(w, 0.1, dep), Vector3(0, -0.05, 0), chao)
	_caixa(Vector3(w, 0.1, dep), Vector3(0, h, 0), parede)
	_caixa(Vector3(0.2, h, dep), Vector3(-w / 2.0, h / 2.0, 0), parede)
	_caixa(Vector3(0.2, h, dep), Vector3(w / 2.0, h / 2.0, 0), parede)
	_caixa(Vector3(w, h, 0.2), Vector3(0, h / 2.0, -dep / 2.0), parede)
	# porta de enrolar fechada (frente)
	var porta := StandardMaterial3D.new()
	porta.albedo_color = Color("3a3b40")
	porta.metallic = 0.7
	porta.roughness = 0.45
	_caixa(Vector3(w, h, 0.15), Vector3(0, h / 2.0, dep / 2.0), porta)
	# móveis da oficina (modelo 3D)
	if ResourceLoader.exists("res://modelos/cenario/oficina_por_dentro.glb"):
		add_child(load("res://modelos/cenario/oficina_por_dentro.glb").instantiate())
	else:
		push_warning("Falta a pasta modelos/cenario (a cidade e a oficina)")
	# grafite da Drops no fundo, acima das prateleiras
	var logo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.2, 1.6)
	logo.mesh = q
	var lm := StandardMaterial3D.new()
	lm.albedo_texture = load("res://imagens/logo_drops.jpg")
	lm.emission_enabled = true
	lm.emission_texture = lm.albedo_texture
	lm.emission_energy_multiplier = 0.35
	logo.material_override = lm
	logo.position = Vector3(0, 3.55, -dep / 2.0 + 0.12)
	add_child(logo)
	# faixa da Show de Ferragens na parede da direita
	var faixa := Label3D.new()
	faixa.text = "SHOW DE FERRAGENS"
	faixa.font_size = 96
	faixa.outline_size = 0
	faixa.modulate = Color("111111")
	faixa.pixel_size = 0.004
	var fundo := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(4.2, 0.62)
	fundo.mesh = fq
	var fm := StandardMaterial3D.new()
	fm.albedo_color = AMARELO
	fm.emission_enabled = true
	fm.emission = AMARELO
	fm.emission_energy_multiplier = 0.25
	fundo.material_override = fm
	fundo.position = Vector3(w / 2.0 - 0.12, 3.95, -1.0)
	fundo.rotation.y = -PI / 2.0
	add_child(fundo)
	faixa.position = Vector3(0, 0, 0.01)
	fundo.add_child(faixa)
	# luzes de oficina (tubulares em cima do carro)
	for z in [-1.6, 0.4, 2.4]:
		var s := SpotLight3D.new()
		s.position = Vector3(0, 4.3, z)
		s.rotation_degrees = Vector3(-90, 0, 0)
		s.spot_range = 7.0
		s.spot_angle = 62.0
		s.light_energy = 2.2
		s.light_color = Color("f2f5ff")
		s.shadow_enabled = z == 0.4
		add_child(s)
		var tubo := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(1.6, 0.05, 0.12)
		tubo.mesh = tb
		var tm := StandardMaterial3D.new()
		tm.emission_enabled = true
		tm.emission = Color.WHITE
		tm.emission_energy_multiplier = 3.0
		tubo.material_override = tm
		tubo.position = Vector3(0, 4.45, z)
		add_child(tubo)
	# luzes de recorte (como num estúdio de foto): desenham as linhas da lataria dos dois lados
	for lado in [[Vector3(-3.2, 1.5, 2.6), Color("dfe8ff"), 1.3], [Vector3(3.3, 1.8, -2.4), Color("fff1dc"), 1.0]]:
		var rl := SpotLight3D.new()
		rl.position = lado[0]
		rl.light_color = lado[1]
		rl.light_energy = lado[2]
		rl.spot_range = 7.5
		rl.spot_angle = 40.0
		rl.spot_attenuation = 0.6
		add_child(rl)
		rl.look_at(Vector3(0, 0.6, 0.4))
	# reflexo da oficina na pintura do carro
	var sonda := ReflectionProbe.new()
	sonda.size = Vector3(7.4, 4.6, 10.0)
	sonda.position = Vector3(0, 1.6, 0)
	sonda.box_projection = true
	sonda.update_mode = ReflectionProbe.UPDATE_ONCE
	sonda.intensity = 1.0
	if RenderingServer.get_rendering_device() != null and not ResourceLoader.exists("res://imagens/estudio/estudio.hdr"):
		add_child(sonda)   # (visual 2) com o estúdio HDR quem reflete é ele (a sonda da sala deixava o reflexo escuro)
	# luz amarela da marca batendo no fundo
	var o := OmniLight3D.new()
	o.position = Vector3(0, 3.4, -4.2)
	o.light_color = AMARELO
	o.light_energy = 0.8
	o.omni_range = 4.0
	add_child(o)


func _caixa(tam: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = tam
	m.mesh = b
	m.material_override = mat
	m.position = pos
	add_child(m)


# ---------------------------------------------------------------- carro
func _trocar_carro(passo: int) -> void:
	Dados.proximo_carro(passo)
	if visual:
		visual.queue_free()
	visual = CarroVisual.new()
	add_child(visual)
	visual.position = Vector3(0, 0, 0.4)
	visual.montar(Dados.carro(), Dados.cfg())
	nome_l.text = Dados.carro()["nome"]
	for n in partes_box.get_children():
		n.queue_free()
	for k in visual.partes:
		var b := _botao("ABRIR " + str(visual.partes[k]["nome"]).to_upper())
		b.add_theme_font_size_override("font_size", 16)
		var chave: String = k
		b.pressed.connect(func(): visual.abrir(chave))
		partes_box.add_child(b)
	sub_l.text = str(Dados.carro()["sub"]).to_upper()
	_montar_aba()


var _som_ar: AudioStreamPlayer


func _mudar(chave: String, valor) -> void:
	if chave.begins_with("rebaixo") and ResourceLoader.exists("res://audio/suspensao.mp3"):
		if _som_ar == null:
			_som_ar = AudioStreamPlayer.new()
			_som_ar.stream = load("res://audio/suspensao.mp3")
			_som_ar.volume_db = -6.0
			add_child(_som_ar)
		_som_ar.play()   # chiado da suspensão a ar
	if chave.begins_with("pessoa:"):
		Dados.visual[chave.substr(7)] = valor
		Dados.personagem = "protagonista"
		Dados.salvar()
		if boneco:
			Pessoa.vestir(boneco, Dados.visual)
		_montar_aba()
		return
	Dados.mudar(chave, valor)
	visual.atualizar(Dados.cfg())
	_montar_aba()


## o protagonista em pé do lado do carro (só na aba do guarda-roupa)
var boneco: Node3D
func _boneco(mostrar: bool) -> void:
	if boneco == null:
		if not mostrar:
			return
		var f := Pessoa.ficha("protagonista")
		boneco = Pessoa.criar(str(f["arq"]), float(f["altura"]))
		var raiz := Node3D.new()
		add_child(raiz)
		raiz.add_child(boneco)
		raiz.position = Vector3(1.5, 0.0, 1.55)
		raiz.rotation.y = 0.35
		Pessoa.vestir(boneco, Dados.visual)
		var ap := boneco.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.has_animation("drops/Idle_FoldArms"):
			ap.play("drops/Idle_FoldArms")
	boneco.get_parent().visible = mostrar


# ---------------------------------------------------------------- câmera
func _process(dt: float) -> void:
	if OS.has_environment("DROPS_ABA_FOTO"):   # testes: foto da aba aberta e sai
		_t += dt
		if _t > 4.0:
			get_viewport().get_texture().get_image().save_png(OS.get_environment("DROPS_ABA_FOTO"))
			get_tree().quit()
	if _foto != "":
		_t += dt
		var roteiro := [["medidas", ""], ["pintura", "camaleao"], ["rodas", "work"], ["som", "deitado"], ["neon", "rosa"], ["carro", ""], ["kit", ""]]
		if _t > 3.0 + _passo * 2.5 and _passo < roteiro.size():
			get_viewport().get_texture().get_image().save_png(_foto % _passo)
			_passo += 1
			if _passo < roteiro.size():
				if _passo == 1:
					for k in visual.partes: visual.abrir(k)
				aba = roteiro[_passo][0]
				if roteiro[_passo][1] == "camaleao": _mudar("acabamento", "camaleao")
				elif roteiro[_passo][1] == "work": _mudar("roda", "work")
				elif roteiro[_passo][1] == "deitado": _mudar("som", "deitado")
				elif roteiro[_passo][1] == "rosa": _mudar("neon", "rosa")
				_montar_aba()
			else:
				get_tree().quit()
	parado += dt
	if visual and Dados.musica.playing:
		visual.pulsar()
	# (sem giro sozinho: o carro só gira quando você arrasta)
	# câmera fixa no canto da porta (igual à foto da oficina); quem gira é o carro, como num prato giratório
	visual.rotation.y = float(_giro) if _giro != "" else yaw
	var p := Vector3(1.9, 0.75 + 0.9 + pitch * 2.2, 4.75)
	cam.fov = lerp(cam.fov, 38.0 + (dist - 3.2) * 6.0, 0.15)
	cam.global_position = p
	cam.look_at(alvo, Vector3.UP)
	# deixa o carro no meio da parte livre da tela (o menu fica na esquerda): gira a câmera um pouco pra esquerda
	# (mover a câmera pro lado sairia da sala)
	var t := get_viewport().get_visible_rect().size
	cam.h_offset = 0.0
	if fundo and fundo.visible:
		var desvio := (fundo.size.x + 30.0) / t.x * 0.5          # fração da tela ocupada pelo menu / 2
		var meia_h := deg_to_rad(cam.fov) * 0.5 * t.x / t.y      # meio ângulo horizontal (aprox.)
		cam.rotate_object_local(Vector3.UP, desvio * meia_h * 1.6)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_LEFT or e.keycode == KEY_Q:
			_ir_cat(-1)
		elif e.keycode == KEY_RIGHT or e.keycode == KEY_E:
			_ir_cat(1)
		elif e.keycode == KEY_ENTER and aba == "role":
			get_tree().change_scene_to_file("res://cenas/main.tscn")
	if e is InputEventScreenTouch:
		if e.pressed:
			toques[e.index] = e.position
		else:
			toques.erase(e.index)
		parado = 0.0
	elif e is InputEventScreenDrag:
		parado = 0.0
		if toques.size() >= 2 and toques.has(e.index):
			var outros := toques.keys().filter(func(k): return k != e.index)
			var o: Vector2 = toques[outros[0]]
			var antes: float = (toques[e.index] as Vector2).distance_to(o)
			var depois: float = e.position.distance_to(o)
			dist = clamp(dist * antes / max(1.0, depois), 3.2, 8.5)
		else:
			yaw += e.relative.x * 0.008
			pitch = clamp(pitch + e.relative.y * 0.004, -0.2, 0.8)
		toques[e.index] = e.position
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) and not DisplayServer.is_touchscreen_available():
		yaw += e.relative.x * 0.008
		pitch = clamp(pitch + e.relative.y * 0.004, -0.2, 0.8)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = max(3.2, dist - 0.4)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = min(8.5, dist + 0.4)


# ---------------------------------------------------------------- menu
func _estilo(cor: Color, borda: Color, largura_borda := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = cor
	s.border_color = borda
	s.set_border_width_all(largura_borda)
	s.set_corner_radius_all(6)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _botao(texto: String, marcado := false) -> Button:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	var base := _estilo(Color("1f1f25"), AMARELO if marcado else Color("3a3a44"), 3 if marcado else 1)
	b.add_theme_stylebox_override("normal", base)
	b.add_theme_stylebox_override("hover", base)
	b.add_theme_stylebox_override("pressed", _estilo(Color("2c2c34"), AMARELO, 3))
	b.add_theme_color_override("font_color", AMARELO if marcado else Color.WHITE)
	b.add_theme_color_override("font_hover_color", AMARELO if marcado else Color.WHITE)
	return b


## categorias do menu (carrossel em arco no topo, estilo garagem de jogo de rua)
const _CATS := [["carro", "CARRO"], ["medidas", "SUSPENSÃO"], ["pintura", "PINTURA"], ["rodas", "RODAS"],
	["neon", "NEON"], ["som", "SOM"], ["kit", "AEROFÓLIO"], ["personagem", "VOCÊ"], ["musica", "MÚSICA"], ["role", "SAIR PRO ROLÊ"]]
## (demo do navegador) só a oficina: sem rolê na cidade
var CATS: Array = _CATS.filter(func(c): return not (Dados.demo() and c[0] == "role"))
const CIANO := Color("4fd8ff")
var carrossel: Control
var _desenho_carrossel: Control
var titulo_cat: Label
var raiz_ui: Control
var moldura: Panel
var faixa_cima: TextureRect
var faixa_baixo: TextureRect
var contador_l: Label
var painel_aberto := true
var saldo_l: Label


## MODO HISTÓRIA <-> MODO LIVRE (o livre continua igual: tudo liberado, pra quem quer jogo rápido)
func _trocar_modo() -> void:
	if Dados.modo == "historia":
		Dados.sair_historia()
		get_tree().reload_current_scene()
		return
	Dados.entrar_historia()
	if (Dados.historia.get("garagem", []) as Array).is_empty():
		get_tree().change_scene_to_file("res://cenas/historia_abertura.tscn")   # primeira vez: o Drops e a loja
	else:
		get_tree().reload_current_scene()


func _cat_i() -> int:
	for i in CATS.size():
		if CATS[i][0] == aba:
			return i
	return 0


func _ir_cat(passo: int) -> void:
	aba = CATS[(_cat_i() + passo + CATS.size()) % CATS.size()][0]
	painel_aberto = true
	_montar_aba()


static var _xadrez: ImageTexture
func _tex_xadrez() -> ImageTexture:
	if _xadrez:
		return _xadrez
	var q := 22
	var img := Image.create(q * 16, q * 4, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for j in 4:
		for i in 16:
			var v: float = [0.03, 0.07, 0.11, 0.16][rng.randi() % 4] if (i + j) % 2 == 0 else 0.02
			img.fill_rect(Rect2i(i * q + 1, j * q + 1, q - 2, q - 2), Color(v, v, v * 1.05))
	_xadrez = ImageTexture.create_from_image(img)
	return _xadrez


func _ui() -> void:
	var camada := CanvasLayer.new()
	add_child(camada)
	raiz_ui = Control.new()
	raiz_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camada.add_child(raiz_ui)
	# faixas quadriculadas em cima e embaixo + moldura arredondada
	faixa_cima = TextureRect.new()
	faixa_baixo = TextureRect.new()
	for f in [faixa_cima, faixa_baixo]:
		f.texture = _tex_xadrez()
		f.stretch_mode = TextureRect.STRETCH_TILE
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		raiz_ui.add_child(f)
	moldura = Panel.new()
	moldura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var em := StyleBoxFlat.new()
	em.bg_color = Color(0, 0, 0, 0)
	em.border_color = Color(0.92, 0.93, 0.95)
	em.set_border_width_all(3)
	em.set_corner_radius_all(26)
	moldura.add_theme_stylebox_override("panel", em)
	raiz_ui.add_child(moldura)
	# aba do título no canto da moldura
	var tab := PanelContainer.new()
	tab.name = "tab_titulo"
	var et := _estilo(Color("0c0c0f"), Color(0.92, 0.93, 0.95), 3)
	et.set_corner_radius_all(18)
	et.content_margin_left = 22
	et.content_margin_right = 30
	et.content_margin_top = 4
	et.content_margin_bottom = 4
	tab.add_theme_stylebox_override("panel", et)
	tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tt := Label.new()
	tt.text = "OFICINA  DROPS"
	tt.add_theme_font_size_override("font_size", 24)
	tt.add_theme_color_override("font_color", Color.WHITE)
	tab.add_child(tt)
	raiz_ui.add_child(tab)
	# carrossel de categorias
	carrossel = Control.new()
	carrossel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz_ui.add_child(carrossel)
	_desenho_carrossel = Control.new()
	_desenho_carrossel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desenho_carrossel.draw.connect(_desenhar_carrossel)
	carrossel.add_child(_desenho_carrossel)
	# nome do carro (canto de baixo da moldura, como o preço no jogo antigo)
	var nomes := VBoxContainer.new()
	nomes.name = "nomes"
	nomes.alignment = BoxContainer.ALIGNMENT_END
	nomes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz_ui.add_child(nomes)
	nome_l = Label.new()
	nome_l.add_theme_font_size_override("font_size", 34)
	nome_l.add_theme_color_override("font_outline_color", Color.BLACK)
	nome_l.add_theme_constant_override("outline_size", 8)
	nome_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nomes.add_child(nome_l)
	sub_l = Label.new()
	sub_l.add_theme_font_size_override("font_size", 15)
	sub_l.add_theme_color_override("font_color", AMARELO)
	sub_l.add_theme_color_override("font_outline_color", Color.BLACK)
	sub_l.add_theme_constant_override("outline_size", 5)
	sub_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nomes.add_child(sub_l)
	# barra de baixo (em cima do quadriculado): contador, portas e botões
	var baixo := HBoxContainer.new()
	baixo.name = "baixo"
	baixo.add_theme_constant_override("separation", 12)
	baixo.alignment = BoxContainer.ALIGNMENT_CENTER
	raiz_ui.add_child(baixo)
	contador_l = Label.new()
	contador_l.add_theme_font_size_override("font_size", 28)
	contador_l.custom_minimum_size = Vector2(90, 0)
	baixo.add_child(contador_l)
	partes_box = HBoxContainer.new()
	partes_box.add_theme_constant_override("separation", 8)
	partes_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	baixo.add_child(partes_box)
	saldo_l = Label.new()
	saldo_l.add_theme_font_size_override("font_size", 22)
	saldo_l.add_theme_color_override("font_color", Color("7dff8a"))
	saldo_l.visible = Dados.modo == "historia"
	saldo_l.text = Dados.reais(Dados.dinheiro)
	baixo.add_child(saldo_l)
	var modo_b := _botao("MODO LIVRE" if Dados.modo == "historia" else "MODO HISTÓRIA")
	modo_b.add_theme_font_size_override("font_size", 15)
	modo_b.custom_minimum_size = Vector2(0, 50)
	modo_b.pressed.connect(_trocar_modo)
	baixo.add_child(modo_b)
	modo_b.visible = not Dados.demo()
	if Dados.modo == "historia":
		# NOVO JOGO: começa a história do zero (aperta 2 vezes pra confirmar; o modo livre não muda)
		var novo := _botao("NOVO JOGO")
		novo.add_theme_font_size_override("font_size", 15)
		novo.custom_minimum_size = Vector2(0, 50)
		novo.pressed.connect(func():
			if novo.text == "NOVO JOGO":
				novo.text = "APAGA TUDO? APERTA DE NOVO"
				get_tree().create_timer(3.0).timeout.connect(func():
					if is_instance_valid(novo):
						novo.text = "NOVO JOGO")
				return
			Dados.zerar_historia()
			get_tree().change_scene_to_file("res://cenas/historia_abertura.tscn"))
		baixo.add_child(novo)
		if OS.has_environment("DROPS_TESTE_NOVO"):   # teste: aperta NOVO JOGO 2 vezes
			get_tree().create_timer(2.0).timeout.connect(func():
				print("novo: antes dinheiro=", Dados.dinheiro, " garagem=", Dados.historia.get("garagem"))
				novo.pressed.emit()
				print("novo: botao=", novo.text)
				novo.pressed.emit())
	var esconde := _botao("ESCONDER MENU")
	esconde.add_theme_font_size_override("font_size", 15)
	esconde.custom_minimum_size = Vector2(0, 50)
	esconde.pressed.connect(func():
		painel_aberto = not painel_aberto
		esconde.text = "MOSTRAR MENU" if not painel_aberto else "ESCONDER MENU"
		_posicionar())
	baixo.add_child(esconde)
	var orig := _botao("ORIGINAL")
	orig.add_theme_font_size_override("font_size", 15)
	orig.custom_minimum_size = Vector2(0, 50)
	orig.pressed.connect(func(): Dados.original(); visual.atualizar(Dados.cfg()); _montar_aba())
	baixo.add_child(orig)
	orig.visible = Dados.modo != "historia"   # (modo história) voltar de fábrica de graça não vale
	var sair := _botao_amarelo("SAIR PRO ROLÊ", 20)
	sair.custom_minimum_size = Vector2(210, 50)
	baixo.add_child(sair)
	sair.visible = not Dados.demo()
	# painel de opções (esquerda)
	fundo = PanelContainer.new()
	fundo.clip_contents = true
	var est := _estilo(Color(0.04, 0.04, 0.06, 0.88), Color(0.92, 0.93, 0.95, 0.35), 2)
	est.set_corner_radius_all(16)
	est.content_margin_left = 14
	est.content_margin_right = 14
	est.content_margin_top = 10
	est.content_margin_bottom = 10
	fundo.add_theme_stylebox_override("panel", est)
	raiz_ui.add_child(fundo)
	painel = VBoxContainer.new()
	painel.add_theme_constant_override("separation", 8)
	fundo.add_child(painel)
	titulo_cat = Label.new()
	titulo_cat.add_theme_font_size_override("font_size", 26)
	titulo_cat.add_theme_color_override("font_color", AMARELO)
	painel.add_child(titulo_cat)
	var rolar := ScrollContainer.new()
	rolar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rolar.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	painel.add_child(rolar)
	conteudo = VBoxContainer.new()
	conteudo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conteudo.add_theme_constant_override("separation", 12)
	rolar.add_child(conteudo)
	_posicionar()
	get_viewport().size_changed.connect(_posicionar)


func _botao_amarelo(texto: String, fonte: int) -> Button:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", fonte)
	b.add_theme_stylebox_override("normal", _estilo(AMARELO, AMARELO))
	b.add_theme_stylebox_override("hover", _estilo(AMARELO, AMARELO))
	b.add_theme_stylebox_override("pressed", _estilo(Color("e6be00"), AMARELO))
	b.add_theme_color_override("font_color", Color("111111"))
	b.add_theme_color_override("font_hover_color", Color("111111"))
	b.pressed.connect(func(): get_tree().change_scene_to_file("res://cenas/main.tscn"))
	return b


## posiciona tudo pelo tamanho da tela (e fora do "notch" do celular)
func _posicionar() -> void:
	if moldura == null:
		return
	var t := get_viewport().get_visible_rect().size
	var esq := 0.0
	var dir := 0.0
	var bx := 0.0
	var seg := DisplayServer.get_display_safe_area()
	var tela := DisplayServer.screen_get_size()
	if seg.size.x > 0 and tela.x > 0:
		var k := t.x / float(tela.x)
		esq = maxf(0.0, seg.position.x * k)
		dir = maxf(0.0, (tela.x - seg.end.x) * k)
		bx = maxf(0.0, (tela.y - seg.end.y) * k)
	var h_cima := 30.0
	var h_baixo := 76.0 + bx
	faixa_cima.position = Vector2.ZERO
	faixa_cima.size = Vector2(t.x, h_cima)
	faixa_baixo.position = Vector2(0, t.y - h_baixo)
	faixa_baixo.size = Vector2(t.x, h_baixo)
	var m := Rect2(Vector2(18 + esq, h_cima + 22), Vector2(t.x - 36 - esq - dir, t.y - h_cima - h_baixo - 34))
	moldura.position = m.position
	moldura.size = m.size
	var tab := raiz_ui.get_node("tab_titulo") as Control
	tab.position = m.position + Vector2(34, -20)
	# carrossel no topo, no meio
	var cw := minf(m.size.x - 40.0, 940.0)
	carrossel.position = Vector2(m.position.x + (m.size.x - cw) / 2.0, h_cima - 6.0)
	carrossel.size = Vector2(cw, 190)
	_desenho_carrossel.size = carrossel.size
	_montar_carrossel()
	# painel de opções na esquerda, embaixo do carrossel
	var pw := clampf(t.x * 0.34, 380.0, 470.0)
	fundo.position = Vector2(m.position.x + 14, m.position.y + 150)
	fundo.size = Vector2(pw, m.end.y - (m.position.y + 150) - 14)
	fundo.custom_minimum_size = fundo.size
	fundo.visible = painel_aberto and aba != "role"
	var nomes := raiz_ui.get_node("nomes") as Control
	nomes.size = Vector2(minf(560.0, m.size.x - pw - 60), 80)
	nomes.position = Vector2(m.end.x - nomes.size.x - 26, m.end.y - 92)
	var baixo := raiz_ui.get_node("baixo") as Control
	baixo.position = Vector2(30 + esq, t.y - h_baixo + 12)
	baixo.size = Vector2(t.x - 60 - esq - dir, 52)


## pontos do carrossel: o escolhido no meio (spot amarelo), os vizinhos descendo pelo arco dos lados
func _slot(k: int) -> Vector3:
	var cw := carrossel.size.x
	var cx := cw / 2.0
	var xs: Array[float] = [0.0, 0.25, 0.42]
	var ys: Array[float] = [0.0, 74.0, 118.0]
	var tam: Array[float] = [96.0, 54.0, 42.0]
	var a := absi(k)
	return Vector3(cx + signf(k) * xs[a] * cw, ys[a], tam[a])


func _montar_carrossel() -> void:
	if carrossel == null:
		return
	for n in carrossel.get_children():
		if n != _desenho_carrossel:
			n.queue_free()
	var i0 := _cat_i()
	for k in range(-2, 3):
		var ci := (i0 + k + CATS.size()) % CATS.size()
		var s := _slot(k)
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		var vazio := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, vazio)
		var lado := s.z + (40.0 if k == 0 else 16.0)
		b.size = Vector2(lado * (2.6 if k == 0 else 1.0), lado)
		b.position = Vector2(s.x - b.size.x / 2.0, (52.0 if k == 0 else s.y + 14.0))
		var ic := IconeMenu.new(CATS[ci][0], Color("1a1406") if k == 0 else Color(1, 1, 1, 1.0 if absi(k) == 1 else 0.6))
		ic.size = Vector2(s.z, s.z)
		ic.position = (b.size - ic.size) / 2.0
		b.add_child(ic)
		var passo := k
		b.pressed.connect(func():
			if passo == 0:
				if aba == "role":
					get_tree().change_scene_to_file("res://cenas/main.tscn")
				painel_aberto = true
				_posicionar()
			else:
				_ir_cat(passo))
		carrossel.add_child(b)
	# setas pra quem prefere tocar nelas
	for d in [-1, 1]:
		var seta := _botao("‹" if d < 0 else "›")
		seta.add_theme_font_size_override("font_size", 28)
		seta.custom_minimum_size = Vector2(48, 48)
		seta.size = Vector2(48, 48)
		var s2 := _slot(2 * d)
		seta.position = Vector2(s2.x + d * 50.0 - 24.0, s2.y + 18.0)
		seta.pressed.connect(_ir_cat.bind(d))
		carrossel.add_child(seta)
	# nome da categoria em cima do spot
	titulo_cat_topo()
	_desenho_carrossel.queue_redraw()


func titulo_cat_topo() -> void:
	var pill := PanelContainer.new()
	var ep := _estilo(Color("0b0c10"), Color(0.92, 0.93, 0.95, 0.85), 2)
	ep.set_corner_radius_all(14)
	ep.content_margin_left = 26
	ep.content_margin_right = 26
	ep.content_margin_top = 2
	ep.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", ep)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = CATS[_cat_i()][1]
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", CIANO)
	l.add_theme_color_override("font_outline_color", Color(0, 0.15, 0.3))
	l.add_theme_constant_override("outline_size", 4)
	pill.add_child(l)
	carrossel.add_child(pill)
	pill.reset_size()
	pill.position = Vector2(carrossel.size.x / 2.0 - pill.size.x / 2.0, 4.0)


func _desenhar_carrossel() -> void:
	var c := _desenho_carrossel
	var cw := c.size.x
	var cx := cw / 2.0
	# arcos finos dos lados
	for d in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		for i in 25:
			var u := float(i) / 24.0
			pts.append(Vector2(cx + d * (150.0 + u * (cw * 0.42)), 26.0 + pow(u, 1.6) * 120.0))
		c.draw_polyline(pts, Color(1, 1, 1, 0.85), 2.5, true)
	# spot amarelo (trapézio) da categoria escolhida
	var tp := PackedVector2Array([Vector2(cx - 150, 36), Vector2(cx + 150, 36), Vector2(cx + 62, 162), Vector2(cx - 62, 162)])
	var cores := PackedColorArray([Color("ffe36a"), Color("ffe36a"), Color("b8860b"), Color("b8860b")])
	c.draw_polygon(tp, cores)
	c.draw_polyline(PackedVector2Array([tp[0], tp[1], tp[2], tp[3], tp[0]]), Color(0.1, 0.07, 0, 0.6), 2.0, true)


func _titulo(t: String) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", AMARELO)
	conteudo.add_child(l)


func _montar_aba() -> void:
	if conteudo == null or visual == null:
		return
	if titulo_cat:
		titulo_cat.text = CATS[_cat_i()][1]
		_montar_carrossel()
		_posicionar()
	if contador_l:
		var lista := Dados.escolhiveis()
		contador_l.text = "%d/%d" % [lista.find(Dados.idx) + 1, lista.size()]
	for n in conteudo.get_children():
		n.queue_free()
	_boneco(aba == "personagem")
	var c := Dados.cfg()
	if Dados.modo == "historia" and aba in ["medidas", "pintura", "rodas", "neon", "som", "kit"]:
		# (modo história) mexer no carro é na oficina, pagando as peças: aqui só olha
		_titulo("Modo história")
		var av := Label.new()
		av.text = "Aqui você só olha o carro.\nAs mudanças são feitas na OFICINA, pagando as peças:\nPC da oficina (suspensão, aro, pneu) e mesa de tintas na cabine (pintura).\n\nSaldo: " + Dados.reais(Dados.dinheiro)
		av.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		av.add_theme_font_size_override("font_size", 18)
		conteudo.add_child(av)
		return
	match aba:
		"medidas":
			var rmax := CarroVisual.rebaixo_max(Dados.carro())
			_linha("Rebaixo dianteiro", "rebaixo", 1.0, 0.0, rmax, c, "%d cm", "suspensão da frente (0 = original, até %d = aterrado)" % int(rmax))
			_linha("Rebaixo traseiro", "rebaixo_tras", 1.0, 0.0, rmax, c, "%d cm", "suspensão de trás (0 = original, até %d = aterrado)" % int(rmax))
			_linha("Roda (aro)", "aro", 1.0, 14.0, 28.0, c, "%d\"", "aro 14 até 28")
			_linha("Pneu (flanco)", "flanco", 0.5, 3.0, 9.0, c, "%.1f cm", "flanco baixo = pneu fininho")
			_linha("Tala dianteira", "tala", 0.5, 6.0, 10.0, c, "%.1f\"", "largura das rodas da frente")
			_linha("Tala traseira", "tala_tras", 0.5, 6.0, 12.0, c, "%.1f\"", "largura das rodas de trás")
			_linha("Cambagem", "camber", 1.0, 0.0, 8.0, c, "%d°", "roda inclinada pra dentro")
			_linha("Recuo dianteiro", "recuo", 0.5, -6.0, 8.0, c, "%.1f cm", "rodas da frente: + = pra dentro, − = pra fora")
			_linha("Recuo traseiro", "recuo_tras", 0.5, -6.0, 8.0, c, "%.1f cm", "rodas de trás: + = pra dentro, − = pra fora")
		"pintura":
			_titulo("Cor")
			_cores(Dados.CORES, "cor", str(c["cor"]))
			_titulo("Acabamento")
			_opcoes(Dados.ACABAMENTOS, "acabamento", str(c.get("acabamento", "metal")), 3)
			if c.get("acabamento", "") in ["perola", "camaleao"]:
				_titulo("Cor do reflexo")
				_cores(Dados.CORES2, "cor2", str(c.get("cor2", "")))
		"rodas":
			_titulo("Modelo")
			var g := GridContainer.new()
			g.columns = 3
			g.add_theme_constant_override("h_separation", 8)
			g.add_theme_constant_override("v_separation", 8)
			conteudo.add_child(g)
			for r in Dados.RODAS:
				var b := _botao(r[1], r[0] == c.get("roda", ""))
				b.add_theme_font_size_override("font_size", 13)
				b.icon = load("res://modelos/rodas/icones/%s.png" % r[0])
				b.expand_icon = true
				b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
				b.custom_minimum_size = Vector2(120, 128)
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				b.pressed.connect(_mudar.bind("roda", r[0]))
				g.add_child(b)
			_titulo("Cor da roda")
			_cores(Dados.CORES_RODA, "cor_roda", str(c.get("cor_roda", "")))
			_titulo("Borda")
			_opcoes([["polida", "Polida"], ["cor", "Da cor da roda"]], "borda", str(c.get("borda", "polida")), 2)
		"neon":
			_titulo("Neon embaixo do carro")
			var lista := []
			for k in Dados.NEONS:
				lista.append([k, "Desligado" if k == "off" else k.capitalize()])
			_opcoes(lista, "neon", str(c.get("neon", "off")), 2)
		"kit":
			if Acessorios.encaixes_do(Dados.carro()).is_empty():
				var av := Label.new()
				av.text = "Aerofólio é só pra carro.\nPicape não tem (troca de carro na aba CARRO)."
				av.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				av.add_theme_font_size_override("font_size", 18)
				conteudo.add_child(av)
			for e in Acessorios.encaixes_do(Dados.carro()):
				_titulo(e[1])
				_opcoes(e[2], e[0], str(c.get(e[0], "cor" if str(e[0]).ends_with("_cor") else "off")), mini(4, (e[2] as Array).size()))
		"som":
			_titulo("Equipamento de som")
			_opcoes(Dados.opcoes_som(Dados.carro()), "som", str(c.get("som", "off")), 1)
		"carro":
			_titulo("Escolha o carro")
			var gc := GridContainer.new()
			gc.columns = 2
			gc.add_theme_constant_override("h_separation", 8)
			gc.add_theme_constant_override("v_separation", 8)
			conteudo.add_child(gc)
			var lista_c := Dados.escolhiveis()   # (modo história: só os seus carros)
			for k in lista_c.size():
				var i: int = lista_c[k]
				var b := _botao(str(Dados.carros[i]["nome"]), i == Dados.idx)
				b.add_theme_font_size_override("font_size", 16)
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				b.custom_minimum_size = Vector2(0, 52)
				b.clip_text = true
				var passo := k - lista_c.find(Dados.idx)
				b.pressed.connect(_trocar_carro.bind(passo))
				gc.add_child(b)
		"personagem":
			# (fase 2) guarda-roupa do protagonista (os personagens antigos ficam só nos encontros)
			var v := Pessoa.VISUAL_PADRAO.duplicate()
			v.merge(Dados.visual, true)
			_titulo("Parte de cima")
			_opcoes([["camiseta", "CAMISETA"], ["regata", "REGATA"]], "pessoa:cima", str(v["cima"]), 2)
			_cores(Pessoa.CORES_ROUPA, "pessoa:cor_cima", str(v["cor_cima"]))
			_titulo("Parte de baixo")
			_opcoes([["calca", "CALÇA"], ["bermuda", "BERMUDA"]], "pessoa:baixo", str(v["baixo"]), 2)
			_cores(Pessoa.CORES_ROUPA, "pessoa:cor_baixo", str(v["cor_baixo"]))
			_titulo("Tênis")
			_cores(Pessoa.CORES_ROUPA, "pessoa:cor_tenis", str(v["cor_tenis"]))
			_titulo("Cabelo")
			_opcoes([["careca", "CARECA"], ["raspado", "RASPADO"], ["social", "SOCIAL"], ["comprido", "COMPRIDO"]], "pessoa:cabelo", str(v["cabelo"]), 2)
			_opcoes([[true, "COM BARBA"], [false, "SEM BARBA"]], "pessoa:barba", str(v["barba"]), 2)
			_opcoes([["preto", "PRETO"], ["castanho", "CASTANHO"], ["ruivo", "RUIVO"], ["loiro", "LOIRO"], ["grisalho", "GRISALHO"]], "pessoa:cor_cabelo", str(v["cor_cabelo"]), 3)
			_titulo("Pele")
			_opcoes([["clara", "CLARA"], ["media", "MÉDIA"], ["morena", "MORENA"], ["negra", "NEGRA"]], "pessoa:pele", str(v["pele"]), 2)
		"musica":
			_titulo("Trilha da garagem")
			var pm := Dados.painel_musica()
			pm.visible = true
			pm.top_level = false
			conteudo.add_child(pm)


func _linha(nome: String, chave: String, passo: float, mn: float, mx: float, c: Dictionary, fmt: String, dica: String) -> void:
	var l := HBoxContainer.new()
	l.add_theme_constant_override("separation", 10)
	conteudo.add_child(l)
	var tx := VBoxContainer.new()
	tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_child(tx)
	var a := Label.new()
	a.text = nome
	a.add_theme_font_size_override("font_size", 21)
	tx.add_child(a)
	a.clip_text = true
	var b := Label.new()
	b.text = dica
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Color("9a9aa5"))
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # quebra a linha em vez de empurrar o menu pra fora da tela
	b.custom_minimum_size = Vector2(60, 0)
	tx.add_child(b)
	var v := float(c.get(chave, mn))
	var menos := _botao("−")
	menos.custom_minimum_size = Vector2(54, 54)
	menos.add_theme_font_size_override("font_size", 28)
	menos.pressed.connect(func(): _mudar(chave, clamp(v - passo, mn, mx)))
	l.add_child(menos)
	var val := Label.new()
	val.text = fmt % v
	val.custom_minimum_size = Vector2(78, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.add_theme_font_size_override("font_size", 22)
	l.add_child(val)
	var mais := _botao("+")
	mais.custom_minimum_size = Vector2(54, 54)
	mais.add_theme_font_size_override("font_size", 28)
	mais.pressed.connect(func(): _mudar(chave, clamp(v + passo, mn, mx)))
	l.add_child(mais)


func _cores(lista: Array, chave: String, atual: String) -> void:
	var g := GridContainer.new()
	g.columns = 6
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	conteudo.add_child(g)
	for cor in lista:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = cor[0]
		b.custom_minimum_size = Vector2(54, 54)
		var marcado: bool = str(cor[1]).to_lower() == atual.to_lower()
		var s := _estilo(Color(cor[1]), AMARELO if marcado else Color("44444c"), 4 if marcado else 1)
		s.set_corner_radius_all(30)
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_stylebox_override("hover", s)
		b.add_theme_stylebox_override("pressed", s)
		b.pressed.connect(_mudar.bind(chave, cor[1]))
		g.add_child(b)
	# qualquer cor: abre a roda de cores
	var dica := Label.new()
	dica.text = "Qualquer cor (toque na barra e escolha na roda de cores):"
	dica.add_theme_font_size_override("font_size", 14)
	dica.add_theme_color_override("font_color", Color("9a9aa5"))
	conteudo.add_child(dica)
	var livre := ColorPickerButton.new()
	livre.text = "QUALQUER COR"
	livre.focus_mode = Control.FOCUS_NONE
	livre.custom_minimum_size = Vector2(0, 54)
	livre.add_theme_font_size_override("font_size", 18)
	livre.color = Color(atual) if atual.begins_with("#") else Color.WHITE
	livre.edit_alpha = false
	var pk := livre.get_picker()
	pk.picker_shape = ColorPicker.SHAPE_VHS_CIRCLE
	pk.presets_visible = false
	pk.sampler_visible = false
	pk.color_modes_visible = false
	pk.sliders_visible = true
	livre.popup_closed.connect(func(): _mudar(chave, "#" + livre.color.to_html(false)))
	conteudo.add_child(livre)


func _opcoes(lista: Array, chave: String, atual: String, colunas: int) -> void:
	var g := GridContainer.new()
	g.columns = colunas
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	conteudo.add_child(g)
	for o in lista:
		var b := _botao(o[1], str(o[0]) == atual)
		b.custom_minimum_size = Vector2(0, 54)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_mudar.bind(chave, o[0]))
		g.add_child(b)
