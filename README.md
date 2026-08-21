# Wildes

**Wildes** is an isometric voxel sandbox built in **Godot 4.7** (GDScript). You explore an
endless procedurally generated world under an orthographic isometric camera, mine blocks into
a nine-slot hotbar, and build with them. The loop is explore → mine → build, on terrain that
streams in around you as you walk, under a running day/night cycle.

Worlds are saved to three local slots and persist your seed, edits, inventory, equipment instances,
progression, dungeon attempts/completions/reward claims, chest contents, uncollected overworld loot,
harvest state, position, and world time. Copper deposits regenerate deterministically from the
world seed.

## Controls

| Input | Action |
| --- | --- |
| `WASD` / arrows | Move (camera-relative) |
| `Shift` + move | Sprint |
| `Space` | Hop — needed to get up any ledge |
| `Q` / `E` | Rotate the camera 45° |
| Mouse wheel / pinch | Zoom |
| Left-click / hold | Open a targeted chest or crafting station, or use the selected item; hold to mine or draw a bow, release to fire an arrow, or click to attack, till soil, or consume food and potions |
| Right-click | Use the selected item's secondary action, including consuming food or potions and placing blocks; cancel an active bow draw |
| `F` | Enter or leave a nearby dungeon |
| `1`–`9` | Select hotbar slot; while the backpack is open, assign the hovered item to that slot |
| `Tab` | Toggle backpack and crafting |
| `P` | Toggle backpack only |
| `/` | Toggle the developer command console |
| `F10` | Toggle player animation tuner |
| `Esc` | Pause |

Reach is 6 blocks. Mineable targets under the cursor are outlined, while chests open without a
mining outline. A translucent preview shows where a placement would land, using the chest's split
body-and-lid model when appropriate; placements that would overlap you are rejected.

The Structure Designer uses first-person `WASD` movement, mouse look, `Space`/`Ctrl` to
ascend/descend, and `Shift` acceleration. Left-click removes, right-click places, `Tab` opens the
infinite creative palette, and `M` opens Level Module tools with a free cursor. Closing either
panel returns to first-person building. `/` opens the developer console, and `Esc` closes active
designer UI before offering to leave the designer. In Module Tools, `Place Connections` returns to
first-person connection mode. Click a solid lower boundary wall for a standard 1×2 doorway, or
click the floor beneath a prebuilt boundary opening to register its complete shape and size. Only
matching openings connect. Each connection row can export either `Must connect` or a placeable cube
to use when that doorway is left unused. `Must connect` openings require a compatible module;
unused optional openings are sealed across their complete authored shape with the selected cube.
Press `Esc` when finished. Two opposite connections form a straight hall; rooms can expose all four
sides. Entry markers are authored as a player Spawn plus one shared Entrance / Exit Door; aim at
each desired cell before opening Module Tools, set each marker from the target, then commit the pair.
Room modules also expose an Enemy Spawn Zones section. `Add Zone` returns to first-person targeting:
left-click the first floor corner, aim at the opposite corner to review its usable-cell count, then
left-click that second corner to commit. Right-click or `Esc` cancels. Colored floor overlays show
candidates with solid support, body clearance, and three-cell doorway clearance; each saved row can
be removed from Module Tools. To author a chest room, aim at the supported empty cell where the
chest should stand and use Chest Marker → Set from target. A module can contain one chest marker;
the marker also requires empty headroom and an accessible adjacent standing cell.

The animation tuner is a compact right-side debug-build panel. Its Movement, Animation, Parts,
and Attack tabs update the live player immediately, while preview modes let you hold idle, walk,
sprint, jump, fall, or sword-attack behavior. `Export Values to Project Root` writes the complete
current configuration to `player_animation_values.json` beside the `src/` directory.

## Features

**World.** Endless terrain generated from continentalness, erosion, peaks-and-valleys,
temperature, and humidity noise in 20×20 chunk columns, 36 blocks tall. You spawn in a grass
meadow clearing; beyond it are plains, forests, wetlands, sandy lowlands, highlands, and stone
mountains. Lakes with 16–42-block radii and 5–8-block depths, plus rivers, carve into the terrain
and fill with water up to level 5.

**Streaming.** Chunks load in a radius of 4 around you (9×9 = 81 chunks) and unload two chunks
further out. Meshing runs on background threads so movement doesn't hitch; edits are stored
globally and survive unload/reload.

**Dungeon levels.** A doorway near the meadow spawn leads to a deterministic 13-module stone
dungeon assembled from an entry path, five ordinary hallways, and seven rooms: one master room,
three normal rooms, and three chest rooms. Every hallway connects at both ends, while unused room
doorways are sealed with their authored fill blocks. The finite interior uses cutaway-facing
geometry, a black void, and authored torch light. The overworld stays loaded but its streaming and
presentation are suspended until you return through the dungeon door. Doorway selection, exact
room requirements, hallway variants, terrain presentation, ambient lighting, and return-door
materials are configured through typed level resources rather than hardcoded dungeon IDs. Each
destination dungeon owns its catalog, entrance, definition, presentation, and modules under
`levels/content/dungeons/<family>`. Directories organize each self-contained family but never
register content through filesystem scans. A room requirement maps a stable room type, count,
module pool, and either an encounter or base and optional post-completion chest loot pools, so additional variants can join an
existing type and new types such as small or boss rooms can be added without a dungeon-specific
generator branch.

Master rooms configure 40 zombies and normal rooms 25. Chest rooms are passive: each generated room
contains one take-only chest, creates no local enemy wave, and does not seal its branch. Enemies from
other rooms can still enter and attack. On the stone dungeon's first clear, one deterministic chest
contains the guaranteed Iron Pickaxe while each other chest contains one stack of 5–10 Pumpkins;
claiming the guaranteed chest moves its complete bundle directly into inventory, records the claim,
and requests an immediate save. The dungeon is completed separately by exiting alive. If the player
dies or abandons the attempt after claiming, the item and claim remain but completion does not; the
next run requires a repeat-loot transfer before exit. Beginning with the run after the first
completion, every chest contains 5–10 Pumpkins and independently has a 25% chance to include one
Iron Pickaxe. A full inventory leaves a guaranteed bundle unchanged and displays
`Inventory full — drop items first`. Enemy clearance is not currently required for completion. See
[Dungeon chest authoring and rewards](docs/dungeon-chest-authoring.md) for the full authoring and
completion rules.

An encounter activates only after the player is fully inside its combat room. Every ready encounter
room can run a wave concurrently, and each wave permits at most 20 active enemies from its
originating room while larger groups refill authored spawn positions on later physics ticks.
Discovered retreat paths stay open, so enemies can roam between rooms while their wave ownership
remains unchanged. The shared dungeon runtime derives its active capacity from the generated room
tree's weighted antichain bound instead of imposing a fixed wave count. Undiscovered rooms and
hallways are not rendered, including their torches, lights, and shadows. A discovered combat
branch's authored textured wall-fill seal stays visible until its parent room clears; collision
opens immediately, the seal fades out over 0.35 seconds, and the branch and its torches fade in over
the same interval. Opened seals never close. The HUD aggregates wave, active, and pending counts.
Leaving or dying restores the exact overworld anchor and creates fresh encounter state on re-entry.
Dungeon music selects non-repeating tracks with randomized gaps, can repeat throughout a run,
and remains audible during combat before stopping when the player returns outdoors.

**Structure construction workspace.** `dev structure new` opens a document type, length, width, and
height dialog, then enters an isolated first-person workspace for a generic structure or Level
Module plot. `dev structure import` lists valid resources of both types stored directly beside
`src/`, while `dev structure export` asks for a lowercase snake_case ID on first save and confirms
later overwrites of that bound file. Successful exports keep the workspace open and mark the
current draft clean. `dev structure exit` leaves the workspace and confirms before discarding
edited cells, torches, or Level Module metadata. Level Module tools edit precise weight, targeted
`VOID` cells, connections selected from the outside face of a lower boundary wall, and an atomic
player-spawn/shared entrance-exit marker pair. They also author horizontal enemy spawn zones from
two floor corners, showing the usable-cell count and colored candidate overlays. Each connection
can require a match or define the solid block used to fill its complete doorway when generation
leaves it unused.
Torches remain normal first-person palette placements instead of panel metadata. Exported modules
must still be added explicitly to the appropriate level content and catalog; repository-root files
are not consumed or registered by generation automatically. Spawn zones persist horizontal floor
rectangles; blocked decorative cells are ignored, but every zone must retain at least one
supported, body-clear candidate away from doorways. Current Level Module resources require physical
format version two, while `LevelDefinition` uses format version five. Module resources remain
geometry-focused, while `LevelDefinition` assigns them to its entry, hallway, and typed
room-requirement pools. Connection openings are derived from authored boundary geometry, so
hallways can use any enclosed opening size supported by the module bounds.

**Blocks.** Grass, dirt, sand, stone, wood, leaves, cobblestone, mossy stone bricks, stone bricks,
terracotta bricks, and wood planks are minable and placeable. Copper is minable but not placeable.
Worlds without prior mining progress show a mining tip five seconds after loading. The tip
highlights a nearby mineable terrain block and disappears permanently after the player mines a
block or walks away from the highlighted area.
Approaching a collectible apple or pumpkin shows a food recovery tip until the player picks up food
or walks away. Tutorial completion is stored per world so completed tips do not reappear.
Five seconds after the player's first mined block, a top-left hint introduces the `Tab` crafting
menu unless it has already been opened. Tutorial hints wait for any active hint to finish first.
Using a hoe on the exposed top face of grass or dirt converts it into dry farmland, which drops dirt
when mined.
Seeded copper deposits generate after the surrounding terrain as connected 5–30 block blobs. Most
of each deposit stays underground, while some deposits expose up to three blocks at the surface.
Stone and the other common blocks are hand-minable. Copper requires a stone, copper, or iron
pickaxe, while the stronger masonry blocks require a copper or iron pickaxe. Torches are placeable
blocks that you can walk through — each is an omni light with a 9-block radius. Selecting any
placeable item shows a `Right Click to Place Block` interaction prompt while building is available.
Overworld chests are
crafted from wood, placed by the player, persist 15 storage slots, and must be empty before they can
be mined. Generated dungeon chests use the same panel but are take-only and last only for the
current attempt.
Permanent campfires are atomic 3×3 emplacements crafted from twelve stone and two wood. They require
a clear, fully supported footprint, stay lit without fuel, cast the nearest bounded campfire shadow,
and return one campfire item when any footprint cell is mined.
Overworld torch shadows are configurable for the nearest 0, 1, 2, or 4 lights and default to the
nearest one. Overworld chests are solid 1×1 placeable blocks rendered as separate body and lid
meshes with dedicated chest textures. They cannot be mined by hand, and only empty overworld chests
can be mined with a pickaxe.
Hovering a reachable chest brightens it and hinges its lid open slightly. Left-clicking opens its
3×5 storage in the center while the backpack opens from the right. Overworld chests allow transfers
in both directions and persist their contents; dungeon chests allow only taking items. Clicking a
repeat chest item transfers its stack to inventory, and Take all transfers every stack that fits.
Guaranteed chests use Claim Reward to transfer the whole bundle atomically. Mining
an empty overworld chest returns it to the player inventory. `P` or `Esc` closes both panels; `Tab`
replaces the chest with the crafting menu while keeping the backpack open.

**Tools.** New worlds start with an empty inventory, while the first pickaxe is crafted from stone
and wood. Item actions are data-driven: the hoe tills exposed grass and dirt, all three pickaxe tiers
can mine copper, and the sword uses click-triggered, alternating melee swings with a fading
radial scan tracing its 120-degree attack area in front of the player. Its base damage rolls from 8
to 10 independently for each enemy hit. Combat registers slash, blunt, and pierce damage types;
enemies are neutral by default. Zombies take 1.5 times damage from slash, while Skeletons take half
damage from slash and 1.5 times damage from blunt. Stone Golems take half damage from slash and
pierce while remaining neutral to blunt. The Iron Pickaxe is initially guaranteed by the stone
dungeon and can later roll from its farm pool. It has mining power 3, a 2.5 speed multiplier, and no
crafting recipe. The first arrow hit against an unaware combat target deals double damage. Every
first player hit immediately starts the target's response: enemies aggro and docile creatures flee.
Sword and hammer hits use a neutral 1x sneak multiplier, and further arrow hits while the target
remains aggroed or fleeing receive no sneak bonus. The copper hammer uses a slower
two-handed overhead slam that damages and knocks back enemies within about
four blocks of the hammer's ground contact while an expanding white ring marks that area. Its
authored damage falls linearly from 15 at the impact center to 5 at the edge before combat stats.
Damaged enemies show a small black-and-red health bar above their model. Successful hits also show
damage numbers that rise and fade above each affected enemy; the numbers remain legible at the
default camera zoom, render over health bars and world geometry, and are hidden once the camera is
zoomed farther out. Weakness damage is
yellow-gold, resistant damage is dark grey, and neutral damage remains white.
Holding primary use with the bow quickly raises it in front of the player, nocks the first available
stone or copper arrow, and draws the string over 1.5 seconds before holding at maximum draw. A
black-and-yellow bar above the player shows the draw progress, while a white trajectory line updates
from the bow to the predicted first impact and fades near its endpoint. The bow aims at the first
creature, terrain, or object surface under the cursor, solves a reachable ballistic angle dynamically, and caps unreachable shots at
45 degrees. Right-clicking cancels the draw immediately without consuming its arrow; primary use must be released before drawing again. Releasing consumes the nocked arrow and fires it at a speed proportional to the draw. Arrows follow that gravity-driven arc, turn along
their flight direction, and stick into the first enemy or solid block they hit for one second before
fading away, with a short white trail following behind each arrow in flight. The bow chooses the first
compatible arrow in hotbar order, then backpack order. Stone arrows list 8 base pierce damage and
copper arrows list 12; draw progress scales the stat-adjusted hit from 40% to 100% before affinity is applied. Both apply two
knockback before player strength, enemy defense, and damage affinities are resolved.
Held tools use either runtime-extruded pixel art or authored 3D scenes.

**Loot.** Overworld enemies roll deterministic per-species loot pools when defeated. A zombie
independently has a 75% chance to drop 1–3 Copper and a 17% chance to select one gear reward weighted
10 plain Copper Sword, 4 Vicious/Nimble-affixed Copper Sword socketed with a Power Rune, and 3 Stout
Copper Helmet. Each physical weapon or armor copy has its own stable instance ID, rolled affixes,
and ordered rune slots even when two copies share the same item definition. Material drops merge
nearby and expire after five minutes; equipment does not time-expire. The bounded world-loot state
survives chunk streaming, transitions, and save/load. A full backpack leaves the drop in the world; at the hard
128-entry cap, admitting a new batch evicts the nearest-expiring material first, then the oldest
equipment entry only when every retained entry is equipment.

**Lighting.** Per-vertex ambient occlusion is baked into chunk meshes. A directional sun plus a
fill light drive real-time shadows, and a keyframed day/night profile interpolates sky, ambient,
sun color/energy, and shadow opacity across the cycle. Forward+ is the primary renderer. Runtime
fallback values keep GL Compatibility usable at reduced fidelity, without volumetric fog.

**Day/night.** A full 24-hour cycle runs every 20 real minutes, starting at 6:00. Day is
06:00–19:00; sunrise and sundown get their own warm color keys, and nights stay bright enough
to play.

**Slimes.** Large blocky slimes spawn only in the overworld at night and split deterministically
into medium, then small, descendants when defeated. Children jump outward from nearby clear space
and have brief hit immunity after splitting. Up to four can attach to the player at once, dealing
immediate defense-aware damage and repeating it every half second while stacking movement slows up
to a 60% reduction. Each successful grounded jump dislodges one attached slime.

**Music.** The overworld daytime playlist plays at most once per day and fades out quickly while
enemies are aggressive. Dungeon music uses its own shuffled playlist, ignores the day clock and
combat state, and can repeat after randomized gaps throughout a dungeon run. Press `M` to preview
tracks grouped by folder.

**Crafting.** Opening crafting with `Tab` reveals the general recipe panel alongside the backpack.
It contains the eight recipes that do not require a workstation. Iron Pickaxe is initially a
guaranteed stone-dungeon reward and later appears in that dungeon's repeat pool rather than a
crafting recipe. Basic Rune currently has no normal
production acquisition. A placed anvil opens its own panel with the eight copper tool, weapon, and
armor recipes plus copper arrows. A placed cauldron opens a food-and-potion panel; its initial recipe combines two
pumpkins and two apples into one health potion. All catalogs
show a short description of the selected output above its ingredients. Stat-bearing recipes show
their item stats below the ingredients, with numeric values in the same yellow-gold used
for weakness damage. Weapon stats include damage type, maximum damage and its authored range,
reach, cooldown, sweep, and knockback. Pickaxe stats show mining power and speed multiplier, while
consumable stats show the amount of health restored. Catalogs
use materials from the backpack and hotbar and craft immediately when the enabled Craft button is
pressed, playing one success sound. Apples and pumpkins each restore 10% of maximum health, while
health potions restore health completely.

**Developer console.** Press `/` to open a command line at the bottom of the screen. Submitted
commands remain available for the current game session; use `Up` and `Down` to browse them without
losing an unfinished command. The
`spawn <item> [count]` command adds any catalog item directly to the backpack for testing, with the
count defaulting to one when omitted. This intentionally allows debug-only progression bypasses such
as `spawn iron_pickaxe`; `spawn basic_rune` also remains available for testing content that has no
normal production source. `sethealth <number>` sets current health to a non-negative
value, clamping values above the player's current maximum. Item IDs and display names are accepted;
material-qualified item IDs include `iron_pickaxe`, `copper_pickaxe`, and `copper_sword`. Structure
construction uses `dev structure new`, `dev structure import`, `dev structure export`, and
`dev structure exit`. While fully inside an active dungeon encounter, `dev dungeon clear` defeats
every enemy assigned to that room across all pending waves, opens the room through its normal clear
transition, and closes the console. Debug clearing awards no combat experience, item proficiency, or
dungeon enemy loot. Press `/` again or `Esc` to close the console without opening the pause menu.
`spawn birds [count]` creates a mixed
batch of crows, redbirds, ducks, and bluebirds near the player, while
`spawn bird <crow|redbird|duck|bluebird> [count]` creates a specific variant. Bird counts default
to four for a mixed batch and one for a specific variant, with a maximum of sixteen. Copper can be
mined from deposits or added directly with `spawn copper <count>`. New worlds contain one seeded 5×4 pumpkin patch 35–45
blocks from the initial player spawn. Its location, growth states, and rotations persist in the
save. The
`spawn pumpkin_patch` command relocates and randomizes that persistent patch near the player.
Harvested pumpkins stack in the inventory and restore 10% of maximum health when right-clicked in
the backpack or hotbar, or when selected and used with left-click in the world.
About five percent of procedural trees carry apples: two to six collectible apples spawn beneath
the tree and twenty decorate its subtly tinted lower outer leaves. Collected apples persist in saves
and restore 10% of maximum health through the same inventory consumption controls. Mining an
apple-bearing leaf gives each attached apple a 20% chance to fall as a persistent pickup, capped at
one fallen apple per mined leaf.

**UI & saves.** Backpack and hotbar stacks can be split by scrolling while left-dragging. The side
panel includes a trash drop target that accepts backpack, hotbar, and equipped items. A
frosted-glass front-end provides the main menu, world select over three save slots, create-world
and hold-3-seconds-to-delete modals, a chunk-progress loading screen, and a pause menu that freezes
the game. The pause menu exposes persistent frame-rate, 3D resolution,
anti-aliasing, fog, sun-shadow, shadow-range, overworld and dungeon torch-shadow, and
ambient-audio settings. Dungeon shadows default to the nearest six authored torches and fade
between active casters. Saves live in `user://saves/` and autosave every 30 seconds, plus shortly
after any block edit, persistent overworld chest-content change, or persistent world-loot change.
Saving inside a dungeon records its overworld return position because dungeon layouts are
recreated on entry. Dungeon attempt indices, completion counts, and claimed first-clear reward IDs
are saved independently from
the transient layout and chest contents. Dungeon progress changes use the same debounced save path,
and a successful completion requests an immediate save.

## Project Structure

```text
src/                    Godot project. Entry scene: app/app.tscn
├── actors/             Shared procedural animation state, profiles, and humanoid animator
├── app/                Application shell and screen/session transitions
├── game/               Gameplay composition root and session persistence
├── world/              Coordinator plus chunks/, generation/, materials/, model/, and settings/
├── blocks/             Block domain, voxel query contract, and shared block presentation
├── combat/             Melee contacts, profiles, targeting, and validation
├── crafting/           Recipe resources, inventory coordination, presentation, and tests
├── chests/             Container definitions, persistent storage, transfers, presentation, and tests
├── dev_console/        Developer commands, bottom-screen console presentation, and tests
├── entities/           Entity catalog, AI, voxel navigation, populations, and custom presentation
├── levels/             Dungeon content, definitions, generation, runtime, entrance, and presentation
├── items/              Item catalog, action definitions, and held-item scenes
├── loot/               Loot definitions, deterministic resolution, world drops, and focused tests
├── mining/             Mining-owned presentation and focused tests
├── player/             Motor, interaction, targeting, input, animation, camera/, debug/, and visuals/
├── environment/        Packaged environment scene and day_night/ system
├── inventory/          Inventory model and inventory-owned ui/
├── settings/           Persistent display and rendering settings
├── structures/         Generic definitions, drafts, root-file storage, runtime, presentation, and tests
├── ui/                 Shared components/, hud/, screens/, and theme/
├── save/               Three-slot JSON save manager
└── tests/              Headless behavior, determinism, fuzz, and streaming checks
```

Systems are constructed in `game/game.tscn` and injected into each other via `setup()` calls
rather than autoloads or singletons. See `docs/architecture.md` and `docs/world-streaming.md`.

## Building & Running

**Prerequisites:** Godot **4.7**. No other SDKs or dependencies — the game uses only built-in
Godot APIs.

```text
godot --path src
```

Or open `src/` in the Godot 4.7 editor and press Play. The window starts at 1280×720 and is
resizable. The 3D scene renders natively through 2560×1440 and upscales above that ceiling;
UI remains at output resolution. macOS (universal) and Web export presets are committed in
`src/export_presets.cfg`.

## Assets & Attribution

World geometry and held pixel-tool meshes are generated at runtime, while the player is assembled
from Godot primitive meshes. Visual effects use project-authored shaders.

| Asset | Source | License |
| --- | --- | --- |
| `src/assets/fonts/RobotoSlab-{Regular,SemiBold,Bold}.ttf` | [Roboto Slab](https://fonts.google.com/specimen/Roboto+Slab) — Christian Robertson, via Google Fonts | Apache-2.0 |
| `src/assets/audio/ambient/nri-DawnchorusinAmphitheater.mp3` | National Park Service – Dawn chorus in Amphitheater | Public Domain (U.S. Government work) |
| `src/assets/audio/ambient/forest_night_avocado.ogg` | Avocado, prompted by Michael Riegger | Project-authored |
| `src/assets/audio/environment/campfire/fireplace_5_CC0.ogg` | [Fireplace #5](https://bigsoundbank.com/fireplace-5-s2857.html) – Joseph SARDIN, BigSoundBank | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/entities/skeleton/vocalizations/*.mp3` (3 files) | [Skeletons bones dry wooden sticks hangers](https://freesound.org/people/ChExi/sounds/848095/) – ChExi | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/entities/sheep/vocalizations/real_sheep_*.wav` (7 files) | [Sheep 1 and related sheep recordings](https://bigsoundbank.com/sheep-1-s2343.html) – Joseph SARDIN, BigSoundBank | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/entities/zombie/vocalizations/Zombie_*.mp3` (6 files) | [Little Robot Sound Factory](https://web.archive.org/web/20160314071020id_/http://www.littlerobotsoundfactory.com/) – Morten Barfod Søegaard, Little Robot Sound Factory | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `src/assets/audio/entities/bird/wing_flaps/duck_sampled_wing_flap_04_CC0.ogg` | DUCK SAMPLED PACK – real recordings sampled from BigSoundBank / LaSonotheque | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/entities/bird/vocalizations/duck/duck_sampled_quack_*_CC0.*` (3 files) | DUCK SAMPLED PACK – real recordings sampled from BigSoundBank / LaSonotheque | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/entities/bird/vocalizations/crow/crow_sampled_caw_*_CC0.ogg` (5 files) | [BigSoundBank / LaSonotheque](https://bigsoundbank.com/licenses.html) – Joseph SARDIN; edited for the game | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/entities/bird/vocalizations/{redbird,bluebird}/*_CC0.ogg` (13 files) | BigSoundBank – Joseph SARDIN / Le tiroir du fond; edited for the game | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/entities/golem/{walk,impact,death}/*` (6 files) | Golem sounds — [Kenney source 1](https://gamedev-asset-gallery.internalmeta.com/asset?id=kenney%3Aexpanded-bbc9a525b2c0077ceec78c6abb8cf8f80955ca99) and [Kenney source 2](https://gamedev-asset-gallery.internalmeta.com/asset?id=kenney%3Aexpanded-7beda63cb50139fdd859de8c9b87f9c5b740d37d) | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/footsteps/dirt/Footstep_Dirt_*.wav` (9 files) | [Fantasy Sound Effects Library](https://littlerobotsoundfactory.com/) – Footstep Dirt – by Morten Barfod Søegaard, Little Robot Sound Factory, distributed by Little Robot Sound Factory | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `src/assets/audio/footsteps/grass/footstep_grass_*.ogg` (5 files) | [Impact Sounds](https://kenney.nl/assets/impact-sounds) – Kenney | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/combat/` weapon-draw and creature-impact sounds (9 files) | [Voiceover Pack](https://kenney.nl/assets/voiceover-pack) – Kenney | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/combat/impacts/player/player_hit.wav` | Muse, prompted by Michael Riegger | Project-authored |
| `src/assets/audio/combat/weapons/hammer/impacts/low_thump_332670_CC0.ogg` | [low thump.wav](https://freesound.org/people/Reitanna/sounds/332670/) – Reitanna, Freesound sound 332670 | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/footsteps/water/Footstep_Water_*.wav` (8 files) | [Little Robot Sound Factory](https://littlerobotsoundfactory.com/) – Water footsteps – by Morten Barfod Søegaard | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `src/assets/audio/sfx/tools/impactGeneric_light_*.ogg` (4 files) | [Impact Sounds](https://kenney.nl/assets/impact-sounds) – Kenney (https://kenney.nl) – generic light impacts for tool and crafting clunks | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/sfx/farming/tilling/bookFlip*.ogg` (3 files) | [RPG Audio](https://kenney.nl/assets/rpg-audio) – Kenney | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/sfx/farming/harvesting/pop_generic_*_CC0.wav` (3 files) | Generic pop by Muse Spark | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/sfx/items/consume/munch_crunchy_fruit_sequence_3x_CC0.wav` | Source recordings by Joseph SARDIN, BigSoundBank; edited by Muse Spark | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/sfx/levels/dungeon/door/doorOpen_*.ogg` (2 files) | [RPG Audio](https://kenney.nl/assets/rpg-audio) – Kenney | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/music/dungeon/Dungeon Master.mp3` | [Dungeon Master](https://freemusicarchive.org/music/geoff-harvey-purple-planet-music/dungeon-master/dungeon-master-2/) – Geoff Harvey, Purple Planet Music | Creative Commons Attribution (version varies) |
| `src/assets/audio/music/dungeon/Dark Angel.mp3` | [“Dark Angel”](https://freemusicarchive.org/music/joseph-r-lilore/soundscapes/dark-angel/) – Joseph R. Lilore | Creative Commons Attribution (CC BY; version varies) |
| `src/assets/audio/music/dungeon/Night.mp3` | [“Night”](https://freemusicarchive.org/music/mark-wilson-x/quiet-moods/night-3/) – Mark Wilson X | Creative Commons Attribution (CC BY; version varies) |
| `src/assets/audio/music/daytime/Sunrise.mp3` | [“Sunrise”](https://freemusicarchive.org/music/luise-frentzel//sunrise-1/) – Luise Frentzel × Fachhochschule Dortmund | Creative Commons Attribution (CC BY; version varies) |
| `src/assets/models/tools/hoe/copper_hoe.glb`, `Textures/colormap.png`, and derived inventory icon | [Survival Kit](https://kenney.nl/assets/survival-kit) – Kenney | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/textures/tools/bow/*.png` and `src/items/held/{bow,stone_arrow,copper_arrow}.tscn` | Project-authored deterministic pixel art and low-poly primitive models | Project-authored |
| `src/assets/models/farming/pumpkin/*.fbx` (6 files) and derived inventory icon | [Ultimate Crops](https://quaternius.com/packs/ultimatecrops.html) – Quaternius | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/textures/items/anvil.png` | Muse, prompted by Codex for Michael Riegger | Project-authored |
| `src/assets/textures/items/campfire.png` | Codex, prompted by Michael Riegger; authored and nearest-neighbor scaled for Wildes | Project-authored |
| `src/assets/models/foraging/apple/apple.glb`, `Textures/colormap.png`, and derived inventory icon | [Food Kit](https://kenney.nl/assets/food-kit) – Kenney | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/textures/blocks/{bricks,chiseled_marble,cracked_cinder_bricks,deepstone_brick,sedimentary_stone}.png` | Created by Justin Soberano | Project-authored |
| `src/assets/textures/foliage/{blue_wildflower,grass,orange_tulip,pink_heartflower,red_flower,short_grass}.png` | Handmade by Justin Soberano | Project-authored |
| `src/assets/textures/blocks/farmland_dry.png` | Codex, prompted by Michael Riegger | Project-authored |
| `src/assets/textures/effects/mining/dirt_*.png` (3 files) | [Particle Pack](https://kenney.nl/assets/particle-pack) – Kenney | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/images/icons/button/move_to_backpack.png` | Meta Muse (`muse-image-1.0-eval`) through the `meta-imagegen` skill; prompted and downsampled for Wildes | Project-authored |

Godot itself is MIT licensed.
