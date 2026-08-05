# Tests

Four test families: inventory property fuzz + world determinism golden hash + HUD integration + world streaming soak.

## Inventory Fuzz — `src/inventory/inventory_model.gd`

`InventoryModel` is `RefCounted` with no scene dependencies so the fuzzer can run
~100k random operation sequences per second and assert invariants rather than
outcomes.

## Invariants

- **Conservation** — total count per `BlockId.Type` is conserved across any
  `handle_drop` sequence (and per-operation).
- **No exceeds max stack** — no occupied slot has `count > max_stack` when
  `max_stack > 0` (unlimited when `<= 0`).
- **No zero/negative slots** — every non-null slot has `count > 0` and a
  `{type, count}` shape.
- **Every occupied index passes `can_slot_accept_type`** — and is never `AIR`/`null`.
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

The runner is `src/tests/inventory_fuzz_runner.gd` (mirrored to `tests/` for
discoverability). It is a `SceneTree` script so it runs headless without a
scene.

## World Golden Hash — determinism for seed 1337

`src/tests/world_golden_hash.gd` hashes block IDs (`VoxelWorld.get_block_id_at`) over a fixed region `x[-32,32) z[-32,32) y[0,128)` for seed `1337` with the jittered `WorldConfig` (base_height/meadow_radius/tree_density + noise frequencies). The SHA256 is committed in `src/tests/golden_world_hash.json` (`tests/golden_world_hash.json`). Any noise tweak, spline change, or biome edit that silently reshapes existing players' worlds fails immediately — cheap, and otherwise invisible until someone loads an old save.

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
- `inventory_model` totals conserved, no exceed max_stack, no zero/negative, every occupied slot `can_slot_accept_type`, hotbar `HotbarSlot` visuals match `slots[]` after each drop
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
- `Performance.OBJECT_ORPHAN_NODE_COUNT == 0`, no `*DragPreview*` stray `CanvasLayer`
- `ChunkBuildScheduler.pending_count() <= keep_area+20` (thread queue bounded to the retained chunk set)
- no `FAIL:`/`ERROR:`/`WARNING:` in stderr (catches leaked `RID`, `ObjectDB`, `TerrainGenerator` threading errors)

Final `SOAK PASS frames=1080 data_max=171 …` shows max observed bounded.

```sh
godot --path src --headless --script res://tests/soak_world_streaming.gd
```

Catches streaming/threading leaks that unit tests never see.

## CI

`.github/workflows/tests.yml` downloads Godot 4.7 Linux headless, imports `src/`, and runs four:

- fuzzer with 20k sequences × 20 ops (≈400k drops) — prints throughput (`~1M ops/s` raw, `~16k ops/s` invariant-checked)
- golden hash — `GOLDEN PASS` / `GOLDEN FAIL` with expected vs actual
- HUD integration — `HUD_INTEGRATION PASS orphan=0 previews=0` and grep-fails on `ERROR`/`WARNING`/`FAIL`
- world soak — `SOAK PASS` and grep-fails on `ERROR`/`WARNING`/`FAIL` + bounded chunk/orphan checks

All fail the job on violation.
