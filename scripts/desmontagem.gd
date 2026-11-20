extends Node3D
class_name Desmontagem
## (fase 2) Desmontar o carro na oficina: com o carro em cima do elevador (no chão), chegue perto de uma porta,
## do capô ou do porta-malas e aperte TIRAR. A peça vai pro cavalete do lado; COLOCAR põe de volta.
## O que foi tirado fica salvo no carro ("sem_pecas") e ele anda assim pela cidade.

var m      # Main
var of     # Oficina

## cavalete no chão livre entre o elevador e o sofá (coordenadas da oficina)
const CAVALETE := Vector3(1.2, 0.0, 22.6)
const COMPRIMENTO := 2.5
const ALTURA_BARRA := 1.05
const DIST_PECA := 1.15          # quão perto da peça a pessoa precisa estar
const T_VOO := 0.65              # segundos que a peça leva voando entre o carro e o cavalete

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
## o que o botão de ação faz perto do carro ("" = nada)
func acao(p: Vector3) -> String:
	_alvo = ""
	if not _pode():
		return ""
	var v: CarroVisual = m.visual
	var melhor := DIST_PECA
	for id in v.pecas:
		if _voando_id(id):
			continue
		var c: Vector3 = v.centro_peca(id)
		var d := Vector2(p.x - c.x, p.z - c.z).length()
		if id == "PCA" or id == "PTR":
			d -= 0.45    # capô e porta-malas são largos: dá pra pegar pela lateral do carro
		if d < melhor:
			melhor = d
			_alvo = id
	if _alvo == "":
		return ""
	return ("TIRAR " if v.tem_peca(_alvo) else "COLOCAR ") + v.nome_peca(_alvo)


func _pode() -> bool:
	return m.carro != null and m.visual != null and not (m.visual as CarroVisual).pecas.is_empty() \
		and of.carro_no_elevador() and not of.carro_alto and of.subindo == 0 and of.segurando == ""


func fazer(a: String) -> void:
	if _alvo == "":
		return
	var v: CarroVisual = m.visual
	var id := _alvo
	var sem: Array = (Dados.cfg().get("sem_pecas", []) as Array).duplicate()
	if a.begins_with("TIRAR") and v.tem_peca(id):
		v.fechar_tudo()
		sem.append(id)
		Dados.mudar("sem_pecas", sem)
		var h := _copia(v, id)
		h.global_transform = (v.pecas[id] as Node3D).global_transform
		v.mostrar_peca(id, false)
		_holders[id] = h
		_voar(h, h.global_transform, _lugar(h, sem.size() - 1), Callable())
		_som()
		_dica()
		m._montar_partes_ui()
	elif a.begins_with("COLOCAR") and not v.tem_peca(id):
		sem.erase(id)
		Dados.mudar("sem_pecas", sem)
		var h: Node3D = _holders.get(id)
		_holders.erase(id)
		if h == null:
			v.mostrar_peca(id, true)
			m._montar_partes_ui()
		else:
			var alvo: Transform3D = (v.pecas[id] as Node3D).global_transform
			_voar(h, h.global_transform, alvo, func(): v.mostrar_peca(id, true); h.queue_free(); m._montar_partes_ui())
		_som()
		_reorganizar()


func _som() -> void:
	if of._som_chave:
		of._som_chave.global_position = m.pessoa.global_position
		of._som_chave.play()


func _dica() -> void:
	of._dica("pecas", "PEÇA NO CAVALETE: ela fica guardada aqui e o carro anda sem ela.\nPra pôr de volta, chegue perto do lugar dela no carro e aperte COLOCAR.")


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


func _reorganizar() -> void:
	var sem: Array = Dados.cfg().get("sem_pecas", [])
	var i := 0
	for id in sem:
		var h: Node3D = _holders.get(id)
		if h and not _voando_no(h):
			h.global_transform = _lugar(h, i)
		i += 1


## quando troca de carro (ou abre o jogo): o cavalete mostra as peças tiradas DESTE carro
func _sincronizar() -> void:
	if m.visual == _visual_atual:
		return
	_visual_atual = m.visual
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
		tr.origin.y += sin(t * PI) * 0.35        # sobe um pouco no meio do caminho
		var no: Node3D = v["no"]
		if is_instance_valid(no):
			no.global_transform = tr
		if t >= 1.0:
			_voando.remove_at(k)
			var fim: Callable = v["fim"]
			if fim.is_valid():
				fim.call()
