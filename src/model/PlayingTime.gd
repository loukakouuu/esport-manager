class_name PlayingTime
extends RefCounted

## Temps de jeu promis à un joueur.
##
## Ce n'est pas un réglage cosmétique : c'est le contrat moral entre le manager
## et le joueur, et la première source de conflit d'un vestiaire. Un joueur à
## qui on a promis « pilier de l'équipe » et qui joue 40 % des séries devient
## un problème, même bien payé et même si l'équipe gagne.
##
## Chaque palier définit une PART DE SÉRIES attendue. Le système de dynamique
## compare cette attente à la réalité et crée un grief en cas d'écart durable.

enum {
	STAR = 0,        # intouchable, la structure se construit autour de lui
	KEY = 1,         # joueur clé du cinq
	STARTER = 2,     # titulaire régulier
	ROTATION = 3,    # tourne avec un autre
	BACKUP = 4,      # remplaçant, joue quand il faut
	PROSPECT = 5,    # espoir, apprend, jouera plus tard
	SURPLUS = 6,     # hors projet, encouragé à partir
}

const ALL: Array[int] = [STAR, KEY, STARTER, ROTATION, BACKUP, PROSPECT, SURPLUS]

const LABELS := {
	STAR: "Star de l'équipe",
	KEY: "Joueur clé",
	STARTER: "Titulaire",
	ROTATION: "Rotation",
	BACKUP: "Remplaçant",
	PROSPECT: "Espoir",
	SURPLUS: "Hors projet",
}

## Part des séries que le joueur s'attend à disputer.
const EXPECTED_SHARE := {
	STAR: 0.95, KEY: 0.85, STARTER: 0.70, ROTATION: 0.45,
	BACKUP: 0.20, PROSPECT: 0.10, SURPLUS: 0.0,
}

## Multiplicateur de salaire attendu pour chaque statut : une star qu'on paie
## comme un remplaçant est aussi mécontente qu'un remplaçant qui ne joue pas.
const WAGE_EXPECTATION := {
	STAR: 1.45, KEY: 1.20, STARTER: 1.0, ROTATION: 0.85,
	BACKUP: 0.70, PROSPECT: 0.55, SURPLUS: 0.6,
}

## Ce que la fierté d'un joueur accepte comme rétrogradation sans broncher.
const TOLERANCE := 1


static func label(status: int) -> String:
	return LABELS.get(status, "Indéfini")


static func expected_share(status: int) -> float:
	return float(EXPECTED_SHARE.get(status, 0.4))


static func wage_expectation(status: int) -> float:
	return float(WAGE_EXPECTATION.get(status, 1.0))


static func labels() -> Array[String]:
	var out: Array[String] = []
	for s in ALL:
		out.append(label(s))
	return out


## Statut qu'un joueur de ce niveau estime mériter dans cette équipe.
## `rank` = son classement par CA dans l'effectif (0 = le meilleur).
static func deserved(rank: int, squad_size: int, ambition: int) -> int:
	# Un joueur ambitieux se surestime d'un cran, un joueur humble s'en
	# contente d'un de moins — c'est exactement ce qui rend les vestiaires
	# de superteams ingérables.
	var shift := 0
	if ambition >= 16:
		shift = -1
	elif ambition <= 7:
		shift = 1
	var base := STARTER
	if rank == 0 and squad_size >= 5:
		base = KEY
	elif rank <= 1:
		base = STARTER
	elif rank <= 4:
		base = STARTER
	elif rank == 5:
		base = ROTATION
	else:
		base = BACKUP
	return clampi(base + shift, STAR, SURPLUS)


static func color(status: int) -> Color:
	match status:
		STAR: return Color("#37d6c0")
		KEY: return Color("#46c46a")
		STARTER: return Color("#8fc44f")
		ROTATION: return Color("#d9c04a")
		BACKUP: return Color("#dd8038")
		PROSPECT: return Color("#4aa8ff")
	return Color("#8a93a6")
