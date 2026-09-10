# Esport Manager

Jeu de gestion de structure esport, façon Football Manager, développé sous
Godot 4.7 en GDScript. Discipline livrée : **VALORANT**.

Vous ne dirigez pas une équipe mais une **entreprise** : une trésorerie, une
marque, des sponsors, des salariés — et un roster qui joue le VCT ou les
Challengers. Les matchs ne sont pas affichés en 3D : ils sont simulés round par
round, avec l'économie officielle, et racontés en texte et en statistiques.

## Démarrer

### Le plus simple : par l'éditeur Godot

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

### Outils de vérification (sans interface)

```bash
"$GODOT" --headless --path . --script res://tools/run_tests.gd   # 63 tests unitaires
"$GODOT" --headless --path . --script res://tools/ui_check.gd    # écrans + invariants de mise en page
"$GODOT" --headless --path . --script res://tools/season.gd      # saison complète + rapport
bash tools/check_all.sh                                          # les trois d'affilée

# Captures d'écran réelles de chaque écran (ouvre brièvement une fenêtre)
"$GODOT" --path . -- --shots=all
```

> Après avoir ajouté un fichier contenant un `class_name`, il faut réindexer une
> fois avant que les scripts headless le voient :
> `"$GODOT" --headless --path . --editor --quit`
> (`tools/test.sh` et `tools/check_all.sh` le font automatiquement).

### Une fois le jeu lancé

1. **Créer le monde** — laisser la graine proposée ou en saisir une. À graine
   identique, le monde généré est toujours le même.
2. **Choisir une structure** — les onglets filtrent par ligue. Commencer par
   *Challengers EMEA* : la campagne consiste à monter en VCT via l'Ascension.
   La colonne *Difficulté* résume réputation et trésorerie.
3. **Jouer** — la barre du haut affiche date, trésorerie et résultat mensuel,
   et contient les boutons *Avancer 1 jour*, *Avancer 1 semaine*,
   *Jusqu'au prochain match* et *Sauvegarder*. La navigation à gauche donne
   accès à l'effectif, la tactique, le calendrier, les compétitions, le marché,
   les finances, les infrastructures et les messages.

Premier réflexe conseillé : ouvrir **Finances**. Une équipe de Challengers
démarre légèrement déficitaire — signer des sponsors est la première urgence.

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
  potentiel, courbe d'âge esport, forme, moral, fatigue, burnout, blessures,
  traits de personnalité, progression et retraite.
- **Gestion** : contrats et clauses de rachat, marché avec IA de recrutement,
  scouting à information imparfaite, objectifs et confiance de la direction.

## Documentation

- [`CLAUDE.md`](CLAUDE.md) — contexte, structure et règles du projet
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — décisions et justifications
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — suite du développement

## Univers fictif

Structures, joueurs et sponsors sont entièrement fictifs et générés depuis
`data/`. Aucune marque ni personne réelle n'est utilisée.
