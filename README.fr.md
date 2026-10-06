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
mais reste cliquable ; elle est reconstruite à la sortie du combat.

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

Le workflow Gitea Actions (`.gitea/workflows/release.yml`) lance les tests à chaque push. Pousser
un tag de version construit le zip de l'addon (`.pkgmeta`, `@project-version@` remplacé par le tag)
et crée une release avec le zip et la liste des commits depuis le tag précédent. CurseForge
récupère la nouvelle version depuis le miroir GitHub.

```bash
git tag -a v1.2.0 -m "v1.2.0"
```

```bash
git push origin v1.2.0
```

Un tag contenant `beta` ou `alpha` donne une pré-version. Pour créer la release d'un tag déjà
poussé : Actions → CI / Release → Run workflow, avec le tag.

## Licence

[MIT](LICENSE) © 2026 Xin4rius
