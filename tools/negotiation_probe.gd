extends SceneTree

## Sonde d'équilibrage de la négociation.
##
##   godot --headless --path . --script res://tools/negotiation_probe.gd
##
## Les tests disent que le système est correct ; ils ne disent pas s'il est
## JOUABLE. Cette sonde rejoue une stratégie de manager raisonnable — partir
## de l'offre d'ouverture, puis concéder un peu à chaque refus — sur beaucoup
## d'agents libres, et sort les trois chiffres qui décident si le marché est
## amusant ou pénible :
##
##   - le taux de signature : à 30 % le mode fondation est infranchissable,
##     à 100 % la négociation n'est qu'un clic déguisé ;
##   - le nombre de tours : moins de deux, il n'y a rien à apprendre ;
##     plus de six, c'est une corvée ;
##   - le surcoût payé par rapport à la première demande de l'agent : c'est
##     le prix de la maladresse, et il doit rester lisible.
##
## Le manager simulé ne triche pas : il ne voit pas la demande de l'agent, il
## avance à l'aveugle comme un joueur humain.

const T := Negotiation.Terms
const SAMPLE := 40
## Ce que le manager concède à chaque refus, en pourcentage de son offre.
const CONCESSION_PCT := 9.0
const MAX_ROUNDS := 8


func _initialize() -> void:
	DataPack.set_active("")
	print("\nSonde de négociation — %d agents libres" % SAMPLE)
	print("Deux stratégies, la même montée de salaire (+%.0f %% par refus, %d "
		% [CONCESSION_PCT, MAX_ROUNDS] + "tours max) :")
	print("  « brut »   ne touche qu'au salaire et à la prime ;")
	print("  « avisé »  lâche en plus ce qui ne coûte rien tout de suite —")
	print("             clause de rachat basse et part des gains décente.")
	print("")
	print("Si les deux obtiennent le même résultat, la négociation n'a pas de")
	print("profondeur : seul le portefeuille compterait.")
	for smart in [false, true]:
		_measure(smart)
	quit(0)


func _measure(smart: bool) -> void:
	print("\n--- stratégie %s ---" % ("avisée" if smart else "brute"))
	var world := WorldGenerator.generate(4242, GameDate.from_ymd(2026, 1, 5))
	var picks := WorldGenerator.selectable_orgs(world, "chal_emea")
	WorldGenerator.assign_player_org(world, str(picks[0]["org_id"]))
	var org := world.my_org()
	# La sonde mesure la NÉGOCIATION, pas la trésorerie : on écarte le refus
	# « caisse vide », qui a sa propre logique.
	org.ledger.cash = Money.from_units(50_000_000.0)

	var signed := 0
	var refused := 0
	var stalled := 0
	var rounds_total := 0
	var overpay_total := 0.0
	var by_ambition := {"posé": [0, 0], "ambitieux": [0, 0]}

	var agents := world.free_agents("valorant")
	agents.sort_custom(func(a: Player, b: Player):
		return a.current_ability > b.current_ability)

	for i in mini(SAMPLE, agents.size()):
		var p: Player = agents[i]
		var n := NegotiationSystem.open(world, org, p)
		var asked := float(n.demand[T.SALARY])
		var terms := n.offer.duplicate()
		if smart:
			# Ces deux clauses ne coûtent pas un centime aujourd'hui : elles
			# coûtent du contrôle demain. C'est exactement l'arbitrage que la
			# négociation doit rendre lisible.
			terms[T.BUYOUT] = int(float(p.market_value) * 1.2)
			terms[T.PRIZE] = 15.0
		var outcome := "stalled"
		var rounds := 0

		for _r in MAX_ROUNDS:
			rounds += 1
			var out := NegotiationSystem.submit(world, n, terms)
			var status := int(out["status"])
			if status == Negotiation.Status.ACCEPTED:
				outcome = "signed"
				break
			if status == Negotiation.Status.REFUSED:
				outcome = "refused"
				break
			terms[T.SALARY] = Money.pct(int(terms[T.SALARY]),
				100.0 + CONCESSION_PCT)
			terms[T.BONUS] = Money.pct(int(terms[T.BONUS]),
				100.0 + CONCESSION_PCT)
			terms[T.ROLE] = Contract.SquadRole.STARTER

		var key := "ambitieux" if p.attr(Attributes.AMBITION) >= 13 else "posé"
		(by_ambition[key] as Array)[1] += 1
		match outcome:
			"signed":
				signed += 1
				rounds_total += rounds
				overpay_total += float(terms[T.SALARY]) / maxf(asked, 1.0)
				(by_ambition[key] as Array)[0] += 1
				# On libère le joueur : la sonde doit rester comparable d'un
				# agent au suivant, pas construire un effectif de trente.
				ContractSystem.terminate(world, org, p)
			"refused":
				refused += 1
			_:
				stalled += 1
				NegotiationSystem.abandon(world, n)

	var total := signed + refused + stalled
	print("")
	print("  signés          %3d  (%.0f %%)" % [signed,
		float(signed) / maxf(float(total), 1.0) * 100.0])
	print("  refus de l'agent%3d  (%.0f %%)" % [refused,
		float(refused) / maxf(float(total), 1.0) * 100.0])
	print("  sans conclusion %3d  (%.0f %%)" % [stalled,
		float(stalled) / maxf(float(total), 1.0) * 100.0])
	if signed > 0:
		print("  tours moyens    %.1f" % (float(rounds_total) / float(signed)))
		print("  salaire final   %.0f %% de la demande initiale"
			% (overpay_total / float(signed) * 100.0))
	for key in by_ambition:
		var row: Array = by_ambition[key]
		if int(row[1]) > 0:
			print("  %-14s %3d / %3d signés" % [key, int(row[0]), int(row[1])])
	print("")
