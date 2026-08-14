# Architecture

Wildes uses scene composition and explicit dependency injection. There are no autoloads or singletons.

`app/app.tscn` is the application entry point. `App` owns menu, world-selection, loading, and gameplay transitions. Screens emit intent signals; they do not change scenes or reach into gameplay state.

`game/game.tscn` is the gameplay composition root. It packages the world, player, camera, environment, HUD, level interaction, and game session. `Game` wires those systems with `setup()` calls after world initialization. `GameSession` owns save cadence and persistence, while `Game` owns gameplay location, transitions, and pause flow.

The source tree follows feature ownership:

```text
actors/                      reusable procedural animation
app/                         application navigation
game/                        gameplay composition and session lifecycle
blocks/                      block domain resources, voxel query contract, and shared presentation
combat/                      melee profiles, contacts, targeting, and validation
crafting/                    recipe definitions, inventory coordination, and presentation
entities/                    content, AI, navigation, populations, and presentation
environment/                 packaged environment and day/night feature
inventory/                   inventory model and inventory-owned UI
items/                       item resources, actions, catalogs, and held scenes
levels/                      finite dungeon content, generation, runtime, entrance, and presentation
player/                      player behavior, camera, and visuals
progression/                 combat rewards and shared item proficiency
save/                        save encoding and storage
settings/                    persistent display and rendering configuration
ui/                          app screens, HUD, shared controls, and theme
world/
  chunks/                    streaming, scheduling, meshing, and rendering
  generation/                terrain and biome generation
  materials/                 world shaders and material profiles
  model/                     voxel state and edits
  settings/                  serialized world configuration
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
damage removes stats, active state, targeting, and spatial entries together. Lethal retirement
plays the species-owned death pose, then starts an actor-owned one-shot smoke poof and model fade
together; the scene is freed only after both complete. Ordinary distance and streaming retirement
uses only the fade. The retiring-visual cap bounds actors, fades, and their child particle effects
to twelve concurrent presentations and evicts the earliest retained presentation first.

Stat definitions validate every declared base value as finite and nonnegative. `ActorStats` owns
current HP, validates every removable subset of prospective modifiers before committing them, and
emits one health-depleted transition when a living actor reaches zero HP. `EntityCoordinator`
consumes that transition for entity retirement, while `Game` consumes the player transition.

`MeleeCombatCoordinator` validates cursor targeting, range, sweep arc, voxel visibility, target
existence, and contact timing before changing health. `MeleeAttackProfile` owns base damage and an
optional sweep angle. Player swings lock sorted spatial-index candidates from the cursor ray at
attack start, then independently revalidate every locked target at contact; a zero-degree sweep
retains exact single-target ray selection, while a full-circle sweep is independent of planar cursor
aim. The profile calculates
`max(1, base damage + attacker strength - target defense)`. Each successful physical hit applies
that damage through the target state owner, then produces an immutable `MeleeOutcome` containing
the contact, exact applied damage, source item ID, and lethal result. Rejected contacts change no
health and produce no outcome. `Game` explicitly connects completed outcomes to entity reactions,
progression, and presentation without making combat own those policies.

`ActorStats` owns the player's level and current-level experience. `CombatProgressionCoordinator`
awards the reward authored on an `EntityDefinition` exactly once for a player-caused defeat.
Zombie and sheep rewards are currently ten experience and remain content values for later tuning.
The same coordinator translates each target's applied player damage into weapon proficiency and
each incoming damage result into full proficiency credit for every equipped armor piece. These
policy methods are isolated from combat resolution so their earning rules can change independently.
`ItemProficiency` owns deterministic progress keyed by stable item definition ID, so every copy of
an item type shares progress. Each item directly references a `ProficiencyDefinition` resource with
explicit per-level requirements and slot unlock levels; zero is an initially free slot. Current
Common combat gear unlocks its one slot at proficiency level one after one hundred damage.

Combat items also reference an `ItemRarityDefinition` with a stable ID, display name, and display
color. `ItemCatalog` requires rarity and proficiency definitions for melee weapons and armor and
rejects different rarity resources that reuse one ID. Rarity remains classification metadata;
attack profiles, stat modifiers, and proficiency definitions stay authoritative for combat values,
equipment bonuses, and unlock thresholds.

`InventorySlot` presents combat-item and rune details for hotbar, backpack, and equipped slots
through one custom `ItemTooltip`. `Game` passes `ItemProficiency` through `HUD`, `Hotbar`, and
`SidePanel` into each slot, and a visible tooltip queries current progress without owning it.
Weapon rows read the item's melee attack profile, while armor rows read its slot and stat
modifiers, so presentation does not own or duplicate gear state. During a left-button drag, the
source slot owns the adjustable drag count and consumes wheel input before gameplay camera handling.
`InventoryModel` remains the authority for partial moves and discards, while the source and
drag-preview visuals show the pending split without mutating inventory until a drop succeeds.

## Runes and socketing

`RuneDefinition` is typed item content with rarity, weapon and armor compatibility, optional armor
slot restrictions, and socket-only stat modifiers. The Basic Rune is Common, is compatible with
every melee weapon and armor slot, and adds one hundred maximum HP. Its crafting recipe exchanges
thirty-two Sand for one stackable rune. Enchantments remain outside the implemented system.

Each `InventoryStack` owns the stable rune IDs installed on that physical gear copy. The array
preserves physical slot positions, permits an empty value between filled positions, and omits
trailing empty positions. `InventoryModel` preserves that state across full-stack moves and save
round trips. It commits socketing as one transaction that consumes exactly one inventory rune and
updates the target copy. Unsocketing updates the copy and returns the rune together, or rejects the
whole command when the inventory has no capacity.

`RuneSocketingCoordinator` combines the target item's `ProficiencyDefinition`, shared
`ItemProficiency`, and `RuneDefinition` compatibility into the socket command and query API. It
does not own inventory state. The Rune workspace presents one referenced inventory gear slot and
three physical rune slots; it delegates every mutation to the coordinator and keeps the backpack
visible as the drag source.

`RuneEffectCoordinator` derives active modifiers from socketed runes on the selected melee weapon
and all equipped armor. It replaces one bounded `ActorStats` modifier source whenever that active
loadout changes, so duplicate runes stack without accumulating stale runtime modifiers. Maximum-HP
changes preserve the player's current health percentage. Runes on unselected weapons and unequipped
armor remain persisted but inactive. Setup validates each rune and a conservative maximum active
loadout before inventory changes can drive effect replacement.

`Game` owns player stats and handles their completed health-depleted transition. Defeat puts
the player motor into an input-blocking stopped state, closes inventory and debug panels, and
presents a high-layer death screen without pausing world time or entity simulation. The screen
emits respawn or main-menu intent back to `Game`; respawn restores full HP at world spawn, snaps the
camera, and removes the modal without changing inventory. The HUD observes player stats and
presents health plus level progress without owning either value.
`SidePanel` owns its animation
progress and reports committed progress changes to `HUD`, which translates that value into the
right inset so presentation state stays clear of the inventory panel and narrows within the
available viewport when necessary. Entity HP is transient and is not serialized. Drops, enemy
health bars, regeneration, knockback, death audio, and post-respawn invulnerability remain
outside the combat system.

`GameSession` owns save suspension as part of the gameplay lifecycle. Suspension or authoritative
zero HP blocks manual, periodic, and edit-debounce writes while session playtime continues
accumulating. Respawn, Main Menu, and window close restore a living player at world spawn before
saving resumes; exit paths then use the normal final-save and shutdown flow so zero HP is never
persisted. Loading a historical zero-HP snapshot restores full health at world spawn before gameplay
begins and immediately replaces the stored snapshot with that living state.
Save version six stores item proficiency separately and includes per-stack socket IDs in inventory.
Version-four saves first gain empty item proficiency, and version-five inventory stacks then gain
empty socket arrays. The migration chain operates on a copy and commits only after every region is
valid, preserving the original data on failure.

Entity populations are transient and bounded to six per species and twelve total. Spawning makes
four attempts every two seconds in an 18–36 block annulus. Voxel A* has fixed radius, node, and
failed-search retry budgets. The spatial index contains only active actors, and distance or
chunk-streaming loss removes actors and index entries together. Block placement queries that index
and revalidates world, inventory, reach, player overlap, and active-entity overlap immediately
before committing.

## Voxel spaces and levels

`VoxelSpace` is the read-only query boundary shared by the streamed `VoxelWorld` and immutable
`LevelState`. Player setup is one-time; `Game` atomically rebinds movement, collision, targeting,
and edit capabilities when the active space changes. Dungeon levels never become save-state
owners: saves receive an explicit overworld position while retaining the version-five format,
version-four migration, and item proficiency state.

Dungeon content is selected through stable typed resources. `LevelEntranceDefinition` maps a
doorway ID to a level ID and owns its current doorway presentation. `LevelDefinition` selects its
module pools and `LevelPresentationDefinition`; `LevelCatalog` resolves the stable IDs. Generated
torch placements remain presentation-owned, while `LevelState` contains only finite voxel-space
truth, bounds, and entry/return geometry.

Handmade structure tooling should export validated `LevelModuleDefinition` resources and add them
explicitly to `LevelCatalog`; runtime generation does not consume editor drafts or scan folders.
Each future content family, such as containers or encounters, adds its typed authored definition,
transformed placement, state owner, runtime coordinator, and real caller together. Generic marker
payloads, module graphs, persistent placement IDs, and new socket profiles wait until a feature
actually consumes them.

Serialized configuration is explicit and typed. `BlockCatalog` lists `BlockDefinition` resources,
`ItemCatalog` lists item resources and their action definitions, `BiomeLibrary` lists biome
resources, `EntityCatalog` lists entity definitions, `LevelCatalog` lists dungeon modules and levels,
and `WorldConfig` references the biome library. Runtime code does not scan directories or
manufacture fallback domain resources.

Crafting recipes reference canonical item definitions. `CraftingCoordinator` asks `InventoryModel`
to validate and commit ingredient removal and output insertion across the backpack and hotbar as one
immediate transaction. `CraftingPanel` presents availability without mutating inventory slots and
plays one sound only after that transaction succeeds.

Forward+ is the primary renderer. Runtime rendering-device checks select reduced visual values for GL Compatibility fallback. Features unavailable on GL, including volumetric fog, remain disabled there.
