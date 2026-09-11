class_name Organization
extends RefCounted

## La STRUCTURE esport : l'entreprise que dirige le joueur.
##
## Elle porte la trésorerie, la marque et les contrats. Les résultats sportifs
## arrivent par les Roster ; la santé financière, elle, se joue ici.

enum Owner {
	SELF_FUNDED,   # fondateur passionné : peu de cash, aucune rallonge
	INVESTOR,      # fonds d'investissement : exige de la croissance, recapitalise
	ENDEMIC_BRAND, # marque gaming propriétaire : budget stable, exige de l'image
	CELEBRITY,     # créateur/star : fanbase énorme, patience faible
	CORPORATE,     # groupe media/telecom : gros budget, objectifs de prestige
}

const OWNER_LABELS := {
	Owner.SELF_FUNDED: "Fondateur indépendant",
	Owner.INVESTOR: "Fonds d'investissement",
	Owner.ENDEMIC_BRAND: "Marque gaming",
	Owner.CELEBRITY: "Créateur de contenu",
	Owner.CORPORATE: "Groupe média",
}

var id: String = ""
var name: String = ""
var tag: String = ""               # "AUR"
var region: String = "EMEA"
var country: String = "FR"
var color_primary: String = "#e04141"
var color_secondary: String = "#141414"
var founded_year: int = 2020

## Disciplines réellement alignées par la structure ("valorant", "lol", "cs2"…).
## C'est l'identité de la MAISON, pas la liste de ce que le jeu sait simuler :
## Karmine Corp aligne LoL et Valorant qu'on sache ou non jouer LoL. Seules les
## disciplines présentes dans GameRegistry donnent lieu à un Roster ; les
## autres restent affichées comme sections non simulées. Voir GameCatalog.
var games: Array[String] = ["valorant"]

# --- Finance ---------------------------------------------------------------
var ledger: Ledger = null
var sponsor_deals: Array[SponsorDeal] = []
var loans: Array[Loan] = []
var facilities: Dictionary = {}    # Facilities.Kind -> niveau 0..5

## Budget de fonctionnement voté par la direction pour la saison (indicatif).
var wage_budget_yearly: int = 0    # plafond de masse salariale conseillé
var transfer_budget: int = 0       # enveloppe de rachats disponible

## Budgets de fonctionnement mensuels pilotés par le joueur (cents / mois).
## Ce sont de vrais leviers : couper le marketing améliore la trésorerie mais
## étouffe la fanbase, donc le merch, donc les sponsors de la saison suivante.
var budgets: Dictionary = {"marketing": 0, "scouting": 0, "bootcamp": 0}

## Mois consécutifs en trésorerie négative — déclencheur des mesures d'urgence.
var months_in_deficit: int = 0

## Historique mensuel : [{"day", "cash", "income", "expense"}]. Le grand livre
## est compacté au bout de deux ans ; cet historique-là, léger, survit et
## permet de tracer une courbe de trésorerie sur toute la carrière.
var history: Array = []

# --- Marque ----------------------------------------------------------------
var reputation: int = 2000         # 0..10000
var fanbase: int = 10_000          # nombre de fans, moteur du merch/contenu
var brand_value: int = 0           # cents, valorisation de la structure

# --- Sportif ---------------------------------------------------------------
var roster_ids: Dictionary = {}    # game_id -> Array[String] de roster_id
var staff_ids: Array[String] = []

# --- Direction -------------------------------------------------------------
var owner: Owner = Owner.SELF_FUNDED
var board_confidence: float = 60.0 # 0..100 ; 0 => licenciement
var objectives: Array = []         # objectifs de saison (voir BoardSystem)
var is_player_controlled: bool = false
var bankrupt: bool = false


func cash() -> int:
	return ledger.cash if ledger != null else 0


func rosters_for(game_id: String) -> Array[String]:
	var out: Array[String] = []
	for v in roster_ids.get(game_id, []):
		out.append(str(v))
	return out


func add_roster(game_id: String, roster_id: String) -> void:
	if not roster_ids.has(game_id):
		roster_ids[game_id] = []
	if not (roster_ids[game_id] as Array).has(roster_id):
		(roster_ids[game_id] as Array).append(roster_id)


func all_roster_ids() -> Array[String]:
	var out: Array[String] = []
	for g in roster_ids:
		for v in roster_ids[g]:
			out.append(str(v))
	return out


## La structure aligne-t-elle cette discipline ?
func has_game(game_id: String) -> bool:
	return games.has(game_id)


## Disciplines de la structure que le jeu sait simuler.
func playable_games() -> Array[String]:
	var out: Array[String] = []
	for g in games:
		if GameCatalog.playable(g):
			out.append(g)
	return out


## Disciplines annoncées mais pas encore simulées — affichées, jamais jouées.
func upcoming_games() -> Array[String]:
	var out: Array[String] = []
	for g in games:
		if not GameCatalog.playable(g):
			out.append(g)
	return out


func active_sponsors(today: int) -> Array[SponsorDeal]:
	var out: Array[SponsorDeal] = []
	for s in sponsor_deals:
		if s.is_active(today):
			out.append(s)
	return out


func sponsor_slot_taken(slot: SponsorDeal.Slot, today: int) -> bool:
	for s in active_sponsors(today):
		if s.slot == slot:
			return true
	return false


func total_debt() -> int:
	var d := 0
	for l in loans:
		d += l.outstanding
	return d


func facility_level(k: Facilities.Kind) -> int:
	return int(facilities.get(k, 0))


func facility_effect(k: Facilities.Kind) -> float:
	return Facilities.effect(facilities, k)


func owner_label() -> String:
	return OWNER_LABELS.get(owner, "Propriétaire")


## Réputation exprimée en étoiles (0..5) pour l'affichage.
func stars() -> float:
	return clampf(float(reputation) / 2000.0, 0.0, 5.0)


func to_dict() -> Dictionary:
	var deals: Array = []
	for s in sponsor_deals:
		deals.append(s.to_dict())
	var lns: Array = []
	for l in loans:
		lns.append(l.to_dict())
	return {
		"id": id, "name": name, "tag": tag, "region": region, "country": country,
		"color_primary": color_primary, "color_secondary": color_secondary,
		"founded_year": founded_year, "games": games.duplicate(),
		"ledger": ledger.to_dict() if ledger != null else null,
		"sponsor_deals": deals, "loans": lns,
		"facilities": facilities.duplicate(),
		"wage_budget_yearly": wage_budget_yearly, "transfer_budget": transfer_budget,
		"budgets": budgets.duplicate(), "months_in_deficit": months_in_deficit,
		"history": history.duplicate(true),
		"reputation": reputation, "fanbase": fanbase, "brand_value": brand_value,
		"roster_ids": roster_ids.duplicate(true), "staff_ids": staff_ids.duplicate(),
		"owner": int(owner), "board_confidence": board_confidence,
		"objectives": objectives.duplicate(true),
		"is_player_controlled": is_player_controlled, "bankrupt": bankrupt,
	}


static func from_dict(d: Dictionary) -> Organization:
	var o := Organization.new()
	o.id = d.get("id", "")
	o.name = d.get("name", "")
	o.tag = d.get("tag", "")
	o.region = d.get("region", "EMEA")
	o.country = d.get("country", "FR")
	o.color_primary = d.get("color_primary", "#e04141")
	o.color_secondary = d.get("color_secondary", "#141414")
	o.founded_year = int(d.get("founded_year", 2020))
	o.games = GameCatalog.sanitize(d.get("games", ["valorant"]))
	if o.games.is_empty():
		o.games = ["valorant"]
	var ld = d.get("ledger", null)
	o.ledger = Ledger.from_dict(ld) if ld != null else Ledger.new()
	for sd in d.get("sponsor_deals", []):
		o.sponsor_deals.append(SponsorDeal.from_dict(sd))
	for ln in d.get("loans", []):
		o.loans.append(Loan.from_dict(ln))
	var fac := (d.get("facilities", {}) as Dictionary)
	o.facilities = {}
	for k in fac:
		o.facilities[int(k)] = int(fac[k])
	o.wage_budget_yearly = int(d.get("wage_budget_yearly", 0))
	o.transfer_budget = int(d.get("transfer_budget", 0))
	o.budgets = (d.get("budgets", {}) as Dictionary).duplicate()
	for bk in ["marketing", "scouting", "bootcamp"]:
		if not o.budgets.has(bk):
			o.budgets[bk] = 0
	o.months_in_deficit = int(d.get("months_in_deficit", 0))
	o.history = (d.get("history", []) as Array).duplicate(true)
	o.reputation = int(d.get("reputation", 2000))
	o.fanbase = int(d.get("fanbase", 10000))
	o.brand_value = int(d.get("brand_value", 0))
	o.roster_ids = (d.get("roster_ids", {}) as Dictionary).duplicate(true)
	var st: Array[String] = []
	for v in d.get("staff_ids", []):
		st.append(str(v))
	o.staff_ids = st
	o.owner = int(d.get("owner", 0)) as Owner
	o.board_confidence = float(d.get("board_confidence", 60.0))
	o.objectives = (d.get("objectives", []) as Array).duplicate(true)
	o.is_player_controlled = bool(d.get("is_player_controlled", false))
	o.bankrupt = bool(d.get("bankrupt", false))
	return o
