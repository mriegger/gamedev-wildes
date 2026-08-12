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
| `1`–`9` | Select hotbar slot; while the backpack is open, assign the hovered item to that slot |
| `Tab` | Toggle backpack and crafting |
| `P` | Toggle backpack only |
| `/` | Toggle the developer command console |
| `F10` | Toggle player animation tuner |
| `Esc` | Pause |

Reach is 6 blocks. The block under the cursor is outlined, and a ghost block previews where a
placement would land; placements that would overlap you are rejected.

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

**Blocks.** Grass, dirt, sand, stone, wood, and leaves are minable and placeable. Seeded copper
deposits generate after the surrounding terrain as connected 5–30 block blobs. Most of each
deposit stays underground, while some deposits expose up to three blocks at the surface. Stone
and the other common blocks are hand-minable. Copper requires a stone or copper pickaxe. Torches
are a seventh placeable that you can walk through — each is an omni light with a 9-block radius.
Torch shadows are configurable for the nearest 0, 1, 2, or 4 lights and default to the nearest
one.

**Tools.** New worlds start with a copper sword, while the first pickaxe is crafted from stone and
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
data-driven recipes use materials from the backpack and hotbar, take two seconds to complete, and
cancel without consuming ingredients when the panel closes or another recipe is selected.

**Developer console.** Press `/` to open a command line at the bottom of the screen. The
`spawn <item> <count>` command adds any catalog item directly to the backpack for testing. Item
IDs and display names are accepted; equipment IDs remain material-qualified, such as
`copper_pickaxe` and `copper_sword`. Press `/` again or `Esc` to close the console without
opening the pause menu. Copper can be mined from deposits or added directly with
`spawn copper <count>`.

**UI & saves.** A frosted-glass front-end: main menu, world select over three save slots,
create-world and hold-3-seconds-to-delete modals, a chunk-progress loading screen, and a pause
menu that freezes the game. The pause menu exposes persistent frame-rate, 3D resolution,
anti-aliasing, fog, sun-shadow, shadow-range, torch-shadow, and ambient-audio settings. Saves live in
`user://saves/` and autosave every 30 seconds, plus shortly after any block edit.

## Project Structure

```text
src/                    Godot project. Entry scene: app/app.tscn
├── actors/             Shared procedural animation state, profiles, and humanoid animator
├── app/                Application shell and screen/session transitions
├── game/               Gameplay composition root and session persistence
├── world/              Coordinator plus chunks/, generation/, materials/, model/, settings/,
│                       and special_blocks/
├── blocks/             Block ids, definitions, catalog, and torch placement rules
├── combat/             Melee contacts, profiles, targeting, and validation
├── crafting/           Recipe resources, inventory coordination, presentation, and tests
├── dev_console/        Developer commands, bottom-screen console presentation, and tests
├── entities/           Entity catalog, AI, voxel navigation, populations, and custom presentation
├── items/              Item catalog, action definitions, and held-item scenes
├── mining/             Mining-owned presentation and focused tests
├── player/             Motor, interaction, targeting, input, animation, camera/, debug/, and visuals/
├── environment/        Packaged environment scene and day_night/ system
├── inventory/          Inventory model and inventory-owned ui/
├── settings/           Persistent display and rendering settings
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
| `src/assets/audio/entities/zombie/vocalizations/Zombie_*.mp3` (6 files) | [Little Robot Sound Factory](https://web.archive.org/web/20160314071020id_/http://www.littlerobotsoundfactory.com/) – Morten Barfod Søegaard, Little Robot Sound Factory | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `src/assets/audio/footsteps/dirt/Footstep_Dirt_*.wav` (9 files) | [Fantasy Sound Effects Library](https://littlerobotsoundfactory.com/) – Footstep Dirt – by Morten Barfod Søegaard, Little Robot Sound Factory, distributed by Little Robot Sound Factory | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `src/assets/audio/combat/` sword and creature sounds (6 files) | [Voiceover Pack](https://kenney.nl/assets/voiceover-pack) – Kenney | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/audio/footsteps/water/Footstep_Water_*.wav` (8 files) | [Little Robot Sound Factory](https://littlerobotsoundfactory.com/) – Water footsteps – by Morten Barfod Søegaard | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `src/assets/audio/sfx/tools/impactGeneric_light_*.ogg` (4 files) | [Impact Sounds](https://kenney.nl/assets/impact-sounds) – Kenney (https://kenney.nl) – generic light impacts for tool and crafting clunks | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| `src/assets/textures/effects/mining/dirt_*.png` (3 files) | [Particle Pack](https://kenney.nl/assets/particle-pack) – Kenney | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |

Godot itself is MIT licensed.
