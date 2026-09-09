class_name SeasonBuilder
extends RefCounted

## Construit la saison compétitive d'une année à partir de
## data/world/season_valorant.json.
##
## Aucune compétition n'est codée en dur : ajouter une ligue nationale, changer
## un format de playoffs ou déplacer les Masters se fait dans le JSON. C'est ce
## qui rendra l'ajout d'un second jeu (CS2, LoL) indolore : un fichier de plus.

const SEASON_PATH := "res://data/world/season_valorant.json"

const FORMAT_MAP := {
	"round_robin": Stage.Format.ROUND_ROBIN,
	"groups": Stage.Format.GROUPS,
	"single_elim": Stage.Format.SINGLE_ELIM,
	"double_elim": Stage.Format.DOUBLE_ELIM,
	"swiss": Stage.Format.SWISS,
}

const KIND_MAP := {
	"league": Competition.Kind.LEAGUE,
	"tournament": Competition.Kind.TOURNAMENT,
	"international": Competition.Kind.INTERNATIONAL,
	"qualifier": Competition.Kind.QUALIFIER,
	"ascension": Competition.Kind.ASCENSION,
}


static func data() -> Dictionary:
	return DataFile.load_json(SEASON_PATH, {}) as Dictionary


## Crée toutes les compétitions de l'année `year` et y inscrit les rosters
## selon leur `league_key`.
static func build_season(world: World, year: int) -> void:
	var d := data()
	var default_dist: Array = d.get("default_prize_distribution", [])

	for entry_v in d.get("leagues", []):
		var entry: Dictionary = entry_v
		var comp := _make_competition(world, entry, year, default_dist)
		comp.kind = Competition.Kind.LEAGUE
		_attach_stages(world, comp, _stages_for(d, entry), year)
		# Inscription des rosters de cette ligue.
		for rid in world.rosters:
			var r: Roster = world.rosters[rid]
			if r.league_key == comp.key and not r.is_academy:
				comp.participants.append(rid)
				r.competition_ids.append(comp.id)
		if not comp.stages.is_empty():
			comp.stages[0].participants = comp.participants.duplicate()
		world.competitions[comp.id] = comp

	for entry_v in d.get("internationals", []):
		var entry: Dictionary = entry_v
		var comp := _make_competition(world, entry, year, default_dist)
		comp.kind = KIND_MAP.get(str(entry.get("kind", "international")),
			Competition.Kind.INTERNATIONAL)
		comp.qualification_rules = (entry.get("seed_from", []) as Array).duplicate(true)
		if entry.has("promotes_to"):
			comp.qualification_rules.append({"promotes_to": entry["promotes_to"]})
		_attach_stages(world, comp, entry.get("stages", []), year)
		world.competitions[comp.id] = comp


static func _stages_for(d: Dictionary, entry: Dictionary) -> Array:
	if entry.has("stages"):
		return entry["stages"]
	var preset := str(entry.get("stages_preset", ""))
	return (d.get("stage_presets", {}) as Dictionary).get(preset, [])


static func _make_competition(world: World, entry: Dictionary, year: int,
		default_dist: Array) -> Competition:
	var c := Competition.new()
	c.id = world.ids.next(Ids.COMP)
	c.key = str(entry["key"])
	c.name = "%s %d" % [str(entry["name"]), year]
	c.short_name = str(entry.get("short_name", entry["name"]))
	c.game_id = "valorant"
	c.region = str(entry.get("region", "EMEA"))
	c.country = str(entry.get("country", ""))
	c.tier = int(entry.get("tier", 1))
	c.season_year = year
	c.prestige = int(entry.get("prestige", 4000))
	c.is_lan = bool(entry.get("lan", false))
	c.travel_cost_per_team = Money.from_units(
		float(entry.get("travel_cost_per_team", 0)))
	c.prize_pool = Money.from_units(float(entry.get("prize_pool", 0)))
	c.prize_distribution = (entry.get("prize_distribution", default_dist) as Array).duplicate()
	c.stipend_yearly = Money.from_units(float(entry.get("stipend_yearly", 0)))
	c.rev_share_yearly = Money.from_units(float(entry.get("rev_share_yearly", 0)))
	c.entry_fee = Money.from_units(float(entry.get("entry_fee", 0)))
	return c


static func _attach_stages(world: World, comp: Competition, stages: Array,
		year: int) -> void:
	for i in stages.size():
		var sd: Dictionary = stages[i]
		var st := Stage.new()
		st.id = "%s_s%d" % [comp.id, i]
		st.competition_id = comp.id
		st.name = str(sd.get("name", "Phase %d" % (i + 1)))
		st.format = FORMAT_MAP.get(str(sd.get("format", "round_robin")),
			Stage.Format.ROUND_ROBIN)
		st.start_day = _parse_md(str(sd.get("start", "01-01")), year)
		st.end_day = _parse_md(str(sd.get("end", "12-31")), year)
		st.best_of = int(sd.get("best_of", 3))
		st.final_best_of = int(sd.get("final_best_of", sd.get("best_of", 3)))
		st.qualifiers = int(sd.get("qualifiers", 8))
		for key in ["groups", "double_round", "wins_to_qualify", "losses_out",
				"max_rounds"]:
			if sd.has(key):
				st.config[key] = sd[key]
		comp.stages.append(st)


static func _parse_md(md: String, year: int) -> int:
	var parts := md.split("-")
	if parts.size() != 2:
		return GameDate.from_ymd(year, 1, 1)
	return GameDate.from_ymd(year, int(parts[0]), int(parts[1]))


## Remplit les participants d'un tournoi international à partir des phases
## qualificatives déjà terminées. Appelée par CompetitionEngine juste avant de
## générer les rencontres.
static func resolve_seeds(world: World, comp: Competition) -> bool:
	if not comp.participants.is_empty():
		return true
	if comp.qualification_rules.is_empty():
		return false
	var seeds: Array[String] = []
	for rule_v in comp.qualification_rules:
		var rule: Dictionary = rule_v
		if not rule.has("comp_key"):
			continue
		var src := _find_competition(world, str(rule["comp_key"]), comp.season_year)
		if src == null:
			continue
		var stage_index := int(rule.get("stage", 0))
		if stage_index >= src.stages.size():
			continue
		var st: Stage = src.stages[stage_index]
		if st.status != Stage.Status.FINISHED:
			return false   # qualification pas encore jouée : on attend
		for i in mini(int(rule.get("places", 1)), st.ranking.size()):
			if not seeds.has(st.ranking[i]):
				seeds.append(st.ranking[i])
	if seeds.is_empty():
		return false
	comp.participants = seeds
	if not comp.stages.is_empty():
		comp.stages[0].participants = seeds.duplicate()
	for rid in seeds:
		var r := world.roster(rid)
		if r != null and not r.competition_ids.has(comp.id):
			r.competition_ids.append(comp.id)
		_charge_travel(world, comp, r)
	return true


## Participer à un événement international coûte cher : vols, hôtel, staff sur
## place. Une équipe de Challengers peut y laisser un mois de trésorerie.
static func _charge_travel(world: World, comp: Competition, r: Roster) -> void:
	if r == null or comp.travel_cost_per_team <= 0:
		return
	var o := world.org(r.org_id)
	if o == null:
		return
	o.ledger.debit(world.today, comp.travel_cost_per_team,
		Transaction.Category.TRAVEL, "Déplacement — %s" % comp.name, comp.name)


static func _find_competition(world: World, key: String, year: int) -> Competition:
	for cid in world.competitions:
		var c: Competition = world.competitions[cid]
		if c.key == key and c.season_year == year:
			return c
	return null


# ============================================================================
# Changement de saison
# ============================================================================

## Applique la promotion issue de l'Ascension puis construit la saison suivante.
##
## Simplification assumée par rapport au réel : le vainqueur de l'Ascension
## remplace la dernière équipe du VCT. Le vrai système attribue un slot de deux
## ans sans relégation directe ; la règle est isolée ici pour être remplacée
## sans toucher au reste du moteur.
static func roll_over(world: World, next_year: int) -> void:
	_apply_promotions(world)
	_archive_finished(world)
	world.season_year = next_year
	build_season(world, next_year)


static func _apply_promotions(world: World) -> void:
	for cid in world.competitions:
		var comp: Competition = world.competitions[cid]
		if comp.kind != Competition.Kind.ASCENSION:
			continue
		if comp.status != Competition.Status.FINISHED or comp.final_ranking.is_empty():
			continue
		var target_key := ""
		for rule_v in comp.qualification_rules:
			var rule: Dictionary = rule_v
			if rule.has("promotes_to"):
				target_key = str(rule["promotes_to"])
		if target_key == "":
			continue
		var promoted := world.roster(comp.final_ranking[0])
		var league := _find_competition(world, target_key, comp.season_year)
		if promoted == null or league == null or league.final_ranking.is_empty():
			continue
		var relegated := world.roster(league.final_ranking[league.final_ranking.size() - 1])
		if relegated == null or relegated.id == promoted.id:
			continue
		var old_key := promoted.league_key
		promoted.league_key = target_key
		relegated.league_key = old_key
		var promoted_org := world.org(promoted.org_id)
		var relegated_org := world.org(relegated.org_id)
		if promoted_org != null:
			promoted_org.reputation = mini(promoted_org.reputation + 900, 10000)
			world.add_news(world.today, "%s accède au %s"
				% [promoted_org.name, league.short_name],
				"Vainqueur de %s, %s rejoint l'élite la saison prochaine."
					% [comp.short_name, promoted_org.name], "result")
		if relegated_org != null:
			relegated_org.reputation = maxi(relegated_org.reputation - 700, 100)


## Vide le calendrier des saisons closes pour garder la sauvegarde compacte.
static func _archive_finished(world: World) -> void:
	var keep_fixtures := {}
	for cid in world.competitions.keys():
		var c: Competition = world.competitions[cid]
		if c.season_year >= world.season_year:
			for st in c.stages:
				for fid in st.fixture_ids:
					keep_fixtures[fid] = true
	for fid in world.fixtures.keys():
		if not keep_fixtures.has(fid):
			world.fixtures.erase(fid)
	for cid in world.competitions.keys():
		var c: Competition = world.competitions[cid]
		if c.season_year < world.season_year:
			world.competitions.erase(cid)
	for rid in world.rosters:
		var r: Roster = world.rosters[rid]
		r.competition_ids.clear()
		r.season_record.clear()
