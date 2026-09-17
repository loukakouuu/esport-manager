extends SceneTree

## Construit la section Counter-Strike d'un pack de données à partir du
## classement mondial HLTV.
##
##   godot --headless --path . --script res://tools/import_hltv.gd -- \
##       [--pack=vct_2026] [--snapshot=<chemin>] [--dry]
##
## POURQUOI CE SCRIPT NE TÉLÉCHARGE RIEN
## HLTV répond 403 à tout client qui n'est pas un navigateur — curl comme le
## HTTPRequest de Godot. Il n'existe donc pas de récolte automatisable, et
## l'inventer serait mentir sur ce que le script fait. La lecture de la page se
## fait À LA MAIN dans un navigateur (voir tools/hltv/README.md), et ce script
## ne fait que CONVERTIR l'instantané obtenu. Le partage des rôles est net :
## la récolte est manuelle et datée, la conversion est reproductible.
##
## CE QU'ON PREND, ET POURQUOI C'EST HLTV
## Le classement mondial donne d'un seul tenant : le nom des écuries, leur
## RANG (donc la hiérarchie), et pour chacune ses cinq joueurs avec pseudo,
## nom civil et nationalité. C'est exactement l'identité qu'un pack apporte.
##
## Et il donne une chose que le pack Valorant ne peut PAS donner : une
## hiérarchie publiée. « Fnatic est plus fort que BBL » n'est pas une donnée
## publique en Valorant, et le pack VCT laisse donc le jeu inventer l'ordre.
## En Counter-Strike, l'ordre EST publié — c'est le classement HLTV. Le champ
## `strength` de ce pack-ci est donc une vraie mesure, pas un palier poli.
##
## CE QU'ON NE PREND PAS
##  - Les ATTRIBUTS. « Visée 17/20 » reste un jugement de jeu. La note HLTV
##    d'un joueur est publique, mais la convertir en attributs serait un
##    modèle de plus, et ce pack apporte l'identité, pas la simulation.
##  - Les DATES DE NAISSANCE. Elles ne sont que sur les fiches individuelles :
##    450 pages pour un âge. Le moteur en génère un plausible.
##  - Les autres DISCIPLINES d'une maison : HLTV ne parle que de CS. Une
##    structure créée ici ne déclare donc que sa section Counter-Strike.
##
## CONDITIONS D'UTILISATION — À LIRE AVANT DE LANCER
##  - Les noms d'équipes et de joueurs appartiennent à leurs détenteurs, et le
##    classement est le travail éditorial de HLTV. Un pack construit ici est
##    destiné à un USAGE PERSONNEL : ne le redistribuez pas.
##  - Le manifeste écrit par ce script porte la source et sa date.

const DEFAULT_PACK := "vct_2026"
const SNAPSHOT_DIR := "res://tools/hltv"

## Annexe facultative des dates de naissance, produite par
##   tools/import_liquipedia.gd --profiles
## HLTV ne publie l'âge que sur les fiches individuelles ; le wiki
## Counter-Strike de Liquipedia répond par lots de cinquante. Deux sources,
## deux fichiers : chacun garde sa provenance et sa licence.
const PROFILES := "res://tools/hltv/profiles.json"

## Régions du jeu, déduites de la NATIONALITÉ des joueurs et non du pays de la
## marque : une écurie de Counter-Strike joue le circuit de ses joueurs, pas
## celui de son siège. MOUZ est allemande et joue en Europe ; Alter Ego est
## indonésienne et joue en Asie. Le pays affiché pour la structure est celui
## qui revient le plus souvent dans l'effectif, pour la même raison.
const CHINA_CC := ["CN", "HK", "MO", "TW"]
const PACIFIC_CC := ["KR", "JP", "MN", "ID", "TH", "VN", "PH", "MY", "SG",
	"AU", "NZ", "IN", "BD", "PK", "LK", "NP", "KH", "LA", "MM", "BN"]
const AMERICAS_CC := ["US", "CA", "MX", "BR", "AR", "CL", "PE", "CO", "UY",
	"PY", "BO", "EC", "VE", "CR", "PA", "GT", "DO", "PR", "HN", "SV", "NI",
	"JM", "TT", "CU", "BZ", "GY", "SR"]

## Places par région et par étage : Pro League, Challenger League, circuit
## ouvert.
##
## L'EMEA en a plus que les autres, et ce n'est pas un favoritisme : le
## classement mondial y place vingt-trois écuries dans les trente-cinq
## premières, contre deux pour la Chine. Donner partout le même nombre de
## places obligerait soit à inventer des équipes européennes de trop, soit à
## jeter FaZe, BIG et NiP faute de siège. La pyramide épouse donc la
## profondeur réelle de chaque région.
const SLOTS := {
	"EMEA": [12, 10, 8],
	"AMERICAS": [8, 6, 6],
	"PACIFIC": [6, 6, 6],
	"CHINA": [6, 6, 6],
}
const LEVELS := ["pro", "chal", "open"]

## Bandes de niveau des trois étages.
##
## Ce ne sont pas les bornes ABSOLUES du moteur (WorldGenerator._tier_floor /
## _tier_ceiling, soit 64-88 / 40-62 / 26-40) mais celles qu'emploie le
## contenu livré, et c'est délibéré : les finances ont été équilibrées sur
## cette distribution-là. La réputation et la base de fans suivent une
## puissance 6,6 de la force — trois points de moins au bas du circuit ouvert
## divisent le nombre de fans par deux, et une écurie sans autre section n'y
## survit pas à sa première saison. On reste donc dans les bornes du moteur,
## mais sur la distribution qui a été mesurée.
const TIER_FLOOR := [66.0, 42.0, 28.0]
const TIER_CEIL := [88.0, 61.0, 38.0]

## Rang mondial HLTV -> indice de force du jeu. Interpolation linéaire entre
## ces points d'ancrage.
##
## Les POINTS HLTV ne conviennent pas : ils sont d'une brutalité exponentielle
## (1000 pour le premier, 246 pour le dixième, 52 pour le trentième), et les
## transposer tels quels écraserait tout le monde sauf le champion. Le RANG,
## lui, se lit comme un classement : c'est la grandeur qu'on veut.
const CURVE := [
	[1, 90.0], [10, 80.0], [20, 73.0], [30, 68.0], [50, 60.0],
	[80, 52.0], [120, 45.0], [180, 38.0], [243, 32.0],
]

## Le classement liste aussi les équipes-école des grosses écuries. Les
## engager créerait une structure « Spirit Academy » à côté de « Spirit »,
## alors que le jeu fabrique déjà lui-même une académie à chaque maison.
const ACADEMY_WORDS := ["academy", "junior", "juniors", "youth", "talent"]

## Suffixes et préfixes d'entreprise qu'un site met et qu'un autre omet :
## HLTV écrit « Vitality » là où Liquipedia écrit « Team Vitality ». Voir
## _match_key : c'est ce qui décide si une ligne CS ouvre une SECTION dans une
## maison existante ou crée une structure de plus.
const NAME_SUFFIXES := [" esports club", " esports", " e-sports", " esport",
	" gaming", " club"]
const NAME_PREFIXES := ["team "]

## Vocabulaire des postes du wiki Counter-Strike -> postes du module.
## Relevé sur les 372 joueurs du pack : rifle 146 · igl 68 · awp 62 ·
## rifler 35 · entry 34 · support 16 · lurk 13 · lurker 3 · entryfragger 3 ·
## awper 3 · coach 1. Le wiki ne normalise pas, d'où les doublets.
## `igl` n'est pas un poste mais un rôle de capitaine : il est traité à part.
const ROLE_MAP := {
	"awp": "awper", "awper": "awper",
	"entry": "entry_fragger", "entryfragger": "entry_fragger",
	"entry fragger": "entry_fragger",
	"support": "support",
	"lurk": "lurker", "lurker": "lurker",
	"rifle": "rifler", "rifler": "rifler",
}

## Du plus SPÉCIFIQUE au plus générique. Une fiche porte souvent deux postes
## (`awp,rifle` pour ZywOo, `igl,rifle` pour FalleN) : on garde celui qui dit
## quelque chose. « Rifleur » est le poste par défaut de qui n'a rien de
## particulier, il ne doit donc jamais l'emporter sur « AWPeur ».
const ROLE_PRIORITY := ["awper", "lurker", "entry_fragger", "support", "rifler"]

var _pack := DEFAULT_PACK
var _snapshot := ""
var _dry := false
## pseudo -> {"born", "igl"} ; vide si l'annexe n'a jamais été produite.
var _born := {}
var _born_used := 0
var _roles_used := 0


func _initialize() -> void:
	_parse_args()
	_run()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pack="):
			_pack = arg.substr(7)
		elif arg.begins_with("--snapshot="):
			_snapshot = arg.substr(11)
		elif arg == "--dry":
			_dry = true
		elif arg in ["--help", "-h"]:
			_usage("")
			return
		else:
			_usage("Option inconnue : %s" % arg)
			return


func _usage(message: String) -> void:
	if message != "":
		print("\n%s\n" % message)
	print("Usage : godot --headless --path . --script res://tools/import_hltv.gd -- \\")
	print("            [--pack=%s] [--snapshot=<chemin>] [--dry]\n" % DEFAULT_PACK)
	print("  --pack=      pack complété sous user://packs/ (défaut : %s)" % DEFAULT_PACK)
	print("  --snapshot=  instantané à convertir (défaut : le plus récent de")
	print("               %s)" % SNAPSHOT_DIR)
	print("  --dry        n'écrit rien, montre ce qui serait produit\n")
	quit(0 if message == "" else 2)


func _run() -> void:
	# On lit toujours le contenu LIVRÉ : sinon un second import se
	# construirait sur le résultat du premier.
	DataPack.set_active("")

	var path := _snapshot if _snapshot != "" else _latest_snapshot()
	if path == "":
		print("\nAucun instantané dans %s." % SNAPSHOT_DIR)
		print("Voir tools/hltv/README.md pour en produire un.")
		quit(1)
		return
	var snap := _read_json(path)
	var raw: Array = snap.get("teams", [])
	if raw.is_empty():
		print("\n%s ne contient aucune équipe." % path)
		quit(1)
		return

	print("")
	print("Import HLTV — %s" % path.get_file())
	print("  classement du %s, relevé le %s"
		% [str(snap.get("ranking_date", "?")), str(snap.get("captured", "?"))])
	print("  %d écuries, %d joueurs" % [raw.size(), _players_in(raw)])

	var teams := _read_teams(raw)
	print("  %d retenues (%d équipes-école écartées)"
		% [teams.size(), raw.size() - teams.size()])

	_born = _read_json(PROFILES).get("players", {})
	if _born.is_empty():
		print("  pas d'annexe de dates de naissance : les âges seront générés.")
		print("  (voir tools/import_liquipedia.gd --profiles)")
	else:
		print("  annexe de dates de naissance : %d joueurs connus" % _born.size())

	# Aligner l'orthographe AVANT de répartir : c'est le nom qui décide si la
	# ligne rejoint une maison existante.
	var renamed := _align_names(teams)

	var leagues := {}
	var rosters := {}
	_assign(teams, leagues, rosters)

	var shipped_fill := _fill_from_shipped(leagues)
	_report(leagues, renamed, shipped_fill)

	if _dry:
		print("\n--dry : rien n'écrit.")
		quit(0)
		return
	_write_pack(leagues, rosters, snap)
	quit(0)


# ============================================================================
# Lecture de l'instantané
# ============================================================================

func _latest_snapshot() -> String:
	var dir := DirAccess.open(SNAPSHOT_DIR)
	if dir == null:
		return ""
	var best := ""
	for f in dir.get_files():
		if f.begins_with("ranking-") and f.ends_with(".json") and f > best:
			best = f
	return "" if best == "" else "%s/%s" % [SNAPSHOT_DIR, best]


## Lecture brute, hors du cache et de la chaîne de résolution des packs : ici
## on veut CE fichier-là, pas celui que le pack actif choisirait.
func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var json := JSON.new()
	var err := json.parse(f.get_as_text())
	f.close()
	if err != OK:
		print("JSON illisible (%s, ligne %d) : %s"
			% [path, json.get_error_line(), json.get_error_message()])
		return {}
	return json.data if json.data is Dictionary else {}


func _players_in(raw: Array) -> int:
	var n := 0
	for t_v in raw:
		n += ((t_v as Array)[3] as Array).size()
	return n


## Une ligne du classement -> une écurie exploitable.
func _read_teams(raw: Array) -> Array:
	var out: Array = []
	for t_v in raw:
		var t: Array = t_v
		var name := _clean_name(str(t[0]))
		if _is_academy(name):
			continue
		var players: Array = t[3]
		if players.is_empty():
			continue
		var countries: Array = []
		var regions: Array = []
		for p_v in players:
			var cc := str((p_v as Array)[3])
			countries.append(cc)
			regions.append(_region_of(cc))
		out.append({
			"name": name,
			"rank": int(t[1]),
			"points": int(t[2]),
			"region": _modal(regions),
			"country": _modal(countries),
			"players": players,
		})
	out.sort_custom(func(a, b): return int(a["rank"]) < int(b["rank"]))
	return out


## HLTV préfixe « ex- » l'effectif qui a quitté son écurie. Le nom qui reste
## est celui sous lequel ces joueurs ont joué la saison : on le garde, sans le
## préfixe, plutôt que de perdre l'équipe.
func _clean_name(name: String) -> String:
	var n := name.strip_edges()
	if n.to_lower().begins_with("ex-"):
		n = n.substr(3).strip_edges()
	return n


func _is_academy(name: String) -> bool:
	var low := " %s " % name.to_lower()
	for w in ACADEMY_WORDS:
		if low.contains(" %s " % w):
			return true
	return false


func _region_of(cc: String) -> String:
	if CHINA_CC.has(cc):
		return "CHINA"
	if PACIFIC_CC.has(cc):
		return "PACIFIC"
	if AMERICAS_CC.has(cc):
		return "AMERICAS"
	return "EMEA"


## Valeur la plus fréquente. À égalité, l'ordre alphabétique tranche : une
## conversion doit donner deux fois le même résultat.
func _modal(values: Array) -> String:
	var tally := {}
	for v in values:
		tally[v] = int(tally.get(v, 0)) + 1
	var best := ""
	var best_n := 0
	var keys: Array = tally.keys()
	keys.sort()
	for k in keys:
		if int(tally[k]) > best_n:
			best = str(k)
			best_n = int(tally[k])
	return best


# ============================================================================
# Orthographe des noms
# ============================================================================

## Aligne le nom des écuries sur celui que le pack emploie DÉJÀ côté Valorant.
##
## C'est tout l'enjeu de la maison à deux sections : WorldGenerator ne
## rapproche une ligne de `orgs_cs2.json` d'une structure existante que si le
## nom est IDENTIQUE au caractère près. « Vitality » et « Team Vitality »
## resteraient deux structures distinctes, avec deux trésoreries — exactement
## ce que le projet promet de ne pas faire.
##
## On ne rapproche que les noms qui coïncident une fois débarrassés de leur
## habillage d'entreprise : mieux vaut deux structures séparées qu'une fusion
## abusive, qui donnerait à une maison une section qu'elle n'a pas.
func _align_names(teams: Array) -> Array:
	var known := {}
	for source in [_pack_orgs_path(), "res://data/world/orgs.json"]:
		var d := _read_json(source)
		for key in d.get("leagues", {}):
			for e_v in (d["leagues"] as Dictionary)[key]:
				var name := str((e_v as Dictionary)["name"])
				known[_match_key(name)] = name
	var renamed: Array = []
	for t_v in teams:
		var t: Dictionary = t_v
		var official := str(known.get(_match_key(str(t["name"])), ""))
		if official != "" and official != str(t["name"]):
			renamed.append("%s → %s" % [t["name"], official])
			t["name"] = official
	return renamed


func _pack_orgs_path() -> String:
	return "%s/world/orgs.json" % DataPack.root_of(_pack)


func _match_key(name: String) -> String:
	var k := name.to_lower().strip_edges()
	for p in NAME_PREFIXES:
		if k.begins_with(p):
			k = k.substr(p.length())
	for s in NAME_SUFFIXES:
		if k.ends_with(s):
			k = k.substr(0, k.length() - s.length())
			break
	var out := ""
	for i in k.length():
		var c := k[i]
		if c.is_valid_identifier() or c.is_valid_int() or c == " ":
			out += c
	return out.strip_edges()


# ============================================================================
# Répartition dans la pyramide
# ============================================================================

## Répartit les écuries d'une région dans ses trois étages, dans l'ordre du
## classement mondial, et leur donne une force.
##
## POURQUOI RELATIF À LA RÉGION ET PAS ABSOLU
## Découper sur la force absolue — « tier 1 = les trente-cinq premières du
## monde » — laisserait la Pro League chinoise avec deux équipes réelles et
## quatre inventées, parce que la Chine n'a que deux écuries dans ce paquet.
## On prend donc les meilleures de CHAQUE région pour son premier étage. Un
## championnat national est de toute façon relatif à son pays : c'est ce que
## modélisent déjà les barrages de montée du jeu.
##
## La FORCE, elle, reste absolue : elle vient du rang mondial. La Pro League
## chinoise existe donc, mais ses six équipes pèsent 64 à 68 quand l'européenne
## pèse 74 à 88. L'écart entre régions survit au découpage, et c'est lui qui
## fait qu'un Major ne se joue pas à pile ou face.
func _assign(teams: Array, leagues: Dictionary, rosters: Dictionary) -> void:
	for region in SLOTS:
		var pool: Array = []
		for t_v in teams:
			if str((t_v as Dictionary)["region"]) == region:
				pool.append(t_v)
		var taken := 0
		for k in LEVELS.size():
			var n := int((SLOTS[region] as Array)[k])
			var take := pool.slice(taken, taken + n)
			taken += n
			var key := "cs_%s_%s" % [LEVELS[k], str(region).to_lower()]
			leagues[key] = _entries_for(take, k, n)
			for t_v in take:
				var t: Dictionary = t_v
				rosters[str(t["name"])] = {"players": _roster_of(t)}


## Une ligne de `orgs_cs2.json` par écurie retenue, force comprise.
##
## La force s'étale du meilleur au moins bon de la ligue, sur une amplitude
## égale à celle que la courbe donne au rang de ses équipes, rabattue dans la
## bande de l'étage. Concrètement : une ligue dont les six équipes tiennent en
## quatre points de classement mondial reste serrée dans le jeu, une ligue
## étalée reste étalée. Les places qu'aucune équipe réelle ne remplit
## continuent la descente vers le plancher de l'étage — voir _fill_from_shipped.
func _entries_for(take: Array, tier_index: int, slots: int) -> Array:
	var ceil_v: float = TIER_CEIL[tier_index]
	var floor_v: float = TIER_FLOOR[tier_index]
	var hi := ceil_v
	var width := 2.0
	if not take.is_empty():
		var best := _curve(int((take[0] as Dictionary)["rank"]))
		var worst := _curve(int((take[take.size() - 1] as Dictionary)["rank"]))
		hi = minf(ceil_v, best)
		# Une ligue dont la MEILLEURE équipe est déjà sous le plancher de son
		# étage doit quand même pouvoir s'aligner : on la remonte juste dedans.
		if hi <= floor_v:
			hi = floor_v + 0.25 * (ceil_v - floor_v)
		width = maxf(best - worst, 2.0)
	var lo := maxf(floor_v, hi - width)
	var step := (hi - lo) / float(maxi(slots - 1, 1))

	var out: Array = []
	for i in take.size():
		var t: Dictionary = take[i]
		out.append({
			"name": str(t["name"]),
			"tag": _tag_from_name(str(t["name"])),
			"country": str(t["country"]),
			"strength": snappedf(hi - step * float(i), 0.1),
			"owner": _owner_for(tier_index, str(t["name"])),
			"color": _color_from(str(t["name"])),
			"_hltv_rank": int(t["rank"]),
		})
	return out


## Rang mondial -> force, par interpolation entre les ancres de CURVE.
func _curve(rank: int) -> float:
	if rank <= int(CURVE[0][0]):
		return float(CURVE[0][1])
	for i in range(1, CURVE.size()):
		var r0 := float(CURVE[i - 1][0])
		var s0 := float(CURVE[i - 1][1])
		var r1 := float(CURVE[i][0])
		var s1 := float(CURVE[i][1])
		if float(rank) <= r1:
			return s0 + (s1 - s0) * (float(rank) - r0) / (r1 - r0)
	return float(CURVE[CURVE.size() - 1][1])


func _roster_of(t: Dictionary) -> Array:
	var out: Array = []
	for p_v in t["players"]:
		var p: Array = p_v
		var entry := {"tag": str(p[0]), "country": str(p[3])}
		if str(p[1]) != "":
			entry["first"] = str(p[1])
		if str(p[2]) != "":
			entry["last"] = str(p[2])
		# La date de naissance et le POSTE viennent de l'annexe Liquipedia.
		# L'âge fixe la position sur la courbe de progression ; le poste, lui,
		# est ce qui se remarque le plus vite en Counter-Strike — il n'y a
		# qu'une AWP par équipe et tout le monde sait qui la tient.
		var extra: Dictionary = _born.get(str(p[0]), {})
		if str(extra.get("born", "")) != "":
			entry["born"] = str(extra["born"])
			_born_used += 1
		var role := _role_from(str(extra.get("roles", "")))
		if role != "":
			entry["role"] = role
			_roles_used += 1
		if bool(extra.get("igl", false)):
			entry["igl"] = true
		out.append(entry)
	return out


## « awp,rifle » -> « awper ». Voir ROLE_MAP et ROLE_PRIORITY.
func _role_from(roles: String) -> String:
	var found := {}
	for token in roles.split(",", false):
		var key := str(ROLE_MAP.get(token.strip_edges(), ""))
		if key != "":
			found[key] = true
	for role in ROLE_PRIORITY:
		if found.has(role):
			return str(role)
	return ""


## Complète les ligues que le classement ne remplit pas avec les équipes
## FICTIVES livrées, en continuant la descente vers le plancher de l'étage.
##
## Le cas est celui de la Chine : le classement mondial n'y compte que huit
## écuries, toutes absorbées par sa Pro League et le haut de sa Challenger.
## Laisser une ligue à deux équipes n'aurait pas de sens sportif ; la combler
## de vraies équipes qui n'y sont pas en aurait encore moins.
func _fill_from_shipped(leagues: Dictionary) -> int:
	var shipped := _read_json("res://data/world/orgs_cs2.json")
	var pools: Dictionary = shipped.get("leagues", {})
	var added := 0
	for key in leagues:
		var entries: Array = leagues[key]
		var tier_index := 0
		for k in LEVELS.size():
			if str(key).begins_with("cs_%s_" % LEVELS[k]):
				tier_index = k
		var slots := int((SLOTS[_region_key(str(key))] as Array)[tier_index])
		if entries.size() >= slots:
			continue
		var floor_v: float = TIER_FLOOR[tier_index]
		var top: float = float(entries[0]["strength"]) \
			if not entries.is_empty() else float(TIER_CEIL[tier_index])
		var step := (top - floor_v) / float(maxi(slots - 1, 1))
		var spare: Array = pools.get(key, [])
		var used := 0
		for i in range(entries.size(), slots):
			if used >= spare.size():
				break
			var e: Dictionary = (spare[used] as Dictionary).duplicate()
			used += 1
			e["strength"] = snappedf(maxf(floor_v, top - step * float(i)), 0.1)
			e["_fictional"] = true
			entries.append(e)
			added += 1
	return added


func _region_key(league_key: String) -> String:
	for region in SLOTS:
		if league_key.ends_with(str(region).to_lower()):
			return str(region)
	return "EMEA"


## La PROPRIÉTÉ d'une écurie n'est pas publiée par HLTV. On en pose une,
## stable et plausible : plus l'étage est haut, plus la maison est adossée à
## un investisseur ou à un groupe.
func _owner_for(tier_index: int, name: String) -> String:
	var choices: Array = [
		["corporate", "investor", "investor", "endemic"],
		["investor", "endemic", "endemic", "self_funded"],
		["self_funded", "self_funded", "endemic", "celebrity"],
	][tier_index]
	return str(choices[_hash_of(name) % choices.size()])


func _hash_of(name: String) -> int:
	var h := 0
	for i in name.length():
		h = (h * 31 + name.unicode_at(i)) % 100000
	return h


## Sigle de repli : initiales, ou trois premières lettres d'un nom d'un mot.
## Même règle que tools/import_liquipedia.gd — HLTV ne publie pas de sigle.
func _tag_from_name(name: String) -> String:
	var parts := name.split(" ", false)
	if parts.size() >= 2:
		var out := ""
		for p in parts:
			out += p.substr(0, 1)
		return out.to_upper().substr(0, 4)
	return name.to_upper().substr(0, 3)


## Couleur stable dérivée du nom : elle ne bouge pas d'un import à l'autre.
func _color_from(name: String) -> String:
	return "#" + Color.from_hsv(float(_hash_of(name) % 360) / 360.0,
		0.62, 0.78).to_html(false)


# ============================================================================
# Rapport et écriture
# ============================================================================

func _report(leagues: Dictionary, renamed: Array, filled: int) -> void:
	print("")
	print("Pyramide Counter-Strike :")
	var keys: Array = leagues.keys()
	keys.sort()
	for key in keys:
		var entries: Array = leagues[key]
		var real: Array = []
		for e_v in entries:
			if not bool((e_v as Dictionary).get("_fictional", false)):
				real.append(e_v)
		var line := "  %-17s %d équipes (%d réelles)  force %.1f → %.1f" % [
			key, entries.size(), real.size(),
			float(entries[0]["strength"]),
			float(entries[entries.size() - 1]["strength"])]
		print(line)
		var names: Array = []
		for e_v in entries:
			var e: Dictionary = e_v
			names.append(str(e["name"]) if not bool(e.get("_fictional", false))
				else "(%s)" % str(e["name"]))
		print("      " + ", ".join(names))
	if filled > 0:
		print("")
		print("  %d places comblées par les équipes fictives livrées " % filled
			+ "(entre parenthèses ci-dessus) :")
		print("  le classement mondial ne compte pas assez d'écuries dans ces "
			+ "régions.")
	if not renamed.is_empty():
		print("")
		print("Orthographes alignées sur le pack (%d) — ces maisons tiendront "
			% renamed.size() + "DEUX sections :")
		for r in renamed:
			print("  %s" % r)


func _write_pack(leagues: Dictionary, rosters: Dictionary,
		snap: Dictionary) -> void:
	var root_dir := DataPack.user_root_of(_pack)
	DirAccess.make_dir_recursive_absolute(root_dir + "/world")

	# Un pack de l'utilisateur MASQUE entièrement le pack livré du même nom
	# (DataPack.root_of). Écrire ici les seuls fichiers Counter-Strike ferait
	# donc disparaître les vraies équipes Valorant, sans le moindre message.
	# On recopie donc ce qu'on ne régénère pas.
	var copied := _copy_bundled(root_dir, ["world/orgs_cs2.json",
		"world/rosters_cs2.json", DataPack.MANIFEST])

	var teams := 0
	var real := 0
	for key in leagues:
		for e_v in leagues[key]:
			teams += 1
			if not bool((e_v as Dictionary).get("_fictional", false)):
				real += 1
	# `_hltv_rank` et `_fictional` ne servent qu'au rapport : on ne les écrit
	# pas, le format d'un pack est décrit dans docs/DATA_PACKS.md et n'en
	# parle pas.
	var clean := {}
	for key in leagues:
		var out: Array = []
		for e_v in leagues[key]:
			var e: Dictionary = (e_v as Dictionary).duplicate()
			e.erase("_hltv_rank")
			e.erase("_fictional")
			out.append(e)
		clean[key] = out

	var dated := "Pyramide Counter-Strike bâtie sur le classement mondial HLTV "
	dated += "du %s." % str(snap.get("ranking_date", "?"))
	dated += " `strength` vient du RANG mondial : contrairement au circuit"
	dated += " Valorant, la hiérarchie du CS est publiée. Une entrée dont le"
	dated += " nom existe déjà ouvre une SECTION dans cette maison au lieu de"
	dated += " créer une structure. Marques appartenant à leurs détenteurs."
	DataFile.save_json(root_dir + "/world/orgs_cs2.json", {
		"_comment": dated,
		"leagues": clean,
	})
	DataFile.save_json(root_dir + "/world/rosters_cs2.json", {
		"_comment": "Effectifs réels relevés sur HLTV. Le moteur reprend les "
			+ "identités et génère tout le reste : âge, attributs, potentiel, "
			+ "contrats.",
		"teams": rosters,
	})
	_write_manifest(root_dir, snap, real, rosters)

	print("")
	print("Pack écrit dans %s" % ProjectSettings.globalize_path(root_dir))
	print("  %d équipes Counter-Strike dont %d réelles, %d joueurs réels."
		% [teams, real, _roster_size(rosters)])
	if _born_used > 0:
		print("  %d avec leur vraie date de naissance, %d avec leur vrai poste."
			% [_born_used, _roles_used])
	if copied > 0:
		print("  %d fichier(s) du pack livré recopiés tels quels." % copied)
	print("")
	print("Pour jouer avec : lancez le jeu → Nouvelle partie → choisissez le")
	print("pack dans la liste avant de générer le monde.")
	print("")
	print("Rappel : le classement et les noms appartiennent à HLTV et aux")
	print("écuries. Pack destiné à votre usage personnel — ne le redistribuez")
	print("pas comme s'il faisait partie du jeu.")


## Recopie les fichiers du pack livré que cet import ne régénère pas.
func _copy_bundled(root_dir: String, generated: Array) -> int:
	var bundled := "%s/%s" % [DataPack.BUNDLED_DIR, _pack]
	if root_dir.begins_with(DataPack.BUNDLED_DIR) \
			or not DirAccess.dir_exists_absolute(bundled):
		return 0
	var n := 0
	for rel in _walk(bundled, ""):
		if generated.has(rel):
			continue
		var dest := "%s/%s" % [root_dir, rel]
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		if DirAccess.copy_absolute("%s/%s" % [bundled, rel], dest) == OK:
			n += 1
	return n


func _walk(base: String, relative: String) -> Array:
	var out: Array = []
	var full := base if relative == "" else "%s/%s" % [base, relative]
	var dir := DirAccess.open(full)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(f if relative == "" else "%s/%s" % [relative, f])
	for sub in dir.get_directories():
		out.append_array(_walk(base,
			sub if relative == "" else "%s/%s" % [relative, sub]))
	return out


## Le manifeste est COMPLÉTÉ, pas réécrit : le pack porte déjà les vraies
## équipes Valorant et leur licence Liquipedia. Les deux sources cohabitent et
## doivent être créditées toutes les deux.
func _write_manifest(root_dir: String, snap: Dictionary, real: int,
		rosters: Dictionary) -> void:
	var m := _read_json("%s/%s" % [DataPack.root_of(_pack), DataPack.MANIFEST])
	m.erase("id")
	m.erase("files")
	m.erase("bundled")
	m["version"] = Time.get_date_string_from_system()
	m["source"] = "%s + %s" % [str(m.get("source", "")).split(" + ")[0],
		str(snap.get("source", "https://www.hltv.org/ranking/teams"))]
	m["license"] = "CC-BY-SA 3.0 (Liquipedia) · HLTV.org (classement)"
	# Le pack couvre désormais DEUX disciplines : son nom d'affichage ne peut
	# plus dire « VCT ». Son identifiant, lui, reste `vct_2026` — c'est celui
	# qu'ont enregistré les sauvegardes existantes, et le renommer les
	# rendrait toutes illisibles. Même arbitrage que `orgs.json`, qui reste le
	# fichier Valorant parce qu'il est le fichier historique.
	m["name"] = "Saison 2026 — équipes réelles"
	m["author"] = "Import Liquipedia + HLTV"
	var note := "Les sections d'autres disciplines viennent des portails"
	note += " d'équipes actives des wikis Liquipedia : une structure dont le"
	note += " nom diffère d'un wiki à l'autre peut en recevoir moins qu'elle"
	note += " n'en a — mieux vaut en manquer une que d'en inventer une."
	note += " Les Challengers Valorant restent fictifs, faute de source."
	note += " La pyramide Counter-Strike suit le classement mondial HLTV ;"
	note += " ses étages sont relatifs à chaque région, mais la force est"
	note += " absolue, et les rares places que le classement ne remplit pas"
	note += " gardent l'équipe fictive livrée."
	m["note"] = note
	var credit := "Équipes Valorant issues de Liquipedia (CC-BY-SA 3.0)."
	credit += " Classement et effectifs Counter-Strike issus de HLTV.org."
	credit += " Noms et marques appartenant à leurs détenteurs."
	m["attribution"] = credit

	# On repart de la phrase Valorant du manifeste et on lui ajoute la nôtre :
	# relancer l'import ne doit pas empiler deux fois la même description.
	var desc: String = str(m.get("description", "")).split(" Côté ")[0]
	desc += " Côté Counter-Strike, %d écuries réelles et %d joueurs, rangés" \
		% [real, _roster_size(rosters)]
	desc += " selon le classement mondial HLTV du %s." \
		% str(snap.get("ranking_date", "?"))
	m["description"] = desc
	DataFile.save_json("%s/%s" % [root_dir, DataPack.MANIFEST], m)


func _roster_size(rosters: Dictionary) -> int:
	var n := 0
	for k in rosters:
		n += ((rosters[k] as Dictionary)["players"] as Array).size()
	return n
