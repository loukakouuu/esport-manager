class_name Loan
extends RefCounted

## Emprunt. Permet de survivre à un trou de trésorerie… au prix d'une charge
## fixe qui étrangle la masse salariale des saisons suivantes.

var id: String = ""
var lender: String = "Banque"
var principal: int = 0            # cents empruntés
var outstanding: int = 0          # capital restant dû
var annual_rate: float = 0.09     # 9 % / an
var start_day: int = 0
var term_months: int = 24
var months_paid: int = 0


func monthly_payment() -> int:
	if term_months <= 0:
		return 0
	var r := annual_rate / 12.0
	if r <= 0.0:
		return int(round(float(principal) / float(term_months)))
	var pow_term := pow(1.0 + r, float(term_months))
	return int(round(float(principal) * r * pow_term / (pow_term - 1.0)))


## Découpe la mensualité en (intérêts, capital).
func split_payment() -> Array[int]:
	var interest := int(round(float(outstanding) * annual_rate / 12.0))
	var total := monthly_payment()
	var principal_part := clampi(total - interest, 0, outstanding)
	var out: Array[int] = [interest, principal_part]
	return out


func is_settled() -> bool:
	return outstanding <= 0 or months_paid >= term_months


func to_dict() -> Dictionary:
	return {"id": id, "lender": lender, "principal": principal,
		"outstanding": outstanding, "annual_rate": annual_rate,
		"start_day": start_day, "term_months": term_months,
		"months_paid": months_paid}


static func from_dict(d: Dictionary) -> Loan:
	var l := Loan.new()
	l.id = d.get("id", "")
	l.lender = d.get("lender", "Banque")
	l.principal = int(d.get("principal", 0))
	l.outstanding = int(d.get("outstanding", 0))
	l.annual_rate = float(d.get("annual_rate", 0.09))
	l.start_day = int(d.get("start_day", 0))
	l.term_months = int(d.get("term_months", 24))
	l.months_paid = int(d.get("months_paid", 0))
	return l
