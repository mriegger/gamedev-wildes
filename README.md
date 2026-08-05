# Wildes

**Wildes** is an isometric voxel sandbox built in **Godot 4.7** (GDScript). You explore an
endless procedurally generated world under an orthographic isometric camera, mine blocks into
a nine-slot hotbar, and build with them. The loop is explore → mine → build, on terrain that
streams in around you as you walk, under a running day/night cycle.

Worlds are saved to three local slots and persist your seed, edits, inventory, position, and
world time.

## Controls

| Input | Action |
| --- | --- |
| `WASD` / arrows | Move (camera-relative) |
| `Space` | Hop — needed to get up any ledge |
| `Q` / `E` | Rotate the camera 45° |
| Mouse wheel / pinch | Zoom |
| Hold left-click | Mine the targeted block (0.35 s) |
| Right-click | Place the selected block |
| `1`–`9` | Select hotbar slot |
| `Esc` | Pause |

Reach is 6 blocks. The block under the cursor is outlined, and a ghost block previews where a
placement would land; placements that would overlap you are rejected.

## Features

**World.** Endless terrain generated from layered noise (hills, detail, biome, forest, ridges)
in 20×20 chunk columns, 36 blocks tall. You spawn in a grass meadow clearing; beyond it are
sandy lowlands, forests, and stone ridges. Lakes (16–42 blocks wide, 6 deep) and rivers carve
into the terrain and fill with water up to level 5.

**Streaming.** Chunks load in a radius of 4 around you (9×9 = 81 chunks) and unload two chunks
further out. Meshing runs on background threads so movement doesn't hitch; edits are stored
globally and survive unload/reload.

**Blocks.** Grass, dirt, sand, stone, wood, and leaves are minable and placeable. Torches are
a seventh placeable that you can walk through — each is an omni light with a 9-block radius;
the four nearest to you cast real shadows.

**Lighting.** Per-vertex ambient occlusion is baked into chunk meshes. A directional sun plus a
fill light drive real-time shadows, and a keyframed day/night profile interpolates sky, ambient,
sun color/energy, and shadow opacity across the cycle.

**Day/night.** A full 24-hour cycle runs every 20 real minutes, starting at 6:00. Day is
06:00–19:00; sunrise and sundown get their own warm color keys, and nights stay bright enough
to play.

**UI & saves.** A frosted-glass front-end: main menu, world select over three save slots,
create-world and hold-3-seconds-to-delete modals, a chunk-progress loading screen, and a pause
menu that freezes the game. Saves live in `user://saves/` and autosave every 30 seconds, plus
shortly after any block edit.

## Project Structure

```text
src/                    Godot project (src/project.godot). Entry scene: ui/main_menu/main_menu.tscn
├── game/               Root gameplay scene; wires every system together and owns save/load
├── world/              generation/ (noise terrain, lakes, rivers), model/ (voxel data + edits),
│                       rendering/ (chunk mesher, chunk + torch renderers), streaming/ (chunk manager)
├── blocks/             Block ids, per-block definitions, catalog, torch placement
├── player/             Motor, interactor (raycast + mine/place), camera rig, targeting, input buffer
├── environment/        Game clock, day/night profile + values, water profile, debug clock panel
├── inventory/          9-slot inventory model
├── ui/                 HUD + hotbar, main_menu/ (menu, world select, create/delete, loading,
│                       pause), theme/
├── save/               Three-slot JSON save manager
├── shaders/            terrain, water, blob_shadow, frosted_glass
└── assets/             Roboto Slab UI font, logo images
```

Systems are constructed in `game/game.tscn` and injected into each other via `setup()` calls
rather than autoloads or singletons.

## Building & Running

**Prerequisites:** Godot **4.7**. No other SDKs or dependencies — the game uses only built-in
Godot APIs.

```text
godot --path src
```

Or open `src/` in the Godot 4.7 editor and press Play. Window is a fixed 1280×720. macOS
(universal) and Web export presets are committed in `src/export_presets.cfg`.

## Assets & Attribution

The world, blocks, and player are code-generated meshes with hand-written GDScript shaders. The
only third-party asset is the UI font:

| Asset | Source | License |
| --- | --- | --- |
| `src/assets/fonts/RobotoSlab-{Regular,SemiBold,Bold}.ttf` | [Roboto Slab](https://fonts.google.com/specimen/Roboto+Slab) — Christian Robertson, via Google Fonts | Apache-2.0 |

Godot itself is MIT licensed.

## PR Index

| PR | Description | Branch |
| --- | --- | --- |
| #1 | Volumetric fog with runtime toggle | `main` |
| #2 | Optimize chunk streaming (async data-ring, per-thread lake cache, separate meshing budgets) + fix fog albedo | `fix/streaming-opt-albedo` |
| #3 | Side-panel inventory (5×8 + hotbar + equipment), tabbed frosted UI, drag-drop, and interaction/performance hardening | `feat/side-panel-inventory` |
| #4 | Comprehensive headless test suite — inventory fuzz, world golden hash, HUD integration, streaming soak + composite Godot CI | `test/comprehensive-headless-suite` |
| #5 | Behavior-preserving codebase optimization — dense resource catalog, lower-allocation world/mesh/UI paths, lifecycle and save cleanup | `refactor/aggressive-codebase-optimization` |
