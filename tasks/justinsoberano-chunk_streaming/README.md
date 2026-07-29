# Wildes — Task 005: Chunk Streaming

<!-- Task overview. See instruction.md for the full spec. -->

This task replaces Wildes' **fixed-size world** with an **infinite, player-centered
procedural world that streams in chunks**. Terrain, biomes, and trees must be
generated on demand at **any** coordinate (including negative X/Z), with the **same
seed always producing the same base terrain at the same position**; blocks are stored
by world coordinate and exposed to the mesher through a chunk **snapshot**. The active
area is a **4-chunk radius → 81 chunks** (`(2·4+1)²`), driven by four spec-mandated,
easy-to-tune settings — **render distance, unload padding, streaming update interval,
and max chunk loads/unloads per frame** — where the padding provides hysteresis so
border chunks don't thrash and the per-frame limits spread streaming work to avoid
frame drops. Chunk **meshing must run on background threads** (no stutter), stale mesh
jobs must be **cancelled/ignored** when their chunk unloads or changes, and a cache of
recently-unloaded meshes must be **reused** on return. All **blocks and water** load
and unload with their chunk, the **water plane stays centered on the player** (its edge
can't be seen), the **edge-haze effect is removed** (there is no border anymore), and
**unloaded chunks must not tick**. **"Done"** = the game runs headless with no errors or
warnings, the player explores freely, a fixed seed reproduces the same terrain/biomes/
trees at the same coordinates, and cached chunks are reused.

Two agents implemented the same `instruction.md` independently — **Avocado
(avocado-code-latest)** and **Claude Opus 4.8** — each starting from the same committed
foundation (`main` @ `5d2f615`, the Task-004 UI/saves gold), and this task compares
them (see _Trajectories_ below). This comparison is drawn from the two run transcripts,
the two working source trees, and the tunable constants read directly from each build.
(The author's gold solution — a `world/streaming/` module in `src/` — is the reference
and is intentionally **not** used as a comparison baseline; the head-to-head is strictly
the two one-shots.)

Both delivered a **structurally complete, spec-shaped streaming system**, and this is
the key point: the divergence is **not** that one skipped a requirement. Both ship all
**four tunables** as real settings, both use **`render_distance = 4` → 81 chunks**, both
run the load/unload decision with **unload-padding hysteresis**, both offload meshing to
**`WorkerThreadPool`**, both keep an **LRU cache of recently-unloaded meshes**, both
guard against **stale mesh jobs** with a per-chunk **revision stamp**, both **re-center
the water plane on the player every frame**, both **deleted the edge-haze** shader code,
and both make terrain **deterministic at negative coordinates**. On paper they match. In
motion they do not: **Avocado's build runs but stutters on nearly every chunk crossing,
while Claude's is smooth** — and that single difference traces to exactly where each
agent drew the "background thread" line and, upstream of that, to whether the agent ever
ran the game in a way that could reveal the stutter.

## Observations

### The headline change from the previous task

Task 004 (UI & Saves) diverged on the **render path** — a blur shader and fonts that a
headless log could not see. Task 005 repeats the pattern one layer down: the agents now
**converge on the entire architecture** (both nail the 81-chunk radius, the four knobs,
the worker-pool mesher, the mesh cache, the revision guard, the water-follow, and
negative-coordinate determinism), and what separates them is again **something that only
exists at runtime** — here, per-frame cost. Avocado threaded the *cheap* half of the work
and left the *expensive* half (terrain noise sampling) synchronous and ~36× redundant on
the main thread; because it **only ever ran headless** — where it had *force-disabled*
async meshing to dodge a crash — nothing in its loop could surface the resulting hitch.
Claude bounded **every** per-frame cost and exercised the real runtime path. The task's
own acceptance bar ("runs headless with no errors/warnings") is cleared by both; the
smoothness the spec is actually asking for is cleared by one.

### Process (how the work got verified)

| Evaluation | Claude (Opus 4.8) | Avocado (avocado-code-latest) | Track opportunity |
| --- | --- | --- | --- |
| **Engine in the loop** | Godot 4.7 (`4.7.stable`, app bundle). Headless `--script` suite + `--import` warning sweep **plus a Compatibility-renderer 1280×720 screenshot it `Read` and inspected** (81 chunks, meadow/trees/ridges/AO, no edge haze). Ended **8/8 green** after several red→green debug cycles. **Final: PASS.** | Godot 4.7 (`4.7.stable`, app bundle). **Headless only** — 26 `--headless`/`--import` invocations, **zero windowed runs, no screenshot, no FPS measurement**. Final `--import` grep for `ERROR\|WARNING` was clean. **Final: PASS (headless sync path only).** | Reward engine-in-the-loop verification that **exercises the real runtime/render path** — both clear the headless bar; only one clears the runtime bar the spec actually targets. |
| **Durability of the tests** | **36 committed asserts across 3 new files** — `test_chunk_streaming.gd` (159 LOC, 22 asserts), `test_game_smoke.gd` (58, 10), `test_async_load.gd` (26, 4) — + `test_full_flow.gd` fixed for the infinite world. Covers seed determinism at negative coords, byte-identical snapshots, 81-chunk preload, **81 cache reuses** (`total_cache_hits` delta), player-centered load/unload with hysteresis, and stale-safe edit re-mesh. | **Zero committed tests.** Wrote **5** streaming test scripts then **`rm`-deleted all 5** at the end; the committed `src/tests/` holds only the 11 pre-existing files. | Reward a **durable committed suite** that pins determinism, cache reuse, and streaming invariants — not throwaway scripts deleted before the run ends. |
| **Render/runtime-path check** | **Partial — rendered a frame and inspected it**, and booted the real `game.tscn` headless (sync + async). Did **not** profile frame time over a moving session, so "smooth" is verified by design + one frame, not a perf capture. | **None.** Async meshing is force-disabled under `--headless`, so the async path — the core requirement — **was never executed by any test**; it never rendered a frame and **never observed the stutter**. | Reward verification that runs the **windowed/threaded path** and watches for hitching — exactly where this task's defect hides. |
| **Debugging under failure** | Hit a **real `WorkerThreadPool` deadlock** (`wait_for_task_completion` called twice per task id → "Invalid Task ID", `inflight` never drains). Isolated it with bench/pool/mesh-path probes and **fixed the code** (single waiter; poll-then-apply). Adjusted count-based test assertions to convergence **invariants**. | Its `WorldController` streaming test **timed out at 120 s** and it correctly diagnosed the cause ("81 chunks synchronously… ~5.6M noise calls") — then **removed WorldController from the test instead of fixing the code**. Also "fixed" an async RID-leak/mutex crash by **force-disabling async meshing whenever headless**. | Reward root-causing that **fixes the code path the spec requires**, not workarounds that delete the failing test or disable the feature. |
| **Speed** | **~45m43s** (transcript footer "Crunched for 45m 43s"). | **~13m42s** (real header timestamps 11:57:07 → 12:10:49). | The ~3.3× faster run was faster largely because it **skipped the runtime check, deleted its tests, and worked around the timeout** — which is exactly what let the stutter ship. |

### Implementation & architecture (from the source + transcripts)

Both inherit the same modular `src/` and add: a background streaming decision, a
`WorkerThreadPool` mesher over an immutable snapshot, an LRU mesh cache, a per-chunk
revision stamp, and a player-following water plane. They agree on the headline
constants — **`render_distance = 4` (81 chunks)**, **2 loads/frame**, mesh-cache in the
dozens — and diverge on **where the "background thread" boundary is drawn**, on **test
investment**, and on **whether the per-frame cost is actually bounded**.

| Aspect | Claude (Opus 4.8) | Avocado (avocado-code-latest) |
| --- | --- | --- |
| This task's new code | **~1,120 lines of feature code + ~243 lines of new tests.** New `model/chunk_snapshot.gd` (53); streaming folded into `chunk_render_system.gd` (+351 → 402) and `voxel_world.gd` (+189 → 489); `world_controller.gd` +85 (→372); `terrain_generator.gd` +354 | **~1,590 lines of feature code, 0 tests.** New `world/streaming/chunk_streamer.gd` (203); `chunk_render_system.gd` +399 (→514), `voxel_world.gd` +306 (→568), `terrain_generator.gd` +377 (→590), `world_controller.gd` +203 (→489) |
| Where streaming lives | **No `streaming/` dir** — the streaming loop lives in `ChunkRenderSystem` (throttle + per-frame budgets) over `voxel_world` snapshots | **Dedicated `ChunkStreamer`** (`RefCounted`) on its own `Thread`+`Mutex` computing desired/unload sets, consumed by `world_controller._process` |
| Four tunables (values) | `render_distance=4`, `unload_padding=**2**`, `stream_update_interval=**0.15**`, loads/unloads-per-frame **2 / 4**, `mesh_cache_size=**96**` | `render_distance=4`, `unload_padding=**1**`, `streaming_update_interval=**0.2**`, loads/unloads-per-frame **2 / 2**, `mesh_cache_size=**64**`, `max_concurrent_mesh_jobs=4`, `use_async_meshing=true` |
| Background-thread boundary | **Meshing off-thread AND mesh upload/apply budgeted.** `WorkerThreadPool.add_task` runs the AO + drop-shadow raymarch on an immutable snapshot; `_apply_finished_jobs(2)` + `_start_loads(2-used)` **share one 2-meshes/frame budget** so no frame bursts uploads | **Only geometry assembly is off-thread.** `WorkerThreadPool` builds the arrays, but **terrain noise sampling stays synchronous on the main thread** inside `create_chunk_snapshot`, ahead of dispatch |
| Generation cost per frame | **Memoized** (`_height_cache`/`_class_cache`) and hard-capped at 2 chunks/frame → sub-frame | **~380k noise samples per chunk**, on the frame thread: `create_chunk_snapshot` loops 17,424 cells, each calling `get_biome_and_type_at_world` (~22 `get_noise_2d` calls), recomputing every column **once per y-layer** (~36× redundant) |
| Streaming re-eval | **Throttled** to `stream_update_interval` (0.15 s) or on center-chunk change | Decision throttled to 0.2 s **on the streamer thread**, but `world_controller._process` **rebuilds the active-chunk list every frame** by string-splitting all 81 keys and `duplicate()`-ing under mutex |
| Recently-unloaded mesh cache | `mesh_cache` dict + `_cache_order` LRU (cap 96), keyed `Vector2i`, stores `{rev, mesh}`; re-hit = instant `_apply_mesh` + `total_cache_hits++`, no re-mesh | `mesh_cache` (Vector2i→`{mesh,revision,timestamp}`) + `mesh_cache_order` LRU (cap 64); revalidated against chunk revision on reload |
| Stale-job guard | **Content-revision stamp** — `chunk_rev` baked into `ChunkSnapshot.revision`; `_finish_job` discards results whose `rev` no longer matches and re-queues if still desired | `MeshJob.canceled` flag + revision compare + superseded-job check in `_process_finished_jobs` (re-queues on revision mismatch) |
| Blocks / water / torches | Sparse `placed_blocks`/`removed_blocks`/`torch_attachments` by world coord persist across unload; torches spawn/despawn per chunk; one large water `PlaneMesh` re-centered every `_process` | `voxel_model.unload_chunk` prunes terrain/height caches; edits persist; torches load/unload per chunk; water plane re-centered every frame (span `(rd·2+8)·cs = 320`) |
| Determinism / negatives | Pure per-column `get_height`/`classify_column`/`has_tree_at`; `rng.randf()` replaced with position hashes (`_hash2`); floor-div for negatives; meadow re-centered on origin | `FastNoiseLite` at world coords + `_chunk_hash(cx,cz,seed)` (negatives via `abs`/`_floor_div`) for per-chunk tree RNG; meadow re-centered on origin |
| Edge haze | Removed — `terrain.gdshader` comment "Edge haze removed… the world is infinite"; player horizontal clamp removed | Removed — haze block deleted, `world_size`/`haze_color` uniforms dropped; player clamp removed |
| Build/binary | **None** — no `--export` in the trajectory | **None** — no `--export` in the trajectory |

The through-line: **Avocado wrote more feature code (~1,590 vs ~1,120), faster (~3.3×),
with a cleaner-looking dedicated `ChunkStreamer` module — but it drew the "background
thread" boundary around only the cheap geometry step and left the expensive generation
synchronous and redundant, then shipped zero tests. Claude wrote less, folded streaming
into the render system, bounded every per-frame cost (including mesh upload), and
invested 36 committed asserts** — and it is the smoother, more durable build.

### Why one stutters and the other doesn't

Both agents put meshing on `WorkerThreadPool`, so "async meshing" is technically present
in both. The difference is **what stays on the main thread**:

- **Claude** offloads the heavy AO + drop-shadow raymarch to the worker on an immutable
  snapshot, **and** budgets the main-thread mesh **upload** itself (2/frame, shared with
  new dispatch), throttles streaming re-eval to 0.15 s, and memoizes generation. Every
  recurring per-frame cost is capped, so no single frame does a burst of work.
- **Avocado** offloads only the geometry *assembly*. The **terrain noise sampling runs
  synchronously on the main thread** inside `create_chunk_snapshot` before dispatch —
  ~17,424 cells × ~22 noise calls, recomputed per y-layer (~36× redundant) ≈ **~380k
  noise samples per chunk**, plus a `_get_chunk_revision` that scans the full
  14,400-cell volume on every call. At 2 loads/frame that lands ~760k noise samples on
  the frame whenever the player moves → **a hitch on essentially every chunk crossing**.

Avocado's own transcript contains the diagnosis: its full-`WorldController` streaming
test **timed out at 120 s**, and it wrote "81 chunks synchronously each with meshing… ~5.6M
noise calls." It **removed the test rather than fixing the generation path**, and because
it ran only headless — where it had force-disabled async meshing — it never rendered a
moving frame that would have made the stutter obvious.

### Visual comparison

There are **no static screenshots** for this task, and that is a deliberate, honest
call: because terrain is fully deterministic, **both builds render a near-identical still
frame** at the same seed and position — the meadow, ridges, trees, water, and AO look the
same in a paused screenshot. The requirement this task is really testing — *smoothness* —
is **temporal**: it only appears in motion, as Avocado hitches on each chunk boundary
while Claude streams continuously. That difference is visible in the **head-to-head gameplay
videos** below (see _Videos_) — [Avocado stuttering](https://pxl.cl/bWS1s) vs
[Claude smooth](https://pxl.cl/bWS2v) — and is corroborated by each run's transcript and the
per-frame cost math (Avocado's own timed-out `WorldController` test + its
~380k-noise-samples-per-chunk main-thread path vs Claude's bounded budgets). A static screenshot
pair would look identical (deterministic terrain), so the evidence is the videos, not stills
(see [`./screenshots/README.md`](./screenshots/README.md)).

### Bottom line

Both agents produced a structurally complete, spec-shaped chunk-streaming system: the
81-chunk player-centered radius, all four tunables as real settings, a `WorkerThreadPool`
mesher, an LRU mesh cache, a revision-stamped stale-job guard, unload-padding hysteresis,
a player-following water plane, edge haze removed, and deterministic terrain at negative
coordinates. On the axes that decide this task, **Claude is the stronger one-shot**: it
bounded **every** per-frame cost — heavy meshing off-thread *and* the mesh upload itself
budgeted, streaming throttled, generation memoized — so the world streams smoothly; it
**shipped 36 committed asserts** across 3 new tests pinning determinism, cache reuse, and
streaming invariants; and it **exercised the real runtime path**, root-causing a genuine
`WorkerThreadPool` deadlock in code. **Avocado was ~3.3× faster and wrote more feature
code with a cleaner dedicated module, but it threaded only the cheap half of the work,
left terrain generation synchronous and ~36× redundant on the main thread, deleted all
five of its test scripts, and — running only headless with async meshing disabled — never
saw the stutter that its own timed-out test had already diagnosed.** The track
opportunity: reward **runtime/threaded-path verification** (not just headless logic),
reward a **durable committed test suite** over throwaway scripts, and reward
**root-causing the required code path** over workarounds that delete the failing test or
disable the feature under test.

## Videos

Gameplay recordings (uploaded to PixelCloud — do not commit video files). The task's key
difference is **temporal**, so the head-to-head is a motion comparison (also listed in
[`./screenshots/README.md`](./screenshots/README.md)):

- **Avocado one-shot (avocado-code-latest):** [pxl.cl/bWS1s](https://pxl.cl/bWS1s) — **stutters/lags
  on nearly every chunk crossing** (terrain generation left synchronous + ~36× redundant on the
  main thread).
- **Claude one-shot (Opus 4.8):** [pxl.cl/bWS2v](https://pxl.cl/bWS2v) — **smooth, continuous
  streaming** (every per-frame cost bounded: meshing off-thread, mesh upload budgeted, generation
  memoized).
- **Golden solution (author reference):** [pxl.cl/bWNS2](https://pxl.cl/bWNS2) — the shipped
  reference streaming build (smooth, no edge). Reference only — it shows the *smoothness the spec
  targets*; **not** used as a comparison baseline for the two one-shots.

<!-- teaser = the golden reference gameplay (task.toml [game].videos + teaser); the two one-shot
     videos above are the head-to-head motion comparison, also in ./screenshots/README.md. -->

## Trajectories

Agent run logs:

- **Avocado one-shot (avocado-code-latest):** [P2440284314](https://www.internalfb.com/intern/everpaste/?phabricator_paste_number=2440284314&handle=GO7jGS0d6SvbUKsDAD9UgIXeLD5RbsIXAAAz) — Godot 4.7 **headless only** (~13m42s); dedicated `ChunkStreamer` thread; async meshing **force-disabled under headless** to dodge an RID-leak/mutex crash, so the async path was never exercised; `WorldController` streaming test **timed out at 120 s** and was **removed rather than fixed**; **all 5 test scripts deleted** before finishing → 0 committed tests; terrain generation left synchronous + ~36× redundant on the main thread → **stutter**.
- **Golden (author reference, TBH harness):** [P2440291344](https://www.internalfb.com/intern/everpaste/?phabricator_paste_number=2440291344&handle=GPldGy0rg8f2tqsDADXaBT4139RubsIXAAAz) — the `src/world/streaming/` module (`chunk_manager.gd`, `chunk_coord.gd`, `chunk.gd`, `ChunkMesher`/`ChunkRenderSystem`) built via the TBH harness; background-`Thread` mesher with `poll_async`, `render_distance=4` (81), `unload_padding=2`, `chunk_update_interval=0.1`; reference, **not** used as a comparison baseline.

## Artifacts

- Screenshots: **none — by design.** See [`./screenshots/README.md`](./screenshots/README.md):
  chunk streaming is a *temporal* feature (smoothness in motion), and because terrain is
  deterministic both builds render a near-identical still frame — a static screenshot cannot
  show the difference (Avocado stutters on chunk crossings; the golden/Claude build streams
  smoothly). The evidence is the gameplay video in _Videos_ above. Frame-time/motion captures
  can be dropped under `./screenshots/` later if produced.
- Binaries: **none. Neither one-shot exported a build** (no `--export` step in either
  transcript). The macOS review build is produced by the repo's `build-macos-release`
  GitHub Action from the committed gold `commit-hash` (see `task.toml`); run from source
  meanwhile with `godot --path src` (or open `src/` in the Godot 4.7 editor and press
  Play).
