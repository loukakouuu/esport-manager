class_name CoreTests
extends RefCounted

## Tests des briques transverses : argent, calendrier, aléa, comptabilité.


static func run() -> Array[TestCase]:
	return [_money(), _dates(), _rng(), _ledger()]


static func _money() -> TestCase:
	var t := TestCase.new("Money — arithmétique en cents")
	t.eq(Money.from_units(1250.0), 125_000, "conversion unités -> cents")
	t.eq(Money.pct(100_000, 12.5), 12_500, "pourcentage")

	# Un split ne doit JAMAIS perdre ni créer de cents.
	var parts := Money.split(1_000_000, [50, 30, 20])
	var sum := 0
	for p in parts:
		sum += p
	t.eq(sum, 1_000_000, "un split conserve le total")

	var odd := Money.split(1_000_001, [1, 1, 1])
	var sum2 := 0
	for p in odd:
		sum2 += p
	t.eq(sum2, 1_000_001, "un split indivisible conserve le total")
	return t


static func _dates() -> TestCase:
	var t := TestCase.new("GameDate — calendrier")
	var d := GameDate.from_ymd(2026, 1, 1)
	t.eq(GameDate.year_of(d), 2026, "année")
	t.eq(GameDate.month_of(d), 1, "mois")
	t.eq(GameDate.day_of_month(d), 1, "jour")
	t.eq(GameDate.day_of_month(GameDate.add_months(d, 1)), 1, "ajout d'un mois")
	t.eq(GameDate.month_of(GameDate.add_months(d, 13)), 2, "ajout de 13 mois")
	t.eq(GameDate.year_of(GameDate.add_months(d, 13)), 2027, "année après 13 mois")

	# 31 janvier + 1 mois ne doit pas déborder sur mars.
	var jan31 := GameDate.from_ymd(2026, 1, 31)
	t.eq(GameDate.month_of(GameDate.add_months(jan31, 1)), 2, "31 janv + 1 mois -> février")

	t.eq(GameDate.age_at(GameDate.from_ymd(2005, 6, 15), GameDate.from_ymd(2026, 6, 14)),
		20, "âge la veille de l'anniversaire")
	t.eq(GameDate.age_at(GameDate.from_ymd(2005, 6, 15), GameDate.from_ymd(2026, 6, 15)),
		21, "âge le jour de l'anniversaire")
	t.check(GameDate.is_last_day_of_month(GameDate.from_ymd(2026, 2, 28)),
		"28 février 2026 est le dernier jour du mois")
	t.check(GameDate.is_leap_year(2028), "2028 est bissextile")
	return t


static func _rng() -> TestCase:
	var t := TestCase.new("Rng — déterminisme")
	var a := Rng.new(12345)
	var b := Rng.new(12345)
	var same := true
	for _i in 200:
		if a.randi() != b.randi():
			same = false
	t.check(same, "deux générateurs de même graine produisent la même séquence")

	var c := Rng.new(999)
	var d1 := c.derive("match:1")
	var d2 := c.derive("match:1")
	t.eq(d1.seed_value, d2.seed_value, "la dérivation est reproductible")
	t.check(c.derive("match:1").seed_value != c.derive("match:2").seed_value,
		"deux sels différents donnent deux graines différentes")

	# La loi normale doit rester dans ses bornes.
	var out_of_range := 0
	for _i in 1000:
		var v := c.gauss_i(10.0, 4.0, 1, 20)
		if v < 1 or v > 20:
			out_of_range += 1
	t.eq(out_of_range, 0, "gauss_i respecte ses bornes")
	return t


static func _ledger() -> TestCase:
	var t := TestCase.new("Ledger — intégrité comptable")
	var l := Ledger.new()
	var day := GameDate.from_ymd(2026, 3, 1)
	l.credit(day, Money.from_units(500_000), Transaction.Category.SPONSORSHIP, "Sponsor")
	l.debit(day, Money.from_units(120_000), Transaction.Category.PLAYER_SALARY, "Salaires")
	l.debit(day + 40, Money.from_units(30_000), Transaction.Category.TRAVEL, "LAN")

	t.eq(l.cash, Money.from_units(350_000), "solde après trois écritures")
	t.eq(l.recompute_cash(0), l.cash, "le solde se reconstruit depuis les écritures")
	t.eq(l.net(day, day), Money.from_units(380_000), "résultat sur une journée")

	# Après compaction, le solde reconstruit doit être identique.
	var before := l.cash
	l.compact(day + 20)
	t.eq(l.recompute_cash(0), before, "la compaction préserve le solde")
	t.eq(l.transactions.size(), 1, "les écritures anciennes sont archivées")
	return t
