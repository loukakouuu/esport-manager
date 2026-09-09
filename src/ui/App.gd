class_name App
extends Control

## Coquille de l'application : barre supérieure, navigation, zone de contenu.

const SCREENS := {
	"home": preload("res://src/ui/screens/HomeScreen.gd"),
	"squad": preload("res://src/ui/screens/SquadScreen.gd"),
	"player": preload("res://src/ui/screens/PlayerScreen.gd"),
	"tactics": preload("res://src/ui/screens/TacticsScreen.gd"),
	"calendar": preload("res://src/ui/screens/CalendarScreen.gd"),
	"competition": preload("res://src/ui/screens/CompetitionScreen.gd"),
	"transfers": preload("res://src/ui/screens/TransfersScreen.gd"),
	"finance": preload("res://src/ui/screens/FinanceScreen.gd"),
	"facilities": preload("res://src/ui/screens/FacilitiesScreen.gd"),
	"inbox": preload("res://src/ui/screens/InboxScreen.gd"),
	"match": preload("res://src/ui/screens/MatchScreen.gd"),
}

const NAV := [
	["home", "Accueil"],
	["squad", "Effectif"],
	["tactics", "Tactique"],
	["calendar", "Calendrier"],
	["competition", "Compétition"],
	["transfers", "Marché"],
	["finance", "Finances"],
	["facilities", "Infrastructures"],
	["inbox", "Messages"],
]

var game: Node = null
var current_screen: Screen = null
var current_name := "home"
var current_args := {}

var _header: HBoxContainer
var _content: MarginContainer
var _nav_box: VBoxContainer


func _ready() -> void:
	game = get_node("/root/Game")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_shell()
	game.state_changed.connect(_on_state_changed)
	game.world_loaded.connect(_on_state_changed)
	if game.has_world() and game.world.player_org_id != "":
		navigate("home")
	else:
		_show_new_game()


func _build_shell() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	_header = UiKit.hbox(14)
	var header_panel := UiKit.panel(10)
	header_panel.add_child(_header)
	root.add_child(header_panel)

	var body := UiKit.hbox(0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var nav_panel := UiKit.panel(8)
	nav_panel.custom_minimum_size = Vector2(180, 0)
	_nav_box = UiKit.vbox(4)
	nav_panel.add_child(_nav_box)
	body.add_child(nav_panel)

	_content = MarginContainer.new()
	_content.add_theme_constant_override("margin_left", 14)
	_content.add_theme_constant_override("margin_right", 14)
	_content.add_theme_constant_override("margin_top", 12)
	_content.add_theme_constant_override("margin_bottom", 12)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_content)


func navigate(screen_name: String, args: Dictionary = {}) -> void:
	if not SCREENS.has(screen_name):
		return
	current_name = screen_name
	current_args = args
	for c in _content.get_children():
		c.queue_free()
	var scr: Screen = SCREENS[screen_name].new()
	scr.setup(self)
	for k in args:
		scr.set(k, args[k])
	_content.add_child(scr)
	current_screen = scr
	scr.refresh()
	_rebuild_header()
	_rebuild_nav()


func _on_state_changed() -> void:
	if game.has_world() and game.world.player_org_id == "":
		_show_new_game()
		return
	if current_screen != null and is_instance_valid(current_screen):
		current_screen.refresh()
	_rebuild_header()
	_rebuild_nav()


func _rebuild_header() -> void:
	for c in _header.get_children():
		c.queue_free()
	if not game.has_world():
		return
	var w: World = game.world
	var o: Organization = game.my_org()
	if o == null:
		return

	_header.add_child(UiKit.label(o.name, 18, UiKit.TEXT))
	_header.add_child(UiKit.label(GameDate.format_full(w.today), 14, UiKit.TEXT_DIM))
	_header.add_child(UiKit.label(Money.fmt(o.cash()), 15,
		UiKit.GOOD if o.cash() >= 0 else UiKit.BAD))
	var monthly := FinanceSystem.projected_monthly_result(w, o)
	_header.add_child(UiKit.label("%s / mois" % Money.fmt_short(monthly), 13,
		UiKit.GOOD if monthly >= 0 else UiKit.BAD))
	_header.add_child(UiKit.spacer())

	_header.add_child(UiKit.button("Avancer 1 jour", func(): game.advance_day()))
	_header.add_child(UiKit.button("Avancer 1 semaine", func(): game.advance_days(7)))
	_header.add_child(UiKit.button("Jusqu'au prochain match",
		func(): game.advance_to_next_match()))
	_header.add_child(UiKit.button("Sauvegarder",
		func(): game.save_game("partie1")))


func _rebuild_nav() -> void:
	for c in _nav_box.get_children():
		c.queue_free()
	if not game.has_world():
		return
	for entry in NAV:
		var key: String = entry[0]
		var label: String = entry[1]
		if key == "inbox":
			var n: int = game.unread_count()
			if n > 0:
				label += "  (%d)" % n
		var b := UiKit.button(label, func(): navigate(key))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if key == current_name:
			b.add_theme_color_override("font_color", UiKit.ACCENT)
		_nav_box.add_child(b)
	_nav_box.add_child(UiKit.spacer())
	if game.last_player_result != null:
		_nav_box.add_child(UiKit.button("Dernier match",
			func(): navigate("match")))


func _show_new_game() -> void:
	for c in _content.get_children():
		c.queue_free()
	for c in _nav_box.get_children():
		c.queue_free()
	for c in _header.get_children():
		c.queue_free()
	var scr := preload("res://src/ui/screens/NewGameScreen.gd").new()
	scr.setup(self)
	_content.add_child(scr)
	current_screen = scr
	scr.refresh()
