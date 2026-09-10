class_name World
extends RefCounted

## L'état complet d'une partie. Un seul objet, entièrement sérialisable.
##
## Choix d'architecture : le World ne contient AUCUNE logique — que des
## données et des accesseurs. Toute la simulation vit dans src/systems/, qui
## prend le World en paramètre. Trois bénéfices concrets :
##   - la sauvegarde est un simple to_dict() du World ;
##   - n'importe quel système est testable sur un World fabriqué à la main ;
##   - on peut rejouer une journée en repartant d'un World cloné.

var seed_value: int = 0
var today: int = 0
var start_day: int = 0
var season_year: int = 2026

var ids: Ids = null
var rng: Rng = null

# Référentiels principaux (id -> objet)
var players: Dictionary = {}
var staff: Dictionary = {}
var orgs: Dictionary = {}
var rosters: Dictionary = {}
var competitions: Dictionary = {}
var fixtures: Dictionary = {}

## Structure dirigée par l'utilisateur.
var player_org_id: String = ""
var player_game_id: String = "valorant"

## Pack de données avec lequel cette partie a été créée ("" = contenu livré).
## Sauvegardé pour que le chargement rétablisse le même univers : recharger une
## partie « vraies équipes » avec le contenu fictif afficherait des noms qui ne
## correspondent plus à rien.
var data_pack: String = ""

## Boîte de réception : tout ce que le jeu a à dire au joueur.
var inbox: Array = []

## Sponsors disponibles sur le marché (non signés).
var sponsor_market: Array = []

## Historique des saisons terminées : [{year, comp_key, champion_org, ...}]
var history: Array = []

## Réglages de partie choisis au démarrage.
var settings: Dictionary = {
	"detailed_matches_for_player_only": true,
	"autosave_monthly": true,
}


func _init() -> void:
	ids = Ids.new()
	rng = Rng.new(0)


# --- Accesseurs -------------------------------------------------------------

func player(id: String) -> Player:
	return players.get(id, null)


func org(id: String) -> Organization:
	return orgs.get(id, null)


func roster(id: String) -> Roster:
	return rosters.get(id, null)


func staffer(id: String) -> Staff:
	return staff.get(id, null)


func competition(id: String) -> Competition:
	return competitions.get(id, null)


func fixture(id: String) -> Fixture:
	return fixtures.get(id, null)


func my_org() -> Organization:
	return org(player_org_id)


func module_for(game_id: String) -> GameModule:
	return GameRegistry.get_module(game_id)


func org_of_roster(roster_id: String) -> Organization:
	var r := roster(roster_id)
	return org(r.org_id) if r != null else null


## Le roster principal (non académie) d'une structure sur une discipline.
func main_roster(org_id: String, game_id: String) -> Roster:
	var o := org(org_id)
	if o == null:
		return null
	for rid in o.rosters_for(game_id):
		var r := roster(rid)
		if r != null and not r.is_academy:
			return r
	return null


func players_of(roster_id: String) -> Array[Player]:
	var out: Array[Player] = []
	var r := roster(roster_id)
	if r == null:
		return out
	for pid in r.player_ids:
		var p := player(pid)
		if p != null:
			out.append(p)
	return out


func free_agents(game_id: String) -> Array[Player]:
	var out: Array[Player] = []
	for pid in players:
		var p: Player = players[pid]
		if p.game_id == game_id and p.is_free_agent() and not p.retired:
			out.append(p)
	return out


func competitions_for(game_id: String, region: String = "") -> Array[Competition]:
	var out: Array[Competition] = []
	for cid in competitions:
		var c: Competition = competitions[cid]
		if c.game_id != game_id:
			continue
		if region != "" and c.region != region:
			continue
		out.append(c)
	return out


## Toutes les rencontres d'une journée donnée.
func fixtures_on(day: int) -> Array[Fixture]:
	var out: Array[Fixture] = []
	for fid in fixtures:
		var f: Fixture = fixtures[fid]
		if f.day == day and not f.played:
			out.append(f)
	return out


func upcoming_for_roster(roster_id: String, limit: int = 5) -> Array[Fixture]:
	var out: Array[Fixture] = []
	for fid in fixtures:
		var f: Fixture = fixtures[fid]
		if not f.played and f.involves(roster_id) and f.day >= today:
			out.append(f)
	out.sort_custom(func(a, b): return a.day < b.day)
	return out.slice(0, limit)


func add_news(day: int, title: String, body: String, kind: String = "info",
		meta: Dictionary = {}) -> void:
	inbox.append({
		"id": ids.next(Ids.NEWS), "day": day, "title": title, "body": body,
		"kind": kind, "read": false, "meta": meta,
	})


# --- Sérialisation ----------------------------------------------------------

func to_dict() -> Dictionary:
	var d := {
		"seed_value": seed_value, "today": today, "start_day": start_day,
		"season_year": season_year,
		"ids": ids.to_dict(), "rng": rng.save_state(),
		"player_org_id": player_org_id, "player_game_id": player_game_id,
		"data_pack": data_pack,
		"inbox": inbox.duplicate(true),
		"sponsor_market": sponsor_market.duplicate(true),
		"history": history.duplicate(true),
		"settings": settings.duplicate(true),
	}
	d["players"] = _map_to_dict(players)
	d["staff"] = _map_to_dict(staff)
	d["orgs"] = _map_to_dict(orgs)
	d["rosters"] = _map_to_dict(rosters)
	d["competitions"] = _map_to_dict(competitions)
	d["fixtures"] = _map_to_dict(fixtures)
	return d


static func from_dict(d: Dictionary) -> World:
	var w := World.new()
	w.seed_value = int(d.get("seed_value", 0))
	w.today = int(d.get("today", 0))
	w.start_day = int(d.get("start_day", 0))
	w.season_year = int(d.get("season_year", 2026))
	w.ids.from_dict(d.get("ids", {}))
	w.rng.load_state(d.get("rng", {}))
	w.player_org_id = d.get("player_org_id", "")
	w.player_game_id = d.get("player_game_id", "valorant")
	w.data_pack = str(d.get("data_pack", ""))
	w.inbox = (d.get("inbox", []) as Array).duplicate(true)
	w.sponsor_market = (d.get("sponsor_market", []) as Array).duplicate(true)
	w.history = (d.get("history", []) as Array).duplicate(true)
	w.settings = (d.get("settings", {}) as Dictionary).duplicate(true)

	for k in d.get("players", {}):
		w.players[k] = Player.from_dict(d["players"][k])
	for k in d.get("staff", {}):
		w.staff[k] = Staff.from_dict(d["staff"][k])
	for k in d.get("orgs", {}):
		w.orgs[k] = Organization.from_dict(d["orgs"][k])
	for k in d.get("rosters", {}):
		w.rosters[k] = Roster.from_dict(d["rosters"][k])
	for k in d.get("competitions", {}):
		w.competitions[k] = Competition.from_dict(d["competitions"][k])
	for k in d.get("fixtures", {}):
		w.fixtures[k] = Fixture.from_dict(d["fixtures"][k])
	return w


static func _map_to_dict(m: Dictionary) -> Dictionary:
	var out := {}
	for k in m:
		out[k] = m[k].to_dict()
	return out
