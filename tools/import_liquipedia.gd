extends SceneTree

## Construit un pack de données à partir de Liquipedia.
##
##   godot --headless --path . --script res://tools/import_liquipedia.gd -- \
##       --contact=<identifiant> [--season=2026] [--stage="Stage 1"] \
##       [--pack=liquipedia] [--no-players] [--sections-only] [--dry]
##
## CE QUE FAIT CE SCRIPT
## Il lit les pages de ligue du VCT sur Liquipedia et écrit un pack de données
## dans user://packs/<pack>/ (voir src/core/DataPack.gd) :
##   world/orgs.json     les douze structures de chaque ligue partenaire,
##                       avec les disciplines qu'elles alignent vraiment
##   world/rosters.json  leurs joueurs — pseudo, nom, pays, date de naissance
##
## CE QU'IL N'IMPORTE PAS, ET POURQUOI
## Aucun attribut, aucun niveau, aucun salaire. « Visée 17/20 » n'est pas une
## donnée publique : c'est un jugement de jeu. Le pack apporte donc l'IDENTITÉ
## (qui joue où, sous quel nom, de quel pays) et le moteur continue de générer
## la SIMULATION. Un vrai joueur importé est un vrai nom sur un profil inventé.
##
## CONDITIONS D'UTILISATION — À LIRE AVANT DE LANCER
##  - Le contenu de Liquipedia est sous licence CC-BY-SA 3.0. Un pack qui en
##    dérive doit créditer la source et se partager sous la même licence ; le
##    manifeste écrit par ce script s'en charge.
##  - L'API exige un User-Agent identifiant : d'où --contact, obligatoire.
##    Sans lui, Liquipedia répond 406. Une adresse joignable est la bonne
##    pratique ; pour un import local et non redistribué, un identifiant de
##    projet suffit à respecter l'esprit de la règle.
##  - L'API exige aussi un débit maximal d'une requête toutes les 30 secondes.
##    Le script s'y tient et groupe les requêtes au maximum : comptez cinq à
##    dix minutes pour un import complet. Ne le contournez pas — c'est ce qui
##    fait bannir les adresses IP.
##  - Les noms d'équipes et de joueurs restent la propriété de leurs
##    détenteurs. Un pack construit ici est destiné à votre usage personnel.
##
## Un import écrit TOUJOURS dans user://packs/, jamais dans le dépôt. Le pack
## livré (res://packs/) sert de base de lecture et reste intact ; c'est la
## version utilisateur qui prend le dessus ensuite.

const API_BASE := "https://liquipedia.net/%s/api.php"
## Débit imposé par Liquipedia pour tout ce qui n'est pas action=parse.
const RATE_LIMIT_SEC := 30.0
## Limite MediaWiki sur le nombre de titres par requête groupée.
const BATCH := 50

## Ligues du jeu et pages Liquipedia correspondantes. C'est la seule table à
## retoucher quand le circuit change de forme ou de nommage.
const LEAGUES := [
	{"key": "vct_emea", "region": "EMEA", "page": "EMEA League"},
	{"key": "vct_americas", "region": "AMERICAS", "page": "Americas League"},
	{"key": "vct_pacific", "region": "PACIFIC", "page": "Pacific League"},
	{"key": "vct_china", "region": "CHINA", "page": "China League"},
]

## Rôles qui désignent un capitaine en jeu (l'orthographe varie sur le wiki).
const CAPTAIN_ROLES := ["captain", "capitain", "igl"]

var _contact := ""
var _pack := "liquipedia"
var _season := "2026"
var _stage := "Stage 1"
var _with_players := true
var _with_sections := true
var _sections_only := false
var _dry := false
var _http: HTTPRequest = null
var _last_call_msec := 0
var _requests := 0


func _initialize() -> void:
	_parse_args()
	if _contact == "":
		_usage("--contact=<email ou URL> est obligatoire : sans lui, l'API de "
			+ "Liquipedia refuse la requête (HTTP 406).")
		return
	_http = HTTPRequest.new()
	_http.accept_gzip = true
	_http.timeout = 30.0
	root.add_child(_http)
	_start()


## HTTPRequest refuse de travailler tant qu'il n'est pas DANS l'arbre, et
## add_child() ne prend effet qu'à la trame suivante : sans cette attente, la
## toute première requête échoue en silence.
func _start() -> void:
	await process_frame
	_run()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--contact="):
			_contact = arg.substr(10).strip_edges()
		elif arg.begins_with("--pack="):
			_pack = arg.substr(7).strip_edges()
		elif arg.begins_with("--season="):
			_season = arg.substr(9).strip_edges()
		elif arg.begins_with("--stage="):
			_stage = arg.substr(8).strip_edges()
		elif arg == "--sections-only":
			_sections_only = true
		elif arg == "--no-sections":
			_with_sections = false
		elif arg == "--no-players":
			_with_players = false
		elif arg == "--dry":
			_dry = true


func _usage(message: String) -> void:
	print("")
	print("  %s" % message)
	print("")
	print("  godot --headless --path . --script res://tools/import_liquipedia.gd -- \\")
	print("      --contact=vous@example.com [--season=2026] [--stage=\"Stage 1\"] \\")
	print("      [--pack=liquipedia] [--no-players] [--dry]")
	print("")
	print("  --contact      identifie vos requêtes auprès de Liquipedia (obligatoire)")
	print("  --season       année du circuit (défaut 2026)")
	print("  --stage        page de ligue à lire : Kickoff, Stage 1, Stage 2…")
	print("  --pack         dossier créé sous user://packs/ (défaut liquipedia)")
	print("  --no-players   n'importe que les structures, pas les joueurs")
	print("  --no-sections  n'interroge pas les autres wikis (une requête par jeu)")
	print("  --sections-only  ne rafraîchit que les disciplines d'un pack existant")
	print("  --dry          n'écrit rien, montre ce qui serait importé")
	print("")
	quit(1)


func _run() -> void:
	# On lit toujours le contenu LIVRÉ, jamais un pack déjà installé : sinon un
	# second import se construirait sur le résultat du premier.
	DataPack.set_active("")
	print("")
	if _sections_only:
		await _run_sections_only()
		return
	print("Import Liquipedia — VCT %s, %s" % [_season, _stage])
	print("Contact déclaré : %s" % _contact)
	print("Débit limité à une requête toutes les %d s, comme l'exige l'API."
		% int(RATE_LIMIT_SEC))
	print("")

	var leagues := {}
	var rosters := {}
	var all_players: Array[String] = []

	for league_v in LEAGUES:
		var league: Dictionary = league_v
		var title := "VCT/%s/%s/%s" % [_season, str(league["page"]), _stage]
		var text := await _page_text(title)
		if text == "":
			print("  %-14s page introuvable (%s)" % [str(league["key"]), title])
			continue
		var teams := _parse_participants(text)
		if teams.is_empty():
			print("  %-14s aucune équipe trouvée — la page a peut-être changé "
				% str(league["key"]) + "de structure.")
			continue

		var entries: Array = []
		for team_v in teams:
			var team: Dictionary = team_v
			entries.append({
				"name": str(team["name"]),
				"tag": _tag_from_name(str(team["name"])),
				"country": _default_country(str(league["region"])),
				# Le niveau n'est pas une donnée publique : valeur de palier,
				# à ajuster à la main dans le pack si le cœur vous en dit.
				"strength": 80,
				"owner": "investor",
				"color": _color_from(str(team["name"])),
			})
			if _with_players and not (team["players"] as Array).is_empty():
				rosters[str(team["name"])] = {"players": team["players"]}
				for p_v in team["players"]:
					all_players.append(str((p_v as Dictionary)["tag"]))
		leagues[str(league["key"])] = entries
		print("  %-14s %2d équipes, %3d joueurs"
			% [str(league["key"]), entries.size(), _count_players(teams)])

	if leagues.is_empty():
		print("\nAucune équipe importée : le pack n'a pas été écrit.")
		print("Vérifiez --season et --stage : les pages sont nommées")
		print("  VCT/<saison>/<Région> League/<Stage>")
		quit(1)
		return

	# Les pages d'équipe donnent le vrai pays de la structure ; la page de
	# tournoi ne le dit pas. Un seul lot de requêtes pour toutes les équipes.
	var team_names: Array[String] = []
	for key in leagues:
		for e in leagues[key]:
			team_names.append(str((e as Dictionary)["name"]))
	if not team_names.is_empty():
		print("\nFiches structures : %d à lire…" % team_names.size())
		var infos := await _team_details(team_names)
		_merge_team_details(leagues, infos)
		print("  %d fiches complétées (pays, sigle)." % infos.size())

	# Les autres disciplines de la maison. Une structure esport est rarement
	# mono-jeu, et le jeu affiche ces sections même s'il ne les simule pas.
	if _with_sections and not team_names.is_empty():
		print("\nSections par discipline : %d portails à lire (une à deux "
			% SECTION_WIKIS.size() + "requêtes chacun)…")
		var sections := await _fetch_sections(team_names)
		_merge_sections(leagues, sections)

	if _with_players and not all_players.is_empty():
		print("\nFiches joueurs : %d à lire, par lots de %d…"
			% [all_players.size(), BATCH])
		var details := await _player_details(all_players)
		_merge_details(rosters, details)
		print("  %d fiches complétées (nom, pays, date de naissance)."
			% details.size())
		var complete := 0
		for team_name in rosters:
			if ((rosters[team_name] as Dictionary)["players"] as Array).size() >= 5:
				complete += 1
		print("  %d équipes sur %d ont un effectif complet."
			% [complete, team_names.size()])
		print("  Les autres utilisent {{ActiveSquadAuto}} sur Liquipedia : leur")
		print("  effectif n'est pas dans le wikitexte, le jeu générera donc des")
		print("  joueurs pour elles.")

	# Un pack REMPLACE le fichier qu'il fournit, il ne s'y ajoute pas. Si on
	# n'écrivait que les quatre ligues VCT, les Challengers disparaîtraient du
	# monde et avec eux toute la pyramide compétitive. On repart donc du
	# contenu livré et on n'y remplace que les ligues importées.
	var orgs := _merge_with_shipped(leagues)
	if _dry:
		print("\n--dry : rien n'écrit. Aperçu des structures :")
		print(JSON.stringify(orgs, "  ").substr(0, 1200))
		if not rosters.is_empty():
			print("\nAperçu des effectifs :")
			print(JSON.stringify(rosters, "  ").substr(0, 1200))
		quit(0)
		return

	_write_pack(orgs, rosters, _imported_teams(leagues))
	quit(0)


## Reprend orgs.json tel qu'il est livré et n'y remplace que les ligues
## effectivement importées. Les Challengers, l'Ascension et tout ce qui n'a pas
## d'équivalent sur Liquipedia restent donc en place.
func _merge_with_shipped(leagues: Dictionary) -> Dictionary:
	var base = DataFile.load_json("res://data/world/orgs.json", {})
	var merged: Dictionary = (base as Dictionary).duplicate(true) \
		if base is Dictionary else {}
	var shipped: Dictionary = merged.get("leagues", {})
	for key in leagues:
		shipped[key] = leagues[key]
	merged["leagues"] = shipped
	merged["_comment"] = "Pack généré depuis Liquipedia (CC-BY-SA 3.0). Les " \
		+ "ligues VCT sont réelles ; les Challengers restent fictifs, faute " \
		+ "de source équivalente. Marques appartenant à leurs détenteurs."
	return merged


func _imported_teams(leagues: Dictionary) -> int:
	var n := 0
	for key in leagues:
		n += (leagues[key] as Array).size()
	return n


func _count_players(teams: Array) -> int:
	var n := 0
	for t in teams:
		n += ((t as Dictionary)["players"] as Array).size()
	return n


# ============================================================================
# Lecture des pages
# ============================================================================

func _page_text(title: String) -> String:
	var data := await _api_get({
		"action": "query", "prop": "revisions", "rvprop": "content",
		"rvslots": "main", "titles": title, "format": "json",
	})
	var pages = (data.get("query", {}) as Dictionary).get("pages", {})
	for pid in pages:
		if int(str(pid)) < 0:
			continue      # -1 = page inexistante
		return _content_of(pages[pid])
	return ""


func _content_of(page: Dictionary) -> String:
	var revisions = page.get("revisions", [])
	if not (revisions is Array) or (revisions as Array).is_empty():
		return ""
	var rev: Dictionary = (revisions as Array)[0]
	var slots = rev.get("slots", {})
	if slots is Dictionary and (slots as Dictionary).has("main"):
		return str(((slots as Dictionary)["main"] as Dictionary).get("*", ""))
	return str(rev.get("*", ""))


## Une requête sur le wiki Valorant, en respectant le débit imposé.
func _api_get(params: Dictionary) -> Dictionary:
	return await _api_get_on("valorant", params)


## Même chose sur un autre wiki Liquipedia (voir SECTION_WIKIS). Le débit est
## volontairement partagé entre tous les wikis : ils sont hébergés ensemble.
func _api_get_on(wiki: String, params: Dictionary) -> Dictionary:
	await _throttle()
	var query: Array[String] = []
	for k in params:
		query.append("%s=%s" % [str(k), str(params[k]).uri_encode()])
	var url := "%s?%s" % [API_BASE % wiki, "&".join(query)]
	var headers := PackedStringArray([
		"User-Agent: EsportManager-Importer/1.0 (%s)" % _contact,
		"Accept-Encoding: gzip",
	])
	if _http.request(url, headers) != OK:
		print("  ! requête impossible")
		return {}
	var result: Array = await _http.request_completed
	var code := int(result[1])
	if code == 429:
		print("  ! Liquipedia demande de ralentir (429) — pause de 60 s.")
		await _sleep(60.0)
		return await _api_get_on(wiki, params)
	if code == 406:
		print("  ! HTTP 406 : User-Agent refusé. Vérifiez --contact.")
		return {}
	if code != 200:
		print("  ! HTTP %d" % code)
		return {}
	var json := JSON.new()
	if json.parse((result[3] as PackedByteArray).get_string_from_utf8()) != OK:
		print("  ! réponse illisible")
		return {}
	return json.data if json.data is Dictionary else {}


func _throttle() -> void:
	var elapsed := float(Time.get_ticks_msec() - _last_call_msec) / 1000.0
	if _last_call_msec > 0 and elapsed < RATE_LIMIT_SEC:
		var wait := RATE_LIMIT_SEC - elapsed
		print("    (attente %.0f s — débit imposé par l'API)" % wait)
		await _sleep(wait)
	_last_call_msec = Time.get_ticks_msec()
	_requests += 1


func _sleep(seconds: float) -> void:
	await create_timer(seconds).timeout


# ============================================================================
# Extraction des participants
# ============================================================================

## Lit la section « Participants » d'une page de tournoi.
##
## Le wikitexte y est de la forme :
##   {{TeamParticipants|
##     |{{Opponent|Fnatic|qualification=…
##       |players={{Persons
##         |{{Person|Boaster|role=Captain}}
##         |{{Person|Milan|role=Head Coach|type=staff}}
##   }}}}
##
## On découpe sur `{{Opponent|` plutôt que d'équilibrer les accolades : c'est
## suffisant, et surtout ça ne casse pas quand le wiki ajoute un paramètre.
func _parse_participants(text: String) -> Array:
	var start := text.find("==Participants==")
	if start < 0:
		return []
	var end := text.find("\n==", start + 4)
	var section := text.substr(start, (end - start) if end > start else -1)

	var out: Array = []
	var chunks := section.split("{{Opponent|", false)
	for i in chunks.size():
		if i == 0 and not section.begins_with("{{Opponent|"):
			continue      # préambule de section
		var chunk := chunks[i]
		var name := _first_token(chunk)
		if name == "" or name.begins_with("points="):
			continue
		out.append({"name": name, "players": _parse_persons(chunk)})
	return out


## Nom d'équipe : ce qui précède le premier `|` ou `}}`.
func _first_token(chunk: String) -> String:
	var cut := chunk.length()
	for marker in ["|", "}}", "\n"]:
		var idx := chunk.find(marker)
		if idx >= 0:
			cut = mini(cut, idx)
	return chunk.substr(0, cut).strip_edges()


func _parse_persons(chunk: String) -> Array:
	var out: Array = []
	var seen := {}
	var re := RegEx.new()
	re.compile("\\{\\{Person\\|([^|}]+)((?:\\|[^|}]*)*)\\}\\}")
	for m in re.search_all(chunk):
		var tag := m.get_string(1).strip_edges()
		var params := m.get_string(2).to_lower()
		if tag == "" or seen.has(tag):
			continue
		# Le staff et les anciens joueurs ne font pas partie de l'effectif.
		if params.contains("type=staff") or params.contains("status=former"):
			continue
		seen[tag] = true
		out.append({
			"tag": tag,
			"igl": _is_captain(params),
			"sub": params.contains("status=sub"),
		})
	return out


func _is_captain(params: String) -> bool:
	for role in CAPTAIN_ROLES:
		if params.contains("role=" + role):
			return true
	return false


# ============================================================================
# Fiches joueurs
# ============================================================================

## Nom réel, pays et date de naissance, par lots de 50 titres.
func _player_details(tags: Array[String]) -> Dictionary:
	var out := {}
	var index := 0
	while index < tags.size():
		var slice := tags.slice(index, mini(index + BATCH, tags.size()))
		index += BATCH
		var data := await _api_get({
			"action": "query", "prop": "revisions", "rvprop": "content",
			"rvslots": "main", "titles": "|".join(slice), "format": "json",
		})
		var pages = (data.get("query", {}) as Dictionary).get("pages", {})
		for pid in pages:
			var page: Dictionary = pages[pid]
			var title := str(page.get("title", ""))
			var text := _content_of(page)
			if text == "":
				continue
			var detail := _parse_player(text)
			if not detail.is_empty():
				# MediaWiki met la première lettre d'un titre en majuscule :
				# la page de « crashies » s'appelle « Crashies ». On indexe donc
				# en minuscules, sinon la moitié des joueurs ne se retrouve pas.
				out[title.to_lower()] = detail
	return out


## Pays et sigle des structures, lus dans l'infobox de leur page.
func _team_details(names: Array[String]) -> Dictionary:
	var out := {}
	var index := 0
	while index < names.size():
		var slice := names.slice(index, mini(index + BATCH, names.size()))
		index += BATCH
		var data := await _api_get({
			"action": "query", "prop": "revisions", "rvprop": "content",
			"rvslots": "main", "titles": "|".join(slice), "format": "json",
		})
		var pages = (data.get("query", {}) as Dictionary).get("pages", {})
		for pid in pages:
			var page: Dictionary = pages[pid]
			var text := _content_of(page)
			if text == "":
				continue
			var country := _country_code(_field(text, ["location", "country"]))
			var abbr := _field(text, ["abbreviation", "shortname"])
			if country == "" and abbr == "":
				continue
			out[str(page.get("title", "")).to_lower()] = {
				"country": country, "tag": abbr}
	return out


func _merge_team_details(leagues: Dictionary, infos: Dictionary) -> void:
	for key in leagues:
		for e_v in leagues[key]:
			var e: Dictionary = e_v
			var info = infos.get(str(e["name"]).to_lower(), null)
			if info == null:
				continue
			var d: Dictionary = info
			if str(d.get("country", "")) != "":
				e["country"] = str(d["country"])
			if str(d.get("tag", "")) != "":
				e["tag"] = str(d["tag"]).to_upper().substr(0, 4)


## Nom civil, pays, date de naissance et éventuel rôle d'IGL.
##
## Trois écritures cohabitent sur le wiki selon l'alphabet du joueur :
##   |givenname= / |familyname=   découpage explicite
##   |romanized_name=             translittération (le |name= est alors en
##                                cyrillique, en coréen ou en chinois)
##   |name=                       nom latin direct, cas le plus fréquent
## Il faut les trois : ne lire que les deux premières laissait sans nom civil
## tous les joueurs anglophones, c'est-à-dire la majorité.
func _parse_player(text: String) -> Dictionary:
	var given := _field(text, ["givenname"])
	var family := _field(text, ["familyname"])
	if given == "":
		var full := _field(text, ["romanized_name"])
		if full == "":
			full = _field(text, ["name"])
		var parts := full.split(" ", false)
		if parts.size() >= 2:
			given = parts[0]
			family = " ".join(Array(parts).slice(1))
		elif full != "":
			given = full
	var country := _country_code(_field(text, ["country", "nationality"]))
	var born := _field(text, ["birth_date"])
	# « |roles=igl » est renseigné sur certaines fiches et complète ce que la
	# page de tournoi indique via role=Captain.
	var igl := _field(text, ["roles"]).to_lower().contains("igl")
	if given == "" and country == "" and born == "":
		return {}
	return {"first": given, "last": family, "country": country, "born": born,
		"igl": igl}


## Cherche « | champ = valeur » dans le wikitexte, premier champ trouvé.
func _field(text: String, keys: Array) -> String:
	for key in keys:
		var re := RegEx.new()
		re.compile("(?im)^\\s*\\|\\s*%s\\s*=\\s*(.+)$" % str(key))
		var m := re.search(text)
		if m == null:
			continue
		var value := m.get_string(1).strip_edges()
		value = value.replace("[[", "").replace("]]", "").replace("'''", "")
		for marker in ["|", "{{", "<"]:
			var idx := value.find(marker)
			if idx >= 0:
				value = value.substr(0, idx)
		value = value.strip_edges()
		if value != "":
			return value
	return ""


func _merge_details(rosters: Dictionary, details: Dictionary) -> void:
	for team_name in rosters:
		var team: Dictionary = rosters[team_name]
		for p_v in team["players"]:
			var p: Dictionary = p_v
			var d = details.get(str(p["tag"]).to_lower(), null)
			if d == null:
				continue
			var detail: Dictionary = d
			p["first"] = str(detail.get("first", ""))
			p["last"] = str(detail.get("last", ""))
			p["country"] = str(detail.get("country", ""))
			p["born"] = str(detail.get("born", ""))
			# La page de tournoi fait foi pour le capitaine ; la fiche joueur
			# ne fait que compléter quand elle n'a rien dit.
			if bool(detail.get("igl", false)):
				p["igl"] = true


# ============================================================================
# Petites conversions
# ============================================================================

const COUNTRY_CODES := {
	"united states": "US", "usa": "US", "canada": "CA", "brazil": "BR",
	"argentina": "AR", "chile": "CL", "mexico": "MX", "colombia": "CO",
	"peru": "PE", "uruguay": "UY", "venezuela": "VE",
	"france": "FR", "germany": "DE", "spain": "ES", "portugal": "PT",
	"united kingdom": "GB", "england": "GB", "scotland": "GB",
	"sweden": "SE", "denmark": "DK", "norway": "NO", "finland": "FI",
	"poland": "PL", "russia": "RU", "turkey": "TR", "italy": "IT",
	"netherlands": "NL", "belgium": "BE", "ukraine": "UA", "serbia": "RS",
	"greece": "GR", "czech republic": "CZ", "austria": "AT",
	"switzerland": "CH", "israel": "IL", "morocco": "MA", "tunisia": "TN",
	"latvia": "LV", "estonia": "EE", "lithuania": "LT", "bulgaria": "BG",
	"romania": "RO", "hungary": "HU", "croatia": "HR", "slovenia": "SI",
	"south korea": "KR", "korea": "KR", "japan": "JP", "china": "CN",
	"singapore": "SG", "thailand": "TH", "indonesia": "ID", "taiwan": "TW",
	"philippines": "PH", "vietnam": "VN", "malaysia": "MY", "india": "IN",
	"hong kong": "HK", "australia": "AU", "new zealand": "NZ",
}

## Pays par défaut d'une région, quand la fiche ne dit rien.
const REGION_DEFAULT := {
	"EMEA": "FR", "AMERICAS": "US", "PACIFIC": "KR", "CHINA": "CN",
}


func _country_code(raw: String) -> String:
	var key := raw.to_lower().strip_edges()
	if COUNTRY_CODES.has(key):
		return COUNTRY_CODES[key]
	if key.length() == 2:
		return key.to_upper()
	return ""


func _default_country(region: String) -> String:
	return str(REGION_DEFAULT.get(region, "US"))


## Sigle de repli : initiales, ou trois premières lettres d'un nom d'un mot.
func _tag_from_name(name: String) -> String:
	var parts := name.split(" ", false)
	if parts.size() >= 2:
		var out := ""
		for p in parts:
			out += p.substr(0, 1)
		return out.to_upper().substr(0, 4)
	return name.to_upper().substr(0, 3)


## Couleur stable dérivée du nom : deux équipes n'ont jamais la même teinte,
## et elle ne bouge pas d'un import à l'autre.
func _color_from(name: String) -> String:
	var h := 0
	for i in name.length():
		h = (h * 31 + name.unicode_at(i)) % 100000
	return "#" + Color.from_hsv(float(h % 360) / 360.0, 0.62, 0.78).to_html(false)


# ============================================================================
# Sections : quelles disciplines la structure aligne-t-elle vraiment ?
# ============================================================================

## Wikis Liquipedia interrogés pour savoir si une structure a une section
## ACTIVE sur une autre discipline. Ajouter une ligne suffit à couvrir un jeu
## de plus ; l'identifiant de gauche doit exister dans GameCatalog.
const SECTION_WIKIS := [
	{"game": "cs2", "wiki": "counterstrike", "label": "Counter-Strike"},
	{"game": "lol", "wiki": "leagueoflegends", "label": "League of Legends"},
	{"game": "rl", "wiki": "rocketleague", "label": "Rocket League"},
	{"game": "apex", "wiki": "apexlegends", "label": "Apex Legends"},
	{"game": "r6", "wiki": "rainbowsix", "label": "Rainbow Six"},
	{"game": "dota2", "wiki": "dota2", "label": "Dota 2"},
	{"game": "ow2", "wiki": "overwatch", "label": "Overwatch"},
]


## Rafraîchit UNIQUEMENT les disciplines déclarées d'un pack déjà importé.
##
## Sept requêtes au lieu d'une quinzaine, et surtout : les effectifs déjà
## récupérés ne sont pas retouchés. C'est le mode à utiliser quand on veut
## corriger les sections sans risquer de perdre un import qui marche.
##
## Seules les structures qui déclarent DÉJÀ un champ `games` sont mises à jour.
## C'est ce qui distingue les structures réelles (dont la liste doit venir de
## Liquipedia) des structures fictives (dont le jeu tire lui-même une liste
## plausible) : y toucher réduirait toutes les équipes inventées à Valorant.
func _run_sections_only() -> void:
	var source := "%s/world/orgs.json" % DataPack.root_of(_pack)
	var data := _read_json(source)
	if data.is_empty():
		print("Pack « %s » introuvable ou illisible : %s" % [_pack, source])
		quit(1)
		return
	var leagues: Dictionary = data.get("leagues", {})

	var names: Array[String] = []
	for key in leagues:
		for e_v in leagues[key]:
			var e: Dictionary = e_v
			if e.has("games"):
				names.append(str(e["name"]))
	if names.is_empty():
		print("Aucune structure ne déclare de disciplines dans ce pack :")
		print("rien à rafraîchir. Lancez un import complet.")
		quit(1)
		return

	print("Sections par discipline — pack « %s »" % _pack)
	print("Contact déclaré : %s" % _contact)
	print("%d structures concernées, %d disciplines à interroger (une à deux "
		% [names.size(), SECTION_WIKIS.size()]
		+ "requêtes chacune), une requête toutes les %d s."
		% int(RATE_LIMIT_SEC))
	print("")

	var sections := await _fetch_sections(names)
	var changed := 0
	for key in leagues:
		for e_v in leagues[key]:
			var e: Dictionary = e_v
			if not e.has("games"):
				continue
			var found: Array = sections.get(str(e["name"]), ["valorant"])
			if found != e["games"]:
				changed += 1
			e["games"] = found

	if _dry:
		print("\n--dry : rien écrit. %d structures auraient changé." % changed)
		quit(0)
		return

	var target := "%s/world/orgs.json" % DataPack.user_root_of(_pack)
	DirAccess.make_dir_recursive_absolute(DataPack.user_root_of(_pack) + "/world")
	# Le manifeste doit accompagner le fichier, sinon le pack n'est pas
	# découvert dans user:// et la version livrée continue de gagner.
	var manifest_src := "%s/%s" % [DataPack.root_of(_pack), DataPack.MANIFEST]
	var manifest := _read_json(manifest_src)
	if not manifest.is_empty():
		manifest.erase("id")
		manifest.erase("files")
		manifest.erase("bundled")
		DataFile.save_json("%s/%s"
			% [DataPack.user_root_of(_pack), DataPack.MANIFEST], manifest)
	DataFile.save_json(target, data)
	print("")
	print("%d structures mises à jour, %d requêtes API." % [changed, _requests])
	print("Écrit dans %s" % ProjectSettings.globalize_path(target))
	quit(0)


## Lecture brute d'un JSON, hors du cache et de la chaîne de résolution des
## packs : ici on veut CE fichier-là, pas celui que le pack actif choisirait.
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var json := JSON.new()
	var ok := json.parse(f.get_as_text()) == OK
	f.close()
	return json.data if ok and json.data is Dictionary else {}


## Complète chaque structure avec la liste de ses disciplines.
##
## POURQUOI CE DÉTOUR PLUTÔT QU'UNE VÉRIFICATION D'EXISTENCE DE PAGE
## « La page Cloud9 existe sur le wiki Counter-Strike » ne veut rien dire : les
## pages des sections dissoutes restent en ligne, et la catégorie
## « Disbanded Teams » ne concerne que les structures entièrement fermées. En
## revanche chaque wiki maintient un Portal:Teams qui isole les équipes
## actives dans des sections à part — voir _active_sections.
func _fetch_sections(team_names: Array) -> Dictionary:
	var out := {}
	for name in team_names:
		out[str(name)] = ["valorant"]
	for entry_v in SECTION_WIKIS:
		var entry: Dictionary = entry_v
		var active := await _active_teams_of(str(entry["wiki"]))
		if active.is_empty():
			print("  %-18s portail illisible — discipline ignorée."
				% str(entry["label"]))
			continue
		var hits := 0
		for name in team_names:
			if _is_listed(active, str(name)):
				(out[str(name)] as Array).append(str(entry["game"]))
				hits += 1
		print("  %-18s %3d équipes actives, %2d de nos structures"
			% [str(entry["label"]), _listed_count(active), hits])
	return out


func _is_listed(active: Dictionary, name: String) -> bool:
	for key in _match_keys(name):
		if active.has(key):
			return true
	return false


## Le dictionnaire contient jusqu'à deux clés par équipe (nom du wiki et alias
## sans suffixe) : seules les clés principales comptent comme des équipes.
func _listed_count(active: Dictionary) -> int:
	var n := 0
	for key in active:
		if bool(active[key]):
			n += 1
	return n


## Page-portail lue sur chaque wiki. Elle existe partout sous ce nom.
const PORTAL := "Portal:Teams"

## Suffixes d'entreprise qu'un wiki met et qu'un autre omet : « Gen.G Esports »
## sur le wiki Valorant, « Gen.G » sur celui de League of Legends. On compare
## donc aussi les noms débarrassés de leur suffixe, des deux côtés.
const CORPORATE_SUFFIXES := [" esports club", " esports", " e-sports", " gaming"]


## Mots qui désignent une section d'équipes DISSOUTES. Tout ce qui suit la
## première d'entre elles est hors sujet.
const DEAD_SECTIONS := ["disbanded", "inactive", "former"]

## Sections à ignorer même quand elles précèdent les dissoutes : un classement
## par gains ou par statistiques mêle les équipes de toutes les époques.
const SKIP_SECTIONS := ["earnings", "statistic", "record"]


## Noms (en minuscules) des équipes déclarées ACTIVES sur un wiki.
##
## On lit la page RENDUE et pas son wikitexte : la plupart de ces portails
## assemblent leurs listes avec un modèle, et le wikitexte ne contient alors
## aucun nom d'équipe. Et on lit des SECTIONS et pas la page entière, parce
## qu'elle liste aussi les équipes dissoutes — sur le wiki Overwatch, 1189
## équipes au lieu de 428, et Fnatic hériterait d'une section qu'elle n'a plus.
func _active_teams_of(wiki: String) -> Dictionary:
	var out := {}
	for index in await _active_sections(wiki):
		var part := await _linked_teams(wiki, index)
		for key in part:
			# La clé principale l'emporte : une équipe vue comme alias dans une
			# section et sous son vrai nom dans une autre ne compte qu'une fois.
			if bool(part[key]) or not out.has(key):
				out[key] = bool(part[key]) or bool(out.get(key, false))
	return out


## Sections du portail contenant les équipes actives.
##
## Deux formes existent, et il faut les gérer toutes les deux :
##  - une section « Notable Active … Teams » unique (Counter-Strike, Rocket
##    League, Rainbow Six, Dota 2, Overwatch) : on ne lit que celle-là ;
##  - pas de section « active » du tout, l'actif étant réparti sur plusieurs
##    sections de premier niveau avant « Notable Disbanded … » (League of
##    Legends, Apex) : on lit tout ce qui précède.
func _active_sections(wiki: String) -> Array[int]:
	var data := await _api_get_on(wiki, {
		"action": "parse", "page": PORTAL, "prop": "sections", "format": "json",
	})
	var sections = (data.get("parse", {}) as Dictionary).get("sections", [])
	var out: Array[int] = []
	if not (sections is Array):
		return out

	for s_v in sections:
		var s: Dictionary = s_v
		var line := str(s.get("line", "")).to_lower()
		# « inactive » contient « active » : le test naïf prendrait exactement
		# la section qu'on cherche à éviter.
		if line.contains("active") and not _mentions(line, DEAD_SECTIONS):
			var idx := _section_index(s)
			if idx > 0:
				return [idx] as Array[int]

	for s_v in sections:
		var s: Dictionary = s_v
		if int(s.get("toclevel", 1)) != 1:
			continue
		var line := str(s.get("line", "")).to_lower()
		if _mentions(line, DEAD_SECTIONS):
			break
		if _mentions(line, SKIP_SECTIONS):
			continue
		var idx := _section_index(s)
		if idx > 0:
			out.append(idx)
	return out


func _mentions(line: String, words: Array) -> bool:
	for w in words:
		if line.contains(str(w)):
			return true
	return false


## Les sections transcluses ont un index de la forme « T-1 » : impossible de
## les redemander séparément, on les ignore.
func _section_index(s: Dictionary) -> int:
	var raw := str(s.get("index", ""))
	return int(raw) if raw.is_valid_int() else -1


## Liens d'une section de la page rendue. Espace principal et pages existantes
## seulement : le reste, ce sont des liens de navigation.
func _linked_teams(wiki: String, section: int) -> Dictionary:
	var data := await _api_get_on(wiki, {
		"action": "parse", "page": PORTAL, "section": section,
		"prop": "links", "format": "json",
	})
	var out := {}
	var links = (data.get("parse", {}) as Dictionary).get("links", [])
	if not (links is Array):
		return out
	for l_v in links:
		var l: Dictionary = l_v
		if int(l.get("ns", -1)) != 0 or not l.has("exists"):
			continue
		_index_team(out, str(l.get("*", "")))
	return out


## Indexe un nom sous sa forme brute ET sans suffixe d'entreprise. La première
## clé est la principale (elle compte pour une équipe), les suivantes sont des
## alias de comparaison.
func _index_team(out: Dictionary, name: String) -> void:
	var keys := _match_keys(name)
	for i in keys.size():
		if not out.has(keys[i]):
			out[keys[i]] = i == 0


func _match_keys(name: String) -> Array[String]:
	var base := name.to_lower().strip_edges()
	var out: Array[String] = []
	if base == "":
		return out
	out.append(base)
	for suffix in CORPORATE_SUFFIXES:
		if base.ends_with(suffix) and base.length() > suffix.length() + 2:
			out.append(base.substr(0, base.length() - suffix.length()).strip_edges())
			break
	return out


## Injecte les disciplines trouvées dans les entrées de structures.
func _merge_sections(leagues: Dictionary, sections: Dictionary) -> void:
	for key in leagues:
		for e_v in leagues[key]:
			var e: Dictionary = e_v
			var found = sections.get(str(e["name"]), ["valorant"])
			e["games"] = found

# ============================================================================
# Écriture du pack
# ============================================================================

func _write_pack(orgs: Dictionary, rosters: Dictionary, imported: int) -> void:
	var root_dir := DataPack.user_root_of(_pack)
	DirAccess.make_dir_recursive_absolute(root_dir + "/world")

	var teams := imported

	DataFile.save_json(root_dir + "/" + DataPack.MANIFEST, {
		"name": "VCT %s — équipes réelles" % _season,
		"author": "Import Liquipedia",
		"version": Time.get_date_string_from_system(),
		"description": "%d structures réelles du VCT %s et %d joueurs. "
			% [teams, _season, _roster_size(rosters)]
			+ "Les niveaux et les attributs restent générés par le jeu.",
		"source": "https://liquipedia.net/valorant",
		"license": "CC-BY-SA 3.0",
		"attribution": "Contenu issu de Liquipedia, sous licence CC-BY-SA 3.0. "
			+ "Noms et marques appartenant à leurs détenteurs.",
		"game": "valorant",
	})
	DataFile.save_json(root_dir + "/world/orgs.json", orgs)
	if not rosters.is_empty():
		DataFile.save_json(root_dir + "/world/rosters.json", {
			"_comment": "Effectifs réels. Le moteur reprend les identités et "
				+ "génère tout le reste : attributs, potentiel, contrats.",
			"teams": rosters,
		})

	print("")
	print("Pack écrit dans %s" % ProjectSettings.globalize_path(root_dir))
	print("  %d structures, %d joueurs, %d requêtes API."
		% [teams, _roster_size(rosters), _requests])
	print("")
	print("Pour jouer avec : lancez le jeu → Nouvelle partie → choisissez le")
	print("pack dans la liste avant de générer le monde.")
	print("")
	print("Rappel de licence : contenu CC-BY-SA 3.0 issu de Liquipedia ; les")
	print("noms d'équipes et de joueurs restent la propriété de leurs")
	print("détenteurs. Pack destiné à votre usage personnel — ne le")
	print("redistribuez pas comme s'il faisait partie du jeu.")


func _roster_size(rosters: Dictionary) -> int:
	var n := 0
	for k in rosters:
		n += ((rosters[k] as Dictionary)["players"] as Array).size()
	return n
