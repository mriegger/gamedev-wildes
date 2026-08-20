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
combat/                      melee and projectile profiles, contacts, targeting, and validation
crafting/                    recipe definitions, inventory coordination, and presentation
chests/                      container definitions, storage, transfers, and presentation
entities/                    content, AI, navigation, populations, and presentation
environment/                 packaged environment and day/night feature
equipment/                   equipment taxonomy, physical instances, armor, and presentation
inventory/                   inventory model and inventory-owned UI
items/                       item resources, actions, catalogs, and held scenes
levels/                      finite dungeon content, generation, runtime, entrance, and presentation
loot/                        deterministic pools, persistent world state, runtime, and presentation
player/                      player behavior, camera, and visuals
progression/                 player leveling, perks, item proficiency, and presentation
save/                        save encoding and storage
settings/                    persistent display and rendering configuration
stats/                       actor stat ownership and prepared modifier changes
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
references an actor scene, typed behavior, and validated combat stats. `EntityTargetObservation`
is an immutable per-tick snapshot of player position and effective camera origin, forward, and right
axes. `Game` and `LevelRuntime` construct that observation from their explicitly injected player and
camera context, including camera offsets. `Game` passes its snapshot through
`WorldEntityCoordinator`, while `LevelRuntime` passes its snapshot directly to its `EntityRuntime`;
each runtime forwards the same value to every actor. `EntityRuntime` owns a fresh `ActorStats` instance
for every runtime ID alongside spawn/despawn lifecycle, the bounded spatial index, active actors,
prepared actors, retiring presentation, and defeat notifications. It rotates the sorted actor order
each tick
before actors consume the shared navigation-search budget. `WorldEntityCoordinator` owns ambient
time-of-day spawning, streamed-position rejection, distance despawning, and overworld population
limits around that runtime.

`GroundMeleeEnemyBrain` owns the reusable deterministic wander, perception-memory, chase, and
melee-attack decisions configured by `GroundMeleeEnemyBehaviorDefinition`; Zombie actors coordinate
that brain with their species-owned combat and presentation. `SkeletonBrain` separately owns roaming,
cover search, cover movement, hiding, sprinting, and attack decisions. Skeleton patrol goals drift
from the actor's current position within thirty horizontal blocks. When a detected player remains
outside the five-block ambush radius, an already occluded Skeleton hides in place; an exposed one
starts a deterministic nearest-cover search. Entering that radius or exhausting cover starts a
sprint. A sprinting Skeleton outside the ambush radius retries cover every second, and completing a
swing requests cover at least one block from the attack position before another ambush.
`VoxelCoverSearch` captures the orthographic camera observation at search start, examines columns
within thirty horizontal blocks in distance-and-coordinate order, and advances at most thirty-two
columns per actor tick. It checks walkable elevations and all nine `VoxelCameraOcclusion` body samples
before spending the bounded A* budget, so the first result is the nearest reachable fully hidden
candidate. Hiding and cover movement revalidate against the current camera every 0.125 seconds, so
camera motion or voxel edits restart the search.

`StoneGolemBrain` separately owns dormant, chase, punch, slam-windup, slam-airborne, and slam-recovery
decisions. `VoxelPlayerVisibilitySensor` gives Zombies and Stone Golems a shared, phase-staggered
0.125-second voxel line-of-sight cache. A fresh clear sample within sixteen blocks alerts a Stone
Golem and records the pursuit goal; occlusion preserves that last-seen position for three seconds,
while exceeding twenty-four blocks forgets it immediately. Dormant Golems do not wander, and alerted
Golems pursue at 1.2 blocks per second through the shared path follower. Their eyes mirror alert state
through duplicated instance-local emissive materials, become dark on dormancy or death, and do not
create a gameplay light.

Sheep retain their distinct deterministic decision state. The shared voxel solver and bounded path
follower own reusable movement calculations. Voxel A* expands eight planar directions with
distance-weighted diagonal edges and refuses diagonals through blocked orthogonal corners.

Custom animation drivers present actor state without deciding gameplay outcomes. `EntityActor`
allows species to omit vocalization presentation while Skeleton, Zombie, and Sheep wire species-owned
profiles through the shared `EntityVocalizations` scheduler. Skeleton selects among three positional
clips, avoids immediate repeats, and stops audio processing when presentation retires. Stone Golem
wires a species-owned action-audio profile for gait contacts, received hits, and death. Each actor
binds its runtime stats to a
billboarded health bar before visual-fade setup, so the bar remains hidden at full health, updates
from completed health changes, and shares the actor's fade lifecycle. Spawned actors fade in through
instance-local geometry transparency. Despawn or lethal damage removes stats, active state,
targeting, and spatial entries together. Lethal retirement plays the species-owned death pose, then
starts an actor-owned one-shot smoke poof and model fade together; the scene is freed only after both
complete. Ordinary distance and streaming retirement uses only the fade. The overworld
retiring-visual cap bounds actors, fades, and their child particle effects to twelve concurrent
presentations and evicts the earliest retained presentation first.

Stat definitions validate every declared base value as finite and nonnegative. `ActorStats` owns
current HP, validates every removable subset of prospective modifiers before committing them, and
emits one health-depleted transition when a living actor reaches zero HP. `EntityRuntime` consumes
that transition for entity retirement and emits `entity_defeated` only after removing the actor from
active state; despawn and shutdown do not emit defeat. `Game` consumes the player transition.
`EntitySpawnGeometry` is the single spawn-fit rule shared by runtime batches and dungeon content
validation, so support, body collision, and centered-feet requirements cannot diverge.

`MeleeCombatCoordinator` validates cursor targeting, range, sweep arc, voxel visibility, target
existence, and contact timing before changing health. It also commits already-resolved projectile
contacts through the same player stats, target defense, damage-affinity, and knockback rules. `Game`
injects a validated `DamageTypeCatalog` that registers the canonical slash, blunt, and pierce
definitions accepted by combat.
`MeleeAttackProfile` owns maximum base damage, optional random reduction below that base, radial
falloff, a damage multiplier, a canonical damage type, an optional
sweep angle, optional knockback, and whether targets lock at attack start or are acquired at contact.
Selecting a melee weapon makes the player presentation smoothly
track the cursor independently of camera-relative movement whenever the player is not sprinting;
sprinting restores movement-owned facing. Directional player swings snap to the current cursor ray,
lock that facing for the attack duration even while sprinting, lock sorted spatial-index candidates
from the same ray, then independently revalidate every locked target at contact. The copper hammer
instead queries its full-circle four-block area at the slam frame, so enemies are affected according
to their positions at impact. A zero-degree sweep
retains exact single-target ray selection, while a full-circle sweep is independent of planar cursor
aim. The profile calculates
`max(1, (base damage + attacker strength - target defense) × damage multiplier)`. Entity definitions
optionally map canonical damage types to weak or resistant responses; missing entries remain neutral.
Combat applies the response multiplier after the profile calculation: 1.5 for weak, 0.5 for resistant,
and 1.0 for neutral. Each successful
physical hit applies that damage through the target state owner and optionally adds a decaying planar
knockback velocity. Melee hits produce immutable `MeleeOutcome` values; arrow hits produce parallel
`ProjectileOutcome` values. Both carry the contact, exact applied damage, source item ID, affinity
response, and lethal result. The player interactor separately emits the AoE's ground
origin for presentation; the hammer consumes it with a procedural expanding and fading ring.
`EnemyCombatFeedback` consumes committed player outcomes through a bounded pool of billboarded
damage labels, resolves active or retiring actors through `EntityRuntime`, and suppresses labels
beyond its authored camera-size threshold. Labels bypass depth testing with an explicit render
priority so they remain above health bars and world geometry. Neutral labels remain white,
weaknesses render yellow-gold, and resistances render dark grey. Rejected contacts change no health
and produce no outcome.
`ArrowProjectileRuntime` owns a bounded set of live arrow models. It atomically consumes the first
compatible ammunition in hotbar order followed by backpack order, launches from the action-authored bow transform at a
draw-scaled speed, evaluates its ballistic position under gravity, and sweeps fixed 60 Hz flight segments
against the entity spatial index and voxel raycast solids. `ArrowTrajectoryView` requests the same
prediction while the bow is drawn and renders it from the nocked arrow to the first predicted contact,
so presentation and the fired projectile share trajectory and collision rules. `PlayerInteractor`
resolves the first voxel surface under the cursor, falling back to the player's ground plane, and owns
the current aim target; the bow action solves the reachable ballistic angle or raises toward its 45-degree cap, and both presentation and firing consume
that authoritative transform. Secondary use cancels an active draw without committing ammunition and
requires primary use to be released before another draw begins. The arrow aligns its shaft to current velocity while `ArrowTrailView`
retains only a short recent window of flight positions, then embeds at the nearest contact while its
trail fades. The arrow holds for one second, then fades and is removed. Projectile profiles own pierce damage, knockback,
collision radius, gravity, and lifetime limits. The bow action maps draw progress to a 0.4–1.0
damage multiplier that the projectile captures at launch and combat applies after attacker strength
and target defense, with damage affinity applied last. `Game` explicitly connects completed melee and
projectile outcomes to entity reactions, progression, and presentation without making combat own
those policies.

Enemy attacks use `TimedMeleeContact` to separate an actor-owned action duration from its one contact
instant. Zombie and Skeleton attacks and the Stone Golem fallback punch emit their configured profile
only when that instant is reached; retirement cancels pending contact. `EntityRuntime` forwards the
completed signal, and `MeleeCombatCoordinator` revalidates the live source, player range, voxel line
of sight, and player bounds before committing damage. Skeleton contact produces ten damage against
an unarmored player through the shared defense calculation while its brain owns the post-swing cover
retreat. A Stone Golem prioritizes a ready slam for a freshly visible target within fifteen horizontal
blocks. While the four-second slam cooldown is active, a freshly visible target within 1.5 blocks can
instead start the 0.8-second fallback punch. It contacts at 0.46 seconds, has a 1.4-second cooldown,
and produces fifteen unarmored damage.

The Stone Golem brain owns slam selection, phase timing, and the locked takeoff target; its actor
owns clearance validation, physical trajectory, cancellation, and landing dust. A 0.6-second windup
precedes a 0.8-second ballistic leap and a 0.75-second recovery. Invalid clearance, despawn, or death
cancels pending contact. The actor emits one radial contact only after reaching its actual grounded
landing position. `EntityRuntime`
forwards that signal and `Game` explicitly binds it to `MeleeCombatCoordinator`, which validates the
live source, one-block horizontal radius, vertical bounds overlap, voxel line of sight, and living
player before applying thirty unarmored damage through normal defense. Radial contact has no mob or
terrain target path.

`CombatHitParticles` subscribes to committed melee and projectile outcomes and selects profiles by
stable source and target definition IDs. Player hits produce bone particles for Skeletons and stone
particles for Stone Golems; successful attacks from either species produce player blood. The Stone
Golem's world-space landing dust is a bounded actor-owned one-shot at the actual landing position.
The dust presents impact state without deciding whether radial damage commits.

`ActorStats` owns the player's level and current-level experience. `CombatProgressionCoordinator`
awards the reward authored on an `EntityDefinition` exactly once for a player-caused defeat.
Zombie, Skeleton, and Sheep rewards are currently ten experience; Stone Golems award thirty. These
remain authored content values.
`ActorStatsDefinition` calculates the next-level requirement as an authored base plus a fixed
per-level increase. Save version eight preserves completed levels while translating version-seven
current-level experience proportionally from the previous exponential requirement.
`PlayerPerkRules` is the canonical catalog and award policy for bounded player perks. `PlayerPerks`
owns only stable-ID rank allocations, while `PlayerPerkCoordinator` derives available points from
the current player level and applies all purchased ranks through one bounded `ActorStats` modifier
source. Allocation preflights both the rank change and projected stat modifiers before committing,
and maximum-HP changes preserve the current health percentage. `Game` creates, restores, and wires
these owners explicitly. Unspent points remain derived rather than becoming a second mutable
ledger.
`ProgressionPanel` presents live level, XP, available points, authored perk effects, and bounded
allocation commands without owning progression state. It polls only while its workspace is visible
and sends allocation requests through `PlayerPerkCoordinator`. `CraftingPanel` is the shared shell
for the Crafting, Runes, and Progression workspaces. Crafting commits immediately, so workspace
switches only change presentation, and reopening always returns to Crafting.
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

`InventorySlot` presents stat-bearing item and rune details for hotbar, backpack, and equipped slots
through one custom `ItemTooltip`. `Game` passes `ItemProficiency` through `HUD`,
`InventoryHotbar`, and `SidePanel` into each inventory-bound slot. `HotbarView` and
`ItemSlotView` own only reusable presentation and selection intent, while a visible tooltip queries
current progress without owning it.
`ItemStatFormatter` derives shared item rows for hover tooltips and crafting details. Weapon rows
include maximum and ranged damage, the canonical damage type, and knockback; armor rows read the
slot and stat modifiers directly. Numeric values use the shared
`CombatPresentationPalette` weakness color. Pickaxe and consumable rows derive mining capability
and restored health from their canonical item actions, so presentation does not own or duplicate
item state. During
a left-button drag, the source slot owns the adjustable drag count and consumes wheel input before gameplay camera handling.
`InventoryModel` remains the authority for partial moves and discards, while the source and
drag-preview visuals show the pending split without mutating inventory until a drop succeeds.

`ChestStorage` owns slot arrays keyed by chest position. Its slot count comes from the canonical
chest block's `ContainerBlockDefinition`, so layout, runtime storage, and persistence share one
definition. The overworld instance is persistent. `ChestCoordinator` binds that owner to
`InventoryModel` and `InventoryLoadoutCoordinator`; cross-scope moves prepare exact expected and
replacement stacks in both owners, validate both revisions, commit both silently, and notify only
after both commits.
Click transfer, drag/drop, and move-all reuse those command paths without exposing mutable slots.
While a chest is open, `ChestPanel` presents its centered 3×5 grid, while the existing right-side
`SidePanel` and bottom `InventoryHotbar` present player storage.
`ChestRenderer` presents placed chests outside the chunk cube mesh. The body uses explicit face
quads so each wooden face is rendered once, while the lid remains a separately hinged box.
`TargetingView` forwards the reachable chest position so the renderer highlights both pieces and
hinges the real lid slightly without changing block or inventory state. Chest placement delegates
to that renderer for a translucent preview of the same split model. Mining uses the normal prepared
world-and-inventory transaction. `Game` supplies `ChestCoordinator.can_break()` as the focused
validator, so only empty chests can commit; the completed block edit then removes their empty
position-keyed storage.

Each `LevelRuntime` instead composes an attempt-owned `ChestStorage` through
`DungeonChestCoordinator`. Generated dungeon chests are take-only and are not save-state owners.
Repeat rewards use the normal prepared inventory transfer and record repeat-loot collection for
repeat-mode runs. Claiming an unclaimed guaranteed chest prepares its complete storage removal,
inventory/loadout projection, and `DungeonProgressState` reward claim, validates all three owners,
then commits them silently before notifying observers. `DungeonRunCompletionTransaction` separately
consumes the attempt's run qualification and increments completion at an alive exit. Runtime teardown
discards only remaining generated chest contents; already claimed inventory and progress are
player-owned.

## Equipment instances, runes, and loot

`EquipmentTypeDefinition` forms a catalog-owned hierarchy rooted at equipment. Weapons and armor
use canonical type resources, and compatibility follows type ancestry plus the authoritative armor
slot where applicable. Adding a weapon family extends that hierarchy without action-class checks.

See [Progression, runes, and enchanting](progression-runes-enchanting.md) for the player-facing
progression and socketing design.

An `ItemDefinition` is the shared identity and base configuration for an item type. Every physical
weapon or armor copy is instead an `InventoryStack` with count one and an `EquipmentInstance`. The
instance owns a globally unique, monotonic `instance_id`, copied
affix rolls, and ordered socketed-rune IDs. Two Copper Swords in the backpack therefore both use
item ID `copper_sword` but retain different instance IDs and may have different affixes and runes.
Moves among backpack, hotbar, equipment slots, chests, and world loot preserve
the same instance; material stacks have no instance data. `EquipmentInstanceFactory` is the sole
allocator, and prepared cross-system operations advance it only when every destination can commit.

`EquipmentAffixDefinition` is canonical content registered by `ItemCatalog`. It declares compatible
equipment types, optional armor-slot restrictions, a display-name suffix, and one or more stat roll
ranges. `EquipmentAffixInstance` freezes the affix ID and each concrete `EquipmentAffixStatRoll` on
the physical copy, so later definition changes do not silently reroll existing gear. Affixes and
their stat rolls are stored in canonical ID order. `InventoryLoadoutCoordinator` projects base item
and affix modifiers from the selected weapon and equipped armor into `ActorStats`; tooltips use the
same instance values.

`RuneDefinition` is typed item content with rarity, equipment-type and armor-slot compatibility,
and socket-only stat modifiers. The Basic Rune is Common, works on every weapon and armor slot, and
adds one hundred maximum HP. It currently has no normal production acquisition; developer spawning
and copies already present in saved inventories remain valid. The weapon-only Power Rune adds one
Strength.
A gear instance's `socketed_rune_ids` array preserves physical slot order, permits empty interior
slots, and omits trailing empty slots.

`RuneSocketingCoordinator` combines the target item's `ProficiencyDefinition`, shared
`ItemProficiency`, and rune compatibility into command and query APIs without owning inventory.
`InventoryLoadoutCoordinator` prepares the corresponding inventory and stat projections together,
then commits and notifies only after both remain valid. It applies runes on the selected weapon and
equipped armor; runes on unselected weapons and unequipped armor remain persisted but inactive.
Duplicate active runes stack without accumulating stale modifiers, and maximum-HP changes preserve
the player's current health percentage.

Each `EntityDefinition` can reference one `LootPoolDefinition`. A pool contains independent rolls
and exclusive weighted groups. Each drop names one canonical item, a count range, and, for
equipment, an optional `LootEquipmentRollDefinition` with fixed or random affixes and runes.
`LootResolver` is node-independent and keys every decision by the pool ID, defeat seed, stable roll
ID, and child path. Reordering resource arrays does not change results, and unrelated rolls do not
consume a shared random stream. Random affixes are weighted and selected without replacement;
random rune slots each sample the weighted choice set independently with replacement. Fixed affix
and rune arrays author an exact selected set, with fixed rune order defining physical socket order;
an affix stat uses one exact value when its minimum and maximum are equal.
Catalog validation rejects non-canonical or incompatible item, affix, and rune resources before
gameplay starts.

The current zombie pool independently rolls a 75% chance for 1–3 Copper. It separately has a 17%
chance to choose exactly one gear result with weights 10 plain Copper Sword, 4 Copper Sword with
one or two random Vicious/Nimble affixes plus one Power Rune, and 3 Copper Helmet with
the fixed Stout affix. The rolled sword is not a separate variant or item ID: it is another
`copper_sword` instance whose per-copy data records the result.

Affixes and runes currently contribute numeric stat modifiers; they are not a generic behavior-trait
framework. A future effect such as flame or knockback must introduce its concrete typed definition,
executor, validation, and real combat caller together. Loot may then reference that validated
content without adding behavior branches to the resolver.

`EntityRuntime` emits one immutable `EntityDefeat` after authoritative removal, preserving the
entity ID, position, and loot seed without coupling drops to melee. `LootResolver` prepares the
complete drop batch and provisional equipment IDs. `OverworldLootCoordinator` commits that allocator
advance and the `WorldLootState` batch through `WorldLootDropTransaction` only after both validate.
The world change records the allocator floor required by its provisional IDs, preventing either
owner from accepting the batch independently.

`WorldLootState` is the node-independent mutable owner for at most 128 persistent overworld entries.
Entries receive stable monotonic IDs and are queried through a bounded spatial index. Nearby material
stacks of the same item merge up to the item stack limit within 1.5 blocks and refresh their
five-minute active-simulation lifetime. Equipment never merges or expires. When capacity requires
an eviction, the material entry with the least remaining lifetime is removed first. If every
retained entry is equipment, the oldest equipment entry is removed. Incoming entries are protected
while their batch is being admitted, so an all-equipment state cannot permanently block future loot.

Pickup is another prepared cross-owner transaction. Materials may move partially into available
inventory capacity while the remainder keeps its world entry ID and lifetime; equipment moves only
as one complete instance. Inventory, active loadout stats, and world loot commit before observers are
notified. Chunk readiness controls `LootDropView` nodes only: streaming a position out removes its
view but not its state, and streaming it back recreates the view. Dungeon and structure-designer
transitions suspend views, pickup, and lifetime advancement without clearing entries. Shutdown also
leaves `WorldLootState` intact for the session owner and save system.

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
available viewport when necessary. Entity HP is transient, while uncollected overworld loot is
serialized independently from entity presentation. Enemy health bars, regeneration, knockback,
death audio, and post-respawn invulnerability remain outside the combat system.

`GameSession` owns save suspension as part of the gameplay lifecycle. Suspension or authoritative
zero HP blocks manual, periodic, and edit-debounce writes while session playtime continues
accumulating. Respawn, Main Menu, and window close restore a living player at world spawn before
saving resumes; exit paths then use the normal final-save and shutdown flow so zero HP is never
persisted. Loading a historical zero-HP snapshot restores full health at world spawn before gameplay
begins and immediately replaces the stored snapshot with that living state.
Save version fifteen stores the shared equipment allocator, persistent `WorldLootState`, block
emplacements, and `DungeonProgressState` alongside inventory, item proficiency, player perks,
pumpkin and apple harvest state, and canonical overworld chest slots keyed by stable block position. Dungeon progress
snapshot version one stores each stable instance's next attempt index, completion count, and sorted
claimed reward IDs. Version-four saves gain empty item proficiency; version five adds rune-slot
arrays; version six adds empty pumpkin state; version seven translates current-level XP to the linear
curve and adds empty perks and legacy chest inventories; and version eight adds empty apple state.
The version-nine-to-ten migration converts legacy chest inventory snapshots to canonical 15-slot
chest arrays and normalizes legacy equipment variant fields. Version ten converts each equipment
stack into a concrete `EquipmentInstance`, assigns globally unique IDs, captures rune slots,
converts known legacy variants into exact affix rolls, and records the next allocator ID when
migrating to version eleven. The version-eleven-to-twelve migration validates and removes retired
durability fields from equipment instances. Version twelve adds an empty world-loot snapshot when
migrating to version thirteen, version thirteen adds empty block emplacements when migrating to
version fourteen, and version fourteen adds empty dungeon progress when migrating to version
fifteen. The chain operates on a copy and commits only after every region is valid,
preserving the original payload on failure.
`Game` restores inventory, proficiency, player stats, chest contents, the shared equipment allocator,
world loot, and dungeon progress before enabling `GameSession`. Save validation requires equipment
instance IDs to be unique across backpack, hotbar, equipped slots, every persisted overworld chest,
and world loot, and requires every ID to precede the saved allocator value. Any invalid or retired
content aborts startup, returns to world selection, and leaves the caller-owned payload and save file
unchanged. Loot creation, pickup, expiration, merge, dungeon-attempt, and dungeon-completion events
queue the same debounced save path as world and chest changes; a completed dungeon also requests an
immediate save.

Ambient overworld populations are transient and bounded by each definition's authored cap and a
sixteen-entity total. The five stable species are capped at six Sheep, six Zombies, four Birds,
three Skeletons, and two Stone Golems. Sheep and Birds spawn by day; Zombies, Skeletons, and Stone
Golems spawn by night. Birds retire when night begins. Skeletons and Stone Golems use the
Zombie-compatible overworld floor set, while authored stone-dungeon encounters remain Zombie-only.
A deterministic round-robin cursor considers eligible species and permits one successful spawn per
interval, preventing one species from starving another. Spawning makes four attempts every two
seconds in an 18–36 block annulus. Overworld voxel A* is bounded to a radius of thirty-two, 512
visited nodes, and two shared searches per tick; actors rotate through that shared budget. The
spatial index contains only active actors, and distance or chunk-streaming loss removes actors and
index entries together. Block placement queries that index and revalidates world, inventory, reach,
player overlap, and active-entity overlap immediately before committing.

## Voxel spaces and levels

`VoxelSpace` is the read-only query boundary shared by the streamed `VoxelWorld` and finite
`LevelState`. Player setup is one-time; `Game` atomically rebinds movement, collision, targeting,
and edit capabilities when the active space changes. Dungeon levels never become save-state
owners: version-fifteen saves receive an explicit overworld position while retaining player-owned
inventory, equipment instances, progression, overworld chest contents, and overworld loot. `Game`
owns persistent `DungeonProgressState`; `LevelRuntime` owns only the transient generated layout,
encounter state, dungeon chest contents, and run-completion qualification for one attempt.

Dungeon content is selected through stable typed resources. `LevelEntranceDefinition` maps a
doorway ID to a level ID and owns its current doorway presentation; its entrance ID is also the
current stable dungeon-instance ID for claims and completion history. `LevelDefinition` selects its
entry module, hallway module pool, exact typed room requirements, `LevelPresentationDefinition`, and
optional `LevelOneTimeChestRewardDefinition`; `LevelCatalog` resolves the stable IDs. Each room
requirement owns a stable room type, an exact count, a module pool, and either one
`LevelRoomEncounterDefinition` or a base and optional post-first-completion `LootPoolDefinition`,
so variants share count and behavior without teaching generation their individual IDs. A
loot-bearing room module must have
one valid chest marker, while an encounter room must have enemy spawn zones. Encounter groups use
unique stable entity IDs.
`LevelEncounterCatalogValidator` proves every entity exists
and every referenced room module has at least one spawn position that fits that entity. Generated
torch placements remain presentation-owned, while `LevelState` contains finite voxel-space truth,
bounds, entry/return geometry, and a dynamic authored-fill overlay without rewriting base cells.
`LevelGenerator` transforms each authored chest marker into one `LevelChestPlacement` with its room
requirement's canonical base and optional post-completion pools. `LevelLootCatalogValidator`
validates unique reward IDs, canonical pools and bundles, item content, equipment variants, at least
one guaranteed repeat roll, and the 15-slot chest bound. Repeat pools evaluate independent chances
and weighted exclusive groups. Guaranteed bundles include every fixed entry and then choose weighted
candidates without replacement up to their authored `max_rewards`. See
[Dungeon chest authoring and rewards](dungeon-chest-authoring.md) for the content contract.

Generation retains immutable `LevelConnection` records with stable placement IDs, socket IDs,
directions, and aperture cells without consuming additional random values. `LevelEncounterTopology`
collapses hallway chains into the room tree. Node-independent `LevelEncounterState` owns `LOCKED`,
`READY`, `ACTIVE`, and `CLEARED` room state, deterministic enemy order, assigned runtime IDs,
pending queues, and monotonic branch seals. Root rooms begin ready; child branches remain
undiscovered until their parent clears. Every ready encounter room can activate independently once
the player's complete body is inside room air and clear of its incoming aperture. Initial and
per-room refill batches validate before state commit, occupied positions remain pending, and a
defeat cannot refill its originating wave until a later physics frame. Each encounter room permits
at most 20 active enemies and continuously refills that capacity until its configured group clears.
Enemies retain their originating room ownership while roaming, so concurrent waves progress
independently. Passive chest rooms create neither encounter state nor a local seal, but roaming
enemies share their navigation space and can enter them.

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

`Game` starts a persisted attempt before setting up and activating `LevelRuntime`. Repeat chest
seeds include that attempt index, while the one-time seed uses only stable layout, instance, and
reward identity so a failed first clear preserves both the designated chest and its contents. First
completion requires claiming the complete guaranteed bundle into inventory and using the return door
alive. The claim is recorded and synchronously saved at pickup, independently of completion. Death,
quit, and ordinary abandon keep the claimed items and claim ID but do not increment completion. A
later attempt that starts with the reward already claimed, or a dungeon with no guaranteed reward,
requires any positive repeat chest-to-inventory transfer before an alive exit can complete it.
Completion qualification is consumed once. Enemy clearance is not currently an input. Full
inventory capacity rejects the complete guaranteed bundle without changing chest, inventory, or
progress state. Level exit restores the overworld before retiring the runtime, so the next entry
starts fresh.

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
`(4,1,4)`–`(34,1,34)` and normal rooms configure 25 over `(3,1,3)`–`(17,1,17)`. Each passive
chest-room copy transforms its authored marker into one chest and has no encounter or spawn zones.
One deterministic chest carries the unclaimed Iron Pickaxe first-clear bundle. Each other chest, and
every chest before the first completion, contains one repeat stack of 5–10 Pumpkins. Beginning with
the next run after the first completion, every chest keeps those Pumpkins and independently rolls a
25% chance for one Iron Pickaxe. Iron Pickaxe is a dungeon reward with power 3 and a 2.5 speed
multiplier; it has no crafting recipe.

## Structure authoring

`StructureDraft` is the Node-independent mutable owner for a generic structure or Level Module
construction session. Its commands commit block and supported wall-torch changes atomically, while
copied snapshots keep the chunk renderer and presentation from mutating draft collections. Imported
module weight, sockets, torches, paired markers, enemy spawn zones, and chest marker are copied into
the draft.
Indexed required-air and floor reference counts reject ordinary edits that would invalidate
overlapping sockets or markers without scanning all metadata, while a cell relevance index limits
spawn-zone validation to affected rectangles. Module-only commands validate complete VOID,
connection, paired-marker, enemy-zone, chest-marker, and precise positive-weight changes before
committing. Cell and torch deltas remain localized, connection removal never refills its aperture,
and torch support removal reports only the attached torches. Imported definitions have an immutable type, ID,
dimensions, and source binding; successful exports are the only operation that changes a draft's
binding or clears its dirty state.

`StructureDefinition` format version one persists a lowercase snake_case ID, bounded dimensions,
dense canonical cube cells, and typed supported wall torches. Dense cells use
`x + size.x * (z + size.z * y)` indexing and reject `VOID`, non-cube blocks, unsupported torches,
and empty structures. Level Modules retain their independent dimensions, cells including `VOID`,
weight, ordered sockets with per-socket unused fill blocks, ordered torches, and paired markers.
They also persist ordered enemy spawn zones and an optional chest marker and require physical format
version two; unversioned or obsolete resources are invalid. `LevelDefinition` independently
requires format version five.
`StructureResourceAdapter` converts both formats without changing their persisted contracts.
`StructureFileStore` scans only direct
`.tres` files in the globalized repository root and bypasses the resource cache during discovery,
import, and validation. Export saves a temporary resource, reloads and compares every persisted
field, then renames the validated file into place; collisions, stale bound sources, or failures
leave the prior file and draft state unchanged.

Hall and room membership is not duplicated on the module resource. `LevelDefinition` classifies
module IDs through its hallway pool and typed room requirements, while paired markers identify the
entry module. Adding a visual variant extends a requirement's module pool; adding a room class such
as small or boss adds another typed requirement with its own encounter or chest loot pools. The
designer's simple connection mode authors at most one doorway per cardinal side while the persisted
module format and generator continue to support existing advanced multi-door resources.

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

The optional chest marker targets one supported empty cell with empty headroom and at least one
adjacent supported two-cell standing space. It cannot overlap a socket aperture, torch, entry marker,
or enemy spawn zone. Module Tools captures it from the centered world target and renders a copied
metadata overlay. Catalog validation pairs a marked module only with a room requirement that owns a
base chest loot pool and no encounter.

`Game` constructs and injects the dual-format file store while composing the console, authoring
workflow, dialogs, and dedicated first-person runtime. It
snapshots and suspends the active overworld or dungeon presentation without changing
`GameplayLocationState`, disables the gameplay player, camera, HUD, and saving, then restores the
same inventory and exact lifecycle state on exit. Designer cells render in bounded 16-cube chunks;
the deterministic voxel raycast is shared with player interaction, while designer movement and
creative selection remain independent from combat and finite inventory state. New and imported
generic structures and Level Modules use the same runtime. Level Module tools release the cursor,
capture the current centered target, stage spawn and return markers before one atomic commit, and
set or clear the chest marker through its own validated command.
Colored metadata overlays present copied socket and marker state; ordinary edits rebuild only
affected chunks and torch nodes, while metadata commits alone refresh the panel and overlays.
Torches continue through the normal first-person palette rather than a second metadata workflow.

Repository-root Level Module exports remain authoring artifacts until they are explicitly added to
the appropriate level content and catalog. Runtime generation does not scan the repository root,
consume drafts, or register exported modules automatically.

Each future content family, such as traps or dungeon objectives, adds its typed authored definition,
transformed placement, state owner, runtime coordinator, and real caller together. Generic marker
payloads, module graphs, and persistent placement IDs wait until a feature
actually consumes them.

Serialized configuration is explicit and typed. `BlockCatalog` lists `BlockDefinition` resources,
`ItemCatalog` lists item resources and their action definitions, `BiomeLibrary` lists biome
resources, `EntityCatalog` lists entity definitions, `LevelCatalog` lists dungeon modules and levels,
and `WorldConfig` references the biome library. Runtime code does not scan directories or
manufacture fallback domain resources.

Crafting recipes reference canonical item definitions. The general catalog owns recipes available
from the `Tab` menu, the anvil catalog exclusively owns copper equipment, and the cauldron catalog
owns food and potion recipes. `CraftingCoordinator` asks `InventoryModel` to validate and commit
ingredient removal and output insertion across the backpack and hotbar as one immediate
transaction. Craftable item definitions own the short descriptions presented above their recipe
ingredients, and recipe validation rejects outputs without one. Reusable `CraftingPanel` instances
present all three catalogs and shared item stats without mutating
inventory slots and play one sound only after a transaction succeeds. The HUD combines the open
panels' animation progress so only one camera-obstruction value is written during transitions.

`CraftingStationBlockDefinition` marks interactable workstation blocks. Shared
`CraftingStationCoordinator` state validates station identity and position and closes an open panel
when its block is removed; `AnvilCoordinator` and `CauldronCoordinator` provide the station-specific
IDs. Normal pickaxe mining owns capacity-safe workstation and attached-torch drops. Indexed chunk
edit snapshots drive the procedural station renderers: `AnvilRenderer` owns the low-poly anvil,
while `CauldronRenderer` owns the suspended pot, tripod, fire, smoke, and dim light. Both renderers
also provide placement previews and subtle hover presentation.

Forward+ is the primary renderer. Runtime rendering-device checks select reduced visual values for GL Compatibility fallback. Features unavailable on GL, including volumetric fog, remain disabled there.
