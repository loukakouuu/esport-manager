class_name Rng
extends RefCounted

## Générateur pseudo-aléatoire DÉTERMINISTE.
##
## Règle du projet : aucun appel à randi()/randf() global n'est autorisé dans
## la logique de simulation. Tout aléa passe par une instance de Rng dont la
## graine est dérivée de la graine du monde. Conséquences :
##   - une sauvegarde rechargée rejoue exactement la même saison ;
##   - un match peut être rejoué/débuggé à l'identique via son seed ;
##   - l'équilibrage est reproductible (on compare deux formules à seed égale).

var _rng := RandomNumberGenerator.new()
var seed_value: int = 0


func _init(p_seed: int = 0) -> void:
	seed_value = p_seed
	_rng.seed = p_seed


## Crée un sous-générateur indépendant mais reproductible.
## Ex : world_rng.derive("match:" + match_id)
func derive(salt: String) -> Rng:
	return Rng.new(hash_seed(seed_value, salt))


static func hash_seed(base: int, salt: String) -> int:
	var h := base
	for i in salt.length():
		h = (h * 31 + salt.unicode_at(i)) & 0x7FFFFFFFFFFF
	return h


func randi() -> int:
	return _rng.randi()


func randf() -> float:
	return _rng.randf()


func range_i(from: int, to_inclusive: int) -> int:
	return _rng.randi_range(from, to_inclusive)


func range_f(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


func chance(probability: float) -> bool:
	return _rng.randf() < probability


## Loi normale bornée : indispensable pour générer des populations crédibles
## (la plupart des joueurs sont moyens, très peu sont exceptionnels).
func gauss(mean: float, sd: float, min_v: float = -INF, max_v: float = INF) -> float:
	var v := _rng.randfn(mean, sd)
	return clampf(v, min_v, max_v)


func gauss_i(mean: float, sd: float, min_v: int, max_v: int) -> int:
	return int(round(clampf(_rng.randfn(mean, sd), float(min_v), float(max_v))))


func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[_rng.randi_range(0, arr.size() - 1)]


func pick_many(arr: Array, count: int) -> Array:
	var copy := arr.duplicate()
	shuffle(copy)
	return copy.slice(0, min(count, copy.size()))


## Tirage pondéré. `weights` doit avoir la même taille que `items`.
func weighted_pick(items: Array, weights: Array) -> Variant:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return pick(items)
	var r := _rng.randf() * total
	for i in items.size():
		r -= maxf(0.0, float(weights[i]))
		if r <= 0.0:
			return items[i]
	return items[items.size() - 1]


func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Fonction logistique : convertit un différentiel de force en probabilité.
## C'est la brique de base de toute la simulation de match.
static func logistic(x: float, steepness: float = 1.0) -> float:
	return 1.0 / (1.0 + exp(-x * steepness))


func save_state() -> Dictionary:
	return {"seed": seed_value, "state": _rng.state}


func load_state(d: Dictionary) -> void:
	seed_value = int(d.get("seed", 0))
	_rng.seed = seed_value
	_rng.state = int(d.get("state", 0))
