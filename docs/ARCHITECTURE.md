# Architecture — décisions et justifications

Ce document explique **pourquoi** le projet est construit ainsi.
`CLAUDE.md` décrit le **quoi**.

---

## 1. Le problème que l'architecture doit résoudre

Le cahier des charges ("un FM esport, Valorant d'abord, d'autres jeux ensuite,
avec une vraie économie") contient trois exigences qui se contredisent si on ne
les traite pas dès le départ :

| Exigence | Contrainte induite |
|---|---|
| Multi-jeu à terme | Rien de spécifique à Valorant ne doit fuiter dans le moteur |
| Économie réaliste | Un seul chemin pour l'argent, auditable, sans dérive |
| Profondeur façon FM | Des milliers d'entités simulées chaque jour, sauvegardables |

La réponse est une séparation en couches à dépendances strictement
descendantes :

```
core  →  model  →  gamemodules  →  systems  →  ui
```

Aucune flèche ne remonte. `Player` ne connaît pas `FinanceSystem` ;
`ValorantSim` ne connaît pas le `World` ; aucun écran ne connaît un système.

---

## 2. Organisation ≠ Roster : la décision la plus structurante

Le brief initial parlait d'« équipe ». Dans l'esport réel, l'unité économique
est la **structure** : c'est elle qui a des sponsors, des salariés, une
trésorerie et une marque. Une structure aligne des **rosters** sur plusieurs
jeux.

Modéliser cette distinction dès la v1 coûte presque rien et débloque tout :

- **Le multi-jeu devient un ajout de données**, pas une refonte. Ajouter CS2 =
  un `Roster` de plus dans la même `Organization`. `FinanceSystem` ne change pas
  d'une ligne : il additionne les salaires de tous les rosters.
- **L'académie existe gratuitement** : c'est un roster marqué `is_academy`.
- **Les finances sont crédibles** : les revenus (sponsors, merch, contenu) sont
  au niveau de la marque, les coûts au niveau des équipes — comme en vrai.

Avec une seule classe `Team`, l'ajout d'un second jeu aurait demandé de refondre
la moitié du moteur.

### Une négociation est une entité du monde, pas un état d'écran

`Negotiation` vit dans `World.negotiations` et se sauvegarde comme le reste.
La tentation était de la garder dans l'écran : elle n'existe que pendant qu'on
la regarde, après tout. Mais une discussion se poursuit d'un jour à l'autre —
la patience de l'agent s'use, sa demande baisse, la table peut s'éteindre
faute d'échanges — et tout cela doit survivre à une sauvegarde comme à un
changement d'écran. Une négociation perdue au rechargement serait un bug
invisible : on ne saurait même pas qu'on avait entamé quelque chose.

Corollaire utile : l'IA pourra un jour négocier par le même chemin, puisque
rien du système ne suppose un humain en face.

### Déclarer une discipline n'est pas la simuler

Une structure réelle aligne des sections que le jeu ne sait pas jouer. Plutôt
que de les taire, `Organization.games` les déclare et `GameCatalog` sait les
nommer ; seul `GameRegistry` — l'annuaire des `GameModule` implémentés — crée
des rosters, des matchs et des compétitions.

La séparation vaut le fichier supplémentaire : sans elle, il faudrait soit
mentir sur ce qu'est une structure, soit fabriquer des rosters fantômes qui
entreraient dans le calendrier et dans les finances. Le jour où un module CS2
existe, la section correspondante devient jouable sans qu'aucune donnée ne
change — et sans casser les carrières en cours.

L'équipe que l'utilisateur dirige est `World.player_roster_id`, distincte du
roster principal : c'est ce qui permet de basculer d'une section à l'autre.

---

## 3. Le module de jeu (`GameModule`)

`src/gamemodules/GameModule.gd` déclare tout ce qui varie d'une discipline à
l'autre : taille d'équipe, rôles, composition attendue, attributs spécifiques,
pondérations par rôle, réglages tactiques, colonnes de statistiques, et **le
simulateur de match**.

Le choix important : la partie « données » est déclarative (JSON + tables de
poids), mais la **simulation reste du code**. Un moteur entièrement piloté par
données ne peut pas représenter à la fois un FPS à rounds et économie et un MOBA
à objectifs continus sans devenir un langage de programmation déguisé. On écrit
donc un simulateur par genre, et on factorise tout le reste.

Coût réel d'un nouveau jeu :

1. `src/gamemodules/cs2/Cs2Module.gd` (déclarations)
2. `src/gamemodules/cs2/Cs2Sim.gd` (simulation)
3. `data/games/cs2/*.json` et un bloc dans `data/world/season_*.json`
4. une ligne dans `GameRegistry`

Rien d'autre. Contrats, finance, calendrier, progression, scouting, sauvegarde
et interface fonctionnent tels quels.

---

## 4. Simulation de match : pourquoi round par round

Le raccourci évident serait de tirer un vainqueur à partir de la différence de
force. On simule au contraire **chaque round avec son économie**, parce que
c'est ce qui produit gratuitement tout ce dont un jeu de gestion a besoin :

- des scores crédibles et variés (13-4, 13-11, 16-14 en prolongation) ;
- des statistiques individuelles cohérentes entre elles ;
- un récit affichable (le pistol perdu, le force-buy raté, le clutch à 11-11) ;
- des leviers de gestion à l'effet **lisible** : un IGL qui gère bien l'économie
  change réellement les décisions d'achat de son équipe.

L'économie officielle est reproduite : 800 au départ, +3000 sur victoire, bonus
de défaite 1900/2400/2900, 200 par frag, 300 à la pose, conservation de
l'équipement des survivants, plafond 9000.

La probabilité de gagner un round est une logistique à cinq termes, tous
regroupés en constantes en tête de `ValorantSim.gd` :

```
x = (force_atk - force_def) * W_SKILL       écart de niveau
  + (biais_map - 0.5)       * W_SIDE        map attaquante ou défensive
  + (éco_atk - éco_def)     * W_ECON        différentiel d'achat
  + (tilt_atk - tilt_def)   * W_MOMENTUM    dynamique et fragilité mentale
  + (prépa_atk - prépa_def) * W_PREP        travail de l'analyste
p = 1 / (1 + e^-x)
```

Le calibrage est verrouillé par un test (`SimTests._strength_curve`) qui impose
une courbe monotone et des ordres de grandeur réalistes : 50 % à niveau égal,
~65 % pour un petit écart, ~85 % pour un écart net, >90 % pour un gouffre.
**Aucune formule d'équilibrage ne doit être modifiée sans relancer ce test.**

---

## 5. Le système financier

### Le grand livre
`Ledger` est la source de vérité unique. Il n'existe **aucun** `org.cash += x`
ailleurs dans le code : tout passe par `credit()` / `debit()` avec une catégorie.
Trois bénéfices :

1. le compte de résultat de l'écran Finances est exact par construction ;
2. un bug financier se détecte par un test d'intégrité (`recompute_cash`) ;
3. on peut expliquer au joueur d'où vient chaque dollar.

Au-delà de deux ans, les écritures anciennes sont agrégées par mois et par
catégorie (`compact()`), pour qu'une partie de dix saisons ne fasse pas gonfler
la sauvegarde.

### Le modèle économique reproduit
Une structure esport réelle vit de ses **sponsors** (50-65 % des revenus), pas
de ses cashprizes (2-8 %). Le jeu reprend cette répartition :

| Produits | Charges |
|---|---|
| Sponsoring (emplacements exclusifs) | Salaires joueurs (poste écrasant) |
| Subvention de ligue partenaire (VCT) | Salaires staff |
| Partage de revenus éditeur (bundles) | Charges sociales (14 à 34 % selon la région) |
| Merchandising (fonction de la fanbase) | Infrastructures (loyer + entretien) |
| Contenu et streaming | Déplacements et LAN |
| Cashprizes (part structure) | Bootcamps, marketing, scouting |
| Ventes de joueurs (clauses de rachat) | Commissions d'agent, primes de signature |
| Apports en capital, emprunts | Impôt sur les sociétés, intérêts |

Quatre mécaniques donnent sa tension au système :

- **Le prize money n'appartient pas à la structure.** Le roster en touche une
  part contractuelle (9 à 18 % par titulaire). Gagner un tournoi rapporte donc
  beaucoup moins que le montant annoncé dans la presse.
- **Les sponsors « à risque » (paris, crypto) paient nettement plus** mais
  coûtent en image : baisse de fanbase et de réputation, donc de valeur des
  contrats suivants. C'est l'arbitrage réel de l'écosystème.
- **Les sponsors exigent des activations.** Sans studio de contenu ni
  responsable dédié, la structure ne tient pas ses obligations et subit une
  retenue mensuelle. Le contenu n'est pas décoratif : c'est une charge de
  production.
- **Les charges sociales varient par région.** Un roster européen coûte
  structurellement plus cher qu'un roster américain à salaire net égal.

### Les indicateurs
`FinanceSystem` expose ce qu'un dirigeant regarde vraiment : résultat mensuel
prévisionnel, **autonomie en mois** (runway), masse salariale et son poids en
pourcentage des revenus. Trois mois de trésorerie négative déclenchent un
avertissement de la direction, six mois le dépôt de bilan.

### Cohérence du monde de départ
La trésorerie initiale d'une structure est calculée **après** la création de son
roster, de son staff et de ses sponsors, comme un multiple de ses charges
mensuelles réelles. Une estimation a priori se décorrèle immédiatement des
salaires effectivement générés et condamne les petites structures à la faillite
dès la première saison — c'est exactement le bug que cette approche supprime.

---

## 6. Information imparfaite

`ScoutingSystem` est le second choix de design le plus important après la
simulation. Le joueur ne voit **jamais** les attributs réels : il voit
l'estimation de son staff, avec une fourchette d'autant plus large que le joueur
est mal connu. Le niveau de connaissance dépend de la notoriété du joueur, de sa
région, de la qualité du recruteur et du budget de scouting.

Sans cette couche, recruter se réduit à trier un tableau par colonne. Avec elle,
un bon recruteur devient un investissement rentable et une erreur de casting
devient une histoire.

L'estimation est **déterministe** (dérivée d'un hachage de l'identifiant du
joueur) : elle ne scintille pas d'un affichage à l'autre.

---

## 6 bis. Une personne appartient à un seul endroit à la fois

Un membre du staff est référencé à **trois** endroits : `Staff.org_id`,
`Organization.staff_ids`, et le roster qu'il encadre
(`Roster.head_coach_id` ou `Roster.staff_ids`). Trois copies de la même
information, donc trois occasions de désynchroniser.

Elles ont désynchronisé. `ContractSystem` retirait un encadrant en fin de
contrat des deux premières et oubliait la troisième : la structure cessait de
verser le salaire, mais `TeamSheetBuilder` lisait toujours `head_coach_id` et
lui appliquait son apport tactique. Mesuré sur trois saisons simulées :
**136 structures sur 136** jouaient avec un entraîneur gratuit.

La règle qui en découle, et qui vaut pour toute donnée dupliquée du projet :

> Quand une information existe en plusieurs exemplaires, il doit y avoir
> **exactement une fonction** qui les écrit toutes, et **exactement une** qui
> les efface toutes. Ici `StaffSystem.attach()` et `StaffSystem.detach()`.
> Aucun autre fichier ne touche `head_coach_id`.

Ce n'est pas une convention de style : c'est ce qui rend le bug impossible
plutôt qu'improbable. Une convention se contourne par distraction ; un point
d'entrée unique se vérifie d'un `grep`. La sonde `tools/staff_probe.gd` compte
les références orphelines à chaque exécution et exige zéro.

Le même motif existe déjà pour l'argent (§5, tout passe par le grand livre) et
pour le temps (`GameSim.advance_day` est le seul à incrémenter `world.today`).

### Pourquoi le staff ne se négocie pas comme un joueur

`NegotiationSystem` existait avant `StaffSystem`, et la tentation était de le
réutiliser. Décision inverse : le staff se recrute en une offre et une réponse.

Marchander six clauses avec un analyste serait la même mécanique une deuxième
fois pour un enjeu plus faible — et deux systèmes de marchandage dans un même
jeu se dévaluent l'un l'autre. L'arbitrage du staff est ailleurs : combien de
postes ouvrir, à quel niveau, pour quelle masse salariale. C'est un problème de
portefeuille, pas de face-à-face, et `StaffSystem.org_chart()` en est la forme
côté IA — une enveloppe par poste, pas un budget commun.

Cette dernière distinction s'est imposée par la mesure. Avec un budget commun,
les postes secondaires consommaient la caisse avant l'expiration du contrat de
l'entraîneur, et la structure se retrouvait ensuite sans banc, incapable de
rembaucher : 50 structures sur 136 après trois saisons.

---

## 7. Déterminisme

Toute la simulation dérive d'une graine unique. Chaque match reçoit un
générateur dérivé de son identifiant (`world.rng.derive("fixture:" + f.id)`).
Conséquences pratiques :

- une sauvegarde rechargée rejoue exactement la même saison ;
- un bug de simulation se reproduit à volonté à partir de la graine ;
- deux versions d'une formule se comparent à graine égale, ce qui rend
  l'équilibrage mesurable au lieu d'être une impression.

---

## 8. Sauvegarde : JSON plutôt que ressources Godot

Le format `.tres` a été écarté au profit de JSON compressé :

- un `World` est un graphe de plusieurs milliers d'objets `RefCounted` ; le
  sérialiseur de ressources y est lent et verbeux ;
- le JSON est inspectable et comparable, ce qui divise le temps de debug ;
- la migration de version se code en quelques lignes (`SaveGame.migrate`), alors
  qu'un `.tres` cassé par un renommage de champ est irrécupérable.

Le fichier porte un `schema_version`. **Tout changement de format doit
l'incrémenter et ajouter son palier de migration.**

---

## 9. Interface construite en code

Les écrans sont générés par `UiKit` plutôt que dessinés en scènes `.tscn`. Ce
n'est pas un raccourci : les tableaux d'un jeu de gestion ont des colonnes qui
dépendent de la discipline. Une table décrite par des données reste juste quand
on ajoute un jeu ; une scène figée doit être redessinée.

`Main.tscn` ne contient qu'un nœud. Toute la navigation est dans `src/ui/App.gd`.

---

## 10. Écarts assumés par rapport à la réalité

| Sujet | Réalité | Implémentation | Pourquoi |
|---|---|---|---|
| Promotion VCT | Le vainqueur de l'Ascension obtient un slot de 2 ans, sans relégation directe | Le vainqueur remplace le dernier du VCT | Boucle de campagne lisible dès la v1. Règle isolée dans `SeasonBuilder._apply_promotions`, remplaçable seule. |
| Noms | Structures et joueurs réels sont protégés | `data/` reste entièrement fictif ; les vrais noms vivent dans un pack (`packs/vct_2026/`, livré parce que le dépôt est privé et le jeu non distribué) | Le code n'a jamais connaissance d'une marque : supprimer `packs/` suffit à rendre le projet publiable. |
| Attributs des joueurs réels | Inconnus, et non publiés | Toujours générés ; le pack n'apporte que l'identité | « Visée 17/20 » est un jugement de jeu, pas une donnée. Prétendre l'importer serait inventer une source. |
| Ligues de Challengers | Des dizaines de ligues nationales | Une ligue par région, 12 équipes | Monde de 96 structures : assez pour un marché vivant, simulable en 5 secondes par saison. |
| Double élimination | Tous formats | Format à 8 équipes ; toute autre taille retombe sur une élimination directe seedée | Couvre les playoffs VCT réels. Généraliser est une extension isolée de `BracketBuilder`. |
| Agents | Négociation à trois (joueur, agent, club) | L'agent est réduit à une commission | Profondeur reportée : la structure de données du contrat porte déjà `agent_fee_pct`. |

---

## 11. Performance mesurée

En headless, sur la machine de développement :

- génération du monde (96 structures, ~715 joueurs) : **~220 ms**
- saison complète (577 séries, tous systèmes actifs) : **~4,7 s**

Une journée simulée est donc instantanée pour le joueur. Le poste dominant est
la simulation de match : c'est là, et nulle part ailleurs, qu'il faudra
optimiser si le besoin apparaît.

---

## 12. Ce qu'il faut savoir avant de modifier

- **Toucher à une constante `W_*` de `ValorantSim`** invalide l'équilibrage :
  relancer `bash tools/test.sh` et `tools/season.gd` et comparer.
- **Ajouter un champ à une entité** implique de le traiter dans `to_dict()` ET
  `from_dict()`, sinon il disparaît silencieusement à la sauvegarde.
- **Ajouter une catégorie de transaction** demande aussi son libellé dans
  `Transaction.LABELS` et, si c'est un produit, son ajout à `INCOME_CATEGORIES`.
- **Ne jamais appeler un système depuis un écran** : passer par `Game`.
