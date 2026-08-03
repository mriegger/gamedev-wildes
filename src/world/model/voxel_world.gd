extends RefCounted
class_name VoxelWorld

signal block_edit_committed(edit: BlockEdit)
signal terrain_chunk_evicted(coord: Vector2i)

var chunk_size: int = 20
var max_build_y: int = 36
var water_level: int = 5

var type_map_dict: Dictionary = {}
var height_map_dict: Dictionary = {}

var _generator_ref: TerrainGenerator = null

var tree_block_fast: Dictionary = {}
var tree_chunks_fast: Dictionary = {}
var generated_tree_chunks: Dictionary = {}
var generated_terrain_chunks: Dictionary = {}

var _terrain_chunk_lru: Dictionary = {}
var max_terrain_cache_chunks: int = 257
var _terrain_lru_mutex: Mutex = Mutex.new()

var placed_blocks: Dictionary = {}
var removed_blocks: Dictionary = {}
var cell_revisions: Dictionary = {}
var _highest_cache: Dictionary = {}
var torch_attachments: Dictionary = {}

func _init(p_chunk_size: int = 20, p_max_build_y: int = 36):
	chunk_size = p_chunk_size
	max_build_y = p_max_build_y
	water_level = 5

func setup_infinite(p_chunk_size: int, p_max_y: int):
	chunk_size = p_chunk_size
	max_build_y = p_max_y
	height_map_dict.clear()
	type_map_dict.clear()
	tree_block_fast.clear()
	tree_chunks_fast.clear()
	generated_tree_chunks.clear()
	generated_terrain_chunks.clear()
	_terrain_chunk_lru.clear()
	_highest_cache.clear()
	cell_revisions.clear()
	placed_blocks.clear()
	removed_blocks.clear()
	torch_attachments.clear()

func set_generator_ref(gen: TerrainGenerator):
	_generator_ref = gen

func _prune_revisions():
	for key in cell_revisions.keys():
		if not placed_blocks.has(key) and not removed_blocks.has(key):
			cell_revisions.erase(key)

func configure_terrain_cache(render_dist: int, unload_padding: int):
	var keep = render_dist + unload_padding
	var touched_area = ((keep + 1) * 2 + 1) * ((keep + 1) * 2 + 1)
	max_terrain_cache_chunks = touched_area * 3 + 256

func _touch_terrain_chunk(coord: Vector2i):
	_terrain_lru_mutex.lock()
	if _terrain_chunk_lru.has(coord):
		_terrain_chunk_lru.erase(coord)
	_terrain_chunk_lru[coord] = true
	_terrain_lru_mutex.unlock()
	generated_terrain_chunks[coord] = true

func prune_terrain_cache(max_to_evict: int = -1) -> int:
	_terrain_lru_mutex.lock()
	if _terrain_chunk_lru.size() <= max_terrain_cache_chunks:
		_terrain_lru_mutex.unlock()
		return 0
	var to_remove = _terrain_chunk_lru.size() - max_terrain_cache_chunks
	if max_to_evict != -1:
		to_remove = min(to_remove, max_to_evict)
	var to_evict: Array[Vector2i] = []
	var lru_keys = _terrain_chunk_lru.keys()
	var evict_count = min(to_remove, lru_keys.size())
	for i in range(evict_count):
		var coord = lru_keys[i] as Vector2i
		_terrain_chunk_lru.erase(coord)
		to_evict.append(coord)
	_terrain_lru_mutex.unlock()

	var evicted: Array[Vector2i] = []
	for coord in to_evict:
		generated_terrain_chunks.erase(coord)
		var ox = coord.x * chunk_size
		var oz = coord.y * chunk_size
		for x in range(ox, ox+chunk_size):
			for z in range(oz, oz+chunk_size):
				var k = Vector2i(x,z)
				height_map_dict.erase(k)
				type_map_dict.erase(k)
				_highest_cache.erase(k)
		if tree_chunks_fast.has(coord):
			var chunk_trees = tree_chunks_fast[coord] as Dictionary
			for tree_pos in chunk_trees.keys():
				tree_block_fast.erase(tree_pos)
			tree_chunks_fast.erase(coord)
		generated_tree_chunks.erase(coord)
		evicted.append(coord)

	for coord in evicted:
		terrain_chunk_evicted.emit(coord)
	_prune_revisions()
	return evicted.size()

func ensure_column_generated(x: int, z: int):
	if _generator_ref == null:
		return
	var key = Vector2i(x, z)
	if height_map_dict.has(key) and type_map_dict.has(key):
		return
	var res = _generator_ref.compute_height_at_world(x, z)
	var h = res.get("h", 1) as int
	height_map_dict[key] = h
	var lf = res.get("lake_factor", 0.0) as float
	var rf = res.get("river_factor", 0.0) as float
	var tb = _generator_ref._compute_type_from_cached(x, z, h, lf, rf)
	type_map_dict[key] = tb.get("type", BlockId.Type.GRASS) as int
	var cc = Vector2i(int(floor(float(x) / float(chunk_size))), int(floor(float(z) / float(chunk_size))))
	_touch_terrain_chunk(cc)

func ensure_region_generated(origin_x: int, origin_z: int, size_x: int, size_z: int):
	if _generator_ref == null:
		return
	for x in range(origin_x, origin_x+size_x):
		for z in range(origin_z, origin_z+size_z):
			ensure_column_generated(x, z)

func apply_chunk_gen(chunk_data: Dictionary):
	var h_dict = {}
	var t_dict = {}
	if chunk_data.has("height"):
		h_dict = chunk_data.get("height", {})
	elif chunk_data.has("height_map"):
		h_dict = chunk_data.get("height_map", {})
	if chunk_data.has("type"):
		t_dict = chunk_data.get("type", {})
	elif chunk_data.has("type_map"):
		t_dict = chunk_data.get("type_map", {})
	for k in h_dict.keys():
		height_map_dict[k] = h_dict[k]
	for k in t_dict.keys():
		type_map_dict[k] = t_dict[k]
	var counts: Dictionary = {}
	for k in h_dict.keys():
		if k is Vector2i:
			var cc = Vector2i(int(floor(float(k.x) / float(chunk_size))), int(floor(float(k.y) / float(chunk_size))))
			counts[cc] = counts.get(cc, 0) + 1
	var threshold = int(float(chunk_size * chunk_size) * 0.9)
	for cc in counts.keys():
		if counts[cc] >= threshold:
			_touch_terrain_chunk(cc)

func apply_chunk_gen_for_coord(coord: Vector2i, chunk_data: Dictionary):
	var h_dict = {}
	var t_dict = {}
	if chunk_data.has("height"):
		h_dict = chunk_data.get("height", {})
	if chunk_data.has("type"):
		t_dict = chunk_data.get("type", {})
	for k in h_dict.keys():
		height_map_dict[k] = h_dict[k]
	for k in t_dict.keys():
		type_map_dict[k] = t_dict[k]
	_touch_terrain_chunk(coord)

func apply_tree_chunk(tree_data: Dictionary):
	var fast = tree_data.get("tree_block_fast", {})
	if fast.is_empty():
		return
	for k in fast.keys():
		if k is Vector3i:
			tree_block_fast[k] = fast[k]
			var cc = Vector2i(int(floor(float(k.x) / float(chunk_size))), int(floor(float(k.z) / float(chunk_size))))
			if not tree_chunks_fast.has(cc):
				tree_chunks_fast[cc] = {}
			tree_chunks_fast[cc][k] = fast[k]
			generated_tree_chunks[cc] = true
			_touch_terrain_chunk(cc)

func apply_tree_chunk_for_coord(coord: Vector2i, tree_data: Dictionary):
	if generated_tree_chunks.has(coord):
		return
	var fast = tree_data.get("tree_block_fast", {}) as Dictionary
	if fast.is_empty():
		generated_tree_chunks[coord] = true
		return
	for k in fast.keys():
		if k is Vector3i:
			tree_block_fast[k] = fast[k]
			if not tree_chunks_fast.has(coord):
				tree_chunks_fast[coord] = {}
			tree_chunks_fast[coord][k] = fast[k]
	generated_tree_chunks[coord] = true

func get_block_at(p: Vector3i):
	if placed_blocks.has(p):
		return placed_blocks[p]
	if removed_blocks.has(p):
		return null
	if tree_block_fast.has(p):
		return tree_block_fast[p]
	var key = Vector2i(p.x, p.z)
	if not height_map_dict.has(key):
		return null
	var h = height_map_dict[key] as int
	if p.y > h:
		if p.y <= water_level and h < water_level:
			return BlockId.Type.WATER
		return null
	var top_t = type_map_dict.get(key, -1) as int
	if top_t == -1:
		return null
	return BlockCatalog.column_block_at(top_t, h, p.y)

func get_block_id_at(p: Vector3i) -> int:
	var bt = get_block_at(p)
	if bt == null:
		return BlockId.Type.AIR
	return bt as int

func is_solid(p: Vector3i) -> bool:
	var bt = get_block_at(p)
	if bt == null:
		return false
	return BlockCatalog.shared().is_solid(bt)

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

func get_revision(p: Vector3i) -> int:
	return cell_revisions.get(p, 0)

func _increment_revision(p: Vector3i) -> int:
	var rev = cell_revisions.get(p, 0) + 1
	cell_revisions[p] = rev
	return rev

func is_breakable(p: Vector3i) -> bool:
	if p.y < 0:
		return false
	var bt = get_block_at(p)
	if bt == null:
		return false
	return BlockCatalog.shared().is_breakable(bt)

func _invalidate_highest_cache(x: int, z: int):
	_highest_cache.erase(Vector2i(x, z))

func get_highest_solid_y(x: int, z: int) -> int:
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

func is_occupied(p: Vector3i) -> bool:
	var bt = get_block_at(p)
	if bt == null:
		return false
	if bt == BlockId.Type.AIR:
		return false
	if bt == BlockId.Type.WATER:
		return false
	return true

func try_mine_block(p: Vector3i) -> Array:
	if not is_breakable(p):
		return [BlockEdit.fail(p, BlockEdit.Operation.MINE, BlockEdit.Result.FAIL_NOT_BREAKABLE)]
	var old_type = get_block_at(p)
	if old_type == null:
		return [BlockEdit.fail(p, BlockEdit.Operation.MINE, BlockEdit.Result.FAIL_INVALID_POS)]
	var old_id = get_block_id_at(p)
	var prev_rev = get_revision(p)
	var was_placed = placed_blocks.has(p)
	var surviving_after = false
	if was_placed:
		placed_blocks.erase(p)
		var col_key = Vector2i(p.x, p.z)
		var h = height_map_dict.get(col_key, -1) as int
		if h != -1 and p.y <= h:
			removed_blocks[p] = true
			surviving_after = true
		else:
			surviving_after = false
	else:
		removed_blocks[p] = true
		surviving_after = true
		if tree_block_fast.has(p):
			tree_block_fast.erase(p)
			var cc = Vector2i(int(floor(float(p.x) / float(chunk_size))), int(floor(float(p.z) / float(chunk_size))))
			if tree_chunks_fast.has(cc):
				tree_chunks_fast[cc].erase(p)
	if torch_attachments.has(p):
		torch_attachments.erase(p)
	_invalidate_highest_cache(p.x, p.z)
	var rev: int
	if surviving_after:
		rev = _increment_revision(p)
	else:
		cell_revisions.erase(p)
		rev = prev_rev + 1
	var edit = BlockEdit.success_mine(p, old_id, rev)
	block_edit_committed.emit(edit)
	var batch: Array[BlockEdit] = [edit]
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
		cell_revisions.erase(torch_pos)
		var torch_rev = torch_prev + 1
		var torch_edit = BlockEdit.success_mine(torch_pos, torch_old_id, torch_rev)
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
	if is_occupied(p):
		var existing_id = get_block_id_at(p)
		if existing_id != BlockId.Type.AIR:
			var existing_def = BlockCatalog.shared().get_definition(existing_id)
			if existing_def == null or not existing_def.is_replaceable:
				if existing_id != BlockId.Type.WATER:
					return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_OCCUPIED)
		else:
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
		if support_pos.y < 0 or support_pos.y >= max_build_y:
			return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_TORCH_SUPPORT, "Support Y out of bounds")
		ensure_column_generated(support_pos.x, support_pos.z)
		ensure_region_generated(support_pos.x -1, support_pos.z -1, 3, 3)
		if not is_opaque(support_pos) and not is_solid(support_pos):
			return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_TORCH_SUPPORT)
	if removed_blocks.has(p):
		removed_blocks.erase(p)
	placed_blocks[p] = canonical_id
	if canonical_id == BlockId.Type.TORCH:
		torch_attachments[p] = attach_dir
	_invalidate_highest_cache(p.x, p.z)
	var rev = _increment_revision(p)
	var edit = BlockEdit.success_place(p, canonical_id, rev, attach_dir)
	block_edit_committed.emit(edit)
	return edit

func get_spawn_position() -> Vector3:
	var meadow_radius = WorldConfig.DEFAULT_MEADOW_RADIUS
	var best = Vector3(0.5, 10.5, 0.5)
	var best_score = 9999.0
	for dx in range(-int(meadow_radius), int(meadow_radius) + 1):
		for dz in range(-int(meadow_radius), int(meadow_radius) + 1):
			var x = dx
			var z = dz
			if Vector2(x, z).length() > meadow_radius:
				continue
			var key = Vector2i(x, z)
			if not height_map_dict.has(key):
				continue
			if type_map_dict.get(key, -1) != BlockId.Type.GRASS:
				continue
			var h = height_map_dict[key]
			var slope = 0
			for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var nk = Vector2i(x + d.x, z + d.y)
				if height_map_dict.has(nk):
					slope = max(slope, abs(height_map_dict[nk] - h))
			if slope > 0:
				continue
			var score = abs(dx) + abs(dz)
			if score < best_score:
				best_score = score
				best = Vector3(x + 0.5, float(h) + 1.0, z + 0.5)
	return best

func snapshot_edits_for_chunk(origin_x: int, origin_z: int, p_chunk_size: int) -> Dictionary:
	var ox_min = origin_x - 2
	var ox_max = origin_x + p_chunk_size + 1
	var oz_min = origin_z - 2
	var oz_max = origin_z + p_chunk_size + 1
	var placed_snap: Dictionary = {}
	var removed_snap: Dictionary = {}
	for pos in placed_blocks.keys():
		if pos is Vector3i:
			if pos.x >= ox_min and pos.x <= ox_max and pos.z >= oz_min and pos.z <= oz_max:
				placed_snap[pos] = placed_blocks[pos]
	for pos in removed_blocks.keys():
		if pos is Vector3i:
			if pos.x >= ox_min and pos.x <= ox_max and pos.z >= oz_min and pos.z <= oz_max:
				removed_snap[pos] = true
	var tree_snap: Dictionary = {}
	var c_min_x = int(floor(float(ox_min) / float(chunk_size)))
	var c_max_x = int(floor(float(ox_max) / float(chunk_size)))
	var c_min_z = int(floor(float(oz_min) / float(chunk_size)))
	var c_max_z = int(floor(float(oz_max) / float(chunk_size)))
	for cx in range(c_min_x, c_max_x + 1):
		for cz in range(c_min_z, c_max_z + 1):
			var c = Vector2i(cx, cz)
			if tree_chunks_fast.has(c):
				var dict = tree_chunks_fast[c] as Dictionary
				for pos in dict.keys():
					if pos is Vector3i:
						if pos.x >= ox_min and pos.x <= ox_max and pos.z >= oz_min and pos.z <= oz_max:
							tree_snap[pos] = dict[pos]
	return {"placed": placed_snap, "removed": removed_snap, "trees": tree_snap}

func is_chunk_data_available(cx: int, cz: int) -> bool:
	var coord = Vector2i(cx, cz)
	return generated_terrain_chunks.has(coord)

func has_trees_in_chunk(cx: int, cz: int) -> bool:
	var coord = Vector2i(cx, cz)
	return generated_tree_chunks.has(coord)
