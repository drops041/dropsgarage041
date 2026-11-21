class_name Texturas
## Texturas de verdade (fotos PBR da Poly Haven, licença CC0, pasta texturas/):
## cor (_diff), AO/aspereza/metal juntos (_arm) e relevo (_nor). Projeção "triplanar" no mundo:
## serve em qualquer caixa sem esticar. metros = tamanho de um ladrilho da foto.

static var _cache := {}


static func material(nome: String, metros := 2.5, tom := Color.WHITE, aspereza := 1.0, relevo := 1.0) -> StandardMaterial3D:
	var chave := "%s|%s|%s|%s|%s" % [nome, metros, tom, aspereza, relevo]
	if _cache.has(chave):
		return _cache[chave]
	var base := "res://texturas/" + nome
	var m := StandardMaterial3D.new()
	if not ResourceLoader.exists(base + "_diff.jpg"):
		m.albedo_color = tom * Color(0.45, 0.45, 0.45)
		m.roughness = 0.7
		return m
	m.albedo_texture = load(base + "_diff.jpg")
	m.albedo_color = tom
	var arm: Texture2D = load(base + "_arm.jpg")
	m.ao_enabled = true
	m.ao_texture = arm
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.ao_light_affect = 0.3
	m.roughness_texture = arm
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = aspereza
	m.metallic = 0.0
	if ResourceLoader.exists(base + "_nor.jpg"):
		m.normal_enabled = true
		m.normal_texture = load(base + "_nor.jpg")
		m.normal_scale = relevo
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / metros
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[chave] = m
	return m
