# Chunk Streaming - Seamless Async

Chunk streaming prevents the game from keeping all 200x200 world chunks (10x10=100) in memory at once.
Previously loading a new chunk stalled the game because `ChunkMesher.build_mesh` did ~14k block checks + AO shadow scans (up to 54 checks per top face) on main thread. Now it's seamless via background threads.

## What is a chunk right now?

Not 16x16. Current:
- `chunk_size = 20` (from `world_config.tres`)
- `world_size = 200` => 10x10 grid
- `max_build_y = 36` (max_height 20 + build_extra 8 +8)
- So chunk = **20x20x36 vertical column** (full height). `ChunkMesher` cache is `(20+2) x 36 x (20+2) = 17424` cells.

To change to Minecraft-like 16x16, set `chunk_size=16` and `world_size=192` (must be multiple).

## How it works - seamless

- `ChunkCoord` - static helpers
- `WorldChunk` - state
- `ChunkManager` - continuous: prunes opposite queues, cancels unloads that become desired again, sorts loads nearest-first, unloads farthest-first, forces update on chunk boundary change regardless of interval.
- `ChunkMesher` split:
  - `build_cache(origin, lookup)` quick snapshot on main thread (now optimized via `VoxelWorld.build_cache_for_chunk` fast path, no Callable overhead, ~4ms per chunk)
  - `build_mesh_data_from_cache(cache)` heavy AO/shadow, runs in background `Thread`
  - `create_mesh_from_data(data)` creates `ArrayMesh` on main thread
- `ChunkRenderSystem`:
  - `rebuild_async(cx,cz)` snapshots cache (fast) then starts `Thread` with `_thread_build_mesh`
  - `_thread_build_mesh` runs heavy geometry off main thread, stores result in mutex-protected `_thread_results`
  - `poll_async(max)` called every `_process` applies up to 4 completed meshes (no stall)
  - `rebuild_immediate` kept for edits (1 per frame) and initial loading screen

Flow:
1. `ensure_chunks_around(pos)` loads (2*r+1)^2 synchronously during loading screen.
2. Each frame `WorldController._process`:
   - `chunk_manager.tick(delta, player_pos)` → `update()` recompute if moved chunk, queue loads/unloads, `process_queues()` queues async builds (2 per frame, ~8ms snapshot)
   - `chunk_renderer.poll_async(4)` applies finished threads
   - `flush_dirty(1)` handles edits
3. Edits stay in `VoxelWorld` global dicts, survive unload/reload.

Why no stall now:
- Before: `rebuild_immediate` built cache + mesh same frame → 10-20ms mesh + 4ms cache per chunk ×4 = 40-80ms hitch.
- After: main thread only does cache snapshot (4ms) via optimized `build_cache_for_chunk` avoiding per-cell `Vector3i` allocation overhead as much as possible, mesh generated in `Thread`. Avg tick 3.9ms measured in `test_chunk_async_seamless.gd`.

## Config

- `chunk_streaming_enabled=true`
- `render_distance=4` → 81 at center
- `unload_padding=2` → keep 13x13
- `max_chunk_loads_per_frame=2` → 2*4ms=8ms main thread max, seamless
- `max_chunk_unloads_per_frame=4` (free is cheap)
- `chunk_update_interval=0.1`

Set `chunk_streaming_enabled=false` to restore old `generate_all_chunks`.

## Testing

```
Godot --headless --path src --script res://tests/test_chunk_streaming.gd
Godot --headless --path src --script res://tests/test_chunk_continuous.gd
Godot --headless --path src --script res://tests/test_chunk_async_seamless.gd
```

`test_chunk_async_seamless` asserts avg tick <12ms for 2 loads, proving seamless.

`test_full_flow` still passes with 81 streaming chunks.

