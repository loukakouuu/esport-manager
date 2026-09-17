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
- **Marché de l'encadrement** → `StaffSystem`, `StaffScreen`, sonde
  `tools/staff_probe.gd`. Neuf postes, une enveloppe par poste plutôt qu'un
  budget commun, et un organigramme qui annonce ce que chaque poste change dans
  le moteur. A réparé deux bugs mesurés au passage : le monde perdait la
  totalité de son encadrement en trois saisons (338 → 0), et chaque roster
  restait branché sur un entraîneur qu'il ne payait plus (136 coachs fantômes,
  soit un bonus tactique gratuit à vie). Les deux postes qui n'avaient aucun
  effet — préparateur physique, directeur sportif — en ont désormais un.
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

### 1.4 Postes réels des joueurs VALORANT
Côté **Counter-Strike, c'est fait** : le wiki renseigne un champ `roles` sur
84 % des fiches, et `import_liquipedia.gd --profiles` le ramène en même temps
que les dates de naissance. C'était la faute la plus visible du pack — il n'y
a qu'une AWP par équipe et tout le monde sait qui la tient.

Côté **Valorant, non** : le wiki Valorant ne publie pas le poste de façon
exploitable dans le wikitexte, et les quatorze équipes qui utilisent
`{{ActiveSquadAuto}}` n'ont même pas d'effectif. Deux pistes : `action=parse`
sur les pages d'équipe pour lire le tableau rendu, ou la clé d'API LPDB v3.
Ça se voit moins qu'en CS — un méta d'agents tournant rend le poste d'un
joueur Valorant bien moins identitaire qu'un AWP.
*Fichiers : `tools/import_liquipedia.gd`, `tools/import_hltv.gd`.*

---

## Priorité 2 — Profondeur de gestion

### 2.1 Sauver le troisième étage de la pyramide
Le Circuit ouvert se ruine intégralement : **32 structures sur 32 en faillite
au bout de deux saisons**, et 17 des 55 Challengers avec elles. Mesuré sur la
même graine avec et sans le marché du staff — les chiffres sont identiques,
c'est donc un problème financier antérieur, pas un effet de bord.

Conséquence concrète : le mode « fonder sa structure » se joue dans un monde
qui meurt autour de vous, et une montée en Challengers vous fait rejoindre un
étage à moitié vide. Les recettes récurrentes d'une structure de Circuit ouvert
tournent autour de 22 k$ par an, contre 312 k$ en Challengers et 5,45 M$ en
VCT : l'écart de 1 à 14 entre les deux premiers étages est probablement trop
brutal, et il n'existe aucune subvention à ce niveau.
*Fichiers : `FinanceSystem`, `SeasonBuilder` (dotations),
`data/world/season_valorant.json`.*
*Mesure : `tools/season.gd`, plus le comptage par étage.*

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

C'est l'objectif structurant du projet.

1. ~~**CS2**~~ — **fait.** `src/gamemodules/cs2/`, MR12 et prolongations MR3,
   économie CS2, AWP dans l'économie du round, maps CT-sided, ADR/KAST, trois
   étages de pyramide, deux Majors à phase suisse. Une maison peut tenir un
   roster Valorant et un roster CS sur une seule trésorerie.
2. **Rocket League** — équipes de 3, pas de rounds, format en buts. Valide que
   l'abstraction `GameModule` tient hors du modèle « rounds ». Coût moyen.
   Attention : `MatchResult.STAT_KEYS` est encore taillé pour un FPS (frags,
   poses, désamorçages). Un jeu à buts demandera d'y toucher — c'est la
   prochaine couture à ouvrir, et elle n'a pas été forcée par CS2.
3. **League of Legends** — genre radicalement différent (draft, objectifs,
   courbe de partie). C'est le vrai test de l'architecture. Coût élevé, mais
   aucune modification du moteur ne devrait être nécessaire hors du module.

Ce que l'arrivée de CS2 a laissé derrière elle :

- **`TrainingSystem.FOCUS_GROUPS` contient toujours des clés d'attributs en
  dur.** Ça a tenu parce que les deux FPS tactiques partagent leur vocabulaire
  (`aim`, `utility`, `clutch`…) ; Rocket League ne le partagera pas. À déplacer
  dans le `GameModule` au troisième jeu, pas avant — le faire aujourd'hui
  serait de l'abstraction sans besoin.
- **`PlayerFactory.TRAITS`** cite les mêmes clés et pose le même constat.
- ~~**Les effectifs CS2 réels ne sont pas importés**~~ — **fait**, mais pas par
  Liquipedia : le circuit Counter-Strike du pack vient du **classement mondial
  HLTV** (`tools/import_hltv.gd`, `tools/hltv/`), qui donne d'un seul tenant les
  écuries, leurs joueurs et — ce que Liquipedia ne donne pas — la hiérarchie.
  Reste une couture : **la récolte n'est pas automatisable.** HLTV répond 403 à
  tout client qui n'est pas un navigateur ; on convertit un instantané relevé à
  la main. L'automatiser demanderait de contourner une protection, ce qui n'est
  ni souhaitable ni stable.
- **Fonder une seconde section en cours de partie** n'existe pas : on fonde sur
  une discipline, et une maison reprise garde les sections qu'elle avait.

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
| L'IA ne règle ni son entraînement ni ses promesses | `AiDirector` | Faible — les valeurs par défaut sont saines |
| Pas de gestion des visas / quotas régionaux | `TransferSystem` | Moyenne — contrainte réelle du VCT non modélisée |
| Les postes des joueurs importés sont générés | `tools/import_liquipedia.gd` | Faible — voir 1.4 |
| Les sections se reconnaissent par le nom, qui diffère d'une source à l'autre | `tools/import_liquipedia.gd`, `tools/import_hltv.gd` | Faible — une section manquée vaut mieux qu'une inventée. L'import HLTV ramène les orthographes au nom déjà présent dans le pack (`Vitality` → `Team Vitality`), mais seulement à suffixe d'entreprise près |
| La hiérarchie sportive des équipes VALORANT est tirée au sort | `WorldGenerator._spread_strength` | Moyenne — jouable et honnête, mais les gains cumulés publiés par Liquipedia donneraient un classement réel. **Côté Counter-Strike c'est réglé** : la force vient du rang mondial HLTV |
| Le circuit Counter-Strike ne se récolte pas tout seul | `tools/hltv/` | Faible — HLTV répond 403 à tout client non-navigateur. La récolte est manuelle et datée, la conversion reproductible ; l'automatiser voudrait dire contourner une protection |
| La Chine n'a que huit écuries réelles en Counter-Strike | `tools/import_hltv.gd` | Faible — dix places de ses ligues inférieures gardent l'équipe fictive livrée. C'est le classement mondial qui est ainsi, pas le convertisseur |
| La réputation de départ ne connaît pas l’HISTOIRE d’une marque | `WorldGenerator._brand_for` | Moyenne — elle vient du prestige de la ligue où la structure joue AUJOURD’HUI. Une écurie historique reléguée d’un étage vaut donc autant qu’une inconnue du même étage : HEROIC démarre à 1 137 de réputation. Aucune source publique ne donne la taille de marque d’une écurie ; le palmarès la fait ensuite remonter |
| `Organization.Owner` n'a aucun effet en jeu | `Organization`, `BoardSystem` | Moyenne — cinq types de propriétaire affichés, zéro conséquence ; l'écran de fondation a dû contourner le problème par le capital |
| `Competition.entry_fee` est lu mais jamais débité | `SeasonBuilder`, `FinanceSystem` | Faible — donnée morte, un engagement gratuit |
| Une section non simulée ne coûte ni ne rapporte rien | `FinanceSystem` | Faible — les disciplines non simulées restent décoratives ; une section SIMULÉE, elle, coûte et rapporte pour de bon |
| Une structure ne peut pas ouvrir une nouvelle section en cours de partie | `Game`, `WorldGenerator` | Moyenne — on hérite de ses sections ou on fonde sur une seule discipline |
| Les joueurs ne changent jamais de discipline | `TransferSystem` | Faible — cela arrive dans la réalité (les passages CS → Valorant de 2020), et les attributs communs le permettraient déjà |
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
