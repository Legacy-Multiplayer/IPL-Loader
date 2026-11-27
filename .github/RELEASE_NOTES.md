## IDE, vehicles and pickups

- Register custom objects from IDE `objs` definitions and map their original
  IDs to Legacy custom IDs automatically.
- Optionally load stock or registered vehicles from `cars` records.
- Load `pick` records using explicit pickup model/type mappings.
- Unloading or failed creation cleans up the map's objects, vehicles and pickups.
- Includes a Capsule Corp setup example and an in-game screenshot.

**Addon-Sscanf is now required.** Install its DLL or SO in `addons/` before
starting the server. The loader uses its native typed scanner for IPL and IDE
records. Copy both `ipl.lua` and `ide.lua` to `includes/` for IDE support.

The ZIP includes the loader, documentation and example setup files. Capsule
model assets are separate. See the example's README for preparation and credits.

Parser checks run against the actual Addon-Sscanf plugin. Native server checks
also covered Capsule registration, entity creation, ground collision and cleanup.
