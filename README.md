# Wildes

**Wildes** is an isometric voxel sandbox built in **Godot 4.7** (GDScript). You explore an
endless procedurally generated world under an orthographic isometric camera, mine blocks into
a nine-slot hotbar, and build with them. The loop is explore → mine → build, on terrain that
streams in around you as you walk, under a running day/night cycle.

Worlds are saved to three local slots and persist your seed, edits, inventory, position, and
world time. Copper deposits regenerate deterministically from the world seed.

## Controls

| Input | Action |
| --- | --- |
| `WASD` / arrows | Move (camera-relative) |
| `Shift` + move | Sprint |
| `Space` | Hop — needed to get up any ledge |
| `Q` / `E` | Rotate the camera 45° |
| Mouse wheel / pinch | Zoom |
| Left-click / hold | Use the selected item's primary action; hold to mine, click to attack |
| Right-click | Place the selected block |
| `F` | Enter or leave a nearby dungeon |
| `1`–`9` | Select hotbar slot; while the backpack is open, assign the hovered item to that slot |
| `Tab` | Toggle backpack and crafting |
| `P` | Toggle backpack only |
| `/` | Toggle the developer command console |
| `F10` | Toggle player animation tuner |
| `Esc` | Pause |

Reach is 6 blocks. The block under the cursor is outlined, and a ghost block previews where a
placement would land; placements that would overlap you are rejected.

The Structure Designer uses first-person `WASD` movement, mouse look, `Space`/`Ctrl` to
ascend/descend, and `Shift` acceleration. Left-click removes, right-click places, `Tab` opens the
infinite creative palette, and `M` opens Level Module tools with a free cursor. Closing either
panel returns to first-person building. `/` opens the developer console, and `Esc` closes active
designer UI before offering to leave the designer. In Module Tools, `Place Connections` returns to
first-person connection mode. Click a solid lower boundary wall for a standard 1×2 doorway, or
click the floor beneath a prebuilt boundary opening to register its complete shape and size. Only
matching openings connect; every unused opening therefore needs a compatible cap module. Press
`Esc` when finished. Two opposite connections form a straight hall; rooms can expose all four sides.

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

**Dungeon levels.** A doorway near the meadow spawn leads to a deterministic 8–12-module stone
dungeon assembled from authored chambers, halls, junctions, and dead ends. The finite interior
uses cutaway-facing geometry, a black void, and authored torch light. The overworld stays loaded
but its streaming and presentation are suspended until you return through the dungeon door.
Doorway selection, module pools, terrain presentation, ambient lighting, and return-door materials
are configured through typed level resources rather than hardcoded dungeon IDs.

**Structure construction workspace.** `dev structure new` opens a document type, length, width, and
height dialog, then enters an isolated first-person workspace for a generic structure or Level
Module plot. `dev structure import` lists valid resources of both types stored directly beside
`src/`, while `dev structure export` asks for a lowercase snake_case ID on first save and confirms
later overwrites of that bound file. Successful exports keep the workspace open and mark the
current draft clean. `dev structure exit` leaves the workspace and confirms before discarding
edited cells, torches, or Level Module metadata. Level Module tools edit precise weight, targeted
`VOID` cells, connections selected from the outside face of a lower boundary wall, and an atomic
spawn/return marker pair.
Torches remain normal first-person palette placements instead of panel metadata. Exported modules
must still be added explicitly to the appropriate level content and catalog; repository-root files
are not consumed or registered by generation automatically.
Hall and room are authoring descriptions rather than persisted module types: the generator follows
doorway connections, while `LevelDefinition` assigns modules to its start, expansion, and cap pools.
Connection openings are derived from authored boundary geometry, so hallways can use any enclosed
opening size supported by the module bounds.

**Blocks.** Grass, dirt, sand, stone, wood, leaves, cobblestone, mossy stone bricks, stone bricks,
terracotta bricks, and wood planks are minable and placeable. Copper is minable but not placeable.
Seeded copper deposits generate after the surrounding terrain as connected 5–30 block blobs. Most
of each deposit stays underground, while some deposits expose up to three blocks at the surface.
Stone and the other common blocks are hand-minable. Copper requires a stone or copper pickaxe,
while the masonry blocks require a copper pickaxe. Torches are placeable blocks that you can walk
through — each is an omni light with a 9-block radius.
Overworld torch shadows are configurable for the nearest 0, 1, 2, or 4 lights and default to the
nearest one.

**Tools.** New worlds start with an empty inventory, while the first pickaxe is crafted from stone and
wood. Item actions are data-driven: stone and copper pickaxes can mine copper, while the sword uses
click-triggered, alternating melee swings. Pixel-art held tools are extruded into shaded 3D
silhouette meshes at runtime.

**Lighting.** Per-vertex ambient occlusion is baked into chunk meshes. A directional sun plus a
fill light drive real-time shadows, and a keyframed day/night profile interpolates sky, ambient,
sun color/energy, and shadow opacity across the cycle. Forward+ is the primary renderer. Runtime
fallback values keep GL Compatibility usable at reduced fidelity, without volumetric fog.

**Day/night.** A full 24-hour cycle runs every 20 real minutes, starting at 6:00. Day is
06:00–19:00; sunrise and sundown get their own warm color keys, and nights stay bright enough
to play.

**Crafting.** Opening crafting with `Tab` reveals a recipe panel alongside the backpack. Eight
data-driven recipes use materials from the backpack and hotbar and craft immediately when the
enabled Craft button is pressed, playing one success sound.

**Developer console.** Press `/` to open a command line at the bottom of the screen. The
`spawn <item> <count>` command adds any catalog item directly to the backpack for testing. Item
IDs and display names are accepted; equipment IDs remain material-qualified, such as
`copper_pickaxe` and `copper_sword`. Structure construction uses `dev structure new`,
`dev structure import`, `dev structure export`, and `dev structure exit`. Press `/` again or
`Esc` to close the console without opening the pause menu. Copper can be mined from deposits or
added directly with `spawn copper <count>`.

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
| `src/assets/audio/footsteps/dirt/Footstep_Dirt_*.wav` (9 files) | [Fantasy Sound Effects Library](https://littlerobotsoundfactory.com/) – Footstep Dirt – by Morten Barfod Søegaard, Little Robot Sound Factory, distributed by Little Robot Sound Factory | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `src/assets/audio/footsteps/grass/footstep_grass_*.ogg` (5 files) | [Impact Sounds](https://kenney.nl/assets/impact-sounds) – Kenney | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/combat/` weapon-draw and creature-impact sounds (9 files) | [Voiceover Pack](https://kenney.nl/assets/voiceover-pack) – Kenney | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/combat/impacts/player/player_hit.wav` | Muse, prompted by Michael Riegger | Project-authored |
| `src/assets/audio/footsteps/water/Footstep_Water_*.wav` (8 files) | [Little Robot Sound Factory](https://littlerobotsoundfactory.com/) – Water footsteps – by Morten Barfod Søegaard | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `src/assets/audio/sfx/tools/impactGeneric_light_*.ogg` (4 files) | [Impact Sounds](https://kenney.nl/assets/impact-sounds) – Kenney (https://kenney.nl) – generic light impacts for tool and crafting clunks | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/textures/effects/mining/dirt_*.png` (3 files) | [Particle Pack](https://kenney.nl/assets/particle-pack) – Kenney | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |

Godot itself is MIT licensed.
