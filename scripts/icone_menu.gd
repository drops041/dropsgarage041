class_name IconeMenu
extends Control
## Ícones desenhados no código (não dependem de fonte com emoji): carro, suspensão, pintura, roda, kit,
## neon, som, personagem, música e rolê.

var tipo := "carro"
var cor := Color.WHITE
var grossura := 3.0


func _init(t := "carro", c := Color.WHITE) -> void:
	tipo = t
	cor = c
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) / 2.0
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var g := maxf(2.0, grossura * s / 64.0)
	match tipo:
		"carro":
			var pts := PackedVector2Array([p.call(0.06, 0.66), p.call(0.08, 0.52), p.call(0.28, 0.46), p.call(0.4, 0.3),
				p.call(0.66, 0.3), p.call(0.8, 0.46), p.call(0.94, 0.5), p.call(0.95, 0.66)])
			draw_colored_polygon(pts, cor)
			for x in [0.27, 0.76]:
				draw_circle(p.call(x, 0.68), s * 0.11, Color(0, 0, 0, 0.85))
				draw_circle(p.call(x, 0.68), s * 0.08, cor)
				draw_circle(p.call(x, 0.68), s * 0.035, Color(0, 0, 0, 0.85))
			draw_colored_polygon(PackedVector2Array([p.call(0.42, 0.34), p.call(0.52, 0.34), p.call(0.52, 0.45), p.call(0.33, 0.45)]), Color(0, 0, 0, 0.55))
			draw_colored_polygon(PackedVector2Array([p.call(0.56, 0.34), p.call(0.65, 0.34), p.call(0.74, 0.45), p.call(0.56, 0.45)]), Color(0, 0, 0, 0.55))
		"medidas":
			# mola da suspensão com setas pra cima e pra baixo
			var zig := PackedVector2Array()
			for i in 9:
				zig.append(p.call(0.36 if i % 2 == 0 else 0.64, 0.2 + i * 0.075))
			draw_polyline(zig, cor, g, true)
			draw_line(p.call(0.28, 0.2), p.call(0.72, 0.2), cor, g * 1.3)
			draw_line(p.call(0.28, 0.8), p.call(0.72, 0.8), cor, g * 1.3)
			for y in [0.12, 0.88]:
				var d := -1.0 if y < 0.5 else 1.0
				draw_colored_polygon(PackedVector2Array([p.call(0.84, y), p.call(0.76, y - d * 0.09), p.call(0.92, y - d * 0.09)]), cor)
			draw_line(p.call(0.84, 0.2), p.call(0.84, 0.8), cor, g * 0.7)
		"pintura":
			# lata de spray
			draw_rect(Rect2(p.call(0.3, 0.36), Vector2(0.34, 0.52) * s), cor)
			draw_rect(Rect2(p.call(0.38, 0.24), Vector2(0.18, 0.12) * s), cor)
			draw_rect(Rect2(p.call(0.42, 0.16), Vector2(0.1, 0.08) * s), cor)
			draw_rect(Rect2(p.call(0.3, 0.5), Vector2(0.34, 0.1) * s), Color(0, 0, 0, 0.45))
			for k in 5:
				draw_circle(p.call(0.66 + k * 0.05, 0.18 - 0.05 + float(k % 3) * 0.05), s * 0.022, cor)
		"rodas":
			var c: Vector2 = p.call(0.5, 0.5)
			draw_arc(c, s * 0.4, 0, TAU, 40, cor, g * 1.6, true)
			draw_arc(c, s * 0.3, 0, TAU, 40, cor, g * 0.8, true)
			for k in 6:
				var a := TAU * k / 6.0
				draw_line(c + Vector2(cos(a), sin(a)) * s * 0.08, c + Vector2(cos(a), sin(a)) * s * 0.29, cor, g * 1.1, true)
			draw_circle(c, s * 0.08, cor)
		"kit":
			# aerofólio
			draw_colored_polygon(PackedVector2Array([p.call(0.08, 0.3), p.call(0.92, 0.3), p.call(0.88, 0.42), p.call(0.12, 0.42)]), cor)
			draw_rect(Rect2(p.call(0.26, 0.42), Vector2(0.07, 0.3) * s), cor)
			draw_rect(Rect2(p.call(0.67, 0.42), Vector2(0.07, 0.3) * s), cor)
			draw_rect(Rect2(p.call(0.1, 0.72), Vector2(0.8, 0.08) * s), cor)
		"neon":
			var c2: Vector2 = p.call(0.5, 0.42)
			draw_circle(c2, s * 0.2, cor)
			draw_rect(Rect2(p.call(0.42, 0.6), Vector2(0.16, 0.14) * s), cor)
			draw_line(p.call(0.42, 0.78), p.call(0.58, 0.78), cor, g)
			for k in 7:
				var a := PI + PI * k / 6.0
				draw_line(c2 + Vector2(cos(a), sin(a)) * s * 0.28, c2 + Vector2(cos(a), sin(a)) * s * 0.38, cor, g, true)
		"som":
			draw_rect(Rect2(p.call(0.2, 0.1), Vector2(0.6, 0.8) * s), cor)
			draw_circle(p.call(0.5, 0.6), s * 0.19, Color(0, 0, 0, 0.75))
			draw_circle(p.call(0.5, 0.6), s * 0.07, cor)
			draw_circle(p.call(0.5, 0.26), s * 0.08, Color(0, 0, 0, 0.75))
		"personagem":
			draw_circle(p.call(0.5, 0.3), s * 0.15, cor)
			draw_colored_polygon(PackedVector2Array([p.call(0.2, 0.9), p.call(0.26, 0.6), p.call(0.5, 0.52), p.call(0.74, 0.6), p.call(0.8, 0.9)]), cor)
		"musica":
			draw_circle(p.call(0.32, 0.74), s * 0.11, cor)
			draw_circle(p.call(0.72, 0.64), s * 0.11, cor)
			draw_line(p.call(0.42, 0.74), p.call(0.42, 0.22), cor, g * 1.2)
			draw_line(p.call(0.82, 0.64), p.call(0.82, 0.14), cor, g * 1.2)
			draw_colored_polygon(PackedVector2Array([p.call(0.4, 0.2), p.call(0.84, 0.1), p.call(0.84, 0.22), p.call(0.4, 0.32)]), cor)
		"role":
			# bandeira quadriculada
			draw_line(p.call(0.2, 0.1), p.call(0.2, 0.92), cor, g * 1.2)
			for i in 4:
				for j in 3:
					if (i + j) % 2 == 0:
						draw_rect(Rect2(p.call(0.22 + i * 0.16, 0.12 + j * 0.13), Vector2(0.16, 0.13) * s), cor)
			draw_rect(Rect2(p.call(0.22, 0.12), Vector2(0.64, 0.39) * s), cor, false, g * 0.6)
