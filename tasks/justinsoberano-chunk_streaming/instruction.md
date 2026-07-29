# Task 005 - Chunk Streaming

## Goal

Replace the fixed world limit with n infinite procedural worlds that loads in chunks around the player. Nearvy terrain should stay active while distant terrain unloads. All chunk data, blocks, terrain, trees, water must stay in sync as the player explores the world

## Requirements
### Procedural world generation
Generate terrain, biomes, and trees when they are needed instead of building the whole world at startup. GEneration must work at ANY location, including negative X and Y coordinates. The same seed must always create the same base terrain at the same position.

You need to store blocks by their world coordinate. The world must be able to create a chunk snapshot for mesh building and remove all terrain data and timers for chunks that are no longer needed/in range.

Remove the edge haze effect because the world will no longer have a fixed size. 

### Player centered streaming

Use the player's position to decide which chunks should be loaded in and unloaded. Load nearby chunks as the player moves and unload chunks that fall outside the active area. For now, define the active are as a 4 chunk radius, 81 total chunks loaded in total.

Following codebase convention, make the following settings variables that are easy to change:
1. Render distance
2. Unload padding
3. Streaming update interval
4. Maximum chunk loads and unloads per frame

Unload padding should stop chunks from loading and unloading over and over again when the player steps near a chunk border. The per frame limits should spread out the chunk streaming work and prevent frame drops. 

### Async chunk meshing 

Meshes should be built on background threads so that mesh generation does not cause any pausing or stuttering in the game. Mesh jobs should be canceled when their chunks are no longer needed. If a mesh job finished after its chunk has unloaded or changed, ignore it. 

Keep a cache of recently unloaded meshes and reuse cashed mesh when the player returns, as long as it is still a valid chunk.

### Blocks and water

All block types and water must load and unlaod with the chunk they belong to. When a chunk is unloaded, all blocks and water that are part of that chunk must be removed and loading that chunk back in must add back all the blocks and water. 

Water is implemented in a way where reaching a certain depth reveals water, because of this we should keep the water plane centered on the player so its edge cannot be seen. 

## Technical Requirements
- Godot 4.7
- Do not add external assets, keep existing ones. 
- Chunk streaming MUST be a background thread task
- Unloaded chunks should not tick


## Acceptance Criteria
- The game runs headlessly with no errors or warnigns
- The player is able to explore the world freely
- A fixed seed creates the same world terrain, biomes, and trees at the same location coordinates
- Cached chunks are reused