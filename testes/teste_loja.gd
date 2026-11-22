extends Node3D
## Teste visual da Drafael Motors sem a cidade (a cidade não cabe na memória do servidor de testes).
## Uso: godot --path . res://testes/teste_loja.tscn  (DROPS_FOTO=/pasta/%s.png tira as fotos e sai)

class FalsoMapa extends Node:
	func tem(_c: String) -> bool:
		return true
	func xf(_c: String) -> Transform3D:
		return Transform3D.IDENTITY


var pe := true
var pessoa: Node3D
var carro: Node3D = null
var historia = null
var mapa := FalsoMapa.new()
var cc: Concessionaria
var cam: Camera3D
var _t := 0.0
var _fotos := [["salao", Vector3(-6, 3.2, 6.5), Vector3(0, 0.6, -6)], ["patio", Vector3(0, 5.5, 16), Vector3(0, 0.5, 2)],
	["fundo", Vector3(9, 2.4, -1.0), Vector3(-3, 0.8, -11)], ["drafael", Vector3(2.5, 1.9, -5.2), Vector3(0, 1.0, -7.3)]]


func _ready() -> void:
	add_child(mapa)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.7, 0.85)
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sol)
	var chao := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	chao.mesh = pm
	chao.position.y = -0.4
	add_child(chao)
	pessoa = Node3D.new()
	add_child(pessoa)
	pessoa.position = Vector3(0, 0, 10)
	cc = Concessionaria.new()
	cc.m = self
	add_child(cc)
	cam = Camera3D.new()
	cam.fov = 70
	add_child(cam)
	cam.current = true


func _process(dt: float) -> void:
	_t += dt
	var n := 0
	for v in cc.vagas:
		if v["cv"] != null:
			n += 1
	if n < cc.vagas.size():
		return
	var k := int((_t - 12.0) / 1.5)
	if _t < 12.0 or k < 0:
		return
	if k >= _fotos.size() * 2:
		get_tree().quit()
		return
	var f: Array = _fotos[k / 2]
	cam.global_position = f[1]
	cam.look_at(f[2])
	if k % 2 == 1 and OS.has_environment("DROPS_FOTO"):
		get_viewport().get_texture().get_image().save_png(OS.get_environment("DROPS_FOTO") % f[0])
