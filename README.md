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
| `Shift` + move | Sprint |
| `Space` | Hop — needed to get up any ledge |
| `Q` / `E` | Rotate the camera 45° |
| Mouse wheel / pinch | Zoom |
| Hold left-click | Use the selected item's primary action |
| Right-click | Place the selected block |
| `1`–`9` | Select hotbar slot |
| `P` | Toggle backpack |
| `F10` | Toggle player animation tuner |
| `Esc` | Pause |

Reach is 6 blocks. The block under the cursor is outlined, and a ghost block previews where a
placement would land; placements that would overlap you are rejected.

The animation tuner is a compact right-side debug-build panel. Its Movement, Animation, and
Parts tabs update the live player immediately, while preview modes let you hold idle, walk,
sprint, jump, or fall behavior. `Export Values to Project Root` writes the complete current
configuration to `player_animation_values.json` beside the `src/` directory.

## Features

**World.** Endless terrain generated from layered noise (hills, detail, biome, forest, ridges)
in 20×20 chunk columns, 36 blocks tall. You spawn in a grass meadow clearing; beyond it are
sandy lowlands, forests, and stone ridges. Lakes (16–42 blocks wide, 6 deep) and rivers carve
into the terrain and fill with water up to level 5.

**Streaming.** Chunks load in a radius of 4 around you (9×9 = 81 chunks) and unload two chunks
further out. Meshing runs on background threads so movement doesn't hitch; edits are stored
globally and survive unload/reload.

**Blocks.** Grass, dirt, sand, stone, wood, and leaves are minable and placeable. Stone requires
the starter copper pickaxe; other current blocks remain hand-minable. Torches are
a seventh placeable that you can walk through — each is an omni light with a 9-block radius.
Torch shadows are configurable for the nearest 0, 1, 2, or 4 lights and default to the nearest
one.

**Lighting.** Per-vertex ambient occlusion is baked into chunk meshes. A directional sun plus a
fill light drive real-time shadows, and a keyframed day/night profile interpolates sky, ambient,
sun color/energy, and shadow opacity across the cycle. Forward+ is the primary renderer. Runtime
fallback values keep GL Compatibility usable at reduced fidelity, without volumetric fog.

**Day/night.** A full 24-hour cycle runs every 20 real minutes, starting at 6:00. Day is
06:00–19:00; sunrise and sundown get their own warm color keys, and nights stay bright enough
to play.

**UI & saves.** A frosted-glass front-end: main menu, world select over three save slots,
create-world and hold-3-seconds-to-delete modals, a chunk-progress loading screen, and a pause
menu that freezes the game. The pause menu exposes persistent frame-rate, 3D resolution,
anti-aliasing, fog, sun-shadow, shadow-range, and torch-shadow settings. Saves live in
`user://saves/` and autosave every 30 seconds, plus shortly after any block edit.

## Project Structure

```text
src/                    Godot project. Entry scene: app/app.tscn
├── app/                Application shell and screen/session transitions
├── game/               Gameplay composition root and session persistence
├── world/              Coordinator plus chunks/, generation/, materials/, model/, settings/,
│                       and special_blocks/
├── blocks/             Block ids, definitions, catalog, and torch placement rules
├── player/             Motor, interaction, targeting, input, camera/, and visuals/
├── environment/        Packaged environment scene and day_night/ system
├── inventory/          Inventory model and inventory-owned ui/
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

The world, blocks, and player are code-generated meshes with hand-written GDScript shaders. The
only third-party asset is the UI font:

| Asset | Source | License |
| --- | --- | --- |
| `src/assets/fonts/RobotoSlab-{Regular,SemiBold,Bold}.ttf` | [Roboto Slab](https://fonts.google.com/specimen/Roboto+Slab) — Christian Robertson, via Google Fonts | Apache-2.0 |

Godot itself is MIT licensed.

## PR Index

| PR | Description | Branch |
| --- | --- | --- |
| [#1](https://github.com/codimango/gamedev-wildes/pull/1) | Optimize chunk streaming and fix volumetric fog albedo | `fix/streaming-opt-albedo` |
| [#2](https://github.com/codimango/gamedev-wildes/pull/2) | Add side-panel inventory, tabbed UI, drag-drop, and interaction hardening | `feat/side-panel-inventory` |
| [#3](https://github.com/codimango/gamedev-wildes/pull/3) | Add the comprehensive headless test suite and composite Godot CI | `test/comprehensive-headless-suite` |
| [#4](https://github.com/codimango/gamedev-wildes/pull/4) | Publish a GitHub Release for every `src` change on `main` | `release/src-releases-main` |
| [#5](https://github.com/codimango/gamedev-wildes/pull/5) | Optimize runtime systems and remove redundant code | `refactor/aggressive-codebase-optimization` |
| [#6](https://github.com/codimango/gamedev-wildes/pull/6) | Organize the project around Godot feature ownership | `refactor/godot-feature-structure` |
| [#7](https://github.com/codimango/gamedev-wildes/pull/7) | Add scalable texture and item catalogs | `feat/texture-array-item-catalog` |
| [#8](https://github.com/codimango/gamedev-wildes/pull/8) | Add expressive procedural player animation | `feat/expressive-player-animation` |
| [#9](https://github.com/codimango/gamedev-wildes/pull/9) | Add full-face voxel ambient occlusion and lighting polish | `feat/ao-lighting-polish` |
| [#10](https://github.com/codimango/gamedev-wildes/pull/10) | Land the AO lighting and player animation stack | `codex/land-pr8-pr9` |
| [#11](https://github.com/codimango/gamedev-wildes/pull/11) | Fix saved-time startup and linear day-night transitions | `codex/fix-linear-day-night` |
| [#12](https://github.com/codimango/gamedev-wildes/pull/12) | Add graphics settings and reduce thermal load | `codex/settings` |
| [#13](https://github.com/codimango/gamedev-wildes/pull/13) | Add an extensible tool system and copper pickaxe | `codex/tool-system` |
| [#14](https://github.com/codimango/gamedev-wildes/pull/14) | Add a configurable sword attack rig and preview | `codex/sword-animation-rig` |
| [#15](https://github.com/codimango/gamedev-wildes/pull/15) | Add copper sword combat | `codex/copper-sword` |
| [#16](https://github.com/codimango/gamedev-wildes/pull/16) | Harden tool data and save contracts | `codex/tool-system-hardening` |
| [#17](https://github.com/codimango/gamedev-wildes/pull/17) | Unify the melee attack presentation lifecycle | `codex/tool-attack-lifecycle` |
| [#18](https://github.com/codimango/gamedev-wildes/pull/18) | Fix release world initialization side effects | `codex/fix-release-initialization` |
| [#21](https://github.com/codimango/gamedev-wildes/pull/21) | Make Godot CI validation fail closed | `codex/strict-godot-validation` |
| [#22](https://github.com/codimango/gamedev-wildes/pull/22) | Add pull request quality scaffolding | `codex/pr-quality-scaffolding` |
| [#23](https://github.com/codimango/gamedev-wildes/pull/23) | Widen world golden block ID encoding | `codex/widen-world-golden-hash` |
