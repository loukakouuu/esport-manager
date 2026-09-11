class_name StaffFactory
extends RefCounted

## Génération du staff. Même logique que les joueurs : une note cible, des
## attributs bruités autour, et un salaire calé sur le marché réel (un bon
## head coach VCT coûte 80-200 k$/an, un analyste 25-60 k$).

## Salaire annuel en $ d'un staff noté EXACTEMENT 10/20, par poste.
## Le barème est calé sur le marché réel : un coach de Challengers tourne
## autour de 20 k$, un coach VCT confirmé autour de 90 k$, et une pointure
## mondiale dépasse 200 k$.
const ROLE_SALARY_BASE := {
	Staff.Role.HEAD_COACH: 18_000,
	Staff.Role.ASSISTANT_COACH: 10_000,
	Staff.Role.ANALYST: 9_000,
	Staff.Role.TEAM_MANAGER: 9_000,
	Staff.Role.PSYCHOLOGIST: 11_000,
	Staff.Role.PERFORMANCE_COACH: 9_500,
	Staff.Role.SCOUT: 8_000,
	Staff.Role.CONTENT_MANAGER: 11_000,
	Staff.Role.GENERAL_MANAGER: 22_000,
}


static func salary_for(role: Staff.Role, overall: float) -> int:
	var base := float(ROLE_SALARY_BASE.get(role, 9_000))
	# Courbe exponentielle : +5 points de note multiplient le salaire par 5.
	var mult := exp((overall - 10.0) / 3.1)
	return Money.from_units(base * mult)


static func create(rng: Rng, ids: Ids, today: int, role: Staff.Role,
		opts: Dictionary = {}) -> Staff:
	var s := Staff.new()
	s.id = ids.next(Ids.STAFF)
	s.role = role
	s.game_id = str(opts.get("game_id", "valorant"))

	var region := str(opts.get("region", "EMEA"))
	var n := DataFile.load_json(PlayerFactory.NAMES_PATH, {"regions": {}}) as Dictionary
	var reg: Dictionary = (n.get("regions", {}) as Dictionary).get(region, {})
	s.region = region
	s.nationality = str(rng.pick(reg.get("countries", ["FR"])))
	s.first_name = str(rng.pick(reg.get("first", ["Alex"])))
	s.last_name = str(rng.pick(reg.get("last", ["Martin"])))
	# Beaucoup de coachs esport sont d'anciens joueurs : ils gardent leur pseudo.
	if rng.chance(0.55):
		s.nickname = PlayerFactory.make_gamertag(rng, ids)

	var age := int(opts.get("age", rng.gauss_i(31.0, 5.5, 22, 55)))
	s.birth_day = GameDate.add_years(today, -age)

	var target := float(opts.get("target_overall", rng.gauss(11.0, 2.8, 3.0, 19.5)))
	for k in Staff.ATTR_KEYS:
		s.attributes[k] = Attributes.clamp_value(rng.gauss_i(target - 1.5, 3.0, 1, 20))
	# On renforce les attributs clés du poste pour coller à la note visée.
	for _pass in 6:
		var cur := s.overall()
		if absf(cur - target) < 0.4:
			break
		var step := clampf((target - cur) * 0.8, -2.0, 2.0)
		for k in s.role_weights():
			s.attributes[k] = Attributes.clamp_value(int(round(float(s.attr(k)) + step)))

	s.reputation = int(clampf(pow(s.overall() / 20.0, 2.0) * 8000.0, 20.0, 9500.0))
	return s
