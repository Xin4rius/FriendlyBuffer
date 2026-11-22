# FriendlyBuffer

## v1.4.0

### English

- **Works in combat**: auras are secret in combat on this client. The addon now keeps each player's
  last out-of-combat reading and updates it in combat (buffs and debuffs removed or expired, buffs cast
  from the addon, auras the client still lets addons read).
- **Combat buff grid**: in combat, the list gives way to a grid prepared out of combat, one square per
  group member with the icons of the buffs they miss. Left click: 1st buff of their priorities, right
  click: 2nd, Shift + left / right click: 3rd / 4th. Invisible while nothing is missing. `/fb grid`
  or the Move button to move it.
- **Dispel window**: number of columns and maximum number of rows; debuffs seen out of combat stay
  shown in combat until they are removed.
- **Simulation**: the settings (or `/fb test`) show the combat grid and the dispel window with 1 to 40
  fake players, to set them up out of combat.
- **Settings split into pages**: general, priorities, combat, nameplates.

### Français

- **Fonctionne en combat** : les auras sont secrètes en combat sur ce client. L'addon garde la dernière
  lecture hors combat de chaque joueur et la tient à jour en combat (buffs et débuffs retirés ou
  expirés, buffs lancés depuis l'addon, auras que le client laisse encore lire).
- **Grille de buffs de combat** : en combat, la liste laisse la place à une grille préparée hors combat,
  une case par membre du groupe avec les icônes des buffs qui lui manquent. Clic gauche : 1er buff de
  ses priorités, clic droit : 2e, Maj + clic gauche / droit : 3e / 4e. Invisible tant que rien ne
  manque. `/fb grid` ou le bouton Déplacer pour la déplacer.
- **Fenêtre de dissipation** : nombre de colonnes et nombre de lignes maximum ; les débuffs vus hors
  combat restent affichés en combat jusqu'à leur retrait.
- **Simulation** : les options (ou `/fb test`) affichent la grille de combat et la fenêtre de
  dissipation avec 1 à 40 faux joueurs, pour les régler hors combat.
- **Options réparties en pages** : général, priorités, combat, barres de nom.

## v1.3.0

### English

- **Resurrection** (priest, paladin, shaman): dead group members go to the top of the list, one click
  resurrects them. Once cast, the player is not offered again for 60 s while they accept.
- **Dispel window**: a small borderless grid (one row per raid group) showing only the group members
  carrying a debuff you can remove, with the debuff icon, a border colored by debuff type and the
  player name. Left click: first dispel spell, right click: the second one. Stays in place in combat.
  `/fb dispel` or the Move button in the settings to move it.
- **Counters**: "in place / total" for each buff under the list (detailed mode, in a group), details
  when hovering the window.
- **Ready check**: missing buffs are listed in the chat.
- **Smart group version**: the group / greater version is on the left click only when at least N
  players of the same raid group (or the same class for greater blessings) need it. 2 by default.
- **Coordination** between FriendlyBuffer users of the group: paladins share out blessings, priests,
  mages and druids share out raid groups.
- **Minimap button** (LibDBIcon): left click shows / hides the window, right click opens the settings.
- **Copy priorities** from another character of the same class.
- The settings no longer try to open during combat (forbidden by the game).

### Français

- **Résurrection** (prêtre, paladin, chaman) : les membres du groupe morts passent en tête de liste,
  un clic les relève. Une fois le sort lancé, le joueur n'est plus proposé pendant 60 s, le temps
  qu'il accepte.
- **Fenêtre de dissipation** : une petite grille sans cadre (une ligne par groupe du raid) qui ne
  montre que les membres du groupe porteurs d'un débuff que vous pouvez retirer, avec l'icône du
  débuff, une bordure de la couleur de son type et le nom du joueur. Clic gauche : premier sort de
  dissipation, clic droit : le second. Reste en place en combat. `/fb dispel` ou le bouton Déplacer
  des options pour la déplacer.
- **Compteurs** : « posés / total » pour chaque buff sous la liste (mode informatif, en groupe), le
  détail au survol de la fenêtre.
- **Ready check** : les buffs manquants sont rappelés dans le chat.
- **Version de groupe intelligente** : la version de groupe / supérieure n'est au clic gauche que si
  au moins N joueurs du même groupe du raid (ou de la même classe pour les bénédictions supérieures)
  en ont besoin. 2 par défaut.
- **Coordination** entre utilisateurs de FriendlyBuffer du groupe : les paladins se répartissent les
  bénédictions, les prêtres, mages et druides les groupes du raid.
- **Bouton de la minicarte** (LibDBIcon) : clic gauche affiche / masque la fenêtre, clic droit ouvre
  les options.
- **Copie des priorités** d'un autre personnage de la même classe.
- Les options ne tentent plus de s'ouvrir en combat (interdit par le jeu).
