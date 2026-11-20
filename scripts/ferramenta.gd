class_name Ferramenta
## (fase 2) ferramentas na mão do boneco, feitas de peças simples (nada de modelo de fora):
## esponja (lavar), lixadeira orbital (lixar), spotter (desamassar, solta faísca), pistola de pintura (névoa da cor).
## Eixos da mão do kit: +Y = pra onde os dedos apontam, +Z = lado do polegar. A ferramenta fica na palma.

static func _mat(cor: Color, metal := 0.0, aspereza := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = cor
	m.metallic = metal
	m.roughness = aspereza
	return m


static func _caixa(pai: Node3D, tam: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = tam
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	pai.add_child(mi)
	return mi


## cilindro com o eixo em 'eixo' (Y, Z ou X)
static func _cil(pai: Node3D, raio: float, comp: float, pos: Vector3, eixo: Vector3, mat: Material, raio_fim := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = raio if raio_fim < 0.0 else raio_fim
	cm.bottom_radius = raio
	cm.height = comp
	cm.radial_segments = 16
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	if eixo == Vector3.FORWARD or eixo == Vector3.BACK:
		mi.rotation.x = PI / 2.0
	elif eixo == Vector3.RIGHT or eixo == Vector3.LEFT:
		mi.rotation.z = PI / 2.0
	pai.add_child(mi)
	return mi


## partículas que saem da ponta (espuma, pó, faísca, tinta)
static func _particulas(pai: Node3D, tipo: String, cor: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "particulas"
	p.local_coords = false
	p.emitting = false
	var sm := SphereMesh.new()
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = m
	p.mesh = sm
	p.direction = Vector3(0, 1, 0)
	match tipo:
		"espuma":
			sm.radius = 0.012; sm.height = 0.024
			p.amount = 40; p.lifetime = 1.2; p.spread = 70.0
			p.initial_velocity_min = 0.05; p.initial_velocity_max = 0.25
			p.gravity = Vector3(0, -0.6, 0)
			p.scale_amount_min = 0.5; p.scale_amount_max = 1.6
			p.color = Color(1, 1, 1, 0.9)
		"po":
			sm.radius = 0.006; sm.height = 0.012
			p.amount = 50; p.lifetime = 0.9; p.spread = 90.0
			p.initial_velocity_min = 0.2; p.initial_velocity_max = 0.6
			p.gravity = Vector3(0, -1.5, 0)
			p.color = Color(0.75, 0.62, 0.5, 0.7)
		"faisca":
			sm.radius = 0.004; sm.height = 0.008
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			p.amount = 60; p.lifetime = 0.35; p.spread = 80.0
			p.initial_velocity_min = 1.0; p.initial_velocity_max = 2.6
			p.gravity = Vector3(0, -6.0, 0)
			p.color = Color(1.0, 0.75, 0.3, 1.0)
		"tinta":
			sm.radius = 0.02; sm.height = 0.04
			p.amount = 70; p.lifetime = 0.6; p.spread = 14.0
			p.initial_velocity_min = 1.2; p.initial_velocity_max = 2.0
			p.gravity = Vector3.ZERO
			p.damping_min = 1.5; p.damping_max = 2.5
			p.scale_amount_min = 0.6; p.scale_amount_max = 2.2
			p.color = Color(cor.r, cor.g, cor.b, 0.45)
	pai.add_child(p)
	return p


## em que mão cada ferramenta vai (depende da animação: no "Interact" e no "Idle_Torch" quem trabalha é a esquerda)
const MAO := {"esponja": "l", "lixadeira": "l", "spotter": "l", "pistola": "r"}

## cria a ferramenta (pai = BoneAttachment3D da mão). Mão esquerda = espelho da direita.
static func criar(nome: String, cor := Color.WHITE, esquerda := false) -> Node3D:
	var f := Node3D.new()
	f.name = "ferramenta"
	# a palma: um pouco pra frente dos nós dos dedos e pro lado de dentro da mão
	# (medido: a palma fica no −X da mão direita; a esquerda é o espelho)
	f.position = Vector3(0.035 if esquerda else -0.035, 0.075, 0.0)
	if not esquerda:
		f.scale = Vector3(-1, 1, 1)
	f.set_meta("nome", nome)
	var preto := _mat(Color(0.05, 0.05, 0.055), 0.2, 0.5)
	match nome:
		"esponja":
			_caixa(f, Vector3(0.05, 0.12, 0.08), Vector3(0.02, 0.0, 0.0), _mat(Color(1.0, 0.82, 0.15), 0.0, 0.95))
			_caixa(f, Vector3(0.012, 0.12, 0.08), Vector3(0.049, 0.0, 0.0), _mat(Color(0.15, 0.55, 0.25), 0.0, 1.0))
			var pt := Node3D.new(); pt.position = Vector3(0.06, 0.0, 0.0); f.add_child(pt)
			_particulas(pt, "espuma", cor)
		"lixadeira":
			# corpo em cima da mão, disco de lixa embaixo (lado da palma)
			_cil(f, 0.05, 0.07, Vector3(0.0, 0.0, 0.0), Vector3.RIGHT, _mat(Color(0.95, 0.75, 0.1), 0.1, 0.5), 0.035)
			_cil(f, 0.065, 0.018, Vector3(0.045, 0.0, 0.0), Vector3.RIGHT, preto)
			_cil(f, 0.066, 0.004, Vector3(0.056, 0.0, 0.0), Vector3.RIGHT, _mat(Color(0.75, 0.55, 0.35), 0.0, 1.0))
			_cil(f, 0.012, 0.25, Vector3(-0.03, -0.14, 0.0), Vector3.UP, preto)   # fio
			var pt := Node3D.new(); pt.position = Vector3(0.06, 0.0, 0.0); f.add_child(pt)
			_particulas(pt, "po", cor)
		"spotter":
			# pistola do spotter (repuxador): corpo pra frente (+Y), cabo pra baixo (−Z), ponta de cobre
			_cil(f, 0.03, 0.2, Vector3(0.0, 0.06, 0.03), Vector3.UP, _mat(Color(0.75, 0.08, 0.08), 0.2, 0.45))
			_caixa(f, Vector3(0.035, 0.04, 0.11), Vector3(0.0, 0.0, -0.025), preto)
			_cil(f, 0.012, 0.05, Vector3(0.0, 0.18, 0.03), Vector3.UP, _mat(Color(0.85, 0.5, 0.25), 0.9, 0.3), 0.006)   # ponta de cobre
			_cil(f, 0.009, 0.3, Vector3(0.0, -0.17, 0.03), Vector3.UP, preto)   # cabo de força
			var pt := Node3D.new(); pt.position = Vector3(0.0, 0.21, 0.03); f.add_child(pt)
			_particulas(pt, "faisca", cor)
		"pistola":
			# pistola de pintura: corpo, bico pra frente (+Y), caneca em cima (+Z), cabo embaixo (−Z)
			var cromo := _mat(Color(0.8, 0.8, 0.82), 1.0, 0.2)
			_caixa(f, Vector3(0.03, 0.1, 0.04), Vector3(0.0, 0.05, 0.03), cromo)
			_cil(f, 0.014, 0.05, Vector3(0.0, 0.12, 0.03), Vector3.UP, cromo, 0.008)
			_caixa(f, Vector3(0.028, 0.035, 0.1), Vector3(0.0, 0.0, -0.02), preto)
			_cil(f, 0.03, 0.08, Vector3(0.0, 0.06, 0.1), Vector3.BACK, _mat(Color(0.9, 0.9, 0.9, 0.85), 0.0, 0.3))   # caneca
			_cil(f, 0.026, 0.05, Vector3(0.0, 0.06, 0.1), Vector3.BACK, _mat(cor, 0.0, 0.4))   # tinta dentro
			var pt := Node3D.new(); pt.position = Vector3(0.0, 0.15, 0.03); f.add_child(pt)
			_particulas(pt, "tinta", cor)
	return f


## liga/desliga as partículas e o som da ferramenta
static func soltar(f: Node3D, sim: bool) -> void:
	if f == null:
		return
	for p in f.find_children("particulas", "CPUParticles3D", true, false):
		(p as CPUParticles3D).emitting = sim
	var nome := str(f.get_meta("nome", ""))
	var s := f.get_node_or_null("som") as AudioStreamPlayer3D
	if sim and s == null and nome != "":
		s = AudioStreamPlayer3D.new()
		s.name = "som"
		s.stream = som(nome)
		s.volume_db = -4.0
		s.unit_size = 3.0
		f.add_child(s)
	if s:
		if sim:
			s.play()
		else:
			s.stop()


## som de cada ferramenta, feito aqui mesmo (provisório até ter gravação de verdade):
## esponja = esfrega molhado, lixadeira = zumbido + lixa, spotter = estalo elétrico, pistola = chiado do ar
static var _sons := {}
static func som(nome: String) -> AudioStreamWAV:
	if _sons.has(nome):
		return _sons[nome]
	var taxa := 22050
	var dur := 2.0
	var n := int(taxa * dur)
	var dados := PackedByteArray()
	dados.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(nome)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / taxa
		var ru := rng.randf_range(-1.0, 1.0)
		var v := 0.0
		match nome:
			"esponja":
				lp += (ru - lp) * 0.08          # ruído abafado
				var vai := 0.5 + 0.5 * sin(t * TAU * 1.5)   # vai e volta da mão
				v = lp * 2.2 * (0.35 + 0.65 * vai * vai)
			"lixadeira":
				lp += (ru - lp) * 0.35
				v = 0.35 * sin(t * TAU * 118.0) + 0.15 * sin(t * TAU * 236.0) + lp * 0.5
			"spotter":
				var ciclo := fmod(t, 0.5)
				var estalo := exp(-ciclo * 60.0)          # pulso de solda
				var puxa := exp(-absf(ciclo - 0.28) * 90.0) # "toc" do martelo deslizante
				lp += (ru - lp) * 0.6
				v = lp * estalo * 1.6 + sin(t * TAU * 160.0) * puxa * 0.9
			"pistola":
				lp += (ru - lp) * 0.5
				lp2 += (lp - lp2) * 0.5
				v = (lp - lp2) * 2.6        # chiado agudo do ar
		var a := clampi(int(clampf(v, -1.0, 1.0) * 26000.0), -32768, 32767)
		dados.encode_s16(i * 2, a)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = taxa
	w.data = dados
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	_sons[nome] = w
	return w
