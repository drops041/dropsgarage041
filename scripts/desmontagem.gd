extends Node3D
class_name Desmontagem
## (fase 2) Desmontar o carro na oficina, com as mãos: com o carro em cima do elevador (no chão), chegue perto
## de uma porta, do capô ou da tampa e aperte TIRAR. O boneco solta a peça e fica segurando; leve até o cavalete
## (na parede do fundo da cabine) e aperte GUARDAR. Pra pôr de volta: PEGAR no cavalete, levar até o carro, COLOCAR.
## O que foi tirado fica salvo no carro ("sem_pecas") e ele anda assim pela cidade.

var m      # Main
var of     # Oficina

## cavalete encostado na parede do fundo da cabine de pintura (coordenadas da oficina)
const CAVALETE := Vector3(-3.4, 0.0, 22.85)
const COMPRIMENTO := 2.5
const ALTURA_BARRA := 1.05
const DIST_PECA := 1.15          # quão perto da peça a pessoa precisa estar
const DIST_CAVALETE := 1.7       # quão perto do cavalete
const T_VOO := 0.35              # segundos da peça indo da mão pro lugar (e vice-versa)
const T_GESTO := 0.85            # o gesto de pegar/soltar

var carregando := ""             # peça na mão ("" = nada)
var _na_mao: Node3D              # cópia da peça que vai na mão
var _mao: Node3D                 # nó que gira junto com o boneco
var _alvo := ""                  # peça escolhida pro botão
var _holders := {}               # id -> Node3D (cópia da peça encostada no cavalete)
var _voando := []                # [{no, de, para, t, fim (Callable)}]
var _visual_atual: Object = null
var _t_sinc := 0.0
var _mat_tubo: StandardMaterial3D


func _ready() -> void:
	_mat_tubo = StandardMaterial3D.new()
	_mat_tubo.albedo_color = Color(0.85, 0.62, 0.08)    # amarelo de oficina
	_mat_tubo.metallic = 0.5
	_mat_tubo.roughness = 0.45
	_montar_cavalete()


func _montar_cavalete() -> void:
	var base := Node3D.new()
	base.name = "CavaletePecas"
	base.position = CAVALETE
	add_child(base)
	# dois cavaletes em "A" e a barra de cima
	for lado in [-1.0, 1.0]:
		var x: float = lado * (COMPRIMENTO / 2.0 - 0.1)
		for s in [-1.0, 1.0]:
			var perna := _tubo(Vector3(0.05, ALTURA_BARRA + 0.05, 0.05))
			perna.position = Vector3(x, (ALTURA_BARRA + 0.05) / 2.0 - 0.02, s * 0.2)
			perna.rotation.x = s * -0.36
			base.add_child(perna)
		var pe := _tubo(Vector3(0.06, 0.04, 0.95))
		pe.position = Vector3(x, 0.02, 0.0)
		base.add_child(pe)
	var barra := _tubo(Vector3(COMPRIMENTO, 0.06, 0.06))
	barra.position = Vector3(0, ALTURA_BARRA, 0)
	base.add_child(barra)
	# borracha no chão (pra peça não riscar)
	var tapete := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(COMPRIMENTO + 0.3, 0.015, 1.25)
	tapete.mesh = bm
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(0.09, 0.09, 0.1)
	mt.roughness = 0.95
	tapete.material_override = mt
	tapete.position = Vector3(0, 0.008, -0.45)
	base.add_child(tapete)
	var placa := Label3D.new()
	placa.text = "PEÇAS"
	placa.font_size = 72
	placa.pixel_size = 0.004
	placa.modulate = Color(1, 0.85, 0.2)
	placa.outline_size = 10
	placa.position = Vector3(0, ALTURA_BARRA + 0.32, 0)
	placa.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	base.add_child(placa)


func _tubo(tam: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = tam
	mi.mesh = bm
	mi.material_override = _mat_tubo
	return mi


# ======================================================================= botão
## o que o botão de ação faz ("" = nada)
func acao(p: Vector3) -> String:
	_alvo = ""
	if m.carro == null or m.visual == null or of.segurando != "" or (m.pessoa and m.pessoa.ocupado()):
		return ""
	var v: CarroVisual = m.visual
	var no_cavalete := _perto_cavalete(p)
	if carregando != "":
		_alvo = carregando
		if no_cavalete:
			return "GUARDAR " + v.nome_peca(carregando)
		if _pode() and v.pecas.has(carregando) and _dist_peca(p, carregando) < DIST_PECA:
			return "COLOCAR " + v.nome_peca(carregando)
		return ""
	# tirar do carro
	if _pode():
		var melhor := DIST_PECA
		for id in v.pecas:
			if not v.tem_peca(id) or _voando_id(id):
				continue
			var d := _dist_peca(p, id)
			if d < melhor:
				melhor = d
				_alvo = id
		if _alvo != "":
			return "TIRAR " + v.nome_peca(_alvo)
	# pegar do cavalete
	if no_cavalete and not _holders.is_empty():
		var melhor := INF
		for id in _holders:
			if _voando_id(id):
				continue
			var d := p.distance_to((_holders[id] as Node3D).global_position)
			if d < melhor:
				melhor = d
				_alvo = id
		if _alvo != "":
			return "PEGAR " + v.nome_peca(_alvo)
	return ""


func _dist_peca(p: Vector3, id: String) -> float:
	var c: Vector3 = (m.visual as CarroVisual).centro_peca(id)
	var d := Vector2(p.x - c.x, p.z - c.z).length()
	if id == "PCA" or id == "PTR":
		d -= 0.45    # capô e tampa são largos: dá pra pegar pela lateral do carro
	return d


func _perto_cavalete(p: Vector3) -> bool:
	var c := (get_parent() as Node3D).global_transform * CAVALETE
	return Vector2(p.x - c.x, p.z - c.z).length() < DIST_CAVALETE


func _pode() -> bool:
	return m.carro != null and m.visual != null and not (m.visual as CarroVisual).pecas.is_empty() \
		and of.carro_no_elevador() and not of.carro_alto and of.subindo == 0 and of.segurando == ""


## o boneco faz o gesto (pegar/soltar) olhando pro ponto e depois roda 'fim'
func _gesto(olhar: Vector3, fim: Callable) -> void:
	if m.pessoa and Pessoa.e_ual(m.pessoa.modelo):
		m.pessoa.trabalhar(m.pessoa.global_position, olhar, "PickUp_Table", T_GESTO, fim)
	else:
		fim.call()


func fazer(a: String) -> void:
	if _alvo == "":
		return
	var v: CarroVisual = m.visual
	var id := _alvo
	var sem: Array = (Dados.cfg().get("sem_pecas", []) as Array).duplicate()
	if a.begins_with("TIRAR") and v.tem_peca(id) and carregando == "":
		v.fechar_tudo()
		carregando = id
		_gesto(v.centro_peca(id), func():
			if not sem.has(id):
				sem.append(id)
			Dados.mudar("sem_pecas", sem)
			var h := _copia(v, id)
			h.global_transform = (v.pecas[id] as Node3D).global_transform
			v.mostrar_peca(id, false)
			_segurar(h)
			_som()
			_dica()
			m._montar_partes_ui())
	elif a.begins_with("GUARDAR") and carregando != "":
		var h := _na_mao
		_gesto((get_parent() as Node3D).global_transform * CAVALETE, func():
			_largar()
			if h:
				_holders[id] = h
				_voar(h, h.global_transform, _lugar(h, _fila(id)), _reorganizar)
			_som())
	elif a.begins_with("PEGAR") and carregando == "" and _holders.has(id):
		var h: Node3D = _holders[id]
		carregando = id
		_gesto(h.global_position, func():
			_holders.erase(id)
			_segurar(h)
			_som())
	elif a.begins_with("COLOCAR") and carregando == id and not v.tem_peca(id):
		var h := _na_mao
		_gesto(v.centro_peca(id), func():
			_largar()
			sem.erase(id)
			Dados.mudar("sem_pecas", sem)
			if h == null:
				v.mostrar_peca(id, true)
				m._montar_partes_ui()
			else:
				var alvo: Transform3D = (v.pecas[id] as Node3D).global_transform
				_voar(h, h.global_transform, alvo, func(): v.mostrar_peca(id, true); h.queue_free(); m._montar_partes_ui())
			_som()
			_reorganizar())


# ======================================================================= peça na mão
## a peça vai pra frente do peito do boneco e gira junto com ele
func _segurar(h: Node3D) -> void:
	_na_mao = h
	if m.pessoa == null:
		return
	if _mao == null or not is_instance_valid(_mao):
		_mao = Node3D.new()
		_mao.name = "MaoPeca"
		m.pessoa.add_child(_mao)
	var de := h.global_transform
	h.reparent(_mao, false)
	h.transform = _pose_mao(h)
	var para := h.global_transform
	# sai do lugar e vem pra mão (rapidinho)
	h.reparent(self, false)
	h.global_transform = de
	_voar(h, de, para, func():
		if is_instance_valid(h) and _na_mao == h and _mao:
			h.reparent(_mao, false)
			h.transform = _pose_mao(h))
	m.pessoa.carregando = true


func _largar() -> void:
	if _na_mao and is_instance_valid(_na_mao):
		var g := _na_mao.global_transform
		_na_mao.reparent(self, false)
		_na_mao.global_transform = g
	_na_mao = null
	carregando = ""
	if m.pessoa:
		m.pessoa.carregando = false


## pose da peça na mão (no espaço do boneco: +z = pra frente, +y = pra cima)
func _pose_mao(h: Node3D) -> Transform3D:
	var bb: AABB = h.get_meta("caixa")
	var rel: Basis = h.get_meta("rel")
	var b: Basis
	if h.get_meta("porta"):
		# porta em pé na frente do corpo, comprida pros lados, lado de fora olhando pra frente
		if float(h.get_meta("lado")) < 0.0:
			b = Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
		else:
			b = Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
	else:
		# capô / tampa: em pé, largura pros lados
		b = Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	b = Basis(Vector3.RIGHT, deg_to_rad(-8.0)) * b * rel.inverse()
	var centro := b * bb.get_center()
	var alt := 0.0
	for k in 8:
		alt = maxf(alt, absf((b * bb.get_endpoint(k)).y - centro.y))
	# o meio da peça na altura das mãos, um pouco pra frente; peça alta sobe pra não arrastar no chão
	var pos := Vector3(0.0, maxf(0.95, alt + 0.12), 0.42) - centro
	var k := 1.0 / maxf(m.pessoa.global_basis.get_scale().x, 0.001)
	return Transform3D(b, pos * k)


## entrou no carro, trocou de carro...: a peça da mão vai pro cavalete sozinha
func guardar_ja() -> void:
	if carregando == "" or _na_mao == null:
		return
	var id := carregando
	var h := _na_mao
	_largar()
	_holders[id] = h
	_reorganizar()


func _som() -> void:
	if of._som_chave:
		of._som_chave.global_position = m.pessoa.global_position
		of._som_chave.play()


func _dica() -> void:
	of._dica("pecas", "PEÇA NA MÃO: leve até o cavalete (parede do fundo da cabine) e aperte GUARDAR.\nPra pôr de volta: PEGAR no cavalete, levar até o lugar dela no carro e COLOCAR.")


# ======================================================================= cópia da peça e lugar no cavalete
## cópia visível da peça (mesmo mesh e material do carro: pintura e cor vão junto)
func _copia(v: CarroVisual, id: String) -> Node3D:
	var pv: Node3D = v.pecas[id]
	var h := Node3D.new()
	h.name = "Peca_" + id
	add_child(h)
	var cp: Node3D = pv.duplicate()
	cp.visible = true
	cp.transform = Transform3D.IDENTITY
	h.add_child(cp)
	h.set_meta("caixa", v.caixa_peca(id))
	h.set_meta("porta", id.begins_with("P") and id != "PCA" and id != "PTR")
	# de que lado do carro a peça fica (x do meio dela no espaço do carro)
	h.set_meta("lado", (v.global_transform.affine_inverse() * v.centro_peca(id)).x)
	# frame da peça em relação ao carro (o pivô pode estar girado se a porta estava aberta)
	h.set_meta("rel", (v.global_basis.orthonormalized().inverse() * pv.global_basis.orthonormalized()))
	return h


## onde a peça fica encostada no cavalete (transform no mundo). i = posição na fila
func _lugar(h: Node3D, i: int) -> Transform3D:
	var bb: AABB = h.get_meta("caixa")
	var rel: Basis = h.get_meta("rel")
	# porta: comprimento do carro vira o comprimento do cavalete, o lado de fora da porta olha pro elevador
	# capô / porta-malas: fica em pé, a frente do capô pra cima
	var b: Basis
	if h.get_meta("porta"):
		# o lado de fora da porta olha pro salão (-z do cavalete): porta da esquerda e da direita giram ao contrário
		if float(h.get_meta("lado")) < 0.0:
			b = Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
		else:
			b = Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
	else:
		b = Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	b = Basis(Vector3.RIGHT, deg_to_rad(-13.0)) * b * rel.inverse()   # encostada: o topo vai pra barra
	# caixa girada pra saber onde fica o pé e o meio
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for k in 8:
		var q: Vector3 = b * bb.get_endpoint(k)
		lo = lo.min(q)
		hi = hi.max(q)
	var fila := Vector3(0, 0, -0.16 * i)                  # uma na frente da outra
	var meio := Vector3((lo.x + hi.x) / 2.0, lo.y, hi.z)   # pé no chão, topo encostado na barra
	var pos := CAVALETE + Vector3(0, 0.02, -0.06) + fila - meio
	var t_local := Transform3D(b, pos)
	return (get_parent() as Node3D).global_transform * t_local


## posição da peça na fila do cavalete (na ordem em que foram tiradas, só as que estão lá)
func _fila(id: String) -> int:
	var i := 0
	for x in Dados.cfg().get("sem_pecas", []):
		if str(x) == id:
			return i
		if _holders.has(str(x)):
			i += 1
	return i


func _reorganizar() -> void:
	var sem: Array = Dados.cfg().get("sem_pecas", [])
	var i := 0
	for id in sem:
		var h: Node3D = _holders.get(id)
		if h and not _voando_no(h):
			h.global_transform = _lugar(h, i)
		if h:
			i += 1


## quando troca de carro (ou abre o jogo): o cavalete mostra as peças tiradas DESTE carro
func _sincronizar() -> void:
	if m.visual == _visual_atual:
		return
	_visual_atual = m.visual
	if _na_mao and is_instance_valid(_na_mao):
		_na_mao.queue_free()
	_na_mao = null
	carregando = ""
	if m.pessoa:
		m.pessoa.carregando = false
	for id in _holders:
		(_holders[id] as Node3D).queue_free()
	_holders.clear()
	_voando.clear()
	if m.visual == null:
		return
	var v: CarroVisual = m.visual
	var sem: Array = Dados.cfg().get("sem_pecas", [])
	var i := 0
	for id in sem:
		if v.pecas.has(str(id)):
			var h := _copia(v, str(id))
			h.global_transform = _lugar(h, i)
			_holders[str(id)] = h
		i += 1


# ======================================================================= animação
func _voar(no: Node3D, de: Transform3D, para: Transform3D, fim: Callable) -> void:
	_voando.append({"no": no, "de": de, "para": para, "t": 0.0, "fim": fim})


func _voando_no(no: Node3D) -> bool:
	for v in _voando:
		if v["no"] == no:
			return true
	return false


func _voando_id(id: String) -> bool:
	return _holders.has(id) and _voando_no(_holders[id])


func _process(dt: float) -> void:
	# a peça na mão gira junto com o boneco (o corpo dele é que vira, não o nó da pessoa)
	if _mao and is_instance_valid(_mao) and m.pessoa and m.pessoa.modelo:
		_mao.rotation.y = m.pessoa.modelo.rotation.y
		_mao.position = m.pessoa.modelo.position - m.pessoa._base_modelo
	_t_sinc -= dt
	if _t_sinc <= 0.0:
		_t_sinc = 0.5
		_sincronizar()
	for k in range(_voando.size() - 1, -1, -1):
		var v: Dictionary = _voando[k]
		v["t"] = minf(1.0, float(v["t"]) + dt / T_VOO)
		var t: float = v["t"]
		var e := t * t * (3.0 - 2.0 * t)
		var tr: Transform3D = (v["de"] as Transform3D).interpolate_with(v["para"], e)
		tr.origin.y += sin(t * PI) * 0.08        # sobe um tiquinho no meio do caminho
		var no: Node3D = v["no"]
		if is_instance_valid(no):
			no.global_transform = tr
		if t >= 1.0:
			_voando.remove_at(k)
			var fim: Callable = v["fim"]
			if fim.is_valid():
				fim.call()
