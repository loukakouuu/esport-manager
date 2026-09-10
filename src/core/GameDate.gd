class_name GameDate
extends RefCounted

## Le temps du jeu est un ENTIER : un index de jour (jour 0 = 1970-01-01 UTC).
##
## Pourquoi pas une Date objet ? Parce que tout le moteur compare, trie et
## planifie des dates des milliers de fois par saison. Un int est trivial à
## sérialiser, à comparer, à utiliser comme clé de dictionnaire, et rend
## impossible les bugs de fuseau/heure d'été.

const SECONDS_PER_DAY := 86400

const MONTHS_FR := [
	"janvier", "février", "mars", "avril", "mai", "juin",
	"juillet", "août", "septembre", "octobre", "novembre", "décembre"
]
const MONTHS_FR_SHORT := [
	"janv.", "févr.", "mars", "avr.", "mai", "juin",
	"juil.", "août", "sept.", "oct.", "nov.", "déc."
]
const WEEKDAYS_FR := ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]


static func from_ymd(year: int, month: int, day: int) -> int:
	var unix := Time.get_unix_time_from_datetime_dict({
		"year": year, "month": month, "day": day,
		"hour": 0, "minute": 0, "second": 0
	})
	return int(floor(float(unix) / float(SECONDS_PER_DAY)))


static func to_dict(day_index: int) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(day_index * SECONDS_PER_DAY)


static func year_of(day_index: int) -> int:
	return int(to_dict(day_index)["year"])


static func month_of(day_index: int) -> int:
	return int(to_dict(day_index)["month"])


static func day_of_month(day_index: int) -> int:
	return int(to_dict(day_index)["day"])


## 0 = dimanche … 6 = samedi
static func weekday(day_index: int) -> int:
	return int(to_dict(day_index)["weekday"])


static func is_monday(day_index: int) -> bool:
	return weekday(day_index) == 1


static func is_last_day_of_month(day_index: int) -> bool:
	return month_of(day_index) != month_of(day_index + 1)


static func is_first_day_of_month(day_index: int) -> bool:
	return day_of_month(day_index) == 1


static func add_days(day_index: int, n: int) -> int:
	return day_index + n


static func add_months(day_index: int, n: int) -> int:
	var d := to_dict(day_index)
	var y := int(d["year"])
	var m := int(d["month"]) + n
	y += int(floor(float(m - 1) / 12.0))
	m = ((m - 1) % 12 + 12) % 12 + 1
	var dom := int(d["day"])
	var max_dom := days_in_month(y, m)
	return from_ymd(y, m, min(dom, max_dom))


static func add_years(day_index: int, n: int) -> int:
	return add_months(day_index, n * 12)


static func days_in_month(year: int, month: int) -> int:
	var lengths := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if month == 2 and is_leap_year(year):
		return 29
	return lengths[month - 1]


static func is_leap_year(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0


## Âge en années révolues à une date donnée.
static func age_at(birth_day: int, at_day: int) -> int:
	var b := to_dict(birth_day)
	var n := to_dict(at_day)
	var age := int(n["year"]) - int(b["year"])
	if int(n["month"]) < int(b["month"]) \
			or (int(n["month"]) == int(b["month"]) and int(n["day"]) < int(b["day"])):
		age -= 1
	return age


## "12 mars 2027"
static func format_long(day_index: int) -> String:
	var d := to_dict(day_index)
	return "%d %s %d" % [int(d["day"]), MONTHS_FR[int(d["month"]) - 1], int(d["year"])]


## "12 mars"
static func format_day_month(day_index: int) -> String:
	var d := to_dict(day_index)
	return "%d %s" % [int(d["day"]), MONTHS_FR_SHORT[int(d["month"]) - 1]]


## "ven. 12 mars 2027"
static func format_full(day_index: int) -> String:
	var d := to_dict(day_index)
	var wd: String = WEEKDAYS_FR[int(d["weekday"])]
	return "%s %d %s %d" % [wd.substr(0, 3) + ".", int(d["day"]),
		MONTHS_FR[int(d["month"]) - 1], int(d["year"])]


## "2027-03-12" — pour les logs et les clés de tri.
static func format_iso(day_index: int) -> String:
	var d := to_dict(day_index)
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


static func format_duration_days(n: int) -> String:
	if n < 0:
		return "expiré"
	if n < 31:
		return "%d j" % n
	if n < 365:
		return "%d mois" % int(round(float(n) / 30.44))
	var years := float(n) / 365.25
	return "%s an%s" % [String.num(years, 1), "s" if years >= 2.0 else ""]


## "mars 27" — abscisse compacte pour les graphes mensuels.
static func format_month_year(day_index: int) -> String:
	var d := to_dict(day_index)
	return "%s %02d" % [MONTHS_FR_SHORT[int(d["month"]) - 1],
		int(d["year"]) % 100]
