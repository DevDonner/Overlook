# FarZoomMinimap

A minimap addon for **WoW Forever** (patch 1.60.1, `## Interface: 16001`) that lets you zoom out past the native minimap's limit and still see your Questie icons, the same ones the big world map shows.

> **Status:** pre-alpha. Phase 0 (the go/no-go spike) hasn't started yet. Nothing here is playable.

## Why

Existing far-zoom minimaps draw extra terrain around the native minimap, but Questie icons stay stuck inside the native minimap's range, or pile up on its edge. FarZoomMinimap reads every pin from the shared HereBeDragons registry (where Questie, TomTom and others register their icons) and draws them itself, in the right place, at any zoom out to about one zone.

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

## Licence

Not chosen yet. All rights reserved until a licence is added.
