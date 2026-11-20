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

var carros: Array = []
var idx := 0                 # carro escolhido
var personagem := "protagonista"   # quem anda a pé
var visual := {}   # (fase 2) roupa, cabelo e pele do protagonista (ver Pessoa.VISUAL_PADRAO)
var configs := {}            # id do carro -> configuração
var dinheiro := 1000000
var recordes := {}


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
	if OS.has_environment("DROPS_VISUAL"):   # testes: visual do protagonista em JSON
		visual = JSON.parse_string(OS.get_environment("DROPS_VISUAL"))
	if OS.has_environment("DROPS_PERSONAGEM"):
		personagem = OS.get_environment("DROPS_PERSONAGEM")
	if OS.has_environment("DROPS_CARRO"):   # testes: abre direto num carro
		for i in carros.size():
			if carros[i]["id"] == OS.get_environment("DROPS_CARRO"):
				idx = i
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
	var f := FileAccess.open(ARQUIVO, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"v31": true, "v43": true, "v44": true, "visual": visual, "idx": idx, "carro": carros[idx]["id"], "personagem": personagem, "configs": configs, "dinheiro": dinheiro, "recordes": recordes, "volume_musica": volume_musica, "faixa": faixa, "graficos": graficos, "tutorial": tutorial_feito, "dicas": dicas}))


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
