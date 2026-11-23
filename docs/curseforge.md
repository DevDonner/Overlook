<!-- The CurseForge project description: paste into the project's Description (Markdown).
     Screenshots: upload them to the project's Images tab, then replace each SCREENSHOT_URL_... below
     with the image's link (right-click the uploaded image, copy image address). -->

# Overlook

**Zoom your minimap out, keep every Questie icon on it, and plan your next move without ever opening the world map.**

## Why I made it

I wanted a minimap that could zoom out seamlessly while still working with Questie and all of its quest icons, no matter where I panned. Now I can zoom out, find the next area with quest objectives, and plan my route, then either zoom back in or leave the map zoomed out while I cover the distance.

I can even see quest turn-ins from across the continent, right on my minimap.

![The minimap in its default position](SCREENSHOT_URL_DEFAULT)

*Right where your minimap always is, until you scroll.*

## Why Questie is required

Questie knows where every quest objective, turn-in, available quest, trainer, flight master and mailbox is. Overlook is what lets you see all of that from far away.

The game's own minimap only shows icons in a small circle around you. Zoom out with Questie alone and its icons stay stuck in that circle or pile up on the edge. Overlook draws the terrain past the native limit and puts every Questie icon in its real place at every zoom level. You can hover and click them, just like on Questie's world map.

No Questie means no icons to show, so Questie is a required dependency.

**Requires [Questie](https://www.curseforge.com/wow/addons/questie).**

![Zoomed out: quest objectives and turn-ins across the zone](SCREENSHOT_URL_ZOOMED_OUT)

*Scroll out past the old limit. Every objective, turn-in and available quest stays on the map.*

![Panned away from the player to scout another area](SCREENSHOT_URL_PANNED)

*Drag to look anywhere. Middle-click or double-click snaps back to you.*

![A cave with its levels stacked](SCREENSHOT_URL_CAVES)

*Caves show every level at once. Alt + wheel peels off the top level, one at a time.*

## Features

- **Far zoom**: mouse wheel past the native limit, out to 3,000 yards by default (up to 6,400). Smooth or stepped.
- **Questie icons and routes** at every zoom, with Questie's tooltips and clicks.
- **Other addons' icons**: RareScanner, TomTom and anything else on the shared map-pin registry, each group with its own show, size and shrink-with-zoom.
- **Quest areas**: the game's blue quest areas, drawn on the far map too.
- **Caves**: the whole cave with every level stacked; **Alt + wheel** peels off the top level, one at a time. Floors in cities and dungeons.
- **Dungeon and raid entrances** on both maps: hover one for its name and level range, coloured for your level.
- **Party and raid** members as class-coloured dots; **pings** shown on the far map.
- **Pan** by dragging; **Recenter**, middle-click or double-click to come back.
- **Mount zoom**: zooms out when you mount, back when you dismount.
- **Bars**: zone name on top, with calendar and addon buttons; coordinates, zoom distance and a clock below.
- **Button panel**: other addons' minimap buttons gathered behind one button.
- **Square or round**, movable (Alt + drag), resizable from the corner, lockable. Optional rotation on the round map.
- **Profiles** with export and import strings.

## How to use

| | |
| --- | --- |
| Mouse wheel | Zoom (Ctrl + wheel: half steps) |
| Drag | Pan |
| Middle-click / double-click | Recenter |
| Right-click | Ping |
| Alt + drag | Move the map |
| Alt + wheel | Cave levels and floors |
| `/overlook` or `/ol` | Settings (also the minimap button and the addon compartment) |

`/overlook help` lists every command, including checks that help with bug reports (`/overlook far`, `/overlook pins`, `/overlook questie`).

## Bugs and ideas

Please include what `/overlook far` and `/overlook questie` print.
