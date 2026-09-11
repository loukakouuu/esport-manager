class_name NegotiationTests
extends RefCounted

## Tests de la négociation de contrat.
##
## Ce qu'ils protègent n'est pas « ça ne plante pas » mais les quatre
## propriétés qui font que la négociation est un choix et pas un tirage :
##  - deux caractères différents ne veulent pas la même chose ;
##  - la clause de rachat oppose vraiment les deux camps ;
##  - une offre au rabais coûte de la patience, et la patience s'épuise ;
##  - une discussion converge au lieu de tourner en rond.

const T := Negotiation.Terms


static func run() -> Array[TestCase]:
	return [_opening(), _character(), _haggling(), _signature(), _persistence()]


## Monde partagé : la génération coûte cher, et aucun de ces tests n'avance le
## temps de la même façon — on repart d'un clone quand il le faut.
static var _cached: World = null


static func _world() -> World:
	if _cached == null:
		DataPack.set_active("")
		_cached = WorldGenerator.generate(9182, GameDate.from_ymd(2026, 1, 5))
		var picks := WorldGenerator.selectable_orgs(_cached, "chal_emea")
		WorldGenerator.assign_player_org(_cached, str(picks[0]["org_id"]))
	return World.from_dict(_cached.to_dict())


static func _rich_org(w: World) -> Organization:
	var o := w.my_org()
	# Les tests portent sur la discussion, pas sur la trésorerie : on écarte le
	# refus « caisse vide », qui a sa propre vérification plus bas.
	o.ledger.cash = Money.from_units(4_000_000.0)
	return o


static func _free_agent(w: World, min_ca: int = 0) -> Player:
	for p in w.free_agents("valorant"):
		if p.current_ability >= min_ca and p.age(w.today) >= 20:
			return p
	return null


# ============================================================================

static func _opening() -> TestCase:
	var t := TestCase.new("Négociation — ouverture")
	var w := _world()
	var o := _rich_org(w)
	var p := _free_agent(w, 90)
	if p == null:
		t.check(false, "un agent libre existe")
		return t

	var n := NegotiationSystem.open(w, o, p)
	t.check(n != null, "la discussion s'ouvre")
	t.check(n.is_live(), "elle est en cours")
	t.eq(n.rounds, 0, "aucun tour n'a encore eu lieu")
	t.eq(n.player_id, p.id, "elle porte sur le bon joueur")
	t.check(w.negotiations.has(n.id), "elle est enregistrée dans le monde")
	t.check(not n.log.is_empty(), "l'agent a dit quelque chose")

	for key in T.keys():
		t.check(n.demand.has(key), "la demande couvre la clause « %s »" % key)
		t.check(n.offer.has(key), "l'offre de départ aussi")

	# Rouvrir ne doit pas créer une seconde table pour le même joueur.
	var again := NegotiationSystem.open(w, o, p)
	t.eq(again.id, n.id, "rouvrir retrouve la discussion en cours")
	t.eq(w.negotiations.size(), 1, "et n'en crée pas une deuxième")

	# Un joueur déjà chez nous ne se recrute pas.
	t.check(NegotiationSystem.find_open(w, o.id, "inconnu") == null,
		"aucune discussion fantôme")
	return t


# ============================================================================

## Deux caractères opposés ne veulent pas le même contrat. Sans ça, tous les
## joueurs se négocient pareil et le système ne sert à rien.
static func _character() -> TestCase:
	var t := TestCase.new("Négociation — le caractère décide")
	var w := _world()
	var o := _rich_org(w)
	var a := _free_agent(w, 80)
	if a == null:
		t.check(false, "un agent libre existe")
		return t

	# Deux profils fabriqués à partir du même joueur : seul le caractère change.
	var ambitious := Player.from_dict(a.to_dict())
	ambitious.attributes[Attributes.AMBITION] = 19
	ambitious.attributes[Attributes.LOYALTY] = 5
	var loyal := Player.from_dict(a.to_dict())
	loyal.attributes[Attributes.AMBITION] = 5
	loyal.attributes[Attributes.LOYALTY] = 19

	var wa := NegotiationSystem.weights(ambitious)
	var wl := NegotiationSystem.weights(loyal)
	t.check(float(wa[T.ROLE]) > float(wl[T.ROLE]),
		"l'ambitieux tient davantage à son statut")
	t.check(float(wa[T.BUYOUT]) > float(wl[T.BUYOUT]),
		"et à pouvoir partir")
	t.check(float(wl[T.MONTHS]) > float(wa[T.MONTHS]),
		"le loyal tient davantage à la durée")

	var ta := NegotiationSystem.target_terms(w, ambitious, o)
	var tl := NegotiationSystem.target_terms(w, loyal, o)
	t.check(int(tl[T.MONTHS]) > int(ta[T.MONTHS]),
		"le loyal demande un contrat plus long")
	t.check(int(ta[T.BUYOUT]) < int(tl[T.BUYOUT]),
		"l'ambitieux veut une clause de rachat plus basse")
	t.eq(int(ta[T.ROLE]), Contract.SquadRole.STARTER,
		"l'ambitieux veut être titulaire")

	# Le même contrat de remplaçant ne vaut pas la même chose pour les deux.
	var bench := NegotiationSystem.target_terms(w, a, o).duplicate()
	bench[T.ROLE] = Contract.SquadRole.SUBSTITUTE
	var sat_a := NegotiationSystem.satisfaction(w, ambitious, o, bench)
	var sat_l := NegotiationSystem.satisfaction(w, loyal, o, bench)
	t.check(sat_a < sat_l,
		"un poste de remplaçant froisse surtout l'ambitieux")

	# La clause de rachat oppose bien les deux camps : plus elle monte, moins
	# le joueur est content — c'est ce qui en fait un arbitrage.
	var low := NegotiationSystem.target_terms(w, a, o).duplicate()
	var high := low.duplicate()
	high[T.BUYOUT] = int(low[T.BUYOUT]) * 4
	t.check(NegotiationSystem.satisfaction(w, a, o, high)
			< NegotiationSystem.satisfaction(w, a, o, low),
		"une clause de rachat élevée dégrade la satisfaction")

	# Et le salaire reste le levier principal.
	var poor := NegotiationSystem.target_terms(w, a, o).duplicate()
	poor[T.SALARY] = Money.pct(int(poor[T.SALARY]), 55.0)
	t.check(NegotiationSystem.satisfaction(w, a, o, poor) < -0.1,
		"un salaire à moitié prix ne passe pas")
	return t


# ============================================================================

static func _haggling() -> TestCase:
	var t := TestCase.new("Négociation — marchandage et patience")
	var w := _world()
	var o := _rich_org(w)
	var p := _free_agent(w, 80)
	if p == null:
		t.check(false, "un agent libre existe")
		return t

	# Une offre dérisoire, répétée, fait partir l'agent.
	var n := NegotiationSystem.open(w, o, p)
	var mood_start := n.mood
	var insulting := n.demand.duplicate()
	insulting[T.SALARY] = Money.pct(int(insulting[T.SALARY]), 30.0)
	insulting[T.BONUS] = 0
	insulting[T.ROLE] = Contract.SquadRole.ACADEMY
	insulting[T.BUYOUT] = int(insulting[T.BUYOUT]) * 6

	var first := NegotiationSystem.submit(w, n, insulting)
	t.check(int(first["status"]) != Negotiation.Status.ACCEPTED,
		"une offre dérisoire n'est pas acceptée")
	t.check(n.mood < mood_start - 20.0,
		"et coûte beaucoup de patience")

	var walked := false
	for _i in 6:
		if not n.is_live():
			walked = true
			break
		NegotiationSystem.submit(w, n, insulting)
	t.check(walked or n.status == Negotiation.Status.REFUSED,
		"à force, l'agent claque la porte")
	t.eq(int(n.status), Negotiation.Status.REFUSED,
		"et la discussion est refusée, pas seulement close")
	t.check(p.org_id != o.id, "le joueur n'a évidemment pas signé")

	# Une discussion close n'accepte plus rien.
	var after := NegotiationSystem.submit(w, n, n.demand)
	t.eq(int(after["status"]), Negotiation.Status.REFUSED,
		"soumettre une offre après la rupture ne relance rien")

	# La contre-proposition CONVERGE : sans cela on tournerait indéfiniment.
	var w2 := _world()
	var o2 := _rich_org(w2)
	var p2 := _free_agent(w2, 80)
	var n2 := NegotiationSystem.open(w2, o2, p2)
	var stingy := n2.demand.duplicate()
	stingy[T.SALARY] = Money.pct(int(stingy[T.SALARY]), 80.0)
	var before := int(n2.demand[T.SALARY])
	NegotiationSystem.submit(w2, n2, stingy)
	if n2.is_live():
		var after_round := int(n2.demand[T.SALARY])
		t.check(after_round < before,
			"l'agent baisse sa demande d'un tour à l'autre")
		t.check(after_round >= int(stingy[T.SALARY]),
			"sans jamais descendre sous l'offre reçue")
	return t


# ============================================================================

static func _signature() -> TestCase:
	var t := TestCase.new("Négociation — signature et trésorerie")
	var w := _world()
	var o := _rich_org(w)
	var p := _free_agent(w, 80)
	if p == null:
		t.check(false, "un agent libre existe")
		return t
	var roster := w.my_roster()
	var squad_before := roster.size()
	var cash_before := o.cash()

	var n := NegotiationSystem.open(w, o, p)
	var generous := n.demand.duplicate()
	generous[T.SALARY] = Money.pct(int(generous[T.SALARY]), 145.0)
	generous[T.BONUS] = Money.pct(int(generous[T.BONUS]), 160.0)
	generous[T.ROLE] = Contract.SquadRole.STARTER
	generous[T.PRIZE] = float(generous[T.PRIZE]) + 6.0

	var signed := false
	for _i in 5:
		var out := NegotiationSystem.submit(w, n, generous)
		if int(out["status"]) == Negotiation.Status.ACCEPTED:
			signed = true
			break
	t.check(signed, "une offre nettement au-dessus finit par être acceptée")
	if not signed:
		return t

	t.eq(p.org_id, o.id, "le joueur appartient à la structure")
	t.check(p.contract != null, "il a un contrat")
	t.eq(p.contract.salary_yearly, int(generous[T.SALARY]),
		"au salaire négocié")
	t.eq(p.contract.buyout, int(generous[T.BUYOUT]),
		"avec la clause de rachat négociée")
	t.near(p.contract.prize_share_pct, float(generous[T.PRIZE]), 0.01,
		"et la part des gains négociée")
	t.eq(w.my_roster().size(), squad_before + 1, "il rejoint l'effectif")
	t.check(o.cash() < cash_before,
		"la prime et la commission d'agent sont débitées")
	t.eq(int(n.status), Negotiation.Status.ACCEPTED, "la discussion est close")

	# Caisse vide : l'accord ne peut pas se conclure, et rien ne bouge.
	var w2 := _world()
	var o2 := w2.my_org()
	o2.ledger.cash = Money.from_units(50.0)
	var p2 := _free_agent(w2, 80)
	var n2 := NegotiationSystem.open(w2, o2, p2)
	var rich_offer := n2.demand.duplicate()
	rich_offer[T.SALARY] = Money.pct(int(rich_offer[T.SALARY]), 150.0)
	rich_offer[T.BONUS] = Money.from_units(90_000.0)
	for _i in 4:
		NegotiationSystem.submit(w2, n2, rich_offer)
	t.check(p2.org_id != o2.id, "sans trésorerie, personne ne signe")
	t.check(n2.status != Negotiation.Status.ACCEPTED,
		"et la discussion n'est pas marquée conclue")
	return t


# ============================================================================

static func _persistence() -> TestCase:
	var t := TestCase.new("Négociation — durée de vie et sauvegarde")
	var w := _world()
	var o := _rich_org(w)
	var p := _free_agent(w, 80)
	if p == null:
		t.check(false, "un agent libre existe")
		return t

	var n := NegotiationSystem.open(w, o, p)
	var offer := n.demand.duplicate()
	offer[T.SALARY] = Money.pct(int(offer[T.SALARY]), 85.0)
	NegotiationSystem.submit(w, n, offer)

	# Une discussion se poursuit d'un jour à l'autre : elle doit survivre à une
	# sauvegarde, patience et fil de conversation compris.
	var back := World.from_dict(w.to_dict())
	t.check(back.negotiations.has(n.id), "la discussion est sauvegardée")
	var n2: Negotiation = back.negotiations[n.id]
	t.eq(n2.rounds, n.rounds, "le nombre de tours est conservé")
	t.near(n2.mood, n.mood, 0.01, "la patience aussi")
	t.eq(n2.log.size(), n.log.size(), "et le fil des échanges")
	t.eq(int(n2.offer[T.SALARY]), int(n.offer[T.SALARY]),
		"ainsi que la dernière offre")

	# Déterminisme : le même monde rejoué donne la même réponse. Recharger ne
	# doit pas permettre de retenter sa chance.
	var replay := World.from_dict(_snapshot(w, n))
	var n_replay: Negotiation = replay.negotiations[n.id]
	var a := NegotiationSystem.submit(w, n, offer)
	var b := NegotiationSystem.submit(replay, n_replay, offer)
	t.eq(int(a["status"]), int(b["status"]),
		"la même offre dans le même état donne le même verdict")
	t.near(n.mood, n_replay.mood, 0.01, "et la même patience restante")

	# Sans nouvelle proposition, la discussion s'éteint toute seule.
	var w3 := _world()
	var o3 := _rich_org(w3)
	var p3 := _free_agent(w3, 80)
	var n3 := NegotiationSystem.open(w3, o3, p3)
	w3.today += NegotiationSystem.STALE_DAYS + 2
	NegotiationSystem.weekly_tick(w3)
	t.eq(int(n3.status), Negotiation.Status.EXPIRED,
		"une discussion oubliée trois semaines s'éteint")
	t.check(not n3.is_live(), "et n'est plus reprenable")

	# Abandonner ferme proprement.
	var w4 := _world()
	var n4 := NegotiationSystem.open(w4, _rich_org(w4), _free_agent(w4, 80))
	NegotiationSystem.abandon(w4, n4)
	t.eq(int(n4.status), Negotiation.Status.EXPIRED, "l'abandon ferme la table")
	return t


## Copie du monde prise AVANT le coup qu'on veut rejouer.
static func _snapshot(w: World, n: Negotiation) -> Dictionary:
	var d := w.to_dict()
	# `to_dict` est déjà une copie profonde ; on la renvoie telle quelle.
	return d
