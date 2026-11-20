class_name Pessoa
extends CharacterBody3D
## O mecânico andando a pé: anda, corre, sobe calçada e dança (dança do Thuess copiada pro esqueleto dele).

const ANDA := 1.75   # m/s (v38: perna acompanha o chão, sem patinar)
const CORRE := 4.4
const PASSO_ANDA := 1.35   # velocidade em que a animação de andar pisa certinho (medido no mecânico, 1,75 m)
const PASSO_CORRE := 3.3

## quem dá pra escolher pra andar a pé (modelo com esqueleto do Mixamo: ganha as animações do mecânico)
const PERSONAGENS := [
	{"id": "voce", "nome": "Você (dono da Drops)", "arq": "res://modelos/personagens/voce.glb", "altura": 1.70},
	{"id": "mecanico", "nome": "Mecânico", "arq": "res://modelos/personagens/mecanico.glb", "altura": 1.72},
	{"id": "jack", "nome": "Jack", "arq": "res://modelos/personagens/jack.glb", "altura": 1.80},
	{"id": "steve", "nome": "Steve", "arq": "res://modelos/personagens/steve.glb", "altura": 1.78},
	{"id": "henry", "nome": "Henry", "arq": "res://modelos/personagens/henry.glb", "altura": 1.80},
]
const BASE_ANIM := "res://modelos/personagens/mecanico.glb"
const DANCA := "res://modelos/personagens/dancarino.glb"

var modelo: Node3D
# v32: andar liso — o boneco (e a câmera) ficam entre dois passos da física
var _p_ant := Vector3.ZERO
var _p_cur := Vector3.ZERO
var _tem_p := false
var _base_modelo := Vector3.ZERO
var pos_lisa := Vector3.ZERO
var anim: AnimationPlayer
var atual := ""
var dancando := false
var desejo := Vector3.ZERO      # direção pedida (já no mundo), tamanho 0..1
var correndo := false
var gravidade := 18.0


func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.85
	add_child(col)
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50)
	var ficha := Pessoa.ficha(OS.get_environment("DROPS_PERSONAGEM") if OS.has_environment("DROPS_PERSONAGEM") else Dados.personagem)
	modelo = Pessoa.criar(str(ficha["arq"]), float(ficha.get("altura", 1.72)))
	add_child(modelo)
	_base_modelo = modelo.position
	anim = modelo.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		var esq := modelo.find_child("Skeleton3D", true, false) as Skeleton3D
		if esq and not anim.has_animation("drops/danca"):
			var arq := str(ficha["arq"])
			if not _cache_danca.has(arq):
				_cache_danca[arq] = _animacoes_para(esq, anim, DANCA, [["danca", ""]])
			if _cache_danca[arq].has_animation("danca"):
				anim.get_animation_library("drops").add_animation("danca", _cache_danca[arq].get_animation("danca"))
		_tocar("parado")


## celular na mão direita (aparece quando abre o app da suspensão a pé)
var _celular: Node3D
func segurar_celular(sim: bool) -> void:
	if _celular == null:
		if not sim or modelo == null:
			return
		var esq := modelo.find_child("Skeleton3D", true, false) as Skeleton3D
		if esq == null:
			return
		var osso := -1
		for i in esq.get_bone_count():
			if _chave_osso(esq.get_bone_name(i)) == _chave_osso("RightHand"):
				osso = i
		if osso < 0:
			return
		var ba := BoneAttachment3D.new()
		ba.bone_idx = osso
		esq.add_child(ba)
		_celular = Node3D.new()
		ba.add_child(_celular)
		var corpo := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.075, 0.155, 0.009)
		corpo.mesh = bm
		var preto := StandardMaterial3D.new()
		preto.albedo_color = Color("0b0b0d")
		preto.roughness = 0.25
		preto.metallic = 0.4
		corpo.material_override = preto
		_celular.add_child(corpo)
		var tela := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.066, 0.14)
		tela.mesh = qm
		var tm := StandardMaterial3D.new()
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.albedo_color = Color("ffd400")
		tela.material_override = tm
		tela.position.z = 0.0052
		_celular.add_child(tela)
		# o osso vem com a escala do esqueleto: desfaz pra o celular ter o tamanho de verdade
		(func():
			var sc := ba.global_transform.basis.get_scale()
			if sc.x > 0.0001:
				_celular.scale = Vector3.ONE / sc
			_celular.position = Vector3(0, 0.09, 0.03) / maxf(sc.x, 0.0001)).call_deferred()
	_celular.visible = sim


static func ficha(id: String) -> Dictionary:
	for p in PERSONAGENS:
		if p["id"] == id and ResourceLoader.exists(p["arq"]):
			return p
	return PERSONAGENS[0]


## monta um personagem pronto: na altura certa, pé no chão e com as animações "drops/parado", "drops/anda", "drops/corre"
static var _cache_anims := {}
static func criar(arq: String, altura := 1.75) -> Node3D:
	var mod: Node3D = load(arq).instantiate()
	var caixa := _caixa(mod)
	if caixa.size.y > 0.01:
		var k := altura / caixa.size.y
		mod.scale = Vector3.ONE * k
		mod.position.y = -caixa.position.y * k
	var ap := mod.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		ap = AnimationPlayer.new()
		ap.name = "AnimationPlayer"
		mod.add_child(ap)
	var esq := mod.find_child("Skeleton3D", true, false) as Skeleton3D
	if esq == null:
		return mod
	if not _cache_anims.has(arq):
		_cache_anims[arq] = _animacoes_para(esq, ap)
	if not ap.has_animation_library("drops"):
		ap.add_animation_library("drops", _cache_anims[arq])
	return mod


## personagem dançando (festinha/encontro): a dança do dançarino passada pro esqueleto dele, já tocando
static var _cache_danca := {}
static func criar_dancando(arq: String, altura := 1.75) -> Node3D:
	var mod: Node3D = load(arq).instantiate()
	var caixa := _caixa(mod)
	if caixa.size.y > 0.01:
		var k := altura / caixa.size.y
		mod.scale = Vector3.ONE * k
		mod.position.y = -caixa.position.y * k
	var ap := mod.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		ap = AnimationPlayer.new()
		ap.name = "AnimationPlayer"
		mod.add_child(ap)
	var esq := mod.find_child("Skeleton3D", true, false) as Skeleton3D
	if esq == null:
		return mod
	if not _cache_danca.has(arq):
		_cache_danca[arq] = _animacoes_para(esq, ap, DANCA, [["danca", ""]])
	if not ap.has_animation_library("drops"):
		ap.add_animation_library("drops", _cache_danca[arq])
	if ap.has_animation("drops/danca"):
		ap.play("drops/danca")
	return mod


## só os giros (a dança não pode arrastar o boneco nem mexer no tamanho dos ossos)
static func _so_giros(a: Animation) -> Animation:
	for t in range(a.get_track_count() - 1, -1, -1):
		var tp := a.track_get_type(t)
		if tp == Animation.TYPE_SCALE_3D or (tp == Animation.TYPE_POSITION_3D and not str(a.track_get_path(t)).contains("Hips")):
			a.remove_track(t)
	return a


## copia andar/correr/parado do mecânico pro esqueleto de outro personagem (mesmos nomes de osso do Mixamo),
## corrigindo a diferença de pose de descanso de cada osso
static func _animacoes_para(esq: Skeleton3D, ap: AnimationPlayer, arq_fonte := BASE_ANIM, pares := [["parado", "Fa"], ["anda", "andar"], ["corre", "run"]]) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	var fonte: Node3D = load(arq_fonte).instantiate()
	var fap := fonte.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var fesq := fonte.find_child("Skeleton3D", true, false) as Skeleton3D
	if fap == null or fesq == null:
		fonte.free()
		return lib
	var raiz := ap.get_node(ap.root_node)
	var caminho_esq := str(raiz.get_path_to(esq))
	var mesmo := fesq.get_bone_count() == esq.get_bone_count() and fesq.get_bone_name(0) == esq.get_bone_name(0)
	# osso do alvo <- osso da fonte (nomes do Mixamo)
	var por_chave := {}
	for i in fesq.get_bone_count():
		por_chave[_chave_osso(fesq.get_bone_name(i))] = i
	var mapa := {}   # alvo -> fonte
	for i in esq.get_bone_count():
		var k := _chave_osso(esq.get_bone_name(i))
		if por_chave.has(k):
			mapa[i] = por_chave[k]
	var s_rot := _giro_ate(fesq, fonte)
	var t_rot := _giro_ate(esq, esq.owner if esq.owner else esq.get_parent())
	var gs_rest := _globais(fesq, s_rot, {})
	var gt_rest := _globais(esq, t_rot, {})
	# poses de descanso diferentes (T x A): alinha a direção dos ossos principais do alvo com a da fonte.
	# Mão, dedos e cabeça não se alinham sozinhos (osso curto/torto dá pulso quebrado e dedo torto):
	# herdam o alinhamento do osso de cima, então ficam retos em relação ao antebraço/pescoço.
	var alinha := {}
	var proximo := {"Hips": "Spine", "Spine": "Spine1", "Spine1": "Spine2", "Spine2": "Neck", "Neck": "Head"}
	for L in ["Left", "Right"]:
		proximo[L + "Shoulder"] = L + "Arm"
		proximo[L + "Arm"] = L + "ForeArm"
		proximo[L + "ForeArm"] = L + "Hand"
		proximo[L + "UpLeg"] = L + "Leg"
		proximo[L + "Leg"] = L + "Foot"
		proximo[L + "Foot"] = L + "ToeBase"
	var t_por_chave := {}
	for bi in mapa:
		t_por_chave[_chave_osso(esq.get_bone_name(bi))] = bi
	for bi in mapa:
		var k := _chave_osso(esq.get_bone_name(bi))
		if not proximo.has(k) or not t_por_chave.has(proximo[k]):
			continue
		var filho_t: int = t_por_chave[proximo[k]]
		var fi: int = mapa[bi]
		var filho_s: int = mapa[filho_t]
		var dt: Vector3 = t_rot * (esq.get_bone_global_rest(filho_t).origin - esq.get_bone_global_rest(bi).origin)
		var ds: Vector3 = s_rot * (fesq.get_bone_global_rest(filho_s).origin - fesq.get_bone_global_rest(fi).origin)
		if dt.length() > 0.03 and ds.length() > 0.03:   # osso "colado" no pai (Auto-Rig Pro) não dá direção confiável
			alinha[bi] = Quaternion(dt.normalized(), ds.normalized())
	# quem não tem alinhamento próprio herda o do osso de cima (em ordem: pai antes do filho)
	var herdar := func(eu: Callable, bi: int) -> Variant:
		if alinha.has(bi):
			return alinha[bi]
		var pai := esq.get_bone_parent(bi)
		if pai < 0:
			return null
		var q = eu.call(eu, pai)
		if q != null and mapa.has(bi):
			alinha[bi] = q
		return q
	for bi in mapa:
		herdar.call(herdar, bi)
	for par in pares:
		var origem: Animation = null
		for n in fap.get_animation_list():
			if n.begins_with(par[1]):
				origem = fap.get_animation(n)
		if origem == null:
			continue
		var nova := Animation.new()
		nova.length = origem.length
		nova.loop_mode = Animation.LOOP_LINEAR
		if mesmo:
			nova = origem.duplicate(true)
			nova.loop_mode = Animation.LOOP_LINEAR
			if par[0] != "parado":
				_tirar_deslocamento(nova, esq, t_rot.inverse() * Vector3.UP)
			if par[0] == "danca":
				nova = _so_giros(nova)
			lib.add_animation(par[0], nova)
			continue
		# trilhas de giro da fonte por osso + todos os tempos de chave
		var trilha := {}
		var tempos := {}
		for t in origem.get_track_count():
			if origem.track_get_type(t) != Animation.TYPE_ROTATION_3D:
				continue
			var fi := fesq.find_bone(str(origem.track_get_path(t).get_concatenated_subnames()))
			if fi < 0:
				continue
			trilha[fi] = t
			for c in origem.track_get_key_count(t):
				tempos[snappedf(origem.track_get_key_time(t, c), 0.001)] = true
		var lista := tempos.keys()
		lista.sort()
		var novas := {}
		for bi in mapa:
			var nt := nova.add_track(Animation.TYPE_ROTATION_3D)
			nova.track_set_path(nt, NodePath(caminho_esq + ":" + esq.get_bone_name(bi)))
			novas[bi] = nt
		for tm in lista:
			var locais := {}
			for fi in trilha:
				locais[fi] = origem.rotation_track_interpolate(trilha[fi], tm)
			var gs := _globais(fesq, s_rot, locais)
			# mesmo giro "no mundo" (em relação à pose de descanso) aplicado ao osso do alvo
			var gt := {}
			for bi in esq.get_bone_count():
				var pai := esq.get_bone_parent(bi)
				var gpai: Quaternion = t_rot if pai < 0 else gt[pai]
				if mapa.has(bi):
					var fi: int = mapa[bi]
					var delta: Quaternion = gs[fi] * (gs_rest[fi] as Quaternion).inverse()
					if alinha.has(bi):
						delta = delta * (alinha[bi] as Quaternion)
					gt[bi] = (delta * gt_rest[bi]).normalized()
					nova.rotation_track_insert_key(novas[bi], tm, (gpai.inverse() * gt[bi]).normalized())
				else:
					gt[bi] = gpai * esq.get_bone_rest(bi).basis.get_rotation_quaternion()
		lib.add_animation(par[0], nova)
	fonte.free()
	return lib


## giro global de cada osso (com o giro do esqueleto dentro do modelo); 'locais' troca o giro de descanso por um animado
static func _globais(sk: Skeleton3D, base: Quaternion, locais: Dictionary) -> Dictionary:
	var g := {}
	for i in sk.get_bone_count():
		var pai := sk.get_bone_parent(i)
		var l: Quaternion = locais[i] if locais.has(i) else sk.get_bone_rest(i).basis.get_rotation_quaternion()
		g[i] = ((base if pai < 0 else g[pai]) * l).normalized()
	return g


## giro do nó do esqueleto em relação a um nó de cima (ex.: Armature girada -90° no Sketchfab)
static func _giro_ate(n: Node, raiz: Node) -> Quaternion:
	var q := Quaternion.IDENTITY
	var x: Node = n
	while x != null and x != raiz:
		if x is Node3D:
			q = (x as Node3D).quaternion * q
		x = x.get_parent()
	return q


static func _caixa(raiz: Node3D) -> AABB:
	var cx := AABB()
	var primeira := true
	for n in raiz.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		var b: AABB = m.transform * m.get_aabb()
		var p := m.get_parent()
		while p and p != raiz:
			if p is Node3D:
				b = (p as Node3D).transform * b
			p = p.get_parent()
		cx = b if primeira else cx.merge(b)
		primeira = false
	return cx


## as animações de andar/correr empurram o quadril pra frente: o jogo é quem anda, então zera isso
static func _tirar_deslocamento(a: Animation, esq: Skeleton3D = null, cima := Vector3.UP) -> void:
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		if not str(a.track_get_path(t)).contains("Hips"):
			continue
		var n := a.track_get_key_count(t)
		if n == 0:
			continue
		# quadril fica no lugar dele de descanso (no chão do jogo): sobra só o sobe-desce e o balanço pros lados
		var ref: Vector3 = a.track_get_key_value(t, 0)
		if esq:
			var hi := esq.find_bone(str(a.track_get_path(t).get_concatenated_subnames()))
			if hi >= 0:
				ref = esq.get_bone_rest(hi).origin
		var up := cima.normalized()
		var h0: Vector3 = (a.track_get_key_value(t, 0) as Vector3) - ref
		var hN: Vector3 = (a.track_get_key_value(t, n - 1) as Vector3) - ref
		h0 -= up * h0.dot(up)
		hN -= up * hN.dot(up)
		var media := Vector3.ZERO
		for k in n:
			var v: Vector3 = (a.track_get_key_value(t, k) as Vector3) - ref
			v -= up * v.dot(up)
			media += v - h0.lerp(hN, float(k) / maxf(1.0, float(n - 1)))
		media /= float(n)
		for k in n:
			var v: Vector3 = a.track_get_key_value(t, k)
			var d := v - ref
			var hz := d - up * d.dot(up)
			var tend := h0.lerp(hN, float(k) / maxf(1.0, float(n - 1)))
			a.track_set_key_value(t, k, ref + up * d.dot(up) + (hz - tend - media))


static func _chave_osso(n: String) -> String:
	var s := n.replace("mixamorig:", "").replace("mixamorig_", "").replace("mixamorig", "").replace("_Armature", "")
	var i := s.rfind("_")
	if i > 0 and s.substr(i + 1).is_valid_int():
		s = s.substr(0, i)
	return s


func _tocar(qual: String) -> void:
	if anim == null or qual == atual:
		return
	var nome := ""
	if anim.has_animation("drops/" + qual):
		nome = "drops/" + qual
	elif qual == "danca" and anim.has_animation("danca"):
		nome = "danca"
	if nome == "":
		return
	atual = qual
	anim.play(nome, 0.25)


func dancar(sim: bool) -> void:
	dancando = sim
	if sim:
		_tocar("danca")


func lisa() -> Vector3:
	if not _tem_p:
		return global_position
	return _p_ant.lerp(_p_cur, clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0))


func _process(_dt: float) -> void:
	if modelo == null:
		return
	pos_lisa = lisa()
	modelo.position = _base_modelo + (pos_lisa - global_position)


func _physics_process(dt: float) -> void:
	var agora := global_position
	if not _tem_p or agora.distance_to(_p_cur) > 3.0:   # teleporte/entrou no carro: sem interpolar
		_p_cur = agora
	_p_ant = _p_cur
	_p_cur = agora
	_tem_p = true
	var vel := (CORRE if correndo else ANDA) * minf(1.0, desejo.length())
	var alvo := desejo.normalized() * vel if desejo.length() > 0.05 else Vector3.ZERO
	var k := 1.0 - exp(-dt * 10.0)
	velocity.x = lerpf(velocity.x, alvo.x, k)
	velocity.z = lerpf(velocity.z, alvo.z, k)
	if not is_on_floor():
		velocity.y -= gravidade * dt
	# sobe degrau (calçada, piso da oficina): se vai bater, tenta passar 30 cm mais alto
	var anda := Vector3(velocity.x, 0, velocity.z) * dt
	if anda.length() > 0.001 and test_move(global_transform, anda):
		var acima := global_transform.translated(Vector3.UP * 0.32)
		if not test_move(global_transform, Vector3.UP * 0.32) and not test_move(acima, anda):
			global_position += Vector3.UP * 0.32
	move_and_slide()
	var plano := Vector2(velocity.x, velocity.z).length()
	if plano > 0.3:
		if dancando and desejo.length() > 0.1:
			dancando = false
		var giro := atan2(velocity.x, velocity.z)
		modelo.rotation.y = lerp_angle(modelo.rotation.y, giro, 1.0 - exp(-dt * 12.0))
	if dancando:
		_tocar("danca")
	else:
		_tocar("corre" if plano > 2.6 else ("anda" if plano > 0.3 else "parado"))
		# ritmo da perna = velocidade de verdade (pé não patina nem fica frenético)
		if anim and atual == "anda":
			anim.speed_scale = clampf(plano / PASSO_ANDA, 0.6, 1.35)
		elif anim and atual == "corre":
			anim.speed_scale = clampf(plano / PASSO_CORRE, 0.85, 1.4)
		elif anim:
			anim.speed_scale = 1.0
