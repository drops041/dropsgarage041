extends "res://mapa_cic/teste_mapa.gd"
## fotos do chão do mapa perto da Drops (grama). DROPS_FOTO=/tmp/x.png ; DROPS_SEM_GRAMA=1 = sem a foto de grama
func _ready() -> void:
	super._ready()
	mapa.raio_carregar = 160.0
	mapa.raio_descarregar = 260.0
	if OS.get_environment("DROPS_SEM_GRAMA") != "":
		mapa._grama = null
	set_process(false)
	await get_tree().create_timer(14.0).timeout
	var base := cam.global_position
	var k := 0
	for v in [[Vector3(0, 1.2, 0), 0.0, -0.35], [Vector3(0, 1.2, 0), 1.6, -0.35], [Vector3(0, 1.2, 0), 3.1, -0.35], [Vector3(0, 1.2, 0), -1.6, -0.35]]:
		cam.global_position = base + v[0]
		cam.rotation = Vector3(v[2], v[1], 0)
		await get_tree().create_timer(2.5).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("DROPS_FOTO").replace(".png", "_%d.png" % k))
		k += 1
	get_tree().quit()
