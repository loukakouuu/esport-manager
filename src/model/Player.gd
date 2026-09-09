class_name Player
extends RefCounted

## Un joueur professionnel.
##
## Le modèle sépare volontairement trois couches :
##  1. VÉRITÉ  : attributs réels, CA/PA. Le joueur (l'utilisateur) ne les voit
##     jamais directement — seulement l'estimation produite par son scouting.
##  2. ÉTAT    : forme, moral, fatigue, burnout, blessure. Volatil, évolue
##     chaque jour.
##  3. CARRIÈRE: contrat, stats, historique, réputation.
##
## `game_data` porte tout ce qui est propre à la discipline (pool d'agents
## Valorant, préférences de map...). Le coeur du moteur n'y touche jamais :
## seul le GameModule correspondant le lit et l'écrit.

var id: String = ""
var game_id: String = "valorant"

# --- Identité ---------------------------------------------------------------
var first_name: String = ""
var last_name: String = ""
var gamertag: String = ""
var nationality: String = "FR"     # code ISO
var region: String = "EMEA"        # zone compétitive (contraintes de roster)
var birth_day: int = 0

# --- Vérité ----------------------------------------------------------------
var attributes: Dictionary = {}    # String -> int 1..20 (communs + spécifiques)
var current_ability: int = 80      # CA 1..200, dérivé des attributs pondérés
var potential_ability: int = 120   # PA 1..200, plafond de développement
var roles: Dictionary = {}         # role_id -> maîtrise 1..20
var primary_role: String = ""
var is_igl: bool = false

# --- État -------------------------------------------------------------------
var form: float = 50.0             # 0..100, moyenne glissante des perfs
var morale: float = 60.0           # 0..100
var fatigue: float = 0.0           # 0..100, se vide au repos
var burnout: float = 0.0           # 0..100, lent à monter ET à descendre
var sharpness: float = 60.0        # 0..100, rythme compétitif
var injured_until: int = -1        # index de jour, -1 = valide
var injury_label: String = ""

# --- Carrière ---------------------------------------------------------------
var org_id: String = ""            # "" = agent libre
var contract: Contract = null
var reputation: int = 300          # 0..10000 (notoriété mondiale)
var fan_appeal: int = 20           # 0..100, capacité à générer du merch/stream
var market_value: int = 0          # cents, recalculé périodiquement
var traits: Array[String] = []
var career: Array = []             # lignes de bilan par saison
var season_stats: Dictionary = {}  # stats agrégées de la saison en cours
var game_data: Dictionary = {}     # payload spécifique à la discipline

# --- Relation au club -------------------------------------------------------
var happiness: float = 60.0        # 0..100, satisfaction contractuelle/sportive
var transfer_listed: bool = false
var wants_out: bool = false
var retired: bool = false
var retire_day: int = -1


func full_name() -> String:
	return "%s %s" % [first_name, last_name]


## Nom d'affichage esport : le pseudo prime, comme dans la vraie vie.
func display_name() -> String:
	return gamertag


func long_name() -> String:
	return "%s \"%s\" %s" % [first_name, gamertag, last_name]


func age(today: int) -> int:
	return GameDate.age_at(birth_day, today)


func attr(key: String) -> int:
	return int(attributes.get(key, 10))


func set_attr(key: String, v: int) -> void:
	attributes[key] = Attributes.clamp_value(v)


func role_rating(role_id: String) -> int:
	return int(roles.get(role_id, 1))


func is_free_agent() -> bool:
	return org_id == ""


func is_injured(today: int) -> bool:
	return injured_until >= today


func is_available(today: int) -> bool:
	return not retired and not is_injured(today)


func has_trait(t: String) -> bool:
	return traits.has(t)


## Condition globale utilisée par la simulation : combine forme, fatigue,
## moral et burnout en un multiplicateur autour de 1.0 (0.82 .. 1.12).
func condition_multiplier() -> float:
	var f := (form - 50.0) / 50.0                # -1 .. +1
	var m := (morale - 50.0) / 50.0
	var fat := fatigue / 100.0
	var bo := burnout / 100.0
	var sh := (sharpness - 50.0) / 50.0
	var mult := 1.0
	mult += f * 0.055
	mult += m * 0.025
	mult += sh * 0.030
	mult -= fat * 0.075
	mult -= bo * 0.090
	return clampf(mult, 0.82, 1.12)


## Marge de progression restante (0..1). Sert au système de développement.
func growth_headroom() -> float:
	return clampf(float(potential_ability - current_ability) / 100.0, 0.0, 1.0)


func to_dict() -> Dictionary:
	return {
		"id": id, "game_id": game_id,
		"first_name": first_name, "last_name": last_name, "gamertag": gamertag,
		"nationality": nationality, "region": region, "birth_day": birth_day,
		"attributes": attributes.duplicate(),
		"current_ability": current_ability, "potential_ability": potential_ability,
		"roles": roles.duplicate(), "primary_role": primary_role, "is_igl": is_igl,
		"form": form, "morale": morale, "fatigue": fatigue, "burnout": burnout,
		"sharpness": sharpness, "injured_until": injured_until,
		"injury_label": injury_label,
		"org_id": org_id,
		"contract": contract.to_dict() if contract != null else null,
		"reputation": reputation, "fan_appeal": fan_appeal,
		"market_value": market_value, "traits": traits.duplicate(),
		"career": career.duplicate(true), "season_stats": season_stats.duplicate(true),
		"game_data": game_data.duplicate(true),
		"happiness": happiness, "transfer_listed": transfer_listed,
		"wants_out": wants_out, "retired": retired, "retire_day": retire_day,
	}


static func from_dict(d: Dictionary) -> Player:
	var p := Player.new()
	p.id = d.get("id", "")
	p.game_id = d.get("game_id", "valorant")
	p.first_name = d.get("first_name", "")
	p.last_name = d.get("last_name", "")
	p.gamertag = d.get("gamertag", "")
	p.nationality = d.get("nationality", "FR")
	p.region = d.get("region", "EMEA")
	p.birth_day = int(d.get("birth_day", 0))
	p.attributes = (d.get("attributes", {}) as Dictionary).duplicate()
	p.current_ability = int(d.get("current_ability", 80))
	p.potential_ability = int(d.get("potential_ability", 120))
	p.roles = (d.get("roles", {}) as Dictionary).duplicate()
	p.primary_role = d.get("primary_role", "")
	p.is_igl = bool(d.get("is_igl", false))
	p.form = float(d.get("form", 50.0))
	p.morale = float(d.get("morale", 60.0))
	p.fatigue = float(d.get("fatigue", 0.0))
	p.burnout = float(d.get("burnout", 0.0))
	p.sharpness = float(d.get("sharpness", 60.0))
	p.injured_until = int(d.get("injured_until", -1))
	p.injury_label = d.get("injury_label", "")
	p.org_id = d.get("org_id", "")
	var c = d.get("contract", null)
	p.contract = Contract.from_dict(c) if c != null else null
	p.reputation = int(d.get("reputation", 300))
	p.fan_appeal = int(d.get("fan_appeal", 20))
	p.market_value = int(d.get("market_value", 0))
	var tr: Array[String] = []
	for t in d.get("traits", []):
		tr.append(str(t))
	p.traits = tr
	p.career = (d.get("career", []) as Array).duplicate(true)
	p.season_stats = (d.get("season_stats", {}) as Dictionary).duplicate(true)
	p.game_data = (d.get("game_data", {}) as Dictionary).duplicate(true)
	p.happiness = float(d.get("happiness", 60.0))
	p.transfer_listed = bool(d.get("transfer_listed", false))
	p.wants_out = bool(d.get("wants_out", false))
	p.retired = bool(d.get("retired", false))
	p.retire_day = int(d.get("retire_day", -1))
	return p
