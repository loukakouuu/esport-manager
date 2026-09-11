# Esport Manager

Jeu de gestion de structure esport, façon Football Manager, développé sous
Godot 4.7 en GDScript. Discipline livrée : **VALORANT**.

Vous ne dirigez pas une équipe mais une **entreprise** : une trésorerie, une
marque, des sponsors, des salariés — et un roster qui joue le VCT ou les
Challengers. Les matchs ne sont pas affichés en 3D : ils sont simulés round par
round, avec l'économie officielle, et racontés en texte et en statistiques.

## Démarrer

### Le plus simple : double-cliquer sur `Jouer.bat`

Le fichier `Jouer.bat`, à la racine du projet, lance directement le jeu.
Si Godot est installé ailleurs que dans `Téléchargements`, ouvrez-le dans un
éditeur de texte et corrigez la ligne `set GODOT=`.

### Par l'éditeur Godot (pour modifier le jeu)

1. Lancer `Godot_v4.7.2-stable_win64.exe`.
2. **Importer** → sélectionner le fichier `project.godot` de ce dossier.
3. Une fois le projet ouvert, appuyer sur **F5** (ou la flèche ▶ en haut à
   droite) pour lancer la partie.

Au premier lancement, Godot réindexe les scripts : c'est normal que ça prenne
quelques secondes.

### En ligne de commande

Godot n'est pas dans le `PATH` par défaut sous Windows. Le plus pratique est de
définir la variable `GODOT` une fois par session :

```bash
# Bash (Git Bash)
export GODOT="/c/Users/dark7/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe"
cd "/c/Users/dark7/Desktop/Projet/Esport Manager/esport-manager"

"$GODOT" --path .                    # lancer le jeu
bash tools/check_all.sh              # tout vérifier (tests, écrans, saison)
```

```powershell
# PowerShell
$env:GODOT = "$env:USERPROFILE\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
cd "$env:USERPROFILE\Desktop\Projet\Esport Manager\esport-manager"

& $env:GODOT --path .
```

Pour voir les `print()` et les erreurs dans le terminal, utiliser la variante
console : `Godot_v4.7.2-stable_win64_console.exe`.

## Une fois le jeu lancé

1. **Choisir le mode** — *Reprendre une structure* : vous héritez d'une maison
   qui existe, avec son effectif, sa trésorerie et ses attentes.
   *Fonder votre structure* : vous partez de rien (voir plus bas).
   C'est aussi sur cet écran qu'on choisit l'univers (vraies équipes ou univers
   fictif) et la graine du monde — à graine identique, le monde est toujours le
   même.
2. **Choisir une structure** — les onglets filtrent par ligue, le panneau de
   droite détaille celle qu'on inspecte : ses sections sur les autres jeux, son
   effectif, ce que la direction attendra. Commencer par *Challengers EMEA* :
   la campagne consiste à monter en VCT via l'Ascension.
3. **Jouer** — la barre du haut ne bouge jamais : écusson, date, trésorerie,
   résultat mensuel, prochain match, et le bouton **Continuer**. La colonne de
   gauche regroupe les pages par thème.

### Fonder sa structure

L'autre mode, plus dur. Vous choisissez un nom, un sigle, des couleurs, une
région et un capital — et c'est tout ce que vous avez.

Pas un joueur sous contrat, aucun sponsor, aucune infrastructure, un entraîneur
débutant, et une réputation nulle qui fera dire non aux bons agents libres.
Vous entrez au **troisième étage de la pyramide**, le *Circuit ouvert*, et la
montée en Challengers passe par un barrage en fin de saison.

Le capital est le vrai arbitrage, parce qu'il s'échange contre de la patience :

| | Capital | La direction |
| --- | --- | --- |
| **Garage** | 40 k$ | c'est vous : elle ne vous licenciera pas |
| **Amorçage** | 120 k$ | ni filet, ni pression particulière |
| **Investisseur** | 320 k$ | exige la montée dès la première saison |

Le championnat démarre mi-février. Une équipe qui ne présente pas cinq joueurs
déclare forfait : les six premières semaines servent à recruter.

### Une structure, plusieurs équipes

Une structure esport aligne rarement une seule discipline. Le jeu reprend les
sections réelles de celle que vous dirigez : la page **Structure** les liste
toutes, et une barre de sections apparaît sous le fil d'Ariane dès qu'il y en a
plus d'une. Cliquer sur une section bascule tout le bloc *Équipe* du menu
— effectif, tactique, entraînement, vestiaire — sur cette équipe-là.

Seul **Valorant** est simulé aujourd'hui. Les autres sections sont affichées
grisées, avec la mention *non simulée* : elles font partie de la maison et
s'ouvriront quand la discipline sera jouable, sans recommencer de carrière.

Premier réflexe conseillé : ouvrir **Finances**. Une équipe de Challengers
démarre légèrement déficitaire — signer des sponsors est la première urgence.
Second réflexe : **Entraînement**, pour choisir votre équilibre entre scrims et
récupération. Il n'y a pas de bon réglage universel.

## Ce que le jeu simule

- **Match** : veto de maps, 13 rounds MR12 avec prolongations, économie
  officielle (800 au départ, +3000 sur victoire, bonus de défaite progressif,
  conservation de l'équipement), momentum et tilt, temps morts, clutchs, aces,
  statistiques individuelles et note par joueur.
- **Compétitions** : une pyramide à trois étages — 4 ligues VCT partenaires,
  4 ligues Challengers, 4 Circuits ouverts — plus Masters, Champions,
  l'Ascension et les barrages de montée. Formats championnat, poules, double
  élimination et système suisse.
- **Finances** : grand livre à double sens, sponsors par emplacement exclusif,
  subventions de ligue, partage de revenus éditeur, merchandising, contenu,
  cashprizes partagés avec les joueurs, salaires, charges sociales régionales,
  infrastructures, emprunts, impôt sur les sociétés, faillite.
- **Joueurs** : attributs mentaux et spécifiques à la discipline, capacité et
  potentiel, aisance par poste, personnalité, courbe d'âge esport, forme,
  moral, fatigue, usure mentale, blessures, historique de développement mois
  par mois, bilan de carrière, progression et retraite.
- **Entraînement** : dix créneaux hebdomadaires à répartir entre scrims,
  mécanique, théorie, préparation physique et repos ; travail individuel et
  intensité réglables joueur par joueur.
- **Vestiaire** : influence de chacun dans le groupe, affinités qui évoluent,
  clans, conflits ouverts, griefs nommés (temps de jeu, salaire, projet
  sportif, poste, surcharge) et conversations où le ton compte autant que le
  sujet.
- **Gestion** : contrats et clauses de rachat, promesses de temps de jeu,
  marché avec IA de recrutement, scouting à information imparfaite, relève
  annuelle par les académies, objectifs et confiance de la direction.

## Vraies équipes

Le pack **VCT 2026** est livré avec le jeu et actif par défaut : 48 structures
réelles des quatre ligues partenaires, environ 190 joueurs réels — pseudo, nom,
nationalité, date de naissance — et leurs **sections sur les autres
disciplines**, lues sur les portails d'équipes actives de chaque wiki
Liquipedia. Team Vitality arrive donc avec CS2, LoL et Rocket League à côté de
son équipe Valorant ; Karmine Corp avec LoL et Rocket League.

Les niveaux et les attributs, eux, restent générés : ils n'existent pas comme
donnée publique. Un vrai joueur importé est un vrai nom, avec le bon âge, sur
un profil simulé.

Une structure dont le nom s'écrit différemment d'un wiki à l'autre peut se
retrouver avec moins de sections qu'elle n'en a réellement. C'est assumé :
mieux vaut en manquer une que d'en inventer une.

L'univers **fictif** reste disponible d'un clic sur l'écran de démarrage, et
un importateur reconstruit le pack à partir des pages publiques de Liquipedia :

```bash
godot --headless --path . --script res://tools/import_liquipedia.gd -- \
    --contact=vous@example.com --pack=vct_2026
```

Tout est expliqué dans [`docs/DATA_PACKS.md`](docs/DATA_PACKS.md), y compris
comment écrire un pack à la main et les conditions de licence.

## Outils de vérification (sans interface)

```bash
"$GODOT" --headless --path . --script res://tools/run_tests.gd   # 231 vérifications
bash tools/check_ui.sh                                           # 60 vues d'écran
"$GODOT" --headless --path . --script res://tools/season.gd      # saison complète
bash tools/check_all.sh                                          # les trois d'affilée

# Captures d'écran réelles de chaque onglet (ouvre brièvement une fenêtre)
"$GODOT" --path . -- --shots=all
```

> Après avoir ajouté un fichier contenant un `class_name`, il faut réindexer une
> fois avant que les scripts headless le voient :
> `"$GODOT" --headless --path . --editor --quit`
> (`tools/test.sh` et `tools/check_all.sh` le font automatiquement).

## Documentation

- [`CLAUDE.md`](CLAUDE.md) — contexte, structure et règles du projet
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — décisions et justifications
- [`docs/DATA_PACKS.md`](docs/DATA_PACKS.md) — vraies équipes, format des packs
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — suite du développement

## Contenu et marques

`data/` ne contient que du contenu **fictif** : structures, joueurs et sponsors
inventés. C'est ce qui tourne quand aucun pack n'est actif, et c'est sur lui que
s'appuient les tests.

`packs/vct_2026/` contient des **noms réels** (structures et joueurs), issus de
Liquipedia sous licence CC-BY-SA 3.0. Ces noms restent la propriété de leurs
détenteurs et ce dossier est destiné à un usage **personnel** : ce dépôt n'est
pas public et le jeu n'est pas distribué. Pour revenir à un projet publiable,
supprimer `packs/` suffit — aucune autre partie du code ne connaît de marque
déposée.
