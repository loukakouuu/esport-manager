# Feuille de route

Le socle est posé et jouable de bout en bout. Cette liste est ordonnée par
**rapport valeur / effort**, pas par ordre d'envie. Chaque entrée précise les
fichiers concernés pour pouvoir être attaquée isolément.

---

## Livré depuis la version précédente

Ces entrées étaient en priorité 1 et 2 ; elles sont faites.

- **Réunions et retours du vestiaire** → `DynamicsSystem`, `InteractionSystem`,
  `DynamicsScreen`, onglet *Vestiaire* de la fiche joueur. Griefs nommés,
  influence, affinités, clans, conflits, conversations où le ton compte.
- **Académie** → `YouthSystem`. Promotions annuelles pondérées par
  l'infrastructure `ACADEMY` et le coach, plus un vivier libre.
- **Entraînement hebdomadaire dirigé** → `TrainingSystem` v2 et
  `TrainingScreen`. Dix créneaux, travail individuel, intensité par joueur.
- **Interface** → `UiKit` refondu, coquille à barre haute permanente,
  navigation groupée, tableaux triables, onglets, radar et courbes.
- **Packs de données** → `DataPack`, `tools/import_liquipedia.gd`,
  `docs/DATA_PACKS.md`. Chaîne de résolution à trois niveaux, pack livré dans
  le dépôt (qui est privé), pack utilisateur prioritaire.
- **Écran de démarrage à deux modes** → `StartScreen`. *Reprendre une
  structure* est complet ; *fonder la sienne* est affiché verrouillé.
- **Structure multi-sections** → `GameCatalog`, `Organization.games`,
  `World.player_roster_id`, `ClubScreen`, barre de sections dans `App`. Une
  structure aligne ses disciplines réelles ; seules celles que `GameRegistry`
  simule donnent une équipe.
- **Négociation de contrat interactive** → `Negotiation`, `NegotiationSystem`,
  `NegotiationScreen`, sonde `tools/negotiation_probe.gd`. Six clauses qui se
  compensent, des goûts qui dépendent du caractère, une patience qui s'use et
  un prix de réserve. Mesuré : 80 % de signatures en jouant brutalement,
  100 % en lâchant ce qui ne coûte rien tout de suite.
- **Mode « fonder sa structure »** → `FoundScreen`, `WorldGenerator.found_org`,
  et un troisième étage de pyramide dans `season_valorant.json` : quatre
  Circuits ouverts et quatre barrages vers les Challengers. On démarre sans
  joueur, sans sponsor et sans place garantie ; le capital choisi s'échange
  contre la patience de la direction.

---

## Priorité 1 — Rendre la boucle de jeu plus riche sans nouveau système

### 1.2 Consignes de match et temps morts pilotés
Le simulateur gère déjà les temps morts et le momentum côté IA. Laisser le
joueur les déclencher pendant l'affichage du match transforme le compte rendu
en vraie expérience.
*Fichiers : `ValorantSim` (points d'interruption), `MatchScreen`.*

### 1.3 Écran d'académie
`YouthSystem` produit les jeunes et `Roster.is_academy` existe, mais il n'y a
pas d'écran pour suivre une promotion, comparer une génération ou décider qui
monte. Peu de code, beaucoup de plaisir.
*Fichiers : nouvel écran, `YouthSystem` (exposer la dernière promotion).*

### 1.4 Postes réels dans les packs importés
L'importateur ne récupère pas le poste des joueurs : Liquipedia ne le publie
pas de façon exploitable dans le wikitexte. Les quatorze équipes qui utilisent
`{{ActiveSquadAuto}}` n'ont pas non plus d'effectif. Deux pistes : `action=parse`
sur les pages d'équipe pour lire le tableau rendu, ou la clé d'API LPDB v3.
Les *sections* par discipline, elles, sont désormais importées (portails
`Portal:Teams` de chaque wiki).
*Fichiers : `tools/import_liquipedia.gd`.*

---

## Priorité 2 — Profondeur de gestion

### 2.1 Recrutement du staff
Le staff est généré au démarrage et jamais renouvelé. Il manque un marché du
staff symétrique à celui des joueurs — d'autant que le coach pèse maintenant
sur la progression, la cohésion ET les promotions d'académie.
*Fichiers : `StaffFactory`, `TransferSystem`, écran staff.*

### 2.2 Rapports de scouting
Envoyer un recruteur observer un joueur ou une ligue pendant N semaines, ce qui
fait monter le niveau de connaissance. `ScoutingSystem.knowledge()` est déjà la
seule porte d'entrée et `ScoutingSystem.report()` produit déjà le texte : il
suffit d'ajouter une source explicite et une file d'affectations.

### 2.3 Presse et image
Conférences de presse, déclarations, réactions des joueurs. `fanbase` et
`reputation` existent déjà, et `Attributes.CONTROVERSY` n'est utilisé nulle
part : il manque les événements qui les font bouger autrement que par les
résultats.

### 2.4 Fenêtres de mercato
Les mouvements sont possibles toute l'année, ce qui vide de son sens la
planification d'une saison.
*Fichiers : `ContractSystem`, `TransferSystem`.*

---

## Priorité 3 — Le multi-jeu

C'est l'objectif structurant du projet, et l'architecture est prête. Ordre
recommandé :

1. **CS2** — même genre que Valorant (FPS à rounds et économie). Le simulateur
   se dérive de `ValorantSim` avec MR12, une économie différente et pas
   d'agents. Coût estimé : faible.
2. **Rocket League** — équipes de 3, pas de rounds, format en buts. Valide que
   l'abstraction `GameModule` tient hors du modèle « rounds ». Coût moyen.
3. **League of Legends** — genre radicalement différent (draft, objectifs,
   courbe de partie). C'est le vrai test de l'architecture. Coût élevé, mais
   aucune modification du moteur ne devrait être nécessaire hors du module.

À faire avant : un écran de sélection de discipline au démarrage, et permettre
à une structure d'ouvrir une seconde section (`Organization` gère déjà
plusieurs rosters par jeu). `TrainingSystem.FOCUS_GROUPS` contient encore des
clés d'attributs Valorant : à déplacer dans le `GameModule` au moment du
deuxième jeu.

---

## Priorité 4 — Confort et pérennité

- **Comparaison de joueurs** côte à côte : `RadarChart` accepte déjà plusieurs
  séries, il ne manque que l'écran.
- **Graphiques financiers** : `Organization.history` enregistre trésorerie,
  recettes et dépenses tous les mois depuis cette version, et `LineChart`
  existe. L'écran Finances peut afficher une courbe sans nouveau code moteur.
- **Historique et palmarès** : `world.history` est rempli mais jamais affiché.
- **Vitesse d'avance du temps** : bouton « avancer jusqu'à » avec conditions
  d'arrêt paramétrables.
- **Localisation** : les textes sont en français en dur. Passer par `tr()`
  avant que le volume ne devienne ingérable.
- **Tests de non-régression sur une saison** : figer les résultats d'une saison
  à graine connue et vérifier qu'ils ne changent pas involontairement.

---

## Dette technique identifiée

| Sujet | Où | Gravité |
|---|---|---|
| `TrainingSystem.FOCUS_GROUPS` contient des clés Valorant | `TrainingSystem` | Moyenne — bloquera le deuxième jeu, pas avant |
| Double élimination limitée à 8 équipes | `BracketBuilder.double_elim_8` | Faible — couvre les besoins actuels |
| Le système suisse n'est pas utilisé par les compétitions livrées | `CompetitionEngine._populate_swiss_round` | Faible — code prêt, données à écrire |
| Pas de fenêtre de mercato | `ContractSystem`, `TransferSystem` | Moyenne — nuit au réalisme |
| L'IA ne recrute pas de staff | `AiDirector` | Moyenne — le niveau du staff IA se dégrade avec le temps |
| L'IA ne règle ni son entraînement ni ses promesses | `AiDirector` | Faible — les valeurs par défaut sont saines |
| Pas de gestion des visas / quotas régionaux | `TransferSystem` | Moyenne — contrainte réelle du VCT non modélisée |
| Les postes des joueurs importés sont générés | `tools/import_liquipedia.gd` | Faible — voir 1.4 |
| Les sections se reconnaissent par le nom, qui diffère d'un wiki à l'autre | `tools/import_liquipedia.gd` | Faible — une section manquée vaut mieux qu'une inventée, mais une table d'alias serait plus juste |
| La hiérarchie sportive des équipes réelles est tirée au sort | `WorldGenerator._spread_strength` | Moyenne — jouable et honnête, mais les gains cumulés publiés par Liquipedia donneraient un classement réel |
| `Organization.Owner` n'a aucun effet en jeu | `Organization`, `BoardSystem` | Moyenne — cinq types de propriétaire affichés, zéro conséquence ; l'écran de fondation a dû contourner le problème par le capital |
| `Competition.entry_fee` est lu mais jamais débité | `SeasonBuilder`, `FinanceSystem` | Faible — donnée morte, un engagement gratuit |
| Pas de marché du staff : une structure fondée garde son entraîneur débutant à vie | `StaffFactory`, voir 2.1 | Moyenne — bloquant à long terme pour le mode fondation |
| Une section non simulée ne coûte ni ne rapporte rien | `FinanceSystem` | Faible — les autres disciplines restent décoratives tant qu'elles ne sont pas jouables |
| Pas d'académie créée à la génération | `WorldGenerator`, `YouthSystem` | Faible — la bascule de section la gérerait déjà, il manque le roster |

---

## Ce qu'il ne faut PAS faire

- **Ajouter un rendu 3D ou 2D du match.** Le projet est un jeu de gestion ; la
  valeur est dans la lecture des chiffres et du récit, pas dans l'animation.
- **Court-circuiter le grand livre** pour « aller plus vite » sur une mécanique
  financière. Le jour où deux chemins existent pour l'argent, l'écran Finances
  devient faux et le bug est introuvable.
- **Mettre du code spécifique à une discipline hors de son module.** C'est la
  seule chose qui puisse tuer l'objectif multi-jeu.
- **Mettre une marque déposée ailleurs que dans `packs/`.** Le dépôt étant
  privé et le jeu non distribué, `packs/vct_2026/` embarque de vrais noms — mais
  c'est le SEUL endroit. `data/` reste entièrement fictif, et aucun identifiant
  du code ne cite de marque. Le jour où le projet devrait être publié,
  supprimer `packs/` doit suffire. Voir `docs/DATA_PACKS.md`.
- **Faire confiance à « l'écran se construit sans erreur ».** Deux bugs
  d'affichage majeurs sont passés par là. Regarder les captures.
