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
combat/                      melee profiles, contacts, targeting, and validation
entities/                    content, AI, navigation, populations, and presentation
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

## Entities and combat

`EntityCatalog` is the authoritative list of stable entity content IDs. Each `EntityDefinition`
references an actor scene, typed behavior, and validated combat stats. `EntityCoordinator` owns a
fresh `ActorStats` instance for every runtime ID alongside spawn/despawn lifecycle, the bounded
spatial index, and active and prepared actor nodes. Zombies and sheep own only their deterministic
behavior state; the shared voxel solver and bounded path follower own reusable movement
calculations. Their custom animation drivers present actor state without deciding gameplay
outcomes. Spawned actors fade in through instance-local geometry transparency. Despawn or lethal
damage removes stats, active state, targeting, and spatial entries together, then a separately
bounded retiring-visual set fades the actor out before freeing its scene node.

`ActorStats` owns current HP, validates prospective modifier values before committing them, and
emits one health-depleted transition when a living actor reaches zero HP. `EntityCoordinator`
consumes that transition for entity retirement, while `Game` consumes the player transition.

`MeleeCombatCoordinator` validates cursor targeting, range, voxel visibility, target existence, and
contact timing before changing health. `MeleeAttackProfile` owns base damage and calculates
`max(1, base damage + attacker strength - target defense)`. A successful physical hit applies that
damage through the target state owner, then produces an immutable `MeleeContact` with stable actor
and attack IDs, world contact position, and normalized direction. Rejected contacts change no
health. `Game` explicitly connects completed contacts to entity reactions, and an effects presenter
can consume the same signal without changing AI or combat rules.

`Game` owns player stats and handles their completed health-depleted transition. Defeat restores
full player HP, cancels current actions and motion, returns the player to world spawn, and snaps the
camera to the restored position without changing inventory. The HUD observes player stats and
presents current and maximum HP without owning either value. Entity HP is transient and is not
serialized. Drops, XP rewards, enemy health bars, regeneration, knockback, death animations, and
post-respawn invulnerability remain outside the combat system.

Entity populations are transient and bounded to six per species and twelve total. Spawning makes
four attempts every two seconds in an 18–36 block annulus. Voxel A* has fixed radius, node, and
failed-search retry budgets. The spatial index contains only active actors, and distance or
chunk-streaming loss removes actors and index entries together. Block placement queries that index
and revalidates world, inventory, reach, player overlap, and active-entity overlap immediately
before committing.

Serialized configuration is explicit and typed. `BlockCatalog` lists `BlockDefinition` resources,
`ItemCatalog` lists item resources and their action definitions, `BiomeLibrary` lists biome
resources, `EntityCatalog` lists entity definitions, and `WorldConfig` references the biome library.
Runtime code does not scan directories or manufacture fallback domain resources.

Forward+ is the primary renderer. Runtime rendering-device checks select reduced visual values for GL Compatibility fallback. Features unavailable on GL, including volumetric fog, remain disabled there.
