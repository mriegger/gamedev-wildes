extends RefCounted
class_name VoxelWorld

## VoxelWorld - owns voxel state, canonical AIR=0, no ChunkData duplication
## Height cache owned here and invalidated on edits, no second cache in controller/motor

signal block_edit_committed(edit: BlockEdit)

var world_size: int = 200
var chunk_size: int = 20
var max_build_y: int = 36
var water_level: int = 5
var infinite_world: bool = false

var height_map: Variant = [] # Array for finite, Dictionary for infinite
var type_map: Variant = []
var type_map_dict: Dictionary = {} # used for infinite when type_map is dict
var height_map_dict: Dictionary = {} # used for infinite

var _generator_ref: TerrainGenerator = null # optional for infinite on-demand generation

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


func setup(p_world_size: int, p_chunk_size: int, p_max_y: int, p_height_map: Variant, p_type_map: Variant, p_tree_fast: Dictionary, p_tree_blocks: Array = []):
	world_size = p_world_size
	chunk_size = p_chunk_size
	max_build_y = p_max_y
	if p_height_map is Dictionary:
		infinite_world = true
		height_map_dict = p_height_map
		height_map = []
		type_map_dict = p_type_map if p_type_map is Dictionary else {}
		type_map = []
	else:
		infinite_world = false
		height_map = p_height_map
		type_map = p_type_map
		height_map_dict.clear()
		type_map_dict.clear()
	tree_block_fast = p_tree_fast
	tree_blocks = p_tree_blocks
	_highest_cache.clear()
	cell_revisions.clear()
	placed_blocks.clear()
	removed_blocks.clear()
	torch_attachments.clear()

func setup_infinite(p_chunk_size: int, p_max_y: int):
	world_size = 1000000
	chunk_size = p_chunk_size
	max_build_y = p_max_y
	infinite_world = true
	height_map = []
	type_map = []
	height_map_dict.clear()
	type_map_dict.clear()
	tree_block_fast.clear()
	tree_blocks.clear()
	_highest_cache.clear()
	cell_revisions.clear()
	placed_blocks.clear()
	removed_blocks.clear()
	torch_attachments.clear()

func set_generator_ref(gen: TerrainGenerator):
	_generator_ref = gen

func ensure_column_generated(x: int, z: int):
	if not infinite_world:
		return
	if _generator_ref == null:
		return
	var key = Vector2i(x, z)
	if height_map_dict.has(key) and type_map_dict.has(key):
		return
	# Generate height/type for this column on demand
	if _generator_ref.has_method("compute_height_at_world"):
		var h = _generator_ref.compute_height_at_world(x, z)
		height_map_dict[key] = h
		if _generator_ref.has_method("compute_type_and_biome_at_world"):
			var tb = _generator_ref.compute_type_and_biome_at_world(x, z, h)
			type_map_dict[key] = tb["type"]

func ensure_region_generated(origin_x: int, origin_z: int, size_x: int, size_z: int):
	if not infinite_world or _generator_ref == null:
		return
	for x in range(origin_x, origin_x+size_x):
		for z in range(origin_z, origin_z+size_z):
			ensure_column_generated(x, z)

func apply_chunk_gen(chunk_data: Dictionary):
	var h_dict = {}
	var t_dict = {}
	# Support both generate_all format (height_map/type_map) and generate_chunk_region format (height/type)
	if chunk_data.has("height_map"):
		var hm = chunk_data["height_map"]
		if hm is Dictionary:
			h_dict = hm
		elif hm is Array:
			# convert array to dict for finite? Not needed for infinite
			pass
	elif chunk_data.has("height"):
		h_dict = chunk_data.get("height", {})

	if chunk_data.has("type_map"):
		var tm = chunk_data["type_map"]
		if tm is Dictionary:
			t_dict = tm
	elif chunk_data.has("type"):
		t_dict = chunk_data.get("type", {})

	for k in h_dict.keys():
		height_map_dict[k] = h_dict[k]
	for k in t_dict.keys():
		type_map_dict[k] = t_dict[k]

func apply_tree_chunk(tree_data: Dictionary):
	var fast = tree_data.get("tree_block_fast", {})
	for k in fast.keys():
		tree_block_fast[k] = fast[k]
	var blocks = tree_data.get("tree_blocks", [])
	for b in blocks:
		tree_blocks.append(b)

func _base_terrain_type_at(x: int, y: int, z: int):
	if infinite_world:
		var key = Vector2i(x, z)
		if not height_map_dict.has(key) or not type_map_dict.has(key):
			# Try on-demand generation before giving up (for torch placement etc)
			ensure_column_generated(x, z)
			if not height_map_dict.has(key) or not type_map_dict.has(key):
				return null
		var h = height_map_dict[key]
		if y > h or y < 0:
			return null
		var top_t = type_map_dict[key]
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
	else:
		if x < 0 or x >= world_size or z < 0 or z >= world_size:
			return null
		if height_map.is_empty() or type_map.is_empty():
			return null
		# height_map may be Array or empty
		if x >= height_map.size() or z >= height_map[x].size():
			return null
		var h = height_map[x][z]
		if y > h or y < 0:
			return null
		if x >= type_map.size() or z >= type_map[x].size():
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
		if infinite_world:
			return BlockId.Type.STONE
		return BlockId.Type.STONE
	if p.y >= max_build_y:
		return null
	if not infinite_world:
		if p.x < 0 or p.x >= world_size or p.z < 0 or p.z >= world_size:
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
	if infinite_world:
		return false
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
	if not infinite_world:
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
	if not infinite_world:
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
		if support_pos.y < 0 or support_pos.y >= max_build_y:
			return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_TORCH_SUPPORT, "Support Y out of bounds")
		if not infinite_world:
			if support_pos.x < 0 or support_pos.x >= world_size or support_pos.z < 0 or support_pos.z >= world_size:
				return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_TORCH_SUPPORT, "Support out of bounds")

		# For infinite, ensure support column exists before checking opacity
		if infinite_world:
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

	var prev_rev = get_revision(p)
	var rev = _increment_revision(p)

	var edit = BlockEdit.success_place(p, canonical_id, rev, attach_dir, prev_rev)
	block_edit_committed.emit(edit)
	return edit

func try_place_torch(p: Vector3i, attach_dir: Vector3i) -> BlockEdit:
	return try_place_block(p, BlockId.Type.TORCH, attach_dir)

func get_spawn_position() -> Vector3:
	if infinite_world:
		# For infinite, spawn at origin meadow
		var meadow_radius = 24.0
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
			if x >= type_map.size() or z >= type_map[x].size():
				continue
			if type_map[x][z] != BlockId.Type.GRASS:
				continue
			var h = height_map[x][z]
			var slope = 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx = x + d.x
				var nz = z + d.y
				if nx >= 0 and nx < world_size and nz >= 0 and nz < world_size:
					if nx < height_map.size() and nz < height_map[nx].size():
						slope = max(slope, abs(height_map[nx][nz] - h))
			if slope > 0:
				continue
			var score = abs(dx) + abs(dz)
			if score < best_score:
				best_score = score
				best = Vector3(x + 0.5, float(h) + 1.0, z + 0.5)
	return best

func get_chunk_coord_for_world_pos(p: Vector3i) -> Vector2i:
	return Vector2i(int(floor(float(p.x) / float(chunk_size))), int(floor(float(p.z) / float(chunk_size))))

func get_chunk_coord_for_world_posf(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / float(chunk_size))), int(floor(p.z / float(chunk_size))))

func get_chunk_origin(chunk: Vector2i) -> Vector3i:
	return Vector3i(chunk.x * chunk_size, 0, chunk.y * chunk_size)

func build_cache_for_chunk(origin_x: int, origin_z: int, p_chunk_size: int, p_max_y: int) -> Dictionary:
	var size_x = p_chunk_size
	var size_z = p_chunk_size
	var size_y = clamp(p_max_y, 6, 128)
	var cache_x = size_x + 2
	var cache_z = size_z + 2
	var cache: Array = []
	cache.resize(cache_x * size_y * cache_z)

	var ws = world_size
	var is_inf = infinite_world

	for lx in range(cache_x):
		var wx = origin_x + lx - 1
		var wx_valid = is_inf or (wx >= 0 and wx < ws)
		for lz in range(cache_z):
			var wz = origin_z + lz - 1
			var wz_valid = wx_valid and (is_inf or (wz >= 0 and wz < ws))
			var base_h = -1
			var base_top_t = -1
			if wz_valid:
				if is_inf:
					var key = Vector2i(wx, wz)
					if height_map_dict.has(key):
						base_h = height_map_dict[key]
						if type_map_dict.has(key):
							base_top_t = type_map_dict[key]
				else:
					if not height_map.is_empty() and wx < height_map.size() and wz < height_map[wx].size():
						var hm = height_map[wx][wz]
						if hm is int:
							base_h = hm
							if not type_map.is_empty() and wx < type_map.size() and wz < type_map[wx].size():
								base_top_t = type_map[wx][wz]
			for ly in range(size_y):
				var idx = (lx * size_y * cache_z) + (ly * cache_z) + lz
				var wy = ly
				if not wz_valid or wy < 0 or wy >= max_build_y:
					var p_out = Vector3i(wx, wy, wz)
					if placed_blocks.has(p_out):
						cache[idx] = placed_blocks[p_out]
					else:
						cache[idx] = -1
					continue

				var p = Vector3i(wx, wy, wz)
				if placed_blocks.has(p):
					cache[idx] = placed_blocks[p]
					continue
				if removed_blocks.has(p):
					cache[idx] = -1
					continue
				if tree_block_fast.has(p):
					cache[idx] = tree_block_fast[p]
					continue

				if base_h == -1:
					cache[idx] = -1
					continue
				if wy > base_h:
					cache[idx] = -1
					continue
				if base_top_t == -1:
					cache[idx] = -1
					continue
				if base_top_t == BlockId.Type.SAND:
					cache[idx] = BlockId.Type.SAND
				elif base_top_t == BlockId.Type.STONE:
					cache[idx] = BlockId.Type.STONE
				elif base_top_t == BlockId.Type.GRASS:
					if wy == base_h:
						cache[idx] = BlockId.Type.GRASS
					elif wy >= base_h - 2:
						cache[idx] = BlockId.Type.DIRT
					else:
						cache[idx] = BlockId.Type.STONE
				elif base_top_t == BlockId.Type.DIRT:
					cache[idx] = BlockId.Type.DIRT
				else:
					cache[idx] = base_top_t

	return {
		"cache": cache,
		"origin_x": origin_x,
		"origin_z": origin_z,
		"size_x": size_x,
		"size_z": size_z,
		"size_y": size_y,
		"cache_x": cache_x,
		"cache_z": cache_z,
	}

func unload_chunk_terrain(cx: int, cz: int):
	# For fast reload (avoid lag when returning), keep height/type/tree caches.
	# Only clear highest cache which is recalculated cheaply. This makes chunk reload
	# reuse existing terrain data and mesh cache for instant display.
	if not infinite_world:
		return
	var ox = cx * chunk_size
	var oz = cz * chunk_size
	var cs = chunk_size
	for x in range(ox - 1, ox + cs + 1):
		for z in range(oz - 1, oz + cs + 1):
			_highest_cache.erase(Vector2i(x, z))
	# Optional bounded pruning: if dict grows huge (>200k columns ≈ 400 chunks), prune oldest.
	# Keep it simple: only prune when exceeding 200k, remove this chunk's terrain then.
	if height_map_dict.size() > 200000:
		for x in range(ox - 1, ox + cs + 1):
			for z in range(oz - 1, oz + cs + 1):
				var k = Vector2i(x, z)
				height_map_dict.erase(k)
				type_map_dict.erase(k)
		var to_erase_tree: Array[Vector3i] = []
		for p in tree_block_fast.keys():
			if p is Vector3i:
				if p.x >= ox and p.x < ox + cs and p.z >= oz and p.z < oz + cs:
					to_erase_tree.append(p)
		for p in to_erase_tree:
			tree_block_fast.erase(p)

func has_trees_in_chunk(cx: int, cz: int) -> bool:
	if not infinite_world:
		return true # for finite assume ok
	var ox = cx * chunk_size
	var oz = cz * chunk_size
	var cs = chunk_size
	# If inside meadow core, zero trees is expected → treat as having data to avoid re-gen
	var meadow_radius = 24.0
	if Vector2(ox + cs*0.5, oz + cs*0.5).length() < meadow_radius - 2.0:
		return true
	for p in tree_block_fast.keys():
		if p is Vector3i:
			if p.x >= ox and p.x < ox + cs and p.z >= oz and p.z < oz + cs:
				return true
	return false

func is_chunk_data_available(cx: int, cz: int) -> bool:
	var origin_x = cx * chunk_size
	var origin_z = cz * chunk_size
	if infinite_world:
		var key = Vector2i(origin_x, origin_z)
		return height_map_dict.has(key)
	else:
		if height_map.is_empty():
			return false
		if origin_x < 0 or origin_z < 0 or origin_x >= world_size or origin_z >= world_size:
			return false
		if origin_x < height_map.size() and origin_z < height_map[origin_x].size():
			return height_map[origin_x][origin_z] != null
		return false

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
