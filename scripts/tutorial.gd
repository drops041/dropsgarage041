class_name Tutorial
extends PanelContainer
## (v36) dicas rápidas na primeira vez que o jogo abre (dá pra pular). Depois não aparece mais.

const PASSOS := [
	["DIRIGIR", "Gire o VOLANTE (esquerda) pra virar.\nACELERA e FREIO ficam na direita. DRIFT pra escorregar de traseira."],
	["SUSPENSÃO A AR", "O botão da mola (na esquerda) abre o controle do ar:\nsobe e desce o carro. Baixou demais? Raspa nas lombadas!"],
	["A PÉ", "Aperte A PÉ pra sair do carro e andar com o joystick.\nNa oficina, chegue perto das coisas e use o botão AMARELO:\npegar roda na parede, subir o elevador, instalar, pintar na cabine."],
	["MAPA", "O mapa fica no canto de cima, na esquerda. Toque nele pra abrir grande.\nD = Drops   N = barracão (carros novos)   E = encontro   C = concessionária   B = blitz"],
	["GARAGEM E MÚSICA", "GARAGEM: monta o carro (cor, rodas, altura, som).\nMÚSICA: troca a faixa, o volume e a qualidade do gráfico (ALTO ou LEVE)."],
]

var _i := 0
var _titulo: Label
var _texto: Label
var _botao: Button


func _ready() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.04, 0.06, 0.92)
	s.border_color = Color("ffd400")
	s.set_border_width_all(3)
	s.set_corner_radius_all(14)
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 18
	s.content_margin_bottom = 18
	add_theme_stylebox_override("panel", s)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	_titulo = Label.new()
	_titulo.add_theme_font_size_override("font_size", 30)
	_titulo.add_theme_color_override("font_color", Color("ffd400"))
	col.add_child(_titulo)
	_texto = Label.new()
	_texto.add_theme_font_size_override("font_size", 21)
	_texto.custom_minimum_size = Vector2(620, 0)
	_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_texto)
	var linha := HBoxContainer.new()
	linha.alignment = BoxContainer.ALIGNMENT_END
	linha.add_theme_constant_override("separation", 14)
	col.add_child(linha)
	var pular := _b("PULAR")
	pular.pressed.connect(_fim)
	linha.add_child(pular)
	_botao = _b("PRÓXIMO")
	_botao.pressed.connect(_proximo)
	linha.add_child(_botao)
	_mostrar()


func _b(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(170, 56)
	b.add_theme_font_size_override("font_size", 22)
	return b


func _mostrar() -> void:
	_titulo.text = "%s   (%d/%d)" % [PASSOS[_i][0], _i + 1, PASSOS.size()]
	_texto.text = PASSOS[_i][1]
	_botao.text = "BORA!" if _i == PASSOS.size() - 1 else "PRÓXIMO"
	reset_size()
	var t := get_viewport().get_visible_rect().size
	position = Vector2((t.x - size.x) / 2.0, t.y * 0.3)


func _proximo() -> void:
	_i += 1
	if _i >= PASSOS.size():
		_fim()
	else:
		_mostrar()


func _fim() -> void:
	Dados.tutorial_feito = true
	Dados.salvar()
	queue_free()
