# Wildes - 200x200 Block World (Godot 4 Compatibility) + Blocky Explorer

1280x720, Compatibility (GL) renderer, 3D orthographic isometric camera with crisp cube shading.

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

## World Editing
- `world_generator.gd` now editable voxel API:
  - `placed_blocks: Dictionary Vector3i->BlockType`
  - `removed_blocks: Dictionary set`
  - `get_block_at(Vector3i)`, `is_solid`, `try_mine_block`, `try_place_block`
  - Full voxel mesh rebuild per chunk (generic, not heightmap-only) using local cache (cs+2 x max_build_y x cs+2) for speed
  - Chunk rebuild on edit affects neighbor chunks if on border
  - `max_build_y = max_height + build_extra +8 = 44` allows upward building
  - Spawn finder: flat GRASS near center
- Still grouped chunks: 100 chunks, one ArrayMesh each, shared ShaderMaterial with top/side shading (0.62 side)

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
