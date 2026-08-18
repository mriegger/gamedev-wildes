# Wildes

**Wildes** is an isometric voxel sandbox built in **Godot 4.7** (GDScript). You explore an
endless procedurally generated world under an orthographic isometric camera, mine blocks into
a nine-slot hotbar, and build with them. The loop is explore → mine → build, on terrain that
streams in around you as you walk, under a running day/night cycle.

Worlds are saved to three local slots and persist your seed, edits, player and chest inventories,
position, and world time. Copper deposits regenerate deterministically from the world seed.

## Controls

| Input | Action |
| --- | --- |
| `WASD` / arrows | Move (camera-relative) |
| `Shift` + move | Sprint |
| `Space` | Hop — needed to get up any ledge |
| `Q` / `E` | Rotate the camera 45° |
| Mouse wheel / pinch | Zoom |
| Left-click / hold | Open a targeted chest or crafting station, or use the selected item's primary action; hold to mine, click to attack or till soil |
| Right-click | Use the selected item's secondary action; place blocks or consume food |
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
be removed from Module Tools.

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
module pool, and encounter, so additional variants can join an existing type and new types such as
small or boss rooms can be added without a dungeon-specific generator branch.
Master rooms configure 40 zombies, normal rooms 25, and chest rooms 6. A room encounter activates
only after the player is fully inside. Every ready room can run a wave concurrently, and each wave
permits at most 20 active enemies from its originating room while larger groups refill authored
spawn positions on later physics ticks. Discovered retreat paths stay open, so enemies can roam
between rooms while their wave ownership remains unchanged. The shared dungeon runtime derives its
active capacity from the generated room tree's weighted antichain bound instead of imposing a fixed
wave count. Undiscovered rooms and hallways are not rendered, including their torches, lights, and
shadows. A discovered branch's authored textured wall-fill seal stays visible until its parent room
clears; collision opens immediately, the seal fades out over 0.35 seconds, and the branch and its
torches fade in over the same interval. Opened seals never close. The HUD aggregates wave, active,
and pending counts. Leaving or dying discards that run, restores the exact overworld anchor and
player-owned inventory, and creates fresh encounter state on re-entry.

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
supported, body-clear candidate away from doorways. Current Level Module resources require their
physical format version. Module
resources remain geometry-focused, while `LevelDefinition` assigns them to its entry, hallway, and
typed room-requirement pools. Connection openings are derived from authored boundary geometry, so
hallways can use any enclosed opening size supported by the module bounds.

**Blocks.** Grass, dirt, sand, stone, wood, leaves, cobblestone, mossy stone bricks, stone bricks,
terracotta bricks, and wood planks are minable and placeable. Copper is minable but not placeable.
Using a hoe on the exposed top face of grass or dirt converts it into dry farmland, which drops dirt
when mined.
Seeded copper deposits generate after the surrounding terrain as connected 5–30 block blobs. Most
of each deposit stays underground, while some deposits expose up to three blocks at the surface.
Stone and the other common blocks are hand-minable. Copper requires a stone or copper pickaxe,
while the masonry blocks require a copper pickaxe. Torches are placeable blocks that you can walk
through — each is an omni light with a 9-block radius.
Overworld torch shadows are configurable for the nearest 0, 1, 2, or 4 lights and default to the
nearest one. Chests are solid 1×1 placeable blocks rendered as separate body and lid meshes with
dedicated chest textures. They cannot be mined by hand, and only empty chests can be mined with a
pickaxe.
Hovering a reachable chest brightens it and hinges its lid open slightly. Left-clicking opens
that chest's own persistent 3×5 storage in the center while the backpack opens from the right.
Items can be dragged between the chest, backpack, and hotbar. Clicking a backpack or chest item
transfers its stack to the other inventory, and the chest's Take all button transfers every stack
that fits into the backpack. An empty chest can be mined with a pickaxe to return it to the player
inventory; a chest containing items cannot be mined. `P` or `Esc` closes both panels; `Tab` replaces
the chest with the crafting menu while keeping the backpack open.

**Tools.** New worlds start with an empty inventory, while the first pickaxe is crafted from stone
and wood. Item actions are data-driven: the hoe tills exposed grass and dirt, stone and copper
pickaxes can mine copper, and the sword uses click-triggered, alternating melee swings. Held tools
use either runtime-extruded pixel art or authored 3D scenes.

**Lighting.** Per-vertex ambient occlusion is baked into chunk meshes. A directional sun plus a
fill light drive real-time shadows, and a keyframed day/night profile interpolates sky, ambient,
sun color/energy, and shadow opacity across the cycle. Forward+ is the primary renderer. Runtime
fallback values keep GL Compatibility usable at reduced fidelity, without volumetric fog.

**Day/night.** A full 24-hour cycle runs every 20 real minutes, starting at 6:00. Day is
06:00–19:00; sunrise and sundown get their own warm color keys, and nights stay bright enough
to play.

**Crafting.** Opening crafting with `Tab` reveals the general recipe panel alongside the backpack.
It contains the five recipes that do not require a workstation. A placed anvil opens its own panel
with the seven copper tool, weapon, and armor recipes. Both catalogs use materials from the
backpack and hotbar and craft immediately when the enabled Craft button is pressed, playing one
success sound.

**Developer console.** Press `/` to open a command line at the bottom of the screen. The
`spawn <item> [count]` command adds any catalog item directly to the backpack for testing, with the
count defaulting to one when omitted. Item
IDs and display names are accepted; equipment IDs remain material-qualified, such as
`copper_pickaxe` and `copper_sword`. Structure construction uses `dev structure new`,
`dev structure import`, `dev structure export`, and `dev structure exit`. Press `/` again or
`Esc` to close the console without opening the pause menu. Copper can be mined from deposits or
added directly with `spawn copper <count>`. New worlds contain one seeded 5×4 pumpkin patch 35–45
blocks from the initial player spawn. Its location, growth states, and rotations persist in the
save. The
`spawn pumpkin_patch` command relocates and randomizes that persistent patch near the player.
Harvested pumpkins stack in the inventory and restore the player's health to full when right-clicked
in the backpack or hotbar, or when selected and used with right-click in the world.
About five percent of procedural trees carry apples: two to six collectible apples spawn beneath
the tree and twenty decorate its subtly tinted lower outer leaves. Collected apples persist in saves and restore
75 percent of maximum health through the same inventory consumption controls.

**UI & saves.** Backpack and hotbar stacks can be split by scrolling while left-dragging. The side
panel includes a trash drop target that accepts backpack, hotbar, and equipped items. A
frosted-glass front-end provides the main menu, world select over three save slots, create-world
and hold-3-seconds-to-delete modals, a chunk-progress loading screen, and a pause menu that freezes
the game. The pause menu exposes persistent frame-rate, 3D resolution,
anti-aliasing, fog, sun-shadow, shadow-range, overworld and dungeon torch-shadow, and
ambient-audio settings. Dungeon shadows default to the nearest six authored torches and fade
between active casters. Saves live in `user://saves/` and autosave every 30 seconds, plus shortly
after any block edit. Saving inside a dungeon records its overworld return position because
dungeon layouts are recreated on entry.

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
| `src/assets/audio/entities/sheep/vocalizations/real_sheep_*.wav` (7 files) | [Sheep 1 and related sheep recordings](https://bigsoundbank.com/sheep-1-s2343.html) – Joseph SARDIN, BigSoundBank | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/entities/zombie/vocalizations/Zombie_*.mp3` (6 files) | [Little Robot Sound Factory](https://web.archive.org/web/20160314071020id_/http://www.littlerobotsoundfactory.com/) – Morten Barfod Søegaard, Little Robot Sound Factory | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `src/assets/audio/entities/bird/wing_flaps/duck_sampled_wing_flap_04_CC0.ogg` | DUCK SAMPLED PACK – real recordings sampled from BigSoundBank / LaSonotheque | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/footsteps/dirt/Footstep_Dirt_*.wav` (9 files) | [Fantasy Sound Effects Library](https://littlerobotsoundfactory.com/) – Footstep Dirt – by Morten Barfod Søegaard, Little Robot Sound Factory, distributed by Little Robot Sound Factory | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `src/assets/audio/footsteps/grass/footstep_grass_*.ogg` (5 files) | [Impact Sounds](https://kenney.nl/assets/impact-sounds) – Kenney | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/combat/` weapon-draw and creature-impact sounds (9 files) | [Voiceover Pack](https://kenney.nl/assets/voiceover-pack) – Kenney | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/combat/impacts/player/player_hit.wav` | Muse, prompted by Michael Riegger | Project-authored |
| `src/assets/audio/footsteps/water/Footstep_Water_*.wav` (8 files) | [Little Robot Sound Factory](https://littlerobotsoundfactory.com/) – Water footsteps – by Morten Barfod Søegaard | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `src/assets/audio/sfx/tools/impactGeneric_light_*.ogg` (4 files) | [Impact Sounds](https://kenney.nl/assets/impact-sounds) – Kenney (https://kenney.nl) – generic light impacts for tool and crafting clunks | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/sfx/farming/tilling/bookFlip*.ogg` (3 files) | [RPG Audio](https://kenney.nl/assets/rpg-audio) – Kenney | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/sfx/farming/harvesting/pop_generic_*_CC0.wav` (3 files) | Generic pop by Muse Spark | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/sfx/items/consume/munch_crunchy_fruit_sequence_3x_CC0.wav` | Source recordings by Joseph SARDIN, BigSoundBank; edited by Muse Spark | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/models/tools/hoe/copper_hoe.glb`, `Textures/colormap.png`, and derived inventory icon | [Survival Kit](https://kenney.nl/assets/survival-kit) – Kenney | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/models/farming/pumpkin/*.fbx` (6 files) and derived inventory icon | [Ultimate Crops](https://quaternius.com/packs/ultimatecrops.html) – Quaternius | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/textures/items/anvil.png` | Muse, prompted by Codex for Michael Riegger | Project-authored |
| `src/assets/models/foraging/apple/apple.glb`, `Textures/colormap.png`, and derived inventory icon | [Food Kit](https://kenney.nl/assets/food-kit) – Kenney | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/textures/blocks/farmland_dry.png` | Codex, prompted by Michael Riegger | Project-authored |
| `src/assets/textures/effects/mining/dirt_*.png` (3 files) | [Particle Pack](https://kenney.nl/assets/particle-pack) – Kenney | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/images/icons/button/move_to_backpack.png` | Meta Muse (`muse-image-1.0-eval`) through the `meta-imagegen` skill; prompted and downsampled for Wildes | Project-authored |

Godot itself is MIT licensed.
