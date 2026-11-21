# FarZoomMinimap

A minimap addon for **WoW Forever** (patch 1.60.1, `## Interface: 16001`) that lets you zoom out past the native minimap's limit and still see your Questie icons, the same ones the big world map shows.

**Requires [Questie](https://www.curseforge.com/wow/addons/questie).** Questie is the source for quest, townsfolk (mailboxes, flight masters, trainers...) and NPC route icons; the game's own tracking icons only exist at native zoom, so FarZoomMinimap doesn't manage them.

> **Status:** pre-alpha. Phase 0 passed; Phase 1 (square shell and far terrain zoom) is in testing. Questie icons on the far map come in Phase 2.

## Why

Existing far-zoom minimaps draw extra terrain around the native minimap, but Questie icons stay stuck inside the native minimap's range, or pile up on its edge. FarZoomMinimap reads every pin from the shared HereBeDragons registry (where Questie, TomTom and others register their icons) and draws them itself, in the right place, at any zoom out to about one zone.

The full design, with decisions, risks and the test plan, is in [docs/design.md](docs/design.md).

## Planned features

- Smooth zoom past the native limit, out to about one zone (default 2,000 yards, up to 3,200)
- Questie icons drawn one by one at every zoom, kill-objective swords included, with Questie's own tooltips and clicks
- Detailed minimap terrain at every zoom, with a seamless handoff from the native minimap
- Optional rotation (off by default)
- Square, draggable and resizable, with lock, Edit Mode support and a settings page with profiles
- Button tray, coordinates, zone text, clock and auto-zoom when mounted

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
- [Questie](https://github.com/Questie/Questie) for quest icons (optional, but it's the main reason this exists)

## Installation

See [docs/INSTALL.md](docs/INSTALL.md): download a ZIP, clone with Git, or link a working copy into your Forever client's `Interface/AddOns/` folder.

## Using it

- **Mouse wheel** on the map zooms. Past the native minimap's widest step it keeps zooming out over minimap terrain (up to 2,000 yards by default). **Ctrl + wheel** takes half steps.
- **Alt + drag** moves the map.

| Command | Does |
| --- | --- |
| `/fzm size 250` | Map size in px (120-600) |
| `/fzm maxzoom 3200` | Far-zoom limit in yards (500-3,200) |
| `/fzm smooth` | Toggle smooth zooming |
| `/fzm reset` | Move the map back to a visible spot at the default size |
| `/fzm far` | Far-zoom state, for bug reports |

## Phase 0 spike commands

Kept for diagnostics until the spike is removed:

| Command | Checks |
| --- | --- |
| `/fzm selftest` | The automatic checks: APIs, position, facing, pin registries, tile loading |
| `/fzm tiles` | Draws the 5 × 5 terrain tiles around you. The terrain should match your minimap and the red dot should be where you are. `/fzm tiles swap` flips the axes if it doesn't |
| `/fzm dump` | Pin counts by continent, texture and Questie type, plus the hidden flag |
| `/fzm combat` | Then pull a mob: prints whether position and facing still work in combat |
| `/fzm tooltip` | Keep the mouse still: a tooltip whose owner is off-screen should stay up 5 s |
| `/fzm party` | In a group: whether other players' positions are readable |
| `/fzm pos` | Your position, facing, map position and tile |

## Development

- `lua tests/run.lua` runs the offline tests (plain Lua 5.1, no dependencies).
- `luacheck .` lints. CI runs both on every push.

## Licence and credits

Not chosen yet. All rights reserved until a licence is added.

`Data/MinimapTiles.lua` is OpenMap's tile table, used under the MIT licence (`LICENSES/OpenMap-LICENSE.txt`).
