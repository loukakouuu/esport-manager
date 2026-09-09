class_name Ledger
extends RefCounted

## Grand livre d'une structure. Source de verite unique de la tresorerie.
##
## `cash` n'est modifie QUE par post(). On peut donc toujours reconstituer le
## solde a partir des ecritures, ce qui rend les bugs financiers detectables
## par un simple test (voir src/tests/).
##
## Compaction : au-dela de ~24 mois, les ecritures anciennes sont agregees en
## une ecriture mensuelle par categorie. Une partie de 10 saisons ne fait donc
## pas exploser la sauvegarde.

var cash: int = 0
var transactions: Array[Transaction] = []
var _next_seq: int = 1

# Cumuls mensuels compactes : "AAAA-MM" -> { category:int -> cents:int }
var archive: Dictionary = {}


func post(t: Transaction) -> void:
	if t.id == "":
		t.id = "tx_%06d" % _next_seq
	_next_seq += 1
	transactions.append(t)
	cash += t.amount


func credit(day: int, amount: int, cat: Transaction.Category,
		label: String, counterparty: String = "") -> Transaction:
	var t := Transaction.make(day, absi(amount), cat, label, counterparty)
	post(t)
	return t


func debit(day: int, amount: int, cat: Transaction.Category,
		label: String, counterparty: String = "") -> Transaction:
	var t := Transaction.make(day, -absi(amount), cat, label, counterparty)
	post(t)
	return t


func in_range(from_day: int, to_day: int) -> Array[Transaction]:
	var out: Array[Transaction] = []
	for t in transactions:
		if t.day >= from_day and t.day <= to_day:
			out.append(t)
	return out


## Compte de resultat sur une periode : { category:int -> cents:int }
func pnl(from_day: int, to_day: int) -> Dictionary:
	var out: Dictionary = {}
	for t in transactions:
		if t.day < from_day or t.day > to_day:
			continue
		out[int(t.category)] = int(out.get(int(t.category), 0)) + t.amount
	return out


func total_income(from_day: int, to_day: int) -> int:
	var s := 0
	for t in transactions:
		if t.day >= from_day and t.day <= to_day and t.amount > 0:
			s += t.amount
	return s


func total_expense(from_day: int, to_day: int) -> int:
	var s := 0
	for t in transactions:
		if t.day >= from_day and t.day <= to_day and t.amount < 0:
			s += t.amount
	return s


func net(from_day: int, to_day: int) -> int:
	return total_income(from_day, to_day) + total_expense(from_day, to_day)


## Solde reconstruit depuis zero : utilise par les tests d'integrite.
func recompute_cash(opening_balance: int) -> int:
	var c := opening_balance
	for month_key in archive:
		for cat in archive[month_key]:
			c += int(archive[month_key][cat])
	for t in transactions:
		c += t.amount
	return c


## Agrege tout ce qui est anterieur a `before_day` dans `archive`.
func compact(before_day: int) -> int:
	var kept: Array[Transaction] = []
	var compacted := 0
	for t in transactions:
		if t.day >= before_day:
			kept.append(t)
			continue
		var key := "%04d-%02d" % [GameDate.year_of(t.day), GameDate.month_of(t.day)]
		if not archive.has(key):
			archive[key] = {}
		var bucket: Dictionary = archive[key]
		bucket[int(t.category)] = int(bucket.get(int(t.category), 0)) + t.amount
		compacted += 1
	transactions = kept
	return compacted


func to_dict() -> Dictionary:
	var txs: Array = []
	for t in transactions:
		txs.append(t.to_dict())
	return {"cash": cash, "next_seq": _next_seq, "transactions": txs,
		"archive": archive.duplicate(true)}


static func from_dict(d: Dictionary) -> Ledger:
	var l := Ledger.new()
	l.cash = int(d.get("cash", 0))
	l._next_seq = int(d.get("next_seq", 1))
	for td in d.get("transactions", []):
		l.transactions.append(Transaction.from_dict(td))
	l.archive = (d.get("archive", {}) as Dictionary).duplicate(true)
	return l
