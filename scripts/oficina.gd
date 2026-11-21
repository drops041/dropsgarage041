class_name Oficina
extends Node
## Oficina "de verdade" dentro da Drops (a pé, estilo RP):
##  - CABINE DE PINTURA: entrou na sala branca -> botão PINTAR -> menu de cores (o carro fica onde está)
##  - ELEVADOR PANTOGRÁFICO: estaciona o carro em cima -> SUBIR ELEVADOR
##  - PAREDE DAS RODAS: pega um jogo de rodas na parede, leva até o carro e instala roda por roda
## Coordenadas "locais" = da Drops (mapa.drops_ponto): x pra esquerda de quem olha da rua, z pra dentro do lote.

const AMARELO := Color("ffd400")
const ELEV := Vector3(-2.55, 0.0, 18.0)         # centro do elevador. v41: GIRADO (carro atravessado) e metade
                                                 # dentro da cabine branca, entrando pela abertura grande
const ELEV_EIXO := Vector3(1, 0, 0)              # direção do comprimento do carro em cima do elevador
const CAB_MIN := Vector2(-5.05, 13.7)            # cabine de pintura (sala branca): x, z
const CAB_MAX := Vector2(-0.35, 23.3)            # (fase 2) cabine aumentada: a parede foi 1,4 m pra dentro da oficina
const PAREDE_X := 4.58                           # parede preta da esquerda (a das rodas)
const RACK_Z0 := 14.2
const RACK_Z1 := 26.4                           # v31: oficina mais funda -> prateleira mais comprida
const CAIXA_SOM := Vector3(4.28, 1.42, 27.3)     # (v33) em cima do gaveteiro vermelho, do lado da sala gamer
const RACK_Y := [0.42, 1.04]
const RAIO_RACK := 0.25
const BOTOEIRA := Vector3(-0.13, 0.0, 14.35)      # (fase 2) botoeira do elevador na parede da cabine, do lado do vão (não fica mais no meio)
const SUBIDA := 0.85                             # quanto o carro sobe
const T_INSTALAR := 1.5

var m: Node                                      # main.gd
var xf := Transform3D.IDENTITY
var raiz: Node3D
var aros_rack: Array = []                        # [Node3D, id, nome, Label3D, pos_local]
var sapatas: Array[Node3D] = []
var bracos: Array = []                           # [MeshInstance3D, lado, sinal]
var altura := 0.0                                # altura atual das sapatas (0 = no chão)
var subindo := 0                                 # +1 subindo, -1 descendo, 0 parado
var carro_alto := false
var _base_carro := Transform3D.IDENTITY
var segurando := ""                              # id da roda na mão
var _na_mao: Node3D
var _mao: Node3D
var instaladas := ["", "", "", ""]
var _instalando := -1
var _t_inst := 0.0
var _acao := ""                                  # o que o botão faz agora
var _alvo_rack := -1
var _alvo_roda := -1
var _som_motor: AudioStreamPlayer3D
var _som_chave: AudioStreamPlayer3D
var barra: ProgressBar
# pintura
var pintando := false
var laje: Laje
var desm: Desmontagem                            # (fase 2) tirar/colocar portas, capô e porta-malas
var _cam_ang := 0.0
var painel_pintura: PanelContainer
var _alvo_pintura := ""                          # (fase 2) "" = carro todo; "PFL", "PCA"... = só aquela peça
var _conteudo: VBoxContainer


func _ready() -> void:
	xf = m.mapa.drops_xf
	raiz = Node3D.new()
	raiz.name = "OficinaRP"
	add_child(raiz)
	raiz.global_transform = xf
	_elevador()
	_rack()
	_sons()
	_caixa_som()
	_sala_gamer()
	_ui()
	# (v40) laje em cima da casa, com sinuca
	laje = Laje.new()
	laje.m = m
	laje.of = self
	raiz.add_child(laje)
	# (fase 2) desmontagem: cavalete de peças do lado do elevador
	desm = Desmontagem.new()
	desm.m = m
	desm.of = self
	raiz.add_child(desm)


# ======================================================================= montagem
func _mat(cor: Color, metal := 0.0, aspereza := 0.6, brilho := 0.0) -> StandardMaterial3D:
	var s := StandardMaterial3D.new()
	s.albedo_color = cor
	s.metallic = metal
	s.roughness = aspereza
	if brilho > 0.0:
		s.emission_enabled = true
		s.emission = cor
		s.emission_energy_multiplier = brilho
	return s


func _caixa(pai: Node3D, tam: Vector3, pos: Vector3, mat: Material, giro := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = tam
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = giro
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pai.add_child(mi)
	return mi


func _elevador() -> void:
	var e := Node3D.new()
	e.name = "Elevador"
	e.position = ELEV
	e.rotation.y = atan2(ELEV_EIXO.x, ELEV_EIXO.z)   # o "z" do elevador vira o eixo do carro
	raiz.add_child(e)
	var aco := _mat(Color(0.16, 0.17, 0.19), 0.6, 0.45)
	var azul := _mat(Color(0.08, 0.25, 0.62), 0.3, 0.45)       # pintura do elevador
	var borracha := _mat(Color(0.05, 0.05, 0.05), 0.0, 0.9)
	var faixa := _mat(Color(1.0, 0.8, 0.05), 0.0, 0.6)
	var preto := _mat(Color(0.03, 0.03, 0.03), 0.0, 0.8)
	# faixa de segurança amarela e preta no chão em volta
	for s in [-1.0, 1.0]:
		_caixa(e, Vector3(0.1, 0.006, 4.6), Vector3(s * 1.45, 0.03, 0), faixa)
		_caixa(e, Vector3(2.9, 0.006, 0.1), Vector3(0, 0.03, s * 2.3), faixa)
	for lado in [-1.0, 1.0]:
		var x: float = lado * 0.52
		# trilho no chão (embutido: o carro passa por cima)
		_caixa(e, Vector3(0.62, 0.012, 2.1), Vector3(x, 0.03, 0), preto)
		var sap := Node3D.new()
		sap.position = Vector3(x, 0.04, 0)
		e.add_child(sap)
		_caixa(sap, Vector3(0.5, 0.07, 1.95), Vector3(0, 0.0, 0), azul)
		for z in [-0.75, 0.75]:
			_caixa(sap, Vector3(0.16, 0.05, 0.2), Vector3(0, 0.06, z), borracha)   # calços de borracha
		sapatas.append(sap)
		# tesoura (dois braços cruzados de cada lado da sapata)
		for sx in [-1.0, 1.0]:
			for sinal in [-1.0, 1.0]:
				var b := _caixa(e, Vector3(0.06, 0.07, 1.7), Vector3(x + sx * 0.2, 0.04, 0), aco)
				bracos.append([b, x + sx * 0.2, sinal])
	# comando (botoeira) preso na parede da cabine, do lado do vão por onde o carro entra; botões virados pra oficina
	var cmd := Node3D.new()
	cmd.position = BOTOEIRA
	cmd.rotation.y = PI / 2.0
	raiz.add_child(cmd)
	_caixa(cmd, Vector3(0.3, 0.42, 0.04), Vector3(0, 1.25, -0.05), aco)                      # chapa na parede
	_caixa(cmd, Vector3(0.24, 0.32, 0.12), Vector3(0, 1.25, 0.03), _mat(Color(1.0, 0.82, 0.05), 0.1, 0.5))
	_caixa(cmd, Vector3(0.05, 0.05, 0.02), Vector3(0.0, 1.32, 0.095), _mat(Color(0.1, 0.9, 0.2), 0, 0.4, 1.5))
	_caixa(cmd, Vector3(0.05, 0.05, 0.02), Vector3(0.0, 1.2, 0.095), _mat(Color(0.95, 0.1, 0.1), 0, 0.4, 1.5))
	_caixa(cmd, Vector3(0.025, 1.2, 0.025), Vector3(0.08, 0.6, -0.04), _mat(Color(0.08, 0.08, 0.08), 0.2, 0.6))   # conduíte até o chão
	_posicionar_elevador()


func _posicionar_elevador() -> void:
	for s in sapatas:
		s.position.y = 0.04 + altura
	var L := 1.7
	for b in bracos:
		var mi: MeshInstance3D = b[0]
		var h := clampf(altura, 0.0, L * 0.95)
		var ang := asin(h / L)
		mi.position = Vector3(float(b[1]), 0.04 + h / 2.0, 0)
		mi.rotation = Vector3(float(b[2]) * ang, 0, 0)


func _rack() -> void:
	var r := Node3D.new()
	r.name = "ParedeDasRodas"
	raiz.add_child(r)
	var chapa := _mat(Color(0.93, 0.93, 0.92), 0.0, 0.75)   # fundo branco da prateleira
	var cano := _mat(Color(0.55, 0.56, 0.58), 0.8, 0.3)
	_caixa(r, Vector3(0.03, 1.5, RACK_Z1 - RACK_Z0 + 0.8), Vector3(PAREDE_X - 0.02, 0.8, (RACK_Z0 + RACK_Z1) / 2.0), chapa)
	for y in RACK_Y:
		_caixa(r, Vector3(0.05, 0.05, RACK_Z1 - RACK_Z0 + 0.6), Vector3(PAREDE_X - 0.08, float(y) - RAIO_RACK - 0.03, (RACK_Z0 + RACK_Z1) / 2.0), cano)
	# letreiro
	var t := Label3D.new()
	t.text = "RODAS DROPS — ESCOLHA O JOGO"
	t.font_size = 64
	t.outline_size = 10
	t.pixel_size = 0.004
	t.modulate = AMARELO
	t.position = Vector3(PAREDE_X - 0.04, 1.75, (RACK_Z0 + RACK_Z1) / 2.0)
	t.rotation.y = -PI / 2.0
	r.add_child(t)
	var lista: Array = Dados.RODAS
	var por_linha := ceili(lista.size() / 2.0)
	for k in lista.size():
		var linha := k / por_linha
		var col := k % por_linha
		var z := lerpf(RACK_Z0, RACK_Z1, float(col) / maxf(1.0, por_linha - 1))
		var y: float = RACK_Y[1 - linha]
		var pos := Vector3(PAREDE_X - 0.16, y, z)
		var aro := _aro_modelo(str(lista[k][0]), RAIO_RACK, 0.2)
		if aro == null:
			continue
		aro.position = pos
		aro.rotation.y = PI          # face de fora (+X do aro) virada pra dentro da oficina
		r.add_child(aro)
		var nome := Label3D.new()
		nome.text = str(lista[k][1])
		nome.font_size = 30
		nome.outline_size = 6
		nome.pixel_size = 0.0022
		nome.width = 200
		nome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nome.position = Vector3(PAREDE_X - 0.05, y - RAIO_RACK - 0.09, z)
		nome.rotation.y = -PI / 2.0
		nome.visibility_range_end = 7.0
		r.add_child(nome)
		aros_rack.append([aro, str(lista[k][0]), str(lista[k][1]), nome, pos])


## um aro da loja (sem pneu), já com material de metal
func _aro_modelo(id: String, raio: float, largura: float) -> Node3D:
	var arq := Dados.modelo("res://modelos/rodas/%s.glb" % id)
	if not ResourceLoader.exists(arq):
		return null
	var cont := Node3D.new()
	var aro: Node3D = load(arq).instantiate()
	aro.scale = Vector3(largura, raio, raio)
	cont.add_child(aro)
	# mesmo cromado (com reflexo) das rodas montadas no carro
	var raios := _cromo(Color(0.86, 0.87, 0.9), 0.2)
	var borda := _cromo(Color(0.96, 0.96, 0.98), 0.04)
	var tambor := _mat(Color(0.35, 0.35, 0.37), 0.8, 0.4)
	for n in aro.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 30.0
		for i in mi.mesh.get_surface_count():
			var mt := mi.mesh.surface_get_material(i)
			var nm := mt.resource_name if mt else ""
			var usa := borda if nm in ["LIP", "BOLT"] else (tambor if nm == "BARREL" else raios)
			if nm == "RIM" and mt is BaseMaterial3D and (mt as BaseMaterial3D).albedo_texture:
				usa = _raios_textura(mt as BaseMaterial3D)
			mi.set_surface_override_material(i, usa)
	return cont


## raios desenhados em textura (BBS trançada): tinta prata com recorte e relevo
func _raios_textura(orig: BaseMaterial3D) -> Material:
	var s := ShaderMaterial.new()
	s.shader = load("res://scripts/shaders/roda.gdshader")
	s.set_shader_parameter("reflexo", CarroVisual.reflexo)
	s.set_shader_parameter("forca_reflexo", CarroVisual.forca_reflexo)
	s.set_shader_parameter("tinta", Color(0.86, 0.87, 0.9))
	s.set_shader_parameter("usa_mascara", true)
	s.set_shader_parameter("mascara", orig.albedo_texture)
	s.set_shader_parameter("relevo", orig.normal_texture)
	return s


func _cromo(cor: Color, aspereza: float) -> Material:
	if not ResourceLoader.exists("res://scripts/shaders/cromo.gdshader"):
		return _mat(cor, 0.85, aspereza)
	var s := ShaderMaterial.new()
	s.shader = load("res://scripts/shaders/cromo.gdshader")
	s.set_shader_parameter("reflexo", CarroVisual.reflexo)
	s.set_shader_parameter("forca_reflexo", CarroVisual.forca_reflexo)
	s.set_shader_parameter("tinta", cor)
	s.set_shader_parameter("aspereza", aspereza)
	return s


## (v33) sala gamer no fundo da oficina (modelo que o dono mandou), com colisão nos móveis
func _sala_gamer() -> void:
	var arq := "res://modelos/cenario/sala_gamer.glb"
	if not ResourceLoader.exists(arq):
		return
	var s: Node3D = load(arq).instantiate()
	raiz.add_child(s)
	for gi in s.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = 45.0
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var corpo := StaticBody3D.new()
	raiz.add_child(corpo)
	# [x0, x1, z0, z1, altura] em coordenadas da oficina
	for b in [[-1.71, 0.13, 23.11, 23.95, 0.62], [-0.71, 0.13, 23.92, 25.63, 0.62],   # sofá em L
			[-4.84, -3.8, 25.39, 27.5, 0.6], [-3.67, -2.77, 25.8, 26.64, 1.0],          # mesa do PC e cadeira
			[-3.51, -0.84, 27.4, 28.21, 0.47]]:                                         # rack da TV
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(b[1] - b[0], b[4], b[3] - b[2])
		cs.shape = bx
		cs.position = Vector3((b[0] + b[1]) / 2.0, b[4] / 2.0, (b[2] + b[3]) / 2.0)
		corpo.add_child(cs)
	# luz da TV (azul/roxa) iluminando a sala
	var luz := OmniLight3D.new()
	luz.light_color = Color(0.55, 0.45, 1.0)
	luz.light_energy = 0.8
	luz.omni_range = 4.5
	luz.position = Vector3(-1.5, 1.3, 26.8)
	luz.shadow_enabled = false
	raiz.add_child(luz)


## caixa de som da oficina (Mega Funk baixinho), em cima da estante do fundo
func _caixa_som() -> void:
	var cx := Node3D.new()
	cx.position = CAIXA_SOM
	cx.rotation.y = -PI / 2.0     # frente pra dentro da oficina
	raiz.add_child(cx)
	var preto := _mat(Color(0.05, 0.05, 0.06), 0.1, 0.6)
	var tela := _mat(Color(0.12, 0.12, 0.13), 0.0, 0.9)
	var cone := _mat(Color(0.02, 0.02, 0.02), 0.2, 0.5)
	var amarelo := _mat(AMARELO, 0.2, 0.4, 0.6)
	_caixa(cx, Vector3(0.46, 0.62, 0.36), Vector3(0, 0.31, 0), preto)
	_caixa(cx, Vector3(0.42, 0.58, 0.01), Vector3(0, 0.31, 0.181), tela)
	for y in [0.2, 0.47]:
		var mi := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 0.15 if y < 0.3 else 0.07
		cy.bottom_radius = cy.top_radius
		cy.height = 0.02
		mi.mesh = cy
		mi.material_override = cone
		mi.rotation.x = PI / 2.0
		mi.position = Vector3(0, y, 0.19)
		cx.add_child(mi)
	_caixa(cx, Vector3(0.12, 0.03, 0.01), Vector3(0.12, 0.57, 0.19), amarelo)   # led
	var som := AudioStreamPlayer3D.new()
	som.stream = load("res://audio/mega_funk.mp3")
	if som.stream is AudioStreamMP3:
		(som.stream as AudioStreamMP3).loop = true
	som.volume_db = -27.0      # (21/11) bem baixinho, de fundo (antes -9 dB)
	som.unit_size = 3.0
	som.max_distance = 25.0
	som.position = Vector3(0, 0.35, 0.2)
	som.autoplay = true
	cx.add_child(som)


## pessoa/carro dentro da Drops (pra abaixar a música do jogo e ouvir o som da oficina)
func dentro(p: Vector3) -> bool:
	var l := local(p)
	return l.z > 6.0 and l.z < 29.0 and absf(l.x) < 5.5 and absf(l.y) < 4.0


func _sons() -> void:
	# (v33) mais baixo e mais "macio" (antes era alto e áspero)
	_som_motor = AudioStreamPlayer3D.new()
	_som_motor.stream = _gerar_som(0)
	_som_motor.volume_db = -16.0
	_som_motor.unit_size = 3.0
	_som_motor.max_distance = 18.0
	_som_motor.position = ELEV
	raiz.add_child(_som_motor)
	_som_chave = AudioStreamPlayer3D.new()
	_som_chave.stream = _gerar_som(1)
	_som_chave.volume_db = -15.0
	_som_chave.unit_size = 3.0
	_som_chave.max_distance = 18.0
	raiz.add_child(_som_chave)


## som feito na hora: 0 = motor hidráulico do elevador (zumbido grave e suave, em loop),
## 1 = parafusadeira (3 apertadinhas com catraca, sem chiado)
func _gerar_som(tipo: int) -> AudioStreamWAV:
	var hz := 22050
	var dur := 1.0 if tipo == 0 else 1.3
	var n := int(hz * dur)
	var b := PackedByteArray()
	b.resize(n * 2)
	var ruido := 0.0
	var ruido2 := 0.0
	for i in n:
		var t := float(i) / hz
		var v := 0.0
		if tipo == 0:
			# 60/120/180 Hz (ciclos inteiros em 1 s: o loop não estala) + chiado de óleo bem filtrado
			v = sin(t * TAU * 60.0) * 0.32 + sin(t * TAU * 120.0) * 0.14 + sin(t * TAU * 180.0) * 0.05
			v *= 0.85 + 0.15 * sin(t * TAU * 4.0)
			ruido += (randf_range(-1, 1) - ruido) * 0.03
			v += ruido * 0.5
		else:
			var k := int(t / 0.42)
			var tl := fmod(t, 0.42)
			var env := 0.0
			if k < 3 and tl < 0.3:
				env = minf(1.0, tl / 0.02) * clampf((0.3 - tl) / 0.08, 0.0, 1.0)
			var catraca := 0.55 + 0.45 * sin(t * TAU * 26.0)       # batidinhas da catraca, arredondadas
			ruido += (randf_range(-1, 1) - ruido) * 0.08
			ruido2 += (ruido - ruido2) * 0.2
			v = (sin(t * TAU * 165.0) * 0.35 + sin(t * TAU * 330.0) * 0.12 + ruido2 * 0.9) * catraca * env
		b.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 20000))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = hz
	w.data = b
	if tipo == 0:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = n
	return w


func _ui() -> void:
	barra = ProgressBar.new()
	barra.show_percentage = false
	barra.custom_minimum_size = Vector2(320, 22)
	barra.visible = false
	var fundo := StyleBoxFlat.new()
	fundo.bg_color = Color(0, 0, 0, 0.6)
	fundo.set_corner_radius_all(10)
	var cheio := StyleBoxFlat.new()
	cheio.bg_color = AMARELO
	cheio.set_corner_radius_all(10)
	barra.add_theme_stylebox_override("background", fundo)
	barra.add_theme_stylebox_override("fill", cheio)
	m.hud.add_child(barra)


# ======================================================================= estado
func local(p: Vector3) -> Vector3:
	return xf.affine_inverse() * p


func _centro_carro() -> Vector3:
	var d: Dictionary = m.dados
	return m.carro.global_transform * Vector3(0, 0, (float(d["axF"]) + float(d["axR"])) / 2.0)


## o carro está em cima do elevador (centralizado e alinhado)?
func carro_no_elevador() -> bool:
	if m.carro == null:
		return false
	var c := local(_centro_carro())
	var dz: Vector3 = xf.basis.inverse() * (m.carro.global_basis.z as Vector3)
	var lado := Vector3(ELEV_EIXO.z, 0, -ELEV_EIXO.x)
	var d := c - ELEV
	return absf(d.dot(lado)) < 0.8 and absf(d.dot(ELEV_EIXO)) < 1.4 and absf(dz.dot(ELEV_EIXO)) > 0.88 and absf(c.y) < 1.5


func pode_entrar_no_carro() -> bool:
	if carro_alto or subindo != 0:
		m.toast("DESCE O ELEVADOR PRIMEIRO")
		return false
	return true


func na_cabine(p: Vector3) -> bool:
	var l := local(p)
	return l.x > CAB_MIN.x and l.x < CAB_MAX.x and l.z > CAB_MIN.y and l.z < CAB_MAX.y and absf(l.y) < 2.0


func _process(dt: float) -> void:
	if m.carro == null:
		return
	_mover_elevador(dt)
	if pintando or (laje and (laje.sinuca.ativo or laje.subindo)):
		_acao = ""
		_mostrar_botao()
		return
	if not m.pe or m.pessoa == null:
		_acao = ""
		_mostrar_botao()
		return
	if _mao and m.pessoa.modelo:
		_mao.rotation.y = m.pessoa.modelo.rotation.y
	_instalar(dt)
	var antes := _acao
	_escolher_acao()
	_dicas()
	_mostrar_botao()
	if antes != _acao:
		_alinhar_botoes.call_deferred()


func _mover_elevador(dt: float) -> void:
	if subindo == 0:
		return
	var alvo_h := 0.0 if subindo < 0 else _altura_sapata_carro() + SUBIDA
	altura = move_toward(altura, alvo_h, dt * 0.38)
	# o carro (a parte que aparece) sobe junto com as sapatas; a física fica no chão, travada
	m.elev_y = maxf(0.0, altura - _altura_sapata_carro())
	_posicionar_elevador()
	if is_equal_approx(altura, alvo_h):
		_som_motor.stop()
		if subindo > 0:
			carro_alto = true
		else:
			carro_alto = false
			m.elev_y = 0.0
			_travar(false)
			_conferir_jogo_incompleto()
		subindo = 0


## no elevador o carro não sai do lugar (nem se alguém encostar nele)
func _travar(sim: bool) -> void:
	for p in ["axis_lock_linear_x", "axis_lock_linear_z", "axis_lock_angular_x", "axis_lock_angular_y", "axis_lock_angular_z"]:
		m.carro.set(p, sim)


## altura do assoalho do carro (onde a sapata encosta)
func _altura_sapata_carro() -> float:
	return 0.1


func _alternar_elevador() -> void:
	if subindo != 0:
		return
	if carro_alto:
		subindo = -1
	else:
		if not carro_no_elevador():
			m.toast("ESTACIONA O CARRO EM CIMA DO ELEVADOR", 2.2)
			return
		# alinha o carro certinho no elevador e trava
		var c := _centro_carro()
		var d: Dictionary = m.dados
		var eixo_mundo: Vector3 = xf.basis * ELEV_EIXO
		var fwd: Vector3 = eixo_mundo if m.carro.global_basis.z.dot(eixo_mundo) > 0.0 else -eixo_mundo
		var b := Basis.looking_at(-fwd, Vector3.UP)
		var centro_mundo := xf * Vector3(ELEV.x, local(c).y, ELEV.z)
		var origem := centro_mundo - b * Vector3(0, 0, (float(d["axF"]) + float(d["axR"])) / 2.0)
		m.carro.linear_velocity = Vector3.ZERO
		m.carro.angular_velocity = Vector3.ZERO
		_base_carro = Transform3D(b, origem)
		m.carro.global_transform = _base_carro
		_travar(true)
		subindo = 1
	_som_motor.play()


# ======================================================================= o que o botão faz
func _escolher_acao() -> void:
	_acao = ""
	_alvo_rack = -1
	_alvo_roda = -1
	if _instalando >= 0:
		return
	var p: Vector3 = m.pessoa.global_position
	var l := local(p)
	# 0) (v40) escada da laje e sinuca
	if laje and segurando == "":
		_acao = laje.acao(l)
		if _acao != "":
			return
	# 1) com roda na mão: instalar / devolver
	if segurando != "":
		var melhor := 9.0
		for i in 4:
			var d := p.distance_to(m.rodas_vis[i].global_position)
			if d < melhor:
				melhor = d
				_alvo_roda = i
		if melhor < 1.6 and carro_no_elevador() and carro_alto:
			_acao = "INSTALAR RODA" if m.visual.id_roda(_alvo_roda) != segurando else ""
			if _acao != "":
				return
		var no_botao := Vector2(l.x - BOTOEIRA.x, l.z - BOTOEIRA.z).length() < 0.9
		if l.x > PAREDE_X - 1.4 and l.z > RACK_Z0 - 0.8 and l.z < RACK_Z1 + 0.8 and not no_botao:
			_acao = "DEVOLVER RODA"
			return
	# 1b) (fase 2) perto de uma porta / capô / porta-malas do carro no elevador, ou do cavalete: tirar, guardar, pegar, colocar
	if desm and segurando == "":
		_acao = desm.acao(p)
		if _acao != "" or desm.carregando != "":
			return
	# 2) cabine de pintura (com roda na mão não: o elevador agora fica dentro da cabine)
	if na_cabine(p) and segurando == "":
		_acao = "PINTAR"
		return
	# 3) parede das rodas
	if segurando == "" and l.x > PAREDE_X - 1.4 and l.z > RACK_Z0 - 0.8 and l.z < RACK_Z1 + 0.8:
		var melhor := 99.0
		for k in aros_rack.size():
			var pz: float = (aros_rack[k][4] as Vector3).z
			var py: float = (aros_rack[k][4] as Vector3).y
			# na frente da pessoa; entre as duas linhas, a de cima se ela olhar pra cima... aqui: a mais perto no z, de cima primeiro
			var d := absf(pz - l.z) + (0.0 if py > 0.8 else 0.18)
			if d < melhor:
				melhor = d
				_alvo_rack = k
		# tocar de novo perto do mesmo lugar alterna entre a de cima e a de baixo
		if _alvo_rack >= 0 and _linha_baixo:
			var par := _par_vertical(_alvo_rack)
			if par >= 0:
				_alvo_rack = par
		if _alvo_rack >= 0:
			_acao = "PEGAR " + str(aros_rack[_alvo_rack][2]).to_upper()
			return
	# 4) elevador: (v37) só no botão (a botoeira amarela do lado do elevador)
	if Vector2(l.x - BOTOEIRA.x, l.z - BOTOEIRA.z).length() < 1.3 and subindo == 0:
		if carro_alto:
			_acao = "DESCER ELEVADOR"
		elif carro_no_elevador():
			_acao = "SUBIR ELEVADOR"


var _linha_baixo := false
func _par_vertical(k: int) -> int:
	var pz: float = (aros_rack[k][4] as Vector3).z
	var py: float = (aros_rack[k][4] as Vector3).y
	for j in aros_rack.size():
		if j != k and absf((aros_rack[j][4] as Vector3).z - pz) < 0.05 and absf((aros_rack[j][4] as Vector3).y - py) > 0.3:
			return j
	return -1


## (v37) dica que aparece só na primeira vez que a pessoa chega em cada coisa
func _dicas() -> void:
	var p: Vector3 = m.pessoa.global_position
	var l := local(p)
	if l.x > PAREDE_X - 1.4 and l.z > RACK_Z0 - 0.8 and l.z < RACK_Z1 + 0.8:
		_dica("rodas", "PAREDE DAS RODAS: escolha o jogo e aperte PEGAR. A seta ▲▼ troca entre a linha de cima e a de baixo.\nDepois suba o carro no elevador e instale roda por roda.")
	elif carro_no_elevador() and Vector2(l.x - ELEV.x, l.z - ELEV.z).length() < 3.6:
		_dica("elevador", "ELEVADOR: o carro tem que estar em cima das sapatas azuis.\nVá até o BOTÃO AMARELO do lado pra subir ou descer.")


func _dica(chave: String, texto: String) -> void:
	if Dados.dicas.has(chave) or OS.has_environment("DROPS_TESTE"):
		return
	Dados.dicas[chave] = true
	Dados.salvar()
	m.toast(texto, 6.0)


func _mostrar_botao() -> void:
	var b: Button = m.botoes.get("acao")
	if b == null:
		return
	b.visible = _acao != ""
	b.text = _acao
	var trocar: Button = m.botoes.get("acao_linha")
	if trocar:
		trocar.visible = _acao.begins_with("PEGAR") and _par_vertical(_alvo_rack) >= 0
	for k in aros_rack.size():
		var sel := k == _alvo_rack
		var lb: Label3D = aros_rack[k][3]
		lb.modulate = AMARELO if sel else Color.WHITE
		(aros_rack[k][0] as Node3D).scale = Vector3.ONE * (1.12 if sel else 1.0)


## os botões de baixo (ação + entrar no carro) ficam encostados no canto direito, qualquer que seja o texto
func _alinhar_botoes() -> void:
	var pb: Control = m.pe_botoes
	pb.reset_size()
	var t: Vector2 = m.get_viewport().get_visible_rect().size
	var mg: float = 26.0 + m._margem_segura()
	pb.position = Vector2(t.x - mg - pb.size.x, t.y - mg - 80)


func trocar_linha() -> void:
	_linha_baixo = not _linha_baixo


func interagir() -> void:
	if _acao == "":
		return
	if _acao in ["SUBIR NA LAJE", "DESCER DA LAJE", "JOGAR SINUCA"]:
		laje.fazer(_acao)
	elif _acao.begins_with("TIRAR ") or _acao.begins_with("COLOCAR ") or _acao.begins_with("GUARDAR ") \
			or (_acao.begins_with("PEGAR ") and desm and desm._alvo != "" and _alvo_rack < 0):
		desm.fazer(_acao)
	elif _acao == "PINTAR":
		abrir_pintura()
	elif _acao == "SUBIR ELEVADOR" or _acao == "DESCER ELEVADOR":
		_alternar_elevador()
	elif _acao.begins_with("PEGAR") and _alvo_rack >= 0:
		_pegar(_alvo_rack)
	elif _acao == "DEVOLVER RODA":
		_soltar()
	elif _acao == "INSTALAR RODA" and _alvo_roda >= 0:
		_instalando = _alvo_roda
		_t_inst = 0.0
		_som_chave.global_position = m.rodas_vis[_alvo_roda].global_position
		_som_chave.play()


# ======================================================================= rodas
func _pegar(k: int) -> void:
	_soltar()
	segurando = str(aros_rack[k][1])
	(aros_rack[k][0] as Node3D).visible = false
	_na_mao = _aro_modelo(segurando, 0.33, 0.22)
	if _na_mao:
		# carrega na frente do peito (gira junto com o personagem)
		_mao = Node3D.new()
		m.pessoa.add_child(_mao)
		_mao.add_child(_na_mao)
		_na_mao.position = Vector3(0, 1.0, 0.42)
		_na_mao.rotation.y = -PI / 2.0     # face pra frente
	m.pessoa.carregando = true
	m.toast("PEGOU: " + str(aros_rack[k][2]).to_upper() + " — LEVA ATÉ O CARRO", 2.4)


func _soltar() -> void:
	if segurando == "":
		return
	for a in aros_rack:
		if a[1] == segurando:
			(a[0] as Node3D).visible = true
	if _mao:
		_mao.queue_free()
		_mao = null
	_na_mao = null
	segurando = ""
	m.pessoa.carregando = false


func _instalar(dt: float) -> void:
	if _instalando < 0:
		barra.visible = false
		return
	var i := _instalando
	var roda: Node3D = m.rodas_vis[i]
	if m.pessoa.global_position.distance_to(roda.global_position) > 2.2 or not carro_alto:
		_instalando = -1
		_som_chave.stop()
		barra.visible = false
		m.toast("SAIU DE PERTO: NÃO INSTALOU")
		return
	_t_inst += dt
	barra.visible = true
	barra.value = _t_inst / T_INSTALAR * 100.0
	var tela := m.get_viewport().get_visible_rect().size
	barra.position = Vector2((tela.x - barra.size.x) / 2.0, tela.y * 0.62)
	if _t_inst >= T_INSTALAR:
		# (modo história) cada roda é 1/4 do jogo (aro 16 pra baixo R$ 1 mil, 17-22 R$ 6 mil, 23+ R$ 10 mil)
		var custo_r := int(Dados.custo_roda(int(Dados.cfg().get("aro", 15))) / 4)
		if not Dados.pagar(custo_r):
			_instalando = -1
			barra.visible = false
			m.toast("SEM DINHEIRO: a roda custa " + Dados.reais(custo_r), 2.0)
			return
		_trocar_roda(i, segurando)
		instaladas[i] = segurando
		_instalando = -1
		barra.visible = false
		# v32: cada roda fica salva na hora (descer o elevador não desfaz mais nada)
		var rs: Array = []
		for k in 4:
			rs.append(m.visual.id_roda(k))
		rs[i] = segurando
		var feitas := 0
		for r in rs:
			if r == segurando:
				feitas += 1
		if feitas >= 4:
			Dados.mudar("roda", segurando)        # jogo completo: vira o "roda" normal
		else:
			Dados.mudar("rodas", rs)
		m.cfg = Dados.cfg()
		m.visual.c = m.cfg
		if feitas >= 4:
			var nome := segurando
			for a in aros_rack:
				if a[1] == segurando:
					nome = str(a[2])
					(a[0] as Node3D).visible = true
			if _mao:
				_mao.queue_free()
				_mao = null
			_na_mao = null
			segurando = ""
			m.pessoa.carregando = false
			instaladas = ["", "", "", ""]
			m.toast("JOGO %s INSTALADO! PODE DESCER O ELEVADOR" % nome.to_upper(), 3.0)
		else:
			m.toast("RODA %d DE 4 INSTALADA (JÁ FICA SALVA)" % feitas, 1.6)


## troca o aro de uma roda só (as outras ficam como estão até terminar o jogo)
func _trocar_roda(i: int, id: String) -> void:
	var velho: Node3D = m.rodas_vis[i]
	var lado := -1.0 if i % 2 == 0 else 1.0
	var c_antes: Dictionary = m.visual.c
	var c2: Dictionary = c_antes.duplicate()
	c2["roda"] = id
	m.visual.c = c2
	var nova: Node3D = m.visual.nova_roda(lado, -1, i < 2)
	m.visual.c = c_antes
	m.corpo_vis.add_child(nova)
	nova.transform = velho.transform
	velho.queue_free()
	m.rodas_vis[i] = nova


## desceu o elevador: o que foi instalado fica (já está salvo roda por roda)
func _conferir_jogo_incompleto() -> void:
	instaladas = ["", "", "", ""]


# ======================================================================= pintura
func abrir_pintura() -> void:
	if m.carro == null:
		return
	if m.pessoa.global_position.distance_to(m.carro.global_position) > 30.0:
		m.toast("TRAZ O CARRO PRA OFICINA PRA PINTAR", 2.2)
		return
	pintando = true
	# começa olhando do lado de onde você está (da cabine pro carro)
	var de: Vector3 = m.pessoa.global_position - _centro_carro()
	_cam_ang = atan2(de.x, de.z) - 0.8
	_cam_alt = 1.0
	if painel_pintura == null:
		_montar_painel()
	painel_pintura.visible = true
	_encher_painel()
	m.pe_botoes.visible = false
	m.stick.visible = false
	m.partes_box.visible = false


func fechar_pintura() -> void:
	pintando = false
	if painel_pintura:
		painel_pintura.visible = false
	m._estilo_ar()


func _montar_painel() -> void:
	painel_pintura = PanelContainer.new()
	var e := StyleBoxFlat.new()
	e.bg_color = Color(0.04, 0.04, 0.06, 0.88)
	e.border_color = AMARELO
	e.set_border_width_all(3)
	e.set_corner_radius_all(14)
	e.content_margin_left = 18
	e.content_margin_right = 18
	e.content_margin_top = 14
	e.content_margin_bottom = 14
	painel_pintura.add_theme_stylebox_override("panel", e)
	m.hud.add_child(painel_pintura)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	painel_pintura.add_child(v)
	var tit := Label.new()
	tit.text = "CABINE DE PINTURA"
	tit.add_theme_font_size_override("font_size", 28)
	tit.add_theme_color_override("font_color", AMARELO)
	v.add_child(tit)
	var rol := ScrollContainer.new()
	rol.custom_minimum_size = Vector2(420, 430)
	rol.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(rol)
	_conteudo = VBoxContainer.new()
	_conteudo.add_theme_constant_override("separation", 8)
	_conteudo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rol.add_child(_conteudo)
	var pronto := Button.new()
	pronto.text = "PRONTO"
	pronto.focus_mode = Control.FOCUS_NONE
	pronto.custom_minimum_size = Vector2(0, 60)
	pronto.add_theme_font_size_override("font_size", 24)
	var sp := StyleBoxFlat.new()
	sp.bg_color = AMARELO
	sp.set_corner_radius_all(10)
	pronto.add_theme_stylebox_override("normal", sp)
	pronto.add_theme_stylebox_override("hover", sp)
	pronto.add_theme_stylebox_override("pressed", sp)
	pronto.add_theme_color_override("font_color", Color.BLACK)
	pronto.add_theme_color_override("font_hover_color", Color.BLACK)
	pronto.add_theme_color_override("font_pressed_color", Color.BLACK)
	pronto.pressed.connect(fechar_pintura)
	v.add_child(pronto)
	painel_pintura.position = Vector2(24, 112)


func _titulo(t: String) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", AMARELO)
	_conteudo.add_child(l)


func _encher_painel() -> void:
	for n in _conteudo.get_children():
		n.queue_free()
	var c := Dados.cfg()
	# (fase 2) o que pintar: o carro todo ou uma peça só (porta de outra cor, capô...)
	var v: CarroVisual = m.visual
	var ids := []
	for id in v.pecas:
		if v.tem_peca(id):
			ids.append(id)
	if not ids.has(_alvo_pintura):
		_alvo_pintura = ""
	var cp: Dictionary = c.get("cores_pecas", {})
	if not ids.is_empty():
		_titulo("O que pintar")
		var gp := GridContainer.new()
		gp.columns = 2
		gp.add_theme_constant_override("h_separation", 8)
		gp.add_theme_constant_override("v_separation", 8)
		_conteudo.add_child(gp)
		for id in [""] + ids:
			var b := Button.new()
			b.text = "CARRO TODO" if id == "" else v.nome_peca(id)
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(0, 46)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 15)
			var marcado: bool = id == _alvo_pintura
			var s: StyleBoxFlat = m._estilo(AMARELO if marcado else Color(0.1, 0.1, 0.12, 0.9), AMARELO if marcado else Color(1, 1, 1, 0.25))
			if id != "" and cp.has(id) and not marcado:
				s.border_color = Color(str(cp[id]))   # peça com cor própria: borda da cor dela
				s.set_border_width_all(3)
			b.add_theme_stylebox_override("normal", s)
			b.add_theme_stylebox_override("hover", s)
			b.add_theme_color_override("font_color", Color.BLACK if marcado else Color.WHITE)
			b.pressed.connect(func(): _alvo_pintura = id; _encher_painel())
			gp.add_child(b)
	_servico(v)
	if _alvo_pintura != "":
		_titulo("Cor: " + v.nome_peca(_alvo_pintura).to_lower())
		_cores(Dados.CORES, "peca:" + _alvo_pintura, str(cp.get(_alvo_pintura, c["cor"])))
		var igual := Button.new()
		igual.text = "IGUAL AO RESTO DO CARRO"
		igual.focus_mode = Control.FOCUS_NONE
		igual.custom_minimum_size = Vector2(0, 46)
		igual.add_theme_font_size_override("font_size", 16)
		igual.pressed.connect(_mudar.bind("peca:" + _alvo_pintura, ""))
		_conteudo.add_child(igual)
		return   # acabamento é do carro todo: aparece só no "CARRO TODO"
	_titulo("Cor")
	_cores(Dados.CORES, "cor", str(c["cor"]))
	_titulo("Acabamento")
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	_conteudo.add_child(g)
	for o in Dados.ACABAMENTOS:
		var b := Button.new()
		b.text = o[1]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 50)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 17)
		var marcado: bool = o[0] == str(c.get("acabamento", "metal"))
		var s: StyleBoxFlat = m._estilo(AMARELO if marcado else Color(0.1, 0.1, 0.12, 0.9), AMARELO if marcado else Color(1, 1, 1, 0.25))
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_stylebox_override("hover", s)
		b.add_theme_color_override("font_color", Color.BLACK if marcado else Color.WHITE)
		b.pressed.connect(_mudar.bind("acabamento", o[0]))
		g.add_child(b)
	if c.get("acabamento", "") in ["perola", "camaleao"]:
		_titulo("Cor do reflexo")
		_cores(Dados.CORES2, "cor2", str(c.get("cor2", "")))


## (fase 2) serviço de funilaria antes da tinta: lavar, lixar a ferrugem, desamassar (do carro todo ou de uma peça)
const SERVICOS := [["s", "Sujeira", "LAVAR"], ["f", "Ferrugem", "LIXAR"], ["a", "Amassado", "DESAMASSAR"]]

func _servico(v: CarroVisual) -> void:
	var alvo := "carro" if _alvo_pintura == "" else _alvo_pintura
	var dg := v.desgaste(alvo)
	if _alvo_pintura == "":
		for id in v.pecas:   # no carro todo, conta o pior de todas as peças
			var dp := v.desgaste(id)
			for k in dg:
				dg[k] = maxf(dg[k], dp[k])
	if dg["f"] + dg["s"] + dg["a"] < 0.01:
		return
	_titulo("Serviço" + ("" if _alvo_pintura == "" else ": " + v.nome_peca(_alvo_pintura).to_lower()))
	for sv in SERVICOS:
		var val: float = dg[sv[0]]
		if val < 0.01:
			continue
		var linha := HBoxContainer.new()
		linha.add_theme_constant_override("separation", 10)
		_conteudo.add_child(linha)
		var lb := Label.new()
		lb.text = "%s %d%%" % [sv[1], roundi(val * 100.0)]
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lb.add_theme_font_size_override("font_size", 17)
		lb.add_theme_color_override("font_color", Color(1, 0.55, 0.35) if val > 0.5 else Color(1, 0.85, 0.5))
		linha.add_child(lb)
		var b := Button.new()
		b.text = sv[2]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 44)
		b.add_theme_font_size_override("font_size", 16)
		var s: StyleBoxFlat = m._estilo(AMARELO, AMARELO)
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_stylebox_override("hover", s)
		b.add_theme_color_override("font_color", Color.BLACK)
		b.pressed.connect(_fazer_servico.bind(alvo, str(sv[0]), str(sv[2])))
		linha.add_child(b)


## onde o boneco fica pra mexer numa peça (ou no carro todo): do lado de fora, virado pra ela
func _posto_de_trabalho(alvo: String) -> Array:
	var v: CarroVisual = m.visual
	var centro := _centro_carro()
	var chao_y: float = m.pessoa.global_position.y
	var olhar := centro
	var ponto: Vector3
	if alvo != "carro" and v.pecas.has(alvo):
		olhar = v.centro_peca(alvo)
		var dir := olhar - centro
		dir.y = 0.0
		if dir.length() < 0.05:
			dir = m.carro.global_basis.z
		ponto = olhar + dir.normalized() * 0.75
	else:
		# carro todo: o lado do carro mais perto de onde a pessoa está
		var lado: Vector3 = m.carro.global_basis.x
		if (m.pessoa.global_position - centro).dot(lado) < 0.0:
			lado = -lado
		ponto = centro + lado * (float(m.dados["W"]) / 2.0 + 0.6)
	ponto.y = chao_y
	return [ponto, olhar]


var _pintando_ja := false

## serviço: [animação, segundos, texto, ferramenta na mão]
const ANIM_SERVICO := {"s": ["Interact", 5.0, "LAVANDO", "esponja"], "f": ["Interact", 5.0, "LIXANDO", "lixadeira"],
	"a": ["Idle_Torch", 5.0, "PUXANDO O AMASSADO", "spotter"]}

func _fazer_servico(alvo: String, chave: String, nome: String) -> void:
	if m.pessoa and m.pessoa.ocupado():
		return
	# (modo história) o material do serviço sai do seu bolso
	var custo := Dados.custo_servico(chave, alvo != "carro")
	if not Dados.pagar(custo):
		m.toast("SEM DINHEIRO: " + nome + " custa " + Dados.reais(custo), 2.0)
		return
	var v: CarroVisual = m.visual
	var antes: Dictionary = (Dados.cfg().get("desgaste", {}) as Dictionary).duplicate(true)
	var dg: Dictionary = antes.duplicate(true)
	if alvo == "carro":
		# carro todo: zera aquilo no corpo e em todas as peças
		for k in dg.keys():
			(dg[k] as Dictionary)[chave] = 0.0
		if not dg.has("carro"):
			dg["carro"] = {chave: 0.0}
	else:
		var atual := v.desgaste(alvo)
		atual[chave] = 0.0
		dg[alvo] = atual
	var fim := func():
		if _som_chave:
			_som_chave.global_position = _centro_carro()
			_som_chave.play()
		m.toast({"LAVAR": "LAVADO! ", "LIXAR": "FERRUGEM LIXADA! ", "DESAMASSAR": "DESAMASSADO! "}.get(nome, "") + "Agora é só pintar.", 1.6)
		_mudar("desgaste", dg)
	if m.pessoa == null or not Pessoa.e_ual(m.pessoa.modelo):
		fim.call()
		return
	# o boneco vai até lá e trabalha; o desgaste some aos poucos enquanto ele faz o serviço
	var an: Array = ANIM_SERVICO[chave]
	var posto := _posto_de_trabalho(alvo)
	var passo := [0]
	var prog := func(k: float):
		var n := int(k * 10.0)
		if n == passo[0]:
			return
		passo[0] = n
		var meio := _misturar_desgaste(antes, dg, k)
		v.c["desgaste"] = meio
		v._aplicar_cores_pecas()
		m.toast("%s... %d%%" % [an[2], roundi(k * 100.0)], 0.6)
	m.pessoa.trabalhar(posto[0], posto[1], str(an[0]), float(an[1]), fim, prog, str(an[3]))


## desgaste no meio do serviço (k = 0 antes, 1 pronto)
func _misturar_desgaste(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out := {}
	var v: CarroVisual = m.visual
	var ids := ["carro"]
	ids.append_array(v.pecas.keys())
	for id in ids:
		var va := _dg_de(a, str(id))
		var vb := _dg_de(b, str(id))
		out[id] = {"f": lerpf(va["f"], vb["f"], k), "s": lerpf(va["s"], vb["s"], k), "a": lerpf(va["a"], vb["a"], k)}
	return out


func _dg_de(dg: Dictionary, id: String) -> Dictionary:
	var base: Dictionary = dg.get("carro", {})
	var r := {"f": float(base.get("f", 0.0)), "s": float(base.get("s", 0.0)), "a": float(base.get("a", 0.0))}
	if id != "carro" and dg.has(id):
		for k in r:
			if (dg[id] as Dictionary).has(k):
				r[k] = float(dg[id][k])
	return r


func _cores(lista: Array, chave: String, atual: String) -> void:
	var g := GridContainer.new()
	g.columns = 6
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	_conteudo.add_child(g)
	for cor in lista:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = cor[0]
		b.custom_minimum_size = Vector2(56, 56)
		var marcado: bool = str(cor[1]).to_lower() == atual.to_lower()
		var s := StyleBoxFlat.new()
		s.bg_color = Color(cor[1])
		s.border_color = AMARELO if marcado else Color("44444c")
		s.set_border_width_all(4 if marcado else 1)
		s.set_corner_radius_all(30)
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_stylebox_override("hover", s)
		b.add_theme_stylebox_override("pressed", s)
		b.pressed.connect(_mudar.bind(chave, cor[1]))
		g.add_child(b)
	var livre := ColorPickerButton.new()
	livre.text = "QUALQUER COR"
	livre.focus_mode = Control.FOCUS_NONE
	livre.custom_minimum_size = Vector2(0, 50)
	livre.add_theme_font_size_override("font_size", 17)
	livre.color = Color(atual) if atual.begins_with("#") else Color.WHITE
	livre.edit_alpha = false
	var pk := livre.get_picker()
	pk.picker_shape = ColorPicker.SHAPE_VHS_CIRCLE
	pk.presets_visible = false
	pk.sampler_visible = false
	pk.color_modes_visible = false
	livre.popup_closed.connect(func(): _mudar(chave, "#" + livre.color.to_html(false)))
	_conteudo.add_child(livre)


func _mudar(chave: String, valor) -> void:
	# pintar de verdade: o boneco vai com a pistola e a cor nova só aparece no fim da demão
	if (chave in ["cor", "cor2", "acabamento"] or chave.begins_with("peca:")) and m.pessoa and Pessoa.e_ual(m.pessoa.modelo) and not _pintando_ja:
		if m.pessoa.ocupado():
			return
		# (modo história) tinta: carro todo = preço cheio (pelo tamanho do carro), uma peça = 20%
		var custo_t := Dados.custo_pintura(m.dados)
		if chave.begins_with("peca:") or (_alvo_pintura != "" and chave == "cor"):
			custo_t = int(round(custo_t * Dados.PINTURA_PECA_FRACAO / 100.0) * 100)
		if not Dados.pagar(custo_t):
			m.toast("SEM DINHEIRO: a tinta custa " + Dados.reais(custo_t), 2.0)
			return
		var cor_tinta := Color(str(valor)) if str(valor).begins_with("#") else Color(str(Dados.cfg().get("cor", "#ffffff")))
		var alvo := chave.substr(5) if chave.begins_with("peca:") else ("carro" if _alvo_pintura == "" else _alvo_pintura)
		var posto := _posto_de_trabalho(alvo if m.visual.pecas.has(alvo) else "carro")
		var c2 := chave
		var v2 = valor
		var prog := func(k: float):
			var n := int(k * 10.0)
			m.toast("PINTANDO... %d%%" % (n * 10), 0.6)
		var fim := func():
			_pintando_ja = true
			_mudar(c2, v2)
			_pintando_ja = false
			m.toast("PINTADO!", 1.2)
		m.pessoa.trabalhar(posto[0], posto[1], "Idle_Torch", 4.5, fim, prog, "pistola", cor_tinta)   # braço esticado com a pistola, varrendo
		return
	if chave.begins_with("peca:"):
		# cor de uma peça só: guarda no dicionário de cores das peças ("" = volta pra cor do carro)
		var id := chave.substr(5)
		var cp: Dictionary = (Dados.cfg().get("cores_pecas", {}) as Dictionary).duplicate()
		if str(valor) == "":
			cp.erase(id)
		else:
			cp[id] = valor
		chave = "cores_pecas"
		valor = cp
	Dados.mudar(chave, valor)
	m.cfg = Dados.cfg()
	m.visual.atualizar(m.cfg)
	if painel_pintura and painel_pintura.visible:
		_encher_painel()



func _unhandled_input(e: InputEvent) -> void:
	if not pintando:
		return
	var rel := Vector2.ZERO
	if e is InputEventScreenDrag:
		rel = (e as InputEventScreenDrag).relative
	elif e is InputEventMouseMotion and ((e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT):
		rel = (e as InputEventMouseMotion).relative
	if rel != Vector2.ZERO:
		_cam_ang -= rel.x * 0.008
		_cam_alt = clampf(_cam_alt + rel.y * 0.006, 0.2, 2.2)


var _cam_alt := 1.0


## câmera da pintura: olha pro carro (sem atravessar parede); gira só quando você arrasta
func camera(dt: float) -> bool:
	if laje and laje.sinuca.camera(dt):
		return true
	if not pintando or m.carro == null:
		return false
	# a câmera fica parada; arrastando o dedo/mouse na tela (fora do menu) ela gira em volta do carro
	var foco := _centro_carro() + Vector3.UP * 0.7
	var dir := Vector3(sin(_cam_ang + 0.8), 0, cos(_cam_ang + 0.8))
	var alvo := foco + dir * 5.2 + Vector3.UP * _cam_alt
	var ray := PhysicsRayQueryParameters3D.create(foco, alvo)
	ray.exclude = [m.carro.get_rid(), m.pessoa.get_rid()]
	var hit: Dictionary = m.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		alvo = foco + (Vector3(hit["position"]) - foco) * 0.85
	m.cam_pos = m.cam_pos.lerp(alvo, 1.0 - exp(-dt * 4.0))
	m.cam.global_position = m.cam_pos
	m.cam.look_at(foco, Vector3.UP)
	return true
