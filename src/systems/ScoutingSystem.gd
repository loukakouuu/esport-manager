class_name ScoutingSystem
extends RefCounted

## Information imparfaite.
##
## C'est le choix de design le plus important du jeu après la simulation :
## le joueur ne voit JAMAIS les attributs réels, seulement l'estimation de son
## staff. Sans cela, le recrutement se réduit à trier un tableau par colonne —
## avec, il redevient un pari où un bon recruteur vaut de l'argent.
##
## L'estimation est DÉTERMINISTE : le même joueur, observé avec le même niveau
## de connaissance, affiche toujours la même valeur. Une estimation qui
## scintillerait à chaque rafraîchissement serait injouable.

## Connaissance qu'a la structure du joueur d'un joueur donné (0..1).
##   1.00 : joueur de l'effectif suivi depuis longtemps
##   0.55 : joueur d'une autre structure de la même ligue
##   0.25 : joueur d'une autre région, jamais observé
static func knowledge(world: World, p: Player) -> float:
	var org := world.my_org()
	if org == null:
		return 1.0
	var base := 0.22

	# Un joueur connu du grand public est plus facile à évaluer.
	base += clampf(float(p.reputation) / 10000.0, 0.0, 1.0) * 0.28

	if p.org_id == org.id:
		var days := 0
		if p.contract != null:
			days = maxi(world.today - p.contract.signed_on_day, 0)
		base = 0.72 + clampf(float(days) / 540.0, 0.0, 0.28)
	else:
		if p.region == org.region:
			base += 0.15
		# Qualité de la cellule de recrutement
		var judgement := 0.0
		for sid in org.staff_ids:
			var s := world.staffer(sid)
			if s == null:
				continue
			if s.role == Staff.Role.SCOUT or s.role == Staff.Role.GENERAL_MANAGER:
				judgement = maxf(judgement, float(s.attr(Staff.JUDGEMENT)) / 20.0)
		base += judgement * 0.30
		# Budget de scouting
		base += clampf(float(org.budgets.get("scouting", 0))
			/ float(Money.from_units(20_000.0)), 0.0, 1.0) * 0.15
	return clampf(base, 0.15, 1.0)


## Décalage stable propre à un couple (joueur, information).
static func _bias(p: Player, key: String) -> float:
	var h := Rng.hash_seed(Rng.hash_seed(1, p.id), key)
	return (float(h % 2000) / 1000.0) - 1.0   # -1 .. +1


static func estimated_ca(world: World, p: Player) -> int:
	var k := knowledge(world, p)
	var margin := (1.0 - k) * 32.0
	return clampi(p.current_ability + int(round(_bias(p, "ca") * margin)), 1, 200)


static func ca_margin(world: World, p: Player) -> int:
	return int(round((1.0 - knowledge(world, p)) * 32.0))


## Affichage du niveau : une fourchette quand l'incertitude est forte,
## une valeur quand le joueur est bien connu.
static func ability_text(world: World, p: Player) -> String:
	var est := estimated_ca(world, p)
	var m := ca_margin(world, p)
	if m <= 3:
		return str(est)
	return "%d-%d" % [maxi(est - m, 1), mini(est + m, 200)]


## Potentiel estimé, exprimé en étoiles (0..5) et jamais en chiffre : personne
## ne sait vraiment jusqu'où ira un joueur de 17 ans. La mise en forme
## appartient à l'interface (UiKit.stars), pas à ce système.
## Repères : 3 étoiles ~ titulaire de Challengers, 4 ~ niveau VCT,
## 5 ~ candidat au top mondial.
static func potential_value(world: World, p: Player) -> float:
	var k := knowledge(world, p)
	var est := float(p.potential_ability) + _bias(p, "pa") * (1.0 - k) * 40.0
	return clampf((est - 60.0) / 26.0, 0.5, 5.0)


static func estimated_attr(world: World, p: Player, key: String) -> int:
	var k := knowledge(world, p)
	var margin := (1.0 - k) * 5.0
	return Attributes.clamp_value(
		p.attr(key) + int(round(_bias(p, key) * margin)))


## Fourchette affichée pour un attribut (min, max).
static func attr_range(world: World, p: Player, key: String) -> Vector2i:
	var est := estimated_attr(world, p, key)
	var m := int(round((1.0 - knowledge(world, p)) * 4.0))
	if m <= 0:
		return Vector2i(est, est)
	return Vector2i(maxi(est - m, 1), mini(est + m, 20))


static func attr_text(world: World, p: Player, key: String) -> String:
	var r := attr_range(world, p, key)
	if r.x == r.y:
		return str(r.x)
	return "%d-%d" % [r.x, r.y]


## Libellé de la fiabilité de l'évaluation, affiché sur la fiche joueur.
static func confidence_text(world: World, p: Player) -> String:
	var k := knowledge(world, p)
	if k >= 0.9:
		return "Évaluation fiable"
	if k >= 0.7:
		return "Bien observé"
	if k >= 0.5:
		return "Observé partiellement"
	if k >= 0.35:
		return "Peu d'informations"
	return "Quasiment inconnu"
