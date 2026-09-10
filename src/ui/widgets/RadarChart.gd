class_name RadarChart
extends Control

## Toile d'araignée : profil d'un joueur sur quelques axes agrégés.
##
## Un tableau de 27 attributs dit la vérité mais ne se lit pas. Le radar donne
## la SILHOUETTE — « c'est un mécanicien pur », « c'est un cerveau » — en un
## coup d'œil, et permet de superposer un second joueur pour comparer.

var axes: Array[String] = []          # libellés courts
var series: Array = []                # [{"values": [0..1], "color": Color, "name": String}]
var max_value: float = 20.0
var rings: int = 4


func _init() -> void:
	custom_minimum_size = Vector2(240, 240)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func make(axis_labels: Array[String], values: Array[float],
		color: Color, max_v: float = 20.0) -> RadarChart:
	var r := RadarChart.new()
	r.axes = axis_labels.duplicate()
	r.max_value = max_v
	r.add_series(values, color, "")
	return r


func add_series(values: Array[float], color: Color, series_name: String) -> void:
	series.append({"values": values.duplicate(), "color": color,
		"name": series_name})
	queue_redraw()


func _draw() -> void:
	if axes.is_empty():
		return
	var n := axes.size()
	# On réserve de la marge pour les libellés, qui débordent du polygone.
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 34.0
	if radius <= 8.0:
		return

	for ring in range(1, rings + 1):
		var rr := radius * float(ring) / float(rings)
		var pts := PackedVector2Array()
		for i in n:
			pts.append(center + _dir(i, n) * rr)
		pts.append(pts[0])
		draw_polyline(pts, UiKit.BORDER, 1.0, true)

	for i in n:
		var edge := center + _dir(i, n) * radius
		draw_line(center, edge, UiKit.BORDER_SOFT, 1.0, true)

	var font := ThemeDB.fallback_font
	for s in series:
		var d: Dictionary = s
		var vals: Array = d["values"]
		var color: Color = d["color"]
		var poly := PackedVector2Array()
		for i in n:
			var v := clampf(float(vals[i]) / max_value, 0.0, 1.0) if i < vals.size() else 0.0
			poly.append(center + _dir(i, n) * radius * maxf(v, 0.02))
		draw_colored_polygon(poly, Color(color.r, color.g, color.b, 0.22))
		var outline := poly.duplicate()
		outline.append(poly[0])
		draw_polyline(outline, color, 2.0, true)
		for p in poly:
			draw_circle(p, 2.5, color)

	for i in n:
		var dir := _dir(i, n)
		var anchor := center + dir * (radius + 13.0)
		var text := axes[i]
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			UiKit.FS_SMALL).x
		# Le libellé se cale à gauche, à droite ou centré selon son côté, sinon
		# il chevauche le polygone.
		var offset := -tw * 0.5
		if dir.x > 0.35:
			offset = 0.0
		elif dir.x < -0.35:
			offset = -tw
		draw_string(font, anchor + Vector2(offset, 4.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FS_SMALL, UiKit.TEXT_DIM)


## Premier axe en haut, puis sens horaire.
func _dir(i: int, n: int) -> Vector2:
	var a := -PI * 0.5 + TAU * float(i) / float(n)
	return Vector2(cos(a), sin(a))
