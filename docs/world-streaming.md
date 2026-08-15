# World Streaming

The chunk pipeline lives together under `src/world/chunks` and separates coordination, background work, and scene ownership.

- `ChunkManager` owns desired, retained, visible, dirty, and pending chunk state.
- `ChunkBuildScheduler` snapshots chunk-local edits and retained generated blocks, runs terrain and mesh jobs on worker threads, and exposes completed typed results.
- `ChunkMesher` converts voxel snapshots into mesh data and creates meshes on the main thread.
- `ChunkRenderer` owns chunk scene nodes, mesh pooling, and the mesh cache.
- `ChunkCoord`, `ChunkBuildJob`, and `ChunkBuildResult` provide shared coordinate and transfer types.

Startup uses the same pipeline as runtime. `WorldController` asks `ChunkManager` for an initial load, applies each result, then starts normal processing. Runtime processing recomputes desired chunks after player movement, schedules bounded work, applies completed results on the main thread, unloads distant nodes, and rebuilds visible chunks after edits.

A chunk enters `visible_chunks` only after its mesh is restored or applied. Torch visuals subscribe to chunk-ready and chunk-unloaded signals, so special-block nodes follow the same readiness boundary.

Worker threads only produce data. Godot scene nodes, `ArrayMesh` assignment, pooling, and signal-driven visual updates remain on the main thread. Shutdown stops and joins workers before clearing renderer-owned nodes.

Entering a finite dungeon suspends `WorldController`, `ChunkManager`, and `ChunkBuildScheduler`.
Loaded chunk nodes and caches remain owned by the world, queued jobs stop being dequeued, and at
most the two already-running builds may finish without being applied. Resume releases those
workers and continues streaming around the unchanged overworld player anchor.

`VoxelWorld` indexes placed blocks, removed blocks, generated tree blocks, and seeded copper deposits
by chunk. A full chunk build derives copper from the world seed and chunk origin after base terrain
exists; terrain-only preloads do not generate it. Deposits and empty-chunk markers stay in memory
across mesh rebuilds, then leave with evicted terrain and regenerate from the same seed when the chunk
returns. Saves persist mined copper as normal removed-block edits rather than storing generated
deposits. Each build job snapshots only the requested chunk plus the mesher's two-block border, so
distant accumulated edits do not turn every rebuild into a full-world scan.

The streaming soak test instantiates the real gameplay scene, moves the real player, edits the real voxel model, and checks visible/data/terrain bounds, pending work, orphan nodes, and drag-preview leaks.

Transient entities use the same readiness boundary through `WorldController.is_position_streamed`.
`WorldEntityCoordinator` rejects ambient spawn candidates outside streamed regions and removes
active actors as soon as their position is no longer streamed or exceeds the despawn radius.
`EntityRuntime` owns those actors, their stats, spatial entries, and retirement; removal clears all
gameplay indexes together. The entity streaming soak
moves across regions while alternating day and night, and asserts population, pathfinding, index,
and cleanup bounds independently of the chunk renderer soak. Retired actors leave all gameplay
indexes and population counts immediately. Their fading presentations use a separate fixed bound.

Finite dungeons do not reuse ambient spawning or streaming rules. Each `LevelRuntime` owns a
dedicated 64-actor `EntityRuntime` over `LevelState`; room encounters feed it validated atomic
batches and bounded navigation work. Entering a dungeon suspends the overworld coordinator without
destroying its runtime. Leaving restores and resumes the same overworld instance before queuing the
dungeon runtime for deletion; death suspends it immediately and follows that restore-then-retire
order during the return flow.
