class_name Barracao
extends Node
## (v34) BARRACÃO do evento dos carros novos, no terreno vazio do lado direito da Drops (de quem olha da rua).
## Fechado (paredes de bloco, telhado de zinco com tesouras), portão de enrolar aberto na frente pra entrar
## de carro, piso de epóxi com vagas pintadas, grafite nas paredes, os carros novos montados (rebaixados,
## rodas boas, neon, portas abertas), galera e Mega Funk lá dentro.
## Coordenadas locais: origem no meio da frente do lote (na calçada), +Z aponta pra rua, o lote vai até z = -30.

const LARG := 16.0          # largura do lote (x de -8 a 8)
const FUNDO := 30.0         # profundidade (z de 0 a -30)
const ALT := 6.2            # pé-direito na parede
const CUMEEIRA := 8.0       # altura no meio do telhado
const PORTA := 9.0          # largura do portão
const CAMADA_DENTRO := 2    # camada de render das superfícies de dentro (o sol não ilumina lá dentro)
const AMARELO := Color("ffd400")

var m: Node                 # main.gd
var xf := Transform3D.IDENTITY
var entrada := Vector3.ZERO # (ponto do mapa: frente do barracão)
var dentro_agora := false
var som: AudioStreamPlayer3D
var _caixa := AABB(Vector3(-LARG / 2.0, -1.0, -FUNDO), Vector3(LARG, 10.0, FUNDO))
var _mats := {}

# carros novos montados pro evento: [id, cor, acabamento, cor2, roda, aro, cor_roda, borda, camber, rebaixo, neon, portas]
const MONTAGENS := [
	["golfgti", "#f2f2f2", "perola", "#ff7ad9", "sfn", 18, "#c9ccd1", "polida", 3, 17.0, "rosa", true],
	["jetta", "#101012", "brilho", "#6ea6ff", "m850", 19, "#16171a", "polida", 2, 16.0, "azul", false],
	["tiguan", "#8a8d8f", "fosco", "#ffffff", "lambo", 20, "#16171a", "cor", 1, 13.0, "ciano", true],
	["id4", "#5b2bd6", "camaleao", "#2be7ff", "revu", 20, "#c9ccd1", "polida", 2, 14.0, "roxo", false],
	["saveirorobust", "#b5121b", "metal", "#ffd400", "work", 17, "#c9ccd1", "polida", 4, 18.0, "vermelho", true],
	["lexusnx", "#f2f2ef", "perola", "#ffd400", "tusk", 20, "#4a4d52", "cor", 1, 12.0, "amarelo", false],
	["f150", "#16171a", "fosco", "#ff3a3a", "raptor", 20, "#16171a", "cor", 0, 8.0, "vermelho", true],
	["santacruz", "#2f7f4c", "metal", "#ffffff", "hre522", 20, "#c9ccd1", "polida", 2, 12.0, "verde", false],
]


func _ready() -> void:
	if not m.mapa.tem("barracao"):
		return
	xf = m.mapa.xf("barracao")
	entrada = xf * Vector3(0, 0, 2.0)
	_predio()
	_carros()
	_galera()
	_som()


# ------------------------------------------------------------------ materiais
func _mat(nome: String, cor: Color, rug := 0.85, metal := 0.0, emis := 0.0, tex := "") -> StandardMaterial3D:
	if _mats.has(nome):
		return _mats[nome]
	var s := StandardMaterial3D.new()
	s.albedo_color = cor
	s.roughness = rug
	s.metallic = metal
	if tex != "":
		s.albedo_texture = load(tex)
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if emis > 0.0:
		s.emission_enabled = true
		s.emission = cor
		s.emission_energy_multiplier = emis
		if tex != "":
			s.emission_texture = s.albedo_texture
	_mats[nome] = s
	return s


func _caixa_m(pos: Vector3, tam: Vector3, mat: Material, dentro := false, colide := false, giro := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = tam
	mi.mesh = bm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if dentro else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if dentro:
		mi.layers = 1 << (CAMADA_DENTRO - 1)
	mi.visibility_range_end = 220.0
	add_child(mi)
	mi.global_transform = xf * Transform3D(Basis(Vector3.UP, giro), pos)
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


func _quad(pos: Vector3, tam: Vector2, mat: Material, giro_y: float) -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = tam
	q.mesh = qm
	q.material_override = mat
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.layers = 1 << (CAMADA_DENTRO - 1)
	q.visibility_range_end = 120.0
	add_child(q)
	q.global_transform = xf * Transform3D(Basis(Vector3.UP, giro_y), pos)


# ------------------------------------------------------------------ prédio
func _predio() -> void:
	var bloco := _mat("bloco", Color(0.78, 0.78, 0.76), 0.9)
	var bloco_in := _mat("bloco_in", Color(0.2, 0.2, 0.22), 0.9)
	var zinco := _mat("zinco", Color(0.62, 0.64, 0.66), 0.45, 0.6)
	var zinco_in := _mat("zinco_in", Color(0.32, 0.33, 0.35), 0.6, 0.4)
	var aco := _mat("aco", Color(0.12, 0.12, 0.13), 0.5, 0.7)
	var piso := _mat("piso", Color(0.17, 0.17, 0.19), 0.32, 0.0)
	var faixa := _mat("faixa", AMARELO, 0.6)
	var branco := _mat("faixa_b", Color(0.9, 0.9, 0.9), 0.6)
	var lampada := _mat("lampada", Color(1, 0.97, 0.9), 0.3, 0.0, 3.0)
	var hx := LARG / 2.0
	var z0 := -FUNDO
	var zc := -FUNDO / 2.0
	# piso (sólido) de epóxi escuro
	_caixa_m(Vector3(0, -0.2, zc), Vector3(LARG, 0.46, FUNDO), piso, true, true)
	# paredes: por fora bloco claro (sol), por dentro grafite (sem sol)
	for s in [-1.0, 1.0]:
		_caixa_m(Vector3(s * (hx - 0.12), ALT / 2.0, zc), Vector3(0.24, ALT, FUNDO), bloco, false, true)
		_caixa_m(Vector3(s * (hx - 0.25), ALT / 2.0, zc), Vector3(0.02, ALT, FUNDO - 0.5), bloco_in, true)
	_caixa_m(Vector3(0, ALT / 2.0, z0 + 0.12), Vector3(LARG, ALT, 0.24), bloco, false, true)
	_caixa_m(Vector3(0, ALT / 2.0, z0 + 0.25), Vector3(LARG - 0.5, ALT, 0.02), bloco_in, true)
	# frente: dois pedaços de parede e a viga em cima do portão (aberto, enrolado lá em cima)
	var lado := (LARG - PORTA) / 2.0
	for s in [-1.0, 1.0]:
		_caixa_m(Vector3(s * (PORTA / 2.0 + lado / 2.0), ALT / 2.0, -0.12), Vector3(lado, ALT, 0.24), bloco, false, true)
	_caixa_m(Vector3(0, ALT - 0.6, -0.12), Vector3(PORTA, 1.2, 0.24), bloco, false, true)
	_caixa_m(Vector3(0, ALT - 1.35, -0.2), Vector3(PORTA + 0.3, 0.42, 0.42), aco)                  # rolo do portão de enrolar
	for s in [-1.0, 1.0]:
		_caixa_m(Vector3(s * (PORTA / 2.0 + 0.06), (ALT - 1.2) / 2.0, -0.2), Vector3(0.12, ALT - 1.2, 0.2), aco)   # trilhos
	# oitão (triângulo da fachada e do fundo) + telhado de duas águas de zinco com tesouras de aço
	var sobe := CUMEEIRA - ALT
	var meia := sqrt(hx * hx + sobe * sobe)
	var ang := atan2(sobe, hx)
	for s in [-1.0, 1.0]:
		var c := _caixa_m(Vector3(s * hx / 2.0, ALT + sobe / 2.0 + 0.05, zc), Vector3(meia + 0.6, 0.08, FUNDO + 0.8), zinco)
		c.global_transform = xf * Transform3D(Basis(Vector3(0, 0, 1), -s * ang), Vector3(s * hx / 2.0, ALT + sobe / 2.0 + 0.05, zc))
		var ci := _caixa_m(Vector3.ZERO, Vector3(meia, 0.02, FUNDO - 0.4), zinco_in, true)
		ci.global_transform = xf * Transform3D(Basis(Vector3(0, 0, 1), -s * ang), Vector3(s * hx / 2.0, ALT + sobe / 2.0 - 0.06, zc))
	for zz in [-0.12, z0 + 0.12]:
		var k := 6
		for i in k:
			var w := LARG * (1.0 - float(i) / k)
			_caixa_m(Vector3(0, ALT + sobe * (float(i) + 0.5) / k, zz), Vector3(w, sobe / k + 0.01, 0.24), bloco)
	var zt := z0 + 2.5
	while zt < -1.0:
		_caixa_m(Vector3(0, ALT - 0.1, zt), Vector3(LARG - 0.5, 0.18, 0.12), aco, true)          # banzo de baixo
		for s in [-1.0, 1.0]:
			var b := _caixa_m(Vector3.ZERO, Vector3(meia - 0.3, 0.16, 0.12), aco, true)
			b.global_transform = xf * Transform3D(Basis(Vector3(0, 0, 1), -s * ang), Vector3(s * hx / 2.0, ALT + sobe / 2.0 - 0.2, zt))
		_caixa_m(Vector3(0, ALT + sobe / 2.0 - 0.15, zt), Vector3(0.1, sobe, 0.1), aco, true)       # pendural
		zt += 5.0
	# luminárias (barras de LED) e luz de verdade
	for zz in [-5.0, -12.0, -19.0, -26.0]:
		for x in [-3.6, 3.6]:
			_caixa_m(Vector3(x, ALT - 0.45, zz), Vector3(0.18, 0.06, 2.6), lampada, true)
	for zz in [-6.0, -15.0, -24.0]:
		var l := OmniLight3D.new()
		l.light_color = Color(1, 0.96, 0.9)
		l.light_energy = 2.2
		l.omni_range = 14.0
		l.omni_attenuation = 1.0
		l.shadow_enabled = false
		add_child(l)
		l.global_position = xf * Vector3(0, ALT - 0.8, zz)
	for s in [-1.0, 1.0]:   # neon colorido nas laterais
		var l := OmniLight3D.new()
		l.light_color = Color(0.7, 0.35, 1.0) if s < 0 else Color(0.25, 0.85, 1.0)
		l.light_energy = 1.4
		l.omni_range = 9.0
		l.shadow_enabled = false
		add_child(l)
		l.global_position = xf * Vector3(s * 5.5, 2.4, -15.0)
		_caixa_m(Vector3(s * (hx - 0.3), 4.8, -15.0), Vector3(0.05, 0.06, FUNDO - 3.0), _mat("neon%d" % int(s), l.light_color, 0.3, 0.0, 4.0), true)
	# vagas pintadas (faixas brancas) e faixa amarela do corredor
	for zz in [-6.4, -9.6, -12.8, -16.0, -19.2, -22.4]:
		for s in [-1.0, 1.0]:
			_caixa_m(Vector3(s * 5.6, 0.035, zz), Vector3(4.6, 0.01, 0.1), branco, true)
	for s in [-1.0, 1.0]:
		_caixa_m(Vector3(s * 3.2, 0.035, -14.5), Vector3(0.12, 0.01, 16.5), faixa, true)
	# (v38) paredes de dentro só com as fotos dos projetos da Drops (cada foto uma vez), e o mural da Drops no fundo
	var fotos := [[-1.0, -6.0, 1], [-1.0, -14.5, 2], [-1.0, -23.0, 3], [1.0, -10.0, 4], [1.0, -19.0, 5]]   # lado, z, foto
	for fq in fotos:
		var sx: float = fq[0]
		var qd := quadro_foto("res://modelos/cenario/projeto_%d.jpg" % fq[2], 4.0)
		add_child(qd)
		qd.global_transform = xf * Transform3D(Basis(Vector3.UP, -sx * PI / 2.0), Vector3(sx * (hx - 0.4), 3.4, fq[1]))   # na frente da fita de LED
		for gi in qd.find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).layers = 1 << (CAMADA_DENTRO - 1)
	_quad(Vector3(0, 2.9, z0 + 0.27), Vector2(LARG - 1.0, (LARG - 1.0) * 340.0 / 2048.0), _mat("mural", Color(1, 1, 1), 0.85, 0.0, 0.25, "res://modelos/cenario/mural_drops.jpg"), 0.0)


## (v38) quadro com foto dos projetos da Drops: moldura preta fininha e a foto com as cores dela.
## Olha pra +Z; altura da foto em metros (a largura sai da proporção da foto).
static var _sh_foto: Shader
static func quadro_foto(arq: String, alt: float) -> Node3D:
	var q := Node3D.new()
	if not ResourceLoader.exists(arq):
		return q
	var tx: Texture2D = load(arq)
	var larg := alt * float(tx.get_width()) / float(tx.get_height())
	var mold := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(larg + 0.14, alt + 0.14, 0.05)
	mold.mesh = bm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.02, 0.02, 0.025)
	mm.roughness = 0.4
	mold.material_override = mm
	mold.position.z = -0.03
	q.add_child(mold)
	var f := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(larg, alt)
	f.mesh = qm
	if _sh_foto == null:
		_sh_foto = load("res://scripts/shaders/foto.gdshader")
	var sm := ShaderMaterial.new()
	sm.shader = _sh_foto
	sm.set_shader_parameter("foto", tx)
	sm.set_shader_parameter("ganho", GANHO_FOTO)
	f.material_override = sm
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.add_child(f)
	for m in [mold, f]:
		(m as GeometryInstance3D).visibility_range_end = 260.0
	return q
const GANHO_FOTO := 1.0


# ------------------------------------------------------------------ carros, galera e som
func _carros() -> void:
	var vagas := [Vector3(-5.4, 0.03, -8.0), Vector3(5.4, 0.03, -8.0), Vector3(-5.4, 0.03, -11.2), Vector3(5.4, 0.03, -11.2),
		Vector3(-5.4, 0.03, -14.4), Vector3(5.4, 0.03, -14.4), Vector3(-5.4, 0.03, -17.6), Vector3(5.4, 0.03, -17.6)]
	for k in MONTAGENS.size():
		var mo: Array = MONTAGENS[k]
		var i := -1
		for j in Dados.carros.size():
			if Dados.carros[j]["id"] == mo[0]:
				i = j
		if i < 0:
			continue
		var d: Dictionary = Dados.carros[i]
		var c: Dictionary = (d["padrao"] as Dictionary).duplicate(true)
		c["cor"] = mo[1]
		c["acabamento"] = mo[2]
		c["cor2"] = mo[3]
		c["roda"] = mo[4]
		c["aro"] = mo[5]
		c["cor_roda"] = mo[6]
		c["borda"] = mo[7]
		c["camber"] = mo[8]
		c["rebaixo"] = mo[9]
		c["rebaixo_tras"] = mo[9] + 1.0
		c["neon"] = mo[10]
		CarroVisual.socar(d, c)   # (v37) no chão, pneu fininho e o maior aro que cabe
		c["som"] = "deitado" if d.get("bed") != null else "off"
		var cv := CarroVisual.new()
		add_child(cv)
		cv.montar(d, c, true)
		cv.alcance(120.0)
		var v: Vector3 = vagas[k]
		var lado := -1.0 if v.x < 0 else 1.0
		cv.global_transform = xf * Transform3D(Basis(Vector3.UP, -lado * PI / 2.0), v)
		if mo[11]:
			cv.abrir("portas")
		var corpo := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(d["W"]), 1.3, cv.comprimento)
		col.shape = box
		col.position = Vector3(0, 0.65, (cv.frente_z + cv.tras_z) / 2.0)
		corpo.add_child(col)
		cv.add_child(corpo)


func _galera() -> void:
	var gente := [["dancarino", Vector3(-1.2, 0.03, -21.5), 1.77], ["mulher_a", Vector3(0.2, 0.03, -22.4), 1.65],
		["mulher_c", Vector3(1.4, 0.03, -21.0), 1.66], ["dancarino", Vector3(-2.0, 0.03, -10.0), 1.75],
		["mulher_b", Vector3(-1.0, 0.03, -9.2), 1.63], ["feliz", Vector3(1.8, 0.03, -25.5), 1.72],
		["mulher_a", Vector3(2.1, 0.03, -13.5), 1.64], ["dancarino", Vector3(-2.3, 0.03, -26.0), 1.78],
		["jack", Vector3(0.8, 0.03, -20.4), 1.80], ["henry", Vector3(2.4, 0.03, -10.6), 1.80], ["steve", Vector3(-0.2, 0.03, -25.0), 1.78]]
	for p in gente:
		var arq := "res://modelos/personagens/%s.glb" % p[0]
		if not ResourceLoader.exists(arq):
			continue
		if p[0] in ["jack", "steve", "henry"]:
			var h := Node3D.new()
			h.add_child(Pessoa.criar_dancando(arq, float(p[2])))
			add_child(h)
			h.global_transform = xf * Transform3D(Basis(Vector3.UP, randf_range(0, TAU)), p[1])
			var apn := h.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if apn and apn.has_animation("drops/danca"):
				apn.seek(randf_range(0, 5), true)
			for gi in h.find_children("*", "GeometryInstance3D", true, false):
				(gi as GeometryInstance3D).visibility_range_end = 90.0
			continue
		var g: Node3D = load(arq).instantiate()
		add_child(g)
		g.global_transform = xf * Transform3D(Basis(Vector3.UP, randf_range(0, TAU)), p[1])
		var hi := 0.0
		for s in g.find_children("*", "Skeleton3D", true, false):
			var sk := s as Skeleton3D
			for b in sk.get_bone_count():
				hi = maxf(hi, (sk.global_transform * sk.get_bone_global_rest(b)).origin.y - g.global_position.y)
		g.scale = Vector3.ONE * (float(p[2]) / (hi if hi > 0.05 else 1.0))
		for gi in g.find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).visibility_range_end = 90.0
		var ap := g.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and not ap.get_animation_list().is_empty():
			var n: String = ap.get_animation_list()[0]
			ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
			ap.play(n)
			ap.seek(randf_range(0, 5), true)


func _som() -> void:
	som = AudioStreamPlayer3D.new()
	som.stream = load("res://audio/mega_funk.mp3")
	if som.stream is AudioStreamMP3:
		(som.stream as AudioStreamMP3).loop = true
	som.volume_db = -5.0
	som.unit_size = 10.0
	som.max_distance = 55.0
	som.autoplay = true
	add_child(som)
	som.global_position = xf * Vector3(0, 2.5, -24.0)
	# caixa de som no fundo
	var cx := _caixa_m(Vector3(0, 0.75, -28.6), Vector3(2.6, 1.5, 0.7), _mat("caixa", Color(0.05, 0.05, 0.06), 0.6))
	cx.layers = 1 << (CAMADA_DENTRO - 1)


# ------------------------------------------------------------------ uso
func dentro(p: Vector3) -> bool:
	if not m.mapa.tem("barracao"):
		return false
	return _caixa.has_point(xf.affine_inverse() * p)


func _physics_process(_dt: float) -> void:
	var alvo: Node3D = m.pessoa if m.pe and m.pessoa else m.carro
	if alvo == null:
		return
	var agora := dentro(alvo.global_position)
	dentro_agora = agora
