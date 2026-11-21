extends Node
class_name Historia
## MODO HISTÓRIA na cidade (só existe com Dados.modo == "historia").
## Etapa 1: o Drafael (dono da Drafael Motors) chega na Drops Garage com uma G3 velha de garagem e pede o serviço:
## lavar, lixar a ferrugem, desamassar e pintar de vermelho. Você aceita e recebe na hora (peças x 1,5);
## cada serviço da cabine desconta o material do seu bolso; o que sobra é o seu lucro.
## Pronto o serviço, você leva a G3 até a Drafael Motors e entrega.

const AMARELO := Color("ffd400")
## o Drafael: camisa branca, calça preta, careca de barba
const VISUAL_DRAFAEL := {"cima": "camiseta", "cor_cima": "#ececea", "baixo": "calca", "cor_baixo": "#18181b",
	"cor_tenis": "#18181b", "cabelo": "careca", "barba": true, "cor_cabelo": "preto", "pele": "morena"}
## onde o Drafael espera, na entrada da oficina (coordenadas da Drops) e pra onde ele olha
const DRAFAEL_LOCAL := Vector3(0.7, 0.0, 14.4)    # no salão da oficina, na boca do corredor
const G3_LOCAL := Vector3(3.0, 0.6, 18.2)         # onde a G3 aparece quando você aceita (o mesmo lugar onde o carro sai)
const COR_PEDIDA := ["Vermelho", "#b5121b"]
const XP_SERVICO := 100

var m                  # Main
var drafael: Node3D
var _anim: AnimationPlayer
var camada: CanvasLayer
var botao: Button
var ficha: PanelContainer
var ficha_l: RichTextLabel
var dialogo: PanelContainer
var dialogo_l: Label
var dialogo_botoes: HBoxContainer
var _t := 0.0
var _acao := ""


func _ready() -> void:
	_ui()
	_atualizar_mundo()


# ---------------------------------------------------------------- o pedido
func servico() -> Dictionary:
	return Dados.historia.get("servico", {})


## o primeiro serviço: G3 do Drafael
func _pedido_g3() -> Dictionary:
	var i := Dados.indice_de("saveirog3")
	var d: Dictionary = Dados.carros[i]
	var itens := [
		{"id": "s", "nome": "Lavar", "custo": Dados.CUSTO_LAVAR},
		{"id": "f", "nome": "Lixar a ferrugem", "custo": Dados.CUSTO_LIXAR},
		{"id": "a", "nome": "Desamassar", "custo": Dados.CUSTO_DESAMASSAR},
		{"id": "cor", "nome": "Pintar de " + COR_PEDIDA[0].to_lower(), "cor": COR_PEDIDA[1], "custo": Dados.custo_pintura(d)},
	]
	var custo := 0
	for it in itens:
		custo += int(it["custo"])
	return {"carro": "saveirog3", "cliente": "Drafael", "itens": itens, "custo": custo,
		"pago": int(round(custo * Dados.HISTORIA_JURO)), "estado": "oferta"}


## cada item do pedido já foi feito? (olha o carro do serviço como está salvo)
func feitos() -> Array:
	var sv := servico()
	var out := []
	var i := Dados.indice_de(str(sv.get("carro", "")))
	if i < 0:
		return out
	var c := Dados.cfg(i)
	var dg: Dictionary = c.get("desgaste", {})
	for it in sv.get("itens", []):
		var ok := false
		if str(it["id"]) == "cor":
			ok = str(c.get("cor", "")).to_lower() == str(it["cor"]).to_lower() and (c.get("cores_pecas", {}) as Dictionary).is_empty()
		else:
			ok = true
			for parte in dg:   # carro todo e cada peça
				if float((dg[parte] as Dictionary).get(it["id"], 0.0)) > 0.03:
					ok = false
		out.append(ok)
	return out


# ---------------------------------------------------------------- o Drafael na oficina
func _atualizar_mundo() -> void:
	var etapa := str(Dados.historia.get("etapa", ""))
	var sv := servico()
	var esperando := etapa == "primeiro_carro" and str(sv.get("estado", "")) in ["", "oferta"]
	if esperando and drafael == null:
		_criar_drafael()
	elif not esperando and drafael:
		drafael.queue_free()
		drafael = null


func _criar_drafael() -> void:
	drafael = Pessoa.criar("res://modelos/personagens/protagonista.glb", 1.80)
	add_child(drafael)
	Pessoa.vestir(drafael, VISUAL_DRAFAEL)
	drafael.global_position = m.mapa.drops_ponto(DRAFAEL_LOCAL)
	var olha: Vector3 = m.mapa.drops_ponto(G3_LOCAL) - drafael.global_position   # olhando pro meio da oficina
	drafael.rotation.y = atan2(olha.x, olha.z)
	_anim = drafael.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		for n in ["drops/Idle", "drops/parado"]:
			if _anim.has_animation(n):
				_anim.play(n)
				break
	var nome := Label3D.new()
	nome.text = "DRAFAEL"
	nome.font_size = 48
	nome.pixel_size = 0.005
	nome.modulate = AMARELO
	nome.outline_size = 8
	nome.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nome.no_depth_test = true
	nome.position = Vector3(0, 2.15, 0)
	drafael.add_child(nome)


# ---------------------------------------------------------------- tela
func _botao(texto: String, amarelo := true) -> Button:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	var cor := AMARELO if amarelo else Color(0.05, 0.05, 0.07, 0.9)
	var s: StyleBoxFlat = m._estilo(cor, AMARELO if amarelo else Color(1, 1, 1, 0.4))
	for e in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(e, s)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, Color("111111") if amarelo else Color.WHITE)
	b.custom_minimum_size = Vector2(0, 56)
	return b


func _ui() -> void:
	camada = CanvasLayer.new()
	camada.layer = 6
	add_child(camada)
	# botão de ação (falar com o Drafael / entregar o carro)
	botao = _botao("")
	botao.visible = false
	botao.pressed.connect(_apertou)
	camada.add_child(botao)
	# ficha do serviço (canto de cima, do lado do mapa)
	ficha = PanelContainer.new()
	var est: StyleBoxFlat = m._estilo(Color(0.04, 0.04, 0.06, 0.82), Color(1, 1, 1, 0.3))
	est.content_margin_left = 12
	est.content_margin_right = 12
	est.content_margin_top = 8
	est.content_margin_bottom = 8
	ficha.add_theme_stylebox_override("panel", est)
	ficha.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ficha.visible = false
	camada.add_child(ficha)
	ficha_l = RichTextLabel.new()
	ficha_l.bbcode_enabled = true
	ficha_l.fit_content = true
	ficha_l.scroll_active = false
	ficha_l.custom_minimum_size = Vector2(300, 0)
	ficha_l.add_theme_font_size_override("normal_font_size", 16)
	ficha_l.add_theme_font_size_override("bold_font_size", 17)
	ficha_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ficha.add_child(ficha_l)
	# diálogo (fala do Drafael + botões)
	dialogo = PanelContainer.new()
	var ed: StyleBoxFlat = m._estilo(Color(0.04, 0.04, 0.06, 0.94), AMARELO)
	ed.content_margin_left = 22
	ed.content_margin_right = 22
	ed.content_margin_top = 16
	ed.content_margin_bottom = 16
	dialogo.add_theme_stylebox_override("panel", ed)
	dialogo.visible = false
	camada.add_child(dialogo)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	dialogo.add_child(v)
	var quem := Label.new()
	quem.text = "DRAFAEL · DRAFAEL MOTORS"
	quem.add_theme_font_size_override("font_size", 18)
	quem.add_theme_color_override("font_color", AMARELO)
	v.add_child(quem)
	dialogo_l = Label.new()
	dialogo_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogo_l.add_theme_font_size_override("font_size", 21)
	v.add_child(dialogo_l)
	dialogo_botoes = HBoxContainer.new()
	dialogo_botoes.add_theme_constant_override("separation", 12)
	v.add_child(dialogo_botoes)
	_posicionar()
	get_viewport().size_changed.connect(_posicionar)


func _posicionar() -> void:
	var t := get_viewport().get_visible_rect().size
	botao.size = Vector2(320, 60)
	botao.position = Vector2((t.x - botao.size.x) / 2.0, t.y - 210)
	ficha.position = Vector2(14, 196)   # embaixo do mapa e do botão da suspensão (o meio do topo é dos avisos)
	dialogo.size = Vector2(minf(t.x - 80, 760), 0)
	dialogo.position = Vector2((t.x - dialogo.size.x) / 2.0, t.y * 0.5 - 130)


func _falar(texto: String, botoes: Array) -> void:
	dialogo_l.text = texto
	for n in dialogo_botoes.get_children():
		n.queue_free()
	for b in botoes:   # [texto, Callable, amarelo?]
		var bt := _botao(str(b[0]), bool(b[2]) if b.size() > 2 else true)
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cb: Callable = b[1]
		bt.pressed.connect(func():
			dialogo.visible = false
			cb.call())
		dialogo_botoes.add_child(bt)
	dialogo.visible = true
	botao.visible = false


# ---------------------------------------------------------------- ações
func _apertou() -> void:
	match _acao:
		"falar":
			var p := _pedido_g3()
			var lista := ""
			for it in p["itens"]:
				lista += "\n  • " + str(it["nome"])
			_falar("Fala, parceiro! Eu sou o Drafael, da Drafael Motors. Tenho essa G3 véia de garagem aqui e preciso dela no capricho pra vender:" + lista +
				"\n\nTe pago " + Dados.reais(p["pago"]) + " adiantado. O material sai por tua conta (uns " + Dados.reais(p["custo"]) + "), o resto é teu lucro. Fechado?",
				[["ACEITAR", _aceitar], ["AGORA NÃO", func(): pass, false]])
		"entregar":
			_entregar()


func _aceitar() -> void:
	var p := _pedido_g3()
	p["estado"] = "fazendo"
	Dados.historia["servico"] = p
	Dados.dinheiro += int(p["pago"])
	Dados.idx = Dados.indice_de(str(p["carro"]))
	Dados.salvar()
	# a G3 aparece na entrada da oficina; o seu carro fica guardado (volta quando você entregar a G3)
	var saida: Vector3 = m.mapa.drops_xf.basis * Vector3(0, 0, -1)   # de frente pra saída, como o carro começa
	if m.pe:
		m._criar_carro(m.mapa.drops_ponto(G3_LOCAL), atan2(saida.x, saida.z))
	m.toast("+" + Dados.reais(p["pago"]) + "  ·  A G3 é tua até entregar!", 3.0)
	_atualizar_mundo()


func _entregar() -> void:
	var sv := servico()
	var lucro := int(sv.get("pago", 0)) - int(sv.get("custo", 0))
	sv["estado"] = "entregue"
	Dados.historia["xp"] = int(Dados.historia.get("xp", 0)) + XP_SERVICO
	Dados.historia["servicos_feitos"] = int(Dados.historia.get("servicos_feitos", 0)) + 1
	Dados.historia["etapa"] = "loja"
	Dados.historia.erase("servico")
	# volta pro seu carro, ali mesmo no pátio da loja
	var garagem: Array = Dados.historia.get("garagem", [])
	if not garagem.is_empty():
		Dados.idx = Dados.indice_de(str(garagem[garagem.size() - 1]))
	Dados.salvar()
	var pos: Vector3 = m.carro.global_position + Vector3.UP * 0.5
	var giro: float = m.carro.rotation.y
	m._criar_carro(pos, giro)
	_falar("Ficou TOP, parceiro! Essa G3 vai vender rapidinho.\nTeu lucro nesse serviço ficou em torno de " + Dados.reais(lucro) + " (depende do quanto você gastou de material).\n+" + str(XP_SERVICO) + " XP\n\nLogo eu trago mais serviço. E quando quiser trocar de carro, a loja é aqui!",
		[["VALEU!", func(): pass]])


# ---------------------------------------------------------------- todo frame
func _process(dt: float) -> void:
	_t += dt
	if _t < 0.2:
		return
	_t = 0.0
	_atualizar_mundo()
	_atualizar_ficha()
	_atualizar_botao()


func _atualizar_ficha() -> void:
	var sv := servico()
	if str(sv.get("estado", "")) not in ["fazendo", "pronto"]:
		ficha.visible = false
		return
	var f := feitos()
	var tudo := not f.is_empty() and not f.has(false)
	if tudo and sv["estado"] == "fazendo":
		sv["estado"] = "pronto"
		Dados.salvar()
		m.toast("SERVIÇO PRONTO! Leva a G3 pra Drafael Motors (C no mapa)", 4.0)
	var txt := "[b][color=#ffd400]SERVIÇO DO DRAFAEL · G3[/color][/b]\n"
	var itens: Array = sv.get("itens", [])
	for k in itens.size():
		var ok: bool = k < f.size() and f[k]
		txt += ("[color=#7dff8a]✔ " if ok else "[color=#ffffff]☐ ") + str(itens[k]["nome"]) + "[/color]\n"
	txt += "[color=#9aa0aa]Recebido: " + Dados.reais(int(sv.get("pago", 0))) + "[/color]"
	if sv["estado"] == "pronto":
		txt += "\n[b][color=#ffd400]Pronto! Entrega na Drafael Motors (C)[/color][/b]"
	ficha_l.text = txt
	ficha.visible = true


func _atualizar_botao() -> void:
	_acao = ""
	if dialogo.visible:
		botao.visible = false
		return
	var sv := servico()
	if drafael and m.pe and m.pessoa and m.pessoa.global_position.distance_to(drafael.global_position) < 2.6:
		_acao = "falar"
		botao.text = "FALAR COM O DRAFAEL"
	elif str(sv.get("estado", "")) == "pronto" and not m.pe and m.carro and m.mapa.tem("concessionaria") \
			and Dados.carro()["id"] == str(sv.get("carro", "")):
		var patio: Vector3 = m.mapa.xf("concessionaria") * Vector3(0, 0, 4.0)
		var d := Vector2(m.carro.global_position.x - patio.x, m.carro.global_position.z - patio.z).length()
		if d < 16.0 and m.carro.linear_velocity.length() < 2.0:
			_acao = "entregar"
			botao.text = "ENTREGAR A G3 PRO DRAFAEL"
	botao.visible = _acao != ""
