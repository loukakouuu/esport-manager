extends Screen

## Table de négociation : une clause par ligne, et l'avis de l'agent en face.
##
## Le parti pris est celui du reste du jeu — INFORMATION IMPARFAITE. L'agent
## dit « insuffisant » ou « juste limite », jamais « il manque 8 400 $ ». On
## apprend en proposant, et chaque proposition coûte de la patience.
##
## L'écran ne calcule rien : tous les avis viennent de NegotiationSystem, qui
## est aussi ce que consulte la simulation. Deux jugements concurrents
## finiraient par se contredire à l'écran.

const T := Negotiation.Terms

## Deux pas de réglage par clause : un fin pour chercher la limite, un gros
## pour ne pas cliquer trente fois. Les montants sont en CENTS (règle du
## projet) — d'où les zéros, commentés en dollars.
const STEPS := {
	T.SALARY: [100_000, 1_000_000],     # 1 000 $ et 10 000 $
	T.BONUS: [50_000, 500_000],         # 500 $ et 5 000 $
	T.BUYOUT: [500_000, 5_000_000],     # 5 000 $ et 50 000 $
	T.MONTHS: [1, 6],
	T.PRIZE: [1, 5],
}

var negotiation_id: String = ""


func build() -> void:
	var n: Negotiation = game().negotiation(negotiation_id)
	if n == null:
		add_child(UiKit.empty_state("Cette discussion n'existe plus.",
			"Ouvrez-en une depuis le marché ou la fiche d'un joueur."))
		return
	var w := world()
	var p := w.player(n.player_id)
	var o: Organization = game().my_org()
	if p == null or o == null:
		add_child(UiKit.empty_state("Joueur introuvable."))
		return

	add_child(_header(w, p, n))
	var parts := split(420)
	var main: VBoxContainer = parts[0]
	var side: VBoxContainer = parts[1]

	main.add_child(_terms_card(w, p, o, n))
	main.add_child(_actions(n))
	main.add_child(UiKit.vspacer())

	side.add_child(_state_card(w, p, o, n))
	side.add_child(_log_card(n))


# ============================================================================

func _header(w: World, p: Player, n: Negotiation) -> Control:
	var module := w.module_for(p.game_id)
	var current := w.org(p.org_id)
	var subtitle := "%s · %d ans · %s" % [module.role_label(p.primary_role),
		p.age(w.today), "agent libre" if p.is_free_agent()
			else ("sous contrat à %s" % current.name if current != null
				else "sous contrat")]
	return page_header("Négociation — %s" % p.display_name(), subtitle, [
		UiKit.ghost("Fiche du joueur ▸", func():
			navigate("player", {"player_id": p.id})),
	])


## Le tableau des clauses : valeur proposée, réglages, avis de l'agent.
func _terms_card(w: World, p: Player, o: Organization,
		n: Negotiation) -> Control:
	var card := UiKit.card("Votre proposition", 6, 14)
	var terms := _terms(n)
	var closed := not n.is_live()

	# L'avis de l'agent porte sur la DERNIÈRE OFFRE TRANSMISE, jamais sur ce
	# qu'on est en train de régler. Sinon on trouverait le seuil exact en
	# cliquant, sans jamais dépenser un tour — et la patience ne coûterait
	# plus rien. Une clause modifiée depuis repasse donc à « à transmettre ».
	var scores := NegotiationSystem.clause_scores(w, p, o, n.offer, n.demand) \
		if n.rounds > 0 else {}

	card.body.add_child(_clause_row("Salaire annuel", T.SALARY,
		Money.fmt(int(terms[T.SALARY])), scores, terms, n, closed))
	card.body.add_child(_clause_row("Prime à la signature", T.BONUS,
		Money.fmt(int(terms[T.BONUS])), scores, terms, n, closed))
	card.body.add_child(_clause_row("Durée", T.MONTHS,
		"%d mois" % int(terms[T.MONTHS]), scores, terms, n, closed))
	card.body.add_child(_role_row(terms, scores, n, closed))
	card.body.add_child(_clause_row("Clause de rachat", T.BUYOUT,
		Money.fmt(int(terms[T.BUYOUT])), scores, terms, n, closed))
	card.body.add_child(_clause_row("Part des gains", T.PRIZE,
		"%.0f %%" % float(terms[T.PRIZE]), scores, terms, n, closed))

	card.body.add_child(UiKit.separator())
	var cost := UiKit.hbox(18)
	var upfront := int(terms[T.BONUS]) + Money.pct(int(terms[T.SALARY]), 8.0)
	cost.add_child(UiKit.stat_block("À verser à la signature",
		Money.fmt(upfront), UiKit.BAD if upfront > o.cash() else UiKit.TEXT,
		"prime + commission d'agent"))
	cost.add_child(UiKit.stat_block("Coût mensuel",
		Money.fmt(int(round(float(terms[T.SALARY]) / 12.0))), UiKit.TEXT,
		"sur %d mois" % int(terms[T.MONTHS])))
	cost.add_child(UiKit.stat_block("Trésorerie après signature",
		Money.fmt(o.cash() - upfront),
		UiKit.GOOD if o.cash() - upfront >= 0 else UiKit.BAD))
	cost.add_child(UiKit.spacer())
	card.body.add_child(cost)
	return card.panel


func _clause_row(label: String, key: String, value: String,
		scores: Dictionary, terms: Dictionary, n: Negotiation,
		closed: bool) -> Control:
	var row := UiKit.hbox(8)
	var l := UiKit.label(label, UiKit.FS_BODY_L, UiKit.TEXT_DIM)
	l.custom_minimum_size = Vector2(168, 0)
	row.add_child(l)

	var steps: Array = STEPS.get(key, [1, 10])
	row.add_child(_step_button("−−", key, -int(steps[1]), closed))
	row.add_child(_step_button("−", key, -int(steps[0]), closed))
	var v := UiKit.label(value, UiKit.FS_BODY_L, UiKit.TEXT, true)
	v.custom_minimum_size = Vector2(120, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(v)
	row.add_child(_step_button("+", key, int(steps[0]), closed))
	row.add_child(_step_button("++", key, int(steps[1]), closed))

	row.add_child(UiKit.spacer())
	row.add_child(_verdict_for(key, scores, terms, n))
	return row


## Pastille d'avis, ou rappel qu'il faut transmettre pour savoir.
func _verdict_for(key: String, scores: Dictionary, terms: Dictionary,
		n: Negotiation) -> Control:
	if not scores.has(key) or _differs(terms, n.offer, key):
		var pill := UiKit.pill("à transmettre", UiKit.TEXT_FAINT)
		pill.custom_minimum_size = Vector2(96, 0)
		return pill
	return _verdict_pill(float(scores[key]))


func _differs(a: Dictionary, b: Dictionary, key: String) -> bool:
	return absf(float(a.get(key, 0)) - float(b.get(key, 0))) > 0.001


func _role_row(terms: Dictionary, scores: Dictionary, n: Negotiation,
		closed: bool) -> Control:
	var row := UiKit.hbox(8)
	var l := UiKit.label("Statut promis", UiKit.FS_BODY_L, UiKit.TEXT_DIM)
	l.custom_minimum_size = Vector2(168, 0)
	row.add_child(l)
	var roles := [Contract.SquadRole.STARTER, Contract.SquadRole.SUBSTITUTE,
		Contract.SquadRole.ACADEMY]
	var current := int(terms[T.ROLE])
	for role_v in roles:
		var role: int = role_v
		var b := UiKit.button(NegotiationSystem.role_label(role), func():
			ui(_state_key())[T.ROLE] = role
			refresh())
		b.disabled = closed
		if role == current:
			b.add_theme_color_override("font_color", UiKit.ACCENT)
		row.add_child(b)
	row.add_child(UiKit.spacer())
	row.add_child(_verdict_for(T.ROLE, scores, terms, n))
	return row


func _step_button(text: String, key: String, delta: int,
		closed: bool) -> Button:
	var b := UiKit.ghost(text, func(): _bump(key, delta))
	b.custom_minimum_size = Vector2(38, 28)
	b.disabled = closed
	return b


func _verdict_pill(score: float) -> Control:
	var v := NegotiationSystem.clause_verdict(score)
	var level := int(v["level"])
	var color := UiKit.BAD
	if level >= 2:
		color = UiKit.GOOD
	elif level == 1:
		color = UiKit.GOOD.darkened(0.15)
	elif level == 0:
		color = UiKit.WARN
	elif level == -1:
		color = UiKit.ACCENT
	var pill := UiKit.pill(str(v["text"]), color, level >= 1)
	pill.custom_minimum_size = Vector2(96, 0)
	return pill


# ============================================================================

func _actions(n: Negotiation) -> Control:
	var row := UiKit.hbox(8)
	if not n.is_live():
		row.add_child(UiKit.label(_closing_text(n), UiKit.FS_BODY_L,
			UiKit.GOOD if n.status == Negotiation.Status.ACCEPTED
				else UiKit.TEXT_DIM))
		row.add_child(UiKit.spacer())
		row.add_child(UiKit.button("Retour au marché",
			func(): navigate("transfers")))
		return row

	var send := UiKit.primary("Transmettre l'offre  ▶", func():
		game().submit_offer(n.id, _terms(n))
		refresh())
	send.custom_minimum_size = Vector2(190, 34)
	row.add_child(send)

	if n.status == Negotiation.Status.COUNTERED:
		row.add_child(UiKit.button("Accepter sa contre-proposition", func():
			game().accept_counter(n.id)
			refresh()))
		row.add_child(UiKit.ghost("Reprendre ses termes", func():
			ui(_state_key()).clear()
			for key in n.demand:
				ui(_state_key())[key] = n.demand[key]
			refresh()))
	row.add_child(UiKit.spacer())
	row.add_child(UiKit.danger("Rompre les discussions", func():
		game().abandon_negotiation(n.id)
		refresh()))
	return row


func _closing_text(n: Negotiation) -> String:
	match n.status:
		Negotiation.Status.ACCEPTED:
			return "Accord trouvé — le joueur a signé."
		Negotiation.Status.REFUSED:
			return "L'agent a mis fin aux discussions."
		Negotiation.Status.EXPIRED:
			return "Discussion close."
	return ""


func _state_card(w: World, p: Player, o: Organization,
		n: Negotiation) -> Control:
	var card := UiKit.card("État de la discussion", 7, 12)
	card.body.add_child(UiKit.kv("Tours de table", str(n.rounds)))
	card.body.add_child(UiKit.caption("Patience de l'agent"))
	card.body.add_child(UiKit.meter(n.mood, 100.0, 240,
		UiKit.GOOD if n.mood > 55.0
			else (UiKit.WARN if n.mood > 25.0 else UiKit.BAD)))
	card.body.add_child(UiKit.wrap(
		"Chaque proposition entame sa patience, et une offre au rabais bien "
		+ "davantage. À zéro, il s'en va.", UiKit.FS_SMALL, UiKit.TEXT_FAINT))

	card.body.add_child(UiKit.separator())
	card.body.add_child(UiKit.caption("Ce qu'il regarde en premier"))
	for entry in _priorities(p):
		card.body.add_child(UiKit.bar_row(str(entry[0]), float(entry[1]),
			UiKit.INFO))
	card.body.add_child(UiKit.wrap(
		"Poids relatif de chaque clause pour lui. On sait QUOI soigner ; "
		+ "combien, il faudra le découvrir en proposant.",
		UiKit.FS_SMALL, UiKit.TEXT_FAINT))

	if not p.is_free_agent() and p.contract != null:
		card.body.add_child(UiKit.separator())
		card.body.add_child(UiKit.kv("Clause à payer",
			Money.fmt(p.contract.buyout)))
		card.body.add_child(UiKit.label(
			"Elle s'ajoute au coût de signature et va à sa structure actuelle.",
			UiKit.FS_SMALL, UiKit.TEXT_FAINT))
	return card.panel


## Les trois clauses qui pèsent le plus pour ce joueur-là, en pourcentage du
## poids total. C'est une lecture de son caractère, pas de ses exigences
## chiffrées : on sait QUOI soigner, pas COMBIEN.
func _priorities(p: Player) -> Array:
	var w := NegotiationSystem.weights(p)
	var total := 0.0
	for key in w:
		total += float(w[key])
	var rows: Array = []
	for key in w:
		rows.append([_clause_label(str(key)), float(w[key]) / total * 100.0])
	rows.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	return rows.slice(0, 4)


func _clause_label(key: String) -> String:
	match key:
		T.SALARY: return "Salaire"
		T.BONUS: return "Prime"
		T.MONTHS: return "Durée"
		T.ROLE: return "Statut"
		T.BUYOUT: return "Liberté de partir"
		T.PRIZE: return "Part des gains"
	return key


func _log_card(n: Negotiation) -> Control:
	var card := UiKit.card("Échanges", 5, 12)
	card.panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := UiKit.vbox(6)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var entries: Array = n.log.duplicate()
	entries.reverse()
	for entry_v in entries.slice(0, 14):
		var entry: Dictionary = entry_v
		var from_agent := str(entry.get("who", "")) == "agent"
		var line := UiKit.vbox(1)
		line.add_child(UiKit.label(
			"%s · %s" % [GameDate.format_day_month(int(entry.get("day", 0))),
				"l'agent" if from_agent else "vous"],
			UiKit.FS_MICRO, UiKit.TEXT_FAINT))
		line.add_child(UiKit.wrap(str(entry.get("text", "")), UiKit.FS_BODY,
			UiKit.TEXT if from_agent else UiKit.TEXT_DIM))
		box.add_child(line)
	card.body.add_child(box)
	return card.panel


# ============================================================================
# Clauses en cours d'édition
# ============================================================================

## L'état d'édition est propre à CETTE discussion : ouvrir une deuxième
## négociation ne doit pas hériter des réglages de la première.
func _state_key() -> String:
	return "nego.%s" % negotiation_id


## Clauses affichées : celles que le joueur est en train de régler, sinon la
## dernière offre transmise.
func _terms(n: Negotiation) -> Dictionary:
	var st := ui(_state_key())
	var out := n.offer.duplicate()
	for key in T.keys():
		if st.has(key):
			out[key] = st[key]
	return out


func _bump(key: String, delta: int) -> void:
	var n: Negotiation = game().negotiation(negotiation_id)
	if n == null:
		return
	var terms := _terms(n)
	var value := float(terms.get(key, 0)) + float(delta)
	match key:
		T.MONTHS:
			value = clampf(value, 6.0, 60.0)
		T.PRIZE:
			value = clampf(value, 0.0, 40.0)
		_:
			value = maxf(value, 0.0)
	ui(_state_key())[key] = value if key == T.PRIZE else int(value)
	refresh()
