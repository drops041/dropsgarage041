class_name Rua
extends Node3D
## Drops Garage Racha — o rolê na cidade
## Sai da Drops, volante na tela, suspensão a ar, lombadas que raspam, drift com fumaça e câmera livre.
## Teclado: W/S ou setas acelera/freia, A/D vira, Espaço drift, Q/E sobe/desce a suspensão, C troca de carro, V volta a câmera.

const AMARELO := Color("ffd400")
## mapa novo: Cidade Industrial de Curitiba (OpenStreetMap). As posições antigas abaixo
## (delegacia, posto, hangar) são do mapa velho e são "levadas" pro lugar real.
const SAIDA_LOCAL := Vector3(3.0, 0.6, 18.2)           # dentro da oficina da Drops, no fundo do corredor (coordenada local da fachada)
const CARRO_PARADO_LOCAL := Vector3(0.1, 0.0, 18.6)    # o outro carro estacionado do lado (igual na foto)
const CAM_SAIDA_LOCAL := Vector3(1.0, 1.5, 12.2)       # câmera começa de frente pro carro, no corredor
const CAM_SAIDA_FIM := Vector3(3.6, 2.3, 9.0)
const DEL_LOMBADA_VELHA := Vector3(-60, 0, 0)          # lombada na frente da delegacia (mapa velho)
const POLICIAL := Vector3(-56.4, 0.0, -9.3)   # ao lado da lombada da Rua da Oficina (u = -60), na frente da delegacia
const LOMB_H := 0.095     # altura da lombada (m)
const LOMB_L := 0.95      # meio-comprimento (m)
const AR_MIN := -8.0      # suspensão: 8 cm acima do original
var AR_MAX := 18.0        # até onde o carro baixa (aterrado) — muda por carro: CarroVisual.rebaixo_max

var dados: Dictionary
var cfg: Dictionary
var carro: VehicleBody3D
var visual: CarroVisual
var rodas: Array[VehicleWheel3D] = []
var cam: Camera3D
var musica: AudioStreamPlayer
var hud: CanvasLayer
var botoes := {}
var virado_t := 0.0
var cam_pos := Vector3.ZERO
var cam_yaw := 0.0          # câmera girada pelo dedo: fica onde você deixou
var intro := 0.0            # saindo da oficina
var lombadas: Array = []    # [cx, cz, dx, dz, meia_largura]
var mapa: MapaCIC
var rede := RedeCIC.new()
var del_xf := Transform3D.IDENTITY   # mapa velho -> lugar real da delegacia
var minimapa: Control
var rua_label: Label
var rua_atual := ""
var rua_t := 0.0
var _intro_freio := false
var mapa_aberto := false
var mapa_ui: Control
var mapa_tela: Control
var mapa_zoom := 0.8          # pixels de tela por metro
var mapa_centro := Vector2.ZERO
var gps = null                # Vector3 do destino marcado no mapa (ou null)
var gps_feixe: MeshInstance3D
var _mt := {}                 # toques no mapa grande
var _mt_dist := 0.0
var _mt_mexeu := 0.0
var vel_label: Label
var rebaixo := 10.0         # cm (suspensão a ar)
var ar_alvo := 10.0
var rebaixo_t := 10.0       # traseira (a dianteira é o "rebaixo")
var ar_alvo_t := 10.0
var eixo := 0               # 0 = as duas, 1 = só a dianteira, 2 = só a traseira
var rodas_vis: Array[Node3D] = []   # roda que aparece (separada da roda da física)
var giro_roda := 0.0
var ar_dir := 0
var ar_painel: Control
var cel_topo: VBoxContainer
var cel_mao: Control
var ar_label: Label
var toast_l: Label
var toast_t := 0.0
var raspa_msg_t := -99.0
var faisca: CPUParticles3D
var fumaca: Array[CPUParticles3D] = []
var som_ar: AudioStreamPlayer
var som_raspa: AudioStreamPlayer3D
var raspa_som_t := 0.0
var ar_som_t := 0.0
var tremor := 0.0
var volante: TextureRect
var vol_id := -1
var vol_ang := 0.0
var vol_ultimo := 0.0
var arrasto_id := -1
var tempo := 0.0
var pe := false             # andando a pé
var congelado := false      # contagem de desafio
var sonda: ReflectionProbe
var _na_oficina := false
var foto := false           # modo foto
var foto_ui: Control
var foto_yaw := 0.0
var foto_pitch := 0.15
var foto_dist := 5.5
var foto_previa: TextureRect
var foto_aviso: Label
var role: Node
var policia: Policia
var pessoa: Pessoa
var oficina: Oficina
var barracao: Barracao         # (v34) evento dos carros novos no barracão do lado da Drops
var sol_luz: DirectionalLight3D
var elev_y := 0.0
# v32: movimento liso — a física roda em passos fixos; o que aparece (lataria/rodas/câmera) é interpolado entre os passos
var corpo_vis: Node3D
var _xf_ant := Transform3D()
var _xf_cur := Transform3D()
var _tem_xf := false
var xf_liso := Transform3D()
var usar_cam_teste := false
var cam_teste := Transform3D()                  # quanto o elevador da oficina levantou o carro
var ape_yaw := 0.0
var stick: Control
var stick_bola: TextureRect
var stick_id := -1
var stick_v := Vector2.ZERO
var pe_botoes: HBoxContainer
var partes_box: HBoxContainer
var carro_hud: Array = []
var _teste := OS.has_environment("DROPS_TESTE")
var _f := 0


func _ready() -> void:
	var _t_ini := Time.get_ticks_msec()
	CarroVisual.detalhe_total = false
	_ambiente()
	_cidade()
	if OS.has_environment("DROPS_TEMPO"):
		print("tempo cidade: ", Time.get_ticks_msec() - _t_ini, " ms")
	_predios()
	_lombadas()
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 700.0
	add_child(cam)
	cam.current = true
	musica = Dados.musica
	som_ar = AudioStreamPlayer.new()
	som_ar.stream = _som("res://audio/suspensao.mp3", true)
	if som_ar.stream == null:
		som_ar.stream = _ruido(0.55, 0.9, 5200.0)
	som_ar.volume_db = -4.0
	add_child(som_ar)
	_efeitos()
	_hud()
	var fs := mapa.drops_xf.basis * Vector3(0, 0, -1)
	_criar_carro(mapa.drops_ponto(SAIDA_LOCAL), atan2(fs.x, fs.z))
	mapa.alvo = carro
	intro = 2.5
	oficina = Oficina.new()
	oficina.name = "Oficina"
	oficina.m = self
	add_child(oficina)
	if OS.has_environment("DROPS_TUTORIAL"):   # (v37) as dicas gerais não abrem mais sozinhas; ficam só as da oficina
		hud.add_child(Tutorial.new())
	barracao = Barracao.new()
	barracao.name = "Barracao"
	barracao.m = self
	add_child(barracao)
	# (carro parado na oficina tirado a pedido: a oficina fica livre pra manobrar)
	_hud_mapa()
	policia = Policia.new()
	policia.name = "Policia"
	add_child(policia)
	policia.montar(self)
	role = load("res://scripts/role.gd").new()
	add_child(role)
	role.iniciar(self)
	get_viewport().size_changed.connect(_posicionar_botoes)


# ---------------------------------------------------------------- fim de tarde
func _ambiente() -> void:
	CarroVisual.usar_reflexo("res://imagens/reflexo/rua.png", 0.75)   # o carro reflete o céu de fim de tarde e as casas
	var env := Environment.new()
	# fim de tarde: céu alaranjado no horizonte, azul em cima, sol baixo
	var ceu := ProceduralSkyMaterial.new()
	ceu.sky_top_color = Color("3d5f9e")
	ceu.sky_horizon_color = Color("f2a56b")
	ceu.sky_curve = 0.12
	ceu.ground_horizon_color = Color("b8826a")
	ceu.ground_bottom_color = Color("3a3036")
	ceu.sun_angle_max = 12.0
	ceu.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = ceu
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a8a097")     # neutro/quente: o azul do céu deixava asfalto e calçada azulados
	env.ambient_light_energy = 0.72
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.88
	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.3
	env.ssr_enabled = false         # sem reflexo das luzes no asfalto
	env.ssao_enabled = true
	env.ssao_intensity = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color("c9a58e")
	env.fog_sun_scatter = 0.25
	env.fog_density = 0.0009
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# reflexo da rua na lataria do seu carro (vai junto com ele)
	sonda = ReflectionProbe.new()
	sonda.size = Vector3(60, 20, 60)
	sonda.update_mode = ReflectionProbe.UPDATE_ALWAYS
	sonda.intensity = 0.9
	sonda.max_distance = 80.0
	if RenderingServer.get_rendering_device() != null:  # reflexo só no Forward+ (no modo compatível fica preto)
		add_child(sonda)
	var sol := DirectionalLight3D.new()   # sol de fim de tarde, baixo e alaranjado
	sol.light_color = Color("ffb27a")
	sol.light_energy = 1.15
	# a cidade não faz sombra (bem mais leve e sem travada); quem faz sombra é o carro e as pessoas,
	# então a sombra fica curta e bem nítida. No celular continua sem sombra (tem a sombra de contato).
	sol.shadow_enabled = false   # sem sombra do sol (pesava); o carro tem a sombra de contato embaixo dele
	sol.directional_shadow_max_distance = 45.0
	sol.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sol.shadow_blur = 1.5
	sol.rotation_degrees = Vector3(-16, -62, 0)
	sol.light_cull_mask = 0xFFFFF & ~(1 << (Barracao.CAMADA_DENTRO - 1))   # o sol não ilumina o lado de dentro do barracão
	add_child(sol)
	sol_luz = sol
	sol.shadow_enabled = Dados.grafico_alto()


## (v33) qualidade do gráfico: ALTO (padrão) = 3D na resolução cheia da tela, antisserrilhado 4x de verdade,
## sombra dos carros e das pessoas, carros com mais detalhe. LEVE = o modo antigo do celular (75%, sem sombra).
func aplicar_graficos() -> void:
	var vp := get_viewport()
	var alto := Dados.grafico_alto()
	if alto:
		vp.scaling_3d_scale = 1.0
		vp.msaa_3d = Viewport.MSAA_4X
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED   # o FXAA borrava as texturas; o MSAA já tira o serrilhado
	elif Dados.leve():
		vp.scaling_3d_scale = 0.75
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	else:
		vp.scaling_3d_scale = 1.0
		vp.msaa_3d = Viewport.MSAA_2X
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	if sol_luz:
		sol_luz.shadow_enabled = alto    # só carro, gente e árvore fazem sombra (a cidade não), até 45 m
	CarroVisual.lod_extra = 2.5 if alto else 1.0


# ---------------------------------------------------------------- cidade + colisão
func _cidade() -> void:
	mapa = MapaCIC.new()
	mapa.name = "MapaCIC"
	mapa.luzes_dos_postes = false   # fim de tarde: as lâmpadas acendem (brilho), sem luz extra pesada no modo compatível
	if Dados.leve():   # celular: carrega menos em volta
		mapa.raio_carregar = 480.0
		mapa.raio_descarregar = 640.0
		if not Dados.grafico_alto():   # gráfico leve: árvores e postes somem mais perto
			mapa.distancia_arvores = 260.0
			mapa.distancia_arvore_real = 55.0
			mapa.distancia_postes = 180.0
			mapa.max_luzes = 5
	aplicar_graficos()
	if OS.has_environment("DROPS_SEMARV"):
		mapa.distancia_arvore_real = 0.01
	add_child(mapa)
	rede.carregar("res://mapa_cic/ruas.json")
	mapa.carregar_perto(mapa.posicao_spawn())


func _tem_pintura(m: MeshInstance3D) -> bool:
	if str(m.name).begins_with("PAINT") or str(m.get_parent().name).begins_with("PAINT"):
		return true
	for i in m.mesh.get_surface_count():
		var mat := m.mesh.surface_get_material(i)
		if mat and mat.resource_name.get_slice("__", 0) == "PAINT":
			return true
	return false


func _caixa_de(n: Node) -> AABB:
	var cx := AABB()
	var primeira := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.get_aabb()
		cx = b if primeira else cx.merge(b)
		primeira = false
	return cx


# ---------------------------------------------------------------- posto, hangar, delegacia e o policial
var policial: Node3D
var balao: Label3D
var balao_t := 0.0
var piazada_t := -99.0


func _predio(arq: String, pos: Vector3, giro: float, escala: float, esconder: Array = [], sem_colisao: Array = [], chao_colide := false, alcance := 0.0) -> Node3D:
	if not ResourceLoader.exists(Dados.modelo(arq)):
		return null
	var n: Node3D = load(Dados.modelo(arq)).instantiate()
	add_child(n)
	n.position = pos
	n.rotation.y = giro
	n.scale = Vector3.ONE * escala
	if alcance > 0.0 and not Dados.leve():   # longe da câmera não desenha
		for gi in n.find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).visibility_range_end = alcance
			(gi as GeometryInstance3D).visibility_range_end_margin = 15.0
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var nome := str(m.name) + " " + str(m.get_parent().name)
		var some := false
		for e in esconder:
			if nome.contains(e):
				some = true
		if some:
			m.visible = false
			continue
		if m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.get_aabb()
		if b.size.length() < 0.5 or (b.size.y < 0.12 and b.position.y < 0.2 and not chao_colide):
			continue
		var pula := false
		for e in sem_colisao:
			if nome.contains(e):
				pula = true
		if pula:
			continue   # chão: a física usa o chão reto da cidade (sem degrau)
		var corpo := StaticBody3D.new()
		var col := CollisionShape3D.new()
		col.shape = m.mesh.create_trimesh_shape()
		corpo.add_child(col)
		add_child(corpo)
		corpo.global_transform = m.global_transform
	if Dados.leve():
		Dados.juntar(n, 0.0, true)
		if alcance > 0.0:
			for gi in n.find_children("*", "GeometryInstance3D", true, false):
				(gi as GeometryInstance3D).visibility_range_end = alcance
	return n


func _predios() -> void:
	# posto (no lugar do posto de verdade do mapa)
	if mapa.tem("posto"):
		var px := mapa.xf("posto")
		if _predio("res://modelos/cenario/posto.glb", px.origin + Vector3(0, 0.035, 0), px.basis.get_euler().y, 0.65, [], [], true, 260.0) != null:
			for lx in [-3.5, 3.5]:   # luz da cobertura das bombas
				var lp := OmniLight3D.new()
				lp.light_color = Color("f4f7ff")
				lp.light_energy = 2.4
				lp.omni_range = 15.0
				lp.position = px * Vector3(lx, 3.6, -0.7)
				add_child(lp)
	# encontro: galpão aberto num terrenão de verdade, de frente pra rua
	if mapa.tem("hangar"):
		_galpao(mapa.xf("hangar"))
	# (v37) concessionária DROPS CAR feita no próprio jogo (o modelo antigo vinha bugado e com logos de montadoras)
	if mapa.tem("concessionaria"):
		var cc := Concessionaria.new()
		cc.name = "Concessionaria"
		cc.m = self
		add_child(cc)
	# delegacia "É o Frank": no lugar da PMPR do mapa, com a lombada e o policial na frente
	del_xf = _xf_delegacia()
	var esc := float(mapa.dados["delegacia"].get("escala", 1.0)) if mapa.tem("delegacia") else 1.0
	var dl := del_xf * Vector3(-60, -1.2 * esc, -6.4)   # o pátio do prédio fica 1,2 m acima da base do modelo
	if _predio("res://modelos/cenario/delegacia_frank.glb", dl, del_xf.basis.get_euler().y, esc, [], [], false, 300.0) != null:
		_placa_delegacia(Transform3D(del_xf.basis.scaled(Vector3.ONE * esc), dl))
	_predio("res://modelos/cenario/viatura.glb", del_xf * Vector3(-74.0, 0.02, -15.0), 0.25 + del_xf.basis.get_euler().y, 1.0, [], [], false, 120.0)
	# o policial
	policial = Node3D.new()
	add_child(policial)
	policial.position = del_xf * POLICIAL
	policial.rotation.y = del_xf.basis.get_euler().y   # olhando pra rua
	var mod := Pessoa.criar(Policia.ARQ_POLICIAL, 1.8)
	policial.add_child(mod)
	var ap := mod.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap and ap.has_animation("drops/parado"):
		ap.play("drops/parado")
	balao = Label3D.new()
	balao.text = "PIAZADA DO DIABO!"
	balao.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	balao.font_size = 72
	balao.outline_size = 18
	balao.modulate = Color("ffd400")
	balao.outline_modulate = Color(0, 0, 0)
	balao.pixel_size = 0.006
	balao.position = Vector3(0, 2.45, 0)
	balao.no_depth_test = true
	balao.visible = false
	policial.add_child(balao)
	_chao_do_policial.call_deferred()


## leva o "mapa velho" da delegacia (lombada em x = -60 na rua z = 0) pro lugar real
## nome da delegacia: no lugar do letreiro do prédio e numa placa azul na grade da frente
func _placa_delegacia(x: Transform3D) -> void:
	var fachada := Label3D.new()
	fachada.text = "DELEGACIA É O FRANK"
	fachada.font_size = 160
	fachada.outline_size = 18
	fachada.pixel_size = 0.0065 * x.basis.get_scale().x
	fachada.modulate = Color(0.12, 0.25, 0.62)
	fachada.outline_modulate = Color(1, 1, 1)
	fachada.position = x * Vector3(-5.6, 1.2 + 9.6, -19.75)
	fachada.rotation.y = x.basis.orthonormalized().get_euler().y
	add_child(fachada)
	var placa := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(7.0, 1.3, 0.08)
	placa.mesh = bx
	var mp := StandardMaterial3D.new()
	mp.albedo_color = Color(0.08, 0.2, 0.55)
	mp.roughness = 0.5
	placa.material_override = mp
	placa.position = x * Vector3(-9.0, 1.2 + 3.4, 0.25)
	placa.rotation.y = x.basis.orthonormalized().get_euler().y
	add_child(placa)
	var t := Label3D.new()
	t.text = "POLÍCIA CIVIL\nDELEGACIA É O FRANK"
	t.font_size = 72
	t.outline_size = 0
	t.pixel_size = 0.007
	t.modulate = Color(1, 1, 1)
	t.position = Vector3(0, 0, 0.05)
	placa.add_child(t)


## galpão aberto do encontro: piso de concreto, pilares de aço e telhado de duas águas (sem parede)
const GALPAO_X := 26.0
const GALPAO_Z := 33.0
var galpao_xf := Transform3D.IDENTITY
var som_galpao: AudioStreamPlayer3D
func _galpao(hx: Transform3D) -> void:
	galpao_xf = hx
	var raiz := Node3D.new()
	raiz.name = "Galpao"
	add_child(raiz)
	raiz.transform = hx
	var aco := StandardMaterial3D.new()
	aco.albedo_color = Color(0.2, 0.21, 0.23)
	aco.metallic = 0.6
	aco.roughness = 0.45
	var telha := StandardMaterial3D.new()
	telha.albedo_color = Color(0.62, 0.64, 0.66)
	telha.metallic = 0.5
	telha.roughness = 0.5
	telha.cull_mode = BaseMaterial3D.CULL_DISABLED
	var conc := StandardMaterial3D.new()
	conc.albedo_color = Color(0.56, 0.56, 0.55)
	conc.roughness = 0.75
	var faixa := StandardMaterial3D.new()
	faixa.albedo_color = Color(1.0, 0.82, 0.1)
	faixa.roughness = 0.6
	var luz := StandardMaterial3D.new()
	luz.albedo_color = Color(1, 1, 1)
	luz.emission_enabled = true
	luz.emission = Color(1.0, 0.95, 0.85)
	luz.emission_energy_multiplier = 3.0
	var caixa := func(tam: Vector3, pos: Vector3, mat: Material, giro := Vector3.ZERO, colide := false) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = tam
		mi.mesh = bm
		mi.material_override = mat
		mi.position = pos
		mi.rotation = giro
		mi.visibility_range_end = 400.0
		raiz.add_child(mi)
		if colide:
			var sb := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = tam
			cs.shape = sh
			sb.add_child(cs)
			sb.position = pos
			sb.rotation = giro
			raiz.add_child(sb)
	var BEIRAL := 8.5
	var CUMEEIRA := 11.5
	# piso (um pouco acima do chão) com faixa amarela na borda
	var hmin := 1e9
	var hmax := -1e9
	for ix in range(-8, 9):
		for iz in range(-10, 11):
			var pg := hx * Vector3(ix * (GALPAO_X + 0.5) / 8.0, 0, iz * (GALPAO_Z + 0.5) / 10.0)
			var hh := mapa.altura(pg.x, pg.z) - hx.origin.y
			hmin = minf(hmin, hh)
			hmax = maxf(hmax, hh)
	# v32: piso sólido (com colisão), rente ao terreno: antes ele ficava 10 cm acima do chão de verdade
	# e o carro/pessoa afundava nele (o chão que segurava era o terreno lá embaixo)
	var topo_piso := hmax + 0.025
	caixa.call(Vector3(GALPAO_X * 2.0 + 1.0, 0.5, GALPAO_Z * 2.0 + 1.0), Vector3(0, topo_piso - 0.25, 0), conc, Vector3.ZERO, true)
	for s in [-1.0, 1.0]:
		caixa.call(Vector3(0.25, 0.01, GALPAO_Z * 2.0), Vector3(s * (GALPAO_X - 1.2), topo_piso + 0.004, 0), faixa)
	# paredes: laterais com as fotos dos projetos (até 4,5 m, em cima fica aberto) e o fundo com a logo da Drops
	var reboco := StandardMaterial3D.new()
	reboco.albedo_color = Color(0.22, 0.22, 0.24)
	reboco.roughness = 0.9
	var ALT_PAREDE := 4.5
	var painel := func(tex: String, tam: Vector2, pos: Vector3, giro_y: float) -> void:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = tam
		q.mesh = qm
		var mt := StandardMaterial3D.new()
		mt.albedo_texture = load(tex)
		mt.roughness = 0.85
		mt.emission_enabled = true          # grafite aparece mesmo à noite (tinta "viva")
		mt.emission_texture = mt.albedo_texture
		mt.emission_energy_multiplier = 0.22
		mt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		q.material_override = mt
		q.position = pos
		q.rotation.y = giro_y
		q.visibility_range_end = 260.0
		raiz.add_child(q)
	for s in [-1.0, 1.0]:
		caixa.call(Vector3(0.3, ALT_PAREDE, GALPAO_Z * 2.0 + 0.6), Vector3(s * (GALPAO_X + 0.4), topo_piso + ALT_PAREDE / 2.0, 0), reboco, Vector3.ZERO, true)
	# (v38) paredes laterais só com as fotos dos projetos da Drops (sem grafite atrás), cada foto uma vez
	# (v40) painéis gigantes (7,2 m), cada um no meio de um vão entre pilares
	var fotos := [[-1.0, -20.62, 1], [-1.0, -4.12, 2], [-1.0, 12.38, 3], [1.0, -12.38, 4], [1.0, 4.12, 5]]   # lado, z, foto
	var alt_foto := 7.2
	for fq in fotos:
		var sx: float = fq[0]
		var qd := Barracao.quadro_foto("res://modelos/cenario/projeto_%d.jpg" % fq[2], alt_foto)
		raiz.add_child(qd)
		qd.position = Vector3(sx * (GALPAO_X + 0.18), topo_piso + 0.45 + alt_foto / 2.0, fq[1])
		qd.rotation.y = -sx * PI / 2.0
	caixa.call(Vector3(GALPAO_X * 2.0 + 1.1, BEIRAL, 0.3), Vector3(0, topo_piso + BEIRAL / 2.0, -GALPAO_Z - 0.4), reboco, Vector3.ZERO, true)
	painel.call("res://modelos/cenario/mural_drops.jpg", Vector2(GALPAO_X * 2.0, GALPAO_X * 2.0 * 340.0 / 2048.0), Vector3(0, topo_piso + GALPAO_X * 340.0 / 2048.0 + 0.1, -GALPAO_Z - 0.24), 0.0)
	# pilares e tesouras (pórticos a cada ~8 m)
	var n_port := 9
	for i in n_port:
		var z := -GALPAO_Z + i * (GALPAO_Z * 2.0) / (n_port - 1)
		for s in [-1.0, 1.0]:
			caixa.call(Vector3(0.45, BEIRAL, 0.45), Vector3(s * GALPAO_X, BEIRAL / 2.0, z), aco, Vector3.ZERO, true)
			var meio: Vector3 = Vector3(s * GALPAO_X / 2.0, (BEIRAL + CUMEEIRA) / 2.0, z)
			var incl: float = atan2(CUMEEIRA - BEIRAL, GALPAO_X)
			caixa.call(Vector3(GALPAO_X + 0.6, 0.45, 0.3), meio, aco, Vector3(0, 0, -s * incl))
			caixa.call(Vector3(GALPAO_X, 0.18, 0.2), Vector3(s * GALPAO_X / 2.0, BEIRAL + 0.2, z), aco)   # banzo de baixo
			for k in 4:   # diagonais da tesoura
				var xx: float = s * (k + 0.5) * GALPAO_X / 4.0
				var ytop: float = BEIRAL + (CUMEEIRA - BEIRAL) * (1.0 - absf(xx) / GALPAO_X)
				caixa.call(Vector3(0.12, ytop - BEIRAL, 0.12), Vector3(xx, (ytop + BEIRAL) / 2.0 + 0.1, z), aco)
	# telhado de duas águas
	var incl2 := atan2(CUMEEIRA - BEIRAL, GALPAO_X)
	var largura := sqrt(GALPAO_X * GALPAO_X + (CUMEEIRA - BEIRAL) * (CUMEEIRA - BEIRAL)) + 1.5
	for s in [-1.0, 1.0]:
		caixa.call(Vector3(largura, 0.06, GALPAO_Z * 2.0 + 3.0), Vector3(s * (GALPAO_X / 2.0 + 0.5), (BEIRAL + CUMEEIRA) / 2.0 + 0.35, 0), telha, Vector3(0, 0, -s * incl2))
	# calhas laterais (vigas ao longo do galpão)
	for s in [-1.0, 1.0]:
		caixa.call(Vector3(0.35, 0.5, GALPAO_Z * 2.0 + 1.0), Vector3(s * GALPAO_X, BEIRAL, 0), aco)
	# luminárias (sem luz de verdade pra não pesar: só 2 luzes no meio)
	for i in 6:
		var z := -GALPAO_Z + 6.0 + i * (GALPAO_Z * 2.0 - 12.0) / 5.0
		for x in [-9.0, 9.0]:
			caixa.call(Vector3(0.35, 0.08, 3.2), Vector3(x, BEIRAL - 0.1, z), luz)
	for z in [-12.0, 12.0]:
		var l := OmniLight3D.new()
		l.light_color = Color("ffe6c4")
		l.light_energy = 2.0
		l.omni_range = 28.0
		l.omni_attenuation = 0.8
		l.position = Vector3(0, BEIRAL - 0.6, z)
		raiz.add_child(l)
	# letreiro na frente
	var nome := Label3D.new()
	nome.text = "ENCONTRO DROPS GARAGE"
	nome.font_size = 200
	nome.outline_size = 24
	nome.pixel_size = 0.008
	nome.modulate = Color(1.0, 0.85, 0.15)
	nome.outline_modulate = Color(0, 0, 0)
	nome.position = Vector3(0, BEIRAL + 1.3, GALPAO_Z + 0.3)
	raiz.add_child(nome)
	# o som do encontro: Mega Funk tocando dentro do galpão (chegando perto você escuta)
	som_galpao = AudioStreamPlayer3D.new()
	som_galpao.stream = load("res://audio/mega_funk.mp3")
	if som_galpao.stream is AudioStreamMP3:
		(som_galpao.stream as AudioStreamMP3).loop = true
	som_galpao.unit_size = 14.0
	som_galpao.max_distance = 110.0
	som_galpao.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	som_galpao.volume_db = 4.0
	som_galpao.position = Vector3(0, 3.0, 0)
	som_galpao.autoplay = true
	raiz.add_child(som_galpao)


## música do jogo abaixa quando você chega no galpão (pra ouvir o som do encontro)
func _mixar_galpao() -> void:
	if som_galpao == null or Dados.musica == null:
		return
	var alvo: Node3D = pessoa if pe and pessoa else carro
	if alvo == null:
		return
	var d := alvo.global_position.distance_to(galpao_xf.origin)
	var f := clampf((d - 45.0) / 60.0, 0.0, 1.0)   # 0 dentro do galpão, 1 a mais de ~105 m
	var vol := lerpf(-40.0, 0.0, f)
	if oficina and oficina.dentro(alvo.global_position):
		vol = minf(vol, -14.0)   # na oficina: a música do jogo abaixa e dá pra ouvir a caixa de som
	if barracao and barracao.dentro(alvo.global_position):
		vol = minf(vol, -30.0)   # no barracão: o som do evento manda
	Dados.musica.volume_db = lerpf(Dados.musica.volume_db, vol, 0.08)


## carros na vitrine da concessionária (os mais novos)
func _xf_delegacia() -> Transform3D:
	if not mapa.tem("delegacia"):
		return Transform3D.IDENTITY
	var d: Dictionary = mapa.dados["delegacia"]
	var q := Vector3(d["rua"][0], float(d.get("nivel", 0.0)), d["rua"][2])
	var dir := Vector3(d["dir"][0], 0, d["dir"][2]).normalized()
	var lado := (Vector3(d["pos"][0], 0, d["pos"][2]) - q).normalized()
	var phi := atan2(-dir.z, dir.x)
	if (Basis(Vector3.UP, phi) * Vector3(0, 0, -1)).dot(lado) < 0.0:
		dir = -dir
		phi = atan2(-dir.z, dir.x)
	return Transform3D(Basis(Vector3.UP, phi), q) * Transform3D(Basis.IDENTITY, -DEL_LOMBADA_VELHA)


func _chao_do_policial() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var pp := del_xf * POLICIAL
	var q := PhysicsRayQueryParameters3D.create(pp + Vector3.UP * 3.0, pp + Vector3.DOWN * 1.0)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		policial.global_position.y = r["position"].y


## farda azul-marinho: pinta o corpo do modelo (do pescoço pra baixo) e põe um quepe
func _farda(mod: Node3D) -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float pescoco = 0.8;
varying float yy;
void vertex() { yy = VERTEX.y; }
void fragment() {
	vec3 c = texture(tex, UV).rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 farda = vec3(0.07, 0.11, 0.24) * (0.7 + l * 1.4);
	ALBEDO = yy < pescoco ? farda : c;
	ROUGHNESS = 0.85;
}
"""
	for mi in mod.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a := m.get_aabb()
		for i in m.mesh.get_surface_count():
			var orig := m.mesh.surface_get_material(i) as BaseMaterial3D
			var sm := ShaderMaterial.new()
			sm.shader = sh
			if orig:
				sm.set_shader_parameter("tex", orig.albedo_texture)
			sm.set_shader_parameter("pescoco", a.position.y + a.size.y * 0.83)
			m.set_surface_override_material(i, sm)
	# quepe na cabeça (preso no osso da cabeça pra acompanhar)
	var esq := mod.find_child("*", true, false) as Node
	for n in mod.find_children("*", "Skeleton3D", true, false):
		esq = n
	if esq is Skeleton3D:
		var sk := esq as Skeleton3D
		var osso := -1
		for b in sk.get_bone_count():
			if sk.get_bone_name(b).to_lower().contains("headtop"):
				osso = b
		if osso >= 0:
			var preso := BoneAttachment3D.new()
			sk.add_child(preso)
			preso.bone_idx = osso
			var quepe := Node3D.new()
			preso.add_child(quepe)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color("0d1630")
			mat.roughness = 0.6
			var copa := MeshInstance3D.new()
			var cil := CylinderMesh.new()
			cil.top_radius = 0.115
			cil.bottom_radius = 0.105
			cil.height = 0.09
			copa.mesh = cil
			copa.material_override = mat
			quepe.add_child(copa)
			var aba := MeshInstance3D.new()
			var cx := CylinderMesh.new()
			cx.top_radius = 0.075
			cx.bottom_radius = 0.075
			cx.height = 0.012
			aba.mesh = cx
			aba.material_override = mat
			aba.position = Vector3(0, -0.04, 0.08)
			aba.scale = Vector3(1.3, 1, 1)
			quepe.add_child(aba)
			_por_quepe.call_deferred(quepe, sk, osso)


func _por_quepe(quepe: Node3D, sk: Skeleton3D, osso: int) -> void:
	await get_tree().process_frame
	var topo: Vector3 = sk.global_transform * sk.get_bone_global_pose(osso).origin
	quepe.global_transform = Transform3D(policial.global_basis, topo + Vector3(0, -0.035, 0))


## passou na lombada da delegacia: o policial grita
func _policial(dt: float, vel: float) -> void:
	if policial == null:
		return
	if balao.visible:
		balao_t -= dt
		if balao_t <= 0.0:
			balao.visible = false
	var p := carro.global_position
	var l := del_xf.affine_inverse() * p
	if absf(l.x - (POLICIAL.x - 3.6)) < 1.6 and absf(l.z) < 7.5 and absf(vel) > 1.0 and tempo - piazada_t > 4.0:
		piazada_t = tempo
		balao.visible = true
		balao_t = 2.8
		# vira pro carro
		var d := p - policial.global_position
		policial.rotation.y = atan2(d.x, d.z)


# ---------------------------------------------------------------- lombadas
static func perfil_lombada(d: float) -> float:
	var t := d / LOMB_L
	if absf(t) >= 1.0:
		return 0.0
	return LOMB_H * (1.0 - t * t) * (1.0 - t * t * 0.15)


func altura_lombada(x: float, z: float) -> float:
	var h := 0.0
	for b in lombadas:
		var rx: float = x - float(b[0])
		var rz: float = z - float(b[1])
		if absf(rx) > 15.0 or absf(rz) > 15.0:
			continue
		var d: float = rx * float(b[2]) + rz * float(b[3])
		if absf(d) >= LOMB_L:
			continue
		if absf(-rx * float(b[3]) + rz * float(b[2])) > float(b[4]):
			continue
		h = maxf(h, perfil_lombada(d))
	return h


func _lombadas() -> void:
	var img := Image.create(256, 64, false, Image.FORMAT_RGB8)
	img.fill(Color("e8c200"))
	for x in 256:
		for y in 64:
			if int(x + y) % 48 < 24:
				img.set_pixel(x, y, Color("151515"))
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 0.7
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lista: Array = mapa.dados.get("lombadas", []).duplicate()
	if mapa.tem("delegacia"):   # a lombada do policial
		var dl := del_xf * DEL_LOMBADA_VELHA
		var dd := del_xf.basis * Vector3(1, 0, 0)
		lista.append([dl.x, dl.z, dd.x, dd.z, float(mapa.dados["delegacia"]["hw"])])
	for l in lista:
		var hw: float = float(l[4])
		var largura := hw * 2.0 - 0.3
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var S := 12
		for i in S:
			var d0 := -LOMB_L + 2.0 * LOMB_L * i / S
			var d1 := -LOMB_L + 2.0 * LOMB_L * (i + 1) / S
			var a := Vector3(d0, perfil_lombada(d0) + 0.02, -largura / 2.0)
			var b := Vector3(d1, perfil_lombada(d1) + 0.02, -largura / 2.0)
			var c := Vector3(d1, perfil_lombada(d1) + 0.02, largura / 2.0)
			var e := Vector3(d0, perfil_lombada(d0) + 0.02, largura / 2.0)
			var ua := Vector2(0, float(i) / S)
			var ub := Vector2(0, float(i + 1) / S)
			var uc := Vector2(largura / 3.2, float(i + 1) / S)
			var ue := Vector2(largura / 3.2, float(i) / S)
			for p in [[a, ua], [b, ub], [c, uc], [a, ua], [c, uc], [e, ue]]:   # sentido horário visto de cima (senão some)
				st.set_uv(p[1])
				st.add_vertex(p[0])
		st.generate_normals()
		st.set_material(mat)
		# a lombada não é parede pra física: o carro passa por cima e a gente sobe as rodas e a lataria na mão
		var corpo := MeshInstance3D.new()
		var malha := st.commit()
		corpo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(corpo)
		corpo.position = Vector3(float(l[0]), mapa.altura(float(l[0]), float(l[1])), float(l[1]))
		corpo.rotation.y = atan2(-float(l[3]), float(l[2]))
		# deita a lombada no chão (rua em subida/descida)
		var arr := malha.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for vi in vs.size():
			var w := corpo.transform * Vector3(vs[vi].x, 0, vs[vi].z)
			vs[vi].y += mapa.altura(w.x, w.z) - corpo.position.y
		arr[Mesh.ARRAY_VERTEX] = vs
		var m2 := ArrayMesh.new()
		m2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m2.surface_set_material(0, mat)
		corpo.mesh = m2
		lombadas.append([float(l[0]), float(l[1]), float(l[2]), float(l[3]), hw])


# ---------------------------------------------------------------- faísca, fumaça e sons
func _efeitos() -> void:
	# faíscas finas: pontinhos pequenos que somem rápido (cor vai de branco-amarelo pra laranja e apaga)
	faisca = CPUParticles3D.new()
	faisca.emitting = false
	faisca.amount = 90
	faisca.lifetime = 0.28
	faisca.explosiveness = 0.0
	faisca.randomness = 0.5
	faisca.direction = Vector3(0, 0.6, -1)
	faisca.spread = 35.0
	faisca.initial_velocity_min = 1.5
	faisca.initial_velocity_max = 3.8
	faisca.gravity = Vector3(0, -9, 0)
	faisca.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	faisca.emission_box_extents = Vector3(0.25, 0.01, 0.1)
	faisca.scale_amount_min = 0.4
	faisca.scale_amount_max = 1.0
	var curva := Curve.new()
	curva.add_point(Vector2(0, 1))
	curva.add_point(Vector2(1, 0.15))
	faisca.scale_amount_curve = curva
	var rampa := Gradient.new()
	rampa.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	rampa.set_color(1, Color(1.0, 0.35, 0.05, 0.0))
	rampa.add_point(0.45, Color(1.0, 0.7, 0.25, 0.9))
	faisca.color_ramp = rampa
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.vertex_color_use_as_albedo = true
	fm.albedo_texture = _bolinha()
	q.material = fm
	faisca.mesh = q
	add_child(faisca)
	som_raspa = AudioStreamPlayer3D.new()
	som_raspa.stream = _som("res://audio/raspada.mp3", true)
	if som_raspa.stream == null:
		som_raspa.stream = _ruido(0.35, 0.35, 2600.0, true)
	som_raspa.volume_db = 2.0
	som_raspa.unit_size = 8.0
	add_child(som_raspa)


## textura redonda e macia pra faísca (sem quadradinho)
func _bolinha() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for x in 32:
		for y in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


func _nova_fumaca() -> CPUParticles3D:
	var f := CPUParticles3D.new()
	f.emitting = false
	f.amount = 40
	f.lifetime = 1.4
	f.direction = Vector3(0, 1, 0)
	f.spread = 35.0
	f.initial_velocity_min = 0.4
	f.initial_velocity_max = 1.2
	f.gravity = Vector3(0, 0.5, 0)
	f.scale_amount_min = 1.0
	f.scale_amount_max = 2.6
	var curva := Curve.new()
	curva.add_point(Vector2(0, 0.3))
	curva.add_point(Vector2(1, 1.0))
	f.scale_amount_curve = curva
	var g := Gradient.new()
	g.set_color(0, Color(0.85, 0.85, 0.9, 0.35))
	g.set_color(1, Color(0.85, 0.85, 0.9, 0.0))
	f.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = CarroVisual._brilho()
	q.material = m
	f.mesh = q
	return f


## efeito de som de arquivo (laço = repete enquanto estiver tocando)
func _som(arq: String, laco: bool) -> AudioStream:
	if not ResourceLoader.exists(arq):
		return null
	var st: AudioStream = load(arq)
	if st is AudioStreamMP3:
		(st as AudioStreamMP3).loop = laco
	return st


## som de ar / raspada feito na hora (chiado)
func _ruido(dur: float, decai: float, corte: float, laco := false) -> AudioStreamWAV:
	var hz := 22050
	var n := int(dur * hz)
	var dados_b := PackedByteArray()
	dados_b.resize(n * 2)
	var y := 0.0
	var a := clampf(corte / hz * 6.28, 0.0, 1.0)
	for i in n:
		var t := float(i) / n
		y += (randf_range(-1.0, 1.0) - y) * a
		var env := pow(1.0 - t, decai) if not laco else 1.0
		var v := int(clampf(y * env * 1.6, -1.0, 1.0) * 30000)
		dados_b.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = hz
	w.data = dados_b
	if laco:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = n
	return w


# ---------------------------------------------------------------- carro
func _criar_carro(pos: Vector3, giro: float) -> void:
	if carro:
		carro.queue_free()
	rodas.clear()
	fumaca.clear()
	dados = Dados.carro()
	cfg = Dados.cfg()
	AR_MAX = CarroVisual.rebaixo_max(dados)
	rebaixo = float(cfg.get("rebaixo", 10.0))
	ar_alvo = rebaixo
	rebaixo_t = float(cfg.get("rebaixo_tras", rebaixo))
	ar_alvo_t = rebaixo_t
	rodas_vis.clear()
	var axF := float(dados["axF"])
	var axR := float(dados["axR"])
	carro = VehicleBody3D.new()
	carro.mass = 1150.0
	carro.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	carro.center_of_mass = Vector3(0, 0.0, (axF + axR) / 2.0)
	carro.angular_damp = 0.6
	add_child(carro)
	carro.global_position = pos
	carro.rotation.y = giro
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(float(dados["W"]) + 0.1, 0.45, axF - axR + 1.5)
	col.shape = box
	col.position = Vector3(0, 0.42, (axF + axR) / 2.0)
	carro.add_child(col)
	visual = CarroVisual.new()
	corpo_vis = Node3D.new()
	corpo_vis.name = "CorpoVis"
	carro.add_child(corpo_vis)
	_tem_xf = false
	corpo_vis.add_child(visual)
	visual.montar(dados, cfg, false)
	for i in 4:
		var frente := i < 2
		var lado := -1.0 if i % 2 == 0 else 1.0
		var w := VehicleWheel3D.new()
		w.position = Vector3(lado * visual.x_roda_eixo(frente), 0.0, axF if frente else axR)
		w.use_as_steering = frente
		w.use_as_traction = not frente
		w.wheel_radius = visual.raio()
		w.wheel_rest_length = 0.12
		w.suspension_travel = 0.1
		w.suspension_stiffness = 45.0
		w.suspension_max_force = 9000.0
		w.damping_compression = 0.9
		w.damping_relaxation = 1.3
		w.wheel_friction_slip = 2.4 if frente else 2.1
		w.wheel_roll_influence = 0.2
		carro.add_child(w)
		rodas.append(w)
		var rv := visual.nova_roda(lado, i)
		corpo_vis.add_child(rv)
		rv.position = w.position
		rodas_vis.append(rv)
		# (sem fumaça nas rodas: tirada a pedido)
	som_raspa.reparent(carro, false)
	som_raspa.position = Vector3.ZERO
	cam_pos = carro.global_position - carro.global_basis.z * 7.0 + Vector3.UP * 2.5
	_ar_texto()


# ---------------------------------------------------------------- física / direção
func _physics_process(dt: float) -> void:
	if carro == null:
		return
	var xf_agora := carro.global_transform
	if not _tem_xf or xf_agora.origin.distance_to(_xf_cur.origin) > 6.0:   # teleporte: não "voa" até lá
		_xf_cur = xf_agora
		_t_batida = 1.0          # (e a parada do teleporte não conta como batida)
		_vel_ant = carro.linear_velocity
	_xf_ant = _xf_cur
	_xf_cur = xf_agora
	_tem_xf = true
	tempo += dt
	if _teste:
		_roteiro_teste()
	if (congelado or foto or mapa_aberto) and not pe:
		_vel_ant = carro.linear_velocity
		carro.engine_force = 0.0
		carro.brake = 60.0
		carro.steering = 0.0
		_suspensao(dt)
		return
	if pe:
		_vel_ant = carro.linear_velocity
		carro.engine_force = 0.0
		carro.brake = 40.0
		carro.steering = 0.0
		for f in fumaca:
			f.emitting = false
		_suspensao(dt)
		_a_pe(dt)
		return
	_desgaste_rodando(dt)
	var frente := carro.global_basis.z
	var vel := carro.linear_velocity.dot(frente)
	var acel := Input.get_action_strength("acelerar")
	var freio := Input.get_action_strength("frear")
	if visual:
		visual.frear(freio > 0.0)   # luz de freio
	var forca := 3400.0 * float(dados.get("acc", 8.5)) / 8.5
	var vmax := float(dados.get("vmax", 50)) * 0.9
	carro.brake = 0.0
	carro.engine_force = 0.0
	if acel > 0.0:
		carro.engine_force = forca * acel if vel < vmax else 0.0
	elif freio > 0.0:
		if vel > 1.0:
			carro.brake = 28.0 * freio
		else:
			carro.engine_force = -forca * 0.55 * freio
	else:
		carro.brake = 1.5
	# drift: freio de mão solta a traseira, dá um empurrão no giro e solta fumaça
	var mao := Input.is_action_pressed("freio_mao")
	var curva := Input.get_action_strength("esquerda") - Input.get_action_strength("direita")
	for w in rodas:
		if not w.use_as_steering:
			w.brake = 40.0 if mao else 0.0
			w.wheel_friction_slip = 0.9 if mao else (1.5 if absf(curva) > 0.5 and acel > 0.0 and vel > 8.0 else 2.1)
	if mao and absf(vel) > 6.0:
		carro.apply_torque(Vector3.UP * curva * 2600.0)
	var max_curva := lerpf(0.55, 0.16, clampf(absf(vel) / 32.0, 0.0, 1.0))
	carro.steering = move_toward(carro.steering, curva * max_curva, dt * 2.6)
	# caiu fora do mapa (bloco ainda carregando): volta pro chão
	if carro.global_position.y < mapa.altura(carro.global_position.x, carro.global_position.z) - 4.0:
		mapa.carregar_perto(carro.global_position)
		teletransportar(carro.global_position, carro.rotation.y)
		return
	# desvira sozinho
	if carro.global_basis.y.y < 0.35:
		virado_t += dt
		if virado_t > 1.5:
			_desvirar()
	else:
		virado_t = 0.0
	_suspensao(dt)
	_raspar(dt, vel)
	_policial(dt, vel)


func _suspensao(dt: float) -> void:
	if ar_dir != 0:
		if eixo != 2:
			ar_alvo = clampf(ar_alvo + ar_dir * dt * 14.0, AR_MIN, AR_MAX)
		if eixo != 1:
			ar_alvo_t = clampf(ar_alvo_t + ar_dir * dt * 14.0, AR_MIN, AR_MAX)
	var antes := rebaixo + rebaixo_t * 1000.0
	rebaixo = move_toward(rebaixo, ar_alvo, dt * 16.0)
	rebaixo_t = move_toward(rebaixo_t, ar_alvo_t, dt * 16.0)
	if absf(rebaixo + rebaixo_t * 1000.0 - antes) > 0.001:
		ar_som_t = 0.35   # segura o chiado um pouquinho depois que para
		if not som_ar.playing:
			som_ar.volume_db = -4.0
			som_ar.play()
		_ar_texto()
	else:
		ar_som_t -= dt
		if som_ar.playing and ar_som_t <= 0.0:
			som_ar.volume_db -= dt * 60.0   # some aos poucos (sem corte seco)
			if som_ar.volume_db < -40.0:
				som_ar.stop()
	var media := 0.0
	for w in rodas:
		media += w.position.y
	media /= 4.0
	# em cima da lombada: cada roda sobe o tanto da lombada e a lataria acompanha (inclina)
	var hs: Array[float] = []
	var t := carro.global_transform
	# giro da roda pela velocidade (a roda que aparece não fica pendurada na roda da física: sem balanço)
	giro_roda = fmod(giro_roda + carro.linear_velocity.dot(carro.global_basis.z) / maxf(0.1, visual.raio()) * dt, TAU)
	var off_elev := elev_y - 0.07 * clampf(elev_y / 0.3, 0.0, 1.0)
	for i in rodas.size():
		var w := rodas[i]
		var g: Vector3 = t * w.position
		var h := altura_lombada(g.x, g.z)
		hs.append(h)
		if i < rodas_vis.size():
			var r := rodas_vis[i]
			var xr := signf(w.position.x) * visual.x_roda_eixo(i < 2, rebaixo if i < 2 else rebaixo_t)   # baixou muito: roda pra dentro do para-lama
			r.position = Vector3(xr, lerpf(r.position.y, w.position.y + h + off_elev, 0.5), w.position.z)
			r.rotation = Vector3(0, carro.steering if i < 2 else 0.0, 0)
			var gn := r.find_child("gira", true, false) as Node3D
			if gn:
				gn.rotation.x = giro_roda
	# dianteira e traseira: cada eixo desce o seu tanto
	var hf := (hs[0] + hs[1]) / 2.0 - visual.rebaixo_eixo(true, rebaixo)
	var hr := (hs[2] + hs[3]) / 2.0 - visual.rebaixo_eixo(false, rebaixo_t)
	var sobe := (hf + hr) / 2.0
	visual.corpo.rotation.x = lerpf(visual.corpo.rotation.x, -atan((hf - hr) / (float(dados["axF"]) - float(dados["axR"]))), 0.5)
	visual.corpo.rotation.z = lerpf(visual.corpo.rotation.z, atan(((hs[1] + hs[3]) - (hs[0] + hs[2])) / 2.0 / (visual.x_roda() * 2.0)), 0.5)
	visual.corpo.position.y = lerpf(visual.corpo.position.y, media - float(dados["wy"]) + _quique() + sobe, 0.3)
	visual.neon_luz.position.y = media - visual.raio() + 0.12
	visual.neon_chao.position.y = media - visual.raio() + 0.015
	# elevador da oficina: a lataria e as rodas sobem (as rodas ficam um pouco penduradas, suspensão esticada)
	visual.position.y = elev_y


## (fase 2) desgaste de verdade: batida forte amassa (no lado que bateu), rodar suja, e carro sujo e amassado
## enferruja devagar. Tudo sai na oficina (cabine: LAVAR / LIXAR / DESAMASSAR).
var _vel_ant := Vector3.ZERO
var _rodado := 0.0
var _t_batida := 0.0

func _desgaste_rodando(dt: float) -> void:
	var v := carro.linear_velocity
	var dv := _vel_ant - v
	_vel_ant = v
	_t_batida = maxf(0.0, _t_batida - dt)
	var choque := dv.length()
	if choque > 4.0 and _t_batida <= 0.0:
		_t_batida = 0.6
		var loc: Vector3 = carro.global_basis.inverse() * dv.normalized()   # pra onde a batida empurrou (no carro)
		var peca := "carro"
		if loc.z > 0.6:
			peca = "PCA"    # bateu de frente (a velocidade pra frente sumiu)
		elif loc.z < -0.6:
			peca = "PTR"    # bateram atrás
		else:
			var lado := "L" if loc.x > 0.0 else "R"
			peca = "PF" + lado
		_amassar(peca, clampf((choque - 4.0) * 0.06, 0.04, 0.35))
	_rodado += v.length() * dt
	if _rodado > 500.0:   # a cada meio quilômetro
		_rodado = 0.0
		var dg: Dictionary = (Dados.cfg().get("desgaste", {}) as Dictionary).duplicate(true)
		var c: Dictionary = dg.get("carro", {})
		c["s"] = minf(0.85, float(c.get("s", 0.0)) + 0.012)
		dg["carro"] = c
		for id in dg:
			var p: Dictionary = dg[id]
			if float(p.get("a", 0.0)) > 0.2 and float(c["s"]) > 0.4:
				p["f"] = minf(0.6, float(p.get("f", 0.0)) + 0.005)   # amassado + sujeira = ferrugem aparecendo
		_salvar_desgaste(dg)


func _amassar(peca: String, quanto: float) -> void:
	var dg: Dictionary = (Dados.cfg().get("desgaste", {}) as Dictionary).duplicate(true)
	if not visual.pecas.has(peca):
		peca = "carro"
	var p: Dictionary = dg.get(peca, visual.desgaste(peca) if peca != "carro" else {})
	p["a"] = minf(1.0, float(p.get("a", 0.0)) + quanto)
	dg[peca] = p
	_salvar_desgaste(dg)
	if quanto > 0.1:
		toast("BATEU! " + ("AMASSOU O CARRO" if peca == "carro" else "AMASSOU: " + visual.nome_peca(peca)), 1.4)


func _salvar_desgaste(dg: Dictionary) -> void:
	Dados.mudar("desgaste", dg)
	cfg = Dados.cfg()
	visual.c["desgaste"] = dg
	visual._aplicar_cores_pecas()


## pula no grave quando o som tá ligado e a música tocando
func _quique() -> float:
	if not musica.playing:
		visual.bater(0.0)
		return 0.0
	var g := Dados.grave
	visual.bater(g)   # cone dos alto-falantes batendo
	var forca := 0.012 if str(cfg.get("som", "off")) == "off" else (0.045 if str(cfg.get("som", "")) == "deitado" else 0.032)
	visual.neon_luz.light_energy = 1.6 + g * 3.0
	return -g * g * forca


## o assoalho encostou na lombada?
func _raspar(dt: float, vel: float) -> void:
	var pior := 0.0
	var onde := Vector3.ZERO
	var meia := float(dados["W"]) / 2.0 - 0.3
	for lx in [-meia, 0.0, meia]:
		for k in 7:
			var lz := lerpf(visual.tras_z + 0.4, visual.frente_z - 0.4, k / 6.0)
			var p: Vector3 = visual.corpo.global_transform * Vector3(lx, visual.piso, lz)
			var h := altura_lombada(p.x, p.z)
			if h <= 0.0:
				continue
			var chao := mapa.altura(p.x, p.z)
			var entra := chao + h - p.y
			if entra > pior:
				pior = entra
				onde = Vector3(p.x, chao + h, p.z)
	var raspando := pior > 0.004 and absf(vel) > 0.6
	faisca.emitting = raspando
	if raspando:
		faisca.global_transform = Transform3D(carro.global_basis, onde)   # espirra pra trás do carro
		carro.brake = maxf(carro.brake, 2.0 + pior * 40.0)  # segura um pouquinho, sem parar o carro
		tremor = maxf(tremor, minf(0.22, pior * 2.5 + 0.05))
		raspa_som_t = 0.45   # toca pelo menos um pedacinho mesmo na lombada rápida
		som_raspa.volume_db = 2.0
		if not som_raspa.playing:
			som_raspa.play(randf_range(0.0, 2.0))
	elif som_raspa.playing:
		raspa_som_t -= dt
		if raspa_som_t <= 0.0:
			som_raspa.volume_db -= dt * 70.0
			if som_raspa.volume_db < -40.0:
				som_raspa.stop()


func _desvirar() -> void:
	virado_t = 0.0
	var p := carro.global_position + Vector3.UP * 1.0
	var giro := carro.rotation.y
	carro.linear_velocity = Vector3.ZERO
	carro.angular_velocity = Vector3.ZERO
	carro.global_transform = Transform3D(Basis(Vector3.UP, giro), p)


# ---------------------------------------------------------------- câmera
var _memf := 0
func _process(dt: float) -> void:
	_mixar_galpao()
	if OS.has_environment("DROPS_MEM"):   # medição de desempenho (só no teste)
		_memf += 1
		if _memf == 120:
			print("MEM video=", Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6, " prims=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), " draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			var grupos := {}
			for mi in find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				if not (m.mesh is ArrayMesh) or not m.is_visible_in_tree():
					continue
				var d := cam.global_position.distance_to(m.global_position)
				if m.visibility_range_end > 0.0 and d > m.visibility_range_end:
					continue
				var t := 0
				for s2 in m.mesh.get_surface_count():
					t += m.mesh.surface_get_array_index_len(s2) / 3
				var top: Node = m
				var guard := 0
				while top.get_parent() != null and top.get_parent() != self and guard < 60:
					top = top.get_parent()
					guard += 1
				var k := str(top.name) + ":" + str(top.get_class())
				grupos[k] = grupos.get(k, 0) + t
			var ks := grupos.keys()
			ks.sort_custom(func(a, b): return grupos[a] > grupos[b])
			for k in ks.slice(0, 15):
				print("MEMG ", k, " ", grupos[k])
			get_tree().quit()
	if carro == null:
		return
	if Input.is_action_just_pressed("trocar_carro"):
		Dados.proximo_carro(1)
		_criar_carro(carro.global_position + Vector3.UP * 0.8, carro.rotation.y)
		return
	_interpolar_carro()
	if usar_cam_teste:
		cam.global_transform = cam_teste
		return
	if Input.is_physical_key_pressed(KEY_Q):
		ar_dir = -1
	elif Input.is_physical_key_pressed(KEY_E) and not pe:
		ar_dir = 1
	elif not (botoes["ar_sobe"] as Button).button_pressed and not (botoes["ar_desce"] as Button).button_pressed:
		ar_dir = 0
	if Input.is_physical_key_pressed(KEY_V):
		cam_yaw = 0.0
	_volante(dt)
	if toast_t > 0.0:
		toast_t -= dt
		toast_l.modulate.a = clampf(toast_t / 0.4, 0.0, 1.0)
	if sonda and carro and sonda.is_inside_tree():
		sonda.global_position = carro.global_position + Vector3.UP * 1.5
	# a oficina agora é de andar dentro (de carro ou a pé); o menu do carro só abre pelo botão GARAGEM
	_atualizar_hud_mapa(dt)
	if foto:
		_camera_foto()
		return
	if pe:
		if oficina and oficina.camera(dt):
			return
		_camera_pe(dt)
		return
	var foco := xf_liso.origin + Vector3.UP * 0.9
	# saindo da oficina: câmera de frente, do lado aberto do pátio
	if intro > 0.0:
		# começo: câmera mostrando o carro dentro da oficina (sem andar sozinho)
		intro -= dt
		var tt := smoothstep(0.0, 1.0, clampf(1.0 - intro / 2.5, 0.0, 1.0))
		var cp := mapa.drops_ponto(CAM_SAIDA_LOCAL.lerp(CAM_SAIDA_FIM, tt))
		cam.global_position = cp
		cam.look_at(foco, Vector3.UP)
		cam_pos = cp
		if Input.get_action_strength("acelerar") > 0.0 or Input.get_action_strength("frear") > 0.0:
			intro = 0.0
		return
		if false:
			Input.action_release("acelerar")
			# freia na rua pra não atravessar até a casa da frente
			if carro.linear_velocity.dot(carro.global_basis.z) > 1.2 and intro > 0.0:
				Input.action_press("frear", 0.7)
				_intro_freio = true
			else:
				Input.action_release("frear")
		return
	if _intro_freio:
		_intro_freio = false
		Input.action_release("frear")
	var frente := xf_liso.basis.z
	frente.y = 0.0
	frente = frente.normalized().rotated(Vector3.UP, cam_yaw)
	var alvo := xf_liso.origin - frente * 6.8 + Vector3.UP * 2.4
	# não deixa a câmera atravessar parede: puxa pra perto do carro
	var ray := PhysicsRayQueryParameters3D.create(foco, alvo)
	ray.exclude = [carro.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		alvo = foco + (Vector3(hit["position"]) - foco) * 0.85
	cam_pos = cam_pos.lerp(alvo, 1.0 - exp(-dt * 6.0))
	var sacode := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * tremor * 0.12
	tremor = maxf(0.0, tremor - dt * 1.5)
	cam.global_position = cam_pos + sacode
	cam.look_at(foco + frente * 2.5, Vector3.UP)


## coloca a parte que aparece do carro na posição "entre dois passos da física" (tira a tremedeira/travadinha)
func _interpolar_carro() -> void:
	if carro == null or corpo_vis == null:
		return
	if not _tem_xf:
		xf_liso = carro.global_transform
		corpo_vis.transform = Transform3D()
		return
	var f := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	if OS.get_environment("DROPS_LISO") == "0":
		f = 1.0
		_xf_ant = carro.global_transform
		_xf_cur = carro.global_transform
	xf_liso = _xf_ant.interpolate_with(_xf_cur, f)
	corpo_vis.transform = carro.global_transform.affine_inverse() * xf_liso


func _unhandled_input(e: InputEvent) -> void:
	# arrastar na parte de cima da tela gira a câmera (e ela fica ali)
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed and (foto or t.position.y < get_viewport().get_visible_rect().size.y * 0.62) and arrasto_id < 0:
			arrasto_id = t.index
		elif not t.pressed and t.index == arrasto_id:
			arrasto_id = -1
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if foto and d.index == arrasto_id:
			foto_yaw -= d.relative.x * 0.008
			foto_pitch = clampf(foto_pitch + d.relative.y * 0.005, -0.05, 1.2)
		elif d.index == arrasto_id:
			if pe:
				ape_yaw = wrapf(ape_yaw - d.relative.x * 0.008, -PI, PI)
			else:
				cam_yaw = wrapf(cam_yaw - d.relative.x * 0.008, -PI, PI)


func teletransportar(pos: Vector3, giro: float, ao_chao := true) -> void:
	if pe:
		entrar_carro_ja()
	intro = 0.0
	Input.action_release("acelerar")
	Input.action_release("frear")
	mapa.carregar_perto(pos)
	if ao_chao:
		pos = mapa.no_chao(pos, 0.6)
	_tem_xf = false
	carro.linear_velocity = Vector3.ZERO
	carro.angular_velocity = Vector3.ZERO
	carro.global_transform = Transform3D(Basis(Vector3.UP, giro), pos)
	cam_yaw = 0.0
	cam_pos = pos - Vector3(sin(giro), 0, cos(giro)) * 7.0 + Vector3.UP * 2.5


func entrar_carro_ja() -> void:
	if pessoa:
		pessoa.global_position = carro.global_position
	entrar_carro()


# ---------------------------------------------------------------- modo foto
func entrar_foto() -> void:
	foto = true
	var alvo: Node3D = pessoa if pe else carro
	foto_yaw = alvo.global_rotation.y + 2.4
	foto_pitch = 0.15
	foto_dist = 5.5 if not pe else 3.2
	hud.visible = false
	if foto_ui == null:
		_montar_foto_ui()
	foto_ui.visible = true
	foto_previa.visible = false


func sair_foto() -> void:
	foto = false
	hud.visible = true
	foto_ui.visible = false
	cam.fov = 62.0
	if carro:
		cam_pos = cam.global_position


func _camera_foto() -> void:
	var alvo: Vector3 = (pessoa.global_position + Vector3.UP * 1.0) if pe else (carro.global_position + Vector3.UP * 0.6)
	var cp := cos(foto_pitch)
	var p := alvo + Vector3(sin(foto_yaw) * cp, sin(foto_pitch), cos(foto_yaw) * cp) * foto_dist
	p.y = maxf(p.y, 0.25)
	cam.global_position = p
	cam.look_at(alvo, Vector3.UP)
	cam.fov = 50.0


func _montar_foto_ui() -> void:
	var camada := CanvasLayer.new()
	camada.layer = 5
	add_child(camada)
	foto_ui = Control.new()
	foto_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	foto_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camada.add_child(foto_ui)
	var topo := HBoxContainer.new()
	topo.position = Vector2(26, 20)
	topo.add_theme_constant_override("separation", 12)
	foto_ui.add_child(topo)
	var sair := Button.new()
	sair.text = "SAIR"
	sair.focus_mode = Control.FOCUS_NONE
	sair.add_theme_font_size_override("font_size", 22)
	sair.pressed.connect(sair_foto)
	topo.add_child(sair)
	var tit := Label.new()
	tit.text = "MODO FOTO · arraste pra girar"
	tit.add_theme_font_size_override("font_size", 22)
	tit.add_theme_color_override("font_outline_color", Color.BLACK)
	tit.add_theme_constant_override("outline_size", 6)
	topo.add_child(tit)
	for par in [["−", 0.8], ["+", -0.8]]:
		var b := Button.new()
		b.text = par[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(56, 48)
		b.add_theme_font_size_override("font_size", 26)
		var passo: float = par[1]
		b.pressed.connect(func(): foto_dist = clampf(foto_dist + passo, 2.0, 14.0))
		topo.add_child(b)
	var tirar := Button.new()
	tirar.focus_mode = Control.FOCUS_NONE
	tirar.custom_minimum_size = Vector2(90, 90)
	var st := StyleBoxFlat.new()
	st.bg_color = Color.WHITE
	st.set_corner_radius_all(45)
	st.border_color = Color(1, 1, 1, 0.4)
	st.set_border_width_all(6)
	tirar.add_theme_stylebox_override("normal", st)
	tirar.add_theme_stylebox_override("hover", st)
	tirar.add_theme_stylebox_override("pressed", st)
	tirar.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	tirar.position = Vector2(-130, -45)
	tirar.pressed.connect(tirar_foto)
	foto_ui.add_child(tirar)
	foto_previa = TextureRect.new()
	foto_previa.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	foto_previa.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	foto_previa.set_anchors_preset(Control.PRESET_CENTER)
	foto_previa.size = Vector2(560, 320)
	foto_previa.position = Vector2(-280, -160)
	foto_previa.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foto_ui.add_child(foto_previa)
	foto_aviso = Label.new()
	foto_aviso.add_theme_font_size_override("font_size", 20)
	foto_aviso.add_theme_color_override("font_color", AMARELO)
	foto_aviso.add_theme_color_override("font_outline_color", Color.BLACK)
	foto_aviso.add_theme_constant_override("outline_size", 6)
	foto_aviso.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	foto_aviso.position = Vector2(-400, -110)
	foto_aviso.size = Vector2(800, 80)
	foto_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foto_aviso.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foto_ui.add_child(foto_aviso)


## tira a foto da tela sem os botões, põe a marca da Drops no canto e salva em Imagens
func tirar_foto() -> void:
	foto_ui.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	foto_ui.visible = true
	var logo: Image = (load("res://imagens/logo_drops.jpg") as Texture2D).get_image()
	if logo:
		logo.convert(img.get_format())
		var lw := int(img.get_width() * 0.16)
		logo.resize(lw, int(lw * float(logo.get_height()) / logo.get_width()), Image.INTERPOLATE_LANCZOS)
		var margem := int(img.get_width() * 0.02)
		img.blend_rect(logo, Rect2i(Vector2i.ZERO, logo.get_size()), Vector2i(img.get_width() - logo.get_width() - margem, img.get_height() - logo.get_height() - margem))
	var pasta := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if pasta == "" or not DirAccess.dir_exists_absolute(pasta):
		pasta = OS.get_user_data_dir()
	var nome := "DropsGarage_%s.png" % Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var caminho := pasta.path_join(nome)
	var ok := img.save_png(caminho) == OK
	foto_previa.texture = ImageTexture.create_from_image(img)
	foto_previa.visible = true
	get_tree().create_timer(2.5).timeout.connect(func(): if foto_previa: foto_previa.visible = false)
	foto_aviso.text = ("FOTO SALVA EM:\n" + caminho) if ok else "NÃO CONSEGUI SALVAR A FOTO"
	get_tree().create_timer(3.0).timeout.connect(func(): if foto_aviso: foto_aviso.text = "")


# ---------------------------------------------------------------- a pé
func descer() -> void:
	if pe or carro == null:
		return
	if carro.linear_velocity.length() > 1.5:
		toast("PARA O CARRO PRIMEIRO")
		return
	pe = true
	Input.action_release("acelerar")
	if pessoa == null:
		pessoa = Pessoa.new()
		add_child(pessoa)
	pessoa.visible = true
	pessoa.process_mode = Node.PROCESS_MODE_INHERIT
	# desce do lado que tem espaço (dentro da oficina um lado é parede); sem espaço nos lados, desce atrás do carro
	var meio := carro.global_position + Vector3.UP * 0.9
	var ok := false
	for dir: Vector3 in [-carro.global_basis.x, carro.global_basis.x, -carro.global_basis.z]:
		var dist: float = (float(dados["W"]) / 2.0 + 0.8) if dir != -carro.global_basis.z else 3.2
		var alvo := meio + dir * dist
		var q := PhysicsRayQueryParameters3D.create(meio, alvo + dir * 0.4)
		q.exclude = [carro.get_rid()]
		if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			pessoa.global_position = alvo - Vector3.UP * 0.6
			ok = true
			break
	if not ok:
		pessoa.global_position = carro.global_position - carro.global_basis.x * (float(dados["W"]) / 2.0 + 0.8) + Vector3.UP * 0.3
	pessoa.velocity = Vector3.ZERO
	ape_yaw = atan2(-carro.global_basis.z.x, -carro.global_basis.z.z) + PI
	if visual.partes.has("portas"):
		visual.abrir("portas")
		get_tree().create_timer(1.1).timeout.connect(func(): if visual and visual.aberto("portas"): visual.abrir("portas"))
	_modo_hud()
	_montar_partes_ui()


func entrar_carro() -> void:
	if not pe:
		return
	if oficina and not oficina.pode_entrar_no_carro():
		return
	if oficina and oficina.pintando:
		oficina.fechar_pintura()
	if pessoa.global_position.distance_to(carro.global_position) > 4.0:
		toast("CHEGA PERTO DO CARRO")
		return
	if oficina and oficina.desm:
		oficina.desm.guardar_ja()   # peça na mão vai pro cavalete
	pe = false
	pessoa.dancar(false)
	pessoa.visible = false
	pessoa.process_mode = Node.PROCESS_MODE_DISABLED
	visual.fechar_tudo()
	cam_pos = carro.global_position - carro.global_basis.z * 7.0 + Vector3.UP * 2.5
	cam_yaw = 0.0
	_modo_hud()


func _desenhar_mao() -> void:
	var s := cel_mao.size
	var pele := Color("c68a62")
	var sombra := Color("9c6744")
	# palma embaixo, polegar na esquerda, dedos na direita
	cel_mao.draw_rect(Rect2(Vector2(-30, s.y * 0.62), Vector2(s.x + 60, s.y * 0.5)), pele)
	cel_mao.draw_circle(Vector2(s.x * 0.5, s.y * 0.66), s.x * 0.62, pele)
	cel_mao.draw_set_transform(Vector2(-6, s.y * 0.5), -0.5, Vector2.ONE)
	cel_mao.draw_rect(Rect2(Vector2(-22, -18), Vector2(48, 120)), pele)
	cel_mao.draw_circle(Vector2(2, -18), 24, pele)
	cel_mao.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	for k in 4:
		var y := s.y * (0.34 + k * 0.1)
		cel_mao.draw_rect(Rect2(Vector2(s.x - 14, y), Vector2(34, 30)), pele)
		cel_mao.draw_circle(Vector2(s.x + 18, y + 15), 15, pele)
		cel_mao.draw_line(Vector2(s.x - 12, y + 30), Vector2(s.x + 26, y + 30), sombra, 2.0)


func _modo_hud() -> void:
	for n in carro_hud:
		(n as CanvasItem).visible = not pe
	ar_painel.visible = false
	_estilo_ar()


## suspensão a ar: no carro é o painel; a pé vira o app "DROPS AIR" no celular na mão do personagem
func _abrir_ar() -> void:
	if pe and pessoa and carro and pessoa.global_position.distance_to(carro.global_position) > 25.0:
		toast("CHEGA PERTO DO CARRO PRA USAR O APP", 2.0)
		return
	ar_painel.visible = not ar_painel.visible
	_estilo_ar()


func _estilo_ar() -> void:
	if ar_painel == null:
		return
	var cel := pe and ar_painel.visible
	cel_topo.visible = pe
	if pe:
		var e := StyleBoxFlat.new()
		e.bg_color = Color("10131a")
		e.border_color = Color("050506")
		e.set_border_width_all(11)
		e.border_width_top = 26
		e.border_width_bottom = 22
		e.set_corner_radius_all(34)
		e.content_margin_left = 22
		e.content_margin_right = 22
		e.content_margin_top = 38
		e.content_margin_bottom = 34
		e.shadow_color = Color(0, 0, 0, 0.5)
		e.shadow_size = 12
		ar_painel.add_theme_stylebox_override("panel", e)
		(cel_topo.get_node("conectado") as Label).text = "● conectado: " + str(dados["nome"])
		var tm := Time.get_time_dict_from_system()
		(cel_topo.get_node("hora") as Label).text = "%02d:%02d" % [tm["hour"], tm["minute"]]
	else:
		ar_painel.add_theme_stylebox_override("panel", _estilo(Color(0.04, 0.04, 0.06, 0.85), AMARELO, 12))
	if cel_mao:
		cel_mao.visible = false   # sem mão desenhada: só o celular
	if pe_botoes:
		pe_botoes.visible = pe and not cel   # celular na frente: esconde os botões de baixo enquanto mexe no app
	if minimapa:
		minimapa.visible = not cel           # o celular fica no lugar do minimapa (lateral direita)
	if pessoa:
		pessoa.segurar_celular(cel)
	_posicionar_botoes.call_deferred()
	stick.visible = pe
	pe_botoes.visible = pe
	partes_box.visible = pe and not visual.partes.is_empty()


func _montar_partes_ui() -> void:
	for n in partes_box.get_children():
		n.queue_free()
	for k in visual.partes:
		if visual.parte_fora(k):
			continue   # (fase 2) peça tirada na oficina: não tem o que abrir
		var b := Button.new()
		b.text = "ABRIR " + str(visual.partes[k]["nome"]).to_upper()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 56)
		b.add_theme_font_size_override("font_size", 18)
		var n := _estilo(Color(0.05, 0.05, 0.07, 0.6), Color(1, 1, 1, 0.35))
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", n)
		var chave: String = k
		b.pressed.connect(func(): visual.abrir(chave))
		partes_box.add_child(b)


func _a_pe(_dt: float) -> void:
	var v := stick_v
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): v.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): v.x += 1.0
	v = v.limit_length(1.0)
	var frente := Vector3(sin(ape_yaw + PI), 0, cos(ape_yaw + PI))
	var direita := Vector3(-frente.z, 0, frente.x)
	if not pessoa.ocupado():   # trabalhando na oficina: o boneco anda sozinho até a peça
		pessoa.desejo = frente * -v.y + direita * v.x
		pessoa.correndo = stick_v.length() > 0.92 or Input.is_physical_key_pressed(KEY_SHIFT)
	var perto := pessoa.global_position.distance_to(carro.global_position) < 4.0
	(botoes["entrar"] as Button).modulate.a = 1.0 if perto else 0.45
	partes_box.visible = perto and not visual.partes.is_empty()
	(botoes["dancar"] as Button).button_pressed = pessoa.dancando


func _camera_pe(dt: float) -> void:
	var foco := pessoa.lisa() + Vector3.UP * 1.45
	var tras := Vector3(sin(ape_yaw), 0, cos(ape_yaw))
	var alvo := foco + tras * 3.6 + Vector3.UP * 0.7
	var ray := PhysicsRayQueryParameters3D.create(foco, alvo)
	ray.exclude = [pessoa.get_rid(), carro.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		alvo = foco + (Vector3(hit["position"]) - foco) * 0.85
	cam_pos = cam_pos.lerp(alvo, 1.0 - exp(-dt * 10.0))
	cam.global_position = cam_pos
	cam.look_at(foco, Vector3.UP)
	if Input.is_physical_key_pressed(KEY_LEFT) and Input.is_physical_key_pressed(KEY_SHIFT):
		ape_yaw += dt * 2.0


func _stick_input(e: InputEvent) -> void:
	var centro := stick.size / 2.0
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed and stick_id < 0:
			stick_id = t.index
		elif not t.pressed and t.index == stick_id:
			stick_id = -1
			stick_v = Vector2.ZERO
		if t.pressed and t.index == stick_id:
			stick_v = ((t.position - centro) / 80.0).limit_length(1.0)
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if d.index == stick_id:
			stick_v = ((d.position - centro) / 80.0).limit_length(1.0)
	stick_bola.position = centro - stick_bola.size / 2.0 + stick_v * 70.0
	stick.accept_event()


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		var k := (e as InputEventKey).physical_keycode
		if k == KEY_F:
			if pe: entrar_carro()
			else: descer()
		elif k == KEY_E and pe and oficina:
			oficina.interagir()
		elif k == KEY_ESCAPE and oficina and oficina.pintando:
			oficina.fechar_pintura()
		elif false and k == KEY_G and pe and pessoa:
			pessoa.dancar(not pessoa.dancando)


# ---------------------------------------------------------------- volante
func _volante(dt: float) -> void:
	if vol_id < 0:
		vol_ang *= exp(-dt * 9.0)
		if absf(vol_ang) < 0.002:
			vol_ang = 0.0
	volante.rotation = vol_ang
	if pe:
		return
	var v := clampf(vol_ang / 1.57, -1.0, 1.0)
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_RIGHT):
		return
	if v < -0.01:
		Input.action_press("esquerda", -v)
		Input.action_release("direita")
	elif v > 0.01:
		Input.action_press("direita", v)
		Input.action_release("esquerda")
	else:
		Input.action_release("esquerda")
		Input.action_release("direita")


func _volante_input(e: InputEvent) -> void:
	var centro := volante.size / 2.0
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed and vol_id < 0:
			vol_id = t.index
			vol_ultimo = (t.position - centro).angle()
		elif not t.pressed and t.index == vol_id:
			vol_id = -1
		volante.accept_event()
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if d.index != vol_id:
			return
		# a posição chega no espaço do volante já girado: desfaz o giro
		var p := (d.position - centro).rotated(vol_ang)
		var a := p.angle()
		var delta := wrapf(a - vol_ultimo, -PI, PI)
		vol_ultimo = a
		vol_ang = clampf(vol_ang + delta, -2.36, 2.36)
		vol_ultimo = (d.position - centro).rotated(vol_ang).angle()
		volante.accept_event()


# ---------------------------------------------------------------- botões na tela
func _circulo(r: int, cor: Color) -> ImageTexture:
	var img := Image.create(r * 2, r * 2, false, Image.FORMAT_RGBA8)
	for y in r * 2:
		for x in r * 2:
			var d := Vector2(x - r + 0.5, y - r + 0.5).length()
			if d < r - 4:
				img.set_pixel(x, y, cor)
			elif d < r:
				img.set_pixel(x, y, Color(1, 1, 1, 0.55))
	return ImageTexture.create_from_image(img)


func _botao(acao: String, texto: String, r: int, cor: Color) -> TouchScreenButton:
	var b := TouchScreenButton.new()
	b.texture_normal = _circulo(r, cor)
	b.texture_pressed = _circulo(r, Color(1.0, 0.83, 0.0, 0.85))
	var sh := CircleShape2D.new()
	sh.radius = r
	b.shape = sh
	b.shape_centered = true
	b.action = acao
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", int(r * 0.42))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(r * 2, r * 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	hud.add_child(b)
	botoes[acao] = b
	return b


func _estilo(cor: Color, borda: Color, raio := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = cor
	s.border_color = borda
	s.set_border_width_all(2)
	s.set_corner_radius_all(raio)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func _botao_ui(texto: String, nome: String) -> Button:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	var n := _estilo(Color(0.05, 0.05, 0.07, 0.6), Color(1, 1, 1, 0.35))
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", n)
	b.add_theme_stylebox_override("pressed", _estilo(Color(1.0, 0.83, 0.0, 0.9), AMARELO))
	b.add_theme_color_override("font_pressed_color", Color.BLACK)
	hud.add_child(b)
	botoes[nome] = b
	return b


func _hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var escuro := Color(0.05, 0.05, 0.07, 0.55)
	volante = TextureRect.new()
	volante.texture = load("res://imagens/volante.svg")
	volante.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	volante.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	volante.size = Vector2(190, 190)
	volante.pivot_offset = volante.size / 2.0
	volante.modulate = Color(1, 1, 1, 0.92)
	volante.gui_input.connect(_volante_input)
	var marca := Label.new()
	marca.text = "DROPS"
	marca.add_theme_font_size_override("font_size", 12)
	marca.add_theme_color_override("font_color", AMARELO)
	marca.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marca.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marca.size = volante.size
	marca.mouse_filter = Control.MOUSE_FILTER_IGNORE
	volante.add_child(marca)
	hud.add_child(volante)
	_botao("frear", "FREIO", 56, escuro)
	_botao("acelerar", "ACELERA", 70, Color(0.1, 0.1, 0.1, 0.6))
	_botao("freio_mao", "DRIFT", 44, escuro)
	_botao_ui("GARAGEM", "garagem").pressed.connect(func():
		_salvar_ar()
		get_tree().change_scene_to_file("res://cenas/garagem.tscn"))
	_botao_ui("CARRO", "carro").pressed.connect(func():
		Dados.proximo_carro(1)
		_criar_carro(carro.global_position + Vector3.UP * 0.8, carro.rotation.y))
	var bm := _botao_ui("♫ MÚSICA", "musica")
	var pm := Dados.painel_musica()   # tocar/parar, trocar de música e volume só da música
	bm.add_child(pm)
	pm.position = Vector2(-150, 56)
	bm.pressed.connect(func(): pm.visible = not pm.visible)
	if OS.has_environment("DROPS_PAINEL"):
		pm.visible = true
	_botao_ui("FOTO", "foto").pressed.connect(entrar_foto)
	_botao_ui("◎ CÂMERA", "camera").pressed.connect(func(): cam_yaw = 0.0)
	# botão da mola: suspensão a ar (no carro abre o painel; a pé abre o app no celular)
	var bmola := _botao_ui("", "ar")
	bmola.custom_minimum_size = Vector2(78, 78)
	bmola.size = Vector2(78, 78)
	var icm := IconeMenu.new("medidas", Color.WHITE)
	icm.size = Vector2(52, 52)
	icm.position = Vector2(13, 13)
	bmola.add_child(icm)
	bmola.pressed.connect(_abrir_ar)
	# mão que segura o celular (aparece a pé)
	cel_mao = Control.new()
	cel_mao.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cel_mao.visible = false
	cel_mao.draw.connect(_desenhar_mao)
	hud.add_child(cel_mao)
	# painel da suspensão a ar
	ar_painel = PanelContainer.new()
	ar_painel.add_theme_stylebox_override("panel", _estilo(Color(0.04, 0.04, 0.06, 0.85), AMARELO, 12))
	ar_painel.visible = false
	hud.add_child(ar_painel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	ar_painel.add_child(col)
	# cabeçalho do app (só aparece no modo celular)
	cel_topo = VBoxContainer.new()
	cel_topo.visible = false
	col.add_child(cel_topo)
	var hora := Label.new()
	hora.name = "hora"
	hora.add_theme_font_size_override("font_size", 13)
	hora.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	cel_topo.add_child(hora)
	var app := Label.new()
	app.text = "DROPS AIR"
	app.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	app.add_theme_font_size_override("font_size", 26)
	app.add_theme_color_override("font_color", AMARELO)
	cel_topo.add_child(app)
	var con := Label.new()
	con.name = "conectado"
	con.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	con.add_theme_font_size_override("font_size", 14)
	con.add_theme_color_override("font_color", Color("7dff9a"))
	cel_topo.add_child(con)
	ar_label = Label.new()
	ar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ar_label.add_theme_font_size_override("font_size", 20)
	ar_label.add_theme_color_override("font_color", AMARELO)
	col.add_child(ar_label)
	var eixos := HBoxContainer.new()
	eixos.add_theme_constant_override("separation", 6)
	col.add_child(eixos)
	var bts_eixo: Array[Button] = []
	for par in [["AS DUAS", 0], ["FRENTE", 1], ["TRÁS", 2]]:
		var be := Button.new()
		be.text = par[0]
		be.toggle_mode = true
		be.button_pressed = int(par[1]) == eixo
		be.focus_mode = Control.FOCUS_NONE
		be.custom_minimum_size = Vector2(72, 44)
		be.add_theme_font_size_override("font_size", 16)
		eixos.add_child(be)
		bts_eixo.append(be)
	for k in bts_eixo.size():
		bts_eixo[k].pressed.connect(func():
			eixo = k
			for q in bts_eixo.size():
				bts_eixo[q].set_pressed_no_signal(q == k))
	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 8)
	col.add_child(linha)
	for par in [["▲ SOBE", "ar_sobe", -1], ["▼ DESCE", "ar_desce", 1]]:
		var b := Button.new()
		b.text = par[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(110, 64)
		b.add_theme_font_size_override("font_size", 20)
		b.button_down.connect(func(): ar_dir = int(par[2]))
		b.button_up.connect(func(): ar_dir = 0)
		linha.add_child(b)
		botoes[par[1]] = b
	var aterrar := Button.new()
	aterrar.text = "ATERRAR"
	aterrar.focus_mode = Control.FOCUS_NONE
	aterrar.custom_minimum_size = Vector2(0, 52)
	aterrar.add_theme_font_size_override("font_size", 20)
	aterrar.pressed.connect(func(): _ar_para(AR_MAX))
	col.add_child(aterrar)
	var subir := Button.new()
	subir.text = "ALTURA DE RUA"
	subir.focus_mode = Control.FOCUS_NONE
	subir.custom_minimum_size = Vector2(0, 52)
	subir.add_theme_font_size_override("font_size", 20)
	subir.pressed.connect(func(): _ar_para(0.0))
	col.add_child(subir)
	var bpe := _botao_ui("A PÉ", "descer")
	bpe.pressed.connect(descer)
	carro_hud = [volante, botoes["acelerar"], botoes["frear"], botoes["freio_mao"], botoes["carro"], bpe]
	# a pé: joystick, entrar no carro, dançar e portas
	stick = Control.new()
	stick.size = Vector2(200, 200)
	var fundo := TextureRect.new()
	fundo.texture = _circulo(100, Color(0.05, 0.05, 0.07, 0.45))
	fundo.size = Vector2(200, 200)
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stick.add_child(fundo)
	stick_bola = TextureRect.new()
	stick_bola.texture = _circulo(40, Color(1.0, 0.83, 0.0, 0.8))
	stick_bola.size = Vector2(80, 80)
	stick_bola.position = Vector2(60, 60)
	stick_bola.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stick.add_child(stick_bola)
	stick.gui_input.connect(_stick_input)
	stick.visible = false
	hud.add_child(stick)
	pe_botoes = HBoxContainer.new()
	pe_botoes.add_theme_constant_override("separation", 12)
	pe_botoes.visible = false
	hud.add_child(pe_botoes)
	var dancar := _botao_ui("DANÇAR", "dancar")
	dancar.reparent(pe_botoes)
	dancar.custom_minimum_size = Vector2(150, 70)
	dancar.pressed.connect(func(): if pessoa: pessoa.dancar(not pessoa.dancando))
	dancar.visible = false  # dança desligada por enquanto
	# botão de ação da oficina (PINTAR, PEGAR RODA, INSTALAR, SUBIR ELEVADOR...): muda conforme onde você está
	var acao := _botao_ui("", "acao")
	acao.reparent(pe_botoes)
	acao.custom_minimum_size = Vector2(260, 70)
	acao.add_theme_stylebox_override("normal", _estilo(Color(1.0, 0.83, 0.0, 0.92), AMARELO))
	acao.add_theme_stylebox_override("hover", _estilo(Color(1.0, 0.83, 0.0, 0.92), AMARELO))
	acao.add_theme_color_override("font_color", Color.BLACK)
	acao.add_theme_color_override("font_hover_color", Color.BLACK)
	acao.visible = false
	acao.pressed.connect(func(): if oficina: oficina.interagir())
	var b_linha := _botao_ui("▲▼", "acao_linha")
	b_linha.reparent(pe_botoes)
	b_linha.custom_minimum_size = Vector2(80, 70)
	b_linha.visible = false
	b_linha.pressed.connect(func(): if oficina: oficina.trocar_linha())
	var entrar := _botao_ui("ENTRAR NO CARRO", "entrar")
	entrar.reparent(pe_botoes)
	entrar.custom_minimum_size = Vector2(230, 70)
	entrar.pressed.connect(entrar_carro)
	partes_box = HBoxContainer.new()
	partes_box.add_theme_constant_override("separation", 10)
	partes_box.visible = false
	hud.add_child(partes_box)
	# aviso no meio da tela
	toast_l = Label.new()
	toast_l.add_theme_font_size_override("font_size", 34)
	toast_l.add_theme_color_override("font_color", AMARELO)
	toast_l.add_theme_color_override("font_outline_color", Color.BLACK)
	toast_l.add_theme_constant_override("outline_size", 10)
	toast_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_l.modulate.a = 0.0
	toast_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(toast_l)
	_posicionar_botoes()


func toast(t: String, dur := 1.6) -> void:
	toast_l.text = t
	toast_l.add_theme_font_size_override("font_size", 34 if t.length() < 60 else 24)   # dica longa: letra menor
	toast_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_t = dur
	toast_l.modulate.a = 1.0


func _ar_texto() -> void:
	if ar_label == null or visual == null:
		return
	var media := 0.0
	for w in rodas:
		media += w.position.y
	media /= 4.0
	# assoalho = centro da roda (no chão fica a 'raio' do asfalto) + quanto a lataria desce
	var cf := maxf(0.0, (visual.raio() + (-float(dados["wy"]) - ar_alvo / 100.0) + visual.piso) * 100.0)
	var ct := maxf(0.0, (visual.raio() + (-float(dados["wy"]) - ar_alvo_t / 100.0) + visual.piso) * 100.0)
	ar_label.text = "FRENTE %d cm · TRÁS %d cm" % [roundi(cf), roundi(ct)]


func _ar_para(v: float) -> void:
	if eixo != 2:
		ar_alvo = v
	if eixo != 1:
		ar_alvo_t = v


func _salvar_ar() -> void:
	Dados.mudar("rebaixo", roundf(rebaixo))
	Dados.mudar("rebaixo_tras", roundf(rebaixo_t))


func _posicionar_botoes() -> void:
	if hud == null:
		return
	var t := get_viewport().get_visible_rect().size
	var m := 26.0 + _margem_segura()
	volante.position = Vector2(m, t.y - m - 190)
	botoes["acelerar"].position = Vector2(t.x - m - 140, t.y - m - 140)
	botoes["frear"].position = Vector2(t.x - m - 140 - 130, t.y - m - 112)
	botoes["freio_mao"].position = Vector2(t.x - m - 100, t.y - m - 140 - 110)
	# (v36) GARAGEM / CARRO / A PÉ na direita, embaixo da fileira de cima (onde ficava o minimapa)
	var bw := 150.0
	for k in ["garagem", "carro", "descer"]:
		(botoes[k] as Button).custom_minimum_size = Vector2(bw, 52)
		(botoes[k] as Button).reset_size()
	botoes["garagem"].position = Vector2(t.x - m - bw, m + 70)
	botoes["carro"].position = Vector2(t.x - m - bw, m + 134)
	botoes["musica"].position = Vector2(t.x - m - 300, m)
	botoes["foto"].position = Vector2(t.x - m - 600, m)
	if foto_ui:
		foto_ui.size = t
	botoes["camera"].position = Vector2(t.x - m - 150, m)
	botoes["ar"].position = Vector2(m, m + 250)
	if pe:
		var tam := ar_painel.get_combined_minimum_size()
		# celular na lateral direita (não cobre o personagem no meio da tela)
		ar_painel.position = Vector2(t.x - m - tam.x - 10.0, (t.y - tam.y) / 2.0 + 20.0)
		if cel_mao:
			cel_mao.position = ar_painel.position
			cel_mao.size = tam
			cel_mao.queue_redraw()
	else:
		ar_painel.position = Vector2(m + 96, m + 230)
	botoes["descer"].position = Vector2(t.x - m - bw, m + 198)
	stick.position = Vector2(m + 10, t.y - m - 210)
	pe_botoes.reset_size()
	pe_botoes.position = Vector2(t.x - m - pe_botoes.size.x, t.y - m - 80)
	partes_box.position = Vector2(t.x * 0.5 - 200, t.y - m - 160)
	toast_l.size = Vector2(t.x, 60)
	toast_l.position = Vector2(0, t.y * 0.2)
	if minimapa:
		minimapa.position = Vector2(m, m)          # (v36) mapa no canto de cima, à esquerda
		rua_label.size = Vector2(520, 30)
		rua_label.position = Vector2(m, m + minimapa.size.y + 4)
		vel_label.position = Vector2(t.x - m - 150, t.y - m - 140 - 160)


# ---------------------------------------------------------------- teste automático (só com DROPS_TESTE)
var _cam_t: Camera3D
func _teste2() -> void:
	var ft := OS.get_environment("DROPS_FOTO")
	if _f == 10:
		intro = 0.0
		var l: Array = lombadas[0]
		var d := Vector3(l[2], 0, l[3])
		teletransportar(Vector3(l[0], 0.6, l[1]) - d * 9.0 + Vector3(-d.z, 0, d.x) * 1.4, atan2(d.x, d.z))
		ar_alvo = AR_MAX; rebaixo = AR_MAX; ar_alvo_t = AR_MAX; rebaixo_t = AR_MAX
	if _f == 40:
		carro.linear_velocity = carro.global_basis.z * 7.0
	if _f > 40 and _f < 140 and faisca.emitting and _f % 5 == 0:
		print("RASPOU f=", _f)
	if _f in [95, 112] and ft != "": get_viewport().get_texture().get_image().save_png(ft % _f)
	if _f == 125:
		_cam_t = Camera3D.new(); add_child(_cam_t); _cam_t.current = true
		var hx := mapa.xf("hangar")
		_cam_t.global_position = hx * Vector3(30, 25, 95)
		_cam_t.look_at(hx * Vector3(0, 5, 0))
		mapa.carregar_perto(hx.origin)
	if _f == 132 and ft != "": get_viewport().get_texture().get_image().save_png(ft % 132)
	if _f == 140:
		_cam_t.global_position = mapa.drops_ponto(Vector3(-6, 1.7, -10))
		_cam_t.look_at(mapa.drops_ponto(Vector3(2.3, 1.6, 2)))
		mapa.carregar_perto(_cam_t.global_position)
		var fwd := mapa.drops_xf.basis * Vector3(0, 0, 1)
		teletransportar(mapa.drops_ponto(Vector3(2.3, 0.6, -6.0)), atan2(fwd.x, fwd.z))
	if _f == 160: carro.linear_velocity = (mapa.drops_xf.basis * Vector3(0, 0, 1)) * 4.0
	if _f == 175 and ft != "": get_viewport().get_texture().get_image().save_png(ft % 175)
	if _f == 290 and ft != "": get_viewport().get_texture().get_image().save_png(ft % 290)
	if _f % 15 == 0 and _f > 140:
		print("f=%d local=%s oficina=%s portao=%.2f" % [_f, mapa.drops_local(carro.global_position).round(), _na_oficina, mapa.portao_aberto])
	if _f == 420: get_tree().quit()


func _teste3() -> void:
	var ft := OS.get_environment("DROPS_FOTO")
	var vistas := [[Vector3(-850, 0, -100), 10.0, 45.0], [Vector3(-700, 0, 300), 70.0, 260.0], [Vector3(250, 0, 250), 35.0, 90.0], [Vector3(-500, 0, -900), 6.0, 60.0]]
	for k in vistas.size():
		var f0: int = 20 + k * 60
		if _f == f0:
			intro = 0.0
			var mp := rede.mais_perto(vistas[k][0], 120.0)
			var q := Vector3(mp["ponto"].x, 0, mp["ponto"].y)
			var d := Vector3(mp["dir"].x, 0, mp["dir"].y)
			teletransportar(q + Vector3(-d.z, 0, d.x) * 1.8, atan2(d.x, d.z))
			if _cam_t == null:
				_cam_t = Camera3D.new(); _cam_t.far = 1500.0; add_child(_cam_t)
			_cam_t.current = true
			var c := q - d * 14.0
			_cam_t.global_position = mapa.no_chao(c, float(vistas[k][1]))
			_cam_t.look_at(mapa.no_chao(q + d * float(vistas[k][2]), 1.0))
			print("vista ", k, " em ", q.round(), " alt ", mapa.altura(q.x, q.z))
		if _f == f0 + 45 and ft != "":
			get_viewport().get_texture().get_image().save_png(ft % _f)
	if _f == 300: get_tree().quit()


## teste da oficina RP: elevador, parede das rodas, instalar as 4 e cabine de pintura
## teste 9: close na roda dianteira de cada aro (DROPS_RODAS="id1,id2" ou todos), com DROPS_COR_RODA opcional
var _t9_lista := []
func _teste9() -> void:
	var ft := OS.get_environment("DROPS_FOTO")
	if _f == 10:
		intro = 0.0
		_t9_lista = OS.get_environment("DROPS_RODAS").split(",") if OS.has_environment("DROPS_RODAS") else Dados.RODAS.map(func(r): return r[0])
		var fz := mapa.drops_xf.basis.z
		var mid := (float(dados["axF"]) + float(dados["axR"])) / 2.0
		teletransportar(mapa.drops_ponto(Oficina.ELEV) - mapa.drops_xf.basis * Oficina.ELEV_EIXO * mid, atan2((mapa.drops_xf.basis * Oficina.ELEV_EIXO).x, (mapa.drops_xf.basis * Oficina.ELEV_EIXO).z))
		if OS.has_environment("DROPS_COR_RODA"):
			Dados.mudar("cor_roda", OS.get_environment("DROPS_COR_RODA"))
	var k := (_f - 60) / 30
	var fase := (_f - 60) % 30
	if _f < 60:
		return
	if k >= _t9_lista.size():
		get_tree().quit()
		return
	if fase == 0:
		Dados.mudar("roda", _t9_lista[k])
		cfg = Dados.cfg()
		_criar_carro(carro.global_position, carro.rotation.y)
	if fase == 20 and rodas_vis.size() > 0:
		var w: Vector3 = rodas_vis[0].global_position
		var lado := carro.global_basis.x * (1.0 if carro.to_local(w).x > 0 else -1.0)
		var pos := w + lado * 1.25 + carro.global_basis.z * 0.35 + Vector3.UP * 0.15
		cam_teste = Transform3D(Basis(), pos).looking_at(w, Vector3.UP)
		usar_cam_teste = true
	if fase == 28 and ft != "":
		get_viewport().get_texture().get_image().save_png(ft % _t9_lista[k])


## teste 10: barracão do evento (entra de carro pelo portão e tira fotos lá dentro)
func _teste10() -> void:
	var ft := OS.get_environment("DROPS_FOTO")
	var foto := func(n: String) -> void:
		if ft != "":
			get_viewport().get_texture().get_image().save_png(ft % n)
	var bx := barracao.xf
	match _f:
		10:
			intro = 0.0
			var fz := bx.basis.z
			teletransportar(bx * Vector3(0, 0.4, 9.0), atan2(-fz.x, -fz.z))
		40:
			cam_teste = Transform3D(Basis(), bx * Vector3(-14, 9, 22)).looking_at(bx * Vector3(0, 3, -8), Vector3.UP)
			usar_cam_teste = true
		50:
			foto.call("0_fachada")
			usar_cam_teste = false
			Input.action_press("acelerar")
		150:
			Input.action_release("acelerar")
			Input.action_press("frear")
		200:
			Input.action_release("frear")
			print("t10 dentro: ", barracao.dentro_agora, " carro local ", (bx.affine_inverse() * carro.global_position).round())
			foto.call("1_dirigindo")
			cam_teste = Transform3D(Basis(), bx * Vector3(0, 3.0, -2.0)).looking_at(bx * Vector3(0, 1.0, -22), Vector3.UP)
			usar_cam_teste = true
		220:
			foto.call("2_corredor")
			cam_teste = Transform3D(Basis(), bx * Vector3(-1.5, 1.8, -6.0)).looking_at(bx * Vector3(-5.4, 0.7, -12.0), Vector3.UP)
		240:
			foto.call("3_carros")
			cam_teste = Transform3D(Basis(), bx * Vector3(1.5, 1.8, -20.0)).looking_at(bx * Vector3(5.4, 0.7, -12.0), Vector3.UP)
		260:
			foto.call("4_carros_b")
			cam_teste = Transform3D(Basis(), bx * Vector3(0, 2.0, -12.0)).looking_at(bx * Vector3(0, 2.0, -29), Vector3.UP)
		280:
			foto.call("5_fundo")
			cam_teste = Transform3D(Basis(), bx * Vector3(2.5, 2.6, -12.7)).looking_at(bx * Vector3(-8.0, 2.8, -12.7), Vector3.UP)
		300:
			foto.call("6_fotos_esq")
			cam_teste = Transform3D(Basis(), bx * Vector3(-2.5, 2.6, -9.0)).looking_at(bx * Vector3(8.0, 2.8, -9.0), Vector3.UP)
		320:
			foto.call("7_fotos_dir")
		330:
			get_tree().quit()


## (v40) laje: sobe a escada, joga sinuca, desce
func _teste14() -> void:
	# (fase 2) desmontagem com as mãos: tira a porta, carrega, guarda no cavalete, pega de volta e põe
	var ft := OS.get_environment("DROPS_FOTO")
	var foto := func(n: String) -> void:
		if ft != "":
			get_viewport().get_texture().get_image().save_png(ft % n)
	var cam := func(de: Vector3, para: Vector3) -> void:
		if _cam_t == null:
			_cam_t = Camera3D.new(); _cam_t.far = 300.0; _cam_t.fov = 70.0; add_child(_cam_t)
		_cam_t.current = true
		_cam_t.global_position = mapa.drops_ponto(de)
		_cam_t.look_at(mapa.drops_ponto(para))
	var ir := func(local: Vector3) -> void:
		pessoa.global_position = mapa.drops_ponto(local) + Vector3.UP * 0.1
	match _f:
		5:
			intro = 0.0
			for i in Dados.carros.size():
				if Dados.carros[i]["id"] == "saveirog5":
					Dados.idx = i
			Dados.mudar("sem_pecas", [])
			_criar_carro(carro.global_position + Vector3.UP * 0.8, carro.rotation.y)
		20:
			var mid := (float(dados["axF"]) + float(dados["axR"])) / 2.0
			var c := mapa.drops_ponto(Oficina.ELEV)
			var ez: Vector3 = mapa.drops_xf.basis * Oficina.ELEV_EIXO
			teletransportar(c - ez * mid, atan2(ez.x, ez.z))
		70:
			descer()
		80:
			cam.call(Vector3(3.5, 2.3, 13.0), Vector3(-2.5, 0.8, 19.0))
		95:
			foto.call("0_cabine")
			var c: Vector3 = visual.centro_peca("PFL")
			var lado: Vector3 = (c - carro.global_position)
			lado.y = 0.0
			pessoa.global_position = c + lado.normalized() * 0.6
			pessoa.global_position.y = mapa.drops_ponto(Vector3.ZERO).y + 0.1
		105:
			print("t14 acao: ", oficina._acao)
			oficina.interagir()
		185:
			cam.call(mapa.drops_local(pessoa.global_position) + Vector3(2.4, 1.7, -2.0), mapa.drops_local(pessoa.global_position) + Vector3(0, 1.0, 0))
		150:
			pessoa.desejo = Vector3(0, 0, 0)
		200:
			foto.call("1_segurando")
			var h: Node3D = oficina.desm._na_mao
			print("t14 carregando ", oficina.desm.carregando, " anim ", pessoa.atual, " sem ", Dados.cfg().get("sem_pecas"),
				" peça ", (h.global_position - pessoa.global_position) if h else Vector3.INF, " pai ", h.get_parent().name if h else "-", " vis ", h.is_visible_in_tree() if h else false)
			ir.call(Oficina.ELEV * 0.0 + Desmontagem.CAVALETE + Vector3(0.3, 0, -1.1))
		215:
			print("t14 acao cavalete: ", oficina._acao)
			oficina.interagir()
		240:
			cam.call(Desmontagem.CAVALETE + Vector3(1.8, 1.7, -2.6), Desmontagem.CAVALETE + Vector3(0, 0.7, 0))
		255:
			foto.call("2_cavalete")
			print("t14 holders ", oficina.desm._holders.keys(), " carregando '", oficina.desm.carregando, "'")
		265:
			print("t14 acao pegar: ", oficina._acao)
			oficina.interagir()
		320:
			print("t14 carregando de novo ", oficina.desm.carregando)
			var c: Vector3 = visual.centro_peca("PFL")
			var lado: Vector3 = (c - carro.global_position)
			lado.y = 0.0
			pessoa.global_position = c + lado.normalized() * 0.6
			pessoa.global_position.y = mapa.drops_ponto(Vector3.ZERO).y + 0.1
		335:
			print("t14 acao colocar: ", oficina._acao)
			oficina.interagir()
		400:
			print("t14 fim: sem ", Dados.cfg().get("sem_pecas"), " porta ", visual.tem_peca("PFL"), " carregando '", oficina.desm.carregando, "'")
			oficina._alvo_pintura = ""
			oficina._mudar("cor", "#d12a6b")
		560:
			cam.call(mapa.drops_local(pessoa.global_position) + Vector3(2.0, 1.7, -2.2), mapa.drops_local(pessoa.global_position) + Vector3(0, 1.0, 0))
		575:
			foto.call("3_pintando")
			cam.call(Vector3(2.5, 1.7, 12.6), Oficina.BOTOEIRA + Vector3(0, 1.2, 0))
		590:
			foto.call("4_botoeira")
			Dados.mudar("cor", "#f4f4f1")
			get_tree().quit()


func _teste13() -> void:
	# (fase 2) boneco trabalhando: G3 velha no elevador, lava a porta, desamassa o carro, pinta
	var ft := OS.get_environment("DROPS_FOTO")
	var foto := func(n: String) -> void:
		if ft != "":
			get_viewport().get_texture().get_image().save_png(ft % n)
	match _f:
		5:
			intro = 0.0
			for i in Dados.carros.size():
				if Dados.carros[i]["id"] == "saveirog3":
					Dados.idx = i
			Dados.mudar("sem_pecas", [])
			Dados.mudar("desgaste", {"carro": {"f": 0.65, "s": 0.45, "a": 0.5}})
			_criar_carro(carro.global_position + Vector3.UP * 0.8, carro.rotation.y)
		20:
			var mid := (float(dados["axF"]) + float(dados["axR"])) / 2.0
			var c := mapa.drops_ponto(Oficina.ELEV)
			var ez: Vector3 = mapa.drops_xf.basis * Oficina.ELEV_EIXO
			teletransportar(c - ez * mid, atan2(ez.x, ez.z))
		70:
			descer()
		80:
			pessoa.global_position = mapa.drops_ponto(Vector3(1.0, 0.1, 16.0))
			if _cam_t == null:
				_cam_t = Camera3D.new(); _cam_t.far = 300.0; _cam_t.fov = 65.0; add_child(_cam_t)
			_cam_t.current = true
			_cam_t.global_position = mapa.drops_ponto(Vector3(2.2, 2.0, 22.6))
			_cam_t.look_at(mapa.drops_ponto(Vector3(-2.4, 0.7, 18.0)))
		90:
			oficina._fazer_servico("PFL", "s", "LAVAR")
		330:
			foto.call("1_lavando")
			print("t13 anim ", pessoa.atual, " ferramenta ", pessoa._ferr != null)
		640:
			print("t13 desgaste depois de lavar: ", Dados.cfg().get("desgaste"), " ocupado ", pessoa.ocupado())
			oficina._fazer_servico("carro", "a", "DESAMASSAR")
		900:
			foto.call("2_desamassando")
			print("t13 anim ", pessoa.atual)
		1200:
			print("t13 desgaste depois: ", Dados.cfg().get("desgaste"), " ocupado ", pessoa.ocupado())
			oficina._alvo_pintura = ""
			oficina._mudar("cor", "#1f6fd1")
		1380:
			foto.call("3_pintando")
			print("t13 anim ", pessoa.atual, " cor ainda ", Dados.cfg().get("cor"))
		1600:
			foto.call("4_pintado")
			print("t13 cor depois ", Dados.cfg().get("cor"))
			Dados.mudar("desgaste", {"carro": {"f": 0.65, "s": 0.45, "a": 0.5}})
			Dados.mudar("cor", "#8d1d1d")
			get_tree().quit()


func _teste16() -> void:
	# desmontagem com as mãos, caminho completo: tira 2 peças, guarda no cavalete, recria o carro,
	# pega do cavalete e coloca de volta. DROPS_T16_CARRO = id do carro (padrão f150)
	var ft := OS.get_environment("DROPS_FOTO")
	var foto := func(n: String) -> void:
		if ft != "":
			get_viewport().get_texture().get_image().save_png(ft % n)
	var cid := OS.get_environment("DROPS_T16_CARRO") if OS.has_environment("DROPS_T16_CARRO") else "f150"
	var ids: Array = (OS.get_environment("DROPS_T16_PECAS") if OS.has_environment("DROPS_T16_PECAS") else "PFL,PTR").split(",")
	var perto := func(id: String) -> void:
		var c: Vector3 = visual.centro_peca(id)
		var lc: Vector3 = carro.global_transform.affine_inverse() * c
		var off: Vector3
		if id == "PCA" or id == "PTR":
			off = carro.global_basis.z.normalized() * signf(lc.z) * 0.75
		else:
			off = carro.global_basis.x.normalized() * signf(lc.x) * 0.6
		var k := 0.0
		while k < 4.0 and oficina.desm._dist_peca(c + off.normalized() * k, id) < 0.65:
			k += 0.05
		pessoa.global_position = c + off.normalized() * k
		pessoa.global_position.y = mapa.drops_ponto(Vector3.ZERO).y + 0.1
	var no_cavalete := func() -> void:
		pessoa.global_position = mapa.drops_ponto(Desmontagem.CAVALETE + Vector3(0.0, 0.1, -1.0))
	var log := func(o: String) -> void:
		print("t16 [", _f, "] ", o, " pos=", mapa.drops_local(pessoa.global_position), " | acao='", oficina._acao, "' na_mao='", oficina.desm.carregando, "' holders=", oficina.desm._holders.keys(), " sem=", Dados.cfg().get("sem_pecas"), " pecas_visiveis=", visual.pecas.keys().filter(func(k): return visual.tem_peca(k)))
	var F := 60   # frames por passo (o gesto leva 0,85 s)
	var passo := int(_f / F)
	if _f % F != 0:
		return
	match passo:
		1:
			intro = 0.0
			for i in Dados.carros.size():
				if Dados.carros[i]["id"] == cid:
					Dados.idx = i
			Dados.mudar("sem_pecas", [])
			_criar_carro(carro.global_position + Vector3.UP * 0.8, carro.rotation.y)
		2:
			var mid := (float(dados["axF"]) + float(dados["axR"])) / 2.0
			var c := mapa.drops_ponto(Oficina.ELEV)
			var ez: Vector3 = mapa.drops_xf.basis * Oficina.ELEV_EIXO
			teletransportar(c - ez * mid, atan2(ez.x, ez.z))
		3:
			descer()
		4:
			log.call("desceu; no elevador=" + str(oficina.carro_no_elevador()))
			perto.call(ids[0])
		5:
			log.call("perto da peca " + ids[0])
			for k in visual.pecas:
				print("t16   dist ", k, " = ", oficina.desm._dist_peca(pessoa.global_position, k), " centro=", mapa.drops_local(visual.centro_peca(k)), " caixa=", visual.caixa_peca(k))
			print("t16   ocupado=", pessoa.ocupado(), " pode=", oficina.desm._pode())
			_t16_agir()
		6:
			log.call("tirou " + ids[0])
			no_cavalete.call()
		7:
			log.call("no cavalete")
			_t16_agir()
		8:
			log.call("guardou")
			perto.call(ids[1])
		9:
			log.call("perto da peca " + ids[1])
			_t16_agir()
		10:
			log.call("tirou " + ids[1])
			no_cavalete.call()
		11:
			_t16_agir()
		12:
			log.call("guardou 2")
			if _cam_t == null:
				_cam_t = Camera3D.new(); _cam_t.far = 300.0; _cam_t.fov = 70.0; add_child(_cam_t)
			_cam_t.current = true
			_cam_t.global_position = mapa.drops_ponto(Desmontagem.CAVALETE + Vector3(2.5, 1.8, -3.6))
			_cam_t.look_at(mapa.drops_ponto(Desmontagem.CAVALETE + Vector3(0, 0.6, 0)))
		13:
			foto.call("1_cavalete")
			_cam_t.current = false
			# sai do carro e volta (recria o carro, como trocar de carro / voltar da garagem)
			entrar_carro_ja()
		14:
			log.call("entrou no carro")
			descer()
		15:
			log.call("desceu de novo")
			no_cavalete.call()
		16:
			log.call("no cavalete depois de entrar/sair")
			_t16_agir()
		17:
			log.call("pegou")
			perto.call(oficina.desm.carregando if oficina.desm.carregando != "" else ids[0])
		18:
			log.call("perto do lugar")
			_t16_agir()
		19:
			log.call("colocou")
			no_cavalete.call()
		20:
			_t16_agir()
		21:
			log.call("pegou 2")
			perto.call(oficina.desm.carregando if oficina.desm.carregando != "" else ids[1])
		22:
			log.call("perto do lugar 2")
			_t16_agir()
		23:
			log.call("colocou 2")
			_cam_t.current = true
		24:
			foto.call("2_cavalete_vazio")
			# estado quebrado de propósito: salvo diz que falta a porta, mas o carro mostra; mão "fantasma"
			Dados.mudar("sem_pecas", ["PFL", "PFL", "XYZ"])
			visual.mostrar_peca("PFL", true)
			oficina.desm.carregando = "PRR"
			oficina.desm._na_mao = null
			log.call("quebrado de proposito")
		26:
			log.call("depois de conferir")
			Dados.mudar("sem_pecas", [])
		28:
			log.call("depois de limpar")
			get_tree().quit()


func _t16_agir() -> void:
	if oficina._acao == "PINTAR" or oficina._acao == "":
		print("t16   (nao apertou: acao='", oficina._acao, "')")
		return
	oficina.interagir()


func _teste12() -> void:
	# (fase 2) desmontagem: Astral no elevador, tira porta e capô, olha o cavalete, põe a porta de volta
	var ft := OS.get_environment("DROPS_FOTO")
	var foto := func(n: String) -> void:
		if ft != "":
			get_viewport().get_texture().get_image().save_png(ft % n)
	var perto := func(id: String) -> void:
		var c: Vector3 = visual.centro_peca(id)
		var lado: Vector3 = (c - carro.global_position)
		lado.y = 0.0
		pessoa.global_position = c + lado.normalized() * 0.55
		pessoa.global_position.y = mapa.drops_ponto(Vector3.ZERO).y + 0.1
	match _f:
		5:
			intro = 0.0
			for i in Dados.carros.size():
				if Dados.carros[i]["id"] == OS.get_environment("DROPS_T12_CARRO") if OS.has_environment("DROPS_T12_CARRO") else Dados.carros[i]["id"] == "astrag":
					Dados.idx = i
			Dados.mudar("sem_pecas", [])
			_criar_carro(carro.global_position + Vector3.UP * 0.8, carro.rotation.y)
		20:
			var mid := (float(dados["axF"]) + float(dados["axR"])) / 2.0
			var c := mapa.drops_ponto(Oficina.ELEV)
			var ez: Vector3 = mapa.drops_xf.basis * Oficina.ELEV_EIXO
			teletransportar(c - ez * mid, atan2(ez.x, ez.z))
		70:
			print("t12 carro ", dados["id"], " no elevador: ", oficina.carro_no_elevador(), " pecas ", visual.pecas.keys())
			descer()
		80:
			perto.call("PFL")
		90:
			print("t12 acao porta: ", oficina._acao)
			oficina.interagir()
		100:
			foto.call("1_tirando")
		115:
			var c: Vector3 = visual.centro_peca("PCA")
			pessoa.global_position = c + carro.global_basis.x * 1.05
			pessoa.global_position.y = mapa.drops_ponto(Vector3.ZERO).y + 0.1
		125:
			print("t12 acao capo: ", oficina._acao)
			oficina.interagir()
		160:
			print("t12 sem_pecas: ", Dados.cfg().get("sem_pecas"))
			for id in oficina.desm._holders:
				var h: Node3D = oficina.desm._holders[id]
				for mi in h.find_children("*", "MeshInstance3D", true, false):
					var bb: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
					print("t12   malha ", mi.name, " de ", mapa.drops_local(bb.position), " ate ", mapa.drops_local(bb.end), " vis ", (mi as MeshInstance3D).visible, " camadas ", (mi as MeshInstance3D).layers, " vr ", (mi as MeshInstance3D).visibility_range_end)
				print("t12 holder ", id, " local=", mapa.drops_local(h.global_position), " vis=", h.is_visible_in_tree(), " filhos=", h.get_child_count(), " malhas=", h.find_children("*", "MeshInstance3D", true, false).size())
			if _cam_t == null:
				_cam_t = Camera3D.new(); _cam_t.far = 300.0; _cam_t.fov = 70.0; add_child(_cam_t)
			_cam_t.current = true
			_cam_t.global_position = mapa.drops_ponto(Vector3(3.6, 2.1, 19.3))
			_cam_t.look_at(mapa.drops_ponto(Vector3(0.2, 0.6, 21.6)))
		175:
			foto.call("2_cavalete")
			_cam_t.global_position = mapa.drops_ponto(Vector3(1.6, 1.9, 13.6))
			_cam_t.look_at(mapa.drops_ponto(Vector3(-2.2, 0.8, 18.0)))
		190:
			foto.call("3_carro_sem")
			_cam_t.current = false
			perto.call("PFL")
		200:
			print("t12 acao volta: ", oficina._acao)
			oficina.interagir()
		240:
			print("t12 sem_pecas depois: ", Dados.cfg().get("sem_pecas"), " porta visivel ", visual.tem_peca("PFL"))
			_cam_t.current = true
		255:
			foto.call("4_cavalete_depois")
			oficina._mudar("peca:PFL", "#1fa34a")    # porta da frente esquerda verde
			oficina._mudar("peca:PFR", "#f2c21b")    # e a direita amarela
			_cam_t.global_position = mapa.drops_ponto(Vector3(1.8, 1.7, 21.8))
			_cam_t.look_at(mapa.drops_ponto(Vector3(-2.4, 0.8, 18.4)))
		270:
			foto.call("5_portas_coloridas")
			_cam_t.global_position = mapa.drops_ponto(Vector3(1.8, 1.7, 15.0))
			_cam_t.look_at(mapa.drops_ponto(Vector3(-2.4, 0.8, 18.6)))
		285:
			foto.call("5b_outro_lado")
			_cam_t.current = false
			oficina.abrir_pintura()
			oficina._alvo_pintura = "PFL"
			oficina._encher_painel()
		310:
			foto.call("6_painel")
			print("t12 cores: ", Dados.cfg().get("cores_pecas"))
			oficina.fechar_pintura()
			Dados.mudar("sem_pecas", [])
			Dados.mudar("cores_pecas", {})
			get_tree().quit()


func _teste11() -> void:
	var ft := OS.get_environment("DROPS_FOTO")
	var foto := func(n: String) -> void:
		if ft != "":
			get_viewport().get_texture().get_image().save_png(ft % n)
	var lj: Laje = oficina.laje
	var fz := mapa.drops_xf.basis.z
	var mid := (float(dados["axF"]) + float(dados["axR"])) / 2.0
	match _f:
		10:
			intro = 0.0
			Engine.time_scale = 3.0   # escada e bolas andam por tempo: acelera pro teste caber
			Engine.max_physics_steps_per_frame = 24
			var c := mapa.drops_ponto(Oficina.ELEV)
			var ez: Vector3 = mapa.drops_xf.basis * Oficina.ELEV_EIXO
			teletransportar(c - ez * mid, atan2(ez.x, ez.z))
		50:
			descer()
		60:
			pessoa.global_position = mapa.drops_ponto(Laje.ESC_BAIXO + Vector3(0.1, 0.1, 0))
			var bx := mapa.drops_xf.basis.x
			ape_yaw = atan2(bx.x, bx.z)
		80:
			print("t11 acao no pe da escada: ", oficina._acao)
			foto.call("1_escada")
			oficina.interagir()
		120:
			foto.call("2_subindo")
		200:
			print("t11 em cima: y=", snappedf(oficina.local(pessoa.global_position).y, 0.01), " acao=", oficina._acao)
			foto.call("3_laje")
		210:
			pessoa.global_position = mapa.drops_ponto(Laje.MESA + Vector3(0.9, 0.1, -1.7))
			ape_yaw = atan2(-fz.x, -fz.z) + 0.6
		240:
			print("t11 acao na mesa: ", oficina._acao)
			foto.call("4_mesa")
			oficina.interagir()
		280:
			print("t11 sinuca ativa: ", lj.sinuca.ativo)
			foto.call("5_sinuca")
			lj.sinuca._tacar(0.95)
		300:
			foto.call("6_tacada")
		520:
			var n := 0
			for i in range(1, 16):
				if lj.sinuca.dentro[i]: n += 1
			print("t11 depois da tacada: rodando=", lj.sinuca.rodando, " encaçapadas=", n, " tacadas=", lj.sinuca.tacadas, " vez=", lj.sinuca.vez, " grupos=", lj.sinuca.grupo)
			foto.call("7_depois")
			if lj.sinuca.vez == 0 and not lj.sinuca.rodando:
				lj.sinuca._tacar(0.5)   # passa a vez pra máquina jogar
		600, 700, 800, 900, 1000, 1100:
			var n := 0
			for i in range(1, 16):
				if lj.sinuca.dentro[i]: n += 1
			print("t11 jogo: vez=", lj.sinuca.vez, " grupos=", lj.sinuca.grupo, " encaçapadas=", n, " tacadas=", lj.sinuca.tacadas, " ia_t=", snappedf(lj.sinuca._ia_t, 0.1))
			if _f == 700: foto.call("7b_maquina")
			if lj.sinuca.vez == 0 and not lj.sinuca.rodando:
				lj.sinuca.mira = Vector2.from_angle(randf() * TAU)
				lj.sinuca._tacar(0.6)
		1110:
			lj.sinuca.sair()
		1120:
			pessoa.global_position = mapa.drops_ponto(Laje.ESC_TOPO + Vector3(0, 0.1, 0))
		1140:
			print("t11 acao no topo: ", oficina._acao)
			oficina.interagir()
		1290:
			print("t11 desceu: y=", snappedf(oficina.local(pessoa.global_position).y, 0.01))
			foto.call("8_desceu")
		1300:
			get_tree().quit()


func _teste8() -> void:
	var ft := OS.get_environment("DROPS_FOTO")
	var foto := func(n: String) -> void:
		if ft != "":
			get_viewport().get_texture().get_image().save_png(ft % n)
	var fz := mapa.drops_xf.basis.z
	var mid := (float(dados["axF"]) + float(dados["axR"])) / 2.0
	match _f:
		10:
			intro = 0.0
			var c := mapa.drops_ponto(Oficina.ELEV)
			var ez: Vector3 = mapa.drops_xf.basis * Oficina.ELEV_EIXO
			teletransportar(c - ez * mid, atan2(ez.x, ez.z))
		60:
			print("t8 no elevador: ", oficina.carro_no_elevador())
			descer()
		70:
			pessoa.global_position = mapa.drops_ponto(Vector3(3.2, 0.1, 17.5))
			ape_yaw = atan2(-mapa.drops_xf.basis.x.x, -mapa.drops_xf.basis.x.z)
		90:
			print("t8 acao rack: ", oficina._acao)
			foto.call("1_rack")
			oficina.interagir()
		100:
			print("t8 segurando: ", oficina.segurando)
			pessoa.global_position = mapa.drops_ponto(Vector3(2.9, 0.1, 15.5))
		108:
			foto.call("1b_segurando")
		104:
			pessoa.global_position = mapa.drops_ponto(Oficina.BOTOEIRA + Vector3(0.5, 0.1, 0.3))   # no botão do elevador
		110:
			print("t8 acao no botão: ", oficina._acao)
			oficina.interagir()   # sobe o elevador
		260:
			print("t8 alto: ", oficina.carro_alto, " altura ", oficina.altura)
			foto.call("2_elevador")
		270, 380, 490, 600:
			var i := [270, 380, 490, 600].find(_f)
			var fora := carro.global_basis.x * signf((carro.global_transform.affine_inverse() * rodas_vis[i].global_position).x)
			pessoa.global_position = rodas_vis[i].global_position + fora * 0.75
			pessoa.global_position.y = mapa.drops_ponto(Vector3.ZERO).y + 0.1
		280, 390, 500, 610:
			print("t8 acao roda: ", oficina._acao, " pessoa=", mapa.drops_local(pessoa.global_position), " rodas=", [mapa.drops_local(rodas_vis[0].global_position), mapa.drops_local(rodas_vis[2].global_position)])
			oficina.interagir()
		340:
			foto.call("3_instalando")
		370:
			print("t8 depois da 1a roda: rodas=", Dados.cfg().get("rodas", "-"), " roda=", Dados.cfg()["roda"])
		712:
			pessoa.global_position = mapa.drops_ponto(Oficina.BOTOEIRA + Vector3(0.5, 0.1, 0.3))
		722:
			print("t8 no botão? ", mapa.drops_local(pessoa.global_position), " subindo ", oficina.subindo, " instalando ", oficina._instalando)
		730:
			print("t8 roda salva: ", Dados.cfg()["roda"], " segurando '", oficina.segurando, "' acao ", oficina._acao,)
			foto.call("3b_instalado")
			oficina.interagir()   # desce
		900:
			print("t8 desceu: alto=", oficina.carro_alto, " elev_y=", elev_y, " aros=", rodas_vis.map(func(r): return (r.find_child("gira", true, false) as Node3D).get_child(1).scene_file_path.get_file()))
			oficina._soltar()
			pessoa.global_position = mapa.drops_ponto(Vector3(-3.4, 0.1, 15.0))
		920:
			print("t8 acao cabine: ", oficina._acao)
			oficina.interagir()
		940:
			oficina._mudar("cor", "#2be7ff")
		1000:
			foto.call("4_pintura")
			oficina.fechar_pintura()
		1010:
			get_tree().quit()


## teste de travada: o carro "anda" 25 m/s em linha reta pela cidade e mede o pior quadro da montagem dos blocos
var _t7_dir := Vector3.ZERO
var _t7_pior := 0
var _t7_falta := 0
func _teste7() -> void:
	if _f == 10:
		intro = 0.0
		_t7_dir = Vector3(1, 0, 0.35).normalized()
		if OS.has_environment("DROPS_T7_TEMPO"):   # acelera o tempo (ver o trânsito andando por minutos)
			Engine.time_scale = float(OS.get_environment("DROPS_T7_TEMPO"))
			Engine.max_physics_steps_per_frame = 40
	if _f > 10 and carro:
		var t0 := Time.get_ticks_usec()
		var p := carro.global_position + _t7_dir * float(OS.get_environment("DROPS_T7_VEL") if OS.has_environment("DROPS_T7_VEL") else "0.85")
		carro.global_position = mapa.no_chao(p, 0.6)
		carro.linear_velocity = Vector3.ZERO
		_t7_pior = maxi(_t7_pior, Time.get_ticks_usec() - t0)
	if _f > 30 and carro:
		# bloco em volta do carro (até 200 m do centro) que ainda não apareceu = "rua demorando pra carregar"
		for nome in mapa.dados["blocos"]:
			var c: Array = mapa.dados["blocos"][nome]["centro"]
			if Vector2(carro.global_position.x - c[0], carro.global_position.z - c[1]).length() < 200.0:
				var n: Node = mapa._carregados.get(nome)
				if n == null or not (n as Node3D).visible:
					_t7_falta += 1
	if _f % 60 == 0:
		var tr_par := 0
		for t in role.transito:
			if float(t["sp"]) < 0.5:
				tr_par += 1
		print("t7 f=", _f, " pos=", carro.global_position.round(), " pior_montagem_us=", mapa._perf_max, " fila=", mapa._fila.size(), " quadros_com_bloco_faltando=", _t7_falta, " transito_parado=", tr_par, "/", role.transito.size())
		mapa._perf_max = 0
	if _f == 600: get_tree().quit()


func _teste4() -> void:
	var ft := OS.get_environment("DROPS_FOTO")
	if _f == 30:
		teletransportar(mapa.posicao_spawn(), carro.rotation.y + PI / 2.0)
		abrir_mapa()
		mapa_zoom = 0.9
	if _f == 60 and ft != "": get_viewport().get_texture().get_image().save_png(ft % 60)
	if _f == 70:
		marcar_gps(mapa.no_chao(mapa.xf("hangar").origin + Vector3(0, 0, 40)))
		mapa_zoom = 0.35
	if _f == 100 and ft != "": get_viewport().get_texture().get_image().save_png(ft % 100)
	if _f == 110: fechar_mapa()
	if _f == 150 and ft != "": get_viewport().get_texture().get_image().save_png(ft % 150)
	if _f == 160: get_tree().quit()


func _teste5() -> void:
	var ft := OS.get_environment("DROPS_FOTO")
	var vistas := [
		[mapa.drops_ponto(Vector3(2.3, 1.6, 1.0)), mapa.drops_ponto(Vector3(1.6, 1.4, 23.0))],     # do portão olhando pra dentro (foto 1)
		[mapa.drops_ponto(Vector3(1.2, 1.6, 14.0)), mapa.drops_ponto(Vector3(1.0, 1.7, 23.5))],    # oficina, logo no fundo (foto 2)
		[mapa.drops_ponto(Vector3(3.5, 1.6, 15.0)), mapa.drops_ponto(Vector3(-3.5, 1.2, 19.0))],   # vão pra cabine branca (foto 3)
		[Vector3(662.7, 0, 571.4), Vector3(720.0, 0, 571.0)],                                       # rua, igual ao vídeo do Street View
		[Vector3(640.0, 0, 571.0), Vector3(560.0, 0, 572.0)],
		[mapa.drops_ponto(Vector3(-1.0, 1.7, -8.6)), mapa.drops_ponto(Vector3(1.0, 2.6, 3.0))],   # frente da Drops
		[Vector3(600.0, 0, 568.0), Vector3(620.0, 0, 585.0)],   # casas do lado, de perto
		[Vector3(470.0, 0, 572.0), Vector3(505.0, 0, 590.0)]]   # lado sul da Gastão, a oeste da Drops
	if OS.has_environment("DROPS_VISTAS"):   # "ax,az,bx,bz;..." câmera a 1,6 m olhando pra b
		vistas = []
		for v in OS.get_environment("DROPS_VISTAS").split(";"):
			var n := v.split(",")
			vistas.append([Vector3(float(n[0]), 0, float(n[1])), Vector3(float(n[2]), 0, float(n[3]))])
	if OS.has_environment("DROPS_POLICIA"):   # vistas da polícia: posto, delegacia e as blitz
		vistas = []
		if mapa.tem("posto"):
			var px := mapa.xf("posto")
			vistas.append([px * Vector3(15.0, 0, 17.0), px * Vector3(7.5, 0, 8.5)])
		vistas.append([del_xf * Vector3(-60.0, 0, 0.5), del_xf * Vector3(-66.0, 0, -11.0)])
		for i in policia.blitz.size():
			var b: Vector3 = policia.blitz[i]
			var dd: Vector3 = policia._blitz_dir[i]
			vistas.append([b - dd * 16.0 + Vector3(dd.z, 0, -dd.x) * -1.5, b + Vector3(dd.z, 0, -dd.x) * 2.0])
	if OS.has_environment("DROPS_CIMA"):   # vista de cima da região da Drops (pra escolher lugar)
		vistas = [[mapa.drops_ponto(Vector3(0, 60, 10.01)), mapa.drops_ponto(Vector3(0, 0, 10))],
			[mapa.drops_ponto(Vector3(0, 30, -30)), mapa.drops_ponto(Vector3(0, 0, 12))]]
	if OS.has_environment("DROPS_CONC") and mapa.tem("concessionaria"):   # vistas da concessionária
		var cc := mapa.xf("concessionaria")
		vistas = [[cc * Vector3(0, 6, 26), cc * Vector3(0, 3, 0)], [cc * Vector3(-18, 8, 18), cc * Vector3(0, 2, -4)],
			[cc * Vector3(16, 4, 12), cc * Vector3(-4, 2, -6)], [cc * Vector3(0, 2.2, 4), cc * Vector3(0, 1.5, -12)]]
	if OS.has_environment("DROPS_OFICINA"):   # vistas de dentro da oficina (coordenadas da Drops, já com altura)
		vistas = [[mapa.drops_ponto(Vector3(2.5, 1.7, 19.0)), mapa.drops_ponto(Vector3(-2.0, 1.0, 26.5))],
			[mapa.drops_ponto(Vector3(0.8, 1.6, 23.0)), mapa.drops_ponto(Vector3(-3.0, 0.9, 27.5))],
			[mapa.drops_ponto(Vector3(-1.0, 1.6, 24.5)), mapa.drops_ponto(Vector3(3.5, 1.2, 27.5))],
			[mapa.drops_ponto(Vector3(-4.5, 1.6, 24.0)), mapa.drops_ponto(Vector3(-1.0, 1.0, 28.0))],
			[mapa.drops_ponto(Vector3(3.6, 2.3, 13.6)), mapa.drops_ponto(Vector3(-2.55, 0.4, 18.0))]]
	if OS.has_environment("DROPS_OF_VISTAS"):   # "ax,ay,az,bx,by,bz;..." em coordenadas da Drops (pra testar a oficina)
		vistas = []
		for v in OS.get_environment("DROPS_OF_VISTAS").split(";"):
			var n := v.split(",")
			vistas.append([mapa.drops_ponto(Vector3(float(n[0]), float(n[1]), float(n[2]))), mapa.drops_ponto(Vector3(float(n[3]), float(n[4]), float(n[5])))])
	if OS.has_environment("DROPS_GALPAO"):   # vistas do galpão do encontro
		var gx := galpao_xf
		vistas = [[gx * Vector3(6, 0, GALPAO_Z + 14), gx * Vector3(0, 0, 0)], [gx * Vector3(-15, 0, 6), gx * Vector3(-8, 0, 15)],
			[gx * Vector3(8, 0, -6), gx * Vector3(-GALPAO_X, 0, -2)], [gx * Vector3(-6, 0, 4), gx * Vector3(GALPAO_X, 0, 10)],
			[gx * Vector3(0, 0, 8), gx * Vector3(0, 0, -GALPAO_Z)],
			[gx * Vector3(-11, 0, -4.12), gx * Vector3(-GALPAO_X, 2.5, -4.12)], [gx * Vector3(11, 0, 4.12), gx * Vector3(GALPAO_X, 2.5, 4.12)]]
	if _f == 15 and ft != "": get_viewport().get_texture().get_image().save_png(ft % 15)
	for k in vistas.size():
		var f0: int = 30 + k * 30
		if _f == f0:
			intro = 0.0
			if _cam_t == null:
				_cam_t = Camera3D.new(); _cam_t.far = 900.0; _cam_t.fov = 72.0; add_child(_cam_t)
			_cam_t.current = true
			var a: Vector3 = vistas[k][0]
			var b: Vector3 = vistas[k][1]
			if OS.has_environment("DROPS_VISTAS"):
				a = mapa.no_chao(a, 1.6); b = mapa.no_chao(b, 1.2)
			elif OS.has_environment("DROPS_OFICINA") or OS.has_environment("DROPS_CIMA") or OS.has_environment("DROPS_CONC") or OS.has_environment("DROPS_OF_VISTAS"):
				pass
			elif OS.has_environment("DROPS_POLICIA") or OS.has_environment("DROPS_GALPAO"):
				a = mapa.no_chao(a, 2.4); b = mapa.no_chao(b, 0.9)
			elif k == 3 or k == 4 or k >= 6:
				a = mapa.no_chao(a, 2.4); b = mapa.no_chao(b, 1.8)
			_cam_t.global_position = a
			_cam_t.look_at(b)
			mapa.carregar_perto(a)
		if _f == f0 + 25 and ft != "":
			get_viewport().get_texture().get_image().save_png(ft % _f)
	if _f % 30 == 0:
		print("f=%d fps=%d prims=%d draws=%d" % [_f, Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	if _f == 45 and OS.has_environment("DROPS_PERF"):
		var ns := 0
		var vis := 0
		var luzes := 0
		for mi in visual.find_children("*", "MeshInstance3D", true, false):
			ns += (mi as MeshInstance3D).mesh.get_surface_count() if (mi as MeshInstance3D).mesh else 0
			if (mi as MeshInstance3D).is_visible_in_tree():
				vis += (mi as MeshInstance3D).mesh.get_surface_count() if (mi as MeshInstance3D).mesh else 0
		for l in get_tree().root.find_children("*", "Light3D", true, false):
			if (l as Light3D).is_visible_in_tree(): luzes += 1
		print("CARRO superficies=", ns, " visiveis=", vis, " luzes_visiveis=", luzes)
	if _f == 30 + vistas.size() * 30: get_tree().quit()


func _roteiro_teste() -> void:
	_f += 1
	if OS.get_environment("DROPS_TESTE") == "5":
		_teste5()
		return
	if OS.get_environment("DROPS_TESTE") == "6":   # a pé: desce do carro e anda
		var ft6 := OS.get_environment("DROPS_FOTO")
		if _f == 20:
			intro = 0.0
			descer()
		if _f == 45 and OS.has_environment("DROPS_CELULAR"):
			_abrir_ar()
		if _f > 40 and _f < 140 and pessoa:
			pessoa.desejo = -(pessoa.global_position - carro.global_position).normalized() * 0.0 + Vector3(sin(ape_yaw + PI), 0, cos(ape_yaw + PI)) * 0.6
		if _f in [60, 100, 160] and ft6 != "":
			get_viewport().get_texture().get_image().save_png(ft6 % _f)
		if _f == 170: get_tree().quit()
		return
	if OS.get_environment("DROPS_TESTE") == "8":
		_teste8()
		return
	if OS.get_environment("DROPS_TESTE") == "9":
		_teste9()
		return
	if OS.get_environment("DROPS_TESTE") == "10":
		_teste10()
		return
	if OS.get_environment("DROPS_TESTE") == "11":
		_teste11()
		return
	if OS.get_environment("DROPS_TESTE") == "15":   # batida: frente, lado e traseira
		if _f == 30:
			intro = 0.0
			Dados.mudar("desgaste", {})
		if _f in [60, 90, 120] and not pe:
			var dirs := {60: carro.global_basis.z, 90: carro.global_basis.x, 120: -carro.global_basis.z}
			_vel_ant = carro.linear_velocity + dirs[_f] * 12.0
		if _f in [62, 92, 122]:
			print("t15 ", _f, " desgaste ", Dados.cfg().get("desgaste"))
		if _f == 130:
			Dados.mudar("desgaste", {})
			get_tree().quit()
		return
	if OS.get_environment("DROPS_TESTE") == "14":
		_teste14()
		return
	if OS.get_environment("DROPS_TESTE") == "13":
		_teste13()
		return
	if OS.get_environment("DROPS_TESTE") == "16":
		_teste16()
		return
	if OS.get_environment("DROPS_TESTE") == "12":
		_teste12()
		return
	if OS.get_environment("DROPS_TESTE") == "7":
		_teste7()
		return
	if OS.get_environment("DROPS_TESTE") == "4":
		_teste4()
		return
	if OS.get_environment("DROPS_TESTE") == "3":
		_teste3()
		return
	if OS.get_environment("DROPS_TESTE") == "2":
		_teste2()
		return
	var ft := OS.get_environment("DROPS_FOTO")
	var foto_em := func(f: int): if ft != "" and _f == f: get_viewport().get_texture().get_image().save_png(ft % f)
	foto_em.call(40)
	foto_em.call(120)
	if _f == 20: Input.action_press("acelerar", 0.45)
	if _f == 200:
		# lombada perto da Drops, aterrado
		var l: Array = lombadas[0]
		var d := Vector3(l[2], 0, l[3])
		teletransportar(Vector3(l[0], 0.6, l[1]) - d * 14.0 + Vector3(-d.z, 0, d.x) * 1.5, atan2(d.x, d.z))
		ar_alvo = AR_MAX; rebaixo = AR_MAX; ar_alvo_t = AR_MAX; rebaixo_t = AR_MAX
		Input.action_press("acelerar", 0.35)
	foto_em.call(262)
	if _f == 290:
		Input.action_release("acelerar")
		var l2 := del_xf * Vector3(-75, 0.6, 2.0)
		var d2 := del_xf.basis * Vector3(1, 0, 0)
		teletransportar(l2, atan2(d2.x, d2.z))
		carro.linear_velocity = d2 * 6.0
		Input.action_press("acelerar", 0.25)
	foto_em.call(345)
	if _f == 360:
		Input.action_release("acelerar")
		var hx := mapa.xf("hangar")
		teletransportar(hx * Vector3(6, 0.6, 50), hx.basis.get_euler().y + PI)
	if _f == 380: cam_yaw = PI
	foto_em.call(430)
	if _f == 440:
		var px := mapa.xf("posto")
		teletransportar(px * Vector3(-30, 0.6, 30), px.basis.get_euler().y + PI * 0.8)
	foto_em.call(500)
	if _f == 510:
		teletransportar(mapa.drops_ponto(Vector3(2.3, 0.6, -9.0)), atan2((mapa.drops_xf.basis * Vector3(0, 0, 1)).x, (mapa.drops_xf.basis * Vector3(0, 0, 1)).z))
		Input.action_press("acelerar", 0.3)
	foto_em.call(600)
	if _f % 30 == 0:
		print("f=%d pos=%s vel=%.1f fps=%d rua=%s raspa=%s prims=%d draws=%d transito=%d" % [_f, carro.global_position.round(), carro.linear_velocity.length(), Engine.get_frames_per_second(), rua_atual, faisca.emitting,
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), role.transito.size()])
	if _f == 640:
		print("na_oficina=", _na_oficina)
		get_tree().quit()


## o outro carro parado dentro da oficina (decoração, com colisão)
func _carro_parado() -> void:
	var ids := []
	for c in Dados.carros:
		if c["id"] != Dados.carro()["id"]:
			ids.append(c["id"])
	var pref := "golg5" if "golg5" in ids else str(ids[0])
	var i := 0
	for k in Dados.carros.size():
		if Dados.carros[k]["id"] == pref:
			i = k
	var cfg := Dados.cfg(i)
	cfg["cor"] = "#f2f2ee"
	cfg["acabamento"] = "metal"
	cfg["som"] = "off"
	cfg["neon"] = "off"
	var cv := CarroVisual.new()
	add_child(cv)
	cv.montar(Dados.carros[i], cfg, true)
	var fs := mapa.drops_xf.basis * Vector3(0, 0, -1)
	cv.global_position = mapa.drops_ponto(CARRO_PARADO_LOCAL)
	cv.rotation.y = atan2(fs.x, fs.z) + 0.08
	var corpo := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(float(Dados.carros[i]["W"]), 1.3, cv.comprimento)
	col.shape = box
	col.position = Vector3(0, 0.7, (cv.frente_z + cv.tras_z) / 2.0)
	corpo.add_child(col)
	cv.add_child(corpo)


# ---------------------------------------------------------------- mapa grande (toque no minimapa)
func _margem_segura() -> float:
	var seg := DisplayServer.get_display_safe_area()
	var tela := DisplayServer.screen_get_size()
	if seg.size.x <= 0 or tela.x <= 0:
		return 0.0
	var k := get_viewport().get_visible_rect().size.x / float(tela.x)
	return maxf(seg.position.x, tela.x - seg.end.x) * k


func abrir_mapa() -> void:
	if mapa_ui == null:
		_montar_mapa_ui()
	var alvo: Node3D = pessoa if pe and pessoa else carro
	mapa_centro = Vector2(alvo.global_position.x, alvo.global_position.z)
	mapa_aberto = true
	mapa_ui.visible = true
	Input.action_release("acelerar")


func fechar_mapa() -> void:
	mapa_aberto = false
	if mapa_ui:
		mapa_ui.visible = false


func marcar_gps(p) -> void:
	gps = p
	if gps_feixe == null:
		gps_feixe = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.6
		cm.bottom_radius = 1.6
		cm.height = 40.0
		cm.cap_top = false
		cm.cap_bottom = false
		gps_feixe.mesh = cm
		var mt := StandardMaterial3D.new()
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mt.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mt.cull_mode = BaseMaterial3D.CULL_DISABLED
		mt.albedo_color = Color(1, 0.24, 0.95, 0.28)
		gps_feixe.material_override = mt
		add_child(gps_feixe)
	gps_feixe.visible = gps != null
	if gps != null:
		gps_feixe.global_position = (gps as Vector3) + Vector3.UP * 20.0


func _montar_mapa_ui() -> void:
	mapa_ui = Control.new()
	mapa_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	mapa_ui.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.add_child(mapa_ui)
	var fundo := ColorRect.new()
	fundo.color = Color(0.04, 0.05, 0.06, 0.97)
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mapa_ui.add_child(fundo)
	mapa_tela = Control.new()
	mapa_tela.set_anchors_preset(Control.PRESET_FULL_RECT)
	mapa_tela.clip_contents = true
	mapa_tela.mouse_filter = Control.MOUSE_FILTER_STOP
	mapa_tela.draw.connect(_desenhar_mapa)
	mapa_tela.gui_input.connect(_mapa_input)
	mapa_ui.add_child(mapa_tela)
	var barra := HBoxContainer.new()
	barra.add_theme_constant_override("separation", 10)
	barra.position = Vector2(26 + _margem_segura(), 20)
	mapa_ui.add_child(barra)
	var tit := Label.new()
	tit.text = "MAPA · CIC"
	tit.add_theme_font_size_override("font_size", 28)
	tit.add_theme_color_override("font_color", AMARELO)
	barra.add_child(tit)
	for par in [["✕ FECHAR", fechar_mapa], ["◎ EU", func(): var a: Node3D = pessoa if pe and pessoa else carro; mapa_centro = Vector2(a.global_position.x, a.global_position.z)],
			["+", func(): mapa_zoom = clampf(mapa_zoom * 1.4, 0.25, 6.0)], ["−", func(): mapa_zoom = clampf(mapa_zoom / 1.4, 0.25, 6.0)],
			["LIMPAR GPS", func(): marcar_gps(null)]]:
		var b := Button.new()
		b.text = par[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(70, 56)
		b.add_theme_font_size_override("font_size", 20)
		var n := _estilo(Color(0.05, 0.05, 0.07, 0.85), Color(1, 1, 1, 0.35))
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", n)
		b.pressed.connect(par[1])
		barra.add_child(b)
	var dica := Label.new()
	dica.text = "Arraste pra mover · pinça ou + − pra zoom · toque num lugar pra marcar o GPS"
	dica.add_theme_font_size_override("font_size", 16)
	dica.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	dica.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	dica.position = Vector2(26 + _margem_segura(), get_viewport().get_visible_rect().size.y - 40)
	dica.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mapa_ui.add_child(dica)
	mapa_ui.visible = false


func _mapa_para_tela(w: Vector3) -> Vector2:
	return mapa_tela.size / 2.0 + (Vector2(w.x, w.z) - mapa_centro) * mapa_zoom


func _tela_para_mapa(q: Vector2) -> Vector2:
	return mapa_centro + (q - mapa_tela.size / 2.0) / mapa_zoom


func _mapa_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_mt[e.index] = e.position
			if _mt.size() == 1:
				_mt_mexeu = 0.0
			if _mt.size() == 2:
				var v: Array = _mt.values()
				_mt_dist = (v[0] as Vector2).distance_to(v[1])
		else:
			if _mt.size() == 1 and _mt_mexeu < 12.0:
				# toque rápido: marca o GPS ali
				var q := _tela_para_mapa(e.position)
				var mp := rede.mais_perto(Vector3(q.x, 0, q.y), 60.0)
				if not mp.is_empty():
					q = mp["ponto"]
				marcar_gps(mapa.no_chao(Vector3(q.x, 0, q.y)))
				toast("GPS: " + str(mp.get("nome", "aqui")) if mp.get("nome", "") != "" else "GPS MARCADO")
			_mt.erase(e.index)
			_mt_mexeu = 99.0 if not _mt.is_empty() else _mt_mexeu
	elif e is InputEventScreenDrag:
		if _mt.size() >= 2 and _mt.has(e.index):
			_mt[e.index] = e.position
			var v: Array = _mt.values()
			var d := (v[0] as Vector2).distance_to(v[1])
			if _mt_dist > 1.0:
				mapa_zoom = clampf(mapa_zoom * d / _mt_dist, 0.25, 6.0)
			_mt_dist = d
			_mt_mexeu = 99.0
		else:
			mapa_centro -= e.relative / mapa_zoom
			_mt_mexeu += e.relative.length()
			_mt[e.index] = e.position
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			mapa_zoom = clampf(mapa_zoom * 1.15, 0.25, 6.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			mapa_zoom = clampf(mapa_zoom / 1.15, 0.25, 6.0)


func _desenhar_mapa() -> void:
	if _mini_tex == null:
		return
	var o: Array = mapa.dados["origem"]
	var k := float(_mini_tex.get_width()) / (float(mapa.dados["nx"]) * float(mapa.dados["bloco_m"]))
	var tam := mapa_tela.size
	var tl := _tela_para_mapa(Vector2.ZERO)
	var br := _tela_para_mapa(tam)
	# só a parte que existe da imagem (fora dela fica o fundo escuro)
	var mw := Rect2(float(o[0]), float(o[1]), _mini_tex.get_width() / k, _mini_tex.get_height() / k)
	var vis := Rect2(tl, br - tl).intersection(mw)
	if vis.size.x > 0 and vis.size.y > 0:
		var src := Rect2((vis.position.x - float(o[0])) * k, (vis.position.y - float(o[1])) * k, vis.size.x * k, vis.size.y * k)
		var dst := Rect2((vis.position - mapa_centro) * mapa_zoom + tam / 2.0, vis.size * mapa_zoom)
		mapa_tela.draw_texture_rect_region(_mini_tex, dst, src, Color(1.1, 1.1, 1.1))
	var fonte := ThemeDB.fallback_font
	var pois := [[mapa.drops_ponto(Vector3(2.3, 0, 2)), AMARELO, "D", "Drops Garage"]]
	if mapa.tem("hangar"): pois.append([mapa.xf("hangar").origin, Color("ff5cd6"), "E", "Encontro"])
	if mapa.tem("posto"): pois.append([mapa.xf("posto").origin, Color("5cc8ff"), "P", "Posto"])
	if mapa.tem("concessionaria"): pois.append([mapa.xf("concessionaria").origin, Color("ff9a3c"), "C", "Drops Car (concessionária)"])
	if barracao and mapa.tem("barracao"): pois.append([barracao.entrada, Color("9e4dff"), "N", "Barracão (carros novos)"])
	if mapa.tem("delegacia"): pois.append([del_xf * Vector3(-60, 0, -14.3), Color("4f7dff"), "★", "Delegacia"])
	if policia:
		for b in policia.blitz:
			pois.append([b, Color("ff3b3b"), "B", "Blitz"])
	if role and not role.mis.is_empty() and role.mis.has("alvo"):
		pois.append([role.mis["alvo"], Color("2be7ff"), "!", "Desafio"])
	if gps != null:
		pois.append([gps, Color("ff3df2"), "★", "GPS"])
	for poi in pois:
		var q := _mapa_para_tela(poi[0])
		mapa_tela.draw_circle(q, 16.0, Color(0, 0, 0, 0.8))
		mapa_tela.draw_circle(q, 13.0, poi[1])
		mapa_tela.draw_string(fonte, q + Vector2(-7, 7), poi[2], HORIZONTAL_ALIGNMENT_CENTER, 14, 18, Color.BLACK)
		mapa_tela.draw_string_outline(fonte, q + Vector2(20, 7), poi[3], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, Color.BLACK)
		mapa_tela.draw_string(fonte, q + Vector2(20, 7), poi[3], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	var alvo: Node3D = pessoa if pe and pessoa else carro
	var c := _mapa_para_tela(alvo.global_position)
	var fv: Vector3 = alvo.global_basis.z if not pe else Vector3(sin(ape_yaw + PI), 0, cos(ape_yaw + PI))
	var dirv := Vector2(fv.x, fv.z).normalized()
	var lado := Vector2(-dirv.y, dirv.x)
	var pulso := 22.0 + 6.0 * sin(tempo * 5.0)
	mapa_tela.draw_arc(c, pulso, 0, TAU, 32, Color(1, 1, 1, 0.8), 3.0)
	mapa_tela.draw_colored_polygon(PackedVector2Array([c + dirv * 20.0, c - dirv * 12.0 + lado * 13.0, c - dirv * 5.0, c - dirv * 12.0 - lado * 13.0]), Color.BLACK)
	mapa_tela.draw_colored_polygon(PackedVector2Array([c + dirv * 16.0, c - dirv * 9.0 + lado * 10.0, c - dirv * 3.0, c - dirv * 9.0 - lado * 10.0]), Color.WHITE)
	mapa_tela.draw_string_outline(fonte, c + Vector2(24, -16), "VOCÊ", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, Color.BLACK)
	mapa_tela.draw_string(fonte, c + Vector2(24, -16), "VOCÊ", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	# escala
	var m100 := 100.0 * mapa_zoom
	mapa_tela.draw_line(Vector2(tam.x - 40 - m100, tam.y - 30), Vector2(tam.x - 40, tam.y - 30), Color.WHITE, 3.0)
	mapa_tela.draw_string(fonte, Vector2(tam.x - 40 - m100, tam.y - 38), "100 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)


# ---------------------------------------------------------------- minimapa e nome da rua
var _mini_tex: Texture2D


func _hud_mapa() -> void:
	if ResourceLoader.exists("res://mapa_cic/minimapa.png"):
		_mini_tex = load("res://mapa_cic/minimapa.png")
	minimapa = Control.new()
	minimapa.size = Vector2(200, 200)
	minimapa.clip_contents = true
	minimapa.mouse_filter = Control.MOUSE_FILTER_STOP
	minimapa.gui_input.connect(func(e: InputEvent):
		if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
			abrir_mapa())
	minimapa.draw.connect(_desenhar_minimapa)
	hud.add_child(minimapa)
	rua_label = Label.new()
	rua_label.add_theme_font_size_override("font_size", 18)
	rua_label.add_theme_color_override("font_color", Color.WHITE)
	rua_label.add_theme_color_override("font_outline_color", Color.BLACK)
	rua_label.add_theme_constant_override("outline_size", 9)
	rua_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rua_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rua_label.modulate.a = 0.0
	hud.add_child(rua_label)
	vel_label = Label.new()
	vel_label.add_theme_font_size_override("font_size", 30)
	vel_label.add_theme_color_override("font_color", AMARELO)
	vel_label.add_theme_color_override("font_outline_color", Color.BLACK)
	vel_label.add_theme_constant_override("outline_size", 8)
	vel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vel_label.size = Vector2(150, 40)
	vel_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(vel_label)
	carro_hud.append(vel_label)
	_posicionar_botoes()


func _atualizar_hud_mapa(dt: float) -> void:
	if minimapa == null:
		return
	minimapa.queue_redraw()
	if mapa_aberto and mapa_tela:
		mapa_tela.queue_redraw()
	if gps != null and carro and Vector2(gps.x - carro.global_position.x, gps.z - carro.global_position.z).length() < 14.0:
		toast("CHEGOU NO DESTINO")
		marcar_gps(null)
	vel_label.text = "%d km/h" % int(absf(carro.linear_velocity.dot(carro.global_basis.z)) * 3.6)
	rua_t -= dt
	if rua_t <= 0.0:
		rua_t = 0.4
		var alvo: Node3D = pessoa if pe and pessoa else carro
		var mp := rede.mais_perto(alvo.global_position, 14.0)
		var nome: String = mp.get("nome", "")
		if nome != "" and nome != rua_atual:
			rua_atual = nome
			rua_label.text = nome
			rua_label.modulate.a = 1.0
			create_tween().tween_property(rua_label, "modulate:a", 0.0, 1.2).set_delay(3.0)


func _desenhar_minimapa() -> void:
	var tam := minimapa.size
	var c := tam / 2.0
	minimapa.draw_rect(Rect2(Vector2.ZERO, tam), Color(0.08, 0.09, 0.1, 0.85))
	if _mini_tex == null or carro == null:
		return
	var alvo: Node3D = pessoa if pe and pessoa else carro
	var p := alvo.global_position
	var o: Array = mapa.dados["origem"]
	var k := float(_mini_tex.get_width()) / (float(mapa.dados["nx"]) * float(mapa.dados["bloco_m"]))   # px da textura por metro
	var R := 170.0   # metros mostrados do centro até a borda
	var esc := (tam.x / 2.0) / (R * k)
	var f: Vector3 = cam.global_basis.z * -1.0
	var ang := -PI / 2.0 - atan2(f.z, f.x)
	var pc := Vector2((p.x - float(o[0])) * k, (p.z - float(o[1])) * k)
	var meio := R * k * 1.5
	minimapa.draw_set_transform(c, ang, Vector2.ONE * esc)
	minimapa.draw_texture_rect_region(_mini_tex, Rect2(-meio, -meio, meio * 2, meio * 2), Rect2(pc - Vector2(meio, meio), Vector2(meio * 2, meio * 2)), Color(1.15, 1.15, 1.15))
	var pois := [[mapa.drops_ponto(Vector3(2.3, 0, 2)), AMARELO, "D"]]
	if mapa.tem("hangar"): pois.append([mapa.xf("hangar").origin, Color("ff5cd6"), "E"])
	if mapa.tem("posto"): pois.append([mapa.xf("posto").origin, Color("5cc8ff"), "P"])
	if mapa.tem("concessionaria"): pois.append([mapa.xf("concessionaria").origin, Color("ff9a3c"), "C"])
	if barracao and mapa.tem("barracao"): pois.append([barracao.entrada, Color("9e4dff"), "N"])
	if mapa.tem("delegacia"): pois.append([del_xf * Vector3(-60, 0, -14.3), Color("4f7dff"), "★"])
	if policia:
		for b in policia.blitz:
			pois.append([b, Color("ff3b3b"), "B"])
	if role and not role.mis.is_empty() and role.mis.has("alvo"):
		pois.append([role.mis["alvo"], Color("2be7ff"), "!"])
	if gps != null:
		pois.append([gps, Color("ff3df2"), "★"])
	minimapa.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var fonte := ThemeDB.fallback_font
	for poi in pois:
		var w: Vector3 = poi[0]
		var q := (Vector2((w.x - float(o[0])) * k, (w.z - float(o[1])) * k) - pc).rotated(ang) * esc
		if q.length() > tam.x / 2.0 - 12.0:
			q = q.normalized() * (tam.x / 2.0 - 12.0)
		minimapa.draw_circle(c + q, 10.0, Color(0, 0, 0, 0.75))
		minimapa.draw_circle(c + q, 8.0, poi[1])
		minimapa.draw_string(fonte, c + q + Vector2(-5, 5), poi[2], HORIZONTAL_ALIGNMENT_CENTER, 10, 12, Color.BLACK)
	# você: setinha amarela apontando pra onde o carro vai
	var fv: Vector3 = alvo.global_basis.z if not pe else Vector3(sin(ape_yaw + PI), 0, cos(ape_yaw + PI))
	var dirv := Vector2(fv.x, fv.z).rotated(ang).normalized()
	var lado := Vector2(-dirv.y, dirv.x)
	minimapa.draw_colored_polygon(PackedVector2Array([c + dirv * 11.0, c - dirv * 7.0 + lado * 7.0, c - dirv * 3.0, c - dirv * 7.0 - lado * 7.0]), Color.BLACK)
	minimapa.draw_colored_polygon(PackedVector2Array([c + dirv * 9.0, c - dirv * 5.5 + lado * 5.5, c - dirv * 2.0, c - dirv * 5.5 - lado * 5.5]), AMARELO)
	minimapa.draw_rect(Rect2(Vector2.ZERO, tam), Color(1, 0.83, 0, 0.9), false, 3.0)
	if gps != null:
		var dg := Vector2(gps.x - p.x, gps.z - p.z).length()
		minimapa.draw_string(fonte, Vector2(6, tam.y - 8), "GPS %s" % (("%d m" % dg) if dg < 1000 else ("%.1f km" % (dg / 1000.0))), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("ff3df2"))
	minimapa.draw_string(fonte, Vector2(tam.x - 62, tam.y - 8), "▣ MAPA", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))
