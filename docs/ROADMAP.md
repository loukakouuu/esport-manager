# Feuille de route

Le socle est posé et jouable de bout en bout. Cette liste est ordonnée par
**rapport valeur / effort**, pas par ordre d'envie. Chaque entrée précise les
fichiers concernés pour pouvoir être attaquée isolément.

---

## Priorité 1 — Rendre la boucle de jeu plus riche sans nouveau système

### 1.1 Négociation de contrat interactive
Aujourd'hui une offre est acceptée ou refusée en un clic. Une vraie négociation
(salaire, durée, statut promis, clause de rachat, prime de signature) est la
brique qui rend le marché intéressant.
*Fichiers : `ContractSystem`, nouvel écran `NegotiationScreen`.*
La fonction `acceptance_chance()` calcule déjà le score : il ne manque que
l'aller-retour et des contre-propositions.

### 1.2 Réunions et retours du vestiaire
Le moral et la satisfaction existent et bougent, mais le joueur ne les pilote
pas. Parler à un joueur mécontent, promettre du temps de jeu, recadrer après une
défaite : c'est peu de code pour beaucoup de vie.
*Fichiers : `ProgressionSystem`, nouveau `MoraleSystem`, écran effectif.*

### 1.3 Consignes de match et temps morts pilotés
Le simulateur gère déjà les temps morts et le momentum côté IA. Laisser le
joueur les déclencher pendant l'affichage du match transforme le compte rendu
en vraie expérience.
*Fichiers : `ValorantSim` (points d'interruption), `MatchScreen`.*

### 1.4 Académie
`is_academy` existe sur `Roster`, l'infrastructure `ACADEMY` aussi, mais rien ne
les utilise. Générer des jeunes, les faire progresser, les promouvoir.
*Fichiers : `WorldGenerator`, `ProgressionSystem`, nouvel écran.*

---

## Priorité 2 — Profondeur de gestion

### 2.1 Recrutement du staff
Le staff est généré au démarrage et jamais renouvelé. Il manque un marché du
staff symétrique à celui des joueurs.
*Fichiers : `StaffFactory`, `TransferSystem`, écran staff.*

### 2.2 Rapports de scouting
Envoyer un recruteur observer un joueur ou une ligue pendant N semaines, ce qui
fait monter le niveau de connaissance. `ScoutingSystem.knowledge()` est déjà la
seule porte d'entrée : il suffit d'y ajouter une source explicite.

### 2.3 Entraînement hebdomadaire dirigé
Choisir un axe de travail (mécanique, utilitaires, anti-strat, repos) avec des
effets opposés sur progression, netteté et fatigue.
*Fichiers : `TrainingSystem`, `ProgressionSystem`.*

### 2.4 Presse et image
Conférences de presse, déclarations, réactions des joueurs. La `fanbase` et la
`reputation` existent déjà comme variables : il manque les événements qui les
font bouger autrement que par les résultats.

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

À faire avant : ajouter un écran de sélection de discipline au démarrage et
permettre à une structure d'ouvrir une seconde section (`Organization` gère déjà
plusieurs rosters par jeu).

---

## Priorité 4 — Confort et pérennité

- **Vitesse d'avance du temps** : bouton « avancer jusqu'à » avec conditions
  d'arrêt paramétrables.
- **Historique et palmarès** : `world.history` est rempli mais jamais affiché.
- **Comparaison de joueurs** côte à côte.
- **Graphiques financiers** : l'écran Finances montre des tableaux, une courbe
  de trésorerie sur 24 mois serait plus parlante.
- **Localisation** : les textes sont en français en dur. Passer par
  `tr()` avant que le volume ne devienne ingérable.
- **Tests de non-régression sur une saison** : figer les résultats d'une saison
  à graine connue et vérifier qu'ils ne changent pas involontairement.

---

## Dette technique identifiée

| Sujet | Où | Gravité |
|---|---|---|
| Double élimination limitée à 8 équipes | `BracketBuilder.double_elim_8` | Faible — couvre les besoins actuels |
| Le système suisse n'est pas utilisé par les compétitions livrées | `CompetitionEngine._populate_swiss_round` | Faible — code prêt, données à écrire |
| Pas de fenêtre de mercato : les mouvements sont possibles toute l'année | `ContractSystem`, `TransferSystem` | Moyenne — nuit au réalisme |
| L'IA ne recrute pas de staff | `AiDirector` | Moyenne — le niveau du staff IA se dégrade avec le temps |
| Les rosters ne se déclarent pas officiellement en compétition | `CompetitionEngine` | Faible |
| Pas de gestion des visas / quotas régionaux | `TransferSystem` | Moyenne — contrainte réelle du VCT non modélisée |

---

## Ce qu'il ne faut PAS faire

- **Ajouter un rendu 3D ou 2D du match.** Le projet est un jeu de gestion ; la
  valeur est dans la lecture des chiffres et du récit, pas dans l'animation.
- **Court-circuiter le grand livre** pour « aller plus vite » sur une mécanique
  financière. Le jour où deux chemins existent pour l'argent, l'écran Finances
  devient faux et le bug est introuvable.
- **Mettre du code spécifique à une discipline hors de son module.** C'est la
  seule chose qui puisse tuer l'objectif multi-jeu.
