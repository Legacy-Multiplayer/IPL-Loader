# Capsule Corp example

IDE registration and IPL loading using Capsule Corp V2 by
[Kerblaz 398](http://kerblaz398.blogspot.com/).

The example loads eight custom objects plus the terrain replacement, two
stock vehicles (Super GT and Sultan), and a Desert Eagle pickup. The map is
moved 8,000 metres east to avoid overlapping the original GTA terrain.

## Setup

Use a test server with the built-in Constants, Messaging, Model, Object,
Pickup, Player, Vehicle and World addons, plus
[Addon-Sscanf](https://github.com/Legacy-Multiplayer/Addon-Sscanf/releases).

Copy these files:

| Example file | Server destination |
| --- | --- |
| Repository `ipl.lua` and `ide.lua` | `includes/` |
| `main.lua` | `main/main.lua` |
| `map.lua` | `includes/capsule.lua` |
| `capsule.ide` and `capsule.ipl` | `resources/maps/capsule/` |

Set `"main": "main"` in `setup.json`.

Supply the prepared model assets in `assets/maps/capsule/`:

- DFF and individual COL files for `ccorp`, `ccorpe`, `ccorp1`, `ccorp2`,
  `ccorp3`, `ccorp4`, `ccorp5`, `ccesped` and `vgeferryland`.
- `ccorp.txd` and `vgsecoast.txd`.

These model, texture and collision assets are separate from this example.
Use the original author's map files and a prepared copy from your installation.
The original COL collections must be split into one model per file. The terrain
uses the game's `vgsecoast` texture dictionary. The source `ccorp4` also
references `scc_grass`; the tested local preparation supplies that missing name
using the map's existing `scc_groundgrass` texture.

Do not install the map's custom vehicles, peds, CLEO scripts or limit adjuster.
The example uses stock vehicle models instead. The added `cars` and `pick`
records are demonstration placements; the original IPL contained only objects.

## Try it

Start the server and use `/capsule`. You arrive on a stock landing pad while
the custom models stream. `/grove` returns to Grove Street. Stopping the main
script removes the map objects, its vehicles, pickup and arrival pad.
