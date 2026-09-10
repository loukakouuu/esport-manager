# Esport Manager — contexte du projet

## Vue d'ensemble
Jeu de gestion de **structure esport** façon Football Manager, développé en solo
avec Claude Code. Le joueur dirige une organisation : il recrute, entraîne,
négocie des sponsors, gère une trésorerie, et suit ses matchs sous forme de
simulation textuelle round par round — **aucun rendu 3D du match**.

Deux partis pris fondateurs :

1. **On dirige une STRUCTURE, pas une équipe.** L'organisation porte la
   trésorerie et la marque ; elle possède un ou plusieurs rosters. C'est ce qui
   rend le multi-jeu naturel plus tard (un roster Valorant + un roster CS2 dans
   la même entreprise) et ce qui rend la finance crédible aujourd'hui.
2. **La finance est un vrai système, pas un compteur.** Toute somme d'argent
   passe par une écriture comptable dans un grand livre. Le compte de résultat
   affiché au joueur est littéralement la somme de ce que le moteur a dépensé.

Discipline livrée : **VALORANT**. L'architecture est multi-jeu dès maintenant
(voir `src/gamemodules/`), mais un seul module est implémenté.

## Stack
- **Moteur** : Godot 4.7 · **Langage** : GDScript
- **Sauvegarde** : JSON compressé (gzip) sous `user://saves/`, avec numéro de
  schéma et fonction de migration (`src/save/SaveGame.gd`)
- **Tests** : headless, sans éditeur ni scène (`tools/run_tests.gd`)
- **Versioning** : Git

## Structure du dépôt
```
res://
├── data/                      Contenu éditable sans toucher au code
│   ├── games/valorant/        maps.json, agents.json
│   └── world/                 orgs.json, sponsors.json, names.json,
│                              season_valorant.json (structure des compétitions)
├── src/
│   ├── core/                  Money, Rng, GameDate, Ids, Log, DataFile
│   ├── model/                 Entités pures et sérialisables (World, Player,
│   │   │                      Organization, Roster, Competition, Fixture…)
│   │   └── finance/           Ledger, Transaction, SponsorDeal, Loan
│   ├── gamemodules/           Interface GameModule + implémentation valorant/
│   ├── systems/               Toute la logique de simulation (sans état propre)
│   ├── save/                  Sauvegarde et migrations
│   ├── ui/                    UiKit, App, screens/
│   └── tests/                 Suites de tests
├── autoload/Game.gd           Façade unique entre l'UI et le moteur
├── scenes/Main.tscn           Scène de lancement
└── tools/                     Scripts headless (tests, simulation de saison)
```

## Règles d'architecture (non négociables)

1. **Le World ne contient que des données.** Aucune méthode de simulation dans
   `src/model/`. La logique vit dans `src/systems/`, sous forme de fonctions
   `static` qui prennent le World en paramètre. Conséquences : la sauvegarde
   est un `to_dict()`, et chaque système est testable isolément.
2. **L'UI ne touche jamais un système.** Elle passe par l'autoload `Game`, qui
   exécute puis émet un signal. Un écran ne peut donc pas casser la simulation.
3. **Tout l'aléa passe par `Rng`.** Aucun appel à `randi()`/`randf()` global
   dans la logique. Une partie est rejouable à l'identique, et l'équilibrage se
   compare à graine égale.
4. **L'argent est un entier de cents.** Jamais de float. Voir `src/core/Money.gd`.
5. **Le temps est un index de jour entier** (`src/core/GameDate.gd`), jamais un
   objet date.
6. **Rien de spécifique à Valorant hors de `src/gamemodules/valorant/`.**
   Le reste du moteur ne connaît que l'interface `GameModule`.
7. **Aucun contenu en dur.** Maps, agents, structures, sponsors, prénoms et
   format des compétitions sont dans `data/`.

## Conventions de code
- Fichiers et classes en **PascalCase** (`Player.gd`), variables et fonctions en
  **snake_case**, membres privés préfixés `_`.
- Commenter le **pourquoi**, pas le quoi. Toute formule de simulation ou
  d'équilibrage doit expliquer son intention et ses ordres de grandeur.
- Tabulations pour l'indentation (voir `.editorconfig`).
- Textes destinés au joueur en français, identifiants en anglais.

## Commandes utiles
```bash
# Suite de tests (réindexe les classes puis exécute)
bash tools/test.sh

# Simulation d'une saison complète + rapport d'équilibrage
godot --headless --path . --script res://tools/season.gd

# Lancer le jeu
godot --path .
```
Après avoir ajouté un fichier avec `class_name`, il faut réindexer une fois :
`godot --headless --path . --editor --quit` (c'est ce que fait `tools/test.sh`).

## État actuel
Fait :
- [x] Noyau : argent en cents, RNG déterministe, calendrier, chargement de données
- [x] Modèle de données complet et sérialisable
- [x] Module Valorant : rôles, attributs, agents, maps, tactiques
- [x] Simulation de match round par round avec économie officielle, veto de maps,
      momentum, temps morts, clutchs, statistiques individuelles et notes
- [x] Génération du monde : 96 structures, ~720 joueurs, 4 régions
- [x] Pyramide compétitive : VCT (4 ligues) + Challengers + Masters + Champions
      + Ascension, formats round robin / poules / double élimination / suisse
- [x] Finances : grand livre, sponsors, subventions, merch, contenu, salaires,
      charges sociales, infrastructures, emprunts, impôt, faillite
- [x] Contrats, clauses de rachat, marché des joueurs, IA de recrutement
- [x] Progression, courbe d'âge, blessures, burnout, moral, retraites
- [x] Scouting à information imparfaite
- [x] Direction : objectifs de saison et confiance
- [x] Sauvegarde/chargement avec migration de schéma
- [x] Interface complète (12 écrans)

Prochaines étapes suggérées : voir `docs/ROADMAP.md`.

## Vérifications avant de committer
```bash
bash tools/check_all.sh    # tests + écrans + saison complète
```
Les trois doivent passer : 63 vérifications unitaires, 12 écrans construits,
et une saison qui se termine avec des classements et des finances cohérents.

## Pièges connus de Godot rencontrés sur ce projet
- **`PanelContainer`, `MarginContainer`, `ScrollContainer` et `CenterContainer`
  EMPILENT leurs enfants** dans le même rectangle. Y ajouter plusieurs contrôles
  les superpose au lieu de les aligner — le bug ne plante pas, il rend l'écran
  illisible. Toujours mettre UN seul enfant (une `HBoxContainer`/`VBoxContainer`)
  et ajouter dedans. `tools/ui_check.gd` vérifie désormais cet invariant.
- `Side`, `sign`, `Color` : noms réservés par Godot. Ne pas nommer une classe ou
  une fonction statique comme un symbole global (`ContractSystem.sign_contract`).
- Une continuation de ligne exige un `\` explicite, y compris dans une lambda.
- Une variable `:=` ne peut pas inférer depuis une valeur non typée (retour de
  `Node.get()`, itération sur un `Array` non typé) : annoter le type.
- Une erreur d'exécution dans `_initialize()` d'un `SceneTree` ne fait pas
  planter le processus : il tourne indéfiniment. Toujours lancer les scripts
  headless avec un `timeout`.

## Vérifier l'interface pour de vrai
Un test qui dit « l'écran se construit sans erreur » ne prouve RIEN sur son
apparence : c'est exactement comme ça qu'un tableau entièrement superposé est
passé entre les mailles. Deux outils complémentaires :

```bash
# 1. Invariants de mise en page (headless, rapide, dans check_all.sh)
godot --headless --path . --script res://tools/ui_check.gd

# 2. Captures d'écran réelles de chaque écran (ouvre une fenêtre)
godot --path . -- --shots=all
godot --path . -- --shots=squad,finance      # sous-ensemble
```
Les PNG sont écrits dans `user://shots/` et le chemin absolu est imprimé.
**Après toute modification visuelle, regarder les captures.**
