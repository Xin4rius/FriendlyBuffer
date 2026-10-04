# FriendlyBuffer

Addon WoW Forever (Interface 16001) : une petite fenêtre liste les joueurs proches à qui vous
pouvez donner un buff de votre classe. Cliquez sur un nom pour lancer le bon buff.

Un joueur apparaît si un buff configuré lui **manque**, **expire bientôt** ou est d'un **rang
inférieur** à ce que vous pouvez lui poser (en tenant compte de son niveau).

## Classes gérées

- **Paladin** : Puissance, Sagesse, Rois, Salut, Lumière, Sanctuaire (+ Bénédictions supérieures).
  Une seule de vos bénédictions par cible : l'addon choisit la première de votre liste de
  priorités qu'aucun autre paladin n'a déjà posée.
- **Prêtre** : Robustesse, Esprit divin, Protection contre l'Ombre (+ Prières).
- **Mage** : Intelligence des Arcanes (+ Illumination), Amplification / Atténuation de la magie.
- **Druide** : Marque du fauve (+ Don du fauve), Épines.

## Utilisation

- `/fb` : afficher / masquer la fenêtre
- `/fb options` : paramètres (aussi dans Options → AddOns → FriendlyBuffer)
- `/fb debug` : bilan du scan (candidats, rejets, barres de nom) et analyse de votre cible
- `/fb plaques` : active / désactive les barres de nom alliées (aussi Maj+V)
- `/fb reset` : replace la fenêtre au centre

Joueurs hors groupe : activez les **barres de nom alliées** pour qu'ils soient détectés. Le clic
les cible par leur nom, lance le buff, puis revient à votre cible précédente. Les inconnus
marqués JcJ sont ignorés si vous ne l'êtes pas.

En combat, la liste est figée (restriction de WoW sur les boutons de sort) mais reste
cliquable ; elle est reconstruite à la sortie du combat. Elle ne se réordonne pas non plus
tant que le curseur est sur la fenêtre, pour éviter de cliquer sur le mauvais joueur.

## Options

Buffs de groupe (clic gauche groupe / clic droit individuel), inclure les inconnus, masquage
automatique, verrouillage, mode d'affichage (minimaliste, informatif, informatif + portée),
nombre de lignes, seuils « expire bientôt », et priorités des buffs par classe de cible.

## Tests hors jeu

```bash
lua tests/run.lua
```

```bash
lua tests/smoke.lua
```

