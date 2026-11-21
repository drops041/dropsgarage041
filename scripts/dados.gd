extends Node
## Dados do jogo (autoload "Dados"): carros, cores, rodas e a configuração salva de cada carro.

const CORES := [["Branco", "#f1f0ec"], ["Prata", "#b9bdc2"], ["Preto", "#111214"], ["Cinza Quartzo", "#58625f"],
	["Azul Petróleo", "#3b6470"], ["Azul Marinho", "#1b2a48"], ["Vermelho", "#b5121b"], ["Amarelo Drops", "#ffcf00"],
	["Verde Limão", "#76cc2a"], ["Roxo", "#5a2a88"], ["Laranja", "#e8641c"], ["Rosa", "#e45a9c"]]
const CORES2 := [["Roxo", "#c99cf0"], ["Azul", "#6ea6ff"], ["Verde", "#5ff0b0"], ["Rosa", "#ff7ad1"], ["Dourado", "#f0c45a"], ["Ciano", "#2be7ff"]]
const ACABAMENTOS := [["metal", "Metálico"], ["brilho", "Brilho"], ["perola", "Pérola"], ["fosco", "Fosco"], ["camaleao", "Camaleão"], ["cromado", "Cromado"]]
const CORES_RODA := [["Prata", "#c9ccd1"], ["Grafite", "#4a4d52"], ["Preto fosco", "#16171a"], ["Branco fosco", "#f2f2ef"],
	["Dourado", "#c9a14a"], ["Bronze", "#7a5a36"], ["Roxo", "#7650cf"], ["Vermelho", "#b5121b"], ["Azul", "#2f64d8"]]
const NEONS := {"off": "", "roxo": "#9b4dff", "azul": "#2b8cff", "ciano": "#2be7ff", "verde": "#3dff7a", "rosa": "#ff3bd4", "vermelho": "#ff2a3a", "amarelo": "#ffd400"}
const RODAS := [["work", "Trampo E03"], ["tsw5", "5 Raios Turbo"], ["vgt", "Visão GT"], ["revu", "Revolto"], ["lambo", "Touro SDC"],
	["magn", "Magnésio"], ["audi", "Argolas"], ["vwrim", "Original de Fábrica"], ["gt3", "Forged GT3"], ["fline", "Forged Line"], ["sfn", "Tramada RS"],
	["tsi", "Turbo 5"], ["m850", "Bávaro 850"], ["rod", "Rodeira R19"], ["llanta", "6 Raios"], ["sdc4", "6 Raios Côncava"], ["sdc1", "Multirraios"],
	["sdc3", "Raios Finos"], ["sdc5", "Estrela"], ["f1", "Fórmula 1"],
	["hre522", "H-Raio 522"], ["tusk", "Presa"], ["dj76", "DJ 76"], ["sv67", "Savoia 67"],
	["nc4", "Savoia NC4"], ["weds", "Kranz Bazar"], ["r557", "Rim 557"],
	["jerez", "Jerez"], ["jettagli", "Jeta GLX"], ["tiguan", "Despacito R"], ["id4", "Volt Aero"],
	["raptor", "Raptora Beadlock"], ["aco15", "Calota de Fábrica"], ["antera", "Antares 109"], ["vsxv", "Trampo VS"]]
const ARQUIVO := "user://garagem.json"
const ARQUIVO_HISTORIA := "user://historia.json"   # (modo história) carros, dinheiro e progresso separados do modo livre

## ---------------------------------------------------------------- MODO HISTÓRIA: economia combinada (20/11)
## Custo das peças pro jogador (o que ele gasta pra fazer o serviço):
##   suspensão a ar R$ 5 mil · som R$ 8 mil
##   rodas: até aro 16 R$ 1 mil · aro 17 a 22 R$ 6 mil · aro 23 pra cima R$ 10 mil
##   pintura: R$ 8 mil (carro pequeno) até R$ 25 mil (carro grande)
## O cliente (o Drafael, dono da Drafael Motors) paga as peças x 1,5 na hora em que você aceita o serviço:
## você compra as peças e fica com o que sobra (o lucro).
## Começo: serviços baratos; vai aumentando aos poucos (nem lento nem rápido demais).
## O MODO LIVRE continua igual (tudo liberado, pra quem quer jogo rápido).
const HISTORIA_DINHEIRO_INICIAL := 20000
const HISTORIA_JURO := 1.5
const CUSTO_SUSPENSAO := 5000
const CUSTO_SOM := 8000
const CUSTO_PINTURA := [8000, 25000]
const CUSTO_LAVAR := 300
const CUSTO_LIXAR := 800
const CUSTO_DESAMASSAR := 1500
## preparação do motor (por carro, cfg "motor" 0..3): [nome, preço, força x, velocidade x]
const MOTOR := [["Original", 0, 1.0, 1.0], ["Estágio 1 · filtro, escape e remap", 3000, 1.10, 1.04],
	["Estágio 2 · comando e cabeçote", 8000, 1.25, 1.09], ["Estágio 3 · turbo", 20000, 1.5, 1.18]]
## clandestinas (arrancada de 500 m na Av. Juscelino): [rival, carro do rival, tempo do rival (s), prêmio]
## (medido no teste 18 com os carros do começo: original ~16,3 s · estágio 1 ~15,4 · estágio 2 ~14,4 · estágio 3 ~13,1)
## a 1ª é fácil; a 2ª precisa do estágio 1, a 3ª do estágio 2, a 4ª do estágio 3
const CLANDESTINAS := [["Zé da Quebrada", "golg2", 21.0, 1000], ["Japa do G5", "golg5", 16.0, 2000],
	["Bigode da G6", "saveiro", 14.95, 4000], ["Tchê do Golfo", "golfgti", 13.75, 8000]]
const PECA_FRACAO := 0.25        # serviço numa peça só (porta, capô...) custa 1/4 do carro todo
const PINTURA_PECA_FRACAO := 0.2


## pintura do carro todo: R$ 8 mil (carro pequeno) até R$ 25 mil (picape grande), pelo entre-eixos
static func custo_pintura(d: Dictionary) -> int:
	var eixos := float(d.get("axF", 1.3)) - float(d.get("axR", -1.3))
	var k := clampf((eixos - 2.6) / (3.6 - 2.6), 0.0, 1.0)   # até ~2,6 m (G3, Donas, Cliô...) = R$ 8 mil
	return int(round(lerpf(CUSTO_PINTURA[0], CUSTO_PINTURA[1], k) / 500.0) * 500)


## custo de um serviço da cabine ("s" lavar, "f" lixar, "a" desamassar)
static func custo_servico(chave: String, so_peca := false) -> int:
	var c: int = {"s": CUSTO_LAVAR, "f": CUSTO_LIXAR, "a": CUSTO_DESAMASSAR}.get(chave, 0)
	return int(round(c * (PECA_FRACAO if so_peca else 1.0)))


static func custo_roda(aro: int) -> int:
	if aro >= 23:
		return 10000
	if aro >= 17:
		return 6000
	return 1000

var carros: Array = []
var idx := 0                 # carro escolhido
var personagem := "protagonista"   # quem anda a pé
var visual := {}   # (fase 2) roupa, cabelo e pele do protagonista (ver Pessoa.VISUAL_PADRAO)
var configs := {}            # id do carro -> configuração
var dinheiro := 1000000
var recordes := {}
var modo := "livre"          # "livre" (tudo liberado, como sempre foi) ou "historia"
var historia := {}           # (modo história) {"etapa", "garagem": [ids dos carros que você tem], "nivel", "xp"}
var _livre := {}             # guarda o modo livre enquanto joga a história
var _voltar_historia := false


const MUSICAS := [["res://audio/drops-garage.mp3", "Drops Garage"], ["res://audio/mega_funk.mp3", "Set Mega Funk (Xhakinha)"]]
var musica: AudioStreamPlayer
var faixa := 0
var volume_musica := 0.8        # 0..1, só a música (os efeitos não mudam)
var tutorial_feito := false     # (v36) dicas da primeira vez já vistas
var dicas := {}                  # (v37) dicas da oficina já mostradas (elevador, rodas)
var graficos := "alto"          # (v33) "alto": resolução cheia, antiserrilhado, sombra dos carros; "leve": o modo antigo do celular
var _espectro: AudioEffectSpectrumAnalyzerInstance
var grave := 0.0          # 0..1, batida do grave da música (pro carro pular e o neon piscar)
var _sem_sinal := 0.0
var _t := 0.0


func _process(dt: float) -> void:
	var g := 0.0
	if musica and musica.playing and _espectro:
		var e := _espectro.get_magnitude_for_frequency_range(30.0, 140.0).length()
		g = clampf((linear_to_db(e) + 42.0) / 30.0, 0.0, 1.0)
		# sem placa de som o medidor não lê nada: faz a batida no tempo da música (~95 bpm)
		_sem_sinal = 0.0 if e > 0.0001 else _sem_sinal + dt
		_t += dt
		if _sem_sinal > 2.0:
			var b := fposmod(_t * 95.0 / 60.0, 1.0)
			g = clampf(1.0 - b * 3.0, 0.0, 1.0)
	grave = lerpf(grave, g, clampf(dt * (25.0 if g > grave else 8.0), 0.0, 1.0))


func _carregar_faixa() -> void:
	var st: AudioStream = load(MUSICAS[faixa][0]) if ResourceLoader.exists(MUSICAS[faixa][0]) else null
	if st is AudioStreamMP3:
		(st as AudioStreamMP3).loop = false
	musica.stream = st
	aplicar_volume()


func aplicar_volume() -> void:
	musica.volume_db = linear_to_db(maxf(volume_musica, 0.001)) - 6.0


func mudar_volume(v: float) -> void:
	volume_musica = clampf(v, 0.0, 1.0)
	aplicar_volume()
	salvar()


## troca de música (passo 1 = próxima, -1 = anterior); se estava tocando continua tocando
func proxima_musica(passo := 1) -> void:
	faixa = posmod(faixa + passo, MUSICAS.size())
	_carregar_faixa()
	musica.play()
	salvar()


func nome_musica() -> String:
	return MUSICAS[faixa][1]


## painelzinho da música (fica em scripts/painel_musica.gd)
func painel_musica() -> PanelContainer:
	return PainelMusica.new()


func tocar_musica(sim: bool) -> void:
	if sim and not musica.playing:
		musica.play()
	elif not sim:
		musica.stop()


func _ready() -> void:
	ajustar_msaa(get_tree().root)
	if placa_sem_msaa():
		print("placa ", RenderingServer.get_video_adapter_name(), ": sem MSAA (evita quadrados pretos)")
	# símbolos (♫ ▲ ▼ ◎) também no navegador/celular: fonte reserva com esses desenhos
	var reserva := load("res://fontes/DejaVuSans.ttf") as Font
	var base := ThemeDB.fallback_font
	if reserva and base:
		var lista: Array[Font] = base.fallbacks.duplicate()
		lista.append(reserva)
		base.fallbacks = lista
	musica = AudioStreamPlayer.new()
	add_child(musica)
	musica.finished.connect(func(): proxima_musica())   # acabou a música: toca a próxima
	var ef := AudioEffectSpectrumAnalyzer.new()
	ef.buffer_length = 0.1
	AudioServer.add_bus_effect(0, ef)
	_espectro = AudioServer.get_bus_effect_instance(0, AudioServer.get_bus_effect_count(0) - 1) as AudioEffectSpectrumAnalyzerInstance
	carros = JSON.parse_string(FileAccess.get_file_as_string("res://carros.json"))
	for i in carros.size():
		if carros[i]["id"] == "saveiro":
			idx = i
	if FileAccess.file_exists(ARQUIVO):
		var salvo = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO))
		if salvo is Dictionary:
			configs = salvo.get("configs", {})
			idx = clampi(int(salvo.get("idx", idx)), 0, carros.size() - 1)
			var cid := str(salvo.get("carro", ""))   # salva pelo nome do carro (tirar/pôr carro não troca o carro do jogador)
			for i in carros.size():
				if carros[i]["id"] == cid:
					idx = i
			personagem = str(salvo.get("personagem", personagem))
			if not salvo.has("v44"):   # v44: a G5 Cross (o carro principal) entra selecionada uma vez
				for i in carros.size():
					if carros[i]["id"] == "saveirog5":
						idx = i
			if not salvo.has("v43"):
				personagem = "protagonista"   # v43: protagonista novo (sem bug de animação) vira o padrão uma vez
			visual = salvo.get("visual", {}) if salvo.get("visual", {}) is Dictionary else {}
			dinheiro = maxi(1000000, int(salvo.get("dinheiro", 1000000)))
			recordes = salvo.get("recordes", {})
			volume_musica = clampf(float(salvo.get("volume_musica", 0.8)), 0.0, 1.0)
			graficos = str(salvo.get("graficos", "alto"))
			tutorial_feito = bool(salvo.get("tutorial", false))
			dicas = salvo.get("dicas", {}) if salvo.get("dicas", {}) is Dictionary else {}
			faixa = clampi(int(salvo.get("faixa", 0)), 0, MUSICAS.size() - 1)
			if str(salvo.get("modo", "livre")) == "historia" and not OS.has_environment("DROPS_TESTE") and not OS.has_environment("DROPS_LIVRE"):
				_voltar_historia = true   # fechou o jogo no modo história: volta nele
	if OS.has_environment("DROPS_VISUAL"):   # testes: visual do protagonista em JSON
		visual = JSON.parse_string(OS.get_environment("DROPS_VISUAL"))
	if OS.has_environment("DROPS_PERSONAGEM"):
		personagem = OS.get_environment("DROPS_PERSONAGEM")
	if OS.has_environment("DROPS_CARRO"):   # testes: abre direto num carro
		for i in carros.size():
			if carros[i]["id"] == OS.get_environment("DROPS_CARRO"):
				idx = i
	if demo():
		_voltar_historia = false   # demo: só o modo livre, num carro que veio no pacote
		if not carro_pronto(str(carros[idx]["id"])):
			for i in carros.size():
				if carro_pronto(str(carros[i]["id"])):
					idx = i
					break
	if _voltar_historia:
		entrar_historia()
	_carregar_faixa()



## navegador/celular: o WebGL não aguenta muitos objetos na cena (acima de ~1000 a tela fica vazia).
## Junta todas as malhas paradas de um grupo numa malha só por material (com 'celula' > 0 separa por pedaços do mapa).
static func juntar(raiz: Node3D, celula := 0.0, tirar_escondidos := false) -> void:
	var inv := raiz.global_transform.affine_inverse()
	var pedacos := {}       # célula -> {material -> SurfaceTool}
	var tirar: Array[MeshInstance3D] = []
	for n in raiz.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if tirar_escondidos and not m.is_visible_in_tree():
			m.queue_free()   # escondido também conta no limite: some de vez
			continue
		if not (m.mesh is ArrayMesh) or not m.is_visible_in_tree() or m.skin != null:
			continue
		if m.visibility_range_end > 0.0:
			continue
		var t := inv * m.global_transform
		var chave := Vector2i.ZERO
		if celula > 0.0:
			var c := (m.global_transform * m.get_aabb()).get_center()
			chave = Vector2i(floori(c.x / celula), floori(c.z / celula))
		if not pedacos.has(chave):
			pedacos[chave] = {}
		var mats: Dictionary = pedacos[chave]
		var ok := true
		for i in m.mesh.get_surface_count():
			if m.mesh.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
				ok = false
		if not ok:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if not mats.has(mat):
				mats[mat] = SurfaceTool.new()
			(mats[mat] as SurfaceTool).append_from(m.mesh, i, t)
		tirar.append(m)
	for chave in pedacos:
		var mats: Dictionary = pedacos[chave]
		var malha := ArrayMesh.new()
		for mat in mats:
			if malha.get_surface_count() >= 250:
				_por(raiz, malha)
				malha = ArrayMesh.new()
			var st := mats[mat] as SurfaceTool
			st.commit(malha)
			malha.surface_set_material(malha.get_surface_count() - 1, mat)
		_por(raiz, malha)
	for m in tirar:
		m.queue_free()


static func _por(raiz: Node3D, malha: ArrayMesh) -> void:
	if malha.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = malha
	mi.name = "junto"
	raiz.add_child(mi)

## celular/navegador: versão leve (sem sombra, malhas juntas, menos trânsito)
static func leve() -> bool:
	return OS.has_feature("web") or OS.has_feature("mobile") or OS.has_environment("DROPS_LEVE")


## gráfico caprichado (padrão a partir da v33, inclusive no celular): dá pra voltar pro leve no painel da música
## (21/11) placas AMD Polaris (RX 460-590, ex.: RX 580) desenham QUADRADOS PRETOS no Forward+ quando o
## antisserrilhado MSAA está ligado junto com o SSAO (sombra de contato do cenário). Nelas o jogo usa FXAA.
static func placa_sem_msaa() -> bool:
	if OS.has_environment("DROPS_SEM_MSAA"):
		return true
	var nome := RenderingServer.get_video_adapter_name().to_lower()
	var re := RegEx.create_from_string("rx\\s*(4[5-9]0|5[4-9]0)\\b|polaris|rx\\s*vega|radeon\\s*\\(tm\\)\\s*rx\\s*(4|5)\\d0")
	return re.search(nome) != null


## põe o antisserrilhado certo pra placa (chamado no começo e quando muda o gráfico)
static func ajustar_msaa(vp: Viewport) -> void:
	if placa_sem_msaa():
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA


static func grafico_alto() -> bool:
	if OS.has_feature("web") or OS.has_environment("DROPS_LEVE"):
		return false
	var d = Engine.get_main_loop().root.get_node_or_null("/root/Dados") if Engine.get_main_loop() else null
	return d == null or str(d.graficos) != "leve"


## versão do navegador: usa o modelo mais leve (_web.scn) quando ele existe
static func modelo(arq: String) -> String:
	var w := arq.replace(".glb", "_web.scn")
	return w if ResourceLoader.exists(w) else arq


func carro() -> Dictionary:
	return carros[idx]


## configuração do carro (padrão do carro + o que o jogador mudou)
func cfg(i: int = -1) -> Dictionary:
	var d: Dictionary = carros[idx if i < 0 else i]
	var c: Dictionary = d["padrao"].duplicate()
	c["rebaixo"] = float(d["padrao"].get("rebaixo", 10.0))   # cm abaixo da altura original (0 = original); carro que já vem baixo começa no 0
	c["flanco"] = minf(float(c.get("flanco", 5.5)), 5.5)   # pneu fininho de fábrica (o jogador muda na garagem)
	c.merge(configs.get(d["id"], {}), true)
	if not c.has("recuo"):
		c["recuo"] = 0.0
	if not c.has("rebaixo_tras"):
		c["rebaixo_tras"] = c["rebaixo"]   # traseira acompanha a dianteira até você mexer nela
	if not c.has("tala_tras"):
		c["tala_tras"] = c["tala"]
	if not c.has("recuo_tras"):
		c["recuo_tras"] = c["recuo"]
	return c


func mudar(chave: String, valor) -> void:
	var id: String = carro()["id"]
	if not configs.has(id):
		configs[id] = {}
	for par in [["rebaixo", "rebaixo_tras"], ["tala", "tala_tras"], ["recuo", "recuo_tras"]]:
		if chave == par[0] and not configs[id].has(par[1]):
			configs[id][par[1]] = cfg()[par[1]]   # mexer na dianteira não leva a traseira junto
	configs[id][chave] = valor
	if chave == "roda":
		configs[id].erase("rodas")   # escolheu o jogo inteiro (loja da garagem): some o "roda por roda" do elevador
	salvar()


func original() -> void:
	configs.erase(carro()["id"])
	salvar()


func salvar() -> void:
	# o arquivo de sempre guarda o MODO LIVRE (no modo história, o que estava guardado em _livre)
	var lv := _livre if modo == "historia" else {"idx": idx, "configs": configs, "dinheiro": dinheiro}
	var f := FileAccess.open(ARQUIVO, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"v31": true, "v43": true, "v44": true, "visual": visual, "idx": lv["idx"], "carro": carros[lv["idx"]]["id"], "personagem": personagem, "configs": lv["configs"], "dinheiro": lv["dinheiro"], "recordes": recordes, "volume_musica": volume_musica, "faixa": faixa, "graficos": graficos, "tutorial": tutorial_feito, "dicas": dicas, "modo": modo}))
	if modo == "historia":
		var h := FileAccess.open(ARQUIVO_HISTORIA, FileAccess.WRITE)
		if h:
			h.store_string(JSON.stringify({"idx": idx, "carro": carros[idx]["id"], "configs": configs, "dinheiro": dinheiro, "historia": historia}))


# ---------------------------------------------------------------- modo história
func entrar_historia() -> void:
	if modo == "historia":
		return
	_livre = {"idx": idx, "configs": configs.duplicate(true), "dinheiro": dinheiro}
	modo = "historia"
	configs = {}
	dinheiro = HISTORIA_DINHEIRO_INICIAL
	historia = {"etapa": "abertura", "garagem": [], "nivel": 1, "xp": 0}
	if FileAccess.file_exists(ARQUIVO_HISTORIA):
		var s = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO_HISTORIA))
		if s is Dictionary:
			configs = s.get("configs", {}) if s.get("configs", {}) is Dictionary else {}
			dinheiro = int(s.get("dinheiro", dinheiro))
			if s.get("historia", {}) is Dictionary:
				historia.merge(s["historia"], true)
			_ir_para(str(s.get("carro", "")))
	if not tem_carro(carros[idx]["id"]) and not (historia["garagem"] as Array).is_empty():
		_ir_para(str(historia["garagem"][0]))
	salvar()


func sair_historia() -> void:
	if modo != "historia":
		return
	salvar()
	modo = "livre"
	idx = int(_livre.get("idx", idx))
	configs = _livre.get("configs", {})
	dinheiro = int(_livre.get("dinheiro", 1000000))
	_livre = {}
	salvar()


## começa a história do zero (apaga o progresso da história; o modo livre não muda)
func zerar_historia() -> void:
	configs = {}
	dinheiro = HISTORIA_DINHEIRO_INICIAL
	historia = {"etapa": "abertura", "garagem": [], "nivel": 1, "xp": 0}
	salvar()


## (demo do navegador: só a oficina e alguns carros, pra mostrar pros amigos)
static func demo() -> bool:
	return OS.has_feature("demo") or OS.has_environment("DROPS_DEMO")


# ---------------------------------------------------------------- demo do navegador: carros baixados na hora
## Na demo cada carro vem num pacote separado (carros/<id>.pck, em pedaços de texto base64: .000.txt, .001.txt...),
## listado em carros/lista.json ({"id": nº de pedaços}). Baixa só quando você escolhe o carro.
signal carro_baixado(id: String, ok: bool)
var _lista_pacotes := {}
var _baixando := ""
var _http: HTTPRequest
var _fila: Array = []          # pedaços que faltam baixar do carro atual
var _progresso := 0.0


func carro_pronto(id: String) -> bool:
	return not demo() or ResourceLoader.exists("res://modelos/carros/%s.glb" % id)


func progresso_download() -> float:
	if _http and _baixando != "" and _http.get_body_size() > 0:
		var lv = _lista_pacotes.get(_baixando, 1)
		var n := float((lv as Array).size() if lv is Array else lv)
		var feito := n - float(_fila.size()) - 1.0
		return clampf((feito + float(_http.get_downloaded_bytes()) / float(_http.get_body_size())) / n, 0.0, 1.0)
	return _progresso


func _base_url() -> String:
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("location.href.replace(/[#?].*$/, '').replace(/[^/]*$/, '')"))
	return OS.get_environment("DROPS_DEMO_URL")


func baixar_carro(id: String) -> void:
	if carro_pronto(id) or _baixando == id:
		return
	if _baixando != "":
		_http.cancel_request()
	if _http == null:
		_http = HTTPRequest.new()
		_http.use_threads = false
		_http.download_chunk_size = 4 * 1024 * 1024   # 4 MB por quadro (o padrão de 64 KB deixava o download lento)
		add_child(_http)
		_http.request_completed.connect(_pedaco_chegou)
	_baixando = id
	_progresso = 0.0
	DirAccess.make_dir_recursive_absolute("user://carros")
	var f := FileAccess.open("user://carros/%s.pck" % id, FileAccess.WRITE)
	if f:
		f.close()
	if _lista_pacotes.is_empty():
		_fila = ["lista"]
	else:
		_montar_fila(id)
	_proximo_pedaco()


func _montar_fila(id: String) -> void:
	_fila = []
	var v = _lista_pacotes.get(id, 0)
	if v is Array:   # endereço de cada pedaço (ex.: "/_blob/..." quando fica guardado como anexo do link)
		_fila = (v as Array).duplicate()
		return
	for k in int(v):
		_fila.append("carros/%s.pck.%03d.txt" % [id, k])


func _proximo_pedaco() -> void:
	if _fila.is_empty():
		var ok := ProjectSettings.load_resource_pack("user://carros/%s.pck" % _baixando)
		print("demo: pacote ", _baixando, " carregado=", ok, " existe=", carro_pronto(_baixando))
		var id := _baixando
		_baixando = ""
		carro_baixado.emit(id, ok and carro_pronto(id))
		return
	var nome: String = _fila[0]
	var url := _base_url() + ("carros/lista.json" if nome == "lista" else nome)
	if nome.begins_with("/") and OS.has_feature("web"):
		url = str(JavaScriptBridge.eval("location.origin")) + nome
	print("demo: baixando ", url)
	if _http.request(url) != OK:
		_falhou()


func _pedaco_chegou(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	print("demo: pedaço ", _fila[0] if not _fila.is_empty() else "?", " result=", result, " code=", code, " bytes=", body.size())
	if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
		_falhou()
		return
	var nome: String = _fila.pop_front()
	if nome == "lista":
		var j = JSON.parse_string(body.get_string_from_utf8())
		_lista_pacotes = j if j is Dictionary else {}
		if not _lista_pacotes.has(_baixando):
			_falhou()
			return
		_montar_fila(_baixando)
	else:
		var f := FileAccess.open("user://carros/%s.pck" % _baixando, FileAccess.READ_WRITE)
		if f == null:
			_falhou()
			return
		f.seek_end()
		f.store_buffer(Marshalls.base64_to_raw(body.get_string_from_ascii()))   # pedaço em texto (base64)
		f.close()
		var lv = _lista_pacotes.get(_baixando, 1)
		_progresso = 1.0 - float(_fila.size()) / maxf(1.0, float((lv as Array).size() if lv is Array else lv))
	_proximo_pedaco.call_deferred()   # (o HTTPRequest ainda está fechando o pedido anterior)


func _falhou() -> void:
	var id := _baixando
	_baixando = ""
	_fila = []
	carro_baixado.emit(id, false)


func tem_carro(id: String) -> bool:
	if demo() and id == "lexusnx":   # licença não comercial: fora do link compartilhado
		return false
	if modo != "historia":
		return true
	if (historia.get("garagem", []) as Array).has(id):
		return true
	var sv: Dictionary = historia.get("servico", {})
	return str(sv.get("carro", "")) == id and str(sv.get("estado", "")) in ["fazendo", "pronto"]


## (modo história) paga uma peça/serviço; no modo livre é tudo de graça. false = não tem dinheiro
func pagar(valor: int) -> bool:
	if modo != "historia" or valor <= 0:
		return true
	if dinheiro < valor:
		return false
	dinheiro -= valor
	salvar()
	return true


func indice_de(id: String) -> int:
	for i in carros.size():
		if carros[i]["id"] == id:
			return i
	return -1


## carros que aparecem na loja do Drops (por enquanto: os 5 do começo)
func a_venda() -> Array:
	var out := []
	for i in carros.size():
		if carros[i].get("inicial", false):
			out.append(i)
	return out


func comprar(i: int) -> bool:
	var preco := int(carros[i].get("preco", 0))
	if modo != "historia" or dinheiro < preco or tem_carro(carros[i]["id"]):
		return false
	dinheiro -= preco
	(historia["garagem"] as Array).append(carros[i]["id"])
	idx = i
	if historia.get("etapa", "") == "abertura":
		historia["etapa"] = "primeiro_carro"
	salvar()
	return true


## índices dos carros que dá pra escolher agora (história: só os seus)
func escolhiveis() -> Array:
	var out := []
	for i in carros.size():
		if tem_carro(carros[i]["id"]):
			out.append(i)
	return out


## troca pro próximo carro (passo 1) ou o anterior (-1); no modo história só passa pelos seus
func proximo_carro(passo := 1) -> void:
	var lista := escolhiveis()
	if lista.is_empty():
		return
	var k := lista.find(idx)
	idx = lista[posmod((k if k >= 0 else 0) + (passo if k >= 0 else 0), lista.size())]
	salvar()


func _ir_para(id: String) -> void:
	for i in carros.size():
		if carros[i]["id"] == id:
			idx = i


func ganhar(valor: int) -> void:
	dinheiro += valor
	salvar()


static func reais(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return "R$ " + s + out


func opcoes_som(d: Dictionary) -> Array:
	var o := [["off", "Só o rádio"]]
	if d.get("picape", false) or d.get("bed") != null:
		o.append(["deitado", "Paredão deitado"])
		o.append(["on", "Paredão em pé"])
		if d.get("tampao", false):
			o.append(["tampao", "Tampão com alto-falantes"])
	else:
		o.append(["on", "Caixa no porta-malas"])
	return o
