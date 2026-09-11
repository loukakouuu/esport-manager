class_name NegotiationSystem
extends RefCounted

## Négociation de contrat, clause par clause.
##
## POURQUOI CE SYSTÈME EXISTE
## Signer un joueur se résumait à un bouton qui acceptait ou refusait. C'est
## une pièce de monnaie, pas une décision : rien à arbitrer, rien à apprendre
## d'un échec. Or le marché est la moitié d'un jeu de gestion.
##
## CE QUI REND LA DISCUSSION INTÉRESSANTE
##  1. **Plusieurs leviers qui se compensent.** Un salaire court passe si la
##     prime est belle ; un rôle de remplaçant ne passe pas, quel que soit le
##     chèque, face à un ambitieux.
##  2. **Des goûts différents selon les caractères.** Le loyal veut un contrat
##     long, l'ambitieux le veut court et avec une clause de rachat basse pour
##     pouvoir partir. La même offre n'a donc pas la même valeur pour deux
##     joueurs de niveau égal.
##  3. **Une information imparfaite.** L'agent dit « c'est un peu court », pas
##     « il manque 8 400 $ ». On apprend en proposant.
##  4. **Une patience qui s'use.** Une offre au rabais coûte cher en capital
##     de sympathie ; au bout de quelques-unes, l'agent s'en va.
##
## La CLAUSE DE RACHAT est le levier le plus intéressant parce que les deux
## camps la veulent dans des directions opposées : la structure veut protéger
## son actif, le joueur veut pouvoir partir.
##
## Tout est déterministe : la graine du monde décide, recharger ne permet pas
## de retenter le même tirage.

const T := Negotiation.Terms

## En dessous de cette satisfaction, l'agent ne transmet même pas l'offre.
const ACCEPT_THRESHOLD := -0.04
## Patience perdue à chaque tour, avant pénalité de sous-enchère. Assez élevée
## pour qu'une discussion qui traîne finisse par échouer : sans ça, monter de
## 9 % à chaque refus signait n'importe qui à tous les coups.
const MOOD_BASE_COST := 12.0

## PRIX DE RÉSERVE. L'agent concède à chaque tour pour que la discussion
## converge, mais jamais en dessous de ces bornes — sinon les deux camps se
## rejoignent mécaniquement et toute offre finit par passer. C'est ce plancher
## qui rend un échec possible, donc une réussite intéressante.
const RESERVE_SALARY_PCT := 90.0
const RESERVE_BONUS_PCT := 70.0
const RESERVE_BUYOUT_MULT := 1.35
## Une discussion sans nouvelle offre pendant ce délai s'éteint d'elle-même.
const STALE_DAYS := 21


# ============================================================================
# Ouverture
# ============================================================================

## Ouvre une discussion, ou renvoie celle qui est déjà en cours.
static func open(world: World, org: Organization, p: Player) -> Negotiation:
	var existing := find_open(world, org.id, p.id)
	if existing != null:
		return existing

	var n := Negotiation.new()
	n.id = world.ids.next(Ids.NEGOTIATION)
	n.org_id = org.id
	n.player_id = p.id
	n.opened_day = world.today
	n.last_day = world.today
	n.demand = target_terms(world, p, org)
	# On part du point de vue de la STRUCTURE, pas de celui de l'agent : la
	# négociation commence donc par un écart à combler, ce qui est tout
	# l'intérêt. Partir de sa demande reviendrait à avoir déjà cédé.
	n.offer = opening_offer(world, p, org)
	n.say(world.today, "agent", _opening_line(world, p, org, n.demand))
	world.negotiations[n.id] = n
	return n


static func find_open(world: World, org_id: String, player_id: String) -> Negotiation:
	for nid in world.negotiations:
		var n: Negotiation = world.negotiations[nid]
		if n.org_id == org_id and n.player_id == player_id and n.is_live():
			return n
	return null


static func for_org(world: World, org_id: String) -> Array[Negotiation]:
	var out: Array[Negotiation] = []
	for nid in world.negotiations:
		var n: Negotiation = world.negotiations[nid]
		if n.org_id == org_id:
			out.append(n)
	out.sort_custom(func(a: Negotiation, b: Negotiation):
		return a.last_day > b.last_day)
	return out


# ============================================================================
# Ce que veut l'agent
# ============================================================================

## Poids de chaque clause pour CE joueur. C'est ici que deux joueurs de même
## niveau cessent d'être interchangeables.
static func weights(p: Player) -> Dictionary:
	var ambition := float(p.attr(Attributes.AMBITION)) / 20.0
	var loyalty := float(p.attr(Attributes.LOYALTY)) / 20.0
	var ego := float(p.attr(Attributes.EGO)) / 20.0
	var pro := float(p.attr(Attributes.PROFESSIONALISM)) / 20.0
	return {
		T.SALARY: 1.00 + ego * 0.80,
		T.BONUS: 0.25 + ego * 0.55 - pro * 0.20,
		T.MONTHS: 0.30 + loyalty * 0.70,
		T.ROLE: 0.45 + ambition * 1.00,
		T.BUYOUT: 0.20 + ambition * 0.75,
		T.PRIZE: 0.20 + ego * 0.40,
	}


## Les clauses que l'agent réclamerait s'il pouvait tout écrire lui-même.
static func target_terms(world: World, p: Player, org: Organization) -> Dictionary:
	var ambition := float(p.attr(Attributes.AMBITION)) / 20.0
	var loyalty := float(p.attr(Attributes.LOYALTY)) / 20.0
	var ego := float(p.attr(Attributes.EGO)) / 20.0
	var salary := ContractSystem.salary_demand(world, p, org)
	return {
		T.SALARY: salary,
		# Le loyal veut de la durée, l'ambitieux veut rester libre de partir.
		T.MONTHS: int(round(18.0 + loyalty * 18.0 - ambition * 8.0)),
		T.ROLE: Contract.SquadRole.STARTER if ambition > 0.45
			else Contract.SquadRole.SUBSTITUTE,
		T.BONUS: Money.pct(salary, 6.0 + ego * 18.0),
		# Le joueur veut une clause BASSE : c'est sa porte de sortie. La
		# structure, elle, la veut haute. C'est le seul point où les deux
		# camps tirent franchement dans des sens opposés.
		T.BUYOUT: int(float(p.market_value) * (1.6 - ambition * 0.7)),
		T.PRIZE: 10.0 + ego * 8.0,
	}


## Clauses de départ raisonnables pour la structure : le point de vue d'en
## face, proposé à l'écran comme brouillon.
## L'écart avec ce que réclame l'agent est VOULU : c'est lui qu'on négocie.
## Partir d'une offre presque acceptable rendrait la discussion décorative.
static func opening_offer(world: World, p: Player, org: Organization) -> Dictionary:
	var t := target_terms(world, p, org)
	return {
		T.SALARY: Money.pct(int(t[T.SALARY]), 72.0),
		T.MONTHS: clampi(int(t[T.MONTHS]), 12, 36),
		T.ROLE: t[T.ROLE],
		T.BONUS: Money.pct(int(t[T.BONUS]), 45.0),
		T.BUYOUT: int(float(p.market_value) * 2.0),
		T.PRIZE: 10.0,
	}


# ============================================================================
# Évaluation d'une offre
# ============================================================================

## Satisfaction de l'agent clause par clause, chacune dans [-1.2, +1].
##
## Un chiffre par clause plutôt qu'un score global : c'est ce qui permet à
## l'écran de dire OÙ ça coince sans révéler de combien.
static func clause_scores(world: World, p: Player, org: Organization,
		terms: Dictionary, demand: Dictionary = {}) -> Dictionary:
	var t := demand if not demand.is_empty() else target_terms(world, p, org)
	var ambition := float(p.attr(Attributes.AMBITION)) / 20.0
	var loyalty := float(p.attr(Attributes.LOYALTY)) / 20.0
	var out := {}

	var salary := float(terms.get(T.SALARY, 0))
	out[T.SALARY] = clampf((salary / maxf(float(t[T.SALARY]), 1.0) - 1.0) * 2.4,
		-1.2, 1.0)

	var bonus := float(terms.get(T.BONUS, 0))
	out[T.BONUS] = clampf((bonus / maxf(float(t[T.BONUS]), 1.0) - 1.0) * 1.1,
		-1.0, 1.0)

	# La durée n'est ni bonne ni mauvaise en soi : elle l'est par rapport à ce
	# que le joueur cherche. On mesure donc l'écart DANS SA DIRECTION.
	var months := float(terms.get(T.MONTHS, 0))
	var want_long := loyalty > ambition
	var gap := (months - float(t[T.MONTHS])) / 12.0
	out[T.MONTHS] = clampf((gap if want_long else -gap) * 0.9, -1.0, 0.7)

	out[T.ROLE] = _role_score(int(terms.get(T.ROLE, 0)), int(t[T.ROLE]), ambition)

	# Plus la clause est haute, plus le joueur est enfermé.
	var buyout := maxf(float(terms.get(T.BUYOUT, 0)), 1.0)
	out[T.BUYOUT] = clampf((float(t[T.BUYOUT]) / buyout - 1.0) * 1.3, -1.1, 0.6)

	var prize := float(terms.get(T.PRIZE, 0.0))
	out[T.PRIZE] = clampf((prize - float(t[T.PRIZE])) / 7.0, -1.0, 0.8)
	return out


static func _role_score(offered: int, wanted: int, ambition: float) -> float:
	if offered == wanted:
		return 0.35
	# Les rôles sont ordonnés du meilleur au pire dans Contract.SquadRole.
	if offered < wanted:
		return 0.8
	return clampf(-0.5 - float(offered - wanted) * 0.45 * (0.5 + ambition),
		-1.2, 0.0)


## Satisfaction globale, pondérée par le caractère. Dans [-1.2, +1] environ.
static func satisfaction(world: World, p: Player, org: Organization,
		terms: Dictionary, demand: Dictionary = {}) -> float:
	var scores := clause_scores(world, p, org, terms, demand)
	var w := weights(p)
	var total := 0.0
	var weight_sum := 0.0
	for key in scores:
		var weight := float(w.get(key, 0.5))
		total += float(scores[key]) * weight
		weight_sum += weight
	return total / maxf(weight_sum, 0.001)


## Probabilité que l'agent dise oui à ces clauses-là, aujourd'hui.
static func acceptance(world: World, p: Player, org: Organization,
		terms: Dictionary, demand: Dictionary = {}) -> float:
	var score := satisfaction(world, p, org, terms, demand) * 2.6 \
		+ ContractSystem.context_score(world, p, org)
	return clampf(Rng.logistic(score, 1.5), 0.02, 0.97)


# ============================================================================
# Un tour de table
# ============================================================================

## Le joueur soumet des clauses. L'agent accepte, contre-propose, ou s'en va.
##
## Renvoie {"status", "text"} — `status` reprenant Negotiation.Status.
static func submit(world: World, n: Negotiation, terms: Dictionary) -> Dictionary:
	var p := world.player(n.player_id)
	var org := world.org(n.org_id)
	if p == null or org == null or not n.is_live():
		return {"status": n.status, "text": "Cette discussion est close."}

	n.rounds += 1
	n.last_day = world.today
	n.offer = terms.duplicate()
	n.say(world.today, "org", _offer_line(terms))

	var sat := satisfaction(world, p, org, terms, n.demand)
	var rng := world.rng.derive("nego:%s:%d" % [n.id, n.rounds])

	if sat >= ACCEPT_THRESHOLD \
			and rng.chance(acceptance(world, p, org, terms, n.demand)):
		return _accept(world, n, p, org, terms)

	# Une offre au rabais coûte bien plus qu'un simple désaccord.
	n.mood -= MOOD_BASE_COST + maxf(-sat, 0.0) * 34.0
	if n.mood <= 0.0:
		n.status = Negotiation.Status.REFUSED
		var bye := "%s met fin à la discussion : « on tourne en rond. »" \
			% p.display_name()
		n.say(world.today, "agent", bye)
		return {"status": n.status, "text": bye}

	_concede(world, n, p, org, terms)
	n.status = Negotiation.Status.COUNTERED
	var reply := _counter_line(world, p, org, terms, n)
	n.say(world.today, "agent", reply)
	return {"status": n.status, "text": reply}


## Le joueur signe la contre-proposition telle quelle.
static func accept_demand(world: World, n: Negotiation) -> Dictionary:
	var p := world.player(n.player_id)
	var org := world.org(n.org_id)
	if p == null or org == null or not n.is_live():
		return {"status": n.status, "text": "Cette discussion est close."}
	n.offer = n.demand.duplicate()
	n.rounds += 1
	n.last_day = world.today
	return _accept(world, n, p, org, n.demand)


static func abandon(world: World, n: Negotiation) -> void:
	if not n.is_live():
		return
	n.status = Negotiation.Status.EXPIRED
	n.last_day = world.today
	n.say(world.today, "org", "Discussion interrompue.")


## Discussions laissées sans réponse : elles s'éteignent, et le joueur en est
## informé. Une négociation ouverte pour toujours fausserait le marché.
static func weekly_tick(world: World) -> void:
	for nid in world.negotiations.keys():
		var n: Negotiation = world.negotiations[nid]
		if n.is_live() and world.today - n.last_day > STALE_DAYS:
			n.status = Negotiation.Status.EXPIRED
			var p := world.player(n.player_id)
			if p != null and world.player_org_id == n.org_id:
				world.add_news(world.today,
					"Discussion close : %s" % p.display_name(),
					("Faute de nouvelle proposition depuis trois semaines, "
					+ "l'entourage de %s met fin aux discussions.")
						% p.long_name(), "contract", {"player_id": p.id})
		# Une discussion close depuis longtemps n'a plus à occuper la
		# sauvegarde ; le fil de la conversation non plus.
		elif not n.is_live() and world.today - n.last_day > 120:
			world.negotiations.erase(nid)


# ============================================================================
# Signature
# ============================================================================

static func _accept(world: World, n: Negotiation, p: Player,
		org: Organization, terms: Dictionary) -> Dictionary:
	var contract := ContractSystem.make_offer(world, org, p,
		int(terms[T.SALARY]), int(terms[T.MONTHS]),
		int(terms[T.ROLE]) as Contract.SquadRole,
		int(terms[T.BUYOUT]), int(terms[T.BONUS]))
	contract.prize_share_pct = float(terms[T.PRIZE])

	# On vérifie la caisse au dernier moment : c'est le seul instant où le
	# montant exact est connu, prime et commission d'agent comprises.
	var upfront := contract.upfront_cost()
	if org.ledger.cash < upfront:
		n.mood -= 10.0
		var broke := ("L'accord tombe à l'eau : %s ne peut pas verser %s "
			+ "à la signature.") % [org.name, Money.fmt(upfront)]
		n.say(world.today, "agent", broke)
		n.status = Negotiation.Status.COUNTERED
		return {"status": n.status, "text": broke}

	if p.is_free_agent():
		ContractSystem.sign_contract(world, org, p, contract,
			world.player_roster_id if org.id == world.player_org_id else "")
	elif not ContractSystem.buyout(world, org, p, contract):
		var no_fee := ("Impossible de payer la clause de rachat de %s."
			% p.display_name())
		n.say(world.today, "agent", no_fee)
		n.status = Negotiation.Status.COUNTERED
		return {"status": n.status, "text": no_fee}

	n.status = Negotiation.Status.ACCEPTED
	var yes := "%s signe : %s / an sur %d mois." \
		% [p.display_name(), Money.fmt(int(terms[T.SALARY])), int(terms[T.MONTHS])]
	n.say(world.today, "agent", yes)
	if world.player_org_id == org.id:
		world.add_news(world.today, "Signature : %s" % p.display_name(),
			"%s rejoint %s. %s" % [p.long_name(), org.name, yes], "transfer",
			{"player_id": p.id})
	return {"status": n.status, "text": yes}


# ============================================================================
# Concession et phrases
# ============================================================================

## L'agent rapproche sa demande de la dernière offre. Sans cela une
## négociation pourrait tourner indéfiniment ; avec, elle converge.
static func _concede(world: World, n: Negotiation, p: Player,
		org: Organization, terms: Dictionary) -> void:
	var step := clampf(0.10 + float(n.rounds) * 0.05, 0.10, 0.35)
	var t := target_terms(world, p, org)
	# En dessous (ou au-dessus, pour la clause) de ces bornes, il préfère
	# encore ne pas signer.
	var reserve := {
		T.SALARY: float(Money.pct(int(t[T.SALARY]), RESERVE_SALARY_PCT)),
		T.BONUS: float(Money.pct(int(t[T.BONUS]), RESERVE_BONUS_PCT)),
		T.BUYOUT: float(t[T.BUYOUT]) * RESERVE_BUYOUT_MULT,
	}
	for key in [T.SALARY, T.BONUS]:
		var want := float(n.demand.get(key, 0))
		var got := float(terms.get(key, 0))
		n.demand[key] = int(round(maxf(want + (got - want) * step,
			float(reserve[key]))))
	var want_buyout := float(n.demand.get(T.BUYOUT, 0))
	var got_buyout := float(terms.get(T.BUYOUT, 0))
	n.demand[T.BUYOUT] = int(round(minf(
		want_buyout + (got_buyout - want_buyout) * step,
		float(reserve[T.BUYOUT]))))

	for key in [T.MONTHS, T.PRIZE]:
		var want2 := float(n.demand.get(key, 0))
		var got2 := float(terms.get(key, 0))
		var moved: float = want2 + (got2 - want2) * step
		n.demand[key] = int(round(moved)) if key == T.MONTHS else moved
	# Le rôle ne se marchande pas au pourcentage : un ambitieux tient à son
	# statut de titulaire jusqu'au bout.
	var ambition := float(p.attr(Attributes.AMBITION)) / 20.0
	if ambition < 0.55 and n.rounds >= 3:
		n.demand[T.ROLE] = int(terms.get(T.ROLE, t[T.ROLE]))


static func _opening_line(world: World, p: Player, org: Organization,
		demand: Dictionary) -> String:
	var pieces: Array[String] = []
	pieces.append("%s vous écoute." % p.display_name())
	if p.is_free_agent():
		pieces.append("Il est libre de tout contrat.")
	else:
		var current := world.org(p.org_id)
		pieces.append("Il est sous contrat%s ; il faudra payer sa clause."
			% ("" if current == null else " à %s" % current.name))
	pieces.append("Son entourage part de %s par an sur %d mois."
		% [Money.fmt(int(demand[T.SALARY])), int(demand[T.MONTHS])])
	return " ".join(pieces)


static func _offer_line(terms: Dictionary) -> String:
	return "Offre : %s / an, %d mois, %s, prime %s, clause %s, %.0f %% des gains." \
		% [Money.fmt_short(int(terms[T.SALARY])), int(terms[T.MONTHS]),
			role_label(int(terms[T.ROLE])), Money.fmt_short(int(terms[T.BONUS])),
			Money.fmt_short(int(terms[T.BUYOUT])), float(terms[T.PRIZE])]


## La réponse de l'agent nomme le point qui bloque le plus, sans jamais donner
## le chiffre : c'est au joueur de trouver de combien.
static func _counter_line(world: World, p: Player, org: Organization,
		terms: Dictionary, n: Negotiation) -> String:
	var scores := clause_scores(world, p, org, terms, n.demand)
	var w := weights(p)
	var worst := ""
	var worst_value := 1.0
	for key in scores:
		var weighted := float(scores[key]) * float(w.get(key, 0.5))
		if weighted < worst_value:
			worst_value = weighted
			worst = str(key)

	var mood_word := "plutôt bien disposé"
	if n.mood < 25.0:
		mood_word = "clairement agacé"
	elif n.mood < 50.0:
		mood_word = "réservé"
	if worst == "" or worst_value > -0.05:
		return ("L'entourage de %s est %s : on n'est plus très loin, mais il "
			+ "attend un dernier geste.") % [p.display_name(), mood_word]
	return "%s Son agent est %s." % [_complaint(worst, p), mood_word]


static func _complaint(key: String, p: Player) -> String:
	match key:
		T.SALARY:
			return "Le salaire proposé est en dessous de ce qu'il vise."
		T.BONUS:
			return "Il attend un vrai geste à la signature, pas une prime symbolique."
		T.MONTHS:
			return ("La durée ne lui convient pas : il ne veut pas s'engager "
				+ "sur cette période-là.")
		T.ROLE:
			return ("Le statut proposé est un point de blocage — il ne vient "
				+ "pas pour s'asseoir sur le banc.")
		T.BUYOUT:
			return ("La clause de rachat est trop haute : il refuse d'être "
				+ "enfermé pour toute la durée du contrat.")
		T.PRIZE:
			return "Il trouve sa part des gains de tournoi trop faible."
	return "%s hésite." % p.display_name()


static func role_label(role: int) -> String:
	match role:
		Contract.SquadRole.STARTER:
			return "titulaire"
		Contract.SquadRole.SUBSTITUTE:
			return "remplaçant"
		Contract.SquadRole.ACADEMY:
			return "académie"
	return "hors effectif"


## Verdict lisible d'une clause, pour l'écran : -2 (bloquant) à +2 (généreux).
static func clause_verdict(score: float) -> Dictionary:
	if score >= 0.45:
		return {"level": 2, "text": "généreux"}
	if score >= 0.05:
		return {"level": 1, "text": "convenable"}
	if score >= -0.20:
		return {"level": 0, "text": "juste limite"}
	if score >= -0.60:
		return {"level": -1, "text": "insuffisant"}
	return {"level": -2, "text": "bloquant"}
