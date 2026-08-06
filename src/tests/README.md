# Tests

Seven test families: inventory property fuzz + world determinism golden hash + HUD integration + player animation integration + animation tuning integration + tool system integration + world streaming soak.

## Inventory Fuzz — `src/inventory/inventory_model.gd`

`InventoryModel` is `RefCounted` with no scene dependencies so the fuzzer can run
~100k random operation sequences per second and assert invariants rather than
outcomes.

## Invariants

- **Conservation** — total count per item `StringName` is conserved across any
  `handle_drop` sequence (and per-operation).
- **No exceeds max stack** — no occupied slot exceeds its `ItemDefinition.max_stack`.
- **No zero/negative slots** — every non-null slot has `count > 0` and a
  `{item_id, count}` shape.
- **Every occupied index passes `can_slot_accept_item_id`**.
- **`can_handle_drop` exactly predicts `handle_drop`** — `can_handle_drop`
  equals `handle_drop` return, `mutated == can_handle_drop`, and `handle_drop`
  is identity (no mutation) iff `can_handle_drop` is false.
- `can_add_batch` / `add_batch` parity is also checked.

## Running locally

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path src --headless --script res://tests/inventory_fuzz_runner.gd -- --seqs=50000 --ops=20
# or smaller smoke:
godot --headless --path src --script res://tests/inventory_fuzz_runner.gd -- --seqs=5000 --ops=20
```

The runner is `src/tests/inventory_fuzz_runner.gd`. It is a `SceneTree` script
so it runs headless without a scene.

## World Golden Hash — determinism for seed 1337

`src/tests/world_golden_hash.gd` hashes block IDs (`VoxelWorld.get_block_id_at`) over a fixed region `x[-32,32) z[-32,32) y[0,128)` for seed `1337` with the jittered `WorldConfig` (base_height/meadow_radius/tree_density + noise frequencies). The SHA256 is committed in `src/tests/golden_world_hash.json`. Any noise tweak, spline change, or biome edit that silently reshapes existing players' worlds fails immediately — cheap, and otherwise invisible until someone loads an old save.

```sh
godot --path src --headless --script res://tests/world_golden_hash.gd
# to regenerate after an intentional worldgen change:
godot --path src --headless --script res://tests/world_golden_hash.gd -- --update
```

The runner loads `WorldConfig` from `res://world/settings/world_config.tres`, calls `runtime_copy_for_seed(1337)`, builds a `TerrainGenerator` + `VoxelWorld`, and hashes 524,288 blocks via `HashingContext.HASH_SHA256`.

## HUD Headless Integration

`src/tests/hud_integration.gd` instantiates `res://ui/hud/hud.tscn`, calls `setup_with_camera(inv, null)`, lets 120 frames pass, drives **real** `push_input` drags and asserts model + node state:

- `Performance.get_monitor(OBJECT_ORPHAN_NODE_COUNT) == 0`
- **mid-drag positive**: `*DragPreview*` `CanvasLayer` count == 1 while dragging (visible before release), **negative**: == 0 after release — one preview appears while dragging, zero survive afterward (mutation G goes red if preview creation is removed)
- no `*DragPreview*` remains after each drop (would have caught the leaked `InventoryDragPreview`/`HotbarDragPreview`)
- `inventory_model` totals conserved, no stack exceeds its item definition, no zero/negative counts, every occupied slot `can_slot_accept_item_id`, and slot/drag `TextureRect` icons match the item catalog
- two drags: left-drag `hotbar[0] (grass 12)` → `backpack[0]` (full move) and right-drag `hotbar[6] (torch 16)` → `backpack[1]` (half-split 8/8 via `force_drag`), both via real `InputEventMouseButton`/`Motion` + `push_input(…, true)` with mid-drag check at `+3` frames and post-drop at `+10`
- fails on any `FAIL:`, `ERROR:` or `WARNING:` in stderr (leaked `CanvasItem` RID, `set_drag_preview` error, etc.)

```sh
godot --path src --headless --script res://tests/hud_integration.gd
```

The drag implementation lives in `src/inventory/ui/inventory_slot.gd` and is exercised through the packaged HUD scene.

## World Streaming Soak

`src/tests/soak_world_streaming.gd` runs the **real** `res://game/game.tscn` headless for a few simulated minutes (900 movement frames with a `60+20*sin` radius walk). Each frame moves `Player` on a slow orbit while the real world process ticks streaming, and every 22/33 frames mines/places via `VoxelWorld.try_mine_block`/`try_place_block`. Every 60 frames it asserts:

- `ChunkManager.data_chunks <= keep_area+40` (`keep=(render+unload)^2`), `visible_chunks <= visible_area+10`, `VoxelWorld.generated_terrain_chunks <= keep*3+260` — bounded, not unbounded growth
- rapid teleports cancel stale work, edit-then-unload cannot cache a stale mesh, and terrain eviction invalidates renderer cache entries
- a saved late-day clock value is applied before world loading, remains unchanged until gameplay starts, and the sunset profile interpolates linearly between lighting keys
- the terrain material owns the shared `Texture2DArray`, terrain UV/layer arrays match vertex counts, and each face has one constant in-range texture layer
- real hotbar key input selects items, then a selected grass item places a `BlockId.GRASS` and mining maps it back to the same item
- `Performance.OBJECT_ORPHAN_NODE_COUNT == 0`, no `*DragPreview*` stray `CanvasLayer`
- `ChunkBuildScheduler.pending_count() <= keep_area+20` (thread queue bounded to the retained chunk set)
- no `FAIL:`/`ERROR:`/`WARNING:` in stderr (catches leaked `RID`, `ObjectDB`, `TerrainGenerator` threading errors)

Final `SOAK PASS frames=… movement_frames=900 data_max=…` shows the runner completed all movement frames with bounded state; the total frame count also includes hardware-dependent world generation and streaming-race setup.

```sh
godot --path src --headless --script res://tests/soak_world_streaming.gd
```

Catches streaming/threading leaks that unit tests never see.

## Player Animation Integration

`player_animation_integration.gd` instantiates the real blocky player visual and manually advances its shared animation state through idle, walk, sprint, turn, jump, fall, land, target tracking, mining, placement, and melee attack. It checks the single procedural timing source, shaped cadence, detached one-piece limbs, marker-derived alternate leg proportions, a flat-bottomed stance path with rounded recovery, rigid-leg compression and extension, whole-arm counter-swing, body weight transfer and braking overshoot, cuboid squash and stretch, locomotion/action layering, the sword's two-arm left-to-right sweep, forward lean, braced stance, finite boundary values, head limits, jump anticipation, landing recovery, a generous crowd performance budget, and final orphan count.

The runner also advances 100 visual instances for 60 frames and verifies they share mesh/profile resources without changing their node count. The world soak holds real W+Shift input across live frames and verifies sprint speed and the active sprint animation.

```sh
godot --path src --headless --script res://tests/player_animation_integration.gd
```

## Animation Tuning Panel Integration

`animation_tuning_panel_integration.gd` instantiates the real player and animation tuning panel, edits a generated animation field and a rigid arm transform through the live controls, switches to sprint preview, exports the complete configuration as full-precision JSON, resets every value, and checks the final orphan count.

```sh
godot --path src --headless --script res://tests/animation_tuning_panel_integration.gd
```

## Tool System Integration

`tool_system_integration.gd` verifies action and catalog data, typed inventory persistence, stone tool gating, real primary-use input, copper-pickaxe and copper-sword held rendering, melee cooldown and animation routing, silhouette extrusion for both supplied tool textures, and node cleanup.

```sh
godot --path src --headless --script res://tests/tool_system_integration.gd
```

## CI

`.github/workflows/tests.yml` downloads Godot 4.7 Linux headless, imports `src/`, and runs seven:

- fuzzer with 20k sequences × 20 ops (≈400k drops) — prints throughput (`~1M ops/s` raw, `~16k ops/s` invariant-checked)
- golden hash — `GOLDEN PASS` / `GOLDEN FAIL` with expected vs actual
- HUD integration — `HUD_INTEGRATION PASS orphan=0 previews=0` and grep-fails on `ERROR`/`WARNING`/`FAIL`
- player animation integration — `PLAYER_ANIMATION PASS orphan=0` plus a 100-instance shared-resource smoke
- animation tuning integration — `ANIMATION_TUNING PASS orphan=0` with live controls, preview, reset, and JSON export
- tool system integration — `TOOL_SYSTEM PASS orphan=0` with mining, melee, typed-stack, input, held-scene, and extrusion coverage
- world soak — `SOAK PASS` and grep-fails on `ERROR`/`WARNING`/`FAIL` + bounded chunk/orphan checks

All fail the job on violation.
