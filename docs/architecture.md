# Architecture

Wildes uses scene composition and explicit dependency injection. There are no autoloads or singletons.

`app/app.tscn` is the application entry point. `App` owns menu, world-selection, loading, and gameplay transitions. Screens emit intent signals; they do not change scenes or reach into gameplay state.

`game/game.tscn` is the gameplay composition root. It packages the world, player, camera, environment, HUD, and game session. `Game` wires those systems with `setup()` calls after world initialization. `GameSession` owns save cadence and persistence, while `Game` owns gameplay lifecycle and pause flow.

The source tree follows feature ownership:

```text
actors/                      reusable procedural animation
app/                         application navigation
game/                        gameplay composition and session lifecycle
blocks/                      block domain resources and rules
environment/                 packaged environment and day/night feature
inventory/                   inventory model and inventory-owned UI
items/                       item resources, actions, catalogs, and held scenes
player/                      player behavior, camera, and visuals
save/                        save encoding and storage
settings/                    persistent display and rendering configuration
ui/                          app screens, HUD, shared controls, and theme
world/
  chunks/                    streaming, scheduling, meshing, and rendering
  generation/                terrain and biome generation
  materials/                 world shaders and material profiles
  model/                     voxel state and edits
  settings/                  serialized world configuration
  special_blocks/            non-chunk-rendered block visuals
tests/                       headless verification
```

Serialized configuration is explicit and typed. `BlockCatalog` lists `BlockDefinition` resources,
`ItemCatalog` lists item resources and their action definitions, `BiomeLibrary` lists biome
resources, and `WorldConfig` references the biome library. Runtime code does not scan directories
or manufacture fallback domain resources.

Forward+ is the primary renderer. Runtime rendering-device checks select reduced visual values for GL Compatibility fallback. Features unavailable on GL, including volumetric fog, remain disabled there.
