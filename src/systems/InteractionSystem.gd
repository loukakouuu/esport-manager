class_name InteractionSystem
extends RefCounted

## Conversations entre le manager et ses joueurs.
##
## Le principe repris de Football Manager : parler n'est jamais gratuit. Chaque
## échange a une CIBLE (un grief nommé, une performance réelle) et un TON. Le
## bon ton dépend de la personnalité du joueur, pas d'une réponse universelle —
## féliciter un ego surdimensionné le rend ingérable, secouer un joueur fragile
## le casse. Et la répétition use : le dixième discours ne vaut plus rien.
##
## Tout est déterministe (graine dérivée du joueur, du jour et du sujet) :
## recharger une sauvegarde ne permet pas de retenter sa chance.

enum Tone { CALM, FIRM, WARM }

const TONE_LABELS := {
	Tone.CALM: "Posé",
	Tone.FIRM: "Ferme",
	Tone.WARM: "Chaleureux",
}

## Délai minimum entre deux conversations avec le même joueur.
const COOLDOWN_DAYS := 7
## Au-delà de ce seuil de lassitude, les discours n'ont plus d'effet positif.
const FATIGUE_CAP := 4.0


static func tone_label(t: int) -> String:
	return TONE_LABELS.get(t, "?")


# ============================================================================
# Sujets disponibles
# ============================================================================

## Renvoie [{"key", "label", "hint", "risky": bool}] pour un joueur donné.
## La liste dépend de la situation réelle : on ne peut pas féliciter un joueur
## qui n'a pas joué, ni discuter d'un grief qu'il n'a pas.
static func available_topics(world: World, p: Player) -> Array:
	var out: Array = []
	var series := int(p.season_stats.get("series", 0))
	var rating := float(p.season_stats.get("rating", 0.0))

	if series >= 2 and rating >= 1.05:
		out.append({"key": "praise_form", "label": "Féliciter ses performances",
			"hint": "Note de %.2f sur %d séries." % [rating, series],
			"risky": false})
	if series >= 2 and rating <= 0.95:
		out.append({"key": "criticise_form", "label": "Recadrer ses performances",
			"hint": "Note de %.2f sur %d séries." % [rating, series],
			"risky": true})
	for c in p.concerns:
		out.append({"key": "concern:" + str(c),
			"label": "Répondre : %s" % DynamicsSystem.grievance_label(str(c)),
			"hint": _concern_hint(world, p, str(c)),
			"risky": true})
	if p.attr(Attributes.PROFESSIONALISM) <= 10 or p.attr(Attributes.EGO) >= 15:
		out.append({"key": "attitude", "label": "Mettre en garde sur l'attitude",
			"hint": "Comportement qui pèse sur le groupe.",
			"risky": true})
	if p.morale < 45.0:
		out.append({"key": "support", "label": "Le rassurer",
			"hint": "Moral en berne (%.0f)." % p.morale, "risky": false})
	if p.age(world.today) <= 20 and p.growth_headroom() > 0.15:
		out.append({"key": "future", "label": "Parler de son avenir",
			"hint": "Un jeune à qui l'on trace un chemin progresse plus vite.",
			"risky": false})
	return out


static func _concern_hint(world: World, p: Player, key: String) -> String:
	match key:
		DynamicsSystem.GRIEVANCE_PLAYING_TIME:
			return "Promesse : %s." % PlayingTime.label(p.promised_time)
		DynamicsSystem.GRIEVANCE_WAGE:
			return "Salaire actuel : %s / an." % Money.fmt_short(
				p.contract.salary_yearly if p.contract != null else 0)
		DynamicsSystem.GRIEVANCE_AMBITION:
			return "Il juge le projet sportif trop modeste."
		DynamicsSystem.GRIEVANCE_ROLE:
			return "Il est aligné à un poste qui ne lui va pas."
		DynamicsSystem.GRIEVANCE_CONTRACT:
			return "Contrat expirant : %s." % GameDate.format_duration_days(
				p.contract.days_remaining(world.today) if p.contract != null else 0)
		DynamicsSystem.GRIEVANCE_TEAMMATE:
			return "Une relation est devenue invivable."
		DynamicsSystem.GRIEVANCE_OVERWORK:
			return "Charge d'entraînement et de matchs trop lourde."
	return ""


static func can_talk(world: World, p: Player) -> bool:
	return world.today - p.last_talk_day >= COOLDOWN_DAYS


static func days_until_talk(world: World, p: Player) -> int:
	return maxi(0, COOLDOWN_DAYS - (world.today - p.last_talk_day))


# ============================================================================
# Conversation
# ============================================================================

## Applique une conversation. Renvoie
## {"ok": bool, "text": String, "morale": float, "reaction": String}.
static func talk(world: World, p: Player, topic: String, tone: int) -> Dictionary:
	if not can_talk(world, p):
		return {"ok": false, "reaction": "cooldown",
			"text": "%s vous a déjà entendu cette semaine." % p.display_name(),
			"morale": 0.0}

	var rng := world.rng.derive("talk:%s:%s:%d" % [p.id, topic, world.today])
	var fit := _tone_fit(p, topic, tone)
	# La lassitude ronge l'effet : au dixième discours, le joueur hoche la tête
	# et retourne à son écran.
	var wear := clampf(1.0 - p.talk_fatigue / FATIGUE_CAP, 0.0, 1.0)
	var roll := fit + rng.range_f(-0.22, 0.22)
	var success := roll > 0.12
	var strong := roll > 0.62

	var delta := 0.0
	var reaction := "neutral"
	if strong:
		delta = 9.0 * wear
		reaction = "great"
	elif success:
		delta = 4.5 * wear
		reaction = "good"
	elif roll > -0.35:
		delta = -1.0
		reaction = "flat"
	else:
		delta = -7.0
		reaction = "bad"

	var text := _apply_topic(world, p, topic, tone, reaction, delta)
	p.morale = clampf(p.morale + delta, 0.0, 100.0)
	p.happiness = clampf(p.happiness + delta * 0.8, 0.0, 100.0)
	p.last_talk_day = world.today
	p.talk_fatigue = clampf(p.talk_fatigue + 0.55, 0.0, FATIGUE_CAP + 1.0)
	return {"ok": true, "text": text, "morale": delta, "reaction": reaction}


## Adéquation du ton à l'homme et au sujet, -1 .. +1.
##
## Règles lisibles plutôt qu'une formule opaque, parce que le joueur doit
## pouvoir apprendre : « lui, il faut le prendre par la douceur ».
static func _tone_fit(p: Player, topic: String, tone: int) -> float:
	var ego := float(p.attr(Attributes.EGO))
	var pressure := float(p.attr(Attributes.PRESSURE))
	var pro := float(p.attr(Attributes.PROFESSIONALISM))
	var fit := 0.15

	match tone:
		Tone.FIRM:
			# La fermeté marche sur les professionnels et les mentalités
			# solides ; elle brise les fragiles et braque les ego.
			fit += (pro - 10.0) * 0.045
			fit += (pressure - 10.0) * 0.050
			fit -= (ego - 10.0) * 0.055
		Tone.WARM:
			fit += (ego - 10.0) * 0.030
			fit -= (pro - 12.0) * 0.025
			fit += (10.0 - pressure) * 0.030
		Tone.CALM:
			# Le ton neutre ne fait jamais de miracle mais ne casse rien.
			fit += 0.10
			fit -= absf(ego - 10.0) * 0.010

	# Certains sujets appellent un ton et un seul.
	if topic == "criticise_form" or topic == "attitude":
		if tone == Tone.WARM:
			fit -= 0.30
		if tone == Tone.FIRM:
			fit += 0.18
	if topic == "support" or topic == "future":
		if tone == Tone.FIRM:
			fit -= 0.35
		if tone == Tone.WARM:
			fit += 0.22
	if topic == "praise_form" and tone == Tone.FIRM:
		fit -= 0.25
	# Un moral déjà au sol rend toute conversation plus dure.
	fit -= clampf((45.0 - p.morale) / 100.0, 0.0, 0.35)
	return clampf(fit, -1.0, 1.0)


## Effets propres au sujet, au-delà du moral. Renvoie le texte de réponse.
static func _apply_topic(world: World, p: Player, topic: String, tone: int,
		reaction: String, delta: float) -> String:
	var good := reaction == "good" or reaction == "great"

	if topic.begins_with("concern:"):
		var key := topic.substr(8)
		if good:
			p.clear_concern(key)
			# On repousse la réapparition du grief : le joueur accorde du
			# crédit au manager pendant quelques semaines.
			if key == DynamicsSystem.GRIEVANCE_PLAYING_TIME:
				p.promise_day = world.today
			if key == DynamicsSystem.GRIEVANCE_TEAMMATE:
				_soften_conflicts(world, p)
			return _reply(p, reaction,
				"comprend votre position et met le sujet de côté",
				"n'est pas convaincu et campe sur sa position")
		if reaction == "bad":
			p.happiness = clampf(p.happiness - 4.0, 0.0, 100.0)
		return _reply(p, reaction,
			"prend note", "s'agace : le sujet n'est pas réglé")

	match topic:
		"praise_form":
			if good:
				p.form = clampf(p.form + 2.5, 0.0, 100.0)
			# Trop de compliments sur un ego fragile, et il se croit au-dessus
			# du groupe : la vraie sanction est là, pas dans le moral.
			if p.attr(Attributes.EGO) >= 16 and not good:
				p.set_attr(Attributes.EGO, mini(20, p.attr(Attributes.EGO) + 1))
			return _reply(p, reaction,
				"apprécie la reconnaissance", "trouve le compliment déplacé")
		"criticise_form":
			if good:
				p.sharpness = clampf(p.sharpness + 3.0, 0.0, 100.0)
				p.form = clampf(p.form + 1.5, 0.0, 100.0)
			return _reply(p, reaction,
				"encaisse et promet de rectifier", "le prend très mal")
		"attitude":
			if good:
				p.set_attr(Attributes.PROFESSIONALISM,
					mini(20, p.attr(Attributes.PROFESSIONALISM) + 1))
			elif reaction == "bad":
				p.set_attr(Attributes.EGO, mini(20, p.attr(Attributes.EGO) + 1))
			return _reply(p, reaction,
				"reconnaît ses torts", "conteste vos reproches")
		"support":
			if good:
				p.morale = clampf(p.morale + 3.0, 0.0, 100.0)
			return _reply(p, reaction,
				"repart avec le sourire", "reste dans sa bulle")
		"future":
			if good:
				# Un jeune à qui l'on montre un chemin travaille davantage.
				p.set_attr(Attributes.WORK_ETHIC,
					mini(20, p.attr(Attributes.WORK_ETHIC) + 1))
				p.happiness = clampf(p.happiness + 4.0, 0.0, 100.0)
			return _reply(p, reaction,
				"se projette dans la structure", "attendait davantage de garanties")
	return _reply(p, reaction, "vous écoute", "reste de marbre")


static func _reply(p: Player, reaction: String, positive: String,
		negative: String) -> String:
	match reaction:
		"great":
			return "%s %s. L'échange a visiblement porté." % [p.display_name(), positive]
		"good":
			return "%s %s." % [p.display_name(), positive]
		"flat":
			return "%s vous écoute sans réagir." % p.display_name()
	return "%s %s." % [p.display_name(), negative]


## Une médiation réussie n'efface pas le conflit, elle le rend vivable.
static func _soften_conflicts(world: World, p: Player) -> void:
	for other_id in p.relations.keys():
		if int(p.relations[other_id]) <= -55:
			p.relations[other_id] = -35
			var other := world.player(str(other_id))
			if other != null:
				other.relations[p.id] = -35


# ============================================================================
# Promesses
# ============================================================================

## Change le temps de jeu promis. Une PROMOTION remonte le moral tout de suite ;
## une rétrogradation le fait chuter d'autant plus que le joueur est ambitieux.
static func set_promise(world: World, p: Player, status: int) -> Dictionary:
	var before := p.promised_time
	p.promised_time = clampi(status, PlayingTime.STAR, PlayingTime.SURPLUS)
	p.promise_day = world.today
	var steps := before - p.promised_time     # positif = promotion
	var amb := float(p.attr(Attributes.AMBITION)) / 20.0
	var delta := 0.0
	if steps > 0:
		delta = float(steps) * (2.5 + amb * 3.5)
		p.clear_concern(DynamicsSystem.GRIEVANCE_PLAYING_TIME)
	elif steps < 0:
		delta = float(steps) * (3.0 + amb * 6.0)
	p.morale = clampf(p.morale + delta, 0.0, 100.0)
	p.happiness = clampf(p.happiness + delta, 0.0, 100.0)
	return {"ok": true, "morale": delta,
		"text": "%s est désormais considéré comme %s."
			% [p.display_name(), PlayingTime.label(p.promised_time).to_lower()]}


## La lassitude s'estompe : passe hebdomadaire appelée par ProgressionSystem.
static func weekly_decay(world: World) -> void:
	for pid in world.players:
		var p: Player = world.players[pid]
		p.talk_fatigue = maxf(0.0, p.talk_fatigue - 0.35)
