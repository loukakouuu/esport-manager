class_name Banner
extends MarginContainer

## Bandeau incliné aux couleurs de la structure : la signature « diffusion ».
##
## Pourquoi un Control qui se dessine lui-même plutôt qu'un StyleBoxFlat : un
## StyleBox ne sait faire que des rectangles à coins arrondis. Or l'inclinaison
## EST le code visuel de l'habillage esport — les incrustations de score, les
## cartouches de joueur et les bas de page d'une diffusion sont tous des
## parallélogrammes. C'est ce qui distingue un écran de jeu d'un tableau de bord
## d'administration, et ça ne coûte que quelques polygones.
##
## Pourquoi un MarginContainer et pas un Control nu : il faut à la fois POSER du
## contenu dessus et le METTRE EN PAGE. Un parent dessine toujours avant ses
## enfants, donc `_draw()` peint derrière le contenu sans qu'on ait à empiler
## quoi que ce soit — et le bandeau n'a jamais qu'UN enfant, ce qui respecte
## l'invariant vérifié par `tools/ui_check.gd`. Sans enfant, il fait très bien
## une simple bande décorative.
##
## Le bandeau se dégrade vers la droite jusqu'à disparaître : la couleur signe
## le bord gauche puis rend la place au texte. Un aplat de couleur d'un bout à
## l'autre rendrait tout titre posé dessus illisible.

## Inclinaison, en pixels d'avancée horizontale sur toute la hauteur.
## 0.28 × hauteur ≈ 16° : lisible comme une inclinaison volontaire, sans
## transformer les bords en pointes.
const SLANT_RATIO := 0.28

## Avancée maximale, en pixels.
##
## Sans ce plafond, l'inclinaison étant proportionnelle à la hauteur, un bandeau
## de 640 px (une grande carte de choix) avance de 180 px : le liseré traverse
## alors la carte en biais d'un coin à l'autre et barre le texte — on ne lit
## plus un habillage, on lit une rayure. Le plafond ne change rien aux bandeaux
## bas (barre haute, en-têtes d'écran), qui restent sous la limite.
const SLANT_MAX := 34.0

@export var tint: Color = Color("#ff5a3c"):
	set(v):
		tint = v
		queue_redraw()

## Largeur du dégradé coloré, en fraction de la largeur totale.
@export var spread: float = 0.55:
	set(v):
		spread = v
		queue_redraw()

## Fond du bandeau sous la couleur. Transparent = on laisse voir le dessous.
@export var base: Color = Color(0, 0, 0, 0):
	set(v):
		base = v
		queue_redraw()

## Épaisseur du liseré vif sur l'arête gauche. 0 pour ne pas en dessiner.
@export var edge: float = 3.0:
	set(v):
		edge = v
		queue_redraw()

## Trait fin le long du bord bas, qui referme le bandeau sur le contenu.
@export var underline: bool = true:
	set(v):
		underline = v
		queue_redraw()

## Opacité du dégradé à son point le plus vif.
@export var intensity: float = 0.30:
	set(v):
		intensity = v
		queue_redraw()


func _init(p_tint: Color = Color("#ff5a3c")) -> void:
	tint = p_tint
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Marges internes du contenu posé sur le bandeau.
func pad(left: int, top: int, right: int, bottom: int) -> Banner:
	add_theme_constant_override("margin_left", left)
	add_theme_constant_override("margin_top", top)
	add_theme_constant_override("margin_right", right)
	add_theme_constant_override("margin_bottom", bottom)
	return self


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var slant := minf(h * SLANT_RATIO, SLANT_MAX)

	if base.a > 0.0:
		draw_rect(Rect2(0, 0, w, h), base)

	# Le dégradé : un quadrilatère incliné dont les deux sommets de droite sont
	# transparents. `draw_polygon` interpole la couleur entre les sommets, ce
	# qui donne le fondu sans passer par un shader ni une texture.
	var band := maxf(spread * w, slant + 1.0)
	var hot := Color(tint.r, tint.g, tint.b, intensity)
	var cold := Color(tint.r, tint.g, tint.b, 0.0)
	draw_polygon(
		PackedVector2Array([
			Vector2(slant, 0), Vector2(band + slant, 0),
			Vector2(band, h), Vector2(0, h),
		]),
		PackedColorArray([hot, cold, cold, hot]))

	if edge > 0.0:
		# Le liseré vif : c'est LUI qu'on voit en premier, le dégradé n'est que
		# son halo. Sans lui, le bandeau ressemble à une tache.
		draw_colored_polygon(PackedVector2Array([
			Vector2(slant, 0), Vector2(slant + edge, 0),
			Vector2(edge, h), Vector2(0, h),
		]), tint)

	if underline:
		draw_rect(Rect2(0, h - 1.0, w, 1.0),
			Color(tint.r, tint.g, tint.b, 0.22))
