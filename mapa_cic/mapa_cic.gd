extends Node3D
class_name MapaCIC
## Mapa da Cidade Industrial (Curitiba) gerado do OpenStreetMap.
## Carrega só os blocos perto do jogador (streaming) pra rodar liso no celular,
## coloca a Drops Garage no endereço real e cria colisão de postes e árvores.

@export var alvo: Node3D
@export var pasta := "res://mapa_cic/"
@export var raio_carregar := 600.0
@export var raio_descarregar := 800.0
@export var distancia_construcoes := 650.0
@export var distancia_arvores := 340.0
@export var distancia_postes := 230.0
@export var colocar_alvo_no_spawn := false
@export_group("Noite")
@export var luzes_dos_postes := true
@export var max_luzes := 8
@export var energia_luz := 2.2

var dados: Dictionary = {}
var drops_xf := Transform3D.IDENTITY     # frente do lote da Drops (fachada virada pra -Z local)
var drops: Node3D
var portao_e: Node3D
var portao_d: Node3D
var portao_aberto := 0.0                 # 0 fechado, 1 aberto
var portao_alvo := 0.0
var auto_portao := true
var _carregados := {}   # nome -> Node3D
var _pedidos := {}      # nome -> caminho
var _fila: Array = []   # trabalho de montar bloco, picado em pedaços (Callable) pra não travar o jogo
@export var sombras_cidade := false   # casas/árvores/postes sem sombra do sol (só o carro e as pessoas fazem sombra)
const ORCAMENTO_US := 3500
const ORCAMENTO_PERTO_US := 9000   # (v38) bloco perto do jogador ainda faltando: monta mais rápido
const MAX_PEDIDOS := 3             # (v38) quantos blocos lendo do disco ao mesmo tempo (os mais perto primeiro)
var _montando := ""                # bloco que está na fila sendo montado
var _vel := Vector3.ZERO           # velocidade do jogador (pra carregar antes o que vem pela frente)
var _p_ult := Vector3.INF
var _falta_perto := false
var _perf := OS.has_environment("DROPS_PERF")
var _perf_ult := 0
var _perf_max := 0             # tempo máximo por quadro montando blocos (3,5 ms)
var _t := 0.0
var _luzes: Array[OmniLight3D] = []
var _shader_chao: Shader
var _grao: Texture2D
var _detalhe: Texture2D        # asfalto (R), calçada de pedrinha (G) e grama (B) de perto
@export var distancia_sinalizacao := 170.0
@export var distancia_arvore_real := 70.0     # até aqui a árvore é o modelo 3D de verdade; depois vira a árvore leve
const ARVORES_REAIS := ["res://modelos/cenario/arvores/arvore_a.glb", "res://modelos/cenario/arvores/arvore_b.glb"]
@export var distancia_nomes := 55.0
# terreno real (curvas de nível do IPPUC): grade de alturas
var _alt := PackedFloat32Array()
var _t_nx := 0
var _t_nz := 0
var _t_x0 := 0.0
var _t_z0 := 0.0
var _t_res := 2.0


func _ready() -> void:
	var f := FileAccess.open(pasta + "mapa_cic.json", FileAccess.READ)
	if f == null:
		push_error("MapaCIC: não achei " + pasta + "mapa_cic.json")
		return
	dados = JSON.parse_string(f.get_as_text())
	_carregar_terreno()
	_shader_chao = _criar_shader()
	if ResourceLoader.exists(pasta + "blocos/tex/grao.png"):
		_grao = load(pasta + "blocos/tex/grao.png")
	if ResourceLoader.exists(pasta + "blocos/tex/detalhe.png"):
		_detalhe = load(pasta + "blocos/tex/detalhe.png")
	_criar_chao_e_bordas()
	_criar_drops()
	_variantes_arvore()   # monta as árvores 3D já no carregamento (antes travava na primeira vez)
	if luzes_dos_postes:
		for i in max_luzes:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.8, 0.55)
			l.light_energy = energia_luz
			l.omni_range = 17.0
			l.omni_attenuation = 1.3
			l.visible = false
			add_child(l)
			_luzes.append(l)
	if alvo and colocar_alvo_no_spawn:
		alvo.global_position = posicao_spawn()
	var t0 := Time.get_ticks_msec()
	_atualizar(true)
	if OS.has_environment("DROPS_TEMPO"):
		print("tempo blocos iniciais: ", Time.get_ticks_msec() - t0, " ms, ", _carregados.size(), " blocos")


# ------------------------------------------------------------------ terreno
func _carregar_terreno() -> void:
	if not dados.has("terreno"):
		return
	var t: Dictionary = dados["terreno"]
	var f := FileAccess.open(pasta + str(t["arquivo"]), FileAccess.READ)
	if f == null:
		push_warning("MapaCIC: sem terreno.bin (o chão fica plano)")
		return
	_t_nx = int(t["nx"])
	_t_nz = int(t["nz"])
	_t_x0 = float(t["x0"])
	_t_z0 = float(t["z0"])
	_t_res = float(t["res"])
	_alt = f.get_buffer(_t_nx * _t_nz * 4).to_float32_array()


## altura do chão (y) em x,z
func altura(x: float, z: float) -> float:
	if _alt.is_empty():
		return 0.0
	var fx := clampf((x - _t_x0) / _t_res, 0.0, _t_nx - 1.001)
	var fz := clampf((z - _t_z0) / _t_res, 0.0, _t_nz - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * _t_nx + ix
	var a := lerpf(_alt[i], _alt[i + 1], tx)
	var b := lerpf(_alt[i + _t_nx], _alt[i + _t_nx + 1], tx)
	return lerpf(a, b, tz)


func no_chao(p: Vector3, acima := 0.0) -> Vector3:
	return Vector3(p.x, altura(p.x, p.z) + acima, p.z)


# ------------------------------------------------------------------ pontos do mapa
func posicao_spawn() -> Vector3:
	var sp: Dictionary = dados["spawn"]
	return Vector3(sp["pos"][0], sp["pos"][1], sp["pos"][2])


func tem(chave: String) -> bool:
	return dados.has(chave)


## transforma uma posição dada no JSON (pos + yaw) num Transform3D
func xf(chave: String) -> Transform3D:
	var d: Dictionary = dados[chave]
	return Transform3D(Basis(Vector3.UP, float(d["yaw"])), Vector3(d["pos"][0], d["pos"][1], d["pos"][2]))


# ------------------------------------------------------------------ streaming
func _process(delta: float) -> void:
	if dados.is_empty():
		return
	var feitos := 0
	var t0 := Time.get_ticks_usec()
	if _perf:
		_perf_max = maxi(_perf_max, _perf_ult)
	var pa := _pos_alvo()
	if _p_ult != Vector3.INF and delta > 0.0:
		var v := (pa - _p_ult) / delta
		if v.length() < 120.0:   # teleporte não conta
			_vel = _vel.lerp(Vector3(v.x, 0, v.z), clampf(delta * 2.0, 0.0, 1.0))
	_p_ult = pa
	var orc := ORCAMENTO_PERTO_US if _falta_perto else ORCAMENTO_US
	while not _fila.is_empty() and Time.get_ticks_usec() - t0 < orc:
		(_fila.pop_front() as Callable).call()
	if _fila.is_empty():
		_montando = ""
	# o bloco já lido mais perto do jogador é o próximo a montar (um por vez)
	var melhor := ""
	var dm := INF
	for nome in _pedidos.keys():
		var caminho: String = _pedidos[nome]
		var st := ResourceLoader.load_threaded_get_status(caminho)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			var d := _dist_bloco(nome, pa)
			if d < dm:
				dm = d
				melhor = nome
		elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_warning("MapaCIC: falhou " + caminho)
			_pedidos.erase(nome)
	if melhor != "" and _fila.is_empty() and feitos == 0:
		_instanciar(melhor, ResourceLoader.load_threaded_get(_pedidos[melhor]), true)
		_pedidos.erase(melhor)
		_montando = melhor
		_pedir()
	if _perf:
		_perf_ult = Time.get_ticks_usec() - t0
	_portao(delta)
	_t += delta
	if _t > 0.25:
		_t = 0.0
		_atualizar(false)
		_atualizar_luzes()


func _pos_alvo() -> Vector3:
	return alvo.global_position if is_instance_valid(alvo) else posicao_spawn()


## distância do jogador até o bloco, olhando um pouco pra frente (pra onde ele está indo)
func _dist_bloco(nome: String, p: Vector3) -> float:
	var c: Array = dados["blocos"][nome]["centro"]
	var frente := p + _vel.limit_length(45.0) * 4.0   # até ~180 m à frente
	return minf(Vector2(p.x - c[0], p.z - c[1]).length(), Vector2(frente.x - c[0], frente.z - c[1]).length() + 40.0)


var _faltando: Array = []   # blocos dentro do raio que ainda não foram pedidos, do mais perto pro mais longe

## pede pro disco os blocos que faltam, os mais perto primeiro, poucos de cada vez
func _pedir() -> void:
	var lendo := 0
	for nome in _pedidos:
		if ResourceLoader.load_threaded_get_status(_pedidos[nome]) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			lendo += 1
	while lendo < MAX_PEDIDOS and not _faltando.is_empty():
		var nome: String = _faltando.pop_front()
		if _carregados.has(nome) or _pedidos.has(nome):
			continue
		var caminho: String = pasta + "blocos/" + nome + ".glb"
		ResourceLoader.load_threaded_request(caminho)
		_pedidos[nome] = caminho
		lendo += 1


func _atualizar(inicio: bool) -> void:
	var p := _pos_alvo()
	var blocos: Dictionary = dados["blocos"]
	var falta := []
	_falta_perto = false
	for nome in blocos:
		var b: Dictionary = blocos[nome]
		var d := Vector2(p.x - b["centro"][0], p.z - b["centro"][1]).length()
		var dp := _dist_bloco(nome, p)
		if minf(d, dp) < raio_carregar and not _carregados.has(nome):
			var caminho: String = pasta + "blocos/" + nome + ".glb"
			if inicio and d < 260.0:
				_instanciar(nome, load(caminho))   # (v38) só o bloco onde nasce e os colados nele: o resto vem logo depois, do mais perto pro mais longe
				continue
			if d < 260.0:
				_falta_perto = true   # o jogador já está chegando nele
			if not _pedidos.has(nome):
				falta.append([dp, nome])
		elif nome == _montando and d < 260.0:
			_falta_perto = true
		if d > raio_descarregar and _carregados.has(nome) and nome != _montando:
			var velho: Node = _carregados[nome]
			if velho.is_inside_tree():
				velho.queue_free()
			else:
				velho.free()
			_carregados.erase(nome)
	falta.sort_custom(func(x, y): return x[0] < y[0])
	_faltando = []
	for f in falta:
		_faltando.append(f[1])
	_pedir()


## espera os blocos em volta de um ponto ficarem prontos (teleporte)
func carregar_perto(p: Vector3) -> void:
	while not _fila.is_empty():
		(_fila.pop_front() as Callable).call()
	_montando = ""
	_p_ult = Vector3.INF
	_vel = Vector3.ZERO
	var blocos: Dictionary = dados["blocos"]
	for nome in blocos:
		var b: Dictionary = blocos[nome]
		var d := Vector2(p.x - b["centro"][0], p.z - b["centro"][1]).length()
		if d < 320.0 and not _carregados.has(nome):
			_instanciar(nome, load(pasta + "blocos/" + nome + ".glb"))
			_pedidos.erase(nome)


func _instanciar(nome: String, cena: PackedScene, aos_poucos := false) -> void:
	if cena == null or _carregados.has(nome):
		return
	var no: Node3D = cena.instantiate()
	no.name = nome
	_carregados[nome] = no
	var b: Dictionary = dados["blocos"][nome]
	if not aos_poucos:
		add_child(no)
		_preparar(no)
		_obstaculos(no, b.get("obst", []))
		_placas_nomes(no, b.get("nomes", []))
		_arvores_reais(no, b.get("arvores", []))
		return
	# longe do jogador: monta em pedaços, um pouco por quadro, e só aparece quando estiver pronto
	no.visible = false
	_fila.append(func(): if is_instance_valid(no): add_child(no))
	_fila.append(func(): if is_instance_valid(no): _preparar(no))
	var obst: Array = b.get("obst", [])
	for k in range(0, obst.size(), 80):
		var parte := obst.slice(k, k + 80)
		_fila.append(func(): if is_instance_valid(no): _obstaculos(no, parte))
	_fila.append(func(): if is_instance_valid(no): _placas_nomes(no, b.get("nomes", [])))
	var arv: Array = b.get("arvores", [])
	for k in range(0, arv.size(), 150):
		var parte2 := arv.slice(k, k + 150)
		_fila.append(func(): if is_instance_valid(no): _arvores_reais(no, parte2))
	_fila.append(func(): if is_instance_valid(no): no.visible = true)


func _preparar(no: Node) -> void:
	for filho in no.find_children("*", "MeshInstance3D", true, false):
		var mi := filho as MeshInstance3D
		var n := String(mi.name)
		if not sombras_cidade:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if n.begins_with("ArvoresC"):
			# árvore leve (cards): só de longe — de perto quem aparece é a árvore 3D da mesma célula
			mi.visibility_range_begin = distancia_arvore_real if not _variantes_arvore().is_empty() else 0.0
			mi.visibility_range_begin_margin = 8.0
			mi.visibility_range_end = distancia_arvores
			mi.visibility_range_end_margin = 20.0
		elif n.begins_with("Arvores"):
			mi.visibility_range_end = distancia_arvores
			mi.visibility_range_end_margin = 20.0
		elif n.begins_with("Postes"):
			mi.visibility_range_end = distancia_postes
			mi.visibility_range_end_margin = 20.0
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif n.begins_with("Construcoes"):
			mi.visibility_range_end = distancia_construcoes
		elif n.begins_with("Chao"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif n.begins_with("Sinalizacao"):
			mi.visibility_range_end = distancia_sinalizacao
			mi.visibility_range_end_margin = 20.0
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if m == null:
				continue
			if n.begins_with("Chao"):
				# chão: textura do bloco + grão fino de perto (asfalto/calçada não ficam borrados)
				var sm := ShaderMaterial.new()
				sm.shader = _shader_chao
				sm.set_shader_parameter("mapa", m.albedo_texture)
				if _grao:
					sm.set_shader_parameter("grao", _grao)
				if _detalhe:
					sm.set_shader_parameter("detalhe", _detalhe)
				if tem("drops_garage"):
					sm.set_shader_parameter("furo_a", Projection(xf("drops_garage").affine_inverse()))
					sm.set_shader_parameter("lim_a", Vector4(-5.15, 0.3, 4.55, 28.45))   # oficina (piso de epóxi/concreto)
				if tem("barracao"):
					sm.set_shader_parameter("furo_b", Projection(xf("barracao").affine_inverse()))
					sm.set_shader_parameter("lim_b", Vector4(-7.9, -29.9, 7.9, -0.1))
				mi.set_surface_override_material(i, sm)
			else:
				m.vertex_color_use_as_albedo = true
				if n.begins_with("Arvores") and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					m.albedo_color = Color(0.72, 0.8, 0.66)   # árvore leve de longe: menos verde-limão, igual às 3D


func _obstaculos(no: Node, lista: Array) -> void:
	if lista.is_empty():
		return
	var corpo := StaticBody3D.new()
	corpo.name = "Obstaculos"
	for o in lista:
		var cs := CollisionShape3D.new()
		var cil := CylinderShape3D.new()
		cil.radius = float(o[2])
		cil.height = 5.0
		cs.shape = cil
		var yb: float = float(o[3]) if o.size() > 3 else 0.0
		cs.position = Vector3(o[0], yb + 2.5, o[1])
		corpo.add_child(cs)
	no.add_child(corpo)


## árvores 3D de verdade (do pacote "Realistic Trees"): cada arquivo tem 2 árvores lado a lado -> 4 variações
static var _variantes: Array = []
static var _variantes_feitas := false
static func _variantes_arvore() -> Array:
	if _variantes_feitas:
		return _variantes
	_variantes_feitas = true
	for arq in ARVORES_REAIS:
		if not ResourceLoader.exists(arq):
			continue
		var cena: Node3D = load(arq).instantiate()
		var partes := [{}, {}]      # por lado: material -> [verts, normais, uvs, índices]
		for mi in cena.find_children("*", "MeshInstance3D", true, false):
			var t: Transform3D = Acessorios._ate(mi, cena)
			for s in mi.mesh.get_surface_count():
				var arr: Array = mi.mesh.surface_get_arrays(s)
				var mat: Material = mi.mesh.surface_get_material(s)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				for k in range(0, idx.size(), 3):
					var a := t * vs[idx[k]]
					var b := t * vs[idx[k + 1]]
					var c := t * vs[idx[k + 2]]
					var lado := 0 if (a.x + b.x + c.x) < 0.0 else 1
					if not partes[lado].has(mat):
						partes[lado][mat] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array()]
					var dst: Array = partes[lado][mat]
					for q in [idx[k], idx[k + 1], idx[k + 2]]:
						dst[0].append(t * vs[q])
						dst[1].append((t.basis * ns[q]).normalized() if ns.size() > q else Vector3.UP)
						dst[2].append(uv[q] if uv.size() > q else Vector2.ZERO)
		cena.free()
		for lado in 2:
			if partes[lado].is_empty():
				continue
			# centraliza no tronco (média dos vértices de baixo)
			var cx := 0.0
			var cz := 0.0
			var nb := 0
			var ymin := INF
			for mat in partes[lado]:
				for v in (partes[lado][mat][0] as PackedVector3Array):
					ymin = minf(ymin, v.y)
			for mat in partes[lado]:
				for v in (partes[lado][mat][0] as PackedVector3Array):
					if v.y < ymin + 0.6:
						cx += v.x
						cz += v.z
						nb += 1
			var centro := Vector3(cx / maxf(nb, 1), ymin, cz / maxf(nb, 1))
			var am := ArrayMesh.new()
			for mat in partes[lado]:
				var d: Array = partes[lado][mat]
				var vs2: PackedVector3Array = d[0]
				for i in vs2.size():
					vs2[i] -= centro
				var arrs := []
				arrs.resize(Mesh.ARRAY_MAX)
				arrs[Mesh.ARRAY_VERTEX] = vs2
				arrs[Mesh.ARRAY_NORMAL] = d[1]
				arrs[Mesh.ARRAY_TEX_UV] = d[2]
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
				var m2: Material = mat
				if mat is BaseMaterial3D:
					# sem normal map (a malha remontada não tem tangentes -> ficava preta) e sem brilho
					var sm := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
					sm.normal_enabled = false
					sm.specular = 0.15
					sm.roughness = 0.95
					if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
						sm.albedo_color = Color(0.95, 0.97, 0.93)   # folhas (textura já corrigida pro verde)
						sm.alpha_scissor_threshold = 0.32          # copa mais cheia de longe (o mipmap afina as folhas)
					m2 = sm
				am.surface_set_material(am.get_surface_count() - 1, m2)
			_variantes.append(am)
	return _variantes


## põe as árvores 3D nas células do bloco (uma MultiMesh por célula e variação = poucas chamadas de desenho)
func _arvores_reais(no: Node, lista: Array) -> void:
	var vars := _variantes_arvore()
	if lista.is_empty() or vars.is_empty():
		return
	var grupos := {}
	for q in lista:
		if drops != null:   # nenhuma árvore dentro/encostada na Drops (a copa furava o telhado da oficina)
			var dl := drops_local(Vector3(float(q[0]), float(q[1]), float(q[2])))
			if dl.x > -7.5 and dl.x < 7.5 and dl.z > -3.0 and dl.z < 33.0:
				continue
		var v := int(absf(float(q[0]) * 7.31 + float(q[2]) * 3.17)) % vars.size()
		var chave := "%d_%d_%d" % [int(q[4]), int(q[5]), v]
		if not grupos.has(chave):
			grupos[chave] = [v, []]
		(grupos[chave][1] as Array).append(q)
	var raiz := Node3D.new()
	raiz.name = "ArvoresReais"
	no.add_child(raiz)
	for chave in grupos:
		var v: int = grupos[chave][0]
		var itens: Array = grupos[chave][1]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = vars[v]
		mm.instance_count = itens.size()
		for i in itens.size():
			var q: Array = itens[i]
			var s := float(q[3]) * (0.95 + fmod(absf(float(q[0]) * 13.7), 0.3))
			var yaw := fmod(float(q[2]) * 1.91, TAU)
			var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s)
			mm.set_instance_transform(i, Transform3D(b, Vector3(float(q[0]), float(q[1]) - 0.05, float(q[2]))))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = distancia_arvore_real
		mmi.visibility_range_end_margin = 8.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sombras_cidade else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		raiz.add_child(mmi)


## postes com placa azul de nome de rua (padrão de Curitiba), em cima da placa de PARE
static var _placa_malha: BoxMesh
static var _placa_mat: StandardMaterial3D
func _placas_nomes(no: Node, lista: Array) -> void:
	if lista.is_empty():
		return
	if _placa_malha == null:
		_placa_malha = BoxMesh.new()
		_placa_malha.size = Vector3(0.95, 0.24, 0.025)
		_placa_mat = StandardMaterial3D.new()
		_placa_mat.albedo_color = Color("14408f")
		_placa_mat.roughness = 0.4
	var raiz := Node3D.new()
	raiz.name = "NomesDeRua"
	no.add_child(raiz)
	for q in lista:
		var base := Vector3(float(q[0]), float(q[1]), float(q[2]))
		for k in 2:
			var yaw: float = float(q[3 + k * 2]) + PI / 2.0
			var nome: String = _abreviar(str(q[4 + k * 2]))
			var pl := Node3D.new()
			raiz.add_child(pl)
			pl.position = base + Vector3(0, 2.72 - k * 0.27, 0)
			pl.rotation.y = yaw
			var m := MeshInstance3D.new()
			m.mesh = _placa_malha
			m.material_override = _placa_mat
			m.position.x = 0.42
			m.visibility_range_end = distancia_nomes + 15.0
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pl.add_child(m)
			for lado in [1.0, -1.0]:
				var t := Label3D.new()
				t.text = nome
				t.font_size = 40 if nome.length() <= 22 else maxi(22, int(40.0 * 22.0 / nome.length()))
				t.pixel_size = 0.0028
				t.outline_size = 0
				t.modulate = Color.WHITE
				t.double_sided = false
				t.width = 320.0
				t.autowrap_mode = TextServer.AUTOWRAP_OFF
				t.position = Vector3(0.42, 0, 0.014 * lado)
				if lado < 0:
					t.rotation.y = PI
				t.visibility_range_end = distancia_nomes
				pl.add_child(t)


## "Rua Engenheiro Luiz Gastão Mendes Lima" -> "R. ENG. LUIZ GASTÃO MENDES LIMA" (cabe na plaquinha)
static func _abreviar(n: String) -> String:
	var t := " " + n + " "
	for par in [["Rua ", "R. "], ["Avenida ", "AV. "], ["Travessa ", "TV. "], ["Engenheiro ", "ENG. "], ["Doutor ", "DR. "],
			["Professor ", "PROF. "], ["Professora ", "PROFA. "], ["General ", "GAL. "], ["Coronel ", "CEL. "], ["Capitão ", "CAP. "],
			["Padre ", "PE. "], ["Senador ", "SEN. "], ["Deputado ", "DEP. "], ["Presidente ", "PRES. "], ["Marechal ", "MAL. "]]:
		t = t.replace(" " + par[0], " " + par[1])
	return t.strip_edges().to_upper()


func _criar_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode cull_back;
uniform sampler2D mapa : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D grao : filter_linear_mipmap, repeat_enable;
uniform sampler2D detalhe : filter_linear_mipmap_anisotropic, repeat_enable;
// (v35) dentro da Drops e do barracão o chão do bloco some (o piso de lá fica 2-3 cm acima e brigava com ele)
uniform mat4 furo_a = mat4(0.0);
uniform vec4 lim_a = vec4(0.0);
uniform mat4 furo_b = mat4(0.0);
uniform vec4 lim_b = vec4(0.0);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
bool no_furo(mat4 f, vec4 l) {
	vec3 q = (f * vec4(wpos, 1.0)).xyz;
	return l.z > l.x && q.x > l.x && q.x < l.z && q.z > l.y && q.z < l.w;
}
void fragment() {
	if (no_furo(furo_a, lim_a) || no_furo(furo_b, lim_b)) discard;
	vec3 c = texture(mapa, UV).rgb;
	// o que é cada pedaço do chão, pela cor da textura do bloco
	vec3 s = pow(c, vec3(1.0 / 2.2));
	float lum = dot(s, vec3(0.299, 0.587, 0.114));
	float sat = max(s.r, max(s.g, s.b)) - min(s.r, min(s.g, s.b));
	float cinza = 1.0 - smoothstep(0.035, 0.085, sat);
	float m_asf = cinza * (1.0 - smoothstep(0.30, 0.42, lum));
	float m_cal = cinza * smoothstep(0.45, 0.58, lum);
	float m_gra = smoothstep(0.015, 0.06, s.g - max(s.r, s.b));
	float dist = length(VERTEX);
	float perto = 1.0 - smoothstep(25.0, 90.0, dist);
	float medio = 1.0 - smoothstep(60.0, 220.0, dist);
	vec3 d1 = texture(detalhe, wpos.xz * 0.45).rgb;           // a cada ~2,2 m
	vec3 d2 = texture(detalhe, wpos.xz * 0.11 + vec2(0.41, 0.13)).rgb;
	float asf = mix(0.62 + d1.r * 0.76, 1.0, 0.25) * mix(0.9, 1.1, d2.r);
	float cal = 0.7 + texture(detalhe, wpos.xz * 1.1).g * 0.6;
	float gra = 0.66 + d1.b * 0.7;
	float k = 1.0;
	k = mix(k, asf, m_asf * medio);
	k = mix(k, cal, m_cal * perto);
	k = mix(k, gra, m_gra * medio);
	float g1 = texture(grao, wpos.xz * 0.55).r;
	float g2 = texture(grao, wpos.xz * 0.11 + vec2(0.37, 0.71)).r;
	c *= mix(1.0, mix(0.86, 1.1, g1), perto * (1.0 - m_asf)) * mix(0.95, 1.04, g2) * k;
	ALBEDO = c;
	ROUGHNESS = mix(0.93, 0.8, m_asf);
	SPECULAR = mix(0.25, 0.35, m_asf);
}
"""
	return s


func _atualizar_luzes() -> void:
	if _luzes.is_empty():
		return
	var p := _pos_alvo()
	var perto: Array = []
	for nome in _carregados:
		for l in dados["blocos"][nome]["luzes"]:
			var v := Vector3(l[0], l[1], l[2])
			var d := v.distance_squared_to(p)
			if d < 130.0 * 130.0:
				perto.append([d, v])
	perto.sort_custom(func(a, b): return a[0] < b[0])
	for i in _luzes.size():
		if i < perto.size():
			_luzes[i].global_position = perto[i][1]
			_luzes[i].visible = true
		else:
			_luzes[i].visible = false


# ------------------------------------------------------------------ Drops Garage (fachada real)
func _criar_drops() -> void:
	if not dados.has("drops_garage") or not ResourceLoader.exists(pasta + "blocos/drops_garage.glb"):
		return
	drops_xf = xf("drops_garage")
	drops = load(pasta + "blocos/drops_garage.glb").instantiate()
	drops.name = "DropsGarage"
	add_child(drops)
	drops.global_transform = drops_xf
	for mi in drops.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i) as StandardMaterial3D
			if mat:
				mat.vertex_color_use_as_albedo = true
	portao_e = drops.find_child("PortaoEsquerdo", true, false) as Node3D
	portao_d = drops.find_child("PortaoDireito", true, false) as Node3D
	# luzes da oficina (tubos brancos), da cabine e do corredor
	for lz in [[Vector3(1.6, 2.9, 16.8), 1.8, 9.0, Color(0.92, 0.97, 1.0)], [Vector3(3.6, 2.9, 20.5), 1.5, 8.0, Color(0.92, 0.97, 1.0)],
			[Vector3(-3.4, 2.5, 18.0), 1.4, 7.0, Color(1, 1, 1)], [Vector3(2.0, 2.6, 8.0), 0.9, 8.0, Color(1.0, 0.9, 0.75)],
			[Vector3(0.5, 2.9, 25.8), 1.5, 8.5, Color(0.92, 0.97, 1.0)]]:   # fundo novo da oficina
		var l := OmniLight3D.new()
		l.position = lz[0]
		l.light_energy = lz[1]
		l.omni_range = lz[2]
		l.light_color = lz[3]
		l.shadow_enabled = false
		drops.add_child(l)


## ponto local da Drops (x pra esquerda de quem olha da rua, z pra dentro do lote) -> mundo
func drops_ponto(local: Vector3) -> Vector3:
	return drops_xf * local


func drops_local(mundo: Vector3) -> Vector3:
	return drops_xf.affine_inverse() * mundo


func abrir_portao(abrir: bool) -> void:
	portao_alvo = 1.0 if abrir else 0.0


func _portao(dt: float) -> void:
	if portao_e == null:
		return
	if auto_portao and is_instance_valid(alvo):
		var lp := drops_local(alvo.global_position)
		var perto := Vector2(lp.x - 2.3, lp.z + 1.0).length() < 13.0
		portao_alvo = 1.0 if perto else 0.0
	portao_aberto = move_toward(portao_aberto, portao_alvo, dt * 0.8)
	var a := smoothstep(0.0, 1.0, portao_aberto) * deg_to_rad(96.0)
	portao_e.rotation.y = a
	portao_d.rotation.y = -a


# ------------------------------------------------------------------ chão e bordas
func _criar_chao_e_bordas() -> void:
	# o chão de verdade é a malha de cada bloco (com morro); este aqui é só uma rede de segurança lá embaixo
	var chao := StaticBody3D.new()
	chao.name = "ChaoFisico"
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	chao.add_child(cs)
	chao.position.y = -25.0 if not _alt.is_empty() else 0.0
	add_child(chao)
	var lim: Array = dados["limites"]
	var x0: float = lim[0]
	var z0: float = lim[1]
	var x1: float = lim[2]
	var z1: float = lim[3]
	var cx := (x0 + x1) / 2.0
	var cz := (z0 + z1) / 2.0
	var lx := x1 - x0
	var lz := z1 - z0
	for w in [[Vector3(cx, 50, z0 - 1), Vector3(lx + 4, 200, 2)], [Vector3(cx, 50, z1 + 1), Vector3(lx + 4, 200, 2)],
			[Vector3(x0 - 1, 50, cz), Vector3(2, 200, lz + 4)], [Vector3(x1 + 1, 50, cz), Vector3(2, 200, lz + 4)]]:
		var sb := StaticBody3D.new()
		var c := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = w[1]
		c.shape = bx
		sb.add_child(c)
		sb.position = w[0]
		add_child(sb)
