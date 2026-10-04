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

## The list

- Players **out of range** of the spell are not shown.
- **Obstacles**: WoW gives no way to know beforehand that a player is out of line of sight. When a
  click fails with "Target not in line of sight", that row is greyed out ("obstacle") and moved to
  the bottom for 5 seconds.
- **Alt + left click**: target the player instead of buffing them.

## Settings

- Group / greater buffs (left click: group version, right click: single version)
- Include strangers, auto-hide when empty, lock the window
- Display mode: minimal (name only) or detailed (spell icon, reason, time left)
- Maximum number of rows, "expiring soon" thresholds (60 s for 5/10 min buffs, 180 s for 30/60 min buffs)
- How long buffed players stay shown as OK (5 s by default, 0 to hide them right away)
- Names on discreet nameplates: font, outline, size, shadow, guild under the name. Defaults look
  like WoW names without Shift+V, with fallback fonts for Chinese, Korean and Cyrillic names.
- Buff priorities per target class: reorder, enable or disable each buff

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

The Gitea Actions workflow (`.gitea/workflows/release.yml`) runs the tests on every push. Pushing a
version tag builds the addon zip (`.pkgmeta`, `@project-version@` replaced by the tag) and creates a
release with the zip and the list of commits since the previous tag. CurseForge picks the new
version up from the GitHub mirror.

```bash
git tag -a v1.2.0 -m "v1.2.0"
```

```bash
git push origin v1.2.0
```

Tags containing `beta` or `alpha` become pre-releases. To create the release of a tag that was
already pushed: Actions → CI / Release → Run workflow, with the tag.

## License

[MIT](LICENSE) © 2026 Xin4rius
