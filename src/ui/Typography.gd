class_name Typography
extends RefCounted

## Polices du jeu, en un seul endroit.
##
## Pourquoi ce fichier existe : `UiKit.label()` simulait le gras par un contour
## de la même couleur, faute de graisse disponible sur la police par défaut de
## Godot. Un contour n'est pas un gras — il épaissit les lettres vers
## l'extérieur ET vers l'intérieur, ce qui bouche les contreformes et rend
## chaque titre légèrement flou. C'est la première raison pour laquelle
## l'interface avait l'air d'une maquette plutôt que d'un jeu.
##
## Trois familles, trois rôles, jamais mélangés :
##   - DISPLAY (Bahnschrift) : grotesque condensée, façon DIN. Titres, capitales
##     espacées, chiffres de tableau de bord. C'est elle qui donne le ton
##     « diffusion esport » : condensée, elle laisse tenir un titre en capitales
##     sur une seule ligne sans écraser la mise en page.
##   - BODY (Segoe UI) : lisible à 12 px, avec un VRAI fichier de gras.
##   - MONO (Consolas) : chiffres à chasse fixe. Dans une colonne de notes ou
##     d'argent, des chiffres de largeur variable font danser la virgule d'une
##     ligne à l'autre ; l'œil ne peut plus comparer une colonne d'un coup.
##
## Ces polices sont prises sur le SYSTÈME : aucun fichier à télécharger, et
## elles existent sur toute installation de Windows 10/11. Les listes de noms
## ci-dessous contiennent des équivalents Linux/macOS, essayés dans l'ordre —
## `SystemFont` prend le premier nom qu'il trouve installé.
##
## Pour passer un jour à des polices embarquées (distribution hors Windows,
## rendu identique partout) : déposer les .ttf dans `assets/fonts/`, remplacer
## le corps des trois fabriques par un `load()`, et rien d'autre ne bouge.

## Grotesques condensées, de la plus proche du rendu visé à la plus courante.
const DISPLAY_NAMES := ["Bahnschrift", "DIN Next LT Pro", "Oswald",
	"Barlow Condensed", "Roboto Condensed", "Liberation Sans Narrow",
	"Helvetica Neue Condensed", "Arial Narrow", "Segoe UI"]

const BODY_NAMES := ["Segoe UI", "Inter", "Roboto", "Noto Sans",
	"DejaVu Sans", "Helvetica Neue", "Arial"]

const MONO_NAMES := ["Consolas", "JetBrains Mono", "Cascadia Mono",
	"DejaVu Sans Mono", "Menlo", "Courier New"]

## Construire une SystemFont coûte un accès disque : on ne le fait qu'une fois.
static var _cache := {}


## Grotesque condensée pour les titres et les capitales espacées.
static func display(weight: int = 700) -> Font:
	return _make("display", DISPLAY_NAMES, weight)


## Police de lecture courante.
static func body(weight: int = 400) -> Font:
	return _make("body", BODY_NAMES, weight)


## Police de lecture en gras — un vrai fichier gras, pas un contour.
static func body_bold() -> Font:
	return body(700)


## Chiffres à chasse fixe, pour les colonnes de nombres.
static func mono(weight: int = 400) -> Font:
	return _make("mono", MONO_NAMES, weight)


static func _make(key: String, names: Array, weight: int) -> Font:
	var id := "%s:%d" % [key, weight]
	if _cache.has(id):
		return _cache[id]
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.font_weight = weight
	# Le rendu des petites tailles (11-13 px, l'essentiel de l'interface) vit ou
	# meurt sur ce réglage : sans positionnement sous-pixel, l'espacement des
	# lettres devient irrégulier et le texte paraît « sale ».
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.multichannel_signed_distance_field = false
	_cache[id] = f
	return f


## Thème appliqué à la racine de l'application.
##
## Passer par un `Theme` plutôt que par un override sur chaque Label : le thème
## descend tout seul dans l'arbre, y compris dans les contrôles que l'on ne
## construit pas soi-même (info-bulles, listes déroulantes, champs de saisie).
## Sans lui, ces contrôles-là garderaient la police par défaut de Godot et
## trahiraient l'ensemble.
static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = body()
	t.default_font_size = 13

	# Les info-bulles sont le seul élément d'interface que Godot dessine
	# lui-même par-dessus tout le reste : laissées telles quelles, elles
	# arrivent en blanc sur gris clair au milieu d'un jeu sombre.
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color("#0a0c11")
	tip.set_border_width_all(1)
	tip.border_color = Color("#39435a")
	tip.set_corner_radius_all(5)
	tip.content_margin_left = 9
	tip.content_margin_right = 9
	tip.content_margin_top = 6
	tip.content_margin_bottom = 6
	tip.shadow_size = 10
	tip.shadow_color = Color(0, 0, 0, 0.5)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", Color("#e8ebf2"))
	t.set_font_size("font_size", "TooltipLabel", 12)
	return t
