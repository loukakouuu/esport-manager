# Esport Manager — contexte du projet

## Vue d'ensemble
Jeu de gestion de **structure esport** façon Football Manager, développé en solo
avec Claude Code. Le joueur dirige une organisation : il recrute, entraîne,
négocie des sponsors, gère une trésorerie, et suit ses matchs sous forme de
simulation textuelle round par round — **aucun rendu 3D du match**.

Trois partis pris fondateurs :

1. **On dirige une STRUCTURE, pas une équipe.** L'organisation porte la
   trésorerie et la marque ; elle possède un ou plusieurs rosters. Ce n'est
   plus une promesse : une maison peut tenir un roster Valorant ET un roster
   Counter-Strike sur un seul grand livre, avec deux effectifs, deux bancs,
   deux championnats et une seule direction.
   `Organization.games` déclare les disciplines de la maison, y compris celles
   que le moteur ne simule pas encore : elles s'affichent comme sections non
   simulées plutôt que d'être passées sous silence.
   **Invariant vérifié** (`tools/discipline_probe.gd`, `Cs2Tests`) : une
   discipline déclarée ET simulée a toujours une équipe, une équipe a toujours
   sa discipline déclarée, et un joueur appartient toujours à la discipline de
   son équipe et à la structure de son contrat.
2. **La finance est un vrai système, pas un compteur.** Toute somme d'argent
   passe par une écriture comptable dans un grand livre. Le compte de résultat
   affiché au joueur est littéralement la somme de ce que le moteur a dépensé.
3. **Un effectif n'est pas une addition de notes.** Cinq joueurs à 150 de CA qui
   se détestent perdent contre cinq joueurs à 135 qui se comprennent. Le
   vestiaire, les promesses de temps de jeu et l'entraînement sont des systèmes
   à part entière, pas de la décoration.

Disciplines simulées : **VALORANT** et **COUNTER-STRIKE 2**. L'architecture
multi-jeu (`src/gamemodules/`) n'est plus une intention : deux modules
cohabitent, chacun avec ses postes, ses attributs, son économie de round, son
calendrier et ses statistiques.

**Counter-Strike n'est pas un habillage de Valorant.** Ce qui le distingue, et
qui doit le rester :
- **l'AWP** vit dans l'ÉCONOMIE du match (`Cs2Side.has_awp`), pas dans un
  attribut : 4 750 $, une seule paire de mains, perdue si son porteur tombe ;
- **toutes les cartes sont CT-sided** (`data/games/cs2/maps.json`) ;
- **bonus de défaite jusqu'à 2 900 $ et bombe posée payée même en perdant** :
  une équipe menée peut refaire son économie sans gagner un round ;
- **subventions de ligue trois fois plus faibles, dotations de tournoi bien
  plus grosses** : une écurie CS vit de ses résultats, une écurie Valorant de
  son slot. C'est le seul vrai arbitrage économique entre les deux sections ;
- **ADR et KAST** au lieu de l'ACS, avec ses propres références de note.

## Stack
- **Moteur** : Godot 4.7 · **Langage** : GDScript
- **Sauvegarde** : JSON compressé (gzip) sous `user://saves/`, avec numéro de
  schéma et fonction de migration (`src/save/SaveGame.gd`)
- **Tests** : headless, sans éditeur ni scène (`tools/run_tests.gd`)
- **Versioning** : Git

## Structure du dépôt
```
res://
├── data/                      Contenu éditable sans toucher au code (FICTIF)
│   ├── games/valorant/        maps.json, agents.json
│   ├── games/cs2/             maps.json, weapons.json
│   └── world/                 sponsors.json, names.json, et par discipline :
│                              orgs.json + season_valorant.json (Valorant, noms
│                              historiques), orgs_cs2.json + season_cs2.json
├── packs/vct_2026/            Pack livré : vraies structures et vrais joueurs,
│                              dans les DEUX disciplines — orgs.json +
│                              rosters.json (Valorant, Liquipedia) et
│                              orgs_cs2.json + rosters_cs2.json (Counter-Strike,
│                              classement mondial HLTV)
│                              (voir docs/DATA_PACKS.md — dépôt privé)
├── src/
│   ├── core/                  Money, Rng, GameDate, Ids, Log, DataFile, DataPack
│   ├── model/                 Entités pures et sérialisables (World, Player,
│   │   │                      Organization, Roster, Competition, Fixture…)
│   │   │                      + calculs purs : AbilityCalc, RoleFamiliarity,
│   │   │                      PersonalityCalc, PlayingTime, Attributes
│   │   └── finance/           Ledger, Transaction, SponsorDeal, Loan
│   ├── gamemodules/           GameCatalog (disciplines connues), GameModule
│   │                          (interface) + implémentations valorant/ et cs2/
│   ├── systems/               Toute la logique de simulation (sans état propre)
│   ├── save/                  Sauvegarde et migrations
│   ├── ui/                    UiKit, Typography, App, Screen, widgets/, screens/
│   └── tests/                 Suites de tests
├── autoload/Game.gd           Façade unique entre l'UI et le moteur
├── scenes/Main.tscn           Scène de lancement
├── tools/                     Scripts headless (tests, saison, écrans, import)
└── tools/hltv/                Instantané daté du classement mondial HLTV, la
                               SOURCE du circuit Counter-Strike du pack, plus
                               la marche à suivre pour le rafraîchir
```

## Règles d'architecture (non négociables)

1. **Le World ne contient que des données.** Aucune méthode de simulation dans
   `src/model/`. La logique vit dans `src/systems/`, sous forme de fonctions
   `static` qui prennent le World en paramètre. Conséquences : la sauvegarde
   est un `to_dict()`, et chaque système est testable isolément.
   *(Exception assumée : les calculs purs d'un seul objet — `AbilityCalc`,
   `RoleFamiliarity`, `PersonalityCalc` — vivent dans `model/` parce qu'ils ne
   touchent pas au monde.)*
2. **L'UI ne touche jamais un système.** Elle passe par l'autoload `Game`, qui
   exécute puis émet un signal. Un écran ne peut donc pas casser la simulation.
3. **Les systèmes ne connaissent pas l'UI.** Aucun `UiKit` dans `src/systems/`,
   `src/model/`, `src/gamemodules/`, `src/core/`. Un système qui veut dire
   quelque chose au joueur écrit une phrase, pas des étoiles.
4. **Tout l'aléa passe par `Rng`.** Aucun appel à `randi()`/`randf()` global
   dans la logique. Une partie est rejouable à l'identique, et l'équilibrage se
   compare à graine égale.
5. **L'argent est un entier de cents.** Jamais de float. Voir `src/core/Money.gd`.
6. **Le temps est un index de jour entier** (`src/core/GameDate.gd`), jamais un
   objet date.
7. **Rien de spécifique à une discipline hors de son dossier
   `src/gamemodules/<jeu>/`.** Le reste du moteur ne connaît que l'interface
   `GameModule` — et l'interface est le seul endroit où l'on ajoute quelque
   chose quand une discipline a besoin de dire une chose de plus.
   Y sont passés, à l'arrivée de CS2 : les curseurs tactiques
   (`tactic_sliders`), le pool de cartes (`map_pool`), les attributs qui
   déclinent ou vieillissent bien (`declining_attributes` /
   `ageing_attributes`), la composition générée (`generated_lineup`), le nom
   des camps (`side_label`) et les chemins de données
   (`season_path`, `orgs_path`, `rosters_path`).
   *Contre-exemple à ne pas refaire* : `ProgressionSystem` listait en dur des
   constantes `ValorantModule.*` pour le déclin lié à l'âge. Un AWPeur y
   perdait sa lecture de jeu et gardait son AWP.
8. **Aucun contenu en dur.** Maps, agents, structures, sponsors, prénoms et
   format des compétitions sont dans `data/`, et remplaçables par un pack
   (voir `src/core/DataPack.gd` et `docs/DATA_PACKS.md`).
9. **Un écran ne mémorise rien.** Il est détruit et reconstruit à chaque
   rafraîchissement. Onglet actif, tri, filtre : tout passe par
   `App.view_state`, exposé aux écrans par `Screen.ui(clé)`.
10. **Un écran d'équipe passe par `Game.my_roster()`, jamais par
    `main_roster()`.** Une structure a plusieurs équipes et le joueur choisit
    laquelle il dirige (`World.player_roster_id`). Un écran qui rappelle
    `main_roster()` affiche l'équipe principale quoi qu'il arrive, et la
    bascule de section devient décorative sans qu'aucun test ne s'en plaigne.
    Les *systèmes*, eux, ont le droit d'appeler `main_roster()` : ils
    raisonnent sur une structure, pas sur ce que regarde le joueur.
11. **Une discipline connue n'est pas une discipline jouable.**
    `GameCatalog` liste ce que le jeu sait nommer, `GameRegistry` ce qu'il sait
    simuler. Seul `GameRegistry` crée des rosters, des matchs et des
    compétitions.
12. **Un poste de BANC appartient à une ÉQUIPE, pas à la maison.**
    `StaffSystem.TEAM_ROLES` (entraîneur, analyste, adjoint) se recrute autant
    de fois que la structure aligne de sections, et `holder()` veut un
    `roster_id` pour ces postes-là. Sans ça, la section Counter-Strike d'une
    maison paraîtrait avoir l'entraîneur de sa section Valorant tout en jouant
    à 8/20 de tactique. Les autres postes servent toute la maison et n'ont pas
    de discipline (`Staff.game_id` vide).

## Direction artistique
Habillage de **diffusion esport** : fond très sombre, panneaux étagés, titres en
capitales condensées, couleur de la structure portée par des bandeaux inclinés.

Une règle gouverne tout le reste :
**le spectacle vit sur les surfaces d'apparat, jamais dans les données.**
Écran-titre, barre haute, en-têtes d'écran, cartouche de joueur : bandeaux,
lueurs, grandes capitales. Un tableau de dix-huit colonnes reste sobre — fond
calme, couleur réservée à la donnée. Un classement qui brille est un classement
qu'on ne lit plus, et un jeu de gestion se lit trois heures d'affilée.

- **Polices** : `src/ui/Typography.gd`, seul endroit qui les nomme. Trois rôles
  jamais mélangés — DISPLAY (Bahnschrift, condensée) pour les titres et les
  capitales, BODY (Segoe UI, avec un vrai gras) pour la lecture, MONO (Consolas)
  pour tout nombre EMPILÉ sous un autre. Elles viennent du système ; passer à des
  .ttf embarqués ne touche que ce fichier. Le thème est posé une fois à la racine
  dans `App._build_shell()` : il descend dans les contrôles qu'on ne construit
  pas soi-même (info-bulles, listes déroulantes).
  **Ne jamais simuler un gras par un contour** — c'était le cas avant, et c'est
  ce qui rendait chaque titre légèrement flou.
- **Bandeaux** : `src/ui/widgets/Banner.gd`. C'est un `MarginContainer` qui peint
  derrière son unique enfant — il met donc en page ET décore, sans empiler quoi
  que ce soit (voir l'invariant du `PanelContainer` plus bas). Son inclinaison
  est PLAFONNÉE (`SLANT_MAX`) : proportionnelle à la hauteur sans plafond, elle
  traversait une grande carte en diagonale et barrait le texte.
- **Fond** : `src/ui/widgets/Backdrop.gd` — dégradé, deux halos (un chaud, un
  froid) et vignettage, en trois quads et sans aucune texture importée. Un aplat
  de couleur unie est ce qui date le plus une interface.
- **Pas de trait d'un pixel partout.** C'est la signature du formulaire des
  années 90. `UiKit.soft()` (utilisé par `panel()`) rend la bordure presque
  invisible et confie la séparation à l'OMBRE — ce que fait un objet posé sur un
  autre.
- **Panneau cliquable** : `UiKit.clickable()`. Godot n'offre rien de tel (un
  Button ne met pas ses enfants en page, un PanelContainer n'écoute pas la
  souris). Rendre la CARTE ENTIÈRE cliquable, et pas seulement son bouton, est
  ce qui sépare un formulaire d'un jeu : on vise une grande forme.
- **En-tête d'écran** : toujours `Screen.page_header()`, jamais un
  `UiKit.title()` posé nu. Il teinte le bandeau avec la couleur de la structure
  dirigée, ce qui relie les dix-neuf écrans entre eux.
- **Couleur d'une structure** : `UiKit.org_color(o)`, qui lit le `color_primary`
  de la marque. Ne pas revenir à `color_from_id()` — c'est un hachage, il ignore
  la couleur choisie par le joueur qui fonde sa structure comme celles du pack.
- **Profondeur** : `UiKit.raised()` (ombre + filet clair) pour ce qui doit
  attirer l'œil en premier. Tout étager revient à ne rien étager.
- **Majuscule initiale** : `UiKit.sentence()`, jamais `String.capitalize()` de
  Godot, qui met une majuscule à CHAQUE mot et transforme une phrase française
  rédigée par le moteur en titre à l'anglaise.
- **Transitions** : fondu de 120 ms à l'entrée d'un écran (`App._play_enter`).
  `App.transitions` est mis à `false` par DevShots — une capture prise au milieu
  d'un fondu n'est pas reproductible, et c'est toute la valeur des captures.

## Le parcours d'entrée
Trois écrans, une question chacun — c'est la règle qui les tient :

1. **StartScreen** : reprendre, ou commencer ? Les parties en cours d'abord, en
   cartes à écusson (façon Football Manager) ; puis deux grands rectangles
   cliquables ENTIÈREMENT (`UiKit.clickable`) pour le mode ; l'univers en
   pastilles tout en bas.
   **Plus aucune graine à l'écran** : elle existe toujours (c'est elle qui rend
   une partie rejouable et l'équilibrage comparable) mais elle est tirée au sort
   à la création du monde. La demander au joueur revenait à exposer un rouage de
   développement dans la vitrine. Les outils headless continuent de la fixer.
   **Ne pas remettre d'`OptionButton` ici** : il porte le dessin du système
   d'exploitation — flèche grise, cadre carré — et c'est ce qui trahit un jeu.
2. **NewGameScreen** : quelle STRUCTURE ? Une grille de cartes portant écusson
   et couleur de marque, pas un tableau. On choisit une identité, pas la plus
   grosse trésorerie.
   La navigation est un **filtre, pas une arborescence** : un étage
   (deuxième division / élite), une région, et une recherche par nom ou sigle.
   *Ne pas revenir au ruban d'onglets de ligue* qu'il y avait avant — huit
   chips de codes (« CHAL CN », « PRO PAC »), une seule ligue visible à la
   fois, et aucun moyen de trouver une structure sans deviner sa région. La
   recherche traverse les quatre régions d'un coup, et c'est elle qui fait la
   différence quand le monde compte 96 maisons reprenables.
   Le barème de difficulté se calcule sur TOUT l'étage, jamais sur les seules
   cartes affichées : sinon filtrer sur une région ferait de sa lanterne rouge
   une reprise « confortable », et taper dans la recherche ferait changer une
   structure de difficulté sous le curseur.
3. **FoundScreen** : sa propre marque, si on a choisi de fonder.

L'attribution Liquipedia (CC-BY-SA) doit rester affichée sur StartScreen quel
que soit l'univers actif : c'est une obligation de licence, pas une décoration.

## Le tableau de bord (écran d'accueil)
Deux règles, et elles valent pour tout écran de synthèse qu'on ajouterait :

1. **Rien de ce qui est déjà dans la barre haute.** Date, trésorerie et résultat
   mensuel y sont en permanence. L'accueil les répétait en gros : un sixième de
   l'écran pour zéro information. La place va à ce qu'on ne voit nulle part
   ailleurs — classement réel, cohésion, vestiaire, autonomie.
2. **Tout ce qui est affiché est une PORTE.** Une ligne « Emberko — douleur à
   l'épaule » qu'on ne peut pas cliquer oblige à traverser le menu pour
   retrouver Emberko. Chaque tâche, chaque rencontre, chaque message mène d'un
   clic là où on agit. C'est tout ce que veut dire « fluide ».

La liste de tâches (`HomeScreen._collect_tasks`) est le cœur de l'écran : elle
recense blessures, départs demandés, épuisement, griefs, fins de contrat, cinq
incomplet, entraîneur manquant, trésorerie courte, offres de sponsor et messages
non lus — chacun avec SA destination. Le tri est stable (rang composé urgence ×
1000 + ordre de découverte) : une liste qui se réordonne sous le curseur entre
deux rafraîchissements est pénible à cliquer.

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

# Écrans : deux états du monde × tous les onglets, plus les invariants
bash tools/check_ui.sh

# Simulation d'une saison complète + rapport d'équilibrage
godot --headless --path . --script res://tools/season.gd

# Cohérence multi-disciplines : invariants, notes, santé des structures
# Sans --pack : l'univers fictif. Avec : celui que le joueur obtient par défaut.
godot --headless --path . --script res://tools/discipline_probe.gd
godot --headless --path . --script res://tools/discipline_probe.gd -- --pack=vct_2026

# Reconstruire le circuit Counter-Strike du pack depuis le classement HLTV
# (ne télécharge rien : voir tools/hltv/README.md)
godot --headless --path . --script res://tools/import_hltv.gd

# Captures d'écran réelles (ouvre brièvement une fenêtre)
godot --path . -- --shots=all
godot --path . -- --shots=squad,player

# Lancer le jeu
godot --path .
```
Après avoir ajouté un fichier avec `class_name`, il faut réindexer une fois :
`godot --headless --path . --editor --quit` (c'est ce que font `tools/test.sh`
et `tools/check_ui.sh`).

## État actuel
Fait :
- [x] Noyau : argent en cents, RNG déterministe, calendrier, chargement de données
- [x] Modèle de données complet et sérialisable
- [x] Module Valorant : rôles, attributs, agents, maps, tactiques
- [x] Module Counter-Strike 2 : postes (AWPeur, entry, soutien, lurker,
      rifleur), attributs propres (sniping, lurk), maîtrise d'armes, maps
      CT-sided, économie CS2, MR12 et prolongations MR3, ADR/KAST
- [x] Simulation de match round par round avec économie officielle, veto de maps,
      momentum, temps morts, clutchs, statistiques individuelles et notes
- [x] Génération du monde : 188 structures, ~1 560 joueurs, 4 régions,
      226 équipes — dont 38 maisons qui tiennent deux sections
- [x] Pyramide compétitive à trois étages PAR DISCIPLINE : côté Valorant
      VCT + Challengers + Circuit ouvert, Masters, Champions, Ascension et
      barrages ; côté Counter-Strike Pro League + Challenger League + Circuit
      ouvert, deux Majors à phase suisse, un Intercontinental et les barrages
      de montée. Formats round robin / poules / double élimination / suisse
- [x] Finances : grand livre, sponsors, subventions, merch, contenu, salaires,
      charges sociales, infrastructures, emprunts, impôt, faillite
- [x] Contrats, clauses de rachat, marché des joueurs, IA de recrutement
- [x] Progression, courbe d'âge, blessures, burnout, moral, retraites
- [x] Relève annuelle : promotions d'académie et vivier libre
- [x] Scouting à information imparfaite + rapport d'observation rédigé
- [x] Aisance par poste, personnalité déduite, historique de développement
- [x] Entraînement : programme collectif hebdomadaire + travail individuel
- [x] Vestiaire : influence, affinités, clans, conflits, griefs, conversations
- [x] Direction : objectifs de saison et confiance
- [x] Sauvegarde/chargement avec migration de schéma
- [x] Packs de données remplaçables + importateurs Liquipedia et HLTV
- [x] Pack « Saison 2026 » livré et actif par défaut, sur les DEUX
      disciplines : 48 structures et ~190 joueurs réels côté Valorant
      (Liquipedia), 76 écuries et 373 joueurs réels côté Counter-Strike
      (classement mondial HLTV), plus les sections des autres disciplines.
      Le circuit CS apporte en plus une VRAIE HIÉRARCHIE — voir plus bas
- [x] Écran de démarrage à deux modes, tous deux jouables : *reprendre une
      structure* et *fonder la sienne*
- [x] Fondation : entrée par le Circuit ouvert, effectif entièrement à
      composer, capital échangé contre la patience de la direction
- [x] Structure multi-sections : bascule d'équipe, écran Structure
- [x] Négociation de contrat clause par clause, avec patience de l'agent
- [x] Marché de l'encadrement : neuf postes, un organigramme qui dit ce que
      chacun change dans le moteur, embauche, prolongation, licenciement ;
      l'IA gère le sien sur enveloppe par poste
- [x] Interface complète (19 écrans, 33 vues, balayées sur TROIS états du monde
      — reprise, fondation, et maison à deux sections dirigée côté CS2)
- [x] Fondation d'une structure sur la discipline de son choix

Pas encore fait, volontairement :
- [ ] Les disciplines autres que Valorant et Counter-Strike 2 (annoncées, non
      simulées)
- [ ] Fenêtres de mercato : les mouvements sont possibles toute l'année
- [ ] Attributs tirés de données publiques. La note HLTV d'un joueur EST
      publique, mais la convertir serait un modèle de plus : un pack apporte
      l'identité, le moteur fait la simulation.

Prochaines étapes suggérées : voir `docs/ROADMAP.md`.

## Vérifications avant de committer
```bash
bash tools/check_all.sh    # tests + écrans + saison + cohérence multi-jeux
```
Tout doit passer : 566 vérifications unitaires, 99 vues d'écran construites sans
violation d'invariant, une saison qui se termine avec des classements et des
finances cohérents dans les DEUX disciplines, et la sonde
`tools/discipline_probe.gd` sans aucun « KO » sur les DEUX univers — le fictif
et celui du pack.

Compter environ quatre minutes : depuis que les championnats jouent vraiment
toute leur saison, qu'il y en a deux et que les deux univers sont mesurés, une
saison complète représente ~3 200 séries (~50 s) au lieu de 825, et il y en a
trois à jouer.

## Deux bugs de compétition corrigés en ajoutant Counter-Strike

Ils étaient là avant, et ils ne se voyaient pas : la saison se terminait, les
classements s'affichaient, aucun test ne criait. C'est la deuxième discipline
qui les a rendus visibles — les ligues de Counter-Strike n'ont pas la même
taille que celles du VCT, et c'est ce qui a fait sortir les deux.

1. **Un championnat ne repartait pas de toutes ses équipes.** Le `qualifiers`
   d'une phase de playoffs dit combien d'équipes partent en tournoi
   international ; `CompetitionEngine._seed_next` le lisait comme « combien
   d'équipes continuent la saison ». Résultat mesuré : après les playoffs du
   Kickoff, le VCT EMEA ne comptait plus que DEUX équipes pour ses Stage 1 et
   Stage 2, et les deux tiers de chaque championnat n'étaient jamais joués.
   Une phase régulière de championnat repart désormais de `comp.participants`.
   Seules les phases à élimination héritent d'un classement.
   *C'est ce correctif qui fait passer une saison de 825 à ~3 200 séries.*

2. **Un arbre à taille non-puissance-de-deux gelait la compétition.** Les
   rencontres « équipe A contre personne » n'étaient jamais prêtes
   (`Fixture.is_ready`), donc jamais jouées, donc la phase ne se terminait
   jamais et la compétition restait figée jusqu'à la fin de la saison. Invisible
   en Valorant, dont les arbres reçoivent toujours huit qualifiés pile ; fatal
   pour une ligue CS à six équipes. `CompetitionEngine._resolve_byes` traite les
   exemptions du premier tour — qui ne créditent ni victoire au classement ni
   ligne au bilan de saison : elles font avancer, c'est tout.

## Pièges connus de Godot rencontrés sur ce projet
- **`PanelContainer`, `MarginContainer`, `ScrollContainer` et `CenterContainer`
  EMPILENT leurs enfants** dans le même rectangle. Y ajouter plusieurs contrôles
  les superpose au lieu de les aligner — le bug ne plante pas, il rend l'écran
  illisible. Toujours mettre UN seul enfant (une `HBoxContainer`/`VBoxContainer`)
  et ajouter dedans. `tools/ui_check.gd` vérifie cet invariant.
- **Un `ScrollContainer` dimensionne son enfant d'après les `SIZE_EXPAND` de
  L'ENFANT, pas les siens.** Sur un axe où le défilement est désactivé, un
  enfant sans `SIZE_EXPAND` retombe à sa taille minimale : le contenu disparaît
  sans la moindre erreur. `tools/ui_check.gd` vérifie aussi cet invariant.
- **Deux `ScrollContainer` imbriqués sur le même axe** : l'extérieur donne à
  l'intérieur sa taille MINIMALE, soit zéro, et le contenu disparaît. Comme
  `UiKit.data_table` défile déjà tout seul, ne jamais l'emballer dans un
  `UiKit.scroll`. `tools/ui_check.gd` vérifie aussi cet invariant — l'axe seul
  compte, l'imbrication horizontal/vertical restant légitime.
- `Side`, `sign`, `Color`, `_get` : noms réservés par Godot. Ne pas nommer une
  classe, une fonction statique ou une méthode comme un symbole global
  (`ContractSystem.sign_contract`, `_api_get` et non `_get`).
- Un `HTTPRequest` doit être **dans l'arbre** avant sa première requête, et
  `add_child()` ne prend effet qu'à la trame suivante : `await process_frame`.
- Une continuation de ligne exige un `\` explicite, y compris dans une lambda.
- Une variable `:=` ne peut pas inférer depuis une valeur non typée (retour de
  `Node.get()`, itération sur un `Array` non typé, littéral indexé) : annoter.
- Une erreur d'exécution dans `_initialize()` d'un `SceneTree` ne fait pas
  planter le processus : il tourne indéfiniment. Toujours lancer les scripts
  headless avec un `timeout`.

## Vérifier l'interface pour de vrai
Un test qui dit « l'écran se construit sans erreur » ne prouve RIEN sur son
apparence : c'est exactement comme ça qu'un tableau entièrement superposé est
passé entre les mailles, puis qu'un corps de tableau invisible est passé une
deuxième fois. Trois niveaux, du moins cher au plus sûr :

```bash
# 1. Invariants de mise en page, tous les onglets de tous les écrans
bash tools/check_ui.sh

# 2. Captures d'écran réelles, un PNG par onglet
godot --path . -- --shots=all
godot --path . -- --shots=squad,finance

# 3. Jouer.
```
Les PNG sont écrits dans `user://shots/` et le chemin absolu est imprimé.
**Après toute modification visuelle, regarder les captures.** Un invariant
attrape une faute de structure, jamais une faute de goût.

## Équilibrage — repères à ne pas casser
Ces valeurs ont été mesurées, pas devinées. Une modification qui les déplace
doit être intentionnelle.

| Grandeur | Repère |
| --- | --- |
| Progression 17-18 ans | +9 de CA par saison en moyenne |
| Progression 19-20 ans | +6 |
| Progression 21-23 ans | +2 |
| Déclin 26 ans et plus | −6 |
| Usure mentale, programme équilibré | ~15 en fin de saison |
| Usure mentale, scrims à fond sans repos | ~75 |
| Moral d'un joueur correctement traité | gravite autour de 60 |
| Population du monde | fictif ~1 560 joueurs (941 VAL, 620 CS2) · pack ~1 474 (921, 553) |
| Équipes | fictif 226 (136 VAL, 90 CS2) dans 188 structures · pack 224 (136, 88) dans 207 |
| Note moyenne d'un match | 1.00 dans CHAQUE discipline (mesuré 1.02 / 1.01) |
| Victoire à niveau égal | 50 % |
| Rounds par carte | ~21 en Valorant, ~21 en CS2 |
| Prolongations | 13 % en Valorant, 10 % en CS2 |
| Cartes à dix rounds d'écart | 9 % en Valorant, 16 % en CS2 (voulu) |
| Maisons à deux sections | fictif 38 dont 87 % solvables · pack 17 dont 88 % |
| Dépôts de bilan sur une saison | fictif 12 % · pack 17 %, toujours concentrés sur les circuits ouverts |
| Podiums internationaux CS2 (8 premiers × 3 tournois) | EMEA 9 · Amériques 6 · Pacifique 5 · Chine 4 |
| Écart de réputation dans une ligue d'élite | rapport 1,1 à 1,45 (maisons à une seule section) |
| Réputation médiane, étage 1 / 2 / 3 | ~6 500 / ~2 300 / ~640 |
| Négociation, jeu brutal (salaire seul, +9 %/tour) | 80 % de signatures, 4,3 tours, 95 % du prix demandé |
| Négociation, jeu avisé (clause de rachat basse, part des gains) | 100 %, 3,7 tours, 91 % du prix demandé |
| Encadrement, coachs fantômes après 3 saisons | 0, toujours (`tools/staff_probe.gd`) |
| Encadrement, taille moyenne après 3 saisons | ~5 personnes par structure, note ~11 |
| Encadrement, structures solvables sans entraîneur | ≤ 3 % à un instant donné (délai de recrutement) |
| Salaires du staff, structure de Challengers | ~13 % des recettes (bande visée : 10-20 %) |

L'écart entre les deux lignes de NÉGOCIATION EST le système : s'il se referme,
c'est que les clauses non monétaires ont cessé de compter et qu'il ne reste
qu'un portefeuille. Le mesurer :
`godot --headless --path . --script res://tools/negotiation_probe.gd`

La ligne des COACHS FANTÔMES vaut zéro par construction : un encadrant n'est
rattaché que par `StaffSystem.attach()` et détaché que par
`StaffSystem.detach()`. Le jour où un autre fichier écrit `head_coach_id`, un
roster gardera un entraîneur qu'il ne paie plus — c'était le cas de 136
structures sur 136 avant cette version. Le mesurer :
`godot --headless --path . --script res://tools/staff_probe.gd`

La ligne des CARTES À DIX ROUNDS D'ÉCART est plus haute en Counter-Strike, et
c'est voulu : des cartes toutes CT-sided plus une économie qui punit deux fois
le même demi-buy produisent des mi-temps à sens unique. Si cet écart se
refermait sur celui de Valorant, c'est que le biais de camp ou le poids de
l'économie auraient cessé de compter, et les deux disciplines se joueraient
pareil.

La ligne des DÉPÔTS DE BILAN doit rester concentrée sur les circuits ouverts :
c'est le bas de la pyramide, il est fait pour être fragile. Le jour où elle
remonte dans les étages 1 et 2, c'est qu'une discipline n'est plus finançable —
`tools/discipline_probe.gd` l'imprime ligue par ligue. Le critère est bien la
CONCENTRATION et pas le pourcentage : 36 des 37 faillites du pack sont dans un
circuit ouvert, zéro à l'étage 1.

L'univers du PACK est plus dur que le fictif (17 % contre 12 %), et il l'était
déjà avant que Counter-Strike y soit réel — 16 % mesurés sans le circuit HLTV.
La raison est dans les données, pas dans un réglage : le monde fictif a été
écrit avec 38 maisons à deux sections, dont la section CS vit sur la trésorerie
de la section Valorant. Le monde réel n'en a que 17, parce que la plupart des
écuries de Counter-Strike n'ont pas de slot VCT. Une écurie CS seule, en bas de
pyramide, est un commerce fragile — dans le jeu comme dehors.

La ligne de l'ÉCART DE RÉPUTATION est celle qui dit si la MARQUE est encore
tirée au dé. La réputation de départ venait de `pow(strength/100, 2.8)`, et
`strength` est un tirage pour tout pack qui ne déclare pas de hiérarchie — ce
que le pack Valorant ne PEUT pas faire, faute de donnée publique. Le jeu
désignait donc au hasard la plus grosse marque du monde : Nova Esports passait
devant Spirit, NAVI, FaZe et MOUZ, et l'écart dans une même ligue atteignait
2,4. Elle vient désormais du PRESTIGE DE LA LIGUE où la structure a son slot
(`WorldGenerator._brand_for`) : un slot en ligue partenaire EST la marque, et
c'est ensuite le palmarès qui la fait bouger. Si le rapport remonte au-delà de
1,6, c'est que le dé a repris la main. La mesure exclut les maisons à
plusieurs sections : leur prime de marque est légitime — tenir deux rosters
fait bien une maison plus grosse — et la mêler au reste masquerait
précisément ce qu'on cherche.

**Ne pas toucher à `BRAND_CURVE` ni à `_fanbase_for` sans remesurer les
faillites.** La réputation ouvre les paliers de sponsors et multiplie les
recettes de merchandising : la première version de ce correctif relevait la
réputation du circuit ouvert de 39 %, et ça suffisait à faire tomber les
dépôts de bilan de 18 % à 2 % et la masse salariale d'une structure de 54 % à
34 % de ses recettes. Un monde où plus personne ne coule n'a plus d'enjeu — la
cambrure entre étages est ce qui tient les deux bouts.

La ligne des PODIUMS INTERNATIONAUX est née avec le pack HLTV, et c'est elle
qui garde son apport principal. Les étages de la pyramide CS sont RELATIFS à
leur région — sans quoi la Pro League chinoise n'aurait que deux équipes
réelles — mais la FORCE, elle, vient du rang mondial. Le dégradé
EMEA > Amériques > Pacifique > Chine est donc ce qui prouve que l'écart mesuré
par HLTV a survécu au découpage. S'il s'aplatissait, un Major se jouerait à
pile ou face et le classement n'aurait servi à rien.
