# Packs de données — jouer avec de vraies équipes

Le jeu sait tourner sur deux univers : un univers **entièrement fictif**
(96 structures, environ 700 joueurs, tous inventés) et un pack **VCT 2026** qui
apporte les vraies structures et les vrais joueurs. Un *pack de données*
remplace tout ou partie du contenu sans toucher au code.

Le pack VCT 2026 est **livré avec le jeu** et actif par défaut.

## Pourquoi le système existe quand même

Les noms de structures esport sont des **marques déposées** et les joueurs ont
un **droit à l'image**. C'est le problème de Football Manager, et sa réponse est
celle qu'on reprend : le jeu peut sortir avec des noms inventés là où il n'a pas
la licence, et le contenu réel arrive par un fichier séparé.

Ce dépôt étant **privé et non publié**, le pack réel y voyage directement — ça
évite de refaire un import sur chaque machine. Le jour où le projet devrait
devenir public, **supprimer le dossier `packs/` suffit** : plus aucune ligne du
code ne connaît de marque déposée, et l'univers fictif reprend la main tout
seul.

## Comment ça marche

Le jeu lit toutes ses données à travers une chaîne de résolution :

```
user://packs/<pack>/world/orgs.json     ← pack installé par vous : il gagne
res://packs/<pack>/world/orgs.json      ← pack livré avec le jeu
res://data/world/orgs.json              ← contenu livré, toujours en dernier
```

Un pack peut donc ne remplacer **que** les structures, ou que les prénoms, ou
tout. Le reste continue de venir du jeu.

Réimporter un pack sous le même identifiant l'écrit dans `user://`, où il prend
le pas sur la version livrée : le dépôt n'est jamais modifié par un import.
Sous Windows, `user://` est :

```
C:\Users\<vous>\AppData\Roaming\Godot\app_userdata\Esport Manager\
```

Le pack actif se choisit sur l'**écran de démarrage**, avant de générer le
monde. Il est enregistré dans la sauvegarde : recharger une partie rétablit
automatiquement le bon univers.

Code correspondant : [`src/core/DataPack.gd`](../src/core/DataPack.gd).

## Construire ou rafraîchir un pack (Liquipedia)

Un importateur est fourni. Il lit les pages de ligue du VCT sur Liquipedia et
écrit un pack complet.

```bash
godot --headless --path . --script res://tools/import_liquipedia.gd -- \
    --contact=vous@example.com --pack=vct_2026
```

| Option | Effet |
| --- | --- |
| `--contact=` | **Obligatoire.** Identifie vos requêtes ; sans lui l'API répond 406. |
| `--season=2026` | Année du circuit. |
| `--stage="Stage 1"` | Page de ligue lue : `Kickoff`, `Stage 1`, `Stage 2`… |
| `--pack=liquipedia` | Nom du dossier créé sous `user://packs/`. |
| `--no-players` | N'importe que les structures. |
| `--no-sections` | N'interroge pas les autres wikis (une requête par discipline). |
| `--dry` | N'écrit rien, montre ce qui serait importé. |

Comptez **dix à quinze minutes** : Liquipedia impose une requête toutes les
30 secondes et le script s'y tient.

### Ce que l'import donne vraiment

Résultat d'un import réel (VCT 2026, Stage 1) :

- **48 structures** réelles sur les quatre ligues partenaires, avec leur pays
  et leur sigle ;
- **187 joueurs** réels — pseudo, prénom, nom, nationalité, date de naissance ;
- **34 équipes sur 48** avec un effectif complet ;
- les **autres disciplines** de chaque structure (voir plus bas).

Les quatorze équipes restantes utilisent `{{ActiveSquadAuto}}` sur Liquipedia :
leur effectif est assemblé côté serveur et n'existe pas dans le texte de la
page. Le jeu génère des joueurs pour celles-là.

Les ligues Challengers restent fictives : il n'y a pas de source équivalente,
et l'importateur les laisse donc telles qu'elles sont livrées — sinon toute la
pyramide compétitive et l'Ascension disparaîtraient.

### Les sections des autres disciplines

Une structure esport est rarement mono-jeu, et le jeu affiche toutes ses
sections même s'il n'en simule qu'une. L'importateur les récupère en lisant le
`Portal:Teams` de chaque wiki Liquipedia — Counter-Strike, League of Legends,
Rocket League, Apex, Rainbow Six, Dota 2, Overwatch.

Ce portail est la bonne source parce qu'il **sépare explicitement les équipes
actives des équipes dissoutes**. Les deux raccourcis évidents, eux, sont faux :

- *« la page existe sur le wiki »* : les pages des sections dissoutes restent
  en ligne, on obtiendrait des sections fantômes ;
- *« la catégorie Disbanded Teams »* : elle ne concerne que les structures
  entièrement fermées, pas une section abandonnée.

Une page par discipline, donc sept requêtes, et une liste tenue à jour par les
contributeurs.

### Ce que l'import n'apporte pas, et pourquoi

**Aucun attribut, aucun niveau, aucun salaire.** « Visée 17/20 » n'est pas une
donnée publique : c'est un jugement de jeu. Un pack apporte l'**identité** — qui
joue où, sous quel nom, de quel pays — et le moteur continue de produire la
**simulation**. Un vrai joueur importé est donc un vrai nom sur un profil
inventé, avec la bonne date de naissance (donc le bon âge, donc la bonne courbe
de progression) mais des attributs générés.

Le poste de chaque joueur est également généré : Liquipedia ne le publie pas de
façon exploitable. Le capitaine, lui, est repris quand la page le mentionne.

### Licence

Le contenu de Liquipedia est sous **CC-BY-SA 3.0**. Le manifeste écrit par
l'importateur porte la source, la licence et l'attribution, et l'écran de
démarrage les affiche.

Les noms d'équipes et de joueurs restent la propriété de leurs détenteurs. Un
pack construit ainsi est destiné à un **usage personnel** : ne le redistribuez
pas comme s'il faisait partie du jeu.

## Écrire un pack à la main

Un pack est un dossier. Il lui faut un manifeste et au moins un fichier de
données.

```
user://packs/mon-pack/
├── pack.json
└── world/
    ├── orgs.json        (facultatif)
    ├── rosters.json     (facultatif)
    ├── names.json       (facultatif)
    └── sponsors.json    (facultatif)
```

### `pack.json`

```json
{
  "name": "Mon univers",
  "author": "vous",
  "version": "2026-01",
  "description": "Une phrase affichée dans la liste des packs.",
  "source": "d'où viennent les données",
  "license": "CC-BY-SA 3.0",
  "attribution": "phrase d'attribution affichée si la licence l'exige",
  "game": "valorant"
}
```

### `world/orgs.json`

Même format que le fichier livré. Une entrée par structure, groupée par ligue.
Les clés de ligue attendues sont `vct_emea`, `vct_americas`, `vct_pacific`,
`vct_china`, `chal_emea`, `chal_americas`, `chal_pacific`, `chal_china`.

```json
{
  "leagues": {
    "vct_emea": [
      { "name": "Nom de l'équipe", "tag": "TAG", "country": "FR",
        "strength": 80, "owner": "investor", "color": "#1e6fd9",
        "games": ["valorant", "lol", "cs2"] }
    ]
  }
}
```

`strength` (0-100) pilote le niveau du roster généré, la réputation, la base de
fans et les moyens financiers. `owner` vaut `self_funded`, `investor`,
`endemic`, `celebrity` ou `corporate`.

`games` liste les **disciplines de la structure**. Identifiants reconnus :
`valorant`, `cs2`, `lol`, `rl`, `apex`, `r6`, `dota2`, `ow2` — un identifiant
inconnu est ignoré plutôt que de créer une section fantôme. Le champ est
facultatif : sans lui, le jeu en déduit une liste plausible à partir de
`strength`. Seules les disciplines effectivement simulées (aujourd'hui
Valorant) donnent lieu à une équipe ; les autres s'affichent comme sections non
simulées. Voir [`src/gamemodules/GameCatalog.gd`](../src/gamemodules/GameCatalog.gd).

> Un pack **remplace** le fichier qu'il fournit, il ne s'y ajoute pas. Si votre
> `orgs.json` n'a que les ligues VCT, les Challengers disparaîtront du monde.
> Repartez du fichier livré et modifiez-le.

### `world/rosters.json`

Facultatif. Donne les identités réelles des joueurs d'une structure. La clé est
le **nom exact** de la structure tel qu'il figure dans `orgs.json`.

```json
{
  "teams": {
    "Nom de l'équipe": {
      "players": [
        { "tag": "Pseudo", "first": "Prénom", "last": "Nom",
          "country": "FR", "born": "2003-02-06", "igl": true }
      ]
    }
  }
}
```

Tous les champs sauf `tag` sont facultatifs : ce qui manque est généré. Une
équipe absente du fichier reçoit un effectif entièrement généré.

## Vérifier son pack

```bash
# Le pack est-il vu, et que remplace-t-il ?
godot --headless --path . --script res://tools/run_tests.gd

# Le monde se génère-t-il correctement avec ?
godot --headless --path . --script res://tools/season.gd
```

Si un fichier JSON est invalide, le jeu l'écrit dans la console avec le numéro
de ligne et retombe sur le contenu livré : un pack cassé ne casse pas la partie.
