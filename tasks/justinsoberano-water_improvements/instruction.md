# Task 006 - Lakes, Rivers, Water Realism, and Terrain Optimization

## Goal
Replace the infinite water plane with real WATER blocks that form natural lakes and rivers, make water look realistic (depth, refraction, normals, specular), and keep chunk streaming fast in infinite worlds.

## Requirements

### Water block
Add WATER as a new block type. Non-solid, non-opaque, translucent, replaceable. During generation water should only appear where carved terrain ends up below water_level and the column is part of a lake/river influence or lowland sand, so lakes and rivers are water-filled but the world is not globally flooded. Placed solid blocks should be able to replace water. Water is kept as a static block for now with no flowing logic - just occupies the voxel and renders as water.

### Lakes & Rivers generation
Extend TerrainGenerator with lake and river biomes:
- **Finite worlds**: pre-generate a number of lakes at random positions outside the meadow with spacing to avoid overlap, and a number of rivers as random walk polylines starting near world edges or interior, avoiding the meadow core and avoiding each other. Carve bowls and channels with smooth falloff.
- **Infinite worlds**: use a deterministic grid approach for lakes where each grid cell has a chance to contain a lake. Rivers should be formed via noise for winding channels. Lake lookups should be cached thread-safely and work for any world coordinate including negatives.
- Expose tuning in WorldConfig with enable flags, counts, size ranges, depth, grid size, chance per cell, blend factors, frequency, seed offsets, and minimum distance from meadow. Validate ranges. Trees and spawn positions should avoid lake/river areas.
- Height carving should lerp base terrain toward below water_level based on influence factors with smooth blending for gradual banks.

### Water rendering
- Water should be block-based, not a global PlaneMesh. Do not create a water plane mesh. Clean up dead state left from the old plane system - the `show_water` flag and `infinite_water_size` in WorldConfig and its `.tres`, any `show_water` getters in WorldController, and the `$Water` node in `world.tscn` should be removed since water is now block-based.
- ChunkMesher must build terrain mesh excluding water blocks and a separate translucent water mesh only for WATER blocks. Water top surface should be slightly inset and use world-space consistent UVs so the surface is continuous across chunks.
- Add a WaterProfile resource that is the single source of truth for all water shader values. It should be saved as a `.tres` and loaded by WorldController and applied to the water ShaderMaterial.
- Water material should be a ShaderMaterial from `water.gdshader` rewritten for PBR-style water with tint, scrolling normal maps that are continuous, large-scale wave tilt to spread specular, refraction using screen texture, depth reconstructed from depth texture, depth-based tint, fresnel alpha, and roughness/specular controls. It should receive sun direction, color and energy from the environment. The normal map should be a runtime generated seamless noise texture set up as a normal map.
- ChunkRenderSystem should keep separate terrain and water instances with proper material and no shadows on water, maintain mesh caches for both, use a bounded worker pool with job queue and cancellation, and build terrain data plus both meshes in a single background job to avoid double work.

### Streaming & performance
- Optimize streaming for the new more expensive terrain: separate visible vs cached concepts where visible is render_distance and cached is render_distance plus padding. Use data-only jobs for the outer ring.
- VoxelWorld should have per-chunk indexing for existing tree blocks to allow fast snapshots and bounded terrain cache with LRU eviction and signals for manager sync. Use thread-safe primitives where caches are accessed from threads.
- General optimization: early outs with squared distances, avoid unnecessary allocations in hot loops, reuse computed heights for tree placement, keep per-frame chunk loads low and use a time budget when polling async results.
- Generation should be protected by a mutex where the VM is not fully concurrent.

### Day/night integration
DayNightValues should push sky and sun colors and sun direction to water material so water specular and tint match time of day.

## Acceptance
- Lakes and rivers appear in finite and infinite worlds outside meadow and are deterministic per seed.
- Water is real blocks, transparent, with depth, refraction and specular and continuous surface across chunks.
- No floating single-block water layers above full water surfaces.
- Trees and spawns avoid water biomes.
- Infinite exploration remains smooth with bounded memory and cancellation working.
- Day/night tints water.
- Game runs headless with no errors or warnings.
