extends Node3D
## monta o carro igual no jogo (CarroVisual) e fotografa o para-lama. DROPS_CARRO=id DROPS_FOTO=arq.png
## DROPS_VERDE=1 pinta o plástico (Color_008) de verde pra ver quem aparece por cima
func _ready() -> void:
	var id := OS.get_environment("DROPS_CARRO")
	var dd: Dictionary = {}
	for x in Dados.carros:
		if x["id"] == id:
			dd = x
	var v := CarroVisual.new()
	add_child(v)
	v.montar(dd, Dados.cfg_padrao(dd) if Dados.has_method("cfg_padrao") else Dados.cfg())
	if OS.get_environment("DROPS_VERDE") != "":
		for mi in v.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null: continue
			for s in m.mesh.get_surface_count():
				var mat := m.mesh.surface_get_material(s)
				var modo := OS.get_environment("DROPS_VERDE")
				if mat and modo == "2" and mat.resource_name.begins_with("PAINT"):
					var sr := StandardMaterial3D.new()
					sr.albedo_color = Color.RED
					sr.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					m.set_surface_override_material(s, sr)
				if mat and modo == "1" and mat.resource_name == "Color_008":
					var sm := StandardMaterial3D.new()
					sm.albedo_color = Color.GREEN
					sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					m.set_surface_override_material(s, sm)
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
	c.fov = 45
	c.current = true
	var f := OS.get_environment("DROPS_FOTO")
	var vistas := [[Vector3(2.0, 0.6, 1.9), Vector3(0.85, 0.35, 1.4)], [Vector3(2.0, 0.6, -1.9), Vector3(0.85, 0.35, -1.4)], [Vector3(4.5, 1.5, 3.5), Vector3(0, 0.5, 0.3)]]
	for k in vistas.size():
		c.position = vistas[k][0]
		c.look_at(vistas[k][1])
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png(f.replace(".png", "_%d.png" % k))
	get_tree().quit()
