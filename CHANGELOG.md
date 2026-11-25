# Overlook

## 1.1.0

Plays nicely with other minimap addons, and the map can have all the room it's given.

Heads-up: if you had the top bar switched off, the calendar and addons buttons now move into a small column at the map's side instead of disappearing. Settings > Layout > Buttons: Off brings back the old look.

- Compact layouts. Our buttons (calendar, addons, the minimap-buttons panel) can sit in a slim column at the map's left or right edge, on the map or outside it against the edge, instead of on the bars, so the bars can go and the map keeps its full height. A bar that's switched off hands its buttons to that column instead of losing them. Quick layouts in the settings: Full, Compact (zone name over the map, buttons at its side, no bottom bar) and Map only (no bars, no buttons).
- EllesmereUI's minimap (or any addon that keeps the minimap for itself): Overlook no longer fights it for the map. It fits inside: the other addon keeps the map's size, place, shape, border, buttons and zone text, and Overlook adds the far zoom to its map. Can be switched off.
- Nothing is taken over that can't be given back. Each takeover has its own switch on the new Addons tab: gathering other addons' minimap buttons (now given back the moment it's switched off, no /reload), switching off other clocks, coordinates and zone text, hiding the game's zone header and buttons, and answering other addons' questions about the map's shape.
- Other addons' buttons, text and borders on the minimap stay showing when you zoom out, instead of disappearing with the normal minimap.
- Other addons that draw straight onto the minimap without HereBeDragons (route dots, item and rare finders) are copied onto the far map at the right places. Each addon gets an icon group on the Icons tab to hide or resize. `/overlook others` shows what was found.
- Simpler settings. The Layout tab (was Bars) asks one question per row: layout, where the zone name goes (above the map, on it, or off), the info bar, the buttons and their column. Settings that don't apply right now are hidden, and the finer ones are folded under Advanced. The new Addons tab says whether another minimap addon is running and has two switches up front, the rest under Advanced.

## 1.0.1

- Undercity draws on the far map. The game counts Undercity as outdoors, so before this fix the far map showed the Tirisfal surface there.

## 1.0.0

First release, for WoW Forever (1.60.1). Requires Questie.

- Zoom the minimap past its native limit, out to about one zone (3,000 yards by default, up to 6,400), smoothly or in steps.
- Questie icons on the far map at every zoom, with Questie's own tooltips and clicks; Questie's NPC patrol routes too.
- Other addons' map icons (RareScanner, TomTom), with per-group show, size and shrink-with-zoom.
- Party and raid members as class-coloured dots.
- Dungeon and raid entrances on the normal and the far minimap; hover for the name and level range, coloured for your level.
- The game's blue quest areas on the far map, with adjustable opacity.
- Caves on the far map with every level stacked; Alt + wheel peels them off one at a time. Floors in cities and dungeons.
- Pings drawn on the far map.
- Drag to pan; Recenter, middle-click or double-click to come back.
- Zooms out when you mount, back in when you dismount.
- Zone name bar, and a bottom bar with coordinates, zoom distance and a clock.
- Calendar and addon buttons on the top bar; other addons' minimap buttons gathered into a panel.
- Square or round; movable, resizable, lockable. Optional rotation on the round map at normal zoom.
- The round map has a layout of its own: the zone name, buttons, coordinates, zoom distance and clock in separate boxes under the circle.
- Questie's icon switches in our settings window, plus arrow size and route line width.
- Settings profiles, with export and import strings.
- A welcome window on first login with every control; the Instructions button on the settings' Map tab brings it back.
