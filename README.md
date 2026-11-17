<p align="center"><img src="Media/logo.png" width="160" alt="FriendlyBuffer"></p>

# FriendlyBuffer

*English · [Français](README.fr.md)*

A WoW Forever addon (Interface 16001): a small window lists nearby players who could use one of
your class buffs. Click a name to cast the right buff.

A player is listed when a configured buff is **missing**, **about to expire**, or of a **lower
rank** than the one you can cast on them (their level is taken into account).

## Supported classes

- **Paladin**: Might, Wisdom, Kings, Salvation, Light, Sanctuary (+ Greater Blessings).
  Only one of your blessings fits on a target, so the addon picks the first one in your priority
  list that no other paladin has already cast.
- **Priest**: Power Word: Fortitude, Divine Spirit, Shadow Protection (+ Prayers).
- **Mage**: Arcane Intellect (+ Arcane Brilliance), Amplify / Dampen Magic.
- **Druid**: Mark of the Wild (+ Gift of the Wild), Thorns.

## Usage

- `/fb`: show / hide the window
- `/fb options`: settings (also under Options → AddOns → FriendlyBuffer)
- `/fb debug`: scan summary (candidates, rejections, nameplates) and analysis of your target
- `/fb plates`: toggle friendly nameplates (same as Shift+V)
- `/fb reset`: move the window back to the center
- `/fb toggle <buff>`: turn a buff on / off for everyone (handy in a macro)
- `/fb ignore <name>`: ignore a player, or stop ignoring them (Shift + right click on their row); no name: list ignored players
- `/fb dispel`: move the dispel window (same command when done)
- Minimap button: left click = window, right click = settings, drag = move it
- Key binding "buff the first player of the list": Options → Keybindings → AddOns

Players outside your group: WoW only exposes them to addons through **friendly nameplates** (or
your target). Turn them on (Shift+V), or enable the "discreet friendly nameplates" option: the
addon turns them on but only keeps the name (like without Shift+V), and they let clicks through.

Clicking a group member casts the buff without changing your target. For a stranger, the addon
targets them by name, casts the buff, then restores your previous target; if the targeting fails,
nothing is cast. PvP-flagged strangers are skipped unless you are flagged too.

**Chain buffing**: once a player you clicked has their buff, their row moves to the bottom marked
**OK** (for 5 seconds by default, configurable) and the next players move up, so you can keep
clicking the same spot. While your cursor is over the window, new players are only added at the
bottom, never above.

In combat the list is frozen (WoW does not let addons change spell buttons in combat) but stays
clickable; it is rebuilt when combat ends.

## Specializations

For hybrid classes (warrior, paladin, shaman, druid) the buff depends on the spec: an Enhancement
shaman gets Might rather than Wisdom, a Fury warrior gets Salvation but a Protection warrior never
does, a Feral druid gets no Divine Spirit, and so on. The spec (the talent tree with the most
points) is read by **inspecting** the player: one inspection at a time, out of combat, within
inspect range, never while your own inspect window is open. It is remembered and checked again once
per session. Until it is known, the class's "spec unknown" priorities apply. A row's tooltip shows
the detected spec.

## The list

- Players **out of range** of the spell are not shown.
- **Obstacles**: WoW gives no way to know beforehand that a player is out of line of sight. When a
  click fails with "Target not in line of sight", that row is greyed out ("obstacle") and moved to
  the bottom for 5 seconds.
- **Alt + left click**: target the player instead of buffing them.

- **Dead players** (priest, paladin, shaman): dead group members go to the top of the list; a click
  casts the resurrection. Once cast, the player is not offered again for 60 s while they accept.
- **Counters** (detailed mode, in a group): "in place / total" for each buff under the list, details
  when hovering the window. On a ready check, missing buffs are listed in the chat.
- **Smart group version**: the group version is on the left click only when at least N players (2 by
  default) of the same raid group, or of the same class for greater blessings, need it; otherwise the
  single version.

## Coordination

FriendlyBuffer users of the same group announce themselves to each other (addon messages, nothing in
the chat). Paladins: each one gets one blessing per target class, in priority order (the first takes
Kings, the second Wisdom, and so on); if a paladin without the addon already cast it, the usual choice
applies. Priests, mages, druids in a raid: raid groups are split in turn between players of the same
class. `/fb debug` shows the split.

## Dispel window

Priest, paladin, druid, mage, shaman: a small grid with no background or border (one row per raid
group) where only the square of a group member carrying a debuff you can remove shows up: debuff
icon, border in the color of its type, player name. Left click: first dispel spell (priest: magic;
druid: curse; shaman: poison; paladin: Cleanse), right click: the second one (disease, poison…). In
combat, empty squares stay in place but invisible (WoW forbids hiding them); as auras are secret in
combat on this client, detection then relies on the game's "debuffs I can dispel" filter, without the
type (grey border). `/fb debug` on a target tells whether both readings see it.

## Settings

- Group / greater buffs (left click: group version, right click: single version)
- Include strangers, auto-hide when empty, lock the window
- Display mode: minimal (name only) or detailed (spell icon, reason, time left)
- Maximum number of rows, "expiring soon" thresholds (60 s for 5/10 min buffs, 180 s for 30/60 min buffs)
- How long buffed players stay shown as OK (5 s by default, 0 to hide them right away)
- Names on discreet nameplates: font, outline, size, shadow, guild under the name. Defaults look
  like WoW names without Shift+V, with fallback fonts for Chinese, Korean and Cyrillic names.
- Spec detection by inspection, on by default
- Buff priorities per target class and spec: reorder, enable or disable each buff
- Copy the priorities of another character of the same class (saved on logout)
- Resurrection, ready check reminder, coordination, minimap button, group version threshold
- Dispel window: enabled, names on squares, square size, move

## Languages

English (default), French, German, Spanish (Spain and Mexico), Italian, Brazilian Portuguese,
Russian, Korean, Simplified and Traditional Chinese. Translations live in `Locales/`; each string's
key is its English text.

## Offline tests

```bash
lua tests/run.lua
```

```bash
lua tests/smoke.lua
```

## Releasing

The Gitea Actions workflow (`.gitea/workflows/release.yml`) only runs on a `v*` tag. It runs the
tests, then the BigWigs packager builds the zip (excluded files: `ignore` in `.pkgmeta`) and uploads
it to CurseForge (`CF_API_KEY` secret, `CURSEFORGE_PROJECT_ID` variable), with `CHANGELOG.md` as
the release notes. It finally creates the Gitea release of the tag, with the same zip and changelog.
A push without a tag publishes nothing.

Bump `## Version` in the `.toc`, update `CHANGELOG.md`, then:

```bash
git tag -a v1.3.1 -m "v1.3.1"
```

```bash
git push --follow-tags origin main
```

Tags containing `beta` or `alpha` become beta / alpha files on CurseForge.

## License

[MIT](LICENSE) © 2026 Xin4rius
