extends Node3D
## Cena de teste do mapa: câmera livre pra passear pela CIC.
## PC: WASD anda, Q/E desce/sobe, botão direito do mouse olha, Shift corre, N alterna dia/noite.
## Celular: arraste com um dedo pra olhar, segure com dois dedos pra andar pra frente.

var cam: Camera3D
var sol: DirectionalLight3D
var amb: WorldEnvironment
var mapa: MapaCIC
var rot := Vector2.ZERO
var noite := false
var _toques := {}
var info: Label


func _ready() -> void:
	cam = Camera3D.new()
	cam.far = 1500.0
	cam.fov = 70.0
	add_child(cam)
	sol = DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-50, 35, 0)
	sol.shadow_enabled = true
	sol.directional_shadow_max_distance = 180.0
	add_child(sol)
	amb = WorldEnvironment.new()
	var env := Environment.new()
	var ceu := Sky.new()
	ceu.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = ceu
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.0012
	env.glow_enabled = true
	amb.environment = env
	add_child(amb)
	mapa = MapaCIC.new()
	mapa.alvo = cam
	add_child(mapa)
	cam.global_position = mapa.posicao_spawn() + Vector3(0, 1.6, 0)
	rot.y = cam.global_rotation.y
	info = Label.new()
	info.position = Vector2(12, 8)
	add_child(info)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		rot.y -= ev.relative.x * 0.004
		rot.x = clamp(rot.x - ev.relative.y * 0.004, -1.4, 1.4)
	elif ev is InputEventScreenDrag:
		_toques[ev.index] = true
		if _toques.size() == 1:
			rot.y -= ev.relative.x * 0.006
			rot.x = clamp(rot.x - ev.relative.y * 0.006, -1.4, 1.4)
	elif ev is InputEventScreenTouch:
		if ev.pressed:
			_toques[ev.index] = true
		else:
			_toques.erase(ev.index)
	elif ev is InputEventKey and ev.pressed and ev.keycode == KEY_N:
		_trocar_dia_noite()


func _trocar_dia_noite() -> void:
	noite = not noite
	var env := amb.environment
	var sm := env.sky.sky_material as ProceduralSkyMaterial
	if noite:
		sol.light_energy = 0.05
		sm.sky_top_color = Color(0.02, 0.03, 0.08)
		sm.sky_horizon_color = Color(0.08, 0.07, 0.12)
		sm.ground_horizon_color = Color(0.05, 0.05, 0.07)
		env.ambient_light_energy = 0.25
	else:
		sol.light_energy = 1.0
		sm.sky_top_color = Color(0.38, 0.45, 0.68)
		sm.sky_horizon_color = Color(0.65, 0.67, 0.7)
		sm.ground_horizon_color = Color(0.65, 0.67, 0.7)
		env.ambient_light_energy = 1.0


func _process(dt: float) -> void:
	cam.rotation = Vector3(rot.x, rot.y, 0)
	var v := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): v.z -= 1
	if Input.is_key_pressed(KEY_S): v.z += 1
	if Input.is_key_pressed(KEY_A): v.x -= 1
	if Input.is_key_pressed(KEY_D): v.x += 1
	if Input.is_key_pressed(KEY_Q): v.y -= 1
	if Input.is_key_pressed(KEY_E): v.y += 1
	if _toques.size() >= 2: v.z -= 1
	var vel := 60.0 if Input.is_key_pressed(KEY_SHIFT) else 14.0
	cam.global_position += cam.global_basis * v * vel * dt
	cam.global_position.y = max(cam.global_position.y, mapa.altura(cam.global_position.x, cam.global_position.z) + 0.5)
	info.text = "FPS %d   pos %.0f, %.0f   (N = dia/noite)" % [Engine.get_frames_per_second(), cam.global_position.x, cam.global_position.z]
