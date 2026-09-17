# Esport Manager

Jeu de gestion de structure esport, façon Football Manager, développé sous
Godot 4.7 en GDScript. Disciplines simulées : **VALORANT** et
**COUNTER-STRIKE 2**.

Vous ne dirigez pas une équipe mais une **entreprise** : une trésorerie, une
marque, des sponsors, des salariés — et un ou plusieurs rosters, qui jouent le
VCT, les Challengers, la Pro League ou un Major. Les matchs ne sont pas
affichés en 3D : ils sont simulés round par round, avec l'économie officielle
de leur jeu, et racontés en texte et en statistiques.

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
2. **Choisir une structure** — une première rangée d'onglets choisit la
   discipline, une seconde la ligue ; le panneau de droite détaille la maison
   qu'on inspecte : ses sections sur les autres jeux, son effectif, ce que la
   direction attendra. Commencer par *Challengers EMEA* : la campagne consiste
   à monter en VCT via l'Ascension. Une maison qui aligne les deux disciplines
   apparaît dans les deux listes, et la carte cliquée décide de la section par
   laquelle on entre — on dirige ensuite la maison entière.
3. **Jouer** — la barre du haut ne bouge jamais : écusson, date, trésorerie,
   résultat mensuel, prochain match, et le bouton **Continuer**. La colonne de
   gauche regroupe les pages par thème.

### Fonder sa structure

L'autre mode, plus dur. Vous choisissez un nom, un sigle, des couleurs, une
**discipline**, une région et un capital — et c'est tout ce que vous avez.

Pas un joueur sous contrat, aucun sponsor, aucune infrastructure, un entraîneur
débutant — remplaçable dès le premier jour, si vous avez de quoi le payer — et
une réputation nulle qui fera dire non aux bons agents libres.
Vous entrez au **troisième étage de la pyramide**, le *Circuit ouvert* de la
discipline choisie, et la montée passe par un barrage en fin de saison.
On fonde sur une seule discipline : ouvrir deux équipes le jour où l'on n'a
encore signé personne est le plus court chemin vers le dépôt de bilan.

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

**Valorant et Counter-Strike 2** sont simulés, et une maison peut tenir les
deux : un roster VCT et un roster Pro League sur une seule trésorerie, un seul
grand livre, une seule direction. Chaque section a ses joueurs, son marché, son
entraîneur, son championnat et ses dotations — et elle pèse sur les comptes de
la maison entière, ce qui est exactement le problème de gestion qu'on cherche.

Les sections des disciplines que le moteur ne simule pas encore (LoL, Rocket
League…) restent affichées grisées, avec la mention *non simulée* : elles font
partie de la maison et s'ouvriront le jour venu, sans recommencer de carrière.

### Counter-Strike n'est pas Valorant

La deuxième discipline n'est pas un habillage : elle a ses propres règles, et
ce sont elles qui rendent sa gestion différente.

- **L'AWP.** Une arme à 4 750 $ qui gagne un round à elle seule, mais qu'on ne
  rachète pas quand on est à sec. Elle vit dans l'économie du match, pas dans
  un attribut : perdre son AWPeur tôt, c'est perdre l'arme, et souvent le round
  suivant. L'écran Tactique expose un curseur *Priorité à l'AWP*.
- **Des cartes CT-sided.** Toutes, sans exception — un 12-0 en défense suivi
  d'un effondrement en attaque est un scénario ordinaire de CS.
- **Une économie plus punitive.** Plafond à 16 000 $, bonus de défaite qui
  monte à 2 900 $, et une bombe posée qui paie **même quand on perd le round** :
  une équipe menée peut refaire son économie sans gagner.
- **Cinq postes à elle** : AWPeur, entry fragger, soutien, lurker, rifleur.
- **Un autre modèle économique.** Counter-Strike n'est pas franchisé : les
  subventions de ligue y sont trois fois plus faibles qu'en VCT, et l'argent se
  gagne en tournoi — dotations de championnat plus grosses, Majors à 1,25 M$.
  Une écurie CS vit de ses résultats là où une écurie Valorant vit de son slot.
- **Ses statistiques** : ADR et KAST au lieu de l'ACS, notes calées sur les
  ordres de grandeur réels du haut niveau CS2.

Premier réflexe conseillé : ouvrir **Finances**. Une équipe de Challengers
démarre légèrement déficitaire — signer des sponsors est la première urgence.
Second réflexe : **Entraînement**, pour choisir votre équilibre entre scrims et
récupération. Il n'y a pas de bon réglage universel.

### L'encadrement

La page **Encadrement** liste les neuf postes d'une structure esport, occupés
ou non, et dit pour chacun ce qu'il change dans le moteur et ce que la personne
en place délivre aujourd'hui. Un poste vacant n'est pas neutre : sans
entraîneur, l'équipe joue avec 8/20 de niveau tactique, quel que soit le
talent des joueurs.

L'arbitrage est celui d'une masse salariale : un analyste coûte trois fois
moins qu'un entraîneur et ne pèse que sur la préparation adverse ; un
préparateur physique ne se voit jamais en match mais change la fatigue et les
blessures sur toute la saison. Le marché ne se marchande pas clause par clause
comme un joueur — on règle un salaire et une durée, l'intermédiaire répond, et
un refus ferme la porte trois semaines.

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
- **Négociation** : six clauses qui se discutent séparément — salaire, prime à
  la signature, durée, statut promis, clause de rachat, part des gains. Chaque
  joueur a ses priorités selon son caractère, son agent ne dit jamais les
  chiffres qu'il attend, et sa patience s'use à chaque proposition.
- **Encadrement** : neuf postes, de l'entraîneur principal au directeur
  sportif, chacun avec un effet réel sur le moteur — tactique en match,
  progression, cohésion, moral, récupération, fiabilité du scouting,
  activations sponsors, commission d'agent. Un poste vacant applique sa valeur
  plancher, et l'écran le dit. Les structures adverses gèrent le leur.
- **Gestion** : contrats et clauses de rachat, promesses de temps de jeu,
  marché avec IA de recrutement, scouting à information imparfaite, relève
  annuelle par les académies, objectifs et confiance de la direction.

## Vraies équipes

Le pack **Saison 2026** est livré avec le jeu et actif par défaut, et il couvre
les **deux disciplines** :

- côté **Valorant**, 48 structures des quatre ligues partenaires et environ
  190 joueurs réels, lus sur Liquipedia ;
- côté **Counter-Strike**, 76 écuries et 373 joueurs réels, tirés du
  **classement mondial HLTV** — des deux premières mondiales jusqu'au rang 228.

S'y ajoutent les **sections sur les autres disciplines**, lues sur les portails
d'équipes actives de chaque wiki Liquipedia : Team Vitality arrive avec CS2,
LoL et Rocket League à côté de son équipe Valorant ; Karmine Corp avec LoL et
Rocket League.

Les niveaux et les attributs, eux, restent générés : ils n'existent pas comme
donnée publique. Un vrai joueur importé est un vrai nom, avec le bon âge, sur
un profil simulé.

**Sauf pour Counter-Strike, où la hiérarchie est publiée.** « Fnatic est plus
fort que BBL » n'est pas une donnée publique en Valorant, et le jeu invente
donc l'ordre des équipes du VCT. Le classement HLTV, lui, EST cet ordre : la
force des écuries CS en vient directement, à l'intérieur d'une ligue comme
entre les régions. La Pro League EMEA tourne autour de 74-88 quand la chinoise
tient entre 66 et 68 — parce que le classement mondial ne place que deux
écuries chinoises dans ses trente-cinq premières.

Onze maisons tiennent les deux sections sur une seule trésorerie : Vitality,
NAVI, G2, FURIA, MIBR, Liquid, TYLOO, 100 Thieves, Fnatic, FUT, NRG. Ce sont
exactement les onze dont Liquipedia dit, de son côté et sans rapport, qu'elles
ont une section Counter-Strike active.

Une structure dont le nom s'écrit différemment d'une source à l'autre peut se
retrouver avec moins de sections qu'elle n'en a réellement. C'est assumé :
mieux vaut en manquer une que d'en inventer une.

L'univers **fictif** reste disponible d'un clic sur l'écran de démarrage, et
deux importateurs reconstruisent le pack :

```bash
# Valorant — lit les pages publiques de Liquipedia
godot --headless --path . --script res://tools/import_liquipedia.gd -- \
    --contact=vous@example.com --pack=vct_2026

# Counter-Strike — convertit un relevé du classement HLTV
godot --headless --path . --script res://tools/import_hltv.gd
```

Le second ne télécharge rien : HLTV refuse tout client qui n'est pas un
navigateur, et prétendre le contraire donnerait un outil qui ne marche pas. La
récolte se fait à la main, en vingt secondes dans la console du navigateur, et
l'instantané daté vit dans [`tools/hltv/`](tools/hltv/).

Tout est expliqué dans [`docs/DATA_PACKS.md`](docs/DATA_PACKS.md), y compris
comment écrire un pack à la main et les conditions de licence.

## Outils de vérification (sans interface)

```bash
"$GODOT" --headless --path . --script res://tools/run_tests.gd   # 566 vérifications
bash tools/check_ui.sh                                           # 99 vues d'écran
"$GODOT" --headless --path . --script res://tools/season.gd      # saison complète
bash tools/check_all.sh                                          # tout d'affilée

# Cohérence multi-disciplines. Sans --pack : l'univers fictif ; avec : celui
# que le joueur obtient par défaut, où Counter-Strike est réel.
"$GODOT" --headless --path . --script res://tools/discipline_probe.gd
"$GODOT" --headless --path . --script res://tools/discipline_probe.gd -- --pack=vct_2026

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
