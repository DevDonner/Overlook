# FarZoomMinimap

A minimap addon for **WoW Forever** (patch 1.60.1, `## Interface: 16001`) that lets you zoom out past the native minimap's limit and still see your Questie icons, the same ones the big world map shows.

**Requires [Questie](https://www.curseforge.com/wow/addons/questie).** Questie is the source for quest, townsfolk (mailboxes, flight masters, trainers...) and NPC route icons; the game's own tracking icons only exist at native zoom, so FarZoomMinimap doesn't manage them.

> **Status:** alpha. The square shell, far terrain zoom, Questie icon mirror, NPC routes, party dots, pan and recenter, and the settings window all work in game; rotation, profiles and the button tray are still to come.

## Why

Existing far-zoom minimaps draw extra terrain around the native minimap, but Questie icons stay stuck inside the native minimap's range, or pile up on its edge. FarZoomMinimap reads every pin from the shared HereBeDragons registry (where Questie, TomTom and others register their icons) and draws them itself, in the right place, at any zoom out to about one zone.

The full design, with decisions, risks and the test plan, is in [docs/design.md](docs/design.md).

## Features

- Zoom past the native limit, out to about one zone (default 2,000 yards, up to 3,200), smoothly or in steps
- Questie icons at every zoom (kill swords, turn-ins, available quests, townsfolk...) with Questie's own tooltips and clicks
- Questie's NPC patrol routes on the far map
- Other addons' map icons too (RareScanner, TomTom): per-group show, size and shrink-with-zoom
- Party and raid members as class-coloured dots on the far map
- Drag to pan, with a Recenter button; a panned map stays put while you move
- Square, movable (Alt + drag) and resizable from its corner, with a lock
- Settings window, minimap button and addon compartment entry

Planned: optional rotation, profiles, Edit Mode support, button tray, coordinates and zone text.

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
- **Drag** the map to pan; **Recenter** (under the map) goes back to you. Zooming back in while centred hands over to the native minimap.
- **Alt + drag** moves the map; the **corner grip** resizes it.
- **Alt + wheel** in a cave (or a city or dungeon with floors) changes level on the far map: down goes a level deeper, and past the bottom level it comes back to the top.
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
| `/fzm caves` | Which cave the far view would draw here, its levels and the one shown, for checking in game |
| `/fzm underground` | What map the far view would draw here (underground cities, dungeons), for checking in game |
| `/fzm questie` | Check the Questie parts the far map uses (also run once after login; quiet when all is well) |
| `/fzm far`, `/fzm pins`, `/fzm routes` | State, for bug reports |

## Development

- `lua tests/run.lua` runs the offline tests (plain Lua 5.1, no dependencies).
- `luacheck .` lints. CI runs both on every push.

## Licence and credits

Not chosen yet. All rights reserved until a licence is added.

`Data/MinimapTiles.lua` is OpenMap's tile table, used under the MIT licence (`LICENSES/OpenMap-LICENSE.txt`).
