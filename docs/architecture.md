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
progression/                 player leveling, perks, item proficiency, and presentation
save/                        save encoding and storage
settings/                    persistent display and rendering configuration
structures/                  generic definitions, drafts, root-file storage, runtime, and presentation
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
references an actor scene, typed behavior, and validated combat stats. `EntityRuntime` owns a fresh
`ActorStats` instance for every runtime ID alongside spawn/despawn lifecycle, the bounded spatial
index, active actors, prepared actors, retiring presentation, and defeat notifications.
`WorldEntityCoordinator` owns ambient time-of-day spawning, streamed-position rejection, distance
despawning, and overworld population limits around that runtime. Zombies and sheep own only their
deterministic behavior state; the shared voxel solver and bounded path follower own reusable
movement calculations. Their custom animation drivers present actor state without deciding gameplay
outcomes. Spawned actors fade in through instance-local geometry transparency. Despawn or lethal
damage removes stats, active state, targeting, and spatial entries together. Lethal retirement
plays the species-owned death pose, then starts an actor-owned one-shot smoke poof and model fade
together; the scene is freed only after both complete. Ordinary distance and streaming retirement
uses only the fade. The overworld retiring-visual cap bounds actors, fades, and their child particle
effects to twelve concurrent presentations and evicts the earliest retained presentation first.

Stat definitions validate every declared base value as finite and nonnegative. `ActorStats` owns
current HP, validates every removable subset of prospective modifiers before committing them, and
emits one health-depleted transition when a living actor reaches zero HP. `EntityRuntime` consumes
that transition for entity retirement and emits `entity_defeated` only after removing the actor from
active state; despawn and shutdown do not emit defeat. `Game` consumes the player transition.
`EntitySpawnGeometry` is the single spawn-fit rule shared by runtime batches and dungeon content
validation, so support, body collision, and centered-feet requirements cannot diverge.

`MeleeCombatCoordinator` validates cursor targeting, range, sweep arc, voxel visibility, target
existence, and contact timing before changing health. `MeleeAttackProfile` owns base damage and an
optional sweep angle. Player swings lock sorted spatial-index candidates from the cursor ray at
attack start after rotating the player presentation toward that cursor ray, then independently
revalidate every locked target at contact; a zero-degree sweep
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
`ActorStatsDefinition` calculates the next-level requirement as an authored base plus a fixed
per-level increase. Save version eight preserves completed levels while translating version-seven
current-level experience proportionally from the previous exponential requirement.
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
through one custom `ItemTooltip`. `Game` passes `ItemProficiency` through `HUD`,
`InventoryHotbar`, and `SidePanel` into each inventory-bound slot. `HotbarView` and
`ItemSlotView` own only reusable presentation and selection intent, while a visible tooltip queries
current progress without owning it.
Weapon rows read the item's melee attack profile, while armor rows read its slot and stat
modifiers, so presentation does not own or duplicate gear state. During a left-button drag, the
source slot owns the adjustable drag count and consumes wheel input before gameplay camera handling.
`InventoryModel` remains the authority for partial moves and discards, while the source and
drag-preview visuals show the pending split without mutating inventory until a drop succeeds.

## Runes and socketing

See [Progression, runes, and enchanting](progression-runes-enchanting.md) for the player-facing
design, current implementation status, and planned enchantment rules.

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
presents a high-layer death screen. Overworld time and ambient entities continue, while dungeon
simulation and its presentation timers suspend immediately. The screen emits respawn or main-menu
intent back to `Game`. Overworld respawn restores full HP at world spawn; dungeon respawn restores
full HP at the exact overworld return anchor and destroys the failed level runtime. Neither path
changes inventory. The HUD observes player stats and presents health plus level progress without
owning either value.
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

Ambient overworld populations are transient and bounded to six per species and twelve total.
Spawning makes four attempts every two seconds in an 18–36 block annulus. Voxel A* has fixed radius,
node, and failed-search retry budgets. The spatial index contains only active actors, and distance or
chunk-streaming loss removes actors and index entries together. Block placement queries that index
and revalidates world, inventory, reach, player overlap, and active-entity overlap immediately
before committing.

## Voxel spaces and levels

`VoxelSpace` is the read-only query boundary shared by the streamed `VoxelWorld` and finite
`LevelState`. Player setup is one-time; `Game` atomically rebinds movement, collision, targeting,
and edit capabilities when the active space changes. Dungeon levels never become save-state
owners: saves receive an explicit overworld position while retaining the version-five format,
version-four migration, and item proficiency state.

Dungeon content is selected through stable typed resources. `LevelEntranceDefinition` maps a
doorway ID to a level ID and owns its current doorway presentation. `LevelDefinition` selects its
entry module, hallway module pool, exact typed room requirements, and `LevelPresentationDefinition`;
`LevelCatalog` resolves the stable IDs. Each room requirement owns a stable room type, an exact
count, a module pool, and one `LevelRoomEncounterDefinition`, so variants share count and behavior
without teaching generation their individual IDs. Encounter groups use unique stable entity IDs.
`LevelEncounterCatalogValidator` proves every entity exists
and every referenced room module has at least one spawn position that fits that entity. Generated
torch placements remain presentation-owned, while `LevelState` contains finite voxel-space truth,
bounds, entry/return geometry, and a dynamic authored-fill overlay without rewriting base cells.

Generation retains immutable `LevelConnection` records with stable placement IDs, socket IDs,
directions, and aperture cells without consuming additional random values. `LevelEncounterTopology`
collapses hallway chains into the room tree. Node-independent `LevelEncounterState` owns `LOCKED`,
`READY`, `ACTIVE`, and `CLEARED` room state, deterministic enemy order, assigned runtime IDs,
pending queues, and monotonic branch seals. Root rooms begin ready; child branches remain
undiscovered until their parent clears. Every ready room can activate independently once the
player's complete body is inside room air and clear of its incoming aperture. Initial and per-room
refill batches validate before state commit, occupied positions remain pending, and a defeat cannot
refill its originating wave until a later physics frame. Each room permits at most 20 active
encounter enemies and continuously refills that capacity until its configured group clears. Enemies
retain their originating room ownership while roaming, so concurrent waves progress independently.

Each `LevelRuntime` owns a dedicated `EntityRuntime`. Its active capacity is the sum of the root
room capacities, where each subtree contributes the greater of its room weight or the sum of its
child capacities and room weight is `min(configured enemies, 20)`. Retiring presentation remains
independently capped at 64 actors.
Dungeon navigation is bounded to radius 48, 2,048 nodes per search, and two searches per physics
tick. `Game` explicitly rebinds player queries and melee combat between overworld and dungeon voxel
spaces while cancelling pending attacks. Connected room sockets reuse their authored unused-fill
blocks: `LevelState` changes collision, raycast, attack, and pathfinding truth immediately, while
`LevelGeometryRenderer` presents ordinary textured voxel cubes. Undiscovered hallway-and-room
partitions are not rendered and cast no shadows; their torches and lights are disabled. The
discovered side retains its authored textured seal until clearance opens collision immediately,
fades the seal out over 0.35 seconds, and fades the newly discovered partition and torches in over
the same interval. Seals never close, and discovered retreat paths stay open while concurrent room
waves continue. The encounter HUD aggregates active-wave, active-enemy, and pending-enemy counts.
Level exit destroys the runtime; dungeon death suspends it immediately and destroys it while
restoring the overworld, so the next entry starts fresh.

Content directories organize ownership without becoming runtime registries. Each destination
dungeon keeps its catalog, entrance, definition, presentation, and modules together under
`levels/content/dungeons/<family>`. The family catalog is the explicit registry and
`LevelDefinition` remains the authority for entry, hallway, and room-type membership. A future iron
dungeon can mirror the stone family without adding a parallel family ID to every module or scanning
project files at runtime. Golden-only modules live under `tests/fixtures/levels` so they cannot be
mistaken for registered content. The live stone recipe places one master room, three normal rooms,
three chest rooms, five ordinary hallways, and the two-ended entry path for 13 modules inside its
96×16×96 bound. Hallways must connect at both ends; rooms seal every unused doorway with its
socket's authored fill block. Stone master rooms configure 40 zombies over local feet cells
`(4,1,4)`–`(34,1,34)`, normal rooms configure 25 over `(3,1,3)`–`(17,1,17)`, and chest rooms
configure 6 over `(3,1,2)`–`(5,1,6)`.

## Structure authoring

`StructureDraft` is the Node-independent mutable owner for a generic structure or Level Module
construction session. Its commands commit block and supported wall-torch changes atomically, while
copied snapshots keep the chunk renderer and presentation from mutating draft collections. Imported
module weight, sockets, torches, paired markers, and enemy spawn zones are copied into the draft.
Indexed required-air and floor reference counts reject ordinary edits that would invalidate
overlapping sockets or markers without scanning all metadata, while a cell relevance index limits
spawn-zone validation to affected rectangles. Module-only commands validate complete VOID,
connection, paired-marker, enemy-zone, and precise positive-weight changes before committing. Cell
and torch deltas remain localized, connection removal never refills its aperture, and torch support
removal reports only the attached torches. Imported definitions have an immutable type, ID,
dimensions, and source binding; successful exports are the only operation that changes a draft's
binding or clears its dirty state.

`StructureDefinition` format version one persists a lowercase snake_case ID, bounded dimensions,
dense canonical cube cells, and typed supported wall torches. Dense cells use
`x + size.x * (z + size.z * y)` indexing and reject `VOID`, non-cube blocks, unsupported torches,
and empty structures. Level Modules retain their independent dimensions, cells including `VOID`,
weight, ordered sockets with per-socket unused fill blocks, ordered torches, and paired markers.
They also persist ordered enemy spawn zones and require physical format version one; unversioned or
obsolete resources are invalid. `LevelDefinition` independently requires format version two.
`StructureResourceAdapter` converts both formats without changing their persisted contracts.
`StructureFileStore` scans only direct
`.tres` files in the globalized repository root and bypasses the resource cache during discovery,
import, and validation. Export saves a temporary resource, reloads and compares every persisted
field, then renames the validated file into place; collisions, stale bound sources, or failures
leave the prior file and draft state unchanged.

Hall and room membership is not duplicated on the module resource. `LevelDefinition` classifies
module IDs through its hallway pool and typed room requirements, while paired markers identify the
entry module. Adding a visual variant extends a requirement's module pool; adding a room class such
as small or boss adds another typed requirement with its own encounter. The designer's simple
connection mode authors at most one doorway per cardinal side while the persisted module format
and generator continue to support existing advanced multi-door resources.

Each socket persists its stable ID, boundary seed, facing, and unused-fill block ID. AIR means the
connection remains required, while a solid cube records the material generation uses to seal the
complete aperture when it is unused. New sockets infer that value from the carved wall or
supporting floor. The aperture itself is the
complete connected AIR component on that boundary plane, keeping geometry authoritative without a
parallel serialized shape. The draft protects the aperture, inward clearance, and supporting floor
as one transactional footprint. Generation normalizes the complete aperture after rotation and
joins only matching shapes and sizes, allowing arbitrary enclosed hallway cross-sections while
rejecting truncated seams. Required entry and hallway apertures drive alternating room-and-hall
assembly until every hallway has two connections. Generation then leaves connected apertures open
and seals every remaining optional room aperture without adding a module. Standard wall targeting
carves 1×2; prebuilt openings retain their authored size.

Enemy spawn zones are module-only horizontal rectangles selected from two floor corners. The draft
generates a unique stable zone ID, ignores decorative cells that cannot support a body, requires at
least one usable candidate, and protects the last candidate transactionally during later edits.
Candidates require solid support, two clear cells, and three-cell clearance from every doorway.
Module Tools displays each zone's candidate count, removal action, and colored in-world overlay.
Runtime cross-catalog validation applies the exact entity body geometry before a module can be used
by an encounter.

`Game` constructs and injects the dual-format file store while composing the console, authoring
workflow, dialogs, and dedicated first-person runtime. It
snapshots and suspends the active overworld or dungeon presentation without changing
`GameplayLocationState`, disables the gameplay player, camera, HUD, and saving, then restores the
same inventory and exact lifecycle state on exit. Designer cells render in bounded 16-cube chunks;
the deterministic voxel raycast is shared with player interaction, while designer movement and
creative selection remain independent from combat and finite inventory state. New and imported
generic structures and Level Modules use the same runtime. Level Module tools release the cursor,
capture the current centered target, and stage spawn and return markers before one atomic commit.
Colored metadata overlays present copied socket and marker state; ordinary edits rebuild only
affected chunks and torch nodes, while metadata commits alone refresh the panel and overlays.
Torches continue through the normal first-person palette rather than a second metadata workflow.

Repository-root Level Module exports remain authoring artifacts until they are explicitly added to
the appropriate level content and catalog. Runtime generation does not scan the repository root,
consume drafts, or register exported modules automatically.

Each future content family, such as containers or room rewards, adds its typed authored definition,
transformed placement, state owner, runtime coordinator, and real caller together. Generic marker
payloads, module graphs, and persistent placement IDs wait until a feature
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
