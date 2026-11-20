class_name CarroVisual
extends Node3D
## Monta o carro por fora: lataria com a pintura, rodas (aro + pneu), neon e o som da caçamba/porta-malas.
## Usado na garagem (com rodas paradas) e na rua (as rodas vão dentro das rodas de física).

var d: Dictionary
var c: Dictionary
var corpo := Node3D.new()        # tudo que desce quando rebaixa
var modelo: Node3D
var rodas: Array[Node3D] = []    # rodas da garagem
var com_rodas := true
var mat_pintura := ShaderMaterial.new()
var neon_luz: OmniLight3D
var neon_chao: MeshInstance3D
var som_no: Node3D
var piso := 0.0                  # altura do assoalho em relação ao 'corpo' (pra saber quando raspa)
var comprimento := 4.2
var frente_z := 2.0
var tras_z := -2.0
var base_y := 0.0
var partes := {}                 # "portas"/"frente"/"tras" -> {nome, lista:[[pivo, giro_aberto]], t, quer}
var pecas := {}                  # (fase 2) peça soltável: "PFL" -> pivô (porta, capô, porta-malas)
var _caixa_peca := {}            # "PFL" -> AABB da peça no espaço do pivô (pra achar o meio dela)

static var _pneus := {}          # malha do pneu guardada por medida
static var detalhe_total := false  # garagem: carro com todos os detalhes; na rua o carro muito pesado usa a versão simplificada
static var lod_extra := 1.0     # (v33) gráfico ALTO: carros pesados perdem menos detalhe
var triangulos := 0


## carro com muito triângulo (alguns modelos novos passam de 800 mil): na rua usa os níveis simplificados
## que o Godot gera na importação (LOD) — de perto quase não muda, e pesa bem menos
func _ajustar_detalhe() -> void:
	triangulos = 0
	var lista := modelo.find_children("*", "MeshInstance3D", true, false)
	for n in lista:
		var m := (n as MeshInstance3D).mesh
		if m:
			for s in m.get_surface_count():
				triangulos += m.surface_get_array_index_len(s) / 3
	var vies := 1.0 if detalhe_total else clampf(200000.0 * lod_extra / maxf(triangulos, 1.0), 0.12, 1.0)
	for n in lista:
		(n as GeometryInstance3D).lod_bias = vies


func montar(dados: Dictionary, cfg: Dictionary, rodas_paradas := true) -> void:
	d = dados
	com_rodas = rodas_paradas
	add_child(corpo)
	mat_pintura.shader = load("res://scripts/pintura.gdshader")
	modelo = load(Dados.modelo("res://modelos/carros/%s.glb" % d["id"])).instantiate()
	corpo.add_child(modelo)
	_materiais(modelo)
	_medir()
	_montar_partes()
	_ajustar_detalhe()
	neon_luz = OmniLight3D.new()
	neon_luz.omni_range = 3.2
	neon_luz.omni_attenuation = 1.4
	neon_luz.position = Vector3(0, 0.12, (float(d["axF"]) + float(d["axR"])) / 2.0)
	add_child(neon_luz)
	neon_chao = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(float(d["W"]) + 1.6, float(d["axF"]) - float(d["axR"]) + 2.6)
	q.orientation = PlaneMesh.FACE_Y
	neon_chao.mesh = q
	neon_chao.position = Vector3(0, 0.015, neon_luz.position.z)
	neon_chao.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(neon_chao)
	# sombra de contato embaixo do carro (o modo do celular não tem oclusão de ambiente): assenta o carro no chão
	var sombra := MeshInstance3D.new()
	sombra.name = "sombra_contato"
	var sq := QuadMesh.new()
	sq.size = Vector2(float(d["W"]) + 0.35, comprimento + 0.45)
	sq.orientation = PlaneMesh.FACE_Y
	sombra.mesh = sq
	sombra.position = Vector3(0, 0.008, (frente_z + tras_z) / 2.0)
	sombra.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0, 0, 0, 0.82)
	sm.albedo_texture = _sombra_tex()
	sm.render_priority = -1
	sombra.material_override = sm
	add_child(sombra)
	atualizar(cfg)


## não desenha o carro quando ele está longe da câmera (deixa o jogo bem mais leve)
func alcance(metros: float) -> void:
	for n in find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).visibility_range_end = metros
		(n as GeometryInstance3D).visibility_range_end_margin = 10.0


func _medir() -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for n in modelo.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh == null:
			continue
		var t: Transform3D = corpo.global_transform.affine_inverse() * m.global_transform if is_inside_tree() else m.transform
		var b: AABB = t * m.get_aabb()
		lo = lo.min(b.position)
		hi = hi.max(b.end)
	if lo.x == INF:
		return
	frente_z = hi.z
	tras_z = lo.z
	comprimento = hi.z - lo.z
	# assoalho: um pouco acima do ponto mais baixo (para-choque/saia)
	piso = lo.y + 0.02


# ---------------------------------------------------------------- portas, capô e porta-malas
func _montar_partes() -> void:
	var pp = d.get("partes")
	if pp == null:
		return
	var filhos := modelo.find_children("*", "Node3D", true, false)
	for k in pp:
		var lista := []
		for item in pp[k]["p"]:
			var pv := Vector3(item[1][0], item[1][1], item[1][2])
			var q := Quaternion(item[2][0], item[2][1], item[2][2], item[2][3]).normalized()
			var pivo := Node3D.new()
			pivo.position = pv
			modelo.add_child(pivo)
			for f in filhos:
				if str(f.name).begins_with(str(item[0]) + "__") and not str(f.get_parent().name).begins_with(str(item[0]) + "__"):
					f.reparent(pivo, true)
			lista.append([pivo, q])
			pecas[str(item[0])] = pivo
		partes[k] = {"nome": pp[k]["nome"], "lista": lista, "t": 0.0, "quer": 0.0}
	# (fase 2) peças que o jogador tirou na oficina ficam fora (o carro anda sem elas)
	for id in c.get("sem_pecas", []):
		if pecas.has(str(id)):
			(pecas[str(id)] as Node3D).visible = false
	_aplicar_cores_pecas()


# ---------------------------------------------------------------- (fase 2) tirar e colocar peças
const NOMES_PECA := {"PFL": "PORTA ESQ. DA FRENTE", "PFR": "PORTA DIR. DA FRENTE", "PRL": "PORTA ESQ. DE TRÁS",
	"PRR": "PORTA DIR. DE TRÁS", "PCA": "CAPÔ", "PTR": "PORTA-MALAS"}

func nome_peca(id: String) -> String:
	if id == "PTR" and bool(d.get("picape", false)):
		return "TAMPA DA CAÇAMBA"
	return NOMES_PECA.get(id, id)


func tem_peca(id: String) -> bool:
	return pecas.has(id) and (pecas[id] as Node3D).visible


## (fase 2) pintura por peça: c["cores_pecas"] = {"PFL": "#d12a2a", ...}. A peça usa a mesma tinta do carro
## (acabamento, verniz, reflexo) só com outra cor. Sem cor própria, volta pra tinta do carro.
var _mats_peca := {}

## desgaste de uma parte ("carro" ou id da peça): {"f": ferrugem, "s": sujeira, "a": amassado}, 0..1
func desgaste(id: String) -> Dictionary:
	var dg: Dictionary = c.get("desgaste", {})
	var base: Dictionary = dg.get("carro", {})
	var r := {"f": float(base.get("f", 0.0)), "s": float(base.get("s", 0.0)), "a": float(base.get("a", 0.0))}
	if id != "carro" and dg.has(id):
		var p: Dictionary = dg[id]
		for k in r:
			if p.has(k):
				r[k] = float(p[k])
	return r


func _usar_desgaste(mat: ShaderMaterial, dg: Dictionary, semente: Vector3) -> void:
	mat.set_shader_parameter("ferrugem", dg["f"])
	mat.set_shader_parameter("sujeira", dg["s"])
	mat.set_shader_parameter("amassado", dg["a"])
	mat.set_shader_parameter("semente", semente)


func _aplicar_cores_pecas() -> void:
	_usar_desgaste(mat_pintura, desgaste("carro"), Vector3.ZERO)
	if pecas.is_empty():
		return
	var cp: Dictionary = c.get("cores_pecas", {})
	var dg_carro := desgaste("carro")
	var k := 0
	for id in pecas:
		k += 1
		var mat: Material = mat_pintura
		var dg := desgaste(id)
		if cp.has(id) or dg != dg_carro:
			var m2: ShaderMaterial = mat_pintura.duplicate()
			var acab: String = c.get("acabamento", "metal")
			var cor_p := str(cp.get(id, c["cor"]))
			m2.set_shader_parameter("cor", Color(cor_p) if acab != "cromado" else Color(cor_p).lerp(Color.WHITE, 0.6))
			_usar_desgaste(m2, dg, Vector3(k * 7.3, k * 3.1, k * 5.7))
			_mats_peca[id] = m2
			mat = m2
		else:
			_mats_peca.erase(id)
		for mi in (pecas[id] as Node3D).find_children("*", "MeshInstance3D", true, false):
			var mm := mi as MeshInstance3D
			for i in mm.get_surface_override_material_count():
				var o := mm.get_surface_override_material(i)
				if o == mat_pintura or (o is ShaderMaterial and (o as ShaderMaterial).shader == mat_pintura.shader):
					mm.set_surface_override_material(i, mat)


## todas as peças daquela parte ("portas", "frente", "tras") foram tiradas
func parte_fora(k: String) -> bool:
	if not partes.has(k):
		return true
	for item in partes[k]["lista"]:
		if (item[0] as Node3D).visible:
			return false
	return true


func mostrar_peca(id: String, sim: bool) -> void:
	if pecas.has(id):
		(pecas[id] as Node3D).visible = sim


## caixa da peça no espaço do pivô (calculada uma vez)
func caixa_peca(id: String) -> AABB:
	if _caixa_peca.has(id):
		return _caixa_peca[id]
	var pv: Node3D = pecas[id]
	var bb := AABB()
	var primeiro := true
	var inv := pv.global_transform.affine_inverse()
	for mi in pv.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (inv * (mi as MeshInstance3D).global_transform) * (mi as MeshInstance3D).get_aabb()
		bb = b if primeiro else bb.merge(b)
		primeiro = false
	_caixa_peca[id] = bb
	return bb


## meio da peça no mundo (serve até com a peça escondida)
func centro_peca(id: String) -> Vector3:
	var pv: Node3D = pecas[id]
	return pv.global_transform * caixa_peca(id).get_center()


func abrir(k: String) -> void:
	if partes.has(k):
		partes[k]["quer"] = 0.0 if float(partes[k]["quer"]) > 0.5 else 1.0


func fechar_tudo() -> void:
	for k in partes:
		partes[k]["quer"] = 0.0


func aberto(k: String) -> bool:
	return partes.has(k) and float(partes[k]["quer"]) > 0.5


## carro parado com som: pula no grave e o neon pisca
func pulsar() -> void:
	var g := Dados.grave
	var s: String = c.get("som", "off")
	var k := 0.012 if s == "off" else (0.045 if s == "deitado" else 0.032)
	corpo.position.y = base_y - g * g * k
	if neon_luz.visible:
		neon_luz.light_energy = 1.6 + g * 3.0


func _process(dt: float) -> void:
	for k in partes:
		var p: Dictionary = partes[k]
		var t: float = p["t"]
		var quer: float = p["quer"]
		if is_equal_approx(t, quer):
			continue
		t = move_toward(t, quer, dt * 1.4)
		p["t"] = t
		var e := t * t * (3.0 - 2.0 * t)
		for item in p["lista"]:
			(item[0] as Node3D).quaternion = Quaternion.IDENTITY.slerp(item[1], e)


# ---------------------------------------------------------------- medidas
func raio_aro() -> float:
	return float(c["aro"]) * 0.0254 / 2.0

func raio() -> float:
	return raio_aro() + float(c["flanco"]) / 100.0

func largura() -> float:
	return float(c["tala"]) * 0.0254

func x_roda() -> float:
	var poke: float = max(0.0, float(c["tala"]) - 7.0) * 0.0254 * 0.6
	return float(d["W"]) / 2.0 - largura() / 2.0 - 0.02 + poke - float(c.get("recuo", 0.0)) / 100.0   # recuo: roda pra dentro do para-lama


## (v37) maior aro que cabe no para-lama sem o carro precisar subir (com o flanco dado em cm), de 15 a 28
static func aro_maximo(dd: Dictionary, flanco_cm := 3.0) -> int:
	var a = dd.get("arcos")
	if not (a is Dictionary) or a.get("f") == null or a.get("t") == null:
		return 18
	var lim: float = minf(float(a["f"][0]), float(a["t"][0])) - float(dd["wy"]) - 0.015 - flanco_cm / 100.0
	return clampi(int(floor(lim * 2.0 / 0.0254)), 15, 28)


## (v40) motorista sentado no banco da esquerda (carros do trânsito e viaturas): malha fixa, quase não pesa
static var _motoristas: Array = []
var motorista: Node3D
func por_motorista() -> void:
	if _motoristas.is_empty():
		for mo in ["mecanico", "dancarino", "mulher_a", "mulher_b"]:
			var arq := "res://modelos/personagens/motoristas/%s.glb" % mo
			if ResourceLoader.exists(arq):
				_motoristas.append(load(arq))
	if _motoristas.is_empty() or motorista != null:
		return
	motorista = (_motoristas.pick_random() as PackedScene).instantiate()
	var wb := float(d["axF"]) - float(d["axR"])
	var meio := (float(d["axF"]) + float(d["axR"])) / 2.0
	var pic := bool(d.get("picape", false))
	motorista.position = Vector3(float(d["W"]) * 0.2, float(d.get("saia", 0.25)) + (POS_MOTORISTA.y + 0.12 if pic else POS_MOTORISTA.y),
		meio + (POS_MOTORISTA.z + 0.08 if pic else POS_MOTORISTA.z) * wb)
	corpo.add_child(motorista)
	for gi in motorista.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(gi as GeometryInstance3D).visibility_range_end = 80.0
const POS_MOTORISTA := Vector3(0, 0.24, -0.12)   # altura do quadril acima da saia; z em fração do entre-eixos


## (v38) quanto cada carro pode baixar (cm): até a saia lateral ficar a 5 cm do chão (nunca menos que 18).
## Caminhonete e SUV saem de fábrica bem mais altas, então baixam bem mais que um Gol.
static func rebaixo_max(dd: Dictionary) -> float:
	return maxf(18.0, roundf((float(dd.get("saia", 0.23)) - 0.05) * 100.0))


## (v37) configuração "socada" dos carros de evento: no chão (rebaixo máximo), pneu fininho e o maior aro que cabe
static func socar(dd: Dictionary, cc: Dictionary) -> Dictionary:
	cc["flanco"] = 3.0
	cc["aro"] = aro_maximo(dd, 3.0)
	cc["rebaixo"] = rebaixo_max(dd)
	cc["rebaixo_tras"] = rebaixo_max(dd)
	cc["tala"] = 8.5 if int(cc["aro"]) >= 19 else 8.0
	return cc


## arco do para-lama de cada eixo: [altura do topo do arco, meia largura da borda do para-lama] (medido no modelo)
static var _arcos := {}
func _arcos_medir() -> void:
	var id := str(d["id"])
	if _arcos.has(id):
		return
	var pronto = d.get("arcos")   # medido antes pelo ferramentas/medir_arcos.py (não trava o jogo medindo)
	if pronto is Dictionary:
		_arcos[id] = {true: pronto.get("f"), false: pronto.get("t")}
		return
	var W := float(d["W"])
	var wy := float(d["wy"])
	var res := {}
	for frente in [true, false]:
		var ax := float(d["axF"]) if frente else float(d["axR"])
		var pts := PackedVector3Array()
		for n in modelo.find_children("*", "MeshInstance3D", true, false):
			var m := n as MeshInstance3D
			if m.mesh == null or not m.visible:
				continue
			var t := Acessorios._ate(m, modelo)
			for s in m.mesh.get_surface_count():
				var mat := m.get_active_material(s)
				if mat == _nada_mat:
					continue
				var vs: PackedVector3Array = m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for v in vs:
					var p := t * v
					if absf(p.z - ax) < 0.06 and absf(p.x) > W / 2.0 - 0.12 and p.y > wy + 0.05:
						pts.append(p)
		var ay := INF
		for p in pts:
			ay = minf(ay, p.y)
		var axx := 0.0
		for p in pts:
			if p.y < ay + 0.03:
				axx = maxf(axx, absf(p.x))
		res[frente] = [ay, axx] if ay < INF and axx > 0.3 else null
	_arcos[id] = res


## rebaixo de verdade do eixo (m): roda grande num carro de para-lama baixo primeiro sobe o carro até o pneu caber
## no arco (na altura 0), e daí o rebaixo desce a partir disso
func rebaixo_eixo(frente: bool, reb_cm := -999.0) -> float:
	var reb := reb_cm
	if reb_cm < -998.0:
		reb = float(c.get("rebaixo", 0.0)) if frente else float(c.get("rebaixo_tras", c.get("rebaixo", 0.0)))
	return reb / 100.0 - sobe_arco(frente)


## quanto o carro precisa subir (m) pra roda escolhida caber no arco do para-lama na altura original
func sobe_arco(frente: bool) -> float:
	var a = _arcos.get(str(d["id"]), {}).get(frente)
	if a == null:
		return 0.0
	var topo0: float = float(a[0]) + raio() - float(d["wy"])
	return maxf(0.0, raio() * 2.0 + 0.015 - topo0)


## posição da roda no eixo: se o carro está tão baixo que o pneu entra no para-lama, a roda fica por dentro
## da borda do para-lama (senão o pneu atravessa a lataria e aparece por fora)
func x_roda_eixo(frente: bool, reb_cm := -999.0) -> float:
	var x := x_roda()
	var a = _arcos.get(str(d["id"]), {}).get(frente)
	if a == null:
		return x
	var desloc := raio() - float(d["wy"]) - rebaixo_eixo(frente, reb_cm)     # quanto o corpo fica acima/abaixo do eixo
	var topo_arco: float = float(a[0]) + desloc
	if raio() * 2.0 > topo_arco - 0.015:
		x = minf(x, float(a[1]) - largura() / 2.0 - 0.015)
	return x


func atualizar(cfg: Dictionary) -> void:
	c = cfg
	# pintura
	var acab: String = c.get("acabamento", "metal")
	var p: Array = {"metal": [0.6, 0.24, 1.0, 0.0], "brilho": [0.08, 0.12, 1.0, 0.0], "perola": [0.35, 0.18, 1.0, 0.45],
		"fosco": [0.2, 0.62, 0.0, 0.0], "camaleao": [0.55, 0.16, 1.0, 1.0], "cromado": [1.0, 0.04, 1.0, 0.0]}.get(acab, [0.6, 0.24, 1.0, 0.0])
	mat_pintura.set_shader_parameter("cor", Color(str(c["cor"])) if acab != "cromado" else Color(str(c["cor"])).lerp(Color.WHITE, 0.6))
	mat_pintura.set_shader_parameter("cor2", Color(str(c.get("cor2", "#c99cf0"))))
	mat_pintura.set_shader_parameter("metal", p[0])
	mat_pintura.set_shader_parameter("aspereza", p[1])
	mat_pintura.set_shader_parameter("verniz", p[2])
	mat_pintura.set_shader_parameter("flip", p[3])
	_aplicar_cores_pecas()
	# altura: o eixo do modelo encaixa no centro da roda e desce o quanto rebaixou
	_arcos_medir()
	var rf := rebaixo_eixo(true)
	var rr := rebaixo_eixo(false)
	corpo.position.y = raio() - float(d["wy"]) - (rf + rr) / 2.0
	corpo.rotation.x = -atan((rr - rf) / (float(d["axF"]) - float(d["axR"])))   # dianteira e traseira separadas
	base_y = corpo.position.y
	# rodas paradas (garagem)
	for r in rodas:
		r.queue_free()
	rodas.clear()
	if com_rodas:
		for i in 4:
			var frente := i < 2
			var lado := -1.0 if i % 2 == 0 else 1.0
			var r := nova_roda(lado, i)
			r.position = Vector3(lado * x_roda_eixo(frente), raio(), float(d["axF"]) if frente else float(d["axR"]))
			add_child(r)
			rodas.append(r)
	# neon
	var n: String = Dados.NEONS.get(c.get("neon", "off"), "")
	neon_luz.visible = n != ""
	neon_chao.visible = n != ""
	if n != "":
		neon_luz.light_color = Color(n)
		neon_luz.light_energy = 2.4
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(n)
		m.albedo_texture = _brilho()
		neon_chao.material_override = m
	_som()
	Acessorios.montar(self)   # body kit e acessórios (lip, saias, aerofólio, santo antônio, capota, rack)


## uma roda (pneu + aro), com o centro na origem e o eixo em X; lado -1 = esquerda
## qual aro vai na roda i (0 diant. esq, 1 diant. dir, 2 tras. esq, 3 tras. dir):
## o elevador da oficina pode deixar rodas diferentes ("rodas"), senão é o jogo inteiro ("roda")
func id_roda(i: int = -1) -> String:
	var rs = c.get("rodas", [])
	if i >= 0 and rs is Array and rs.size() == 4 and str(rs[i]) != "":
		return str(rs[i])
	return str(c.get("roda", "work"))


func nova_roda(lado: float, i: int = -1) -> Node3D:
	var r := Node3D.new()
	var dentro := Node3D.new()       # cambagem
	dentro.rotation.z = deg_to_rad(float(c.get("camber", 0))) * (1.0 if lado > 0 else -1.0)
	r.add_child(dentro)
	var gira := Node3D.new()         # o giro fica DENTRO da cambagem (senão a roda fica bamba girando)
	gira.name = "gira"
	dentro.add_child(gira)
	var pneu := MeshInstance3D.new()
	pneu.mesh = _pneu(raio(), raio_aro(), largura() + 0.03)
	gira.add_child(pneu)
	var arq := Dados.modelo("res://modelos/rodas/%s.glb" % id_roda(i))
	if ResourceLoader.exists(arq):
		var aro: Node3D = load(arq).instantiate()
		aro.scale = Vector3(largura(), raio_aro(), raio_aro())
		if lado < 0:
			aro.rotation.y = PI
		_cor_aro(aro)
		gira.add_child(aro)
	return r


func _cor_aro(aro: Node) -> void:
	var cor := Color(str(c.get("cor_roda", "#c9ccd1")))
	var polida: bool = c.get("borda", "polida") == "polida"
	# v33: raios com tinta de roda de verdade (luz + pouco reflexo). Antes era tudo espelho cromado:
	# o branco virava cromo e as rodas ficavam escuras/estranhas dependendo do lugar
	var raio_m := _shader("res://scripts/shaders/roda.gdshader")
	raio_m.set_shader_parameter("tinta", cor)
	var sat := cor.s
	var lum := cor.get_luminance()
	if lum > 0.75 and sat < 0.12:          # branco: fosco
		raio_m.set_shader_parameter("metal", 0.0)
		raio_m.set_shader_parameter("aspereza", 0.62)
		raio_m.set_shader_parameter("brilho", 0.12)
	elif lum < 0.12:                        # preto fosco
		raio_m.set_shader_parameter("metal", 0.1)
		raio_m.set_shader_parameter("aspereza", 0.6)
		raio_m.set_shader_parameter("brilho", 0.15)
	elif sat < 0.12:                        # prata / grafite: liga metálica
		raio_m.set_shader_parameter("metal", 0.7)
		raio_m.set_shader_parameter("aspereza", 0.28)
		raio_m.set_shader_parameter("brilho", 0.6)
	else:                                   # cores (dourado, bronze, vermelho...): tinta metálica
		raio_m.set_shader_parameter("metal", 0.45)
		raio_m.set_shader_parameter("aspereza", 0.32)
		raio_m.set_shader_parameter("brilho", 0.4)
	var borda: ShaderMaterial
	if polida:
		borda = _shader("res://scripts/shaders/cromo.gdshader")
		borda.set_shader_parameter("tinta", Color(0.95, 0.95, 0.97))
		borda.set_shader_parameter("aspereza", 0.05)
	else:
		borda = raio_m
	var tambor := StandardMaterial3D.new()
	tambor.albedo_color = Color(0.35, 0.35, 0.37)
	tambor.metallic = 0.8
	tambor.roughness = 0.4
	for n in aro.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i)
			var nome := mat.resource_name if mat else ""
			if nome == "LIP" or nome == "BOLT":
				m.set_surface_override_material(i, borda)
			elif nome == "BARREL":
				m.set_surface_override_material(i, tambor)
			elif mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture:
				# raios desenhados em textura (BBS trançada): mesma tinta, com recorte e relevo
				var rm := raio_m.duplicate() as ShaderMaterial
				rm.set_shader_parameter("usa_mascara", true)
				rm.set_shader_parameter("mascara", (mat as BaseMaterial3D).albedo_texture)
				rm.set_shader_parameter("relevo", (mat as BaseMaterial3D).normal_texture)
				m.set_surface_override_material(i, rm)
			else:
				m.set_surface_override_material(i, raio_m)


## pneu em forma de anel (lado arredondado), eixo em X
static func _pneu(R: float, r_aro: float, w: float) -> ArrayMesh:
	var chave := "%.3f_%.3f_%.3f" % [R, r_aro, w]
	if _pneus.has(chave):
		return _pneus[chave]
	var perfil := [Vector2(r_aro - 0.01, -w / 2.0 + 0.01), Vector2(r_aro + 0.01, -w / 2.0), Vector2(R - 0.035, -w / 2.0 - 0.006),
		Vector2(R - 0.008, -w / 2.0 + 0.02), Vector2(R, -w / 2.0 + 0.05), Vector2(R, w / 2.0 - 0.05), Vector2(R - 0.008, w / 2.0 - 0.02),
		Vector2(R - 0.035, w / 2.0 + 0.006), Vector2(r_aro + 0.01, w / 2.0), Vector2(r_aro - 0.01, w / 2.0 - 0.01)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 40
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		for k in perfil.size() - 1:
			var p0: Vector2 = perfil[k]
			var p1: Vector2 = perfil[k + 1]
			var v00 := Vector3(p0.y, cos(a0) * p0.x, sin(a0) * p0.x)
			var v01 := Vector3(p0.y, cos(a1) * p0.x, sin(a1) * p0.x)
			var v10 := Vector3(p1.y, cos(a0) * p1.x, sin(a0) * p1.x)
			var v11 := Vector3(p1.y, cos(a1) * p1.x, sin(a1) * p1.x)
			for v in [v00, v10, v11, v00, v11, v01]:
				st.add_vertex(v)
	st.generate_normals()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("0e0e10")
	m.roughness = 0.95
	m.metallic_specular = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(m)
	var malha := st.commit()
	_pneus[chave] = malha
	return malha


static var _sombra_t: Texture2D
static func _sombra_tex() -> Texture2D:
	if _sombra_t:
		return _sombra_t
	# retângulo de cantos arredondados bem esfumaçado
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := absf((x + 0.5) / n * 2.0 - 1.0)
			var v := absf((y + 0.5) / n * 2.0 - 1.0)
			var dx := maxf(0.0, u - 0.55) / 0.45
			var dy := maxf(0.0, v - 0.62) / 0.38
			var dd := sqrt(dx * dx + dy * dy)
			var a := clampf(1.0 - dd, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	_sombra_t = ImageTexture.create_from_image(img)
	return _sombra_t


static var _brilho_tex: Texture2D
static func _brilho() -> Texture2D:
	if _brilho_tex:
		return _brilho_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.85))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 128
	t.height = 128
	_brilho_tex = t
	return t


# ---------------------------------------------------------------- som (caçamba / porta-malas)
func _som() -> void:
	if som_no:
		som_no.queue_free()
		som_no = null
	var s: String = c.get("som", "off")
	if s == "off":
		return
	som_no = Node3D.new()
	corpo.add_child(som_no)
	var W := float(d["W"])
	var bed = d.get("bed")
	if s == "tampao" and d.get("tampao", false):
		# caçamba fechada com os alto-falantes: o tampão da Saveiro esticado pro tamanho da caçamba de cada picape
		var tp: Node3D = load("res://modelos/carros/saveiro_som.glb").instantiate()
		var tm = d.get("tampa")
		if tm != null:
			var sz := (float(tm["z1"]) - float(tm["z0"])) / 1.2
			var sx := (W - 0.30) / 1.35
			tp.scale = Vector3(sx, 1.0, sz)
			tp.position = Vector3(0, float(tm["y"]) - 1.07, float(tm["z1"]) + 1.02 * sz)
		som_no.add_child(tp)
	elif s == "on" and bed != null:
		# paredão em pé, encostado na cabine, virado pra trás
		var x: Node3D = load("res://modelos/extras/paredao.glb").instantiate()
		var inner := Node3D.new()
		inner.add_child(x)
		x.position = Vector3(1.2, 0, 2.4)
		var rot := Node3D.new()
		rot.add_child(inner)
		var sc := (W - 0.36) / 9.62
		rot.scale = Vector3.ONE * sc
		rot.rotation.y = PI / 2.0
		rot.position = Vector3(0, float(bed["y"]) + 0.01, float(bed["z"]) + 0.5)
		som_no.add_child(rot)
	else:
		# caixa deitada (trio goiano na caçamba, ou no porta-malas)
		var x: Node3D = load("res://modelos/extras/caixa.glb").instantiate()
		var inner := Node3D.new()
		inner.add_child(x)
		x.position = Vector3(-2.773, -0.4, 1.312)
		inner.rotation.z = PI / 2.0
		var rot := Node3D.new()
		rot.add_child(inner)
		rot.rotation.y = PI
		if bed != null:
			var sc := (W - 0.42) / 3.0
			rot.scale = Vector3.ONE * sc
			rot.position = Vector3(0, float(bed["y"]) + 1.95 * sc / 2.0 + 0.01, float(bed["z"]))
		else:
			var g = d.get("som")
			if g == null:
				g = {"y": 0.85, "z": float(d["axR"]) - 0.3}
			var sc: float = min((W - 0.55) / 3.0, 0.5 / 1.95)
			rot.scale = Vector3.ONE * sc
			rot.position = Vector3(0, float(g["y"]), float(g["z"]))
			rot.rotation.x = -0.3
		som_no.add_child(rot)


# ---------------------------------------------------------------- lataria lisinha
static var _lisos := {}

## junta as normais de vértices no mesmo lugar: tira o aspecto de "triângulos" da lataria
func _suavizar(m: MeshInstance3D, s: int) -> void:
	var chave := str(m.mesh.get_rid().get_id()) + "_" + str(s)
	var malha: ArrayMesh
	if _lisos.has(chave):
		malha = _lisos[chave]
	else:
		var t0 := Time.get_ticks_msec()
		var arr := m.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if vs.is_empty() or vs.size() > 60000:
			return  # modelo detalhado já é liso: não mexe
		# normal de cada vértice = soma das faces em volta que olham pro mesmo lado (não mistura com a face de trás)
		var faces := {}
		var tri := idx if not idx.is_empty() else PackedInt32Array(range(vs.size()))
		for t in range(0, tri.size() - 2, 3):
			var a := vs[tri[t]]
			var b := vs[tri[t + 1]]
			var c2 := vs[tri[t + 2]]
			var fn := (b - a).cross(c2 - a)
			for k in 3:
				var p := vs[tri[t + k]]
				var key := Vector3i(roundi(p.x * 400.0), roundi(p.y * 400.0), roundi(p.z * 400.0))
				if not faces.has(key):
					faces[key] = PackedVector3Array()
				var lista: PackedVector3Array = faces[key]
				lista.append(fn)
				faces[key] = lista
		var tem_n := ns.size() == vs.size()
		var novas := PackedVector3Array()
		novas.resize(vs.size())
		for v in vs.size():
			var p := vs[v]
			var key := Vector3i(roundi(p.x * 400.0), roundi(p.y * 400.0), roundi(p.z * 400.0))
			var ref: Vector3 = ns[v] if tem_n else Vector3.ZERO
			var n := Vector3.ZERO
			var lista: PackedVector3Array = faces.get(key, PackedVector3Array())
			for fn in lista:
				var f: Vector3 = fn
				if tem_n:
					var al := f.normalized().dot(ref)
					if al < 0.0:
						f = -f
					if absf(al) < 0.35:
						continue  # quina viva (borda da janela, vinco): não arredonda
				n += f
			novas[v] = n.normalized() if n.length() > 1e-9 else (ref if tem_n else Vector3.UP)
		arr[Mesh.ARRAY_NORMAL] = novas
		arr[Mesh.ARRAY_TANGENT] = null
		malha = ArrayMesh.new()
		for j in m.mesh.get_surface_count():
			if j == s:
				malha.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			else:
				malha.add_surface_from_arrays(m.mesh.surface_get_primitive_type(j), m.mesh.surface_get_arrays(j))
			malha.surface_set_material(j, m.mesh.surface_get_material(j))
		_lisos[chave] = malha
		if OS.has_environment("DROPS_TEMPO"):
			print("suavizar ", d.get("id", "?"), " ", vs.size(), " vertices: ", Time.get_ticks_msec() - t0, " ms")
	m.mesh = malha
	m.set_surface_override_material(s, mat_pintura)


# ---------------------------------------------------------------- materiais (qualquer GLB)
## panorama que os carros refletem (a garagem usa o estúdio, a rua usa o fim de tarde)
static var reflexo: Texture2D
static var forca_reflexo := 1.0

static func usar_reflexo(arq: String, forca: float) -> void:
	reflexo = load(arq) if ResourceLoader.exists(arq) else null
	forca_reflexo = forca


const _CHAVES := [
	["pintura", ["paint", "carpaint", "car_paint", "body", "lataria", "carroceria", "karosserie", "exterior_color", "bodycolor"]],
	["vidro", ["glass", "window", "vidro", "janela", "windshield", "parabrisa", "windscreen"]],
	["lanterna", ["tail", "lanterna", "rear_light", "rearlight", "brake", "freio", "stop"]],
	["farol", ["luz", "headlight", "head_light", "farol", "lamp", "light", "pisca", "indicator", "blinker"]],
	["cromo", ["chrome", "cromo", "cromado", "mirror", "espelho", "polished"]],
	["pneu", ["tire", "tyre", "pneu", "rubber"]],
	["aro", ["rim", "wheel", "aro", "llanta", "felge", "roda"]],
	["interior", ["interior", "seat", "banco", "dash", "painel", "carpet", "couro", "leather"]],
]

## descobre o que é cada material: primeiro pela etiqueta do importador (PAINT, GLASS, TAIL, LUZ, CROMO, PNEU, ARO),
## depois por palavras no nome (inglês/português/espanhol) e por último pelas propriedades (transparente = vidro, metal liso = cromo)
static func classe_material(mat: Material, nome_no := "") -> String:
	var nome := (mat.resource_name if mat else "")
	var etiqueta := nome.get_slice("__", 0)
	match etiqueta:
		"PAINT": return "pintura"
		"GLASS", "LENS": return "vidro"
		"TAIL", "TAILGLASS": return "lanterna"
		"CROMO": return "cromo"
		"PNEU": return "pneu"
		"ARO": return "aro"
		"INTERIOR": return "interior"
	if etiqueta.begins_with("LUZ") or nome == "Gol_headlight":
		return "farol"
	var n := (nome + " " + nome_no).to_lower()
	if "steering" in n or "volante" in n:
		return "interior"
	for par in _CHAVES:
		# lataria só pelo nome do MATERIAL: peça chamada "Body" tem plástico preto, borracha, forro... que não pintam
		var onde := nome.to_lower() if par[0] == "pintura" else n
		for k in par[1]:
			if k in onde:
				return par[0]
	var sm := mat as BaseMaterial3D
	if sm:
		if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and sm.albedo_color.a < 0.9 and sm.albedo_texture == null:
			return "vidro"
		if sm.metallic > 0.85 and sm.roughness < 0.3:
			return "cromo"
	return "outro"


func _shader(arq: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(arq)
	m.set_shader_parameter("reflexo", reflexo)
	m.set_shader_parameter("forca_reflexo", forca_reflexo)
	return m


func _materiais(raiz: Node) -> void:
	mat_pintura.set_shader_parameter("reflexo", reflexo)
	mat_pintura.set_shader_parameter("forca_reflexo", forca_reflexo)
	var cache := {}   # o mesmo material original vira o mesmo material novo (menos troca de estado = mais leve)
	for n in raiz.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh == null:
			continue
		var escondidas := 0
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i)
			var cls := classe_material(mat, str(m.name))
			if cls == "pintura":
				m.set_surface_override_material(i, mat_pintura)
				if not (mat and "__liso" in mat.resource_name):
					_suavizar(m, i)   # modelo que não passou pelo importador: alisa aqui (perde o LOD da lataria)
				continue
			if cls == "pneu" or cls == "aro":
				# roda que veio grudada no modelo: some (as rodas do jogo entram no lugar)
				m.set_surface_override_material(i, _nada())
				escondidas += 1
				continue
			if cls == "interior" or cls == "outro":
				continue   # material original (texturas PBR do modelo) fica como veio
			var chave := [mat, cls]
			if not cache.has(chave):
				cache[chave] = _material_para(cls, mat)
			if cache[chave] != null:
				m.set_surface_override_material(i, cache[chave])
		if escondidas == m.mesh.get_surface_count():
			m.visible = false


func _material_para(cls: String, orig: Material) -> Material:
	var sm := orig as BaseMaterial3D
	match cls:
		"vidro":
			var v := _shader("res://scripts/shaders/vidro.gdshader")
			if sm and sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and sm.albedo_color.a < 0.95:
				var c := sm.albedo_color
				v.set_shader_parameter("tinta", Color(c.r, c.g, c.b) * 0.35)
				v.set_shader_parameter("opacidade", clampf(c.a, 0.4, 0.82))
			return v
		"cromo":
			var cr := _shader("res://scripts/shaders/cromo.gdshader")
			if sm:
				var c := sm.albedo_color
				cr.set_shader_parameter("tinta", Color(c.r, c.g, c.b).lerp(Color.WHITE, 0.25))
				cr.set_shader_parameter("aspereza", clampf(sm.roughness, 0.03, 0.35))
				if sm.albedo_texture:
					cr.set_shader_parameter("textura", sm.albedo_texture)
					cr.set_shader_parameter("usa_textura", true)
			return cr
		"farol", "lanterna":
			# mantém a textura original do farol/lanterna e acende por cima
			var l: StandardMaterial3D = sm.duplicate() if sm is StandardMaterial3D else StandardMaterial3D.new()
			var cor := Color(1.0, 0.97, 0.9) if cls == "farol" else Color(1.0, 0.08, 0.1)
			if sm == null or (sm.albedo_texture == null and cls == "lanterna"):
				l.albedo_color = Color(0.5, 0.02, 0.03) if cls == "lanterna" else Color(0.95, 0.95, 1.0)
			l.emission_enabled = true
			l.emission = cor
			if l.albedo_texture:
				l.emission_texture = l.albedo_texture
				l.emission_energy_multiplier = 0.9 if cls == "farol" else 1.3
			else:
				l.emission_energy_multiplier = 1.2 if cls == "farol" else 1.4
			l.roughness = minf(l.roughness, 0.15)
			return l
	return null


static var _nada_mat: ShaderMaterial
static func _nada() -> ShaderMaterial:
	if _nada_mat == null:
		_nada_mat = ShaderMaterial.new()
		var s := Shader.new()
		s.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nvoid fragment() { discard; }\n"
		_nada_mat.shader = s
	return _nada_mat
