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

1. **Créer le monde** — laisser la graine proposée ou en saisir une. À graine
   identique, le monde généré est toujours le même. C'est aussi ici qu'on
   choisit un *pack de données* (voir plus bas).
2. **Choisir une structure** — les onglets filtrent par ligue. Commencer par
   *Challengers EMEA* : la campagne consiste à monter en VCT via l'Ascension.
   La colonne *Difficulté* résume réputation et trésorerie.
3. **Jouer** — la barre du haut ne bouge jamais : écusson, date, trésorerie,
   résultat mensuel, prochain match, et le bouton **Continuer**. La colonne de
   gauche regroupe les pages par thème.

Premier réflexe conseillé : ouvrir **Finances**. Une équipe de Challengers
démarre légèrement déficitaire — signer des sponsors est la première urgence.
Second réflexe : **Entraînement**, pour choisir votre équilibre entre scrims et
récupération. Il n'y a pas de bon réglage universel.

## Ce que le jeu simule

- **Match** : veto de maps, 13 rounds MR12 avec prolongations, économie
  officielle (800 au départ, +3000 sur victoire, bonus de défaite progressif,
  conservation de l'équipement), momentum et tilt, temps morts, clutchs, aces,
  statistiques individuelles et note par joueur.
- **Compétitions** : 4 ligues VCT partenaires, 4 ligues Challengers, Masters,
  Champions, Ascension et promotion. Formats championnat, poules, double
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

## Jouer avec de vraies équipes

Le jeu est livré avec un univers entièrement fictif — les noms de structures
esport sont des marques déposées et les joueurs ont un droit à l'image.

Comme Football Manager, il accepte des **packs de données** installés en local
qui remplacent ce contenu. Un importateur construit un pack à partir des pages
publiques de Liquipedia :

```bash
godot --headless --path . --script res://tools/import_liquipedia.gd -- \
    --contact=vous@example.com
```

Il produit 48 structures réelles et environ 190 joueurs réels (pseudo, nom,
nationalité, date de naissance). Les niveaux et attributs restent générés par
le jeu : ils n'existent pas comme donnée publique.

Tout est expliqué dans [`docs/DATA_PACKS.md`](docs/DATA_PACKS.md), y compris
comment écrire un pack à la main et les conditions de licence.

## Outils de vérification (sans interface)

```bash
"$GODOT" --headless --path . --script res://tools/run_tests.gd   # 129 vérifications
bash tools/check_ui.sh                                           # 25 vues d'écran
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

## Univers fictif

Structures, joueurs et sponsors livrés avec le jeu sont entièrement fictifs et
générés depuis `data/`. Aucune marque ni personne réelle n'est utilisée dans ce
dépôt.
