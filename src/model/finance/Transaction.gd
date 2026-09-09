class_name Transaction
extends RefCounted

## Une écriture comptable. TOUT mouvement d'argent du jeu passe par ici :
## il n'existe aucun `org.cash += x` ailleurs dans le code. C'est la règle
## qui rend le compte de résultat exact et auditable — et qui permet à
## l'écran Finances d'expliquer chaque centime au joueur.

enum Category {
	# --- Produits ---
	SPONSORSHIP,        # contrats sponsors
	LEAGUE_STIPEND,     # subvention de ligue partenaire (VCT)
	LEAGUE_REV_SHARE,   # partage des ventes de bundles / skins d'équipe
	PRIZE_MONEY,        # part de la structure sur les cashprizes
	MERCHANDISE,
	CONTENT,            # stream, vidéo, sponsoring de contenu
	BUYOUT_IN,          # vente d'un joueur (clause de rachat encaissée)
	INVESTMENT,         # apport d'actionnaire / levée de fonds
	LOAN_IN,
	OTHER_INCOME,
	# --- Charges ---
	PLAYER_SALARY,
	STAFF_SALARY,
	PRIZE_SHARE,        # part des cashprizes reversée aux joueurs
	SIGNING_BONUS,
	AGENT_FEE,
	BUYOUT_OUT,         # rachat d'un joueur à une autre structure
	FACILITY,           # loyer, matériel, entretien
	TRAVEL,             # déplacements, hôtels, LAN
	BOOTCAMP,
	MARKETING,
	LEAGUE_FEE,         # frais d'engagement / slot
	TAX,
	LOAN_INTEREST,
	LOAN_REPAYMENT,
	MISC,
}

const INCOME_CATEGORIES: Array[int] = [
	Category.SPONSORSHIP, Category.LEAGUE_STIPEND, Category.LEAGUE_REV_SHARE,
	Category.PRIZE_MONEY, Category.MERCHANDISE, Category.CONTENT,
	Category.BUYOUT_IN, Category.INVESTMENT, Category.LOAN_IN,
	Category.OTHER_INCOME,
]

const LABELS := {
	Category.SPONSORSHIP: "Sponsoring",
	Category.LEAGUE_STIPEND: "Subvention de ligue",
	Category.LEAGUE_REV_SHARE: "Partage de revenus éditeur",
	Category.PRIZE_MONEY: "Gains de tournoi (part structure)",
	Category.MERCHANDISE: "Merchandising",
	Category.CONTENT: "Contenu & streaming",
	Category.BUYOUT_IN: "Vente de joueur",
	Category.INVESTMENT: "Apport en capital",
	Category.LOAN_IN: "Emprunt reçu",
	Category.OTHER_INCOME: "Autres produits",
	Category.PLAYER_SALARY: "Salaires joueurs",
	Category.STAFF_SALARY: "Salaires staff",
	Category.PRIZE_SHARE: "Gains reversés aux joueurs",
	Category.SIGNING_BONUS: "Primes à la signature",
	Category.AGENT_FEE: "Commissions d'agent",
	Category.BUYOUT_OUT: "Rachat de joueur",
	Category.FACILITY: "Infrastructures",
	Category.TRAVEL: "Déplacements",
	Category.BOOTCAMP: "Bootcamps",
	Category.MARKETING: "Marketing",
	Category.LEAGUE_FEE: "Frais de ligue",
	Category.TAX: "Impôts et charges",
	Category.LOAN_INTEREST: "Intérêts d'emprunt",
	Category.LOAN_REPAYMENT: "Remboursement d'emprunt",
	Category.MISC: "Divers",
}

var id: String = ""
var day: int = 0
var amount: int = 0          # cents, SIGNÉ (+ encaissement / - décaissement)
var category: Category = Category.MISC
var label: String = ""
var counterparty: String = ""
var meta: Dictionary = {}


static func make(p_day: int, p_amount: int, p_cat: Category,
		p_label: String, p_counterparty: String = "") -> Transaction:
	var t := Transaction.new()
	t.day = p_day
	t.amount = p_amount
	t.category = p_cat
	t.label = p_label
	t.counterparty = p_counterparty
	return t


static func is_income_category(c: Category) -> bool:
	return INCOME_CATEGORIES.has(int(c))


static func category_label(c: Category) -> String:
	return LABELS.get(c, "Divers")


func to_dict() -> Dictionary:
	return {
		"id": id, "day": day, "amount": amount, "category": int(category),
		"label": label, "counterparty": counterparty, "meta": meta.duplicate(),
	}


static func from_dict(d: Dictionary) -> Transaction:
	var t := Transaction.new()
	t.id = d.get("id", "")
	t.day = int(d.get("day", 0))
	t.amount = int(d.get("amount", 0))
	t.category = int(d.get("category", Category.MISC)) as Category
	t.label = d.get("label", "")
	t.counterparty = d.get("counterparty", "")
	t.meta = (d.get("meta", {}) as Dictionary).duplicate()
	return t
