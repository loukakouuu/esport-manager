# Packs de données — jouer avec de vraies équipes

Le jeu est livré avec un univers **entièrement fictif** : 96 structures, environ
700 joueurs, tous inventés. Un *pack de données* remplace tout ou partie de ce
contenu sans toucher au code, et sans rien ajouter au dépôt.

## Pourquoi ce détour plutôt que de livrer les vraies équipes

Les noms de structures esport sont des **marques déposées** et les joueurs ont
un **droit à l'image**. Les embarquer dans le dépôt exposerait le projet.

C'est exactement le problème de Football Manager, et sa réponse est celle qu'on
reprend : le jeu sort avec des noms inventés là où il n'a pas la licence, et
la communauté installe des fichiers de correction en local. Le dépôt reste
propre, l'utilisateur reste libre.

## Comment ça marche

Le jeu lit toutes ses données à travers une chaîne de résolution :

```
user://packs/<pack>/world/orgs.json     ← si ce fichier existe, il gagne
res://data/world/orgs.json              ← sinon, le contenu livré
```

Un pack peut donc ne remplacer **que** les structures, ou que les prénoms, ou
tout. Le reste continue de venir du jeu. Sous Windows, `user://` est :

```
C:\Users\<vous>\AppData\Roaming\Godot\app_userdata\Esport Manager\
```

Le pack actif se choisit sur l'écran **Nouvelle partie**, avant de générer le
monde. Il est enregistré dans la sauvegarde : recharger une partie rétablit
automatiquement le bon univers.

Code correspondant : [`src/core/DataPack.gd`](../src/core/DataPack.gd).

## Construire un pack automatiquement (Liquipedia)

Un importateur est fourni. Il lit les pages de ligue du VCT sur Liquipedia et
écrit un pack complet.

```bash
godot --headless --path . --script res://tools/import_liquipedia.gd -- \
    --contact=vous@example.com
```

| Option | Effet |
| --- | --- |
| `--contact=` | **Obligatoire.** Identifie vos requêtes ; sans lui l'API répond 406. |
| `--season=2026` | Année du circuit. |
| `--stage="Stage 1"` | Page de ligue lue : `Kickoff`, `Stage 1`, `Stage 2`… |
| `--pack=liquipedia` | Nom du dossier créé sous `user://packs/`. |
| `--no-players` | N'importe que les structures. |
| `--dry` | N'écrit rien, montre ce qui serait importé. |

Comptez **cinq à dix minutes** : Liquipedia impose une requête toutes les
30 secondes et le script s'y tient.

### Ce que l'import donne vraiment

Résultat d'un import réel (VCT 2026, Stage 1) :

- **48 structures** réelles sur les quatre ligues partenaires, avec leur pays
  et leur sigle ;
- **187 joueurs** réels — pseudo, prénom, nom, nationalité, date de naissance ;
- **34 équipes sur 48** avec un effectif complet.

Les quatorze autres utilisent `{{ActiveSquadAuto}}` sur Liquipedia : leur
effectif est assemblé côté serveur et n'existe pas dans le texte de la page.
Le jeu génère des joueurs pour celles-là.

Les ligues Challengers restent fictives : il n'y a pas de source équivalente,
et l'importateur les laisse donc telles qu'elles sont livrées — sinon toute la
pyramide compétitive et l'Ascension disparaîtraient.

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
nouvelle partie les affiche.

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
        "strength": 80, "owner": "investor", "color": "#1e6fd9" }
    ]
  }
}
```

`strength` (0-100) pilote le niveau du roster généré, la réputation, la base de
fans et les moyens financiers. `owner` vaut `self_funded`, `investor`,
`endemic`, `celebrity` ou `corporate`.

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
