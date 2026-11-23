# FarZoomMinimap

A minimap addon for **WoW Forever** (patch 1.60.1, `## Interface: 16001`) that lets you zoom out past the native minimap's limit and still see your Questie icons, the same ones the big world map shows.

**Requires [Questie](https://www.curseforge.com/wow/addons/questie).** Questie is the source for quest, townsfolk (mailboxes, flight masters, trainers...) and NPC route icons; the game's own tracking icons only exist at native zoom, so FarZoomMinimap doesn't manage them.

> **Status:** alpha. Everything listed below is built; most of it has been checked in game, and the newest parts (pings, the button panel, cave stacking, mount zoom) are waiting on in-game checks.

## Why

Existing far-zoom minimaps draw extra terrain around the native minimap, but Questie icons stay stuck inside the native minimap's range, or pile up on its edge. FarZoomMinimap reads every pin from the shared HereBeDragons registry (where Questie, TomTom and others register their icons) and draws them itself, in the right place, at any zoom out to about one zone.

The full design, with decisions, risks and the test plan, is in [docs/design.md](docs/design.md).

## Features

- Zoom past the native limit, out to about one zone (default 2,000 yards, up to 3,200), smoothly or in steps
- Questie icons at every zoom (kill swords, turn-ins, available quests, townsfolk...) with Questie's own tooltips and clicks
- Questie's NPC patrol routes on the far map
- Other addons' map icons too (RareScanner, TomTom): per-group show, size and shrink-with-zoom
- Party and raid members as class-coloured dots on the far map
- The game's blue quest areas on the far map, with adjustable opacity
- Caves drawn on the far map, one level at a time
- Drag to pan, with a Recenter button; a panned map stays put while you move
- Zooms out when you mount and comes back when you dismount (adjustable)
- Zone name bar above the map and a bottom bar with coordinates, zoom distance and a clock
- Square or round, movable (Alt + drag) and resizable from its corner, with a lock
- Questie's icon switches in our own settings window, plus player arrow size and route line width
- Settings profiles, with export and import strings for sharing
- Settings window, minimap button and addon compartment entry

- Optional rotating minimap at normal zoom, on the round map only (off by default; the far map stays north-up)

Planned: Edit Mode support.

## Roadmap

| Phase | Goal |
| --- | --- |
| 0 | Spike: confirm player position, facing, the HBD registry and terrain tile IDs work on Forever; set up the offline test harness |
| 1 | Core shell and far terrain tiles |
| 2 | Pin mirror: Questie icons, tooltips and clicks on the far map |
| 3 | Rotation and performance budgets |
| 4 | Usability: settings, profiles, button tray, Edit Mode |
| 5 | Extras: round shapes, quest name bubbles, trail path |

## Requirements

- WoW Forever client (1.60.1)
- [Questie](https://github.com/Questie/Questie) (required)

## Installation

See [docs/INSTALL.md](docs/INSTALL.md): download a ZIP, clone with Git, or link a working copy into your Forever client's `Interface/AddOns/` folder.

## Using it

- **Mouse wheel** on the map zooms. Past the native minimap's widest step it keeps zooming out over minimap terrain. **Ctrl + wheel** takes half steps.
- **Drag** the map to pan; **Recenter** (under the map), a **middle-click** or a **double-click** goes back to you. Zooming back in while centred hands over to the native minimap.
- **Right-click** the far map to ping, like a click on the normal minimap. The game only pings within the normal minimap's range.
- **Alt + drag** moves the map; the **corner grip** resizes it.
- **Alt + wheel** in a cave changes level on the far map: it opens with every level stacked, each step down peels off the top level, and past the bottom the whole stack comes back. In a city or dungeon with floors it steps through the floors.
- **`/fzm`** opens the settings, as do the minimap button (right-click: recenter) and the addon compartment.

| Command | Does |
| --- | --- |
| `/fzm` | Open the settings |
| `/fzm size 250` | Map size in px (120-600) |
| `/fzm maxzoom 3200` | Far-zoom limit in yards (500-3,200) |
| `/fzm smooth` | Toggle smooth zooming |
| `/fzm lock` | Lock or unlock the size |
| `/fzm icons` | List icon groups; e.g. `/fzm icons rarescanner size 0.6` |
| `/fzm reset` | Move the map back to a visible spot at the default size |
| `/fzm options coord` | The game's own options whose label has that text, their values and CVars |
| `/fzm buttons` | The minimap buttons gathered into the bottom bar's panel |
| `/fzm overrides` | What the bars switched off in other addons and the game (and what it was before) |
| `/fzm areas` | Whether the far view can draw quest areas here, and how many zones it is drawing |
| `/fzm caves` | Which cave the far view would draw here, its levels and the one shown, for checking in game |
| `/fzm underground` | What map the far view would draw here (underground cities, dungeons), for checking in game |
| `/fzm questie` | Check the Questie parts the far map uses (also run once after login; quiet when all is well) |
| `/fzm far`, `/fzm pins`, `/fzm routes` | State, for bug reports |

## Development

- `lua tests/run.lua` runs the offline tests (plain Lua 5.1, no dependencies).
- `luacheck .` lints. CI runs both on every push.

## Licence and credits

MIT: see `LICENSE`.

`Data/MinimapTiles.lua` is OpenMap's tile table, used under the MIT licence (`LICENSES/OpenMap-LICENSE.txt`).
`Data/Caves.lua` is generated from the game's own files by `tools/map-data/caves.py`, and holds only file IDs and positions, no game art.
