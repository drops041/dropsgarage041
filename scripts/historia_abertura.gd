extends Node3D
## MODO HISTÓRIA — abertura: o Drops (dono da Drops Garage) de costas, pintando a logo na parede com a pistola.
## Termina, vira pra frente, fala com você, e aparece a loja do primeiro carro (os 5 baratos do começo).
## Os próximos carros você compra na Drafael Motors (loja do Drafael), na cidade.

const AMARELO := Color("ffd400")
## o Drops: camiseta amarela da loja, calça jeans, cabelo raspado e barba
const VISUAL_DROPS := {"cima": "camiseta", "cor_cima": "#ffd400", "baixo": "calca", "cor_baixo": "#2b3a5c",
	"cor_tenis": "#18181b", "cabelo": "raspado", "barba": true, "cor_cabelo": "preto", "pele": "media"}
const T_PINTA := 6.5        # segundos pintando a logo
const T_VIRA := 1.1         # segundos virando pra frente
const FALA := "Olá, sou o Drops! Bora fazer parte desse sonho?\nVocê ganhou R$ 20 mil: compre seu primeiro carro e customize sua imaginação!"

var cam: Camera3D
var drops: Node3D           # modelo do Drops (com AnimationPlayer)
var anim: AnimationPlayer
var pistola: Node3D
var logo_mat: ShaderMaterial
var t := 0.0
var fase := "pinta"         # pinta -> vira -> fala -> loja
var carro_vis: CarroVisual
var lista: Array = []       # índices dos carros à venda
var k := 0
var ui: Control
var legenda: Label
var painel: PanelContainer
var nome_l: Label
var sub_l: Label
var preco_l: Label
var saldo_l: Label
var comprar_b: Button
var _giro := 0.0
var _foto := OS.get_environment("DROPS_FOTO")
var _fotos_tiradas := {}

const PAREDE_Z := -3.0
const LOGO_TAM := Vector2(4.2, 3.0)


func _ready() -> void:
	if Dados.modo != "historia":
		Dados.entrar_historia()
	lista = Dados.a_venda()
	_sala()
	_logo()
	_drops()
	_carro_expo()
	_ui()
	cam = Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.current = true
	_camera(0.0)
	if not OS.has_environment("DROPS_TESTE"):
		Dados.tocar_musica(true)
	if OS.has_environment("DROPS_TESTE_NOVO"):
		print("novo: abertura aberta, dinheiro=", Dados.dinheiro, " garagem=", Dados.historia.get("garagem"), " etapa=", Dados.historia.get("etapa"))
		get_tree().quit()


# ---------------------------------------------------------------- cenário
func _mat(cor: Color, rug := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = cor
	m.roughness = rug
	m.metallic = metal
	return m


func _caixa(tam: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = tam
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _sala() -> void:
	CarroVisual.usar_reflexo("res://imagens/reflexo/estudio.png", 1.0)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0a0a0c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("6c707c")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# chão de loja (claro e brilhante) e a parede preta do fundo, onde vai a logo
	var chao := _mat(Color("d9d9d6"), 0.18, 0.0)
	_caixa(Vector3(16, 0.1, 14), Vector3(0, -0.05, 2.0), chao)
	_caixa(Vector3(16, 6, 0.2), Vector3(0, 3, PAREDE_Z - 0.1), _mat(Color("141416"), 0.9))
	_caixa(Vector3(0.2, 6, 14), Vector3(-8, 3, 2), _mat(Color("e9e9e6"), 0.85))
	_caixa(Vector3(0.2, 6, 14), Vector3(8, 3, 2), _mat(Color("e9e9e6"), 0.85))
	# faixa amarela no rodapé
	var am := _mat(AMARELO, 0.5)
	_caixa(Vector3(16, 0.25, 0.05), Vector3(0, 0.125, PAREDE_Z + 0.02), am)
	# luzes: refletor na parede (a logo), luz do salão e um contra-luz
	var sp := SpotLight3D.new()
	sp.position = Vector3(0, 5.2, 0.8)
	sp.look_at_from_position(sp.position, Vector3(0, 2.3, PAREDE_Z), Vector3.UP)
	sp.spot_range = 12.0
	sp.spot_angle = 42.0
	sp.light_energy = 2.6
	sp.shadow_enabled = true
	add_child(sp)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-50, 30, 0)
	sol.light_energy = 0.7
	sol.shadow_enabled = true
	add_child(sol)
	var o := OmniLight3D.new()
	o.position = Vector3(2.5, 3.0, 4.0)
	o.omni_range = 10.0
	o.light_energy = 1.2
	add_child(o)


## a logo da Drops na parede: aparece aos poucos, seguindo o jato da pistola
func _logo() -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = LOGO_TAM
	q.mesh = qm
	q.position = Vector3(0, 2.35, PAREDE_Z + 0.005)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D logo : source_color, filter_linear_mipmap;
uniform float revela = 0.0;   // 0..1: quanto da logo já foi pintado (da esquerda pra direita, em faixas)
uniform vec2 bico = vec2(-1.0); // onde o jato está batendo agora (uv)
float ruido(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec4 c = texture(logo, UV);
	// logo limpa (imagens/logo_drops_parede.png): amarelo, branco e o contorno preto, o resto transparente
	float tinta = c.a;
	// pintado em 4 faixas, de cima pra baixo, indo e voltando como uma demão
	float faixas = 4.0;
	float linha = floor(UV.y * faixas);
	float x = mod(linha, 2.0) < 0.5 ? UV.x : 1.0 - UV.x;
	float feito = (linha + x) / faixas;
	float borda = (ruido(floor(UV * 140.0)) - 0.5) * 0.02;
	float a = tinta * smoothstep(feito - 0.004, feito + 0.004, revela + borda);
	// tinta fresca brilha um pouco perto do jato
	float perto = 1.0 - smoothstep(0.0, 0.12, distance(UV, bico));
	ALBEDO = c.rgb * 0.82;   // tinta fosca: não estoura de branco embaixo do refletor
	ROUGHNESS = mix(0.8, 0.3, perto);
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""
	logo_mat = ShaderMaterial.new()
	logo_mat.shader = sh
	logo_mat.set_shader_parameter("logo", load("res://imagens/logo_drops_parede.png"))
	q.material_override = logo_mat
	add_child(q)


func _drops() -> void:
	drops = Pessoa.criar("res://modelos/personagens/protagonista.glb", 1.78)
	add_child(drops)
	Pessoa.vestir(drops, VISUAL_DROPS)
	drops.position = Vector3(-0.2, 0, PAREDE_Z + 1.45)
	drops.rotation.y = PI          # de costas pra câmera, olhando a parede
	anim = drops.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_tocar("Idle_Torch")
	# pistola na mão esquerda (a mesma do jogo), com a névoa amarela
	var esq := drops.find_child("Skeleton3D", true, false) as Skeleton3D
	if esq and esq.find_bone("hand_l") >= 0:
		var ba := BoneAttachment3D.new()
		ba.bone_name = "hand_l"
		esq.add_child(ba)
		pistola = Ferramenta.criar("pistola", AMARELO, true)
		ba.add_child(pistola)
		Ferramenta.soltar(pistola, true)


func _tocar(nome: String) -> void:
	if anim == null:
		return
	for n in ["drops/" + nome, nome]:
		if anim.has_animation(n):
			if anim.current_animation != n:
				anim.play(n, 0.3)
			return


## o carro em exposição (aparece na loja, do lado do Drops)
func _carro_expo() -> void:
	var giro := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.7
	cm.bottom_radius = 2.7
	cm.height = 0.06
	giro.mesh = cm
	giro.material_override = _mat(Color("1a1a1e"), 0.3, 0.3)
	giro.position = Vector3(2.6, 0.03, 0.9)
	add_child(giro)
	var aro := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.66
	tm.outer_radius = 2.74
	aro.mesh = tm
	var ma := _mat(AMARELO, 0.4)
	ma.emission_enabled = true
	ma.emission = AMARELO
	ma.emission_energy_multiplier = 1.5
	aro.material_override = ma
	aro.position = Vector3(2.6, 0.065, 0.9)
	add_child(aro)


func _mostrar_carro() -> void:
	if carro_vis:
		carro_vis.queue_free()
	if lista.is_empty():
		return
	var i: int = lista[k]
	var d: Dictionary = Dados.carros[i]
	carro_vis = CarroVisual.new()
	add_child(carro_vis)
	carro_vis.position = Vector3(2.6, 0.06, 0.9)
	carro_vis.montar(d, Dados.cfg(i))
	nome_l.text = str(d["nome"])
	sub_l.text = str(d.get("sub", "")).to_upper()
	var preco := int(d.get("preco", 0))
	var tem := Dados.tem_carro(str(d["id"]))
	preco_l.text = "JÁ É SEU" if tem else Dados.reais(preco)
	saldo_l.text = "Seu dinheiro: " + Dados.reais(Dados.dinheiro)
	comprar_b.disabled = tem or Dados.dinheiro < preco
	comprar_b.text = "COMPRAR" if Dados.dinheiro >= preco or tem else "SEM DINHEIRO"


# ---------------------------------------------------------------- tela
func _estilo(cor: Color, borda: Color, r := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = cor
	s.border_color = borda
	s.set_border_width_all(2)
	s.set_corner_radius_all(r)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _botao(texto: String, amarelo := false, fonte := 20) -> Button:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", fonte)
	var cor := AMARELO if amarelo else Color(0.05, 0.05, 0.07, 0.85)
	var borda := AMARELO if amarelo else Color(1, 1, 1, 0.4)
	for est in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(est, _estilo(cor.darkened(0.4) if est == "disabled" else cor, borda))
	var fc := Color("111111") if amarelo else Color.WHITE
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, fc)
	b.custom_minimum_size = Vector2(0, 54)
	return b


func _ui() -> void:
	var camada := CanvasLayer.new()
	add_child(camada)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camada.add_child(ui)
	# legenda da fala do Drops (embaixo, como filme)
	legenda = Label.new()
	legenda.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	legenda.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legenda.add_theme_font_size_override("font_size", 24)
	legenda.add_theme_color_override("font_outline_color", Color.BLACK)
	legenda.add_theme_constant_override("outline_size", 10)
	legenda.visible = false
	ui.add_child(legenda)
	var pular := _botao("PULAR ›", false, 18)
	pular.name = "pular"
	pular.pressed.connect(_pular)
	ui.add_child(pular)
	# loja do primeiro carro (direita)
	painel = PanelContainer.new()
	painel.add_theme_stylebox_override("panel", _estilo(Color(0.04, 0.04, 0.06, 0.9), Color(1, 1, 1, 0.35), 18))
	painel.visible = false
	ui.add_child(painel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	painel.add_child(v)
	var tit := Label.new()
	tit.text = "SEU PRIMEIRO CARRO"
	tit.add_theme_font_size_override("font_size", 18)
	tit.add_theme_color_override("font_color", AMARELO)
	v.add_child(tit)
	nome_l = Label.new()
	nome_l.add_theme_font_size_override("font_size", 38)
	v.add_child(nome_l)
	sub_l = Label.new()
	sub_l.add_theme_font_size_override("font_size", 15)
	sub_l.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	v.add_child(sub_l)
	preco_l = Label.new()
	preco_l.add_theme_font_size_override("font_size", 34)
	preco_l.add_theme_color_override("font_color", Color("7dff8a"))
	v.add_child(preco_l)
	saldo_l = Label.new()
	saldo_l.add_theme_font_size_override("font_size", 16)
	v.add_child(saldo_l)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	v.add_child(nav)
	var ant := _botao("‹", false, 28)
	ant.custom_minimum_size = Vector2(70, 54)
	ant.pressed.connect(func(): _passar(-1))
	nav.add_child(ant)
	comprar_b = _botao("COMPRAR", true, 22)
	comprar_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comprar_b.pressed.connect(_comprar)
	nav.add_child(comprar_b)
	var prox := _botao("›", false, 28)
	prox.custom_minimum_size = Vector2(70, 54)
	prox.pressed.connect(func(): _passar(1))
	nav.add_child(prox)
	var livre := _botao("VOLTAR PRO MODO LIVRE", false, 14)
	livre.pressed.connect(func():
		Dados.sair_historia()
		get_tree().change_scene_to_file("res://cenas/garagem.tscn"))
	v.add_child(livre)
	_posicionar()
	get_viewport().size_changed.connect(_posicionar)


func _posicionar() -> void:
	var tt := get_viewport().get_visible_rect().size
	painel.size = Vector2(clampf(tt.x * 0.34, 360.0, 460.0), 0)
	painel.position = Vector2(tt.x - painel.size.x - 28, tt.y * 0.5 - 170)
	legenda.size = Vector2(tt.x - 80, 90)
	legenda.position = Vector2(40, tt.y - 120)
	var p := ui.get_node("pular") as Control
	p.position = Vector2(tt.x - 150, 24)


func _passar(passo: int) -> void:
	if lista.is_empty():
		return
	k = posmod(k + passo, lista.size())
	_mostrar_carro()


func _comprar() -> void:
	if lista.is_empty():
		return
	if Dados.comprar(lista[k]):
		legenda.text = "Fechado! A " + str(Dados.carros[lista[k]]["nome"]) + " é tua. Leva pra oficina e capricha!"
		legenda.visible = true
		painel.visible = false
		fase = "comprou"
		t = 0.0


func _pular() -> void:
	if fase in ["pinta", "vira", "fala"]:
		logo_mat.set_shader_parameter("revela", 1.0)
		_abrir_loja()


func _abrir_loja() -> void:
	fase = "loja"
	t = 0.0
	if pistola:
		Ferramenta.soltar(pistola, false)
		pistola.visible = false
	drops.rotation.y = 0.35
	drops.position = Vector3(-0.6, 0, PAREDE_Z + 2.4)   # sai da frente da parede pra perto do carro
	_tocar("Idle")
	legenda.text = FALA
	legenda.visible = true
	painel.visible = true
	(ui.get_node("pular") as Control).visible = false
	_mostrar_carro()


# ---------------------------------------------------------------- roteiro
func _process(dt: float) -> void:
	t += dt
	match fase:
		"pinta":
			var r := clampf(t / T_PINTA, 0.0, 1.0)
			logo_mat.set_shader_parameter("revela", r)
			# o corpo varre de um lado pro outro acompanhando a faixa que está sendo pintada
			var faixa := floorf(r * 4.0)
			var x := fposmod(r * 4.0, 1.0)
			if int(faixa) % 2 == 1:
				x = 1.0 - x
			logo_mat.set_shader_parameter("bico", Vector2(x, (faixa + 0.5) / 4.0))
			drops.rotation.y = PI + (x - 0.5) * 0.7
			if r >= 1.0:
				fase = "vira"
				t = 0.0
				if pistola:
					Ferramenta.soltar(pistola, false)
				_tocar("Idle")
		"vira":
			var e := clampf(t / T_VIRA, 0.0, 1.0)
			e = e * e * (3.0 - 2.0 * e)
			drops.rotation.y = lerp_angle(PI, 0.0, e)
			if e >= 1.0:
				fase = "fala"
				t = 0.0
				if pistola:
					pistola.visible = false
				legenda.text = FALA
				legenda.visible = true
		"fala":
			if t > 3.0:
				_abrir_loja()
		"loja":
			if carro_vis:
				_giro += dt * 0.35
				carro_vis.rotation.y = _giro
		"comprou":
			if t > 2.5:
				get_tree().change_scene_to_file("res://cenas/garagem.tscn")
	_camera(dt)
	_testes()


## câmera: atrás do Drops vendo a logo; depois afasta pra mostrar ele, a logo e o carro
func _camera(dt: float) -> void:
	var pos: Vector3
	var alvo: Vector3
	match fase:
		"pinta":
			var e := clampf(t / T_PINTA, 0.0, 1.0)
			pos = Vector3(-1.4, 1.9, 2.6).lerp(Vector3(0.6, 1.7, 3.3), e)
			alvo = Vector3(0, 2.1, PAREDE_Z)
		"vira", "fala":
			pos = Vector3(0.2, 1.6, 2.4)
			alvo = Vector3(-0.2, 1.45, PAREDE_Z + 1.45)
		_:
			pos = Vector3(1.6, 2.1, 7.4)
			alvo = Vector3(1.4, 1.1, 0.4)
	if dt <= 0.0:
		cam.global_position = pos
	else:
		cam.global_position = cam.global_position.lerp(pos, 1.0 - exp(-dt * 2.5))
	cam.look_at(alvo, Vector3.UP)
	# na loja o painel fica na direita: o carro e o Drops vão pro meio da parte livre da tela
	cam.h_offset = lerpf(cam.h_offset, 1.5 if fase in ["loja", "comprou"] else 0.0, 1.0 - exp(-maxf(dt, 0.0) * 3.0))


## testes automáticos: DROPS_FOTO=/tmp/x_%s.png tira foto de cada fase; DROPS_COMPRAR=1 compra o primeiro
func _testes() -> void:
	if _foto == "":
		return
	var marcas := {"pinta_meio": fase == "pinta" and t > T_PINTA * 0.5, "vira": fase == "fala" and t > 0.3,
		"loja": fase == "loja" and t > 1.5}
	for nome in marcas:
		if marcas[nome] and not _fotos_tiradas.has(nome):
			_fotos_tiradas[nome] = true
			get_viewport().get_texture().get_image().save_png(_foto % nome)
			if nome == "loja":
				if OS.has_environment("DROPS_COMPRAR"):
					_comprar()
				else:
					get_tree().quit()
