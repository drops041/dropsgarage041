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
## (21/11) o Drafael espera LÁ FORA, na calçada em frente ao portão, com a G3 estacionada atrás dele
## (coordenadas da Drops: x pra esquerda de quem olha da rua, z pra dentro do lote; o portão fica em z = 0)
const DRAFAEL_LOCAL := Vector3(1.0, 0.0, -2.3)    # na calçada, olhando pro portão
const G3_LOCAL := Vector3(2.4, 0.6, -5.8)         # a G3 parada na rua, de frente pro portão
const CHAMAR_CADA := 25.0                         # de quanto em quanto tempo ele chama (s)
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
var _quem: Label
var clandestina: Clandestina
var pc: Node3D
var pc_painel: PanelContainer
var _pc_aba := "motor"
var _pc_conteudo: VBoxContainer
var _avisou_pc := false
var aba_ficha: Button          # setinha na lateral que abre/fecha a ficha do serviço
var _ficha_aberta := false
var g3_parada: CarroVisual     # a G3 do Drafael parada na rua (só enfeite, até você aceitar)
var _chamou := -100.0
## o PC da oficina: mesinha encostada na parede da cabine, perto da porta (coordenadas da Drops)
const PC_LOCAL := Vector3(0.05, 0.0, 25.3)


func _ready() -> void:
	_ui()
	_pc_ui()
	_montar_pc()
	clandestina = Clandestina.new()
	clandestina.m = m
	add_child(clandestina)
	if Dados.historia.get("clandestina_marcada", false):
		clandestina.ativar.call_deferred()
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


## 2º serviço: Vambora do Drafael pra rodas aro 17, suspensão a ar e socar (um carro mais caro que a G3)
func _pedido_vambora() -> Dictionary:
	var i := Dados.indice_de("bora")
	var rmax := CarroVisual.rebaixo_max(Dados.carros[i])
	var reb := int(minf(14.0, rmax))
	var itens := [
		{"id": "aro", "nome": "Rodas aro 17", "valor": 17, "custo": Dados.custo_roda(17)},
		{"id": "ar", "nome": "Suspensão a ar", "custo": Dados.CUSTO_SUSPENSAO},
		{"id": "rebaixo", "nome": "Socar: %d cm ou mais (frente e trás)" % reb, "valor": reb, "custo": 0},
	]
	var custo := 0
	for it in itens:
		custo += int(it["custo"])
	return {"carro": "bora", "nome_carro": "Vambora", "cliente": "Drafael", "itens": itens, "custo": custo,
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
		elif str(it["id"]) == "aro":
			ok = int(c.get("aro", 0)) == int(it["valor"])
		elif str(it["id"]) == "ar":
			ok = bool(c.get("ar", false))
		elif str(it["id"]) == "rebaixo":
			ok = bool(c.get("ar", false)) and float(c.get("rebaixo", 0.0)) >= float(it["valor"]) - 0.01 \
				and float(c.get("rebaixo_tras", 0.0)) >= float(it["valor"]) - 0.01
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
	if not esperando and g3_parada:
		g3_parada.queue_free()
		g3_parada = null


func _criar_drafael() -> void:
	drafael = Pessoa.criar("res://modelos/personagens/protagonista.glb", 1.80)
	add_child(drafael)
	Pessoa.vestir(drafael, VISUAL_DRAFAEL)
	drafael.global_position = _no_chao(DRAFAEL_LOCAL, 0.0)
	var olha: Vector3 = m.mapa.drops_ponto(Vector3(2.3, 0, 3.0)) - drafael.global_position   # olhando pro portão
	drafael.rotation.y = atan2(olha.x, olha.z)
	# a G3 velha estacionada atrás dele, de frente pro portão
	var i := Dados.indice_de("saveirog3")
	if i >= 0:
		g3_parada = CarroVisual.new()
		add_child(g3_parada)
		g3_parada.montar(Dados.carros[i], Dados.cfg(i))
		g3_parada.global_position = _no_chao(G3_LOCAL, 0.0)
		g3_parada.rotation.y = _giro_pro_portao()
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


## ponto da Drops no chão de verdade (a rua fica mais baixa que o lote)
func _no_chao(local: Vector3, acima: float) -> Vector3:
	var p: Vector3 = m.mapa.drops_ponto(Vector3(local.x, 0, local.z))
	return m.mapa.no_chao(p, acima)


## giro de quem está na rua olhando pro portão
func _giro_pro_portao() -> float:
	var dentro: Vector3 = m.mapa.drops_xf.basis * Vector3(0, 0, 1)
	return atan2(dentro.x, dentro.z)


## enquanto você não vai lá fora, ele chama de tempos em tempos
func _chamar() -> void:
	if drafael == null or dialogo.visible:
		return
	var voce: Vector3 = m.pessoa.global_position if m.pe and m.pessoa else (m.carro.global_position if m.carro else Vector3.ZERO)
	var dist := voce.distance_to(drafael.global_position)
	var agora := Time.get_ticks_msec() / 1000.0
	if dist < 9.0:
		if not m.pe and agora - _chamou > 8.0:
			_chamou = agora
			m.toast("Desce do carro pra falar com o Drafael", 3.0)
		return
	if agora - _chamou > CHAMAR_CADA:
		_chamou = agora
		m.toast("Drafael (lá fora, no portão): \"Ô parceiro! Chega aqui fora!\"", 4.0)


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
	# a ficha fica escondida: uma setinha na lateral esquerda abre e fecha
	aba_ficha = Button.new()
	aba_ficha.focus_mode = Control.FOCUS_NONE
	aba_ficha.add_theme_font_size_override("font_size", 17)
	var ea: StyleBoxFlat = m._estilo(Color(0.04, 0.04, 0.06, 0.85), AMARELO)
	ea.corner_radius_top_left = 0
	ea.corner_radius_bottom_left = 0
	for e in ["normal", "hover", "pressed"]:
		aba_ficha.add_theme_stylebox_override(e, ea)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		aba_ficha.add_theme_color_override(c, AMARELO)
	aba_ficha.custom_minimum_size = Vector2(0, 52)
	aba_ficha.visible = false
	aba_ficha.pressed.connect(func():
		_ficha_aberta = not _ficha_aberta
		_atualizar_ficha())
	camada.add_child(aba_ficha)
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
	_quem = Label.new()
	_quem.text = "DRAFAEL · DRAFAEL MOTORS"
	_quem.add_theme_font_size_override("font_size", 18)
	_quem.add_theme_color_override("font_color", AMARELO)
	v.add_child(_quem)
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
	# setinha colada na borda esquerda, no meio da altura; a ficha abre do lado dela
	aba_ficha.position = Vector2(0, t.y * 0.55)   # embaixo do botão da suspensão, em cima do joystick
	ficha.position = Vector2(aba_ficha.position.x + 150, t.y * 0.30)
	dialogo.size = Vector2(minf(t.x - 80, 760), 0)
	dialogo.position = Vector2((t.x - dialogo.size.x) / 2.0, t.y * 0.5 - 130)


func _falar(texto: String, botoes: Array, titulo := "DRAFAEL · DRAFAEL MOTORS") -> void:
	_quem.text = titulo
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
				[["ACEITAR", _aceitar.bind({})], ["AGORA NÃO", func(): pass, false]])
		"entregar":
			_entregar()
		"pc":
			abrir_pc()
		"correr":
			clandestina.largar()
		"falar_loja":
			_conversa_loja()
		"ver_carro":
			_ver_carro(_carro_visto)


func _aceitar(p: Dictionary = {}) -> void:
	if p.is_empty():
		p = _pedido_g3()
	p["estado"] = "fazendo"
	Dados.historia["servico"] = p
	Dados.dinheiro += int(p["pago"])
	Dados.idx = Dados.indice_de(str(p["carro"]))
	Dados.salvar()
	# a G3 aparece na entrada da oficina; o seu carro fica guardado (volta quando você entregar a G3)
	# a G3 que estava parada na rua vira o carro do serviço: entra nela e leva pra dentro da oficina
	if g3_parada:
		g3_parada.queue_free()
		g3_parada = null
	if m.pe:
		m._criar_carro(_no_chao(G3_LOCAL, 0.6), _giro_pro_portao())
	m.toast("+" + Dados.reais(p["pago"]) + "  ·  Entra na G3 e leva ela pra dentro da oficina!", 4.0)
	_atualizar_mundo()


func _entregar() -> void:
	var pend := custo_pintura_anotada()
	if pend > 0:
		Dados.dinheiro -= pend
		Dados.historia.erase("pintura")
	var sv := servico()
	var lucro := int(sv.get("pago", 0)) - int(sv.get("custo", 0))
	sv["estado"] = "entregue"
	Dados.historia["xp"] = int(Dados.historia.get("xp", 0)) + XP_SERVICO
	Dados.historia["servicos_feitos"] = int(Dados.historia.get("servicos_feitos", 0)) + 1
	var primeiro := int(Dados.historia["servicos_feitos"]) == 1
	Dados.historia["etapa"] = "volta_oficina" if primeiro else "loja"
	Dados.historia.erase("servico")
	# volta pro seu carro, ali mesmo no pátio da loja
	var garagem: Array = Dados.historia.get("garagem", [])
	if not garagem.is_empty():
		Dados.idx = Dados.indice_de(str(garagem[garagem.size() - 1]))
	Dados.salvar()
	var pos: Vector3 = m.carro.global_position + Vector3.UP * 0.5
	var giro: float = m.carro.rotation.y
	m._criar_carro(pos, giro)
	var prox := "Já tenho mais um: um Vambora pra pôr aro 17 e suspensão a ar, socado. Volta pra tua oficina e dá uma olhada no PC, que tá tudo lá." if primeiro \
		else "Logo eu trago mais serviço. E quando quiser trocar de carro, a loja é aqui!"
	_falar("Ficou TOP, parceiro! Esse carro vai vender rapidinho.\nTeu lucro nesse serviço ficou em torno de " + Dados.reais(lucro) + " (depende do quanto você gastou de material).\n+" + str(XP_SERVICO) + " XP\n\n" + prox,
		[["VALEU!", func(): pass]])


# ---------------------------------------------------------------- loja: comprar, vender, trocar (22/11)
var _carro_visto := {}


func _drafael_loja_perto() -> bool:
	var cc = m.concessionaria
	if cc == null or cc.drafael == null or not cc.drafael.visible or not (m.pe and m.pessoa):
		return false
	return m.pessoa.global_position.distance_to(cc.drafael.global_position) < 2.8


func _meus_carros() -> Array:
	return (Dados.historia.get("garagem", []) as Array).duplicate()


func _conversa_loja() -> void:
	m.concessionaria.atender(m.pessoa)
	var meus := _meus_carros()
	_falar("Fala, parceiro! Aqui tem um de cada, pode olhar à vontade: chega perto do carro e aperta VER.\n" +
		"Se quiser, eu pego o teu usado: pago 70% da tabela + 40% do que você gastou de peça nele.\n\nTeu saldo: " + Dados.reais(Dados.dinheiro),
		[["VENDER UM CARRO MEU", _menu_vender, true], ["SÓ OLHANDO", func(): pass, false]])
	if meus.size() <= 1:
		dialogo_l.text += "\n(Você só tem um carro: pra vender ele, compra outro antes ou faz a troca direto no carro novo.)"


func _menu_vender() -> void:
	var meus := _meus_carros()
	var bts := []
	for id in meus:
		var i := Dados.indice_de(str(id))
		if i < 0:
			continue
		bts.append([str(Dados.carros[i]["nome"]) + " · " + Dados.reais(Dados.valor_revenda(str(id))), _vender.bind(str(id)), true])
	bts.append(["VOLTAR", func(): pass, false])
	if meus.size() <= 1:
		_falar("Você só tem esse carro. Compra outro primeiro (ou faz a troca direto no carro que quiser).", [["OK", func(): pass, false]])
		return
	_falar("Qual você quer vender? (o valor já é o que eu te pago)", bts)


func _vender(id: String) -> void:
	var nome := str(Dados.carros[Dados.indice_de(id)]["nome"])
	var valor := Dados.valor_revenda(id)
	var era_o_atual: bool = str(Dados.carro()["id"]) == id
	if not Dados.vender(id):
		_falar("Não deu pra vender esse.", [["OK", func(): pass, false]])
		return
	if era_o_atual and m.carro:   # vendeu o carro que estava usando: o outro aparece no pátio
		_carro_no_patio()
	_falar("Fechado! " + nome + " é meu agora. Tá aqui: " + Dados.reais(valor) + ".\nSaldo: " + Dados.reais(Dados.dinheiro),
		[["VALEU!", func(): pass]])


## carro de exposição: preço e as opções de compra (à vista ou dando o seu na troca)
func _ver_carro(v: Dictionary) -> void:
	if v.is_empty():
		return
	var i: int = v["i"]
	var d: Dictionary = Dados.carros[i]
	var id := str(d["id"])
	var preco := int(d.get("preco", 0))
	var texto := str(d["nome"]) + " · " + str(d.get("sub", "")) + "\nPreço: " + Dados.reais(preco) + "\nSeu saldo: " + Dados.reais(Dados.dinheiro)
	if Dados.tem_carro(id):
		_falar(texto + "\n\nEsse você já tem!", [["OK", func(): pass, false]], "DRAFAEL MOTORS")
		return
	var bts := []
	if Dados.dinheiro >= preco:
		bts.append(["COMPRAR À VISTA", _comprar.bind(i, ""), true])
	var atual := str(Dados.carro()["id"])
	if (Dados.historia.get("garagem", []) as Array).has(atual):
		var troca := Dados.valor_revenda(atual)
		var nome_atual := str(Dados.carro()["nome"])
		texto += "\n\nNa troca, teu " + nome_atual + " vale " + Dados.reais(troca) + "."
		if Dados.dinheiro + troca >= preco:
			var falta := maxi(0, preco - troca)
			bts.append(["TROCAR PELO MEU " + nome_atual.to_upper() + (" (+ " + Dados.reais(falta) + ")" if falta > 0 else ""), _comprar.bind(i, atual), true])
		else:
			texto += " Ainda falta " + Dados.reais(preco - troca - Dados.dinheiro) + "."
	if bts.is_empty():
		texto += "\n\nAinda não dá: junta mais dinheiro fazendo serviço e ganhando racha."
	bts.append(["SÓ OLHANDO", func(): pass, false])
	_falar(texto, bts, "DRAFAEL MOTORS")


func _comprar(i: int, troca_id: String) -> void:
	var nome := str(Dados.carros[i]["nome"])
	var preco := int(Dados.carros[i].get("preco", 0))
	var credito := Dados.valor_revenda(troca_id) if troca_id != "" else 0
	if Dados.dinheiro + credito < preco or Dados.tem_carro(str(Dados.carros[i]["id"])):
		_falar("Não deu: falta " + Dados.reais(preco - credito - Dados.dinheiro) + ".", [["OK", func(): pass, false]])
		return
	if troca_id != "":
		var g: Array = Dados.historia.get("garagem", [])
		# vende o seu (deixa vender mesmo sendo o único: a troca já põe o novo no lugar)
		Dados.dinheiro += Dados.valor_revenda(troca_id)
		g.erase(troca_id)
		Dados.configs.erase(troca_id)
		(Dados.historia.get("investido", {}) as Dictionary).erase(troca_id)
	if not Dados.comprar(i):
		_falar("Não deu: falta dinheiro.", [["OK", func(): pass, false]])
		return
	Dados.historia["xp"] = int(Dados.historia.get("xp", 0)) + 20
	Dados.salvar()
	_carro_no_patio()
	_falar(nome + " é teu! Deixei ele ali no pátio, é só pegar.\nSaldo: " + Dados.reais(Dados.dinheiro), [["BORA!", func(): pass]])


## põe o carro escolhido (Dados.carro()) no meio do pátio da loja, de frente pra rua
func _carro_no_patio() -> void:
	if not m.mapa.tem("concessionaria"):
		return
	var cx: Transform3D = m.mapa.xf("concessionaria")
	var pos: Vector3 = cx * Vector3(0, 0.7, 4.2)
	var frente: Vector3 = cx.basis * Vector3(0, 0, 1)
	m._criar_carro(pos, atan2(frente.x, frente.z))


# ---------------------------------------------------------------- todo frame
func _process(dt: float) -> void:
	_t += dt
	if _t < 0.2:
		return
	_t = 0.0
	_atualizar_mundo()
	_atualizar_ficha()
	_atualizar_botao()
	_chamar()
	_cobrar_pintura_na_saida()
	if str(Dados.historia.get("etapa", "")) == "volta_oficina" and not _avisou_pc and m.oficina and m.carro \
			and m.oficina.dentro(m.pessoa.global_position if m.pe and m.pessoa else m.carro.global_position):
		_avisou_pc = true
		m.toast("Drafael: dá uma olhada no PC da oficina (do lado da cabine)", 4.0)


func _atualizar_ficha() -> void:
	var sv := servico()
	if str(sv.get("estado", "")) not in ["fazendo", "pronto"]:
		ficha.visible = false
		aba_ficha.visible = false
		return
	var f := feitos()
	var tudo := not f.is_empty() and not f.has(false)
	if tudo and sv["estado"] == "fazendo":
		sv["estado"] = "pronto"
		Dados.salvar()
		m.toast("SERVIÇO PRONTO! Leva o carro pra Drafael Motors (C no mapa)", 4.0)
	var txt := "[b][color=#ffd400]SERVIÇO DO DRAFAEL · " + str(sv.get("nome_carro", "G3")) + "[/color][/b]\n"
	var itens: Array = sv.get("itens", [])
	for k in itens.size():
		var ok: bool = k < f.size() and f[k]
		txt += ("[color=#7dff8a]✔ " if ok else "[color=#ffffff]☐ ") + str(itens[k]["nome"]) + "[/color]\n"
	txt += "[color=#9aa0aa]Recebido: " + Dados.reais(int(sv.get("pago", 0))) + "[/color]"
	if sv["estado"] == "pronto":
		txt += "\n[b][color=#ffd400]Pronto! Entrega na Drafael Motors (C)[/color][/b]"
	elif sv["estado"] == "fazendo":
		txt += "\n[color=#9aa0aa]Rodas e suspensão: PC da oficina · pintura e lavagem: cabine[/color]"
	ficha_l.text = txt
	var n_ok := 0
	for x in f:
		if x:
			n_ok += 1
	aba_ficha.text = ("◀ " if _ficha_aberta else "▶ ") + "SERVIÇO %d/%d" % [n_ok, f.size()]
	aba_ficha.visible = true
	ficha.visible = _ficha_aberta
	ficha.position.x = aba_ficha.position.x + aba_ficha.size.x + 8


func _atualizar_botao() -> void:
	_acao = ""
	if dialogo.visible:
		botao.visible = false
		return
	var sv := servico()
	if pc_painel.visible:
		botao.visible = false
		return
	if drafael and m.pe and m.pessoa and m.pessoa.global_position.distance_to(drafael.global_position) < 2.6:
		_acao = "falar"
		botao.text = "FALAR COM O DRAFAEL"
	elif _drafael_loja_perto():
		_acao = "falar_loja"
		botao.text = "FALAR COM O DRAFAEL"
	elif m.pe and m.pessoa and m.concessionaria and not m.concessionaria.carro_perto(m.pessoa.global_position).is_empty():
		var v: Dictionary = m.concessionaria.carro_perto(m.pessoa.global_position)
		_acao = "ver_carro"
		_carro_visto = v
		botao.text = "VER " + str(Dados.carros[int(v["i"])]["nome"]).to_upper() + " · " + Dados.reais(int(Dados.carros[int(v["i"])].get("preco", 0)))
	elif perto_do_pc():
		_acao = "pc"
		botao.text = "USAR O PC"
	elif clandestina and clandestina.pode_largar():
		_acao = "correr"
		botao.text = "CORRER CONTRA " + str(clandestina.dados_rival()[0]).to_upper()
	elif str(sv.get("estado", "")) == "pronto" and not m.pe and m.carro and m.mapa.tem("concessionaria") \
			and Dados.carro()["id"] == str(sv.get("carro", "")):
		var patio: Vector3 = m.mapa.xf("concessionaria") * Vector3(0, 0, 4.0)
		var d := Vector2(m.carro.global_position.x - patio.x, m.carro.global_position.z - patio.z).length()
		if d < 16.0 and m.carro.linear_velocity.length() < 2.0:
			_acao = "entregar"
			botao.text = "ENTREGAR O CARRO PRO DRAFAEL"
	botao.visible = _acao != ""


# ---------------------------------------------------------------- PC da oficina
## mesinha com o computador, encostada na parede da cabine
func _montar_pc() -> void:
	pc = Node3D.new()
	add_child(pc)
	pc.global_transform = m.mapa.drops_xf * Transform3D(Basis(Vector3.UP, PI / 2.0), PC_LOCAL)
	var preto := StandardMaterial3D.new()
	preto.albedo_color = Color(0.06, 0.06, 0.07)
	preto.roughness = 0.4
	var madeira := StandardMaterial3D.new()
	madeira.albedo_color = Color(0.55, 0.4, 0.26)
	madeira.roughness = 0.7
	var tela := StandardMaterial3D.new()
	tela.albedo_color = Color(0.05, 0.08, 0.1)
	tela.emission_enabled = true
	tela.emission = Color(0.25, 0.75, 1.0)
	tela.emission_energy_multiplier = 1.4
	var cx := func(tam: Vector3, pos: Vector3, mat: Material) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = tam
		mi.mesh = bm
		mi.material_override = mat
		mi.position = pos
		pc.add_child(mi)
	cx.call(Vector3(1.2, 0.05, 0.6), Vector3(0, 0.76, 0), madeira)          # tampo
	for sx in [-0.55, 0.55]:
		for sz in [-0.25, 0.25]:
			cx.call(Vector3(0.05, 0.74, 0.05), Vector3(sx, 0.37, sz), preto)  # pernas
	cx.call(Vector3(0.62, 0.38, 0.04), Vector3(0, 1.08, -0.15), preto)      # monitor
	cx.call(Vector3(0.56, 0.32, 0.01), Vector3(0, 1.08, -0.127), tela)      # tela acesa
	cx.call(Vector3(0.06, 0.12, 0.06), Vector3(0, 0.84, -0.17), preto)      # pé do monitor
	cx.call(Vector3(0.42, 0.02, 0.14), Vector3(0, 0.79, 0.08), preto)       # teclado
	cx.call(Vector3(0.18, 0.42, 0.42), Vector3(0.42, 0.21, -0.02), preto)   # gabinete embaixo
	var l := Label3D.new()
	l.text = "PC"
	l.font_size = 40
	l.pixel_size = 0.005
	l.modulate = AMARELO
	l.outline_size = 8
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, 1.55, -0.1)
	pc.add_child(l)


func perto_do_pc() -> bool:
	return pc != null and m.pe and m.pessoa and Vector2(m.pessoa.global_position.x - pc.global_position.x,
		m.pessoa.global_position.z - pc.global_position.z).length() < 1.8


func _pc_ui() -> void:
	pc_painel = PanelContainer.new()
	var est: StyleBoxFlat = m._estilo(Color(0.03, 0.05, 0.07, 0.96), Color(0.25, 0.75, 1.0))
	est.content_margin_left = 18
	est.content_margin_right = 18
	est.content_margin_top = 12
	est.content_margin_bottom = 12
	pc_painel.add_theme_stylebox_override("panel", est)
	pc_painel.visible = false
	camada.add_child(pc_painel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc_painel.add_child(v)
	var topo := HBoxContainer.new()
	topo.add_theme_constant_override("separation", 8)
	topo.name = "abas"
	v.add_child(topo)
	var rolar := ScrollContainer.new()
	rolar.custom_minimum_size = Vector2(0, 330)
	rolar.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(rolar)
	_pc_conteudo = VBoxContainer.new()
	_pc_conteudo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pc_conteudo.add_theme_constant_override("separation", 10)
	rolar.add_child(_pc_conteudo)
	var fechar := _botao("FECHAR O PC", false)
	fechar.pressed.connect(func(): pc_painel.visible = false)
	v.add_child(fechar)


func _clandestina_liberada() -> bool:
	return str(Dados.historia.get("etapa", "")) != "primeiro_carro" or int(Dados.historia.get("servicos_feitos", 0)) > 0


func abrir_pc(aba := "") -> void:
	if aba != "":
		_pc_aba = aba
	var t := get_viewport().get_visible_rect().size
	pc_painel.size = Vector2(minf(t.x - 60, 720), 0)
	pc_painel.position = Vector2((t.x - pc_painel.size.x) / 2.0, 60)
	var abas := pc_painel.find_child("abas", true, false) as HBoxContainer
	for n in abas.get_children():
		n.queue_free()
	var lista := [["servico", "SERVIÇOS"], ["motor", "MOTOR"], ["carro", "RODAS E SUSPENSÃO"]]
	if _clandestina_liberada():
		lista.append(["clandestina", "CLANDESTINA"])
	for a in lista:
		var b := _botao(str(a[1]), a[0] == _pc_aba)
		b.add_theme_font_size_override("font_size", 16)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var k: String = a[0]
		b.pressed.connect(func(): abrir_pc(k))
		abas.add_child(b)
	_encher_pc()
	pc_painel.visible = true


func _texto(t: String, tam := 18, cor := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", cor)
	_pc_conteudo.add_child(l)
	return l


func _encher_pc() -> void:
	for n in _pc_conteudo.get_children():
		n.queue_free()
	var d: Dictionary = Dados.carro()
	var c := Dados.cfg()
	_texto("Saldo: " + Dados.reais(Dados.dinheiro) + "   ·   Carro: " + str(d["nome"]), 17, Color("7dff8a"))
	match _pc_aba:
		"servico":
			var sv := servico()
			if str(sv.get("estado", "")) in ["fazendo", "pronto"]:
				_texto("Serviço em andamento: " + str(sv.get("nome_carro", "G3")) + " do Drafael. A ficha fica embaixo do mapa.", 18)
			elif str(Dados.historia.get("etapa", "")) == "volta_oficina" and int(Dados.historia.get("servicos_feitos", 0)) == 1:
				var p := _pedido_vambora()
				_texto("PEDIDO DO DRAFAEL · Vambora", 22, AMARELO)
				for it in p["itens"]:
					_texto("  • " + str(it["nome"]) + ("  (peças " + Dados.reais(int(it["custo"])) + ")" if int(it["custo"]) > 0 else ""), 17)
				_texto("Ele paga " + Dados.reais(p["pago"]) + " adiantado. Lucro: " + Dados.reais(int(p["pago"]) - int(p["custo"])) + ".", 18, Color("7dff8a"))
				if not m.pe:
					_texto("Desce do carro pra aceitar (o Vambora aparece na oficina).", 15, Color("9aa0aa"))
				else:
					var b := _botao("ACEITAR O SERVIÇO")
					b.pressed.connect(func():
						pc_painel.visible = false
						Dados.historia["etapa"] = "servico2"
						_aceitar(p))
					_pc_conteudo.add_child(b)
			else:
				_texto("Nenhum pedido novo por enquanto. O Drafael avisa quando tiver mais.", 18)
		"motor":
			var nivel := clampi(int(c.get("motor", 0)), 0, Dados.MOTOR.size() - 1)
			_texto("PREPARAÇÃO DO MOTOR · " + str(d["nome"]), 22, AMARELO)
			_texto("Agora: " + str(Dados.MOTOR[nivel][0]), 18)
			for k in range(1, Dados.MOTOR.size()):
				var mt: Array = Dados.MOTOR[k]
				var linha := HBoxContainer.new()
				linha.add_theme_constant_override("separation", 10)
				_pc_conteudo.add_child(linha)
				var l := Label.new()
				l.text = "%s\n+%d%% de força" % [mt[0], roundi((float(mt[2]) - 1.0) * 100.0)]
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				l.add_theme_font_size_override("font_size", 16)
				l.add_theme_color_override("font_color", Color("7dff8a") if k <= nivel else Color.WHITE)
				linha.add_child(l)
				if k <= nivel:
					var ok := Label.new()
					ok.text = "INSTALADO"
					ok.add_theme_color_override("font_color", Color("7dff8a"))
					linha.add_child(ok)
				elif k == nivel + 1:
					var b := _botao("COMPRAR " + Dados.reais(int(mt[1])))
					b.add_theme_font_size_override("font_size", 16)
					var kk := k
					b.pressed.connect(func():
						if not Dados.pagar(int(Dados.MOTOR[kk][1])):
							m.toast("SEM DINHEIRO PRA ESSA PREPARAÇÃO", 2.0)
							return
						Dados.mudar("motor", kk)
						m.cfg = Dados.cfg()
						m.toast("MOTOR PREPARADO: " + str(Dados.MOTOR[kk][0]).get_slice(" ·", 0).to_upper() + "!", 2.5)
						_encher_pc())
					linha.add_child(b)
		"carro":
			_aba_carro(d, c)
		"clandestina":
			_aba_clandestina()


func _aba_carro(d: Dictionary, c: Dictionary) -> void:
	_texto("RODAS · " + str(d["nome"]), 22, AMARELO)
	var aro := int(c.get("aro", 15))
	var amax := CarroVisual.aro_maximo(d)
	var escolha := [aro]
	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 10)
	_pc_conteudo.add_child(linha)
	var menos := _botao("−", false)
	menos.custom_minimum_size = Vector2(64, 56)
	linha.add_child(menos)
	var val := Label.new()
	val.add_theme_font_size_override("font_size", 22)
	val.custom_minimum_size = Vector2(110, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	linha.add_child(val)
	var mais := _botao("+", false)
	mais.custom_minimum_size = Vector2(64, 56)
	linha.add_child(mais)
	var trocar := _botao("")
	trocar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	linha.add_child(trocar)
	var atualiza := func():
		val.text = "aro %d" % escolha[0]
		trocar.disabled = escolha[0] == aro
		trocar.text = "JÁ ESTÁ" if escolha[0] == aro else "TROCAR · " + Dados.reais(Dados.custo_roda(escolha[0]))
	menos.pressed.connect(func(): escolha[0] = maxi(14, escolha[0] - 1); atualiza.call())
	mais.pressed.connect(func(): escolha[0] = mini(amax, escolha[0] + 1); atualiza.call())
	trocar.pressed.connect(func():
		var preco := Dados.custo_roda(escolha[0])
		if not Dados.pagar(preco):
			m.toast("SEM DINHEIRO: o jogo de rodas custa " + Dados.reais(preco), 2.0)
			return
		_mudar_carro("aro", escolha[0])
		m.toast("RODAS ARO %d INSTALADAS!" % escolha[0], 2.0)
		_encher_pc())
	atualiza.call()
	_texto("Até aro 16: R$ 1 mil · 17 a 22: R$ 6 mil · 23 pra cima: R$ 10 mil (o jogo com 4)", 14, Color("9aa0aa"))
	_texto("SUSPENSÃO A AR", 22, AMARELO)
	if not bool(c.get("ar", false)):
		var b := _botao("INSTALAR SUSPENSÃO A AR · " + Dados.reais(Dados.CUSTO_SUSPENSAO))
		b.pressed.connect(func():
			if not Dados.pagar(Dados.CUSTO_SUSPENSAO):
				m.toast("SEM DINHEIRO PRA SUSPENSÃO A AR", 2.0)
				return
			_mudar_carro("ar", true)
			m.toast("SUSPENSÃO A AR INSTALADA! Agora dá pra socar.", 2.5)
			_encher_pc())
		_pc_conteudo.add_child(b)
		_texto("Sem a suspensão a ar o carro fica na altura de fábrica.", 14, Color("9aa0aa"))
	else:
		var rmax := CarroVisual.rebaixo_max(d)
		for par in [["rebaixo", "Frente"], ["rebaixo_tras", "Trás"]]:
			var lh := HBoxContainer.new()
			lh.add_theme_constant_override("separation", 10)
			_pc_conteudo.add_child(lh)
			var nome := Label.new()
			nome.text = str(par[1])
			nome.custom_minimum_size = Vector2(90, 0)
			nome.add_theme_font_size_override("font_size", 18)
			lh.add_child(nome)
			var chave: String = par[0]
			var atual := float(c.get(chave, 0.0))
			for passo in [-2.0, 2.0]:
				var b := _botao("−2 cm" if passo < 0 else "+2 cm", false)
				b.custom_minimum_size = Vector2(110, 50)
				var p2: float = passo
				b.pressed.connect(func():
					var novo := clampf(float(Dados.cfg().get(chave, 0.0)) + p2, 0.0, rmax)
					_mudar_carro(chave, novo)
					_encher_pc())
				lh.add_child(b)
			var vl := Label.new()
			vl.text = "%d cm" % int(atual)
			vl.add_theme_font_size_override("font_size", 20)
			lh.add_child(vl)
		_texto("Mexer na altura é de graça depois de instalada (até %d cm)." % int(rmax), 14, Color("9aa0aa"))


## muda o carro atual e já atualiza o que está na rua/oficina
func _mudar_carro(chave: String, valor) -> void:
	Dados.mudar(chave, valor)
	m.cfg = Dados.cfg()
	if m.visual:
		m.visual.atualizar(m.cfg)
	if chave.begins_with("rebaixo") and "ar_alvo" in m:
		if chave == "rebaixo":
			m.ar_alvo = float(valor)
		else:
			m.ar_alvo_t = float(valor)
	if chave == "aro" and m.carro:
		m._criar_carro(m.carro.global_position + Vector3.UP * 0.3, m.carro.rotation.y)


func _aba_clandestina() -> void:
	var i := int(Dados.historia.get("clandestina", 0))
	if i >= Dados.CLANDESTINAS.size():
		_texto("Você já venceu todas as clandestinas... por enquanto.", 20, AMARELO)
		return
	if not Dados.historia.get("clandestina_vista", false):
		_texto("Achou que seria somente reforma?\nBem-vindo à primeira clandestina...", 26, Color(1, 0.35, 0.3))
	var r: Array = Dados.CLANDESTINAS[i]
	_texto("CLANDESTINA %d · Avenida Juscelino Kubitschek" % (i + 1), 22, AMARELO)
	_texto("Arrancada de 500 m contra " + str(r[0]) + " (" + str(Dados.carros[Dados.indice_de(str(r[1]))]["nome"]) + ").\nGanhou: " + Dados.reais(int(r[3])) + ". Perdeu: pode tentar de novo até ganhar.", 18)
	if i == 0:
		_texto("Esse aí é tranquilo. Os próximos são brabos: prepara o motor antes.", 15, Color("9aa0aa"))
	var b := _botao("MARCAR NO MAPA")
	b.pressed.connect(func():
		Dados.historia["clandestina_vista"] = true
		Dados.historia["clandestina_marcada"] = true
		Dados.salvar()
		clandestina.ativar()
		pc_painel.visible = false
		m.toast("CLANDESTINA MARCADA: Av. Juscelino (siga a seta vermelha)", 3.5))
	_pc_conteudo.add_child(b)


# ---------------------------------------------------------------- pintura: cobra uma vez, na saída da oficina
var _carro_dentro := true

## custo da pintura anotada pro carro atual: carro todo = preço cheio; só peças = 20% cada (no máximo o cheio)
func custo_pintura_anotada() -> int:
	var pt: Dictionary = Dados.historia.get("pintura", {})
	if str(pt.get("carro", "")) != str(Dados.carro()["id"]):
		return 0
	var cheio := Dados.custo_pintura(Dados.carro())
	if pt.get("todo", false):
		return cheio
	var por_peca := int(round(cheio * Dados.PINTURA_PECA_FRACAO / 100.0) * 100)
	return mini(cheio, por_peca * (pt.get("pecas", []) as Array).size())


## anota uma demão (peca "" = carro todo). false = não tem dinheiro pra pagar na saída
func anotar_pintura(peca: String) -> bool:
	var cid := str(Dados.carro()["id"])
	var antes: Dictionary = Dados.historia.get("pintura", {})
	var pt := antes.duplicate(true) if str(antes.get("carro", "")) == cid else {"carro": cid, "todo": false, "pecas": []}
	if peca == "":
		pt["todo"] = true
	elif not (pt["pecas"] as Array).has(peca):
		(pt["pecas"] as Array).append(peca)
	Dados.historia["pintura"] = pt
	var custo := custo_pintura_anotada()
	if Dados.dinheiro < custo:
		Dados.historia["pintura"] = antes
		m.toast("SEM DINHEIRO: essa pintura sai " + Dados.reais(custo), 2.2)
		return false
	Dados.salvar()
	m.toast("Tinta: " + Dados.reais(custo) + " · cobra UMA vez quando o carro sair da oficina", 2.6)
	return true


func _cobrar_pintura_na_saida() -> void:
	if m.oficina == null or m.carro == null:
		return
	var dentro: bool = m.oficina.dentro(m.carro.global_position)
	if _carro_dentro and not dentro and not m.pe:
		var custo := custo_pintura_anotada()
		if custo > 0:
			Dados.dinheiro -= custo
			Dados.historia.erase("pintura")
			Dados.salvar()
			m.toast("PINTURA COBRADA: " + Dados.reais(custo), 2.6)
	_carro_dentro = dentro
