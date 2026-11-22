<p align="center"><img src="Media/logo.png" width="160" alt="FriendlyBuffer"></p>

# FriendlyBuffer

*[English](README.md) · Français*

Addon WoW Forever (Interface 16001) : une petite fenêtre liste les joueurs proches à qui vous
pouvez donner un buff de votre classe. Cliquez sur un nom pour lancer le bon buff.

Un joueur apparaît si un buff configuré lui **manque**, **expire bientôt** ou est d'un **rang
inférieur** à ce que vous pouvez lui poser (en tenant compte de son niveau).

## Classes gérées

- **Paladin** : Puissance, Sagesse, Rois, Salut, Lumière, Sanctuaire (+ Bénédictions supérieures).
  Une seule de vos bénédictions tient sur une cible : l'addon choisit la première de votre liste
  de priorités qu'aucun autre paladin n'a déjà posée.
- **Prêtre** : Robustesse, Esprit divin, Protection contre l'Ombre (+ Prières).
- **Mage** : Intelligence des Arcanes (+ Illumination), Amplification / Atténuation de la magie.
- **Druide** : Marque du fauve (+ Don du fauve), Épines.

## Utilisation

- `/fb` : afficher / masquer la fenêtre
- `/fb options` : paramètres (aussi dans Options → AddOns → FriendlyBuffer)
- `/fb debug` : bilan du scan (candidats, rejets, barres de nom) et analyse de votre cible
- `/fb plaques` (ou `/fb plates`) : active / désactive les barres de nom alliées (comme Maj+V)
- `/fb reset` : replace la fenêtre au centre
- `/fb toggle <buff>` : active / coupe un buff pour tout le monde (pratique en macro)
- `/fb ignore <nom>` : ignore un joueur, ou cesse de l'ignorer (Maj + clic droit sur sa ligne) ; sans nom, liste les ignorés
- `/fb dispel` : déplacer la fenêtre de dissipation (même commande pour finir)
- `/fb grid` : déplacer la grille de buffs de combat (même commande pour finir)
- `/fb test` : simuler un combat avec de faux joueurs (même commande pour arrêter)
- Bouton de la minicarte : clic gauche = fenêtre, clic droit = options, glisser = le déplacer
- Raccourci clavier « buffer le premier joueur de la liste » : Options → Raccourcis → AddOns

Joueurs hors groupe : WoW ne les rend visibles aux addons qu'à travers les **barres de nom
alliées** (ou votre cible). Activez-les (Maj+V), ou cochez l'option « barres de nom alliées
discrètes » : l'addon les active mais n'en garde que le nom (comme sans Maj+V), et elles laissent
passer les clics.

Le clic sur un membre du groupe lance le buff sans changer votre cible. Pour un inconnu, l'addon
le cible par son nom, lance le buff puis rétablit votre cible ; si le ciblage échoue, rien n'est
lancé. Les inconnus marqués JcJ sont ignorés si vous ne l'êtes pas.

**Enchaîner les buffs** : dès que le joueur cliqué a reçu son buff, sa ligne passe en bas avec
**OK** (5 secondes par défaut, réglable) et les suivants remontent : il suffit de cliquer toujours
au même endroit. Tant que le curseur est sur la fenêtre, les nouveaux joueurs s'ajoutent en bas,
jamais au-dessus.

En combat, la liste est figée (WoW interdit aux addons de modifier les boutons de sort en combat)
mais reste cliquable ; elle est reconstruite à la sortie du combat. Les auras étant secrètes en combat
sur ce client, l'addon part de la dernière lecture hors combat de chaque joueur et la tient à jour :
buffs retirés ou expirés, et buffs lancés depuis la liste.

## Spécialisations

Pour les classes hybrides (guerrier, paladin, chaman, druide), le buff dépend de la spé : un chaman
Amélioration reçoit Puissance plutôt que Sagesse, un guerrier Fureur reçoit le Salut mais jamais un
guerrier Protection, un druide farouche n'a pas d'Esprit divin, etc. La spé (l'arbre de talents le
plus rempli) est lue en **inspectant** le joueur : une inspection à la fois, hors combat, à portée
d'inspection, jamais quand votre fenêtre d'inspection est ouverte. Elle est mémorisée et vérifiée
une fois par session. Tant qu'elle est inconnue, les priorités « spé inconnue » de la classe
s'appliquent. L'infobulle d'une ligne indique la spé détectée.

## La liste

- Les joueurs **hors de portée** du sort ne sont pas affichés.
- **Obstacles** : WoW ne permet pas de savoir à l'avance si un joueur est hors de vue. Si un clic
  échoue avec « La cible n'est pas en vue », la ligne est grisée (« obstacle ») et placée en bas
  pendant 5 secondes.
- **Alt + clic gauche** : sélectionne le joueur au lieu de le buffer.

- **Morts** (prêtre, paladin, chaman) : les membres du groupe morts passent en tête de liste ; un
  clic lance la résurrection. Une fois le sort lancé, le joueur n'est plus proposé pendant 60 s, le
  temps qu'il accepte.
- **Compteurs** (mode informatif, en groupe) : sous la liste, « posés / total » pour chaque buff ; le
  détail au survol de la fenêtre. Au ready check, les buffs manquants sont rappelés dans le chat.
- **Version de groupe intelligente** : la version de groupe n'est proposée au clic gauche que si au
  moins N joueurs (2 par défaut) du même groupe du raid, ou de la même classe pour les bénédictions
  supérieures, en ont besoin ; sinon, la version individuelle.

## Coordination

Les joueurs de FriendlyBuffer d'un même groupe s'annoncent entre eux (messages d'addon, sans rien
dans le chat). Paladins : chacun reçoit une bénédiction par classe de cible, dans l'ordre des
priorités (le premier prend Rois, le deuxième Sagesse, etc.) ; si un paladin sans l'addon l'a déjà
posée, on revient au choix habituel. Prêtres, mages, druides en raid : les groupes du raid sont
répartis à tour de rôle entre joueurs de la même classe. `/fb debug` affiche la répartition.

## Fenêtre de dissipation

Prêtre, paladin, druide, mage, chaman : une petite grille sans fond ni cadre (une ligne par groupe
du raid) où n'apparaît que la case d'un membre du groupe portant un débuff que vous pouvez retirer :
icône du débuff, bordure de la couleur de son type, nom du joueur. Clic gauche : premier sort de
dissipation (prêtre : magie ; druide : malédiction ; chaman : poison ; paladin : Épuration), clic droit :
le second (maladie, poison…). En combat, les cases vides restent en place mais invisibles (WoW
interdit de les masquer) ; les auras étant secrètes en combat sur ce client, la détection s'appuie alors
sur les débuffs vus hors combat et encore présents, ceux ajoutés en combat quand le client les laisse lire,
et le filtre « débuffs que je peux dissiper » du jeu (type inconnu : bordure grise).
`/fb debug` sur une cible indique si les deux lectures la voient.

**Grille de buffs de combat** : la liste ne pouvant pas gagner de boutons en combat, une grille est
préparée hors combat avec une case par membre du groupe : son nom et, côte à côte, les icônes des buffs
qui lui manquent. Les clics suivent les priorités de ce joueur : clic gauche 1er buff, clic droit 2e,
Maj + clic gauche 3e, Maj + clic droit 4e (bulle d'aide sur la case). Elle n'apparaît qu'en combat, à la
place de la liste ; une case reste invisible tant que rien ne manque (atténuée hors de portée). Les cases
invisibles restent en place et captent la souris : WoW interdit de les masquer en combat. Réglages :
activation, noms, taille des icônes et bouton Déplacer (ou `/fb grid`). La fenêtre de dissipation a aussi
un nombre de colonnes et un nombre de lignes maximum.

**Simulation** : les options (ou `/fb test`) peuvent afficher hors combat la grille de buffs de combat
et la fenêtre de dissipation comme en combat, avec 1 à 40 faux joueurs (plus de 5 : disposition de raid)
à qui il manque des buffs et qui portent des débuffs à retirer. L'état change toutes les quelques
secondes ; les cases simulées ne lancent rien, et un vrai combat arrête la simulation.

## Options

- Buffs de groupe / supérieurs (clic gauche : version de groupe, clic droit : version individuelle)
- Inclure les inconnus, masquage automatique quand la liste est vide, verrouillage de la fenêtre
- Mode d'affichage : minimaliste (nom seul) ou informatif (icône du sort, raison, temps restant)
- Nombre de lignes maximum, seuils « expire bientôt » (60 s pour les buffs de 5/10 min, 180 s pour
  ceux de 30/60 min)
- Durée d'affichage « OK » des joueurs buffés (5 s par défaut, 0 pour les retirer aussitôt)
- Noms des barres discrètes : police, contour, taille, ombre, guilde sous le nom. Par défaut, ils
  ressemblent aux noms de WoW sans Maj+V, avec des polices de secours pour les noms chinois, coréens
  et cyrilliques.
- Détection de la spé des joueurs (inspection), activée par défaut
- Priorités des buffs par classe et spé de cible : réordonner, activer ou désactiver chaque buff
- Copier les priorités d'un autre personnage de la même classe (sauvegardées à la déconnexion)
- Résurrection, rappel au ready check, coordination, bouton de la minicarte, seuil de la version de groupe
- Fenêtre de dissipation : activée, noms sur les cases, taille des cases, colonnes, lignes, déplacer

## Langues

Anglais (par défaut), français, allemand, espagnol (Espagne et Mexique), italien, portugais
(Brésil), russe, coréen, chinois simplifié et traditionnel. Les traductions sont dans `Locales/` ;
la clé de chaque texte est sa version anglaise.

## Tests hors jeu

```bash
lua tests/run.lua
```

```bash
lua tests/smoke.lua
```

## Publier une version

Le workflow Gitea Actions (`.gitea/workflows/release.yml`) ne se lance que sur un tag `v*`. Il
lance les tests, puis le packager BigWigs construit le zip (fichiers exclus : `ignore` de
`.pkgmeta`) et l'envoie sur CurseForge (secret `CF_API_KEY`, variable `CURSEFORGE_PROJECT_ID`),
avec `CHANGELOG.md` comme notes de version. Il crée enfin la release Gitea du tag, avec le même
zip et le même changelog. Un push sans tag ne publie rien.

Monter `## Version` dans le `.toc`, compléter `CHANGELOG.md`, puis :

```bash
git tag -a v1.3.1 -m "v1.3.1"
```

```bash
git push --follow-tags origin main
```

Un tag contenant `beta` ou `alpha` donne une version bêta / alpha sur CurseForge.

## Licence

[MIT](LICENSE) © 2026 Xin4rius
