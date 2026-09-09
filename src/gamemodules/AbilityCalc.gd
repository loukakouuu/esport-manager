class_name AbilityCalc
extends RefCounted

## Capacité Actuelle (CA) et Capacité Potentielle (PA), échelle 1..200.
##
## La CA n'est PAS stockée comme une vérité indépendante : elle est toujours
## recalculée à partir des attributs pondérés par le rôle. Un joueur qui
## progresse en visée voit donc mécaniquement sa CA, sa valeur marchande et
## ses exigences salariales monter — un seul point de vérité, zéro incohérence.
##
## Repères d'échelle :
##   180+  légende mondiale, top 5 all-time
##   160+  star du top 4 international
##   140+  titulaire solide en ligue partenaire (VCT)
##   115+  bon joueur de Challengers, prêt pour le tier 1
##    90+  niveau Challengers correct
##    60+  amateur avancé

const SCALE := 10.0   # CA = moyenne pondérée (1..20) x 10


static func compute_ca(player: Player, module: GameModule) -> int:
	var w := module.role_weights(player.primary_role)
	if player.is_igl and module.has_method("igl_weights"):
		w = _blend(w, module.call("igl_weights"), 0.30)
	var total := 0.0
	var sum_w := 0.0
	for k in w:
		total += float(player.attr(k)) * float(w[k])
		sum_w += float(w[k])
	if sum_w <= 0.0:
		return player.current_ability
	return clampi(int(round(total / sum_w * SCALE)), 1, 200)


static func refresh(player: Player, module: GameModule) -> void:
	player.current_ability = compute_ca(player, module)
	if player.potential_ability < player.current_ability:
		player.potential_ability = player.current_ability


## Note d'un joueur POUR UN RÔLE donné (1..200) : sert à évaluer une
## reconversion ou un placement hors poste.
static func ca_as_role(player: Player, module: GameModule, role_id: String) -> int:
	var w := module.role_weights(role_id)
	var total := 0.0
	var sum_w := 0.0
	for k in w:
		total += float(player.attr(k)) * float(w[k])
		sum_w += float(w[k])
	if sum_w <= 0.0:
		return 1
	var raw := total / sum_w * SCALE
	# Pénalité de maîtrise : jouer un rôle qu'on ne connaît pas coûte cher.
	var mastery := float(player.role_rating(role_id)) / 20.0
	return clampi(int(round(raw * (0.72 + 0.28 * mastery))), 1, 200)


## Efficacité relative du joueur au poste où on l'aligne (0.72 .. 1.0).
static func role_fit(player: Player, module: GameModule, role_id: String) -> float:
	if role_id == player.primary_role:
		return 1.0
	var mastery := float(player.role_rating(role_id)) / 20.0
	var adapt := float(player.attr(Attributes.ADAPTABILITY)) / 20.0
	return clampf(0.72 + 0.20 * mastery + 0.08 * adapt, 0.72, 1.0)


static func _blend(a: Dictionary, b: Dictionary, ratio: float) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		out[k] = float(out.get(k, 0.0)) + float(b[k]) * ratio
	return out
