class_name SquadTests
extends RefCounted

## Tests des systèmes de gestion d'effectif ajoutés pour la profondeur « FM » :
## entraînement, dynamiques de vestiaire, conversations, aisance aux postes,
## relève et historique de développement.
##
## Ces systèmes se testent sur un VRAI monde généré, parce que leur intérêt est
## justement l'interaction : un grief de temps de jeu n'a de sens que s'il
## existe un roster, un calendrier et des statistiques.

static func run() -> Array[TestCase]:
	var world := _world()
	return [
		_training_plan(),
		_role_familiarity(world),
		_dynamics(world),
		_interactions(world),
		_development(world),
		_youth(),
	]


## Monde partagé par les suites : la génération coûte cher, on la fait une fois.
static var _cached: World = null


static func _world() -> World:
	if _cached != null:
		return _cached
	_cached = WorldGenerator.generate(777, GameDate.from_ymd(2026, 1, 5))
	var candidates := WorldGenerator.selectable_orgs(_cached, "chal_emea")
	WorldGenerator.assign_player_org(_cached, str(candidates[0]["org_id"]))
	# Deux mois de jeu : assez pour des matchs, des griefs et un instantané.
	for _i in 70:
		GameSim.advance_day(_cached)
	return _cached


static func _my_roster(w: World) -> Roster:
	return w.main_roster(w.player_org_id, w.player_game_id)


# ============================================================================

static func _training_plan() -> TestCase:
	var t := TestCase.new("Entraînement — programme et charge")
	var r := Roster.new()

	# Un roster sans programme retombe sur le programme par défaut.
	var plan := TrainingSystem.plan_of(r)
	t.eq(TrainingSystem.plan_total(plan), TrainingSystem.UNITS_PER_WEEK,
		"le programme par défaut occupe toute la semaine")

	# La charge doit ordonner correctement les trois programmes types.
	var heavy := {"scrim": 6, "aim": 3, "theory": 1, "physical": 0, "rest": 0}
	var light := {"scrim": 2, "aim": 0, "theory": 2, "physical": 2, "rest": 4}
	var heavy_load := TrainingSystem.plan_load(heavy)
	var light_load := TrainingSystem.plan_load(light)
	t.check(heavy_load > TrainingSystem.plan_load(plan),
		"tout scrims est plus lourd que le programme par défaut")
	t.check(TrainingSystem.plan_load(plan) > light_load,
		"le programme par défaut est plus lourd qu'une semaine de décharge")
	t.between(heavy_load, 1.2, 1.75, "la charge maximale reste dans l'échelle")
	t.between(light_load, 0.25, 0.75, "la charge minimale reste dans l'échelle")

	# Ce n'est pas le repos mais le travail TECHNIQUE qui fait progresser.
	var p := Player.new()
	r.training = heavy
	var g_heavy := TrainingSystem.growth_multiplier(r, p)
	r.training = light
	var g_light := TrainingSystem.growth_multiplier(r, p)
	t.check(g_heavy > g_light,
		"un programme technique fait progresser plus vite qu'une décharge")
	t.between(g_light, 0.25, 1.0, "une semaine de décharge progresse peu")

	# Le travail individuel doit peser sur ce qui progresse.
	r.training = TrainingSystem.DEFAULT_PLAN.duplicate()
	var without := TrainingSystem.focus_weights(r, p)
	p.training_focus = ValorantModule.CLUTCH
	var with_focus := TrainingSystem.focus_weights(r, p)
	t.check(float(with_focus.get(ValorantModule.CLUTCH, 0.0))
		> float(without.get(ValorantModule.CLUTCH, 0.0)),
		"choisir un domaine augmente son poids dans la progression")

	# Un joueur ménagé progresse moins vite qu'un joueur chargé.
	p.training_intensity = 0.7
	var slow := TrainingSystem.growth_multiplier(r, p)
	p.training_intensity = 1.35
	t.check(TrainingSystem.growth_multiplier(r, p) > slow,
		"l'intensité individuelle module la progression")
	return t


# ============================================================================

static func _role_familiarity(w: World) -> TestCase:
	var t := TestCase.new("Postes — aisance et aptitude")
	var r := _my_roster(w)
	var module := w.module_for(r.game_id)
	var p := w.player(r.player_ids[0])

	t.eq(RoleFamiliarity.level_of(p, p.primary_role),
		RoleFamiliarity.Level.NATURAL,
		"un joueur est naturel à son poste principal")

	var ranking := RoleFamiliarity.ranking(p, module)
	t.eq(ranking.size(), module.roles().size(),
		"tous les postes sont évalués")
	for i in range(1, ranking.size()):
		t.check(int(ranking[i - 1]["ca"]) >= int(ranking[i]["ca"]),
			"le classement des postes est décroissant")
	for entry_v in ranking:
		var e: Dictionary = entry_v
		t.between(float(e["aptitude"]), 0.0, 1.0,
			"l'aptitude reste normalisée entre 0 et 1")

	# Le niveau au poste naturel ne peut pas être battu par un poste inconnu à
	# maîtrise nulle : sinon la pénalité de reconversion ne sert à rien.
	var stranger := ""
	for role in module.roles():
		if RoleFamiliarity.level_of(p, role) == RoleFamiliarity.Level.AWKWARD:
			stranger = role
	if stranger != "":
		t.check(AbilityCalc.ca_as_role(p, module, p.primary_role)
			> AbilityCalc.ca_as_role(p, module, stranger),
			"jouer un poste inadapté coûte du niveau")
	return t


# ============================================================================

static func _dynamics(w: World) -> TestCase:
	var t := TestCase.new("Vestiaire — hiérarchie, affinités, griefs")
	var r := _my_roster(w)
	var squad := w.players_of(r.id)
	t.check(squad.size() >= 5, "l'effectif de test est complet")

	# Les affinités sont SYMÉTRIQUES : A pense de B ce que B pense de A.
	var asymmetric := 0
	for i in squad.size():
		for j in range(i + 1, squad.size()):
			var a: Player = squad[i]
			var b: Player = squad[j]
			if a.relation_with(b.id) != b.relation_with(a.id):
				asymmetric += 1
			t.between(float(a.relation_with(b.id)), -100.0, 100.0,
				"une affinité reste dans l'échelle -100..100")
	t.eq(asymmetric, 0, "les affinités sont symétriques")

	for p_v in squad:
		var p: Player = p_v
		t.between(p.influence, 0.0, 100.0, "l'influence reste dans 0..100")

	var atm := DynamicsSystem.atmosphere(w, r)
	t.between(atm, 0.0, 100.0, "l'ambiance reste dans 0..100")
	t.check(DynamicsSystem.atmosphere_label(atm) != "",
		"l'ambiance a toujours un libellé")
	t.between(DynamicsSystem.chemistry_modifier(w, r), 0.25, 1.6,
		"le multiplicateur de cohésion reste borné")

	t.eq(DynamicsSystem.hierarchy(w, r).size(), squad.size(),
		"la hiérarchie couvre tout l'effectif")

	# Un joueur qui ne joue jamais avec une promesse de titulaire DOIT finir
	# par se plaindre : c'est le cœur du système de promesses.
	var bench: Player = null
	for p_v in squad:
		var p: Player = p_v
		if not r.starters.has(p.id):
			bench = p
	if bench != null:
		bench.promised_time = PlayingTime.KEY
		bench.promise_day = w.today - 90
		DynamicsSystem.weekly_tick(w)
		t.check(bench.has_concern(DynamicsSystem.GRIEVANCE_PLAYING_TIME),
			"un remplaçant à qui l'on a promis un rôle clé se plaint")
		t.check(DynamicsSystem.grievance_pressure(bench) > 0.0,
			"un grief exerce une pression mesurable")
	return t


# ============================================================================

static func _interactions(w: World) -> TestCase:
	var t := TestCase.new("Conversations — effets et déterminisme")
	var r := _my_roster(w)
	var p := w.player(r.starters[0])
	p.last_talk_day = -999
	p.talk_fatigue = 0.0

	t.check(InteractionSystem.can_talk(w, p),
		"on peut parler à un joueur qu'on n'a pas vu depuis longtemps")
	var topics := InteractionSystem.available_topics(w, p)
	for topic_v in topics:
		var topic: Dictionary = topic_v
		t.check(str(topic.get("key", "")) != "", "chaque sujet a une clé")
		t.check(str(topic.get("label", "")) != "", "chaque sujet a un libellé")

	# Déterminisme : même joueur, même jour, même sujet, même issue.
	var before_morale := p.morale
	var a := InteractionSystem.talk(w, p, "support", InteractionSystem.Tone.WARM)
	p.last_talk_day = -999
	p.morale = before_morale
	var b := InteractionSystem.talk(w, p, "support", InteractionSystem.Tone.WARM)
	t.eq(str(a["reaction"]), str(b["reaction"]),
		"une conversation rejouée donne la même réaction")
	t.eq(str(a["text"]), str(b["text"]), "et le même texte")

	# Le délai de carence bloque une deuxième conversation immédiate.
	var blocked := InteractionSystem.talk(w, p, "support",
		InteractionSystem.Tone.WARM)
	t.check(not bool(blocked["ok"]),
		"on ne peut pas enchaîner deux conversations dans la semaine")

	# Une promotion de statut remonte le moral, une rétrogradation le fait chuter.
	p.promised_time = PlayingTime.BACKUP
	var up := InteractionSystem.set_promise(w, p, PlayingTime.KEY)
	t.check(float(up["morale"]) > 0.0, "une promotion fait plaisir")
	var down := InteractionSystem.set_promise(w, p, PlayingTime.SURPLUS)
	t.check(float(down["morale"]) < 0.0, "une mise à l'écart fait mal")
	t.eq(p.promised_time, PlayingTime.SURPLUS, "le statut est bien enregistré")
	return t


# ============================================================================

static func _development(w: World) -> TestCase:
	var t := TestCase.new("Développement — historique et carrière")
	var r := _my_roster(w)
	var p := w.player(r.player_ids[0])

	t.check(not p.development.is_empty(),
		"un instantané mensuel a été enregistré")
	for snap_v in p.development:
		var snap: Dictionary = snap_v
		t.check(snap.has("day") and snap.has("ca"),
			"chaque instantané porte une date et une capacité")
	# Les joueurs de la structure du joueur gardent le détail par attribut,
	# les autres non : c'est ce qui garde la sauvegarde légère.
	t.check((p.last_snapshot() as Dictionary).has("attrs"),
		"les joueurs de l'effectif conservent le détail par attribut")

	var other: Player = null
	for pid in w.players:
		var q: Player = w.players[pid]
		if q.org_id != "" and q.org_id != w.player_org_id \
				and not q.development.is_empty():
			other = q
			break
	if other != null:
		t.check(not (other.last_snapshot() as Dictionary).has("attrs"),
			"les joueurs des autres structures n'en conservent pas")

	# La sauvegarde doit relire à l'identique tous les nouveaux champs.
	p.training_focus = ValorantModule.AIM
	p.training_intensity = 1.35
	p.promised_time = PlayingTime.STAR
	p.relations["x"] = -42
	var round_trip := Player.from_dict(p.to_dict())
	t.eq(round_trip.training_focus, p.training_focus,
		"le domaine d'entraînement survit à la sauvegarde")
	t.near(round_trip.training_intensity, p.training_intensity, 0.001,
		"l'intensité survit à la sauvegarde")
	t.eq(round_trip.promised_time, p.promised_time,
		"le statut promis survit à la sauvegarde")
	t.eq(round_trip.relation_with("x"), -42,
		"les affinités survivent à la sauvegarde")
	t.eq(round_trip.development.size(), p.development.size(),
		"l'historique survit à la sauvegarde")
	return t


# ============================================================================

static func _youth() -> TestCase:
	var t := TestCase.new("Relève — génération annuelle")
	var w := WorldGenerator.generate(31415, GameDate.from_ymd(2026, 1, 5))
	var before := 0
	for pid in w.players:
		if not (w.players[pid] as Player).retired:
			before += 1

	var report := YouthSystem.yearly_intake(w)
	var created := int(report["academy"]) + int(report["free"])
	t.check(created >= YouthSystem.MIN_INTAKE,
		"une génération complète est produite")

	var after := 0
	var teens := 0
	var over_pa := 0
	for pid in w.players:
		var p: Player = w.players[pid]
		if p.retired:
			continue
		after += 1
		var age := p.age(w.today)
		if age <= 18:
			teens += 1
		if p.potential_ability < p.current_ability:
			over_pa += 1
	t.eq(after - before, created, "tous les jeunes générés rejoignent le monde")
	t.check(teens >= created, "la génération est bien composée de mineurs")
	t.eq(over_pa, 0, "aucun joueur n'a un potentiel inférieur à son niveau")

	# Le vivier doit rester dimensionné pour remplir les rosters.
	var slots := 0
	for oid in w.orgs:
		var o: Organization = w.orgs[oid]
		if not o.rosters_for("valorant").is_empty():
			slots += 5
	t.check(after > slots,
		"le vivier reste plus grand que le nombre de places de titulaire")
	return t
