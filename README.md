# FarZoomMinimap

A minimap addon for **WoW Forever** (patch 1.60.1, `## Interface: 16001`) that lets you zoom out past the native minimap's limit and still see your Questie icons, the same ones the big world map shows.

> **Status:** pre-alpha. Phase 0 (the go/no-go spike) hasn't started yet. Nothing here is playable.

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

Not ready yet. Once there's a release, copy the `FarZoomMinimap` folder into your Forever client's `Interface/AddOns/` folder.

## Phase 0 spike

The current build is only the go/no-go spike. Put this repo in `Interface/AddOns/FarZoomMinimap`, log in outdoors with Questie and a few quests, then:

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
