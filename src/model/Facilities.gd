class_name Facilities
extends RefCounted

## Infrastructures de la structure. Niveau 0 (inexistant) à 5 (élite).
##
## Chaque niveau coûte un investissement initial ET une charge mensuelle
## récurrente. C'est le principal arbitrage long terme du jeu : dépenser
## aujourd'hui pour développer mieux demain, ou garder la trésorerie.

enum Kind {
	OFFICE,        # locaux, administratif, crédibilité auprès des sponsors
	TRAINING_ROOM, # setup, salle de scrim -> progression et netteté
	TEAM_HOUSE,    # logement/bootcamp -> récupération de la fatigue
	ANALYTICS,     # outils VOD/data -> efficacité de l'analyste
	WELLNESS,      # suivi médical et sportif -> blessures et burnout
	CONTENT_STUDIO,# studio -> revenus de contenu et fanbase
	ACADEMY,       # structure de formation -> progression des jeunes
}

const KIND_LABELS := {
	Kind.OFFICE: "Locaux",
	Kind.TRAINING_ROOM: "Salle d'entraînement",
	Kind.TEAM_HOUSE: "Team house",
	Kind.ANALYTICS: "Cellule analyse",
	Kind.WELLNESS: "Pôle performance",
	Kind.CONTENT_STUDIO: "Studio de contenu",
	Kind.ACADEMY: "Académie",
}

const MAX_LEVEL := 5

## Coût d'investissement pour passer au niveau N (index = niveau visé), en $.
const UPGRADE_COST_UNITS := {
	Kind.OFFICE:         [0, 25_000, 70_000, 160_000, 400_000, 900_000],
	Kind.TRAINING_ROOM:  [0, 20_000, 60_000, 150_000, 350_000, 750_000],
	Kind.TEAM_HOUSE:     [0, 60_000, 150_000, 320_000, 700_000, 1_500_000],
	Kind.ANALYTICS:      [0, 15_000, 45_000, 110_000, 260_000, 600_000],
	Kind.WELLNESS:       [0, 18_000, 50_000, 120_000, 280_000, 650_000],
	Kind.CONTENT_STUDIO: [0, 30_000, 80_000, 180_000, 420_000, 950_000],
	Kind.ACADEMY:        [0, 40_000, 110_000, 250_000, 550_000, 1_200_000],
}

## Charge mensuelle par niveau, en $.
const UPKEEP_UNITS := {
	Kind.OFFICE:         [0, 1_200, 3_000, 6_500, 14_000, 30_000],
	Kind.TRAINING_ROOM:  [0, 900, 2_200, 5_000, 11_000, 24_000],
	Kind.TEAM_HOUSE:     [0, 3_500, 8_000, 16_000, 32_000, 65_000],
	Kind.ANALYTICS:      [0, 700, 1_800, 4_000, 9_000, 19_000],
	Kind.WELLNESS:       [0, 800, 2_000, 4_500, 10_000, 21_000],
	Kind.CONTENT_STUDIO: [0, 1_500, 3_800, 8_000, 17_000, 36_000],
	Kind.ACADEMY:        [0, 2_500, 6_000, 13_000, 27_000, 55_000],
}


static func label(k: Kind) -> String:
	return KIND_LABELS.get(k, "Infrastructure")


static func upgrade_cost(k: Kind, target_level: int) -> int:
	if target_level <= 0 or target_level > MAX_LEVEL:
		return 0
	return Money.from_units(float(UPGRADE_COST_UNITS[k][target_level]))


static func monthly_upkeep(k: Kind, level: int) -> int:
	return Money.from_units(float(UPKEEP_UNITS[k][clampi(level, 0, MAX_LEVEL)]))


static func total_monthly_upkeep(levels: Dictionary) -> int:
	var total := 0
	for k in Kind.values():
		total += monthly_upkeep(k, int(levels.get(k, 0)))
	return total


static func default_levels() -> Dictionary:
	var d := {}
	for k in Kind.values():
		d[k] = 0
	return d


## Multiplicateur d'effet d'une infra : 0.85 (rien) à 1.30 (niveau 5).
static func effect(levels: Dictionary, k: Kind) -> float:
	var lvl := clampi(int(levels.get(k, 0)), 0, MAX_LEVEL)
	return 0.85 + 0.09 * float(lvl)
