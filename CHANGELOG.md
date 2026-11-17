# FriendlyBuffer

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
