# IPL Loader

Use existing IPL placements in your Legacy Multiplayer scripts without
rewriting each object by hand. The loader reads the file and manages the
objects as one map, from creation through cleanup.

## Features

- Reads object placements from text IPL `inst` sections.
- Converts IPL quaternion rotations to GTA-compatible Euler angles.
- Supports stock IDs, registered custom IDs and ID/name mappings.
- Offers position offsets, dimensions, interior filtering and draw distance.
- Creates objects in batches instead of one large spawn loop.
- Skips referenced LOD placements by default to avoid low-detail duplicates.
- Reports malformed records with their filename and line number.
- Cancels pending batches and removes created objects on request.
- Rolls back a map's created objects if a later object cannot be created.

## Installation

Clone the repository:

```bash
git clone https://github.com/Legacy-Multiplayer/IPL-Loader.git
```

Copy `ipl.lua` into your server's `includes` directory, and put your IPL files
somewhere your script can read, such as `resources/maps`:

```text
server/
├── includes/
│   └── ipl.lua
├── main/
│   └── main.lua
└── resources/
    └── maps/
        └── grove-demo.ipl
```

The server must expose `createWorldObject`, `removeWorldObject`, `createTimer`
and `removeTimer`. Use Legacy's essential **Object** addon for the object
functions; timers are provided by the server. The include uses Lua 5.3+ and
Lua's standard file access. No additional Lua dependencies are needed.

## Quick start

Copy `examples/maps/grove-demo.ipl` into `resources/maps`, then add this to
your main script:

```lua
local IPL = require("ipl")
local map

addEventHandler("onMainScriptInit", function()
    local problem
    map, problem = IPL.load("resources/maps/grove-demo.ipl", {
        dimension = 0,
        interior = 0,
    })
    assert(map, problem)

    local started, startError = map:spawn(function(result, success, why)
        if success then
            print("Loaded " .. #result.objects .. " IPL objects")
        else
            print("IPL load failed: " .. tostring(why))
        end
    end)
    assert(started, startError)
end)

addEventHandler("onMainScriptExit", function()
    if map then
        map:destroy()
    end
end)
```

The sample places five stock objects near Grove Street at their original
coordinates. The include does not spawn or teleport players. A complete Grove
Street script with `/ipl`, `/unloadipl` and vehicle commands is provided in
[`examples/main.lua`](examples/main.lua).

![Grove Street example loaded with IPL Loader](docs/images/grove-example.png)

## Load options

```lua
local map, problem = IPL.load("resources/maps/city.ipl", {
    dimension = 0,
    interior = 0,
    offset = { x = 8000, y = 0, z = 0 },
    drawDistance = 400,
    batchSize = 32,
    skipLOD = true,
})
```

| Option | Default | Behavior |
| --- | --- | --- |
| `dimension` | `0` | Dimension in which objects are created, from `0` to `65535`. |
| `interior` | Unset | Selects placements whose interior byte matches. Unset includes all interiors. |
| `offset` | `{x=0, y=0, z=0}` | Adds the same world-space offset to each placement. |
| `drawDistance` | `400` | Object draw distance; greater than `0`, up to `3000`. |
| `batchSize` | `32` | Objects per 50 ms batch, from `1` to `128`. |
| `skipLOD` | `true` | Excludes placements referenced by another placement's LOD index. |
| `models` | Unset | Maps original IDs or model names to stock/custom IDs. |

Dimensions and native GTA interiors are different concepts. `interior` filters
records; it does not change the player's interior or configure native IPL
streaming flags. Offsets translate placements without changing their rotations.

If `models` is supplied, **every selected placement must have a mapping**.
Numeric ID mappings take precedence over name mappings. An unmapped model
produces an error instead of silently spawning the wrong asset.

## Custom models

Custom models use the same loader. Register their DFF/TXD/COL files with
`registerCustomModel` during `onMainScriptInit`, before players join and before
spawning the map. If the IPL already uses those registered IDs, no mapping is
needed.

For an IPL that still contains its original IDs, provide a mapping:

```lua
-- After registering custom object 160001, map the sample's cones to it.
-- Keep the sample's barriers as stock objects.
local map, problem = IPL.load("resources/maps/grove-demo.ipl", {
    interior = 0,
    models = {
        [1238] = 160001,
        [1422] = 1422,
    },
})
assert(map, problem)
```

The loader does not read IDE files, convert assets, register models or download
anything itself. Legacy handles custom asset delivery. Object creation on the
server does not mean every client has finished downloading or loading its
models. Custom collision remains the responsibility of model registration.

## API

### `IPL.load(path, options)`

Returns `map`, or `nil, error`. Reads and validates the complete file before
creating anything. Paths are relative to the server's working directory unless
an absolute path is supplied. Only load paths permitted by your script.

### `map:spawn(onComplete)`

Returns `true` when batching starts, or `false, error` if it cannot start.
`onComplete(map, success, error)` runs when creation finishes or fails. A map
which is already loading or spawned cannot be spawned again.

If creation fails, objects created by that spawn are removed. The loader does
not remove unrelated objects or alter the game's original world.

### `map:destroy()`

Cancels the pending timer, removes the map's objects and returns the map to
`idle`. It can be called more than once. You can spawn the map again afterward.
Cancelling a load does not invoke its completion callback.

### `IPL.parse(text, sourceName)`

Returns the parsed placement list, or `nil, error`, without using object/timer
functions. `sourceName` labels errors. Entries contain `model`, `name`, `flags`,
`interior`, `x`, `y`, `z`, `rx`, `ry`, `rz`, `lod`, `line` and `index`.
`index` and `lod` follow IPL's zero-based indexing; `lod=-1` means no LOD link.

### `IPL.rotation(qx, qy, qz, qw)`

Returns GTA Euler degrees as `rx, ry, rz`. Normalizes the quaternion and applies
IPL's conjugate convention. Invalid components/zero quaternions raise an error.

### Map fields

| Field | Meaning |
| --- | --- |
| `state` | `idle`, `loading`, `spawned` or `failed`. |
| `objects` | IDs of created objects; object ID `0` is valid. |
| `entries` | Selected placements after filtering/mapping. |
| `total` | Number of parsed placements before filtering. |
| `filtered` | Number excluded by interior/LOD filtering. |
| `path` | Source IPL path. |
| `offset` | Translation applied when creating objects. |

## Supported format and limits

San Andreas **text IPL**, with 11 fields per `inst` record:

```text
inst
1238, trafficcone, 0, 2493, -1678, 13.15, 0, 0, 0, 1, -1
end
```

The fields are model ID, model name, instance flags/interior, XYZ position,
quaternion XYZW and the zero-based LOD index.

- Other text sections are ignored; pickups, traffic, zones and paths are not created.
- Binary IPL and GTA III/VC placement formats are not supported.
- Native instance flags beyond the interior byte and automatic LOD linking are not implemented.
- Referenced LOD filtering does not identify standalone LOD meshes by their names.
- Maximum file size is 8 MiB; maximum placement count is 20,000.
- Native/server/client object limits still apply. Large maps can exceed them.
- Parsing happens before spawning; batching spreads object creation, not file parsing.
- Loading a stock GTA IPL at its original coordinates duplicates existing scenery.

## Checks

From the repository root, using Lua 5.3 or newer:

```bash
lua tests/check-ipl.lua
```

Checks cover parsing errors, quaternion matrices/gimbal lock, model mappings,
LOD/interior filtering, object ID zero, batching, cancellation and rollback.
They use mocked native functions and do not prove in-game appearance or
collision. The include has also been checked against a local Legacy server
for sample object creation and removal. Windows/Linux gameplay validation is
separate from these checks.

## License

[MIT](LICENSE). This repository does not distribute GTA game assets or third-party maps.
