extends Node3D
func _ready() -> void:
	for i in Dados.carros.size():
		var d: Dictionary = Dados.carros[i]
		var cv := CarroVisual.new()
		add_child(cv)
		cv.montar(d, (d["padrao"] as Dictionary).duplicate(true))
		Acessorios._forma.erase(str(d["id"]))
		var f := Acessorios.forma(cv)
		var topo: PackedFloat32Array = f["topo"]
		var atras := float(f["fim_teto"]) - float(f["z0"])
		var y30 := Acessorios.altura(f, float(f["z0"]) + 0.3)
		print("forma %-14s sedan=%s atras=%.2f teto=%.2f h30=%.2f h60=%.2f h90=%.2f h120=%.2f" % [d["id"], f["sedan"], atras, f["teto"], y30, Acessorios.altura(f, float(f["z0"]) + 0.6), Acessorios.altura(f, float(f["z0"]) + 0.9), Acessorios.altura(f, float(f["z0"]) + 1.2)])
		cv.free()
	get_tree().quit()
