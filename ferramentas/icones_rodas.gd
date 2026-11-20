extends SceneTree
## Gera o ícone (128x128, fundo transparente) das rodas da loja.
## Uso: godot --path . -s res://ferramentas/icones_rodas.gd -- jerez jettagli ...

var fila: Array = []
var vp: SubViewport
var raiz: Node3D
var quadros := 0


func _initialize() -> void:
	fila = Array(OS.get_cmdline_user_args())
	vp = SubViewport.new()
	vp.size = Vector2i(256, 256)
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.76, 0.8)
	env.ambient_light_energy = 0.9
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.25
	cam.transform = Transform3D(Basis.IDENTITY, Vector3(3.0, 0.35, 1.25)).looking_at(Vector3.ZERO)
	vp.add_child(cam)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-35, 60, 0)
	sol.light_energy = 1.3
	vp.add_child(sol)
	var sol2 := DirectionalLight3D.new()
	sol2.rotation_degrees = Vector3(-10, 130, 0)
	sol2.light_energy = 0.5
	vp.add_child(sol2)
	_proxima()


func _proxima() -> void:
	if raiz:
		raiz.queue_free()
		raiz = null
	if fila.is_empty():
		quit()
		return
	var id: String = fila[0]
	raiz = load("res://modelos/rodas/%s.glb" % id).instantiate()
	for n in raiz.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var orig := m.mesh.surface_get_material(i)
			var nome := orig.resource_name
			var mat := StandardMaterial3D.new()
			if orig is BaseMaterial3D and (orig as BaseMaterial3D).albedo_texture:
				mat.albedo_texture = (orig as BaseMaterial3D).albedo_texture
				mat.normal_enabled = true
				mat.normal_texture = (orig as BaseMaterial3D).normal_texture
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.metallic = 0.75
			mat.roughness = 0.28 if nome != "BARREL" else 0.5
			mat.albedo_color = Color(0.86, 0.87, 0.9) if nome != "BARREL" else Color(0.45, 0.45, 0.48)
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.set_surface_override_material(i, mat)
	vp.add_child(raiz)
	quadros = 0


func _process(_dt: float) -> bool:
	if raiz == null:
		return false
	quadros += 1
	if quadros == 4:
		var img := vp.get_texture().get_image()
		img.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		img.save_png("res://modelos/rodas/icones/%s.png" % fila[0])
		print("ícone: ", fila[0])
		fila.pop_front()
		_proxima()
	return false
