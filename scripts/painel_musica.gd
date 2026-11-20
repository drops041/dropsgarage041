class_name PainelMusica
extends PanelContainer
## Painelzinho da música (garagem e rua): tocar/parar, trocar de música e volume só da música.

var nome: Label
var play: Button
var vol_l: Label
var barra: HSlider
var graf: Button


func _init() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.06, 0.92)
	sb.border_color = Color("ffd400")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sb)
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	nome = Label.new()
	nome.add_theme_font_size_override("font_size", 18)
	nome.add_theme_color_override("font_color", Color("ffd400"))
	nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(nome)
	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 8)
	col.add_child(linha)
	var ant := _botao(linha, "<<", 64)
	play = _botao(linha, "TOCAR", 130)
	var prox := _botao(linha, ">>", 64)
	vol_l = Label.new()
	vol_l.add_theme_font_size_override("font_size", 16)
	col.add_child(vol_l)
	var vlinha := HBoxContainer.new()
	vlinha.add_theme_constant_override("separation", 8)
	col.add_child(vlinha)
	var menos := _botao(vlinha, "−", 52)
	barra = HSlider.new()
	barra.min_value = 0
	barra.max_value = 100
	barra.step = 5
	barra.custom_minimum_size = Vector2(150, 40)
	barra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	barra.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	barra.focus_mode = Control.FOCUS_NONE
	vlinha.add_child(barra)
	var mais := _botao(vlinha, "+", 52)
	graf = _botao(col, "", 260)
	graf.pressed.connect(_graficos)
	ant.pressed.connect(_anterior)
	play.pressed.connect(_tocar)
	prox.pressed.connect(_proxima)
	barra.value_changed.connect(_barra)
	menos.pressed.connect(_menos)
	mais.pressed.connect(_mais)
	visibility_changed.connect(atualiza)


func _ready() -> void:
	# ligado a um método deste painel: quando o painel some (troca de tela), a ligação some junto
	Dados.musica.finished.connect(_acabou)
	atualiza()


func _botao(pai: Node, t: String, largura: int) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(largura, 52)
	b.add_theme_font_size_override("font_size", 22)
	pai.add_child(b)
	return b


func _graficos() -> void:
	Dados.graficos = "leve" if Dados.graficos != "leve" else "alto"
	Dados.salvar()
	atualiza()
	var cena := get_tree().current_scene
	if cena and cena.has_method("aplicar_graficos"):
		cena.aplicar_graficos()


func atualiza() -> void:
	if nome == null:
		return
	if graf:
		graf.text = "GRÁFICOS: " + ("ALTO" if Dados.graficos != "leve" else "LEVE")
	nome.text = "♫ " + Dados.nome_musica()
	play.text = "PARAR" if Dados.musica.playing else "TOCAR"
	vol_l.text = "Volume da música: %d%%" % roundi(Dados.volume_musica * 100.0)
	barra.set_value_no_signal(roundf(Dados.volume_musica * 100.0))


func _acabou() -> void:
	atualiza.call_deferred()


func _anterior() -> void:
	Dados.proxima_musica(-1)
	atualiza()


func _proxima() -> void:
	Dados.proxima_musica(1)
	atualiza()


func _tocar() -> void:
	Dados.tocar_musica(not Dados.musica.playing)
	atualiza()


func _barra(v: float) -> void:
	Dados.mudar_volume(v / 100.0)
	atualiza()


func _menos() -> void:
	Dados.mudar_volume(Dados.volume_musica - 0.1)
	atualiza()


func _mais() -> void:
	Dados.mudar_volume(Dados.volume_musica + 0.1)
	atualiza()
