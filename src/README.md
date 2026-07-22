# Wildes - 200x200 Block World (Godot 4 Compatibility) + Blocky Explorer + AO & Shadows

1280x720, Compatibility (GL) renderer, 3D orthographic isometric camera with crisp cube shading, voxel AO, and real-time shadows.

## New: Blocky Explorer
- **Camera-relative WASD**: forward/right derived from isometric camera flat basis; moves with step-up (1.05 blocks) to climb rolling hills
- **Space hop**: jump_velocity 9, gravity 22, on_ground detection via voxel check
- **Smooth Q/E quarter turns**: camera rig lerps yaw by 90° increments (yaw_lerp_speed 6), wheel zoom 10..110 ortho size
- **Cursor select**: raycast (Amanatides & Woo) from ortho camera through mouse, reach 7.5 blocks
  - `target_block` = first solid within reach
  - `placement_block` = adjacent empty cell (last ray step)
  - Rejects placement that collides with player AABB
- **Hold Left to mine**: 0.35s hold commits exactly 1 matching block
- **Right click to place**: consumes exactly 1 from selected hotbar slot, cooldown 0.18s
- **Collectible**: GRASS, DIRT, SAND, STONE, Wood (LOG), Leaves – layered terrain:
  - GRASS top = GRASS, next 2 = DIRT, deeper = STONE
  - SAND all SAND, STONE all STONE
  - Trees LOG+LEAVES
  - Mining deeper under meadows yields DIRT then STONE
- **9-slot hotbar** bottom center (CanvasLayer), color-coded, count, selected highlight (yellow border). Keys 1..9 to select. `HotbarUI` refresh group call.
- **Selection visuals**: white translucent wire box on target (darkens as mine progresses), ghost translucent block at placement with selected material color (top_level MeshInstance)

## New: Ambient Occlusion & Real-time Shadows (v2 - AO only, no black sides)
- **Voxel AO (subtle, not black)**: per-vertex AO baked into vertex colors, sides stay bright
  - Samples 3 neighbors (side1, side2, diagonal) at `pos+N+U*du`, `N+V*dv`, `N+U*du+V*dv`
  - If side1 && side2 -> occlusion=3 else sum
  - Brightness **1.0 / 0.84 / 0.66 / 0.48** - corners visible but not black (tunable `enable_ao`)
  - All 6 faces, cache fallback for chunk borders
  - Shader `crisp_shade mix(0.88,1.0,top)` keeps side faces bright, AO provides crevice darkening only
- **Real-time Drop Shadows under floating blocks**:
  - For each exposed top face, scans upward `y+2 .. y+7` (max 6 air gap) via `is_solid_world()`
  - If solid found above (floating block / overhang), darkens ground below:
    - 1 gap (directly above): 0.60 factor, 2 gaps 0.67, up to 6 gaps 0.92
  - Recomputed on every chunk rebuild -> **real-time, not static** (placing/removing a floating block instantly updates shadow below)
  - Meets requirement: "block with space below it should add shadow below it, real time"
  - No static heightmap sun shadows anymore - removed `sun_shadow_map` usage to avoid black sides
- **Real-time Directional Shadows**:
  - Sun `shadow_enabled=true`, PSSM4 splits 0.1/0.2/0.5, bias 0.04, normal bias 0.8, blur 1.0, max distance 220
  - Chunks `cast_shadow=ON`, terrain shader lit `diffuse_lambert` so they receive shadows (floating blocks cast onto ground)
  - Player model explicitly `cast_shadow=ON`, plus contact blob shadow plane (fades with jump) for soft AO under feet
  - Environment ambient raised to **1.18**, sky 0.50, sun contrib 0.65 so shadowed sides are not black, AO remains visible
- **Fixes**: water shader compatibility (removed `depth_draw_alpha_prepass`), shadow atlas 2048

## World Editing
- `world_generator.gd` now editable voxel API + AO/shadows:
  - `placed_blocks: Dictionary Vector3i->BlockType`
  - `removed_blocks: Dictionary set`
  - `get_block_at(Vector3i)`, `is_solid`, `try_mine_block`, `try_place_block`
  - Full voxel mesh rebuild per chunk (generic, not heightmap-only) using local cache (cs+2 x max_build_y x cs+2) for speed
  - Chunk rebuild on edit affects neighbor chunks if on border, recomputes AO on the fly (sun shadow map stays static for large terrain, real shadow map handles dynamic)
  - `max_build_y = max_height + build_extra +8 = 44` allows upward building
  - Spawn finder: flat GRASS near center
  - Exports: `enable_ao`, `ao_darkness`, `enable_shadows`, `shadow_cast_distance`
  - Sun shadow map `_generate_sun_shadow_map()` + per-vertex AO in `_build_chunk_mesh_generic`
- Still grouped chunks: 100 chunks, one ArrayMesh each, shared ShaderMaterial with AO + shadow-friendly lit shading

## Project Layout
```
project.godot (Compatibility, input map: move_left/right/forward/back, jump, rotate_left/right, mine, place, zoom)
main.tscn
  World (world_generator.gd)
  Player (player_explorer.gd) group player
  CameraRig group camera_rig (camera_rig.gd) follows player, smooth yaw
  HotbarUI CanvasLayer group hotbar_ui (hotbar_ui.gd)
shaders/
  terrain.gdshader
  water.gdshader
scripts/
  world_generator.gd
  player_explorer.gd
  camera_rig.gd
  hotbar_ui.gd
  main.gd
```

## Controls
- WASD / Arrows: move explorer (camera-relative)
- Space: hop
- Q/E: smooth 90° quarter turn
- Wheel: zoom
- Mouse cursor: selects reachable block or adjacent placement cell
- Left Hold: mine (exactly 1 per commit)
- Right Click: place from hotbar (exactly 1 per commit)
- 1-9: select hotbar

## Opening
Open `src/project.godot` in Godot 4.4+. Play. World is 200x200, 40k columns, still responsive via chunk mesh merging.
