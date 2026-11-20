class_name RedeCIC
extends RefCounted
## Rede de ruas da CIC (do ruas.json): rua mais perto, nome da rua, pontos pro trânsito e desafios.

const CEL := 40.0
const TIPOS_TRANSITO := ["residential", "tertiary", "secondary", "primary", "unclassified", "tertiary_link", "living_street",
	"motorway", "motorway_link", "trunk", "trunk_link", "primary_link", "secondary_link"]
const AVENIDAS := ["motorway", "trunk", "primary", "secondary", "motorway_link", "trunk_link", "primary_link"]
const MAO_UNICA := ["motorway", "motorway_link", "trunk", "trunk_link"]   # pista dupla: cada lado é uma rua de mão única


func mao_unica(i: int) -> bool:
	return ruas[i]["tipo"] in MAO_UNICA

var ruas: Array = []          # {nome, tipo, w, pts: PackedVector2Array, cum: PackedFloat32Array, L}
var _grade := {}              # Vector2i -> [[rua, seg], ...]
var _vert := {}               # Vector2i (2.5 m) -> [[rua, vértice], ...]


func carregar(caminho: String) -> bool:
	var f := FileAccess.open(caminho, FileAccess.READ)
	if f == null:
		return false
	var lista = JSON.parse_string(f.get_as_text())
	if typeof(lista) != TYPE_ARRAY:
		return false
	for r in lista:
		var pts := PackedVector2Array()
		for p in r["pts"]:
			pts.append(Vector2(p[0], p[1]))
		if pts.size() < 2:
			continue
		var cum := PackedFloat32Array([0.0])
		for k in range(1, pts.size()):
			cum.append(cum[k - 1] + pts[k].distance_to(pts[k - 1]))
		var i := ruas.size()
		ruas.append({"nome": r["nome"], "tipo": r["tipo"], "w": float(r["largura"]), "pts": pts, "cum": cum, "L": cum[cum.size() - 1]})
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var n := int(ceil(a.distance_to(b) / (CEL * 0.5))) + 1
			for j in n + 1:
				var c := _cel(a.lerp(b, float(j) / n))
				if not _grade.has(c):
					_grade[c] = []
				var item := [i, k]
				if not (_grade[c] as Array).has(item):
					_grade[c].append(item)
		for k in pts.size():
			var c2 := Vector2i(floori(pts[k].x / 2.5), floori(pts[k].y / 2.5))
			if not _vert.has(c2):
				_vert[c2] = []
			_vert[c2].append([i, k])
	return true


func _cel(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CEL), floori(p.y / CEL))


## rua mais perto do ponto: {i, s, d, ponto: Vector2, dir: Vector2, nome}
func mais_perto(p3: Vector3, raio := 40.0) -> Dictionary:
	var p := Vector2(p3.x, p3.z)
	var c := _cel(p)
	var melhor := {}
	var md := raio
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var k := c + Vector2i(dx, dz)
			if not _grade.has(k):
				continue
			for item in _grade[k]:
				var r: Dictionary = ruas[item[0]]
				var a: Vector2 = r["pts"][item[1]]
				var b: Vector2 = r["pts"][item[1] + 1]
				var ab := b - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
				var q := a + ab * t
				var d := q.distance_to(p)
				if d < md:
					md = d
					melhor = {"i": item[0], "s": float(r["cum"][item[1]]) + ab.length() * t, "d": d, "ponto": q,
						"dir": ab.normalized(), "nome": r["nome"]}
	return melhor


func ponto(i: int, s: float) -> Vector2:
	var r: Dictionary = ruas[i]
	var cum: PackedFloat32Array = r["cum"]
	var pts: PackedVector2Array = r["pts"]
	s = clampf(s, 0.0, r["L"])
	var k := cum.bsearch(s) - 1
	k = clampi(k, 0, pts.size() - 2)
	var L := cum[k + 1] - cum[k]
	return pts[k].lerp(pts[k + 1], (s - cum[k]) / L if L > 1e-6 else 0.0)


func direcao(i: int, s: float) -> Vector2:
	var r: Dictionary = ruas[i]
	var cum: PackedFloat32Array = r["cum"]
	var pts: PackedVector2Array = r["pts"]
	var k := clampi(cum.bsearch(clampf(s, 0.0, r["L"])) - 1, 0, pts.size() - 2)
	return (pts[k + 1] - pts[k]).normalized()


## ruas que encostam na ponta (0 = começo, 1 = fim) da rua i: [[j, s, sentido], ...]
func saidas(i: int, ponta: int) -> Array:
	var r: Dictionary = ruas[i]
	var pts: PackedVector2Array = r["pts"]
	var p: Vector2 = pts[0] if ponta == 0 else pts[pts.size() - 1]
	var res: Array = []
	var c := Vector2i(floori(p.x / 2.5), floori(p.y / 2.5))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var k := c + Vector2i(dx, dz)
			if not _vert.has(k):
				continue
			for item in _vert[k]:
				var j: int = item[0]
				if j == i or not (ruas[j]["tipo"] in TIPOS_TRANSITO):
					continue
				var rj: Dictionary = ruas[j]
				var v: int = item[1]
				if (rj["pts"][v] as Vector2).distance_to(p) > 2.5:
					continue
				var s: float = rj["cum"][v]
				if v < (rj["pts"] as PackedVector2Array).size() - 1:
					res.append([j, s, 1.0])
				if v > 0 and not (rj["tipo"] in MAO_UNICA):
					res.append([j, s, -1.0])
	return res


## ponto aleatório de rua entre rmin e rmax do centro: {i, s} ({} se não achar)
func ponto_aleatorio(centro: Vector3, rmin: float, rmax: float, tipos := TIPOS_TRANSITO) -> Dictionary:
	for tent in 60:
		var a := randf() * TAU
		var d := randf_range(rmin, rmax)
		var p := Vector3(centro.x + cos(a) * d, 0, centro.z + sin(a) * d)
		var mp := mais_perto(p, 45.0)
		if mp.is_empty() or not (ruas[mp["i"]]["tipo"] in tipos):
			continue
		var r: Dictionary = ruas[mp["i"]]
		if float(r["L"]) < 30.0:
			continue
		var dd := (mp["ponto"] as Vector2).distance_to(Vector2(centro.x, centro.z))
		if dd < rmin or dd > rmax:
			continue
		return {"i": mp["i"], "s": clampf(mp["s"], 8.0, float(r["L"]) - 8.0)}
	return {}
