# Instantanés du classement mondial HLTV

Ce dossier contient la **source** de la pyramide Counter-Strike du pack de
données : un relevé daté du classement mondial HLTV.

```
ranking-2026-09-14.json    182 écuries, 874 joueurs
```

`tools/import_hltv.gd` le convertit en pack. La récolte, elle, se fait à la
main — et ce n'est pas un oubli.

## Pourquoi la récolte n'est pas automatisée

HLTV répond **403** à tout client qui n'est pas un navigateur : `curl` avec un
User-Agent de Chrome comme le `HTTPRequest` de Godot. Il n'y a pas de clé d'API
à demander, pas de débit à respecter qui débloquerait la chose. Écrire un
importateur qui « télécharge le classement » serait donc écrire un importateur
qui ne marche pas.

Le partage des rôles est assumé : **la récolte est manuelle et datée, la
conversion est reproductible.** Le fichier d'instantané est dans le dépôt, on
peut donc relire exactement ce qui a produit le pack, et régénérer le pack sans
retoucher au réseau.

## Rafraîchir l'instantané

1. Ouvrir <https://www.hltv.org/ranking/teams> dans un navigateur.
2. Ouvrir la console de développement (F12).
3. Coller le script ci-dessous. Il imprime le JSON complet.
4. Copier le résultat dans un nouveau fichier `ranking-AAAA-MM-JJ.json` de ce
   dossier, en reprenant l'en-tête du fichier existant (`source`,
   `ranking_date`, `captured`, `columns`) et en remplaçant `teams`.
5. Relancer la conversion :

```bash
godot --headless --path . --script res://tools/import_hltv.gd
```

L'importateur prend **le fichier au nom le plus récent** du dossier. Les
anciens instantanés peuvent rester : ils documentent d'où venait un pack.

### Le script à coller

```js
copy(JSON.stringify([...document.querySelectorAll('.ranked-team')].map(el => {
  const pos  = parseInt((el.querySelector('.position')?.textContent || '').replace('#', ''));
  const name = el.querySelector('.name')?.textContent.trim();
  const pts  = parseInt((el.querySelector('.points')?.textContent || '').replace(/\D/g, '')) || 0;
  const players = [...el.querySelectorAll('td.player-holder')].map(td => {
    const alt  = td.querySelector('img.playerPicture')?.getAttribute('alt') || '';
    const nick = td.querySelector('.nick')?.textContent.trim() || '';
    const cc   = ((td.querySelector('img.flag')?.getAttribute('src')) || '')
                   .match(/\/([A-Z0-9]+)\.gif/)?.[1] || '';
    const m = alt.match(/^(.*?)\s*'(.*?)'\s*(.*)$/);   // « Dmitry 'sh1ro' Sokolov »
    return [nick, m ? m[1] : '', m ? m[3].trim() : '', cc];
  }).filter(p => p[0]);
  return [name, pos, pts, players];
})));
```

`copy()` met le résultat dans le presse-papier. Sur un navigateur qui ne
connaît pas `copy()`, remplacer par `console.log(...)`.

## Ce que le classement contient vraiment

Le tableau du classement porte, pour chaque écurie, **le rang, les points, et
les cinq joueurs avec leur pseudo, leur nom civil et leur nationalité** — la
photo de l'effectif ET la hiérarchie, en une seule page. C'est ce qui rend
cette source suffisante à elle seule.

Ce qu'il ne contient pas :

- **la date de naissance** des joueurs — elle n'est que sur les fiches
  individuelles, soit ~450 pages pour un âge. Elle vient donc d'ailleurs :
  voir « Les dates de naissance » plus bas ;
- **le pays de la structure** — on prend la nationalité la plus fréquente de
  l'effectif, qui est de toute façon ce qui décide de sa région de jeu ;
- **le sigle, la couleur, le type de propriétaire** — dérivés du nom, de façon
  stable d'un import à l'autre ;
- **les autres disciplines** de la maison : HLTV ne parle que de
  Counter-Strike. Elles viennent du pack Valorant quand la structure y figure.

## Les dates de naissance et les postes

```bash
godot --headless --path . --script res://tools/import_liquipedia.gd -- \
    --profiles --contact="esport-manager (outil personnel, usage local)"
```

Ils viennent du **wiki Counter-Strike de Liquipedia**, qui répond par lots de
cinquante là où HLTV demanderait une page par joueur. Le résultat est écrit
dans `profiles.json`, à côté de l'instantané : deux sources, deux fichiers,
chacun sa provenance et sa licence (CC-BY-SA 3.0 pour celle-ci). C'est
`import_hltv.gd` qui les fusionne au moment de fabriquer le pack.

Comptez **quatre minutes** : Liquipedia impose une requête toutes les trente
secondes, et le script s'y tient. Relevé réel : **307 dates de naissance et
314 postes sur 372 joueurs** (83 %). Ce qui manque reste généré.

Pourquoi s'embêter :

- **l'âge** fixe la position sur la courbe de progression. Sans lui, apEX est
  un espoir de dix-sept ans qui progresse, là où il devrait être un vétéran de
  trente-trois qui décline ;
- **le poste** est ce qui se remarque le plus vite en Counter-Strike. Il n'y a
  qu'une AWP par équipe et tout le monde sait qui la tient : voir ZywOo rangé
  « soutien » pendant qu'apEX tient l'AWP décrédibilise toute la fiche.

Le wiki ne normalise pas son vocabulaire (`rifle` 146 · `igl` 68 · `awp` 62 ·
`rifler` 35 · `entry` 34 · `support` 16 · `lurk` 13 · …) et une fiche porte
souvent deux postes — `awp,rifle` pour ZywOo. La table de traduction et
l'ordre de priorité sont dans `tools/import_hltv.gd` (`ROLE_MAP`,
`ROLE_PRIORITY`) : on garde le poste qui dit quelque chose, jamais le
« rifleur » par défaut. `igl` n'est pas un poste mais le brassard de
capitaine, et il est traité à part. Le mode `--profiles` imprime le
vocabulaire rencontré à chaque exécution — c'est comme ça qu'on verra
apparaître un libellé que la conversion ne saurait pas traduire.

## Normalisations appliquées à la lecture

- Le préfixe `ex-` d'un effectif sans écurie est retiré (`ex-MANA` → `MANA`) :
  c'est sous ce nom que ces joueurs ont joué la saison.
- Les équipes-école (`… Academy`, `… Junior`) sont écartées : le jeu fabrique
  déjà une académie à chaque structure, et « Spirit Academy » à côté de
  « Spirit » ferait deux maisons là où il n'y en a qu'une.
- Le nom est aligné sur celui que le pack emploie déjà côté Valorant quand les
  deux coïncident une fois l'habillage d'entreprise retiré : `Vitality` →
  `Team Vitality`, `G2` → `G2 Esports`. **C'est cet alignement qui fait qu'une
  maison tient deux sections sur une seule trésorerie** — le moteur rapproche
  les structures par nom exact.

## Licence et usage

Le classement est le **travail éditorial de HLTV**, les noms d'équipes et de
joueurs appartiennent à leurs détenteurs. Ce dépôt est privé et non publié ;
l'instantané et le pack qui en dérive sont à **usage personnel**. Ne les
redistribuez pas comme s'ils faisaient partie du jeu — et le jour où le projet
devrait devenir public, supprimer `packs/` et `tools/hltv/` suffit : plus
aucune ligne du code ne connaît de marque déposée.
