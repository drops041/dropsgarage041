extends Node
## O resto do rolê: Encontro no Pátio (carros rebaixados, galera dançando e a nota do rebaixado),
## Desafios (drift, tiro até o pátio, carro do cliente) e o trânsito da cidade.

const AMARELO := Color("ffd400")
## mapa da CIC: o hangar fica num terrenão de verdade (hx = posição/giro dele),
## as posições do encontro são medidas a partir do hangar (como no mapa velho, com o hangar em 0,0,0)
const NOVOS := ["jack", "steve", "henry"]   # personagens novos (esqueleto Auto-Rig/Mixamo convertido do .blend)
var hx := Transform3D.IDENTITY
var PATIO := Vector3.ZERO     # chegada do "tiro": logo depois do portão do hangar
var DROPS := Vector3.ZERO     # na rua, em frente ao portão da Drops
var CLIENTES: Array = []
const VAGAS_LIVRES := [2, 7, 10]         # sobra vaga pra você estacionar
const LEVES := ["golg5", "golg2", "corsa", "bora", "fusca", "saveiro", "saveirog7", "versa"]
const RIVAIS := ["Japa do G5", "Bigode da G6", "Magrão do Donas", "Tchê do Golfo", "Mineiro do Vambora"]

var m: Rua                               # a cena da rua (main.gd)
# encontro
var na_vaga := -1.0
var nota_mostrada := false
var nota_painel: PanelContainer
# desafios
var mis := {}                            # desafio rodando
var mis_label: Label
var des_painel: PanelContainer
var res_painel: PanelContainer
var marcador: Node3D
var seta: MeshInstance3D
var contagem := 0.0
var conta_label: Label
var dinheiro_l: Label
# trânsito
var transito: Array = []
var parados: Array = []


func iniciar(cena: Rua) -> void:
	m = cena
	if m.mapa.tem("hangar"):
		hx = m.mapa.xf("hangar")
	PATIO = hx * Vector3(0, 0, 22)
	DROPS = m.mapa.drops_ponto(Vector3(2.3, 0, -4.0))
	for k in 8:
		var pa := m.rede.ponto_aleatorio(DROPS, 250.0, 750.0)
		if not pa.is_empty():
			var q: Vector2 = m.rede.ponto(pa["i"], pa["s"])
			CLIENTES.append(m.mapa.no_chao(Vector3(q.x, 0, q.y)))
	if CLIENTES.is_empty():
		CLIENTES.append(PATIO)
	_encontro()
	_ui()
	_marcador()
	_transito()


func _rnd_cfg(i: int) -> Dictionary:
	var c := Dados.cfg(i)
	c["cor"] = Dados.CORES.pick_random()[1]
	c["acabamento"] = ["metal", "perola", "camaleao", "brilho", "fosco"].pick_random()
	c["cor2"] = Dados.CORES2.pick_random()[1]
	c["roda"] = ["work", "audi", "vwrim", "lambo", "revu", "llanta", "sdc1", "sdc5", "tsi", "magn", "sv67", "r557", "dj76"].pick_random()   # rodas leves nos carros da rua
	c["aro"] = randi_range(16, 20)
	c["tala"] = [6.5, 7.0, 7.5, 8.0, 8.5].pick_random()
	c["flanco"] = randf_range(7.0, 9.5)
	c["cor_roda"] = Dados.CORES_RODA.pick_random()[1]
	c["camber"] = randi_range(0, 4)
	return c


func _indice(id: String) -> int:
	for i in Dados.carros.size():
		if Dados.carros[i]["id"] == id:
			return i
	return 0


# ---------------------------------------------------------------- Encontro no Pátio
## vagas do encontro: duas fileiras encostadas nas paredes do hangar, de frente pro corredor (e pro avião)
func vaga(v: int) -> Array:
	var lado := -1.0 if v < 6 else 1.0
	var k := v % 6
	var pos := hx * Vector3(lado * 20.0, 0.036, -9.0 + k * 4.2)
	return [pos, -lado * PI / 2.0 + hx.basis.get_euler().y]


func _encontro() -> void:
	for v in 12:
		if v in VAGAS_LIVRES:
			continue
		var i := _indice(LEVES.pick_random())
		var c := _rnd_cfg(i)
		CarroVisual.socar(Dados.carros[i], c)   # (v37) no chão, pneu fininho e o maior aro que cabe
		c["neon"] = ["roxo", "azul", "ciano", "rosa", "verde", "vermelho"].pick_random()
		var d: Dictionary = Dados.carros[i]
		c["som"] = ["deitado", "on"].pick_random() if d.get("bed") != null else "on"
		var cv := CarroVisual.new()
		m.add_child(cv)
		cv.montar(d, c, true)
		if Dados.leve():
			Dados.juntar(cv.corpo)
		cv.alcance(130.0)
		var vg := vaga(v)
		cv.position = vg[0]
		cv.rotation.y = float(vg[1]) + randf_range(-0.04, 0.04)
		parados.append(cv)
		# parede invisível pra não atravessar o carro parado
		var corpo := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(d["W"]), 1.3, cv.comprimento)
		col.shape = box
		col.position = Vector3(0, 0.65, (cv.frente_z + cv.tras_z) / 2.0)
		corpo.add_child(col)
		cv.add_child(corpo)
	# galera dançando dentro do galpão: todo mundo na mesma escala (altura de gente de verdade), homens e mulheres
	var dancas := [["dancarino", Vector3(-8, -0.008, 14), 1.78], ["mulher_a", Vector3(-6.6, -0.008, 15.6), 1.65],
		["mulher_b", Vector3(9, -0.008, 15), 1.63], ["dancarino", Vector3(10.2, -0.008, 13.4), 1.75],
		["mulher_c", Vector3(-11, -0.008, -5), 1.67], ["dancarino", Vector3(-9.6, -0.008, -6.6), 1.80],
		["mulher_a", Vector3(6, -0.008, -3), 1.64], ["mulher_c", Vector3(7.4, -0.008, -1.6), 1.66],
		["dancarino", Vector3(-4, -0.008, -17), 1.76], ["mulher_b", Vector3(-2.6, -0.008, -15.8), 1.62],
		["feliz", Vector3(0, -0.008, 6), 1.74], ["mulher_a", Vector3(1.6, -0.008, 7.4), 1.66],
		["feliz", Vector3(5, -0.008, -15), 1.72], ["mulher_c", Vector3(-2, -0.008, 21), 1.65], ["dancarino", Vector3(-0.4, -0.008, 22.2), 1.77],
		["jack", Vector3(-7.2, -0.008, 12.4), 1.80], ["steve", Vector3(8.0, -0.008, 16.4), 1.78], ["henry", Vector3(1.2, -0.008, 4.6), 1.80],
		["steve", Vector3(-10.4, -0.008, -3.6), 1.78], ["henry", Vector3(-1.2, -0.008, 22.8), 1.79], ["jack", Vector3(5.0, -0.008, -16.6), 1.80]]
	for dz in dancas:
		var arq := "res://modelos/personagens/%s.glb" % dz[0]
		if not ResourceLoader.exists(arq):
			continue
		var g: Node3D
		if dz[0] in NOVOS:
			# personagens com esqueleto próprio: a dança é adaptada pro corpo deles
			g = Node3D.new()
			g.add_child(Pessoa.criar_dancando(arq, float(dz[2])))
			m.add_child(g)
			g.position = hx * (dz[1] as Vector3)
			g.rotation.y = randf_range(0, TAU)
			var apn := g.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if apn and apn.has_animation("drops/danca"):
				apn.seek(randf_range(0, 5), true)
				apn.speed_scale = randf_range(0.92, 1.08)
			for gi in g.find_children("*", "GeometryInstance3D", true, false):
				(gi as GeometryInstance3D).visibility_range_end = 110.0
			continue
		g = load(arq).instantiate()
		m.add_child(g)
		g.position = hx * (dz[1] as Vector3)
		g.rotation.y = randf_range(0, TAU)
		g.scale = Vector3.ONE * (float(dz[2]) / _altura_modelo(g))
		for gi in g.find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).visibility_range_end = 110.0
		var ap := g.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and not ap.get_animation_list().is_empty():
			var n: String = ap.get_animation_list()[0]
			ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
			ap.play(n)
			ap.seek(randf_range(0, 5), true)
			ap.speed_scale = randf_range(0.92, 1.08)


## altura do boneco (escala 1) pelo esqueleto em pose de descanso: cada modelo veio numa unidade diferente
func _altura_modelo(g: Node3D) -> float:
	var hi := 0.0
	for s in g.find_children("*", "Skeleton3D", true, false):
		var sk := s as Skeleton3D
		for b in sk.get_bone_count():
			hi = maxf(hi, (sk.global_transform * sk.get_bone_global_rest(b)).origin.y - g.global_position.y)
	return hi if hi > 0.05 else 1.0


func _checar_vaga(dt: float) -> void:
	if m.pe or not mis.is_empty():
		return
	var p: Vector3 = hx.affine_inverse() * m.carro.global_position
	var dentro := false
	for v in VAGAS_LIVRES:
		var c: Vector3 = hx.affine_inverse() * (vaga(v)[0] as Vector3)
		if absf(p.x - c.x) < 3.0 and absf(p.z - c.z) < 1.5:
			dentro = true
	if dentro and m.carro.linear_velocity.length() < 0.6:
		na_vaga += dt
		if na_vaga > 1.0 and not nota_mostrada:
			nota_mostrada = true
			_nota()
	elif not dentro:
		na_vaga = 0.0
		nota_mostrada = false
		nota_painel.visible = false


func nota_rebaixado(c: Dictionary, reb: float) -> Array:
	var alt := clampf(reb / 18.0 * 10.0, 0, 10)   # 18 cm já é nota 10 (caminhonete baixando mais não passa de 10)
	var rod := clampf(4.0 + (float(c["aro"]) - 14.0) * 0.75 + (float(c["tala"]) - 6.0) * 0.5 + (0.6 if c.get("borda", "polida") == "polida" else 0.0) + minf(1.0, float(c.get("camber", 0)) / 3.0), 0, 10)
	var s: String = c.get("som", "off")
	var som := 10.0 if s == "trio" else (9.0 if s == "deitado" else (8.0 if s != "off" else 3.5))
	var neon := 9.5 if c.get("neon", "off") != "off" else 4.0
	var pint: float = {"perola": 10.0, "camaleao": 10.0, "cromado": 9.5, "metal": 8.5, "brilho": 7.5, "fosco": 8.0}.get(c.get("acabamento", "metal"), 7.0)
	var tot := (alt * 1.6 + rod * 1.3 + som + neon * 0.7 + pint) / 5.6
	return [tot, [["Altura", alt], ["Rodas", rod], ["Som", som], ["Neon", neon], ["Pintura", pint]]]


func _nota() -> void:
	var r := nota_rebaixado(m.cfg, (m.rebaixo + m.rebaixo_t) / 2.0)
	var tot: float = r[0]
	var lista := [["Você", tot]]
	for n in RIVAIS:
		lista.append([n, randf_range(6.2, 9.4)])
	lista.sort_custom(func(a, b): return a[1] > b[1])
	var pos := 1
	for i in lista.size():
		if lista[i][0] == "Você":
			pos = i + 1
	var premio := int(round(tot * 600.0 * (2.0 if pos == 1 else 1.0)))
	Dados.ganhar(premio)
	for n in nota_painel.get_children():
		n.queue_free()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	nota_painel.add_child(col)
	_label(col, "NOTA DO REBAIXADO", 22, AMARELO)
	_label(col, ("%.1f" % tot).replace(".", ","), 56, AMARELO)
	for it in r[1]:
		var l := HBoxContainer.new()
		col.add_child(l)
		var a := _label(l, it[0], 18, Color("bbbbbb"))
		a.custom_minimum_size = Vector2(90, 0)
		var barra := ProgressBar.new()
		barra.max_value = 10
		barra.value = it[1]
		barra.show_percentage = false
		barra.custom_minimum_size = Vector2(150, 14)
		barra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("ff3bd4")
		barra.add_theme_stylebox_override("fill", sb)
		l.add_child(barra)
		_label(l, ("  %.1f" % it[1]).replace(".", ","), 18, Color.WHITE)
	_label(col, "%dº lugar no encontro · +%s" % [pos, Dados.reais(premio)], 18, Color("7dff8a"))
	nota_painel.visible = true


# ---------------------------------------------------------------- Desafios
func _ui() -> void:
	var hud: CanvasLayer = m.hud
	var b: Button = m._botao_ui("🏆 DESAFIOS", "desafios")
	b.text = "DESAFIOS"
	b.pressed.connect(_abrir_desafios)
	m.carro_hud.append(b)
	dinheiro_l = _label(hud, "", 22, Color("7dff8a"))
	mis_label = _label(hud, "", 24, Color.WHITE)
	mis_label.add_theme_color_override("font_outline_color", Color.BLACK)
	mis_label.add_theme_constant_override("outline_size", 8)
	mis_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	conta_label = _label(hud, "", 120, AMARELO)
	conta_label.add_theme_color_override("font_outline_color", Color.BLACK)
	conta_label.add_theme_constant_override("outline_size", 16)
	conta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nota_painel = _painel(hud)
	des_painel = _painel(hud)
	res_painel = _painel(hud)
	_posicionar()
	m.get_viewport().size_changed.connect(_posicionar)


func _posicionar() -> void:
	var t: Vector2 = m.get_viewport().get_visible_rect().size
	(m.botoes["desafios"] as Button).position = Vector2(t.x - 26 - 470, 26)
	var mg: float = 26.0 + m._margem_segura()
	(m.botoes["desafios"] as Button).position = Vector2(t.x - mg - 470, mg)
	dinheiro_l.position = Vector2(mg + 214, mg + 40)    # (v36) do lado do minimapa
	mis_label.size = Vector2(t.x, 40)
	mis_label.position = Vector2(0, 80)
	conta_label.size = Vector2(t.x, 160)
	conta_label.position = Vector2(0, t.y * 0.3)
	nota_painel.position = Vector2(mg + 214, mg + 80)
	des_painel.position = Vector2(t.x * 0.5 - 260, t.y * 0.16)
	res_painel.position = Vector2(t.x * 0.5 - 220, t.y * 0.22)


func _label(pai: Node, t: String, tam: int, cor: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", cor)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pai.add_child(l)
	return l


func _painel(hud: Node) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", m._estilo(Color(0.04, 0.04, 0.06, 0.92), AMARELO, 12))
	p.visible = false
	hud.add_child(p)
	return p


func _botao(pai: Node, t: String, cb: Callable, largura := 0) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(largura, 58)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	pai.add_child(b)
	return b


func _abrir_desafios() -> void:
	if not mis.is_empty():
		_fim(false, "Desafio cancelado.", 0)
		return
	for n in des_painel.get_children():
		n.queue_free()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	des_painel.add_child(col)
	_label(col, "DESAFIOS", 30, AMARELO)
	var bd := int(Dados.recordes.get("drift", 0))
	var bt := float(Dados.recordes.get("tiro", 0.0))
	var itens := [["drift", "Drift no Pátio", "40 segundos pra fazer o máximo de pontos de drift no Pátio." + (" Recorde: %d pts." % bd if bd > 0 else "")],
		["tiro", "Tiro até o Hangar", "Sai da Drops e chega no Hangar do Encontro o mais rápido que der." + (" Recorde: %.1fs." % bt if bt > 0 else "")],
		["cliente", "Carro do cliente", "Vai buscar o carro do cliente e traz pra Drops antes do tempo acabar."]]
	for it in itens:
		var b := _botao(col, it[1], _comecar.bind(it[0]), 500)
		b.add_theme_font_size_override("font_size", 24)
		var l := _label(col, it[2], 15, Color("aaaaaa"))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.custom_minimum_size = Vector2(500, 0)
	_botao(col, "Fechar", func(): des_painel.visible = false)
	des_painel.visible = true


func _comecar(k: String) -> void:
	des_painel.visible = false
	res_painel.visible = false
	nota_painel.visible = false
	mis = {"k": k, "t": 0.0, "pts": 0.0, "fase": 0}
	match k:
		"drift":
			m.teletransportar(hx * Vector3(-22, 0.6, 40), hx.basis.get_euler().y + PI / 2.0)   # pátio na frente do hangar
			mis["limite"] = 40.0
			_marcar(Vector3.ZERO, false)
		"tiro":
			_largar_na_drops()
			mis["limite"] = maxf(60.0, DROPS.distance_to(PATIO) / 9.0)
			mis["alvo"] = PATIO
			_marcar(PATIO, true)
		"cliente":
			_largar_na_drops()
			mis["limite"] = 120.0
			mis["alvo"] = CLIENTES.pick_random()
			_marcar(mis["alvo"], true, Color("2be7ff"))
	contagem = 3.6
	m.congelado = true


## começo dos desafios: na rua, na frente do portão da Drops
func _largar_na_drops() -> void:
	var mp: Dictionary = m.rede.mais_perto(DROPS, 20.0)
	var d := Vector2(1, 0) if mp.is_empty() else (mp["dir"] as Vector2)
	var q := DROPS if mp.is_empty() else Vector3(mp["ponto"].x, 0, mp["ponto"].y)
	var dir3 := Vector3(d.x, 0, d.y)
	var direita := Vector3(-dir3.z, 0, dir3.x)
	m.teletransportar(q + direita * 1.8 + Vector3.UP * 0.6, atan2(dir3.x, dir3.z))


func _fim(ok: bool, txt: String, premio: int) -> void:
	var k: String = mis.get("k", "")
	mis = {}
	m.congelado = false
	contagem = 0.0
	conta_label.text = ""
	mis_label.text = ""
	_marcar(Vector3.ZERO, false)
	if premio > 0:
		Dados.ganhar(premio)
	for n in res_painel.get_children():
		n.queue_free()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	res_painel.add_child(col)
	_label(col, "DESAFIO CONCLUÍDO" if ok else "NÃO FOI DESSA VEZ", 28, AMARELO)
	var l := _label(col, txt, 20, Color.WHITE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(420, 0)
	if premio > 0:
		_label(col, "+" + Dados.reais(premio), 22, Color("7dff8a"))
	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 10)
	col.add_child(linha)
	if k != "":
		_botao(linha, "De novo", _comecar.bind(k), 200)
	_botao(linha, "Voltar pro rolê", func(): res_painel.visible = false, 200)
	res_painel.visible = true


func _marcador() -> void:
	marcador = Node3D.new()
	var cil := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.2
	cm.bottom_radius = 2.2
	cm.height = 30.0
	cm.cap_top = false
	cm.cap_bottom = false
	cil.mesh = cm
	cil.position.y = 15.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1, 0.83, 0, 0.25)
	cil.material_override = mat
	marcador.add_child(cil)
	marcador.visible = false
	m.add_child(marcador)
	# setinha em cima do carro apontando pro objetivo
	seta = MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.6, 1.0, 0.15)
	seta.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = AMARELO
	seta.material_override = sm
	seta.visible = false
	m.add_child(seta)


func _marcar(p: Vector3, ligado: bool, cor := AMARELO) -> void:
	marcador.visible = ligado
	seta.visible = ligado
	marcador.position = p
	((marcador.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = Color(cor.r, cor.g, cor.b, 0.25)
	(seta.material_override as StandardMaterial3D).albedo_color = cor


func _desafio(dt: float) -> void:
	if mis.is_empty():
		return
	if contagem > 0.0:
		var antes := ceili(contagem)
		contagem -= dt
		var c := ceili(contagem)
		conta_label.text = str(c) if c > 0 and c <= 3 else ""
		if contagem <= 0.0:
			conta_label.text = "VAI!"
			m.congelado = false
			m.get_tree().create_timer(0.7).timeout.connect(func(): conta_label.text = "")
		return
	mis["t"] = float(mis["t"]) + dt
	var t: float = mis["t"]
	var resta: float = float(mis["limite"]) - t
	var p: Vector3 = m.carro.global_position
	if seta.visible:
		var alvo: Vector3 = mis.get("alvo", p)
		seta.global_position = p + Vector3.UP * 2.4
		var dir := Vector3(alvo.x - p.x, 0, alvo.z - p.z)
		if dir.length() > 0.1:
			seta.look_at(seta.global_position + dir, Vector3.UP)
			seta.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
	match mis["k"]:
		"drift":
			var lado := absf(m.carro.linear_velocity.dot(m.carro.global_basis.x))
			var vel := m.carro.linear_velocity.length()
			if lado > 2.5 and vel > 8.0:
				mis["pts"] = float(mis["pts"]) + dt * (lado * 18.0 + vel * 3.0)
			var pts := int(mis["pts"])
			mis_label.text = "DRIFT · %d pts · %ds" % [pts, maxi(0, ceili(resta))]
			if resta <= 0.0:
				var rec := int(Dados.recordes.get("drift", 0))
				if pts > rec:
					Dados.recordes["drift"] = pts
				_fim(pts >= 1500, "Você fez %d pontos de drift%s." % [pts, " (recorde!)" if pts > rec else " · recorde: %d" % maxi(rec, pts)], pts * 2)
		"tiro":
			var d := Vector2(p.x - PATIO.x, p.z - PATIO.z).length()
			mis_label.text = "TIRO ATÉ O HANGAR · %.1fs · %d m" % [t, int(d)]
			if d < 5.0:
				var rec := float(Dados.recordes.get("tiro", 999.0))
				if t < rec:
					Dados.recordes["tiro"] = t
				_fim(true, "Chegou em %.1f segundos%s." % [t, " (recorde!)" if t < rec else " · recorde: %.1fs" % minf(rec, t)], int(maxf(500.0, 6000.0 - t * 120.0)))
			elif resta <= 0.0:
				_fim(false, "O tempo acabou. Olha o minimapa pra cortar caminho.", 0)
		"cliente":
			var alvo: Vector3 = mis["alvo"]
			var d := Vector2(p.x - alvo.x, p.z - alvo.z).length()
			mis_label.text = "%s · %d m · %ds" % ["BUSCA O CARRO DO CLIENTE" if int(mis["fase"]) == 0 else "LEVA PRA DROPS", int(d), maxi(0, ceili(resta))]
			if d < 5.0:
				if int(mis["fase"]) == 0:
					mis["fase"] = 1
					mis["alvo"] = DROPS
					_marcar(DROPS, true)
					m.toast("CARRO NA MÃO! BORA PRA DROPS")
				else:
					_fim(true, "Carro do cliente entregue na Drops com %d segundos sobrando." % int(resta), int(2000.0 + resta * 60.0))
			elif resta <= 0.0:
				_fim(false, "O cliente cansou de esperar. Tenta de novo!", 0)


# ---------------------------------------------------------------- Trânsito (anda nas ruas de verdade da CIC)
func _transito() -> void:
	var n_pm := 2 if Dados.leve() else 3   # viaturas patrulhando no meio do trânsito
	var n_av := 3 if Dados.leve() else 6   # carros só nas avenidas (rodovia, avenidas grandes)
	var total := (4 if Dados.leve() else 7) + n_pm + n_av
	for k in total:
		var pm := k < n_pm
		var av := k >= total - n_av
		var i := _indice(Policia.CARRO_VIATURA if pm else LEVES.pick_random())
		var c := _rnd_cfg(i)
		c["rebaixo"] = randf_range(0.0, 8.0)
		c["rebaixo_tras"] = c["rebaixo"]
		c["neon"] = "off" if randf() < 0.6 else ["roxo", "azul", "ciano", "rosa"].pick_random()
		c["som"] = "off"
		if pm:
			c = Policia.cfg_viatura(Dados.carros[i])
		var cv := CarroVisual.new()
		m.add_child(cv)
		cv.montar(Dados.carros[i], c, true)
		cv.por_motorista()   # (v40) ninguém dirigindo era macabro
		if pm and m.policia:
			m.policia.vestir(cv)
		if Dados.leve():
			Dados.juntar(cv.corpo)
		cv.alcance(320.0 if av else 150.0)
		var corpo := AnimatableBody3D.new()
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(Dados.carros[i]["W"]), 1.2, cv.comprimento)
		col.shape = box
		col.position = Vector3(0, 0.7, (cv.frente_z + cv.tras_z) / 2.0)
		corpo.add_child(col)
		m.add_child(corpo)
		var t := {"cv": cv, "corpo": corpo, "i": -1, "s": 0.0, "dir": 1.0, "sp": 0.0, "vmax": randf_range(8.0, 12.5),
			"espera": 0.0, "pos": Vector3.ZERO, "h": 0.0, "ok": false, "av": av}
		_reposicionar(t, m.carro.global_position if m.carro else DROPS, 40.0, 200.0)
		transito.append(t)


## coloca o carro numa rua aleatória longe o bastante do jogador
func _reposicionar(t: Dictionary, centro: Vector3, rmin: float, rmax: float) -> void:
	var pa: Dictionary = {}
	if t.get("av", false):
		pa = m.rede.ponto_aleatorio(centro, rmin, rmax + 250.0, RedeCIC.AVENIDAS)
	if pa.is_empty():
		pa = m.rede.ponto_aleatorio(centro, rmin, rmax)
	if pa.is_empty():
		return
	t["i"] = pa["i"]
	t["s"] = pa["s"]
	t["dir"] = 1.0 if randf() < 0.5 or m.rede.mao_unica(pa["i"]) else -1.0
	var tipo: String = m.rede.ruas[pa["i"]]["tipo"]
	if OS.has_environment("DROPS_PERF") and t.get("av", false):
		print("trânsito avenida: ", tipo, " ", m.rede.ruas[pa["i"]]["nome"], " ", m.rede.ponto(pa["i"], pa["s"]).round())
	t["vmax"] = randf_range(15.0, 21.0) if tipo in ["motorway", "trunk"] else (randf_range(11.0, 15.0) if tipo in RedeCIC.AVENIDAS else randf_range(8.0, 12.5))
	t["ok"] = false
	t["sp"] = 0.0


func _faixa(t: Dictionary) -> Vector3:
	var q: Vector2 = m.rede.ponto(t["i"], t["s"])
	var d: Vector2 = m.rede.direcao(t["i"], t["s"]) * float(t["dir"])
	var w: float = m.rede.ruas[t["i"]]["w"]
	var direita := Vector2(-d.y, d.x)
	q += direita * w * (0.14 if m.rede.mao_unica(t["i"]) else 0.24)   # mão direita (na pista dupla, faixa da direita)
	return Vector3(q.x, m.mapa.altura(q.x, q.y), q.y)


func _rumo(t: Dictionary) -> float:
	var d: Vector2 = m.rede.direcao(t["i"], t["s"]) * float(t["dir"])
	return atan2(d.x, d.y)


func _andar_transito(dt: float) -> void:
	var jogador: Vector3 = m.pessoa.global_position if m.pe and m.pessoa else m.carro.global_position
	for t in transito:
		if int(t["i"]) < 0:
			_reposicionar(t, jogador, 60.0, 220.0)
			continue
		# longe demais: some e aparece em outra rua perto de você
		if (t["pos"] as Vector3).distance_to(jogador) > (420.0 if t.get("av", false) else 280.0) and t["ok"]:
			_reposicionar(t, jogador, 120.0, 230.0)
		var h := _rumo(t)
		var f := Vector3(sin(h), 0, cos(h))
		var pos: Vector3 = t["pos"]
		# (v40) quem está na frente na MESMA mão segura a fila; carro cruzando ou vindo de frente só faz
		# esperar um pouquinho (antes os dois esperavam um pelo outro pra sempre e formava fila parada)
		var bloq := false
		var bloq_cruz := false
		var bloq_jog := false
		for o in transito:
			if o == t or not o["ok"]:
				continue
			var d: Vector3 = (o["pos"] as Vector3) - pos
			var frente := d.dot(f)
			var lado := absf(d.dot(Vector3(f.z, 0, -f.x)))
			if frente > 0.0 and frente < 8.5 and lado < 2.2:
				if cos(float(o["h"]) - float(t["h"])) > 0.6:
					bloq = true
				elif frente < 6.0:
					bloq_cruz = true
		var dj: Vector3 = jogador - pos
		if dj.dot(f) > 0.0 and dj.dot(f) < 11.0 and absf(dj.dot(Vector3(f.z, 0, -f.x))) < 2.2:
			bloq_jog = true
		t["preso"] = float(t.get("preso", 0.0)) + dt if (bloq or bloq_cruz or bloq_jog) else 0.0
		if bloq_cruz and float(t["preso"]) < 2.0:
			bloq = true   # dá a vez um pouco e depois passa
		if bloq_jog:
			bloq = true
			if float(t["preso"]) > 7.0:   # você parado na frente faz tempo: ele dá meia-volta
				t["dir"] = -float(t["dir"])
				t["preso"] = 0.0
		if bloq and float(t["preso"]) > 9.0 and not bloq_jog:
			bloq = false   # fila travada há muito tempo: destrava
		if float(t["espera"]) > 0.0:
			t["espera"] = float(t["espera"]) - dt
			bloq = true
		var alvo_v: float = 0.0 if bloq else float(t["vmax"])
		t["sp"] = lerpf(t["sp"], alvo_v, minf(1.0, dt * (4.0 if bloq else 1.2)))
		var r: Dictionary = m.rede.ruas[t["i"]]
		var ns: float = float(t["s"]) + float(t["dir"]) * float(t["sp"]) * dt
		if ns > float(r["L"]) or ns < 0.0:
			# chegou no fim da rua: entra numa rua que sai dali (ou volta)
			var ponta := 1 if ns > float(r["L"]) else 0
			var op: Array = m.rede.saidas(t["i"], ponta)
			if op.is_empty():
				t["dir"] = -float(t["dir"])
				t["s"] = clampf(ns, 0.0, float(r["L"]))
			else:
				var e: Array = op.pick_random()
				t["i"] = e[0]
				t["s"] = e[1]
				t["dir"] = e[2]
		else:
			t["s"] = ns
		var alvo := _faixa(t)
		var rumo := _rumo(t)
		if not t["ok"]:
			t["pos"] = alvo
			t["h"] = rumo
			t["ok"] = true
		var k := 1.0 - exp(-dt * 3.5)
		t["pos"] = (t["pos"] as Vector3).lerp(alvo, k)
		t["h"] = lerp_angle(float(t["h"]), rumo, minf(1.0, dt * 3.0))
		var cv: CarroVisual = t["cv"]
		cv.global_position = t["pos"]
		# inclina na subida/descida
		var fr := Vector3(sin(float(t["h"])), 0, cos(float(t["h"])))
		var pp: Vector3 = t["pos"]
		var dh := m.mapa.altura(pp.x + fr.x * 1.6, pp.z + fr.z * 1.6) - m.mapa.altura(pp.x - fr.x * 1.6, pp.z - fr.z * 1.6)
		var incl := -atan2(dh, 3.2)
		cv.rotation = Vector3(incl, float(t["h"]), 0)
		for roda in cv.rodas:
			roda.rotate_object_local(Vector3.RIGHT, float(t["sp"]) / cv.raio() * dt)
		var longe := (t["pos"] as Vector3).distance_to(jogador) > (320.0 if t.get("av", false) else 170.0)
		cv.visible = not longe
		(t["corpo"] as AnimatableBody3D).global_transform = Transform3D(Basis.from_euler(Vector3(incl, float(t["h"]), 0)), t["pos"])
		# se você bater, ele para um pouco
		if not m.pe and (t["pos"] as Vector3).distance_to(m.carro.global_position) < 3.0:
			t["espera"] = 1.2


func _physics_process(dt: float) -> void:
	if m == null or m.carro == null:
		return
	_andar_transito(dt)
	_desafio(dt)
	_checar_vaga(dt)
	dinheiro_l.text = Dados.reais(Dados.dinheiro)
	if Dados.musica.playing and m.carro.global_position.distance_to(PATIO) < 90.0:
		for cv in parados:
			cv.pulsar()
