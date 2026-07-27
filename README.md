# Wildes

<!-- One-paragraph description of the game as a whole and its core loop. This is
     the game-level README — it describes the complete game that lives in src/.
     Each task under tasks/ has its own README describing that task specifically. -->

**Wildes** is a polished isometric 3D voxel sandbox built in **Godot 4.7**. The player
explores one continuous, session-local **200×200** world under an orthographic isometric
camera — mining terrain and building freely from six collectible block types (grass, dirt,
stone, sand, wood, leaves). The core loop is explore → mine → build: hold left-mouse to mine
the targeted block (per-block hold time + pulse feedback), right-mouse to place from a
nine-slot hotbar, with a 6-block reach, yellow reach outlines, and a ghost placement preview.
Successive tasks layer real-time lighting onto that base: baked ambient occlusion and soft cast
shadows, a continuous day/night cycle with a moving sun/moon, and placeable walk-through torches
that cast their own light and shadows on the **forward_plus** renderer.

This repo follows the ADO **GameDev track** task structure: one repo per game
(`gamedev-{game-name}`), a single shared gold source in `src/`, and one folder per task under
`tasks/`.

## Project Structure

```text
gamedev-wildes/
├── src/                  Gold game source — the single, shared, buildable Godot 4.7
│                         project (scripts, scenes, shaders, project.godot).
├── tasks/                One folder per task.
│   └── justinsoberano-scaffolding_game/
│       ├── instruction.md    The task prompt used to reproduce this task's feature.
│       ├── task.toml         Task metadata.
│       ├── screenshots/      Captured game states (avocado/ and claude/).
│       └── README.md         Task description + Avocado vs Claude comparison + trajectories.
└── README.md             This file — the game-level overview.
```

Notes:

- **`src/`** holds the complete, buildable gold game — tasks reference it, they do not copy it.
- **Videos** are not stored in the repo; they are uploaded to **PixelCloud** and referenced
  from each task's `task.toml` and README.

## Constraints

- **Engine** — Godot 4.7 (MIT license; permits commercial/internal use).
- **Model** — always use the latest model.
- **1P / 3P models** — the gold solution and in-game assets are 1P/hand-authored, not from 3P
  models. `README.md` and `task.toml` may reference 3P; `instruction.md` does not.

## Engine & Framework

- **Engine / framework:** Godot 4.7 (GDScript)
- **License:** MIT

## Dependencies

None beyond the Godot engine. The game uses only built-in Godot APIs.

| Library | Version | Source | License |
| --- | --- | --- | --- |
| None | — | — | — |

## Assets & Attribution

All assets are original primitives — the world, blocks, and the explorer are built from
code-generated cube/box meshes and hand-written GDScript shaders (`src/shaders/`). No
third-party or Meta-internal art, audio, fonts, or models are shipped.

No third-party tokens, proprietary code, or IP appear in the code, assets, or the
model-visible environment.

## Building & Running

**Prerequisites:** Godot **4.7** (stable). No other SDKs required.

```text
# From the repo root — the project lives in src/ (src/project.godot):
godot --path src

# Or open the src/ folder in the Godot 4.7 editor and press Play.
```

## Core Features

- Seeded, session-local 200×200 voxel world: open-meadow spawn near trees and exposed stone,
  grading into sandy lowlands, wooded rises, and stone ridges.
- Crisp cubes with readable face shading and world-edge haze.
- Orthographic isometric camera: camera-relative WASD, space to hop, Q/E 45° turns, scroll
  zoom, smooth follow.
- Mining & building: 6-block reach, per-block mining hold times, reach outline, ghost preview,
  and a nine-slot hotbar (keys 1–9) with counts.
- Real-time lighting: baked per-vertex ambient occlusion and soft cast shadows on terrain,
  trees, the explorer, and placed blocks.
- A repeating ~20-minute day/night cycle (10 min day / 10 min night) with a moving sun and moon,
  real-time directional shadows, and a cool, playable night.
- Placeable, walk-through **torches** that light a 9-block radius and cast soft shadows, on the
  **forward_plus** renderer with saturation/contrast color-grading.

## Gold Version

- See each task's `task.toml` for the exact `avocado-model` and `harness` used to build the
  gold solution.

## Tasks

| Task | Description | Completed |
| --- | --- | --- |
| [justinsoberano-scaffolding_game](./tasks/justinsoberano-scaffolding_game/) | Scaffold the Wildes isometric voxel sandbox (world gen, camera, player, mining/placing, hotbar) | 2026-07-21 |
| [justinsoberano-ao_and_shadows](./tasks/justinsoberano-ao_and_shadows/) | Add real-time ambient occlusion + soft cast shadows (baked voxel AO, sun shadows) in the Compatibility renderer | 2026-07-22 |
| [justinsoberano-day_night_cycle](./tasks/justinsoberano-day_night_cycle/) | Add a repeating ~20-min day/night cycle (10 min day / 10 min night) with a moving sun/moon and real-time directional shadows on the player and blocks; nights stay playable | 2026-07-27 |
| [justinsoberano-torches_and_casted_shadows](./tasks/justinsoberano-torches_and_casted_shadows/) | Switch the renderer to forward_plus with color-grade compensation and add walk-through torch light-blocks that light a 9-block radius and cast soft shadows | 2026-07-27 |
