class_name Laje
extends Node3D
## (v40) LAJE ABERTA em cima da casa da Drops (sobe pela escada marinheiro do corredor).
## Mesa de sinuca jogável, sofá, varal de lâmpadas, vasos e caixa térmica.
## Coordenadas: as da oficina (mesmas do drops_garage.py com x invertido).

const Y := 3.14                                  # piso da laje
const X0 := -5.2
const X1 := -0.8
const Z0 := 6.0
const Z1 := 12.5
const ESC_BAIXO := Vector3(-0.25, 0.0, 11.8)     # pé da escada (no corredor)
const ESC_TOPO := Vector3(-1.35, Y, 11.8)        # onde você chega lá em cima
const MESA := Vector3(-3.0, Y, 9.55)
const AMARELO := Color("ffd400")

var m: Node                                      # main.gd
var of: Node                                     # oficina.gd
var sinuca: Sinuca
var subindo := false                             # no meio da escada


func _ready() -> void:
	sinuca = Sinuca.new()
	sinuca.position = MESA
	add_child(sinuca)
	sinuca.montar(m)
	_sofa()
	_varal()
	_enfeites()
	_seguranca()


func _mat(cor: Color, rug := 0.8, brilho := 0.0) -> StandardMaterial3D:
	var s := StandardMaterial3D.new()
	s.albedo_color = cor
	s.roughness = rug
	if brilho > 0.0:
		s.emission_enabled = true
		s.emission = cor
		s.emission_energy_multiplier = brilho
	return s


func _caixa(tam: Vector3, p: Vector3, mat: Material, giro := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = tam
	mi.mesh = bm
	mi.material_override = mat
	mi.position = p
	mi.rotation.y = giro
	mi.visibility_range_end = 90.0
	add_child(mi)
	return mi


func _bloquear(tam: Vector3, centro: Vector3) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = tam
	cs.shape = bx
	sb.add_child(cs)
	sb.position = centro
	add_child(sb)


# ----------------------------------------------------------------------- móveis
func _sofa() -> void:
	var tecido := _mat(Color(0.13, 0.13, 0.15), 0.95)
	var almofada := _mat(Color(0.18, 0.18, 0.2), 0.95)
	var pe := _mat(Color(0.05, 0.05, 0.05), 0.5)
	var cx := -3.0
	var z := 6.55
	_caixa(Vector3(2.2, 0.3, 0.86), Vector3(cx, Y + 0.25, z), tecido)                  # base
	_caixa(Vector3(2.2, 0.5, 0.22), Vector3(cx, Y + 0.6, z - 0.33), tecido)             # encosto
	for s in [-1.0, 1.0]:
		_caixa(Vector3(0.2, 0.28, 0.86), Vector3(cx + s * 1.0, Y + 0.52, z), tecido)    # braços
	for k in 3:
		_caixa(Vector3(0.58, 0.12, 0.62), Vector3(cx - 0.6 + k * 0.6, Y + 0.45, z + 0.07), almofada)
	for s in [-1.0, 1.0]:
		var al := _caixa(Vector3(0.4, 0.36, 0.12), Vector3(cx + s * 0.62, Y + 0.68, z - 0.17), _mat(AMARELO, 0.9))
		al.rotation = Vector3(-0.25, s * 0.15, s * 0.08)
		for sz in [-1.0, 1.0]:
			_caixa(Vector3(0.06, 0.1, 0.06), Vector3(cx + s * 1.02, Y + 0.05, z + sz * 0.36), pe)
	_bloquear(Vector3(2.2, 0.9, 0.9), Vector3(cx, Y + 0.45, z))
	# tapete
	_caixa(Vector3(2.6, 0.01, 1.4), Vector3(cx, Y + 0.006, 7.6), _mat(Color(0.32, 0.12, 0.1), 1.0))


func _varal() -> void:
	# postes de ferro no fundo; na frente o varal fica preso na parede do sobrado
	var ferro := _mat(Color(0.05, 0.05, 0.06), 0.5)
	var no_varal := Node3D.new()
	add_child(no_varal)
	sinuca.esconder_jogando.append(no_varal)
	var ganchos := [Vector3(-1.0, Y + 2.3, Z0 + 0.04), Vector3(-3.0, Y + 2.3, Z0 + 0.04), Vector3(-5.0, Y + 2.3, Z0 + 0.04)]
	var postes := [Vector3(-1.0, Y, Z1 - 0.15), Vector3(-3.0, Y, Z1 - 0.15), Vector3(-5.0, Y, Z1 - 0.15)]
	for p in postes:
		_caixa(Vector3(0.06, 2.5, 0.06), p + Vector3(0, 1.25, 0), ferro)
	var fios := [[ganchos[0], postes[2]], [ganchos[2], postes[0]], [ganchos[1], postes[1]]]
	var lampadas: Array[Vector3] = []
	var cabo := _mat(Color(0.03, 0.03, 0.03), 0.6)
	for f in fios:
		var a: Vector3 = f[0]
		var b: Vector3 = (f[1] as Vector3) + Vector3(0, 2.45, 0)
		var n := int(a.distance_to(b) / 0.42)
		var ant := a
		for k in range(1, n + 1):
			var t := float(k) / n
			var p := a.lerp(b, t) + Vector3.DOWN * 0.45 * 4.0 * t * (1.0 - t)    # barriga do fio
			var meio := (ant + p) / 2.0
			var seg := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.012, 0.012, ant.distance_to(p))
			seg.mesh = bm
			seg.material_override = cabo
			seg.transform = Transform3D(Basis.looking_at((p - ant).normalized(), Vector3.UP), meio)
			seg.visibility_range_end = 90.0
			no_varal.add_child(seg)
			if k < n:
				lampadas.append(p + Vector3.DOWN * 0.05)
			ant = p
	# lâmpadas: uma malha só pra todas (leve)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var esf := SphereMesh.new()
	esf.radius = 0.035
	esf.height = 0.08
	esf.radial_segments = 8
	esf.rings = 4
	mm.mesh = esf
	mm.instance_count = lampadas.size()
	for i in lampadas.size():
		mm.set_instance_transform(i, Transform3D(Basis(), lampadas[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat(Color(1.0, 0.82, 0.5), 0.3, 4.0)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 220.0
	no_varal.add_child(mmi)
	# luz quente em cima da mesa (a do varal) e uma geral fraquinha
	var luz := OmniLight3D.new()
	luz.position = MESA + Vector3(0, 2.1, 0)
	luz.light_color = Color(1.0, 0.86, 0.62)
	luz.light_energy = 1.6
	luz.omni_range = 5.5
	luz.shadow_enabled = false
	add_child(luz)


func _enfeites() -> void:
	# caixa térmica do lado do sofá
	_caixa(Vector3(0.55, 0.4, 0.38), Vector3(-4.55, Y + 0.2, 6.6), _mat(Color(0.75, 0.08, 0.08), 0.5))
	_caixa(Vector3(0.57, 0.06, 0.4), Vector3(-4.55, Y + 0.43, 6.6), _mat(Color(0.95, 0.95, 0.95), 0.5))
	_bloquear(Vector3(0.6, 0.5, 0.42), Vector3(-4.55, Y + 0.25, 6.6))
	# caixinha de som com a logo amarela
	_caixa(Vector3(0.4, 0.62, 0.34), Vector3(-1.45, Y + 0.31, 6.45), _mat(Color(0.04, 0.04, 0.04), 0.6))
	for yy in [0.2, 0.45]:
		var cone := _caixa(Vector3(0.24, 0.24, 0.02), Vector3(-1.45, Y + yy, 6.63), _mat(Color(0.12, 0.12, 0.12), 0.4))
		cone.rotation.z = PI / 4.0
	_caixa(Vector3(0.3, 0.04, 0.02), Vector3(-1.45, Y + 0.58, 6.63), _mat(AMARELO, 0.6, 1.5))
	_bloquear(Vector3(0.42, 0.64, 0.36), Vector3(-1.45, Y + 0.32, 6.45))
	# vasos com planta nos cantos do fundo
	for x in [-1.2, -4.8]:
		var vaso := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.22
		cm.bottom_radius = 0.16
		cm.height = 0.45
		vaso.mesh = cm
		vaso.material_override = _mat(Color(0.55, 0.3, 0.2), 0.9)
		vaso.position = Vector3(x, Y + 0.225, 12.1)
		add_child(vaso)
		var folha := _mat(Color(0.12, 0.42, 0.14), 0.8)
		for k in 7:
			var a := TAU * k / 7.0
			var fo := _caixa(Vector3(0.07, 0.75, 0.02), Vector3(x + cos(a) * 0.08, Y + 0.75, 12.1 + sin(a) * 0.08), folha)
			fo.rotation = Vector3(sin(a) * 0.45, -a, cos(a) * 0.45)
		_bloquear(Vector3(0.45, 0.9, 0.45), Vector3(x, Y + 0.45, 12.1))
	# suporte de tacos na parede do sobrado
	var madeira := _mat(Color(0.3, 0.15, 0.07), 0.5)
	_caixa(Vector3(0.8, 0.08, 0.06), Vector3(-4.6, Y + 1.5, Z0 + 0.05), madeira)
	for k in 4:
		var tc := _caixa(Vector3(0.025, 1.4, 0.025), Vector3(-4.88 + k * 0.18, Y + 0.85, Z0 + 0.09), _mat(Color(0.8, 0.6, 0.35), 0.4))
		tc.rotation.z = 0.04


## parede invisível em volta (o guarda-corpo segura, isto é só garantia)
func _seguranca() -> void:
	var h := 1.3
	_bloquear(Vector3(0.1, h, (11.5 - Z0)), Vector3(X1 + 0.02, Y + h / 2.0, (Z0 + 11.5) / 2.0))
	_bloquear(Vector3(0.1, h, (Z1 - 12.1)), Vector3(X1 + 0.02, Y + h / 2.0, (12.1 + Z1) / 2.0))
	_bloquear(Vector3(X1 - X0, h, 0.1), Vector3((X0 + X1) / 2.0, Y + h / 2.0, Z1 + 0.02))
	_bloquear(Vector3(0.1, h, Z1 - Z0), Vector3(X0 - 0.02, Y + h / 2.0, (Z0 + Z1) / 2.0))


# ----------------------------------------------------------------------- ações
func acao(l: Vector3) -> String:
	if subindo or sinuca.ativo:
		return ""
	if l.y < 1.2 and Vector2(l.x - ESC_BAIXO.x, l.z - ESC_BAIXO.z).length() < 0.95:
		return "SUBIR NA LAJE"
	if l.y > 2.6:
		if Vector2(l.x - ESC_TOPO.x, l.z - ESC_TOPO.z).length() < 0.9:
			return "DESCER DA LAJE"
		if absf(l.x - MESA.x) < 1.35 and absf(l.z - MESA.z) < 1.9:
			return "JOGAR SINUCA"
	return ""


func fazer(a: String) -> void:
	if a == "SUBIR NA LAJE":
		_escada(true)
	elif a == "DESCER DA LAJE":
		_escada(false)
	elif a == "JOGAR SINUCA":
		sinuca.entrar()


## sobe/desce a escada: o boneco vai de frente pra parede, degrau por degrau
func _escada(subir: bool) -> void:
	var p: Pessoa = m.pessoa
	if p == null or subindo:
		return
	subindo = true
	p.set_physics_process(false)
	p.velocity = Vector3.ZERO
	p._tem_p = false
	var xf: Transform3D = of.xf
	var parede: Vector3 = (xf.basis * Vector3(-1, 0, 0)).normalized()     # de frente pra escada
	if p.modelo:
		p.modelo.rotation.y = atan2(parede.x, parede.z)
	var pe_esc := Vector3(-0.32, 0.0, 11.8)
	var pts: Array = []
	if subir:
		pts = [[pe_esc + Vector3(0, 0.02, 0), 0.3], [pe_esc + Vector3(0, Y + 0.12, 0), 2.6], [ESC_TOPO + Vector3(0, 0.05, 0), 0.7]]
	else:
		pts = [[Vector3(-0.32, Y + 0.12, 11.8), 0.7], [pe_esc + Vector3(0, 0.02, 0), 2.4], [ESC_BAIXO + Vector3(0, 0.05, 0), 0.4]]
	p._tocar("anda")
	if p.anim:
		p.anim.speed_scale = 0.75
	var tw := create_tween()
	for q in pts:
		tw.tween_property(p, "global_position", xf * (q[0] as Vector3), float(q[1]))
	tw.tween_callback(func():
		p.set_physics_process(true)
		p.velocity = Vector3.ZERO
		subindo = false)
