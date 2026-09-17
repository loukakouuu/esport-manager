# Packs de données — jouer avec de vraies équipes

Le jeu sait tourner sur deux univers : un univers **entièrement fictif**
(188 structures, environ 1 560 joueurs, tous inventés) et un pack
**Saison 2026** qui apporte les vraies structures et les vrais joueurs, dans
les DEUX disciplines. Un *pack de données* remplace tout ou partie du contenu
sans toucher au code.

Le pack Saison 2026 est **livré avec le jeu** et actif par défaut. Il vient de
deux sources, parce que les deux circuits ne publient pas les mêmes choses :

| | Source | Ce qu'elle donne |
| --- | --- | --- |
| Valorant | Liquipedia (CC-BY-SA 3.0) | 48 structures, 187 joueurs, et les autres disciplines de chaque maison |
| Counter-Strike | Classement mondial HLTV | 76 écuries, 373 joueurs, **et la hiérarchie** |

Cette dernière colonne est la vraie différence entre les deux. « Fnatic est
plus fort que BBL » n'est pas une donnée publique en Valorant : le pack VCT
donne donc la même force à tout le monde et laisse le jeu inventer l'ordre. En
Counter-Strike, l'ordre EST publié — c'est le classement HLTV — et le champ
`strength` du circuit CS est donc une vraie mesure.

> Son identifiant reste `vct_2026`, alors qu'il ne couvre plus seulement le
> VCT : c'est celui qu'ont enregistré les sauvegardes existantes. Même
> arbitrage que `orgs.json`, qui reste le fichier Valorant parce qu'il est le
> fichier historique.

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
| `--sections-only` | Ne rafraîchit que les disciplines d'un pack déjà importé. |
| `--dry` | N'écrit rien, montre ce qui serait importé. |

`--contact` n'a pas besoin d'être une adresse personnelle : Liquipedia veut
surtout un `User-Agent` qui identifie l'outil et son usage. Pour un import
local et non redistribué, quelque chose comme
`--contact="esport-manager (outil personnel, usage local)"` fait l'affaire.
Un contact joignable reste la bonne pratique si le volume augmente.

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

Ce portail est la bonne source parce qu'il **isole les équipes actives** dans
une section à part. Les deux raccourcis évidents, eux, sont faux :

- *« la page existe sur le wiki »* : les pages des sections dissoutes restent
  en ligne, on obtiendrait des sections fantômes ;
- *« la catégorie Disbanded Teams »* : elle ne concerne que les structures
  entièrement fermées, pas une section abandonnée.

Concrètement, l'importateur demande d'abord le **plan** du portail, puis les
liens des seules sections utiles. Deux formes de portail existent et il gère
les deux :

- une section **« Notable Active … Teams »** unique — Counter-Strike, Rocket
  League, Rainbow Six, Dota 2, Overwatch ;
- **pas de section « active » du tout**, l'actif étant réparti sur plusieurs
  sections de premier niveau placées avant « Notable Disbanded … » — League of
  Legends, Apex. On lit alors tout ce qui précède, en sautant les classements
  par gains ou par statistiques : ceux-là mêlent les équipes de toutes les
  époques.

C'est la page rendue et pas son wikitexte, parce que la plupart de ces portails
assemblent leurs listes avec un modèle — le wikitexte ne contient alors aucun
nom d'équipe. Et ce sont des sections et pas la page entière, parce que le
portail liste aussi les équipes dissoutes : sur le wiki Overwatch, 1189 équipes
au lieu de 428, et Fnatic hériterait d'une section qu'elle n'a plus depuis des
années.

Les noms sont comparés en minuscules, et aussi débarrassés de leur suffixe
d'entreprise : « Gen.G Esports » sur le wiki Valorant, « Gen.G » sur celui de
League of Legends. Une structure dont le nom diffère plus que ça sur un autre
wiki n'est simplement pas reconnue — mieux vaut manquer une section que d'en
inventer une.

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

## Construire ou rafraîchir le circuit Counter-Strike (HLTV)

```bash
godot --headless --path . --script res://tools/import_hltv.gd
```

Pas de `--contact`, pas de dix minutes d'attente : **cet importateur ne
télécharge rien.** HLTV répond 403 à tout client qui n'est pas un navigateur —
`curl` avec un User-Agent de Chrome comme le `HTTPRequest` de Godot. Il n'y a
pas de clé d'API à demander. Écrire un importateur qui « télécharge le
classement » serait donc écrire un importateur qui ne marche pas.

Le partage des rôles est assumé : **la récolte est manuelle et datée, la
conversion est reproductible.** Un instantané du classement vit dans
[`tools/hltv/`](../tools/hltv/) avec la marche à suivre pour le rafraîchir
(vingt secondes dans la console du navigateur), et le script le convertit en
pack.

| Option | Effet |
| --- | --- |
| `--pack=vct_2026` | Pack complété sous `user://packs/`. |
| `--snapshot=` | Instantané à convertir. Par défaut : le plus récent de `tools/hltv/`. |
| `--dry` | N'écrit rien, montre la pyramide qui serait produite. |

### Ce que l'import donne vraiment

Résultat d'une conversion réelle (classement du 14 septembre 2026) :

- **76 écuries réelles** sur 86 places, des deux premières mondiales jusqu'au
  rang 228 — le bas de pyramide EST le bas de pyramide ;
- **373 joueurs** réels : pseudo, nom civil, nationalité ;
- une **force tirée du rang mondial**, donc une hiérarchie qui existe à
  l'intérieur d'une ligue ET entre les régions : la Pro League EMEA tourne
  autour de 74-88 quand la chinoise tient entre 66 et 68, parce que le
  classement mondial ne place que deux écuries chinoises dans ses trente-cinq
  premières.

Les dix places restantes sont en Chine, et gardent l'équipe **fictive** livrée :
le classement mondial n'y compte que huit écuries, toutes absorbées par la Pro
League et le haut de la Challenger. Une ligue à deux équipes n'aurait pas de
sens sportif ; la combler de vraies équipes qui n'y sont pas en aurait encore
moins.

### Ce qui fait les maisons à deux sections

Le moteur ne rapproche une ligne de `orgs_cs2.json` d'une structure existante
que si le **nom est identique au caractère près**. Or HLTV écrit « Vitality »
là où Liquipedia écrit « Team Vitality » : sans rien faire, on obtiendrait deux
structures et deux trésoreries pour une seule maison.

L'importateur aligne donc l'orthographe sur celle que le pack emploie déjà,
quand les deux coïncident une fois l'habillage d'entreprise retiré
(`G2` → `G2 Esports`, `fnatic` → `Fnatic`). Il ne rapproche que ça : mieux vaut
deux structures séparées qu'une fusion abusive, qui donnerait à une maison une
section qu'elle n'a pas.

Le résultat se vérifie tout seul, et c'est rassurant : les **onze** structures
que cet alignement rapproche sont exactement les onze dont Liquipedia dit, de
son côté et sans rapport, qu'elles ont une section Counter-Strike active.

### Ce que l'import n'apporte pas, et pourquoi

Même règle que côté Valorant — un pack apporte l'**identité**, le moteur fait
la **simulation** — avec deux précisions propres à HLTV :

- **la note HLTV d'un joueur est publique**, mais la convertir en attributs
  serait un modèle de plus. Le rang d'une ÉQUIPE se transpose en un seul
  nombre ; la note d'un joueur, non ;
- **la date de naissance et le poste** ne sont pas sur le classement — il
  faudrait ~450 fiches individuelles. Ils viennent donc du wiki Counter-Strike
  de Liquipedia, qui répond par lots de cinquante :

```bash
godot --headless --path . --script res://tools/import_liquipedia.gd -- \
    --profiles --contact="esport-manager (outil personnel, usage local)"
```

Quatre minutes, et **307 dates de naissance et 314 postes sur 372 joueurs**.
Deux sources, deux fichiers : l'instantané HLTV et `tools/hltv/profiles.json`
gardent chacun sa provenance et sa licence, et l'import les fusionne.

Le poste n'est pas un détail d'affichage. Il n'y a qu'une AWP par équipe de
Counter-Strike et tout le monde sait qui la tient : ZywOo rangé « soutien »
pendant qu'apEX tient l'AWP se voit immédiatement. Le moteur respecte les
postes déclarés dans les **bornes de composition** de la discipline — une page
de wiki peut annoncer deux AWPeurs dans le même cinq, le second passe rifleur.

### Licence

Le classement est le **travail éditorial de HLTV** et les noms appartiennent à
leurs détenteurs. Le manifeste porte la source et sa date, et l'écran de
démarrage l'affiche à côté de l'attribution Liquipedia. Usage **personnel** :
ne redistribuez ni l'instantané ni le pack.

## Écrire un pack à la main

Un pack est un dossier. Il lui faut un manifeste et au moins un fichier de
données.

```
user://packs/mon-pack/
├── pack.json
├── world/
│   ├── orgs.json            structures Valorant       (facultatif)
│   ├── rosters.json         effectifs réels Valorant  (facultatif)
│   ├── season_valorant.json circuit Valorant          (facultatif)
│   ├── orgs_cs2.json        structures CS2            (facultatif)
│   ├── rosters_cs2.json     effectifs réels CS2       (facultatif)
│   ├── season_cs2.json      circuit CS2               (facultatif)
│   ├── names.json           (facultatif)
│   └── sponsors.json        (facultatif)
└── games/
    ├── valorant/            maps.json, agents.json    (facultatif)
    └── cs2/                 maps.json, weapons.json   (facultatif)
```

**Une discipline = un jeu de fichiers.** Valorant a été la première : ses
fichiers portent les noms historiques, sans suffixe. Toute discipline ajoutée
ensuite suit la convention `<nom>_<discipline>.json`. Chaque module dit lui-même
où sont ses fichiers (`GameModule.orgs_path`, `season_path`, `rosters_path`) :
ajouter une discipline n'oblige donc jamais à toucher au chargeur de packs.

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

> **Si toutes les équipes d'une ligue ont la même `strength`**, le jeu comprend
> que le pack ne déclare aucune hiérarchie et en fabrique une, dérivée de la
> graine. C'est le cas du pack VCT : « Fnatic est plus fort que BBL » n'est pas
> une donnée publique, et l'écrire dans le fichier reviendrait à l'affirmer.
> La hiérarchie change donc d'une partie à l'autre — comme les attributs.
> Donnez des valeurs différentes et c'est la vôtre qui s'applique.

`games` liste les **disciplines de la structure**. Identifiants reconnus :
`valorant`, `cs2`, `lol`, `rl`, `apex`, `r6`, `dota2`, `ow2` — un identifiant
inconnu est ignoré plutôt que de créer une section fantôme. Le champ est
facultatif : sans lui, le jeu en déduit une liste plausible à partir de
`strength`. Seules les disciplines effectivement simulées (aujourd'hui Valorant
et Counter-Strike 2) donnent lieu à une équipe ; les autres s'affichent comme
sections non simulées.
Voir [`src/gamemodules/GameCatalog.gd`](../src/gamemodules/GameCatalog.gd).

> **Déclarer `cs2` suffit.** Une structure de votre `orgs.json` qui déclare une
> discipline simulée reçoit une vraie équipe, même si aucun fichier
> `orgs_cs2.json` ne la mentionne : le moteur l'engage à l'étage qui correspond
> à sa `strength`. C'est ce qui évite d'afficher « Counter-Strike 2 — non
> simulée » sur la fiche d'une écurie pendant que le jeu simule une saison CS
> complète à côté.

> Un pack **remplace** le fichier qu'il fournit, il ne s'y ajoute pas. Si votre
> `orgs.json` n'a que les ligues VCT, les Challengers disparaîtront du monde.
> Repartez du fichier livré et modifiez-le.

### `world/orgs_cs2.json`

Même format, avec les clés de ligue de Counter-Strike (`cs_pro_emea`,
`cs_chal_emea`, `cs_open_emea` et leurs équivalents `_americas`, `_pacific`,
`_china`).

**La règle qui fait tout l'intérêt du fichier** : si le `name` d'une entrée
existe déjà dans le monde, la ligne n'invente PAS une structure — elle ouvre une
**section** dans la maison existante, qui partage sa trésorerie, sa marque et sa
direction. C'est ainsi qu'on obtient des écuries à deux rosters sur un seul
grand livre. Les autres lignes créent des structures 100 % Counter-Strike,
comme il en existe beaucoup dans la réalité.

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
