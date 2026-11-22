extends Node3D
## fotografa um .glb qualquer de alguns ângulos. DROPS_GLB=res://... DROPS_FOTO=/tmp/x.png DROPS_VISTAS="px,py,pz,ax,ay,az;..."
func _ready() -> void:
	var m: Node3D = load(OS.get_environment("DROPS_GLB")).instantiate()
	add_child(m)
	var e := WorldEnvironment.new()
	e.environment = Environment.new()
	e.environment.background_mode = Environment.BG_COLOR
	e.environment.background_color = Color(0.2, 0.2, 0.22)
	e.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.environment.ambient_light_color = Color(0.3, 0.3, 0.33)
	e.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	add_child(e)
	for p in [Vector3(-2.5, 3.6, 0), Vector3(2.5, 3.6, 0)]:
		var l := OmniLight3D.new()
		l.position = p
		l.omni_range = 9.0
		l.light_energy = 1.0
		add_child(l)
	var c := Camera3D.new()
	c.fov = 70
	add_child(c)
	c.current = true
	var k := 0
	for v in OS.get_environment("DROPS_VISTAS").split(";"):
		var n := v.split_floats(",")
		c.position = Vector3(n[0], n[1], n[2])
		c.look_at(Vector3(n[3], n[4], n[5]))
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("DROPS_FOTO").replace(".png", "_%d.png" % k))
		k += 1
	get_tree().quit()
