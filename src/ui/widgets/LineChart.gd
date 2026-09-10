class_name LineChart
extends Control

## Courbe temporelle : progression d'un joueur, trésorerie, forme.
##
## Volontairement minimaliste — pas de zoom, pas d'interaction. Un graphe dans
## un jeu de gestion sert à répondre à « ça monte ou ça descend ? », et cette
## question se règle en un coup d'œil ou pas du tout.

var series: Array = []       # [{"values": [float], "color": Color, "name": String}]
var labels: Array[String] = []   # libellés d'abscisse (facultatifs, espacés)
var min_value: float = 0.0
var max_value: float = 100.0
var auto_range: bool = true
var zero_line: bool = false
var fill: bool = true


func _init() -> void:
	custom_minimum_size = Vector2(280, 130)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func make(values: Array, color: Color, x_labels: Array[String] = [],
		fill_area: bool = true) -> LineChart:
	var c := LineChart.new()
	c.add_series(values, color, "")
	c.labels = x_labels.duplicate()
	c.fill = fill_area
	return c


func add_series(values: Array, color: Color, series_name: String) -> void:
	var f: Array = []
	for v in values:
		f.append(float(v))
	series.append({"values": f, "color": color, "name": series_name})
	queue_redraw()


func _compute_range() -> void:
	if not auto_range:
		return
	var lo := INF
	var hi := -INF
	for s in series:
		for v in (s as Dictionary)["values"]:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
	if lo == INF:
		lo = 0.0
		hi = 1.0
	if absf(hi - lo) < 0.0001:
		hi = lo + 1.0
	# Une marge de 12 % évite que la courbe touche les bords du cadre.
	var pad := (hi - lo) * 0.12
	min_value = lo - pad
	max_value = hi + pad
	if zero_line:
		min_value = minf(min_value, 0.0)
		max_value = maxf(max_value, 0.0)


func _draw() -> void:
	_compute_range()
	var pad_left := 44.0
	var pad_bottom := 18.0 if not labels.is_empty() else 8.0
	var rect := Rect2(pad_left, 6.0, size.x - pad_left - 8.0,
		size.y - pad_bottom - 6.0)
	if rect.size.x <= 4.0 or rect.size.y <= 4.0:
		return
	var font := ThemeDB.fallback_font

	draw_rect(rect, Color("#0e1117"), true)
	for i in 5:
		var t := float(i) / 4.0
		var y := rect.position.y + rect.size.y * t
		draw_line(Vector2(rect.position.x, y),
			Vector2(rect.end.x, y), UiKit.BORDER_SOFT, 1.0)
		var val := max_value - (max_value - min_value) * t
		draw_string(font, Vector2(2.0, y + 4.0), _fmt(val),
			HORIZONTAL_ALIGNMENT_LEFT, pad_left - 6.0, UiKit.FS_MICRO,
			UiKit.TEXT_FAINT)

	if zero_line and min_value < 0.0 and max_value > 0.0:
		var yz := rect.position.y + rect.size.y * (max_value / (max_value - min_value))
		draw_line(Vector2(rect.position.x, yz), Vector2(rect.end.x, yz),
			UiKit.TEXT_FAINT, 1.0)

	for s in series:
		var d: Dictionary = s
		var vals: Array = d["values"]
		var color: Color = d["color"]
		if vals.size() < 2:
			if vals.size() == 1:
				draw_circle(_point(rect, 0, 1, float(vals[0])), 3.0, color)
			continue
		var pts := PackedVector2Array()
		for i in vals.size():
			pts.append(_point(rect, i, vals.size(), float(vals[i])))
		if fill:
			var area := pts.duplicate()
			area.append(Vector2(pts[pts.size() - 1].x, rect.end.y))
			area.append(Vector2(pts[0].x, rect.end.y))
			draw_colored_polygon(area, Color(color.r, color.g, color.b, 0.14))
		draw_polyline(pts, color, 2.0, true)
		draw_circle(pts[pts.size() - 1], 3.0, color)

	if labels.is_empty():
		return
	# On n'affiche qu'un libellé sur N pour ne pas les empiler.
	var step := maxi(1, int(ceil(float(labels.size()) * 46.0 / rect.size.x)))
	for i in labels.size():
		if i % step != 0 and i != labels.size() - 1:
			continue
		var x := rect.position.x + rect.size.x * (float(i)
			/ maxf(float(labels.size() - 1), 1.0))
		draw_string(font, Vector2(x - 14.0, size.y - 4.0), labels[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FS_MICRO, UiKit.TEXT_FAINT)


func _point(rect: Rect2, i: int, n: int, v: float) -> Vector2:
	var x := rect.position.x + rect.size.x * (float(i) / maxf(float(n - 1), 1.0))
	var t := (v - min_value) / maxf(max_value - min_value, 0.0001)
	return Vector2(x, rect.end.y - rect.size.y * clampf(t, 0.0, 1.0))


func _fmt(v: float) -> String:
	if absf(v) >= 1000000.0:
		return "%.1fM" % (v / 1000000.0)
	if absf(v) >= 1000.0:
		return "%.0fk" % (v / 1000.0)
	if absf(v) >= 10.0:
		return "%.0f" % v
	return "%.1f" % v
