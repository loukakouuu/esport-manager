class_name Backdrop
extends MarginContainer

## Fond atmosphérique : dégradés, halos de couleur et vignettage.
##
## Pourquoi ça existe : un aplat de couleur unie est ce qui date le plus une
## interface. Un `ColorRect` à #090b10 derrière des rectangles bordés d'un trait
## d'un pixel, c'est très exactement l'esthétique d'un formulaire — et c'est ce
## que le jeu affichait sur son écran-titre. Tout écran de jeu un peu soigné
## pose d'abord de la LUMIÈRE : un fond qui n'est pas uniforme, des halos qui
## suggèrent une source, et des bords assombris qui ramènent l'œil au centre.
##
## Rien de tout cela n'est une texture importée : trois dégradés suffisent, et
## ils coûtent trois quads. On garde donc un dépôt sans binaire.
##
## Comme `Banner`, c'est un MarginContainer : il peint derrière son unique
## enfant et le met en page, sans empiler quoi que ce soit.

## Teinte du halo principal. Prend la couleur de la structure quand il y en a
## une — le fond lui-même porte alors les couleurs de la maison.
@export var tint: Color = Color("#ff5a3c"):
	set(v):
		tint = v
		queue_redraw()

## Second halo, froid, dans le coin opposé. C'est le contraste chaud/froid qui
## donne l'impression de profondeur ; un seul halo aplatit l'image.
@export var counter_tint: Color = Color("#2a6cff"):
	set(v):
		counter_tint = v
		queue_redraw()

@export var glow_strength: float = 0.15:
	set(v):
		glow_strength = v
		queue_redraw()

## Assombrissement des bords. Ramène l'œil vers le centre de l'écran.
@export var vignette: float = 0.55:
	set(v):
		vignette = v
		queue_redraw()

const TOP := Color("#131926")
const BOTTOM := Color("#06070b")

static var _radial: GradientTexture2D = null
static var _linear: GradientTexture2D = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func pad(left: int, top: int, right: int, bottom: int) -> Backdrop:
	add_theme_constant_override("margin_left", left)
	add_theme_constant_override("margin_top", top)
	add_theme_constant_override("margin_right", right)
	add_theme_constant_override("margin_bottom", bottom)
	return self


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


## Dégradé radial blanc→transparent, teinté au moment du tracé.
##
## Une seule texture sert à TOUS les halos et au vignettage : on la module en
## couleur à chaque `draw_texture_rect`. Construire un `GradientTexture2D` par
## halo rallongerait le chargement pour un résultat identique.
static func _radial_tex() -> GradientTexture2D:
	if _radial != null:
		return _radial
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1), Color(1, 1, 1, 0.28), Color(1, 1, 1, 0),
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	_radial = t
	return t


static func _linear_tex() -> GradientTexture2D:
	if _linear != null:
		return _linear
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([TOP, BOTTOM])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_LINEAR
	t.fill_from = Vector2(0.0, 0.0)
	t.fill_to = Vector2(0.0, 1.0)
	t.width = 8
	t.height = 256
	_linear = t
	return t


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var full := Rect2(0, 0, w, h)

	# 1. Le fond : plus clair en haut, comme un ciel. C'est ce qui remplace
	#    l'aplat uni, et à lui seul il enlève déjà l'aspect « formulaire ».
	draw_texture_rect(_linear_tex(), full, false)

	# 2. Deux halos en diagonale, l'un chaud l'autre froid. Ils débordent
	#    volontairement du cadre : une source lumineuse dont on voit le centre
	#    ressemble à une tache, une dont on ne voit que la retombée ressemble à
	#    de la lumière.
	var r := maxf(w, h) * 1.15
	draw_texture_rect(_radial_tex(),
		Rect2(-r * 0.30, -r * 0.45, r, r), false,
		Color(tint.r, tint.g, tint.b, glow_strength))
	draw_texture_rect(_radial_tex(),
		Rect2(w - r * 0.72, h - r * 0.62, r, r), false,
		Color(counter_tint.r, counter_tint.g, counter_tint.b,
			glow_strength * 0.55))

	# 3. Vignettage : le même dégradé radial, retourné. On ne peut pas inverser
	#    une texture au tracé, alors on assombrit les quatre bords par bandes —
	#    quatre quads valent mieux qu'un shader pour un fond statique.
	if vignette > 0.0:
		var edge := Color(0, 0, 0, vignette)
		var clear := Color(0, 0, 0, 0)
		var d := minf(w, h) * 0.38
		_band(Rect2(0, 0, w, d), edge, clear, true)
		_band(Rect2(0, h - d, w, d), clear, edge, true)
		_band(Rect2(0, 0, d, h), edge, clear, false)
		_band(Rect2(w - d, 0, d, h), clear, edge, false)


## Bande dégradée d'une couleur à l'autre, verticale ou horizontale.
func _band(rect: Rect2, from: Color, to: Color, vertical: bool) -> void:
	var p := PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.position + rect.size,
		rect.position + Vector2(0, rect.size.y),
	])
	var c := PackedColorArray([from, from, to, to]) if vertical \
		else PackedColorArray([from, to, to, from])
	draw_polygon(p, c)
