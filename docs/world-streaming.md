# World Streaming

The chunk pipeline lives together under `src/world/chunks` and separates coordination, background work, and scene ownership.

- `ChunkManager` owns desired, retained, visible, dirty, and pending chunk state.
- `ChunkBuildScheduler` snapshots chunk-local edits and tree blocks, runs terrain and mesh jobs on worker threads, and exposes completed typed results.
- `ChunkMesher` converts voxel snapshots into mesh data and creates meshes on the main thread.
- `ChunkRenderer` owns chunk scene nodes, mesh pooling, and the mesh cache.
- `ChunkCoord`, `ChunkBuildJob`, and `ChunkBuildResult` provide shared coordinate and transfer types.

Startup uses the same pipeline as runtime. `WorldController` asks `ChunkManager` for an initial load, applies each result, then starts normal processing. Runtime processing recomputes desired chunks after player movement, schedules bounded work, applies completed results on the main thread, unloads distant nodes, and rebuilds visible chunks after edits.

A chunk enters `visible_chunks` only after its mesh is restored or applied. Torch visuals subscribe to chunk-ready and chunk-unloaded signals, so special-block nodes follow the same readiness boundary.

Worker threads only produce data. Godot scene nodes, `ArrayMesh` assignment, pooling, and signal-driven visual updates remain on the main thread. Shutdown stops and joins workers before clearing renderer-owned nodes.

`VoxelWorld` indexes placed blocks, removed blocks, and generated tree blocks by chunk. Each build
job snapshots only the requested chunk plus the mesher's two-block border, so distant accumulated
edits do not turn every rebuild into a full-world scan.

The streaming soak test instantiates the real gameplay scene, moves the real player, edits the real voxel model, and checks visible/data/terrain bounds, pending work, orphan nodes, and drag-preview leaks.
