# Project Wildes agent rules

Project Wildes is a Godot 4.7 isometric voxel sandbox expected to grow into many interacting
systems. Keep features independently changeable without introducing shared mutable state.

## Architecture

1. `src/game/game.tscn` is the gameplay composition root. Wire dependencies explicitly through
   constructors, exported resources, or `setup()` calls.
2. No autoloads, singletons, service locators, global mutable registries, or hidden scene-tree
   lookups.
3. Dependencies flow in one direction: definitions and catalogs → domain models → coordinators →
   presentation. Composition roots connect the layers.
4. Each piece of mutable state has one owner. Other systems use its command and query APIs rather
   than mutating its collections, resources, or nodes.
5. Keep rules deterministic and independent of `Node` when they do not require rendering or frame
   callbacks. UI, animation, audio, and meshes present state; they do not own gameplay truth.
6. Avoid dependency cycles. Coordinate peer systems from `Game` or a focused feature coordinator,
   never a global event bus.
7. Cross-system operations must validate before committing so inventory, world, equipment,
   crafting, and combat state cannot partially diverge.

## Systems and content

1. A feature directory owns its definitions, domain state, runtime coordination, presentation, and
   focused tests.
2. Blocks, items, actions, biomes, and future content use canonical typed definitions and catalogs.
   Persist stable IDs, not scene paths or display names.
3. Adding content to an existing mechanic should require a resource and catalog entry, not branches
   scattered through the player, HUD, save manager, or world.
4. A new behavior family must add its definition, executor, validation, and real caller together.
5. Keep mappings in one authoritative place. Do not synchronize parallel block-to-item,
   item-to-action, or similar tables.
6. Prefer focused composition over broad inheritance. Extract shared behavior after a second real
   caller exists; do not create vague `Manager`, `Utils`, or `BaseSystem` abstractions.
7. Commands request changes, queries inspect state, and signals announce completed changes. Every
   signal must have a consumer.
8. Expose narrow semantic APIs such as `try_place_block()` instead of internal collections.

## Voxel world

1. `VoxelWorld` is authoritative for block state and edits. Renderers react to committed changes and
   never maintain competing gameplay state.
2. World generation remains deterministic for a seed and is configured through typed resources.
3. Chunk workers consume snapshots and return data. Scene nodes, meshes, signals, and visual changes
   stay on the main thread.
4. Streaming queues, caches, and indexes must remain bounded. Per-frame, per-block, and per-chunk
   paths use spatial indexes rather than full-world scans.

## Persistence and refactors

1. Save stable IDs and plain values. Rebuild resources, nodes, caches, indexes, and derived state
   after loading.
2. State owners expose snapshot and restore contracts; `SaveManager` owns file encoding and storage.
3. Persisted shape changes require explicit version handling. Never silently reinterpret old data.
4. Rename every call site and delete the old API in the same change. Do not keep aliases, forwarding
   methods, reexports, thin subclasses, or compatibility paths.
5. Do not add unused symbols, signals, parameters, speculative extension points, or defensive paths
   excluded by the type and architecture contracts.
6. If `can_x()` and `x()` encode the same rule, they must share one implementation.
7. Do not add comments. Make ownership, naming, types, and boundaries explain the code.
8. Before finishing, search every added symbol, remove dead code and temporary files, and confirm
   `git status` contains only intended changes.

## Definition of done

Once implementation is done and before pushing a PR, run `REVEIEW.md` ONLY ONCE to get feedback, do not run more than once. Fix any P0 blockers. 
