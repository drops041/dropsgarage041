extends Node3D
## pinta cada material de uma cor pra achar defeito no modelo. DROPS_CARRO=id DROPS_FOTO=arq.png
func _ready() -> void:
	var id := OS.get_environment("DROPS_CARRO")
	var m: Node3D = load("res://modelos/carros/%s.glb" % id).instantiate()
	add_child(m)
	var cores := {"material": Color.RED, "Color_008": Color.GREEN, "INTERIOR__escuro": Color(0.1, 0.2, 1.0), "INTERIOR__caixa_roda": Color.YELLOW, "Diego": Color.MAGENTA, "preto__spec_1": Color.CYAN, "001__spec_1": Color.ORANGE, "0133_Gray": Color(0.5,0.3,0.1), "MASCARA__farol": Color(0.4,0,0.4), "PAINT__material_1__liso": Color.WHITE}
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			var nome := mat.resource_name if mat else ""
			if cores.has(nome):
				var sm := StandardMaterial3D.new()
				sm.albedo_color = cores[nome]
				if nome == "INTERIOR__caixa_roda": sm.cull_mode = BaseMaterial3D.CULL_DISABLED
				(mi as MeshInstance3D).set_surface_override_material(s, sm)
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-40, 60, 0)
	add_child(l)
	var e := WorldEnvironment.new()
	e.environment = Environment.new()
	e.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	e.environment.background_mode = Environment.BG_COLOR
	e.environment.background_color = Color(0.3, 0.3, 0.32)
	add_child(e)
	var c := Camera3D.new()
	add_child(c)
	c.position = Vector3(1.9, 0.45, 2.7)
	c.look_at(Vector3(0.8, 0.3, 1.5))
	c.fov = 45
	c.current = true
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("DROPS_FOTO"))
	c.position = Vector3(2.0, 0.6, -1.9)
	c.look_at(Vector3(0.85, 0.35, -1.4))
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("DROPS_FOTO").replace(".png", "_tras.png"))
	get_tree().quit()
