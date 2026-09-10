class_name RoleFamiliarity
extends RefCounted

## Aisance d'un joueur à un poste, façon Football Manager.
##
## Deux choses différentes, souvent confondues :
##  - la MAÎTRISE du rôle (`player.roles`), qui s'apprend en le jouant ;
##  - l'APTITUDE, c'est-à-dire à quel point ses attributs collent au poste.
##
## Un joueur peut être « naturel » contrôleur sans être bon (maîtrise haute,
## attributs faibles), ou avoir le profil parfait d'un duelliste sans jamais
## en avoir joué. L'interface doit montrer les deux : c'est ce qui rend une
## reconversion intéressante à tenter plutôt qu'évidente.

enum Level { NATURAL, ACCOMPLISHED, COMPETENT, UNCONVINCING, AWKWARD }

const LABELS := {
	Level.NATURAL: "Naturel",
	Level.ACCOMPLISHED: "Accompli",
	Level.COMPETENT: "Compétent",
	Level.UNCONVINCING: "Peu convaincant",
	Level.AWKWARD: "Inadapté",
}

const COLORS := {
	Level.NATURAL: Color("#37d6c0"),
	Level.ACCOMPLISHED: Color("#46c46a"),
	Level.COMPETENT: Color("#d9c04a"),
	Level.UNCONVINCING: Color("#dd8038"),
	Level.AWKWARD: Color("#d64545"),
}


static func level_of(player: Player, role_id: String) -> Level:
	if role_id == player.primary_role:
		return Level.NATURAL
	var m := player.role_rating(role_id)
	if m >= 17:
		return Level.NATURAL
	if m >= 13:
		return Level.ACCOMPLISHED
	if m >= 9:
		return Level.COMPETENT
	if m >= 5:
		return Level.UNCONVINCING
	return Level.AWKWARD


static func label(player: Player, role_id: String) -> String:
	return LABELS[level_of(player, role_id)]


static func color(player: Player, role_id: String) -> Color:
	return COLORS[level_of(player, role_id)]


## Aptitude brute (0..1) : à quel point les attributs du joueur correspondent
## aux exigences du poste, indépendamment de sa maîtrise.
##
## Normalisée sur l'échelle utile du jeu (une moyenne pondérée de 8/20 vaut 0,
## de 17/20 vaut 1) — sinon tous les joueurs professionnels se tiennent entre
## 0.55 et 0.80 et la barre ne dit plus rien.
static func aptitude(player: Player, module: GameModule, role_id: String) -> float:
	var w := module.role_weights(role_id)
	var total := 0.0
	var sum_w := 0.0
	for k in w:
		total += float(player.attr(k)) * float(w[k])
		sum_w += float(w[k])
	if sum_w <= 0.0:
		return 0.0
	var avg := total / sum_w
	return clampf((avg - 8.0) / 9.0, 0.0, 1.0)


## Classement des postes du joueur, du plus adapté au moins adapté.
## Renvoie [{"role", "ca", "aptitude", "level", "label", "color"}].
static func ranking(player: Player, module: GameModule) -> Array:
	var out: Array = []
	for role_id in module.roles():
		var lvl := level_of(player, role_id)
		out.append({
			"role": role_id,
			"ca": AbilityCalc.ca_as_role(player, module, role_id),
			"aptitude": aptitude(player, module, role_id),
			"level": lvl,
			"label": LABELS[lvl],
			"color": COLORS[lvl],
		})
	out.sort_custom(func(a, b): return int(a["ca"]) > int(b["ca"]))
	return out


## Meilleur poste pour ce joueur aujourd'hui.
static func best_role(player: Player, module: GameModule) -> String:
	var r := ranking(player, module)
	return str(r[0]["role"]) if not r.is_empty() else player.primary_role


## Le joueur est-il aligné hors de son meilleur poste ? Sert à signaler
## une composition bancale sans l'interdire.
static func is_misused(player: Player, module: GameModule,
		played_role: String) -> bool:
	return level_of(player, played_role) >= Level.UNCONVINCING
