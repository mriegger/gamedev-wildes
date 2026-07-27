extends RefCounted
class_name VoxelWorld

## VoxelWorld - owns voxel state, canonical AIR=0, no ChunkData duplication
## Height cache owned here and invalidated on edits, no second cache in controller/motor

signal block_edit_committed(edit: BlockEdit)

var world_size: int = 200
var chunk_size: int = 20
var max_build_y: int = 36
var water_level: int = 5

var height_map: Array = []
var type_map: Array = []

var tree_blocks: Array = []
var tree_block_fast: Dictionary = {}

var placed_blocks: Dictionary = {}
var removed_blocks: Dictionary = {}
var cell_revisions: Dictionary = {}
var _highest_cache: Dictionary = {}
var torch_attachments: Dictionary = {}


func _init(p_world_size: int = 200, p_chunk_size: int = 20, p_max_build_y: int = 36):
	world_size = p_world_size
	chunk_size = p_chunk_size
	max_build_y = p_max_build_y


func setup(p_world_size: int, p_chunk_size: int, p_max_y: int, p_height_map: Array, p_type_map: Array, p_tree_fast: Dictionary, p_tree_blocks: Array = []):
	world_size = p_world_size
	chunk_size = p_chunk_size
	max_build_y = p_max_y
	height_map = p_height_map
	type_map = p_type_map
	tree_block_fast = p_tree_fast
	tree_blocks = p_tree_blocks
	_highest_cache.clear()
	cell_revisions.clear()
	placed_blocks.clear()
	removed_blocks.clear()
	torch_attachments.clear()

func _base_terrain_type_at(x: int, y: int, z: int):
	if x < 0 or x >= world_size or z < 0 or z >= world_size:
		return null
	if height_map.is_empty() or type_map.is_empty():
		return null
	var h = height_map[x][z]
	if y > h or y < 0:
		return null
	var top_t = type_map[x][z]
	if top_t == BlockId.Type.SAND:
		return BlockId.Type.SAND
	if top_t == BlockId.Type.STONE:
		return BlockId.Type.STONE
	if top_t == BlockId.Type.GRASS:
		if y == h:
			return BlockId.Type.GRASS
		elif y >= h - 2:
			return BlockId.Type.DIRT
		else:
			return BlockId.Type.STONE
	if top_t == BlockId.Type.DIRT:
		return BlockId.Type.DIRT
	return top_t

func get_block_at(p: Vector3i):
	if p.y < 0:
		return BlockId.Type.STONE
	if p.x < 0 or p.x >= world_size or p.z < 0 or p.z >= world_size or p.y >= max_build_y:
		return null
	if placed_blocks.has(p):
		return placed_blocks[p]
	if removed_blocks.has(p):
		return null
	if tree_block_fast.has(p):
		return tree_block_fast[p]
	return _base_terrain_type_at(p.x, p.y, p.z)

func get_block_id_at(p: Vector3i) -> int:
	var raw = get_block_at(p)
	if raw == null:
		return BlockId.Type.AIR
	if BlockId.is_valid(raw):
		return raw
	return BlockId.Type.AIR

func is_solid(p: Vector3i) -> bool:
	var bt = get_block_at(p)
	if bt == null:
		return false
	return BlockCatalog.shared().is_solid(bt)

func is_occupied(p: Vector3i) -> bool:
	var bt = get_block_at(p)
	if bt == null:
		return false
	return BlockCatalog.shared().is_occupied(bt)

func is_opaque(p: Vector3i) -> bool:
	var bt = get_block_at(p)
	if bt == null:
		return false
	return BlockCatalog.shared().is_opaque(bt)

func is_raycast_solid(p: Vector3i) -> bool:
	var bt = get_block_at(p)
	if bt == null:
		return false
	return BlockCatalog.shared().is_raycast_solid(bt)

func is_world_edge(p: Vector3i) -> bool:
	if p.x <= 0 or p.x >= world_size - 1:
		return true
	if p.z <= 0 or p.z >= world_size - 1:
		return true
	return false

func get_revision(p: Vector3i) -> int:
	return cell_revisions.get(p, 0)

func _increment_revision(p: Vector3i) -> int:
	var rev = cell_revisions.get(p, 0) + 1
	cell_revisions[p] = rev
	return rev

func is_breakable(p: Vector3i) -> bool:
	if p.y < 0:
		return false
	if is_world_edge(p):
		return false
	var bt = get_block_at(p)
	if bt == null:
		return false
	return BlockCatalog.shared().is_breakable(bt)

func _invalidate_highest_cache(x: int, z: int):
	_highest_cache.erase(Vector2i(x, z))

func get_highest_solid_y(x: int, z: int) -> int:
	if x < 0 or x >= world_size or z < 0 or z >= world_size:
		return -1
	var key = Vector2i(x, z)
	if _highest_cache.has(key):
		return _highest_cache[key]
	for y in range(max_build_y - 1, -1, -1):
		var p = Vector3i(x, y, z)
		var bt = get_block_at(p)
		if bt != null and BlockCatalog.shared().is_solid(bt):
			_highest_cache[key] = y
			return y
	_highest_cache[key] = -1
	return -1

func get_highest_top(x: int, z: int) -> float:
	var y = get_highest_solid_y(x, z)
	if y == -1:
		return -9999.0
	return float(y) + 1.0

func try_mine_block(p: Vector3i) -> Array:
	# Returns Array[BlockEdit] batch - primary + any auto-removed attached torches, so every removed block is collected
	if is_world_edge(p):
		return [BlockEdit.fail(p, BlockEdit.Operation.MINE, BlockEdit.Result.FAIL_WORLD_EDGE)]
	if not is_breakable(p):
		return [BlockEdit.fail(p, BlockEdit.Operation.MINE, BlockEdit.Result.FAIL_NOT_BREAKABLE)]
	var old_type = get_block_at(p)
	if old_type == null:
		return [BlockEdit.fail(p, BlockEdit.Operation.MINE, BlockEdit.Result.FAIL_INVALID_POS)]

	var old_id = get_block_id_at(p)
	var prev_rev = get_revision(p)

	if placed_blocks.has(p):
		placed_blocks.erase(p)
	else:
		removed_blocks[p] = true
		if tree_block_fast.has(p):
			tree_block_fast.erase(p)

	if torch_attachments.has(p):
		torch_attachments.erase(p)

	_invalidate_highest_cache(p.x, p.z)
	var rev = _increment_revision(p)

	var edit = BlockEdit.success_mine(p, old_id, rev, prev_rev)
	block_edit_committed.emit(edit)

	var batch: Array[BlockEdit] = [edit]

	# Floating torches attached to this block also removed
	var floating: Array[Vector3i] = []
	for torch_pos in torch_attachments.keys():
		var attach = torch_attachments[torch_pos] as Vector3i
		if torch_pos + attach == p:
			floating.append(torch_pos)
	for torch_pos in floating:
		var torch_old_id = placed_blocks.get(torch_pos, BlockId.Type.TORCH)
		var torch_prev = get_revision(torch_pos)
		placed_blocks.erase(torch_pos)
		torch_attachments.erase(torch_pos)
		_invalidate_highest_cache(torch_pos.x, torch_pos.z)
		var torch_rev = _increment_revision(torch_pos)
		var torch_edit = BlockEdit.success_mine(torch_pos, torch_old_id, torch_rev, torch_prev)
		block_edit_committed.emit(torch_edit)
		batch.append(torch_edit)

	return batch

func try_place_block(p: Vector3i, block_type: int, attach_dir: Vector3i = Vector3i.ZERO) -> BlockEdit:
	var canonical_id: int = block_type

	if canonical_id == BlockId.Type.AIR:
		return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_INVALID_POS, "AIR not placeable")
	if not BlockId.is_valid(canonical_id):
		return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_INVALID_POS, "Invalid block id")

	if p.y < 0 or p.y >= max_build_y:
		return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_Y_OUT_OF_RANGE)
	if p.x < 0 or p.x >= world_size or p.z < 0 or p.z >= world_size:
		return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_OUT_OF_BOUNDS)
	if is_world_edge(p):
		return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_WORLD_EDGE)
	if is_occupied(p):
		return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_OCCUPIED)

	if canonical_id == BlockId.Type.TORCH:
		if attach_dir == Vector3i.ZERO:
			return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_SUPPORT, "Torch requires attach_dir")
		var is_cardinal = false
		for d in [Vector3i.UP, Vector3i.DOWN, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			if attach_dir == d:
				is_cardinal = true
				break
		if not is_cardinal:
			return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_SUPPORT, "Torch attach_dir must be cardinal")
		var support_pos = p + attach_dir
		if support_pos.x < 0 or support_pos.x >= world_size or support_pos.z < 0 or support_pos.z >= world_size or support_pos.y < 0 or support_pos.y >= max_build_y:
			return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_TORCH_SUPPORT, "Support out of bounds")
		if not is_opaque(support_pos) and not is_solid(support_pos):
			return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_TORCH_SUPPORT)

	if removed_blocks.has(p):
		removed_blocks.erase(p)
	placed_blocks[p] = canonical_id
	if canonical_id == BlockId.Type.TORCH:
		torch_attachments[p] = attach_dir
	_invalidate_highest_cache(p.x, p.z)

	var prev_rev = get_revision(p)
	var rev = _increment_revision(p)

	var edit = BlockEdit.success_place(p, canonical_id, rev, attach_dir, prev_rev)
	block_edit_committed.emit(edit)
	return edit

func try_place_torch(p: Vector3i, attach_dir: Vector3i) -> BlockEdit:
	return try_place_block(p, BlockId.Type.TORCH, attach_dir)

func get_spawn_position() -> Vector3:
	if height_map.is_empty() or type_map.is_empty():
		return Vector3(world_size * 0.5 + 0.5, 10.5, world_size * 0.5 + 0.5)
	var cx = world_size / 2
	var cz = world_size / 2
	var meadow_radius = 24.0
	var best = Vector3(cx + 0.5, 10.5, cz + 0.5)
	var best_score = 9999.0
	for dx in range(-int(meadow_radius), int(meadow_radius) + 1):
		for dz in range(-int(meadow_radius), int(meadow_radius) + 1):
			var x = cx + dx
			var z = cz + dz
			if x < 2 or x >= world_size - 2 or z < 2 or z >= world_size - 2:
				continue
			if Vector2(x, z).distance_to(Vector2(cx, cz)) > meadow_radius:
				continue
			if type_map[x][z] != BlockId.Type.GRASS:
				continue
			var h = height_map[x][z]
			var slope = 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx = x + d.x
				var nz = z + d.y
				if nx >= 0 and nx < world_size and nz >= 0 and nz < world_size:
					slope = max(slope, abs(height_map[nx][nz] - h))
			if slope > 0:
				continue
			var score = abs(dx) + abs(dz)
			if score < best_score:
				best_score = score
				best = Vector3(x + 0.5, float(h) + 1.0, z + 0.5)
	return best

func get_stats() -> Dictionary:
	return {
		"world_size": world_size,
		"chunk_size": chunk_size,
		"max_y": max_build_y,
		"placed": placed_blocks.size(),
		"removed": removed_blocks.size(),
		"torches": torch_attachments.size(),
		"tree_fast": tree_block_fast.size(),
		"revisions": cell_revisions.size(),
		"height_cache": _highest_cache.size(),
	}

func clear_edits():
	placed_blocks.clear()
	removed_blocks.clear()
	cell_revisions.clear()
	_highest_cache.clear()
	torch_attachments.clear()
