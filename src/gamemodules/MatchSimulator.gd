class_name MatchSimulator
extends RefCounted

## Interface de simulation d'une série. Une implémentation par discipline.
##
## Contrat impératif : la simulation doit être PURE et DÉTERMINISTE.
## Elle ne lit que le MatchContext qu'on lui passe, n'écrit que dans le
## MatchResult qu'elle renvoie, et n'utilise que le Rng fourni. C'est ce qui
## permet de rejouer un match à l'identique et d'équilibrer les formules
## en comparant deux versions à graine égale.

func simulate(ctx: MatchContext) -> MatchResult:
	push_error("MatchSimulator.simulate() non implémenté")
	return null
