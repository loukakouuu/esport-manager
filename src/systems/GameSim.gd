class_name GameSim
extends RefCounted

## Horloge du jeu : fait avancer le monde d'une journée.
##
## Un seul point d'entrée, advance_day(), qui orchestre les systèmes dans un
## ordre fixe. Cet ordre est important et volontairement figé :
##   1. entraînement et récupération (ce qui s'est passé pendant la semaine)
##   2. matchs du jour
##   3. conséquences des matchs (forme, blessures, réputation)
##   4. progression des compétitions
##   5. échéances contractuelles et marché
##   6. clôture financière mensuelle
##   7. bascule de saison
##
## Toute la simulation est déterministe : à graine et actions égales, deux
## parties produisent exactement la même saison.

## Jour de bascule de saison (après Champions et l'Ascension).
const SEASON_ROLLOVER_MONTH := 11
const SEASON_ROLLOVER_DAY := 15


static func advance_day(world: World) -> Dictionary:
	world.today += 1
	var report := {
		"day": world.today, "results": [] as Array[MatchResult],
		"news": 0, "monthly_close": false, "season_rollover": false,
	}
	var news_before := world.inbox.size()

	if GameDate.is_monday(world.today):
		# L'ordre compte : les griefs et l'ambiance sont recalculés d'abord,
		# parce que l'entraînement (cohésion) et le moral s'appuient dessus.
		DynamicsSystem.weekly_tick(world)
		# Avant l'entraînement : un encadrant recruté ce lundi doit compter
		# dès cette semaine.
		StaffSystem.weekly_tick(world)
		TrainingSystem.weekly_tick(world)
		ProgressionSystem.weekly_tick(world)
		InteractionSystem.weekly_decay(world)
		NegotiationSystem.weekly_tick(world)
		TransferSystem.weekly_tick(world)

	var results := CompetitionEngine.play_day(world)
	for res in results:
		var f := world.fixture(res.fixture_id)
		if f != null:
			ProgressionSystem.after_match(world, f, res)
	report["results"] = results

	# Les compétitions qui n'ont pas joué aujourd'hui doivent quand même
	# pouvoir démarrer une phase à la date prévue.
	for cid in world.competitions:
		CompetitionEngine.advance(world, world.competitions[cid])

	ContractSystem.daily_tick(world)
	StaffSystem.daily_tick(world)

	if GameDate.is_first_day_of_month(world.today):
		_monthly(world)
		report["monthly_close"] = true

	if GameDate.month_of(world.today) == SEASON_ROLLOVER_MONTH \
			and GameDate.day_of_month(world.today) == SEASON_ROLLOVER_DAY:
		_season_rollover(world)
		report["season_rollover"] = true

	report["news"] = world.inbox.size() - news_before
	return report


static func _monthly(world: World) -> void:
	ProgressionSystem.monthly_snapshot(world)
	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		FinanceSystem.monthly_close(world, o)
		SponsorSystem.monthly_review(world, o)
		if not o.is_player_controlled:
			AiDirector.monthly_decisions(world, o)
	# Compaction du grand livre au-delà de deux ans : la sauvegarde reste petite.
	if GameDate.month_of(world.today) == 1:
		var cutoff := GameDate.add_years(world.today, -2)
		for oid in world.orgs:
			(world.orgs[oid] as Organization).ledger.compact(cutoff)


static func _season_rollover(world: World) -> void:
	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		BoardSystem.evaluate_season(world, o)
	ProgressionSystem.yearly_retirements(world)
	# On archive la saison AVANT de remettre les compteurs à zéro : c'est
	# l'historique de carrière affiché sur la fiche du joueur.
	ProgressionSystem.archive_season(world)
	# La relève arrive APRÈS les retraites : le contingent est calculé sur le
	# vivier réel, une fois les départs actés.
	var intake := YouthSystem.yearly_intake(world)
	for pid in world.players:
		(world.players[pid] as Player).season_stats.clear()

	var next_year := world.season_year + 1
	SeasonBuilder.roll_over(world, next_year)

	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		o.objectives = BoardSystem.season_objectives(world, o)
	world.add_news(world.today, "Saison %d" % next_year,
		"La nouvelle saison est programmée. Les calendriers sont disponibles.\n"
		+ "Nouvelle génération : %d jeunes promus par les académies et %d "
			% [int(intake.get("academy", 0)), int(intake.get("free", 0))]
		+ "espoirs sans club sur le marché.",
		"season")


# ============================================================================
# Avance groupée
# ============================================================================

## Avance de N jours en s'arrêtant net si un événement réclame l'attention du
## joueur (match de son équipe, message important). C'est le « continuer »
## de Football Manager.
static func advance_days(world: World, count: int,
		stop_on_player_match: bool = true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for _i in count:
		if world.my_org() != null and world.my_org().bankrupt:
			break
		var rep := advance_day(world)
		out.append(rep)
		if stop_on_player_match and _has_player_result(world, rep):
			break
	return out


## Avance jusqu'à la veille du prochain match de l'équipe du joueur.
static func advance_to_next_player_match(world: World, max_days: int = 400) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var r := world.main_roster(world.player_org_id, world.player_game_id)
	if r == null:
		return out
	for _i in max_days:
		var upcoming := world.upcoming_for_roster(r.id, 1)
		if not upcoming.is_empty() and upcoming[0].day == world.today + 1:
			break
		out.append(advance_day(world))
		if not out.is_empty() and _has_player_result(world, out[out.size() - 1]):
			break
	return out


static func _has_player_result(world: World, report: Dictionary) -> bool:
	if world.player_org_id == "":
		return false
	for res_v in report.get("results", []):
		var res: MatchResult = res_v
		for rid in [res.home_id, res.away_id]:
			var r := world.roster(rid)
			if r != null and r.org_id == world.player_org_id:
				return true
	return false
