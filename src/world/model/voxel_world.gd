extends RefCounted
class_name VoxelWorld

## VoxelWorld - owns voxel state, canonical AIR=0, no ChunkData duplication
## Optimized: per-chunk tree tracking, chunk-level LRU, no scanning

signal block_edit_committed(edit: BlockEdit)
signal terrain_chunk_evicted(coord: Vector2i)

var world_size: int = 200
var chunk_size: int = 20
var max_build_y: int = 36
var water_level: int = 5
var infinite_world: bool = false

var height_map: Variant = [] # Array for finite, Dictionary for infinite (legacy)
var type_map: Variant = []
var type_map_dict: Dictionary = {} # infinite: Vector2i(x,z) -> top type
var height_map_dict: Dictionary = {} # infinite: Vector2i(x,z) -> height

var _generator_ref: TerrainGenerator = null

# Global tree storage (for get_block_at)
var tree_blocks: Array = []
var tree_block_fast: Dictionary = {}

# Per-chunk indexed tree storage to avoid scanning and allow O(k) removal
var tree_chunks_fast: Dictionary = {}
var tree_chunks_blocks: Dictionary = {}
var generated_tree_chunks: Dictionary = {}

# Terrain data tracking - complete generation marker rather than single column test
var generated_terrain_chunks: Dictionary = {} # Vector2i(chunk) -> true

# Terrain chunk LRU for bounding memory - ChunkManager is sole eviction owner
var _terrain_chunk_lru: Array[Vector2i] = []
var max_terrain_cache_chunks: int = 200
var _terrain_lru_mutex: Mutex = Mutex.new()

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
	# Rebuild per-chunk index if we have tree data (finite load)
	tree_chunks_fast.clear()
	tree_chunks_blocks.clear()
	generated_tree_chunks.clear()
	generated_terrain_chunks.clear()
	_terrain_chunk_lru.clear()
	if infinite_world:
		# For dict based height, populate LRU based on existing columns
		var chunk_set: Dictionary = {}
		for k in height_map_dict.keys():
			if k is Vector2i:
				var cc = Vector2i(int(floor(float(k.x) / float(chunk_size))), int(floor(float(k.y) / float(chunk_size))))
				chunk_set[cc] = true
		for cc in chunk_set.keys():
			_terrain_chunk_lru.append(cc)
	# Index existing tree blocks by chunk
	if not tree_block_fast.is_empty():
		for pos in tree_block_fast.keys():
			if pos is Vector3i:
				var cc = Vector2i(int(floor(float(pos.x) / float(chunk_size))), int(floor(float(pos.z) / float(chunk_size))))
				if not tree_chunks_fast.has(cc):
					tree_chunks_fast[cc] = {}
					tree_chunks_blocks[cc] = []
				tree_chunks_fast[cc][pos] = tree_block_fast[pos]
				tree_chunks_blocks[cc].append({"pos": pos, "type": tree_block_fast[pos]})
				generated_tree_chunks[cc] = true
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
	tree_chunks_fast.clear()
	tree_chunks_blocks.clear()
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

func configure_terrain_cache(render_dist: int, unload_padding: int):
	# Keep cache big enough for keep area plus 1 border for cache overlap + slack
	# Each chunk generation touches neighbors (origin-1 .. origin+cs), so touched area = (keep+1)*2+1
	var keep = render_dist + unload_padding
	var keep_area = (keep * 2 + 1) * (keep * 2 + 1)
	var touched_area = ((keep + 1) * 2 + 1) * ((keep + 1) * 2 + 1)
	max_terrain_cache_chunks = touched_area + 32
	print("[VoxelWorld] Configured max terrain cache chunks = %d (keep area %d touched %d)" % [max_terrain_cache_chunks, keep_area, touched_area])

func _touch_terrain_chunk(coord: Vector2i):
	if not infinite_world:
		return
	_terrain_lru_mutex.lock()
	if _terrain_chunk_lru.has(coord):
		_terrain_chunk_lru.erase(coord)
	_terrain_chunk_lru.append(coord)
	_terrain_lru_mutex.unlock()
	generated_terrain_chunks[coord] = true
	# Bounded cleanup: if LRU exceeds max, evict oldest and emit signal so manager stays consistent
	# This keeps cache bounded even for border columns, with explicit ownership
	_prune_terrain_cache_if_needed()

func _prune_terrain_cache_if_needed():
	# Safety only - should not auto-evict during normal streaming since
	# ChunkManager owns eviction. This is called explicitly if needed.
	if not infinite_world:
		return
	_terrain_lru_mutex.lock()
	var over = _terrain_chunk_lru.size() - max_terrain_cache_chunks
	_terrain_lru_mutex.unlock()
	if over <= 0:
		return
	for _i in range(over):
		_terrain_lru_mutex.lock()
		if _terrain_chunk_lru.is_empty():
			_terrain_lru_mutex.unlock()
			break
		var oldest = _terrain_chunk_lru[0]
		_terrain_chunk_lru.remove_at(0)
		_terrain_lru_mutex.unlock()
		_evict_chunk_data(oldest.x, oldest.y, false)

func _evict_chunk_data(cx: int, cz: int, remove_from_lru: bool = true):
	if not infinite_world:
		return
	var coord = Vector2i(cx, cz)
	if remove_from_lru:
		_terrain_lru_mutex.lock()
		_terrain_chunk_lru.erase(coord)
		_terrain_lru_mutex.unlock()
	var ox = cx * chunk_size
	var oz = cz * chunk_size
	var cs = chunk_size
	# Remove own columns (explicit ownership)
	for x in range(ox, ox + cs):
		for z in range(oz, oz + cs):
			var k = Vector2i(x, z)
			height_map_dict.erase(k)
			type_map_dict.erase(k)
			_highest_cache.erase(k)
	generated_terrain_chunks.erase(coord)
	# Bounded cleanup for border columns: only keep border if its owning chunk is still generated
	# This prevents extended cache from growing beyond limit
	for x in range(ox - 1, ox + cs + 1):
		for z in range(oz - 1, oz + cs + 1):
			# Skip inner already removed
			if x >= ox and x < ox + cs and z >= oz and z < oz + cs:
				continue
			var k = Vector2i(x, z)
			var owner = Vector2i(int(floor(float(x) / float(chunk_size))), int(floor(float(z) / float(chunk_size))))
			if not generated_terrain_chunks.has(owner):
				# No owner chunk generated, safe to remove border cache
				height_map_dict.erase(k)
				type_map_dict.erase(k)
				_highest_cache.erase(k)
	# Remove trees for this chunk O(k)
	_remove_tree_chunk(cx, cz)
	terrain_chunk_evicted.emit(coord)

func _remove_tree_chunk(cx: int, cz: int):
	var coord = Vector2i(cx, cz)
	if not tree_chunks_fast.has(coord):
		# Still erase from generated set
		generated_tree_chunks.erase(coord)
		return
	var fast = tree_chunks_fast[coord] as Dictionary
	if fast == null:
		fast = {}
	# Remove from global fast dict
	for pos in fast.keys():
		tree_block_fast.erase(pos)
	# Remove per-chunk storage
	tree_chunks_fast.erase(coord)
	tree_chunks_blocks.erase(coord)
	generated_tree_chunks.erase(coord)
	# Rebuild global tree_blocks array from remaining per-chunk blocks to avoid O(N^2) filtering and ensure no duplicates
	# This is O(total tree blocks) but only on eviction (rare, 4 per frame max)
	var new_global_blocks: Array = []
	for blocks in tree_chunks_blocks.values():
		new_global_blocks.append_array(blocks)
	tree_blocks = new_global_blocks

func ensure_column_generated(x: int, z: int):
	if not infinite_world:
		return
	if _generator_ref == null:
		return
	var key = Vector2i(x, z)
	if height_map_dict.has(key) and type_map_dict.has(key):
		return
	if _generator_ref.has_method("compute_height_at_world"):
		var h = _generator_ref.compute_height_at_world(x, z)
		height_map_dict[key] = h
		if _generator_ref.has_method("compute_type_and_biome_at_world"):
			var tb = _generator_ref.compute_type_and_biome_at_world(x, z, h)
			type_map_dict[key] = tb["type"]
		# Touch chunk for LRU
		var cc = Vector2i(int(floor(float(x) / float(chunk_size))), int(floor(float(z) / float(chunk_size))))
		_touch_terrain_chunk(cc)

func ensure_region_generated(origin_x: int, origin_z: int, size_x: int, size_z: int):
	if not infinite_world or _generator_ref == null:
		return
	for x in range(origin_x, origin_x+size_x):
		for z in range(origin_z, origin_z+size_z):
			ensure_column_generated(x, z)

func apply_chunk_gen(chunk_data: Dictionary):
	# Legacy: marks all touched chunks - kept for compat but now delegates to owning-only logic
	# For complete marker we try to find main chunk via most frequent chunk in dict
	var h_dict = {}
	var t_dict = {}
	if chunk_data.has("height_map"):
		var hm = chunk_data["height_map"]
		if hm is Dictionary:
			h_dict = hm
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

	# For legacy, count columns per chunk and only mark chunks with full ownership
	var counts: Dictionary = {}
	for k in h_dict.keys():
		if k is Vector2i:
			var cc = Vector2i(int(floor(float(k.x) / float(chunk_size))), int(floor(float(k.y) / float(chunk_size))))
			counts[cc] = counts.get(cc, 0) + 1
	var threshold = int(float(chunk_size * chunk_size) * 0.9) # 90% of chunk area counts as complete
	for cc in counts.keys():
		if counts[cc] >= threshold:
			_touch_terrain_chunk(cc)

func apply_chunk_gen_for_coord(coord: Vector2i, chunk_data: Dictionary):
	# Only owning chunk receives complete generation marker and LRU entry
	# Border columns still stored for meshing but with explicit ownership cleanup
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

	# Store all columns (including border) for meshing - needed for seamless
	for k in h_dict.keys():
		height_map_dict[k] = h_dict[k]
	for k in t_dict.keys():
		type_map_dict[k] = t_dict[k]

	# Only owning chunk gets LRU and generation marker
	_touch_terrain_chunk(coord)

func apply_tree_chunk(tree_data: Dictionary):
	# Legacy path without coord - for finite world bulk load, index by chunk
	var fast = tree_data.get("tree_block_fast", {})
	if fast.is_empty():
		return
	var blocks = tree_data.get("tree_blocks", [])
	# If we have no per-chunk info, just merge but also index
	for k in fast.keys():
		if k is Vector3i:
			tree_block_fast[k] = fast[k]
			var cc = Vector2i(int(floor(float(k.x) / float(chunk_size))), int(floor(float(k.z) / float(chunk_size))))
			if not tree_chunks_fast.has(cc):
				tree_chunks_fast[cc] = {}
				tree_chunks_blocks[cc] = []
			if not tree_chunks_fast[cc].has(k):
				tree_chunks_fast[cc][k] = fast[k]
			generated_tree_chunks[cc] = true
			_touch_terrain_chunk(cc)
	# Deduplicate global array: rebuild from per-chunk if infinite, else append
	if infinite_world:
		# Rebuild global from per-chunk to prevent duplicates
		var new_global: Array = []
		for b_arr in tree_chunks_blocks.values():
			new_global.append_array(b_arr)
		# Also need to add current blocks that may not be in per-chunk blocks yet (if blocks array provided)
		# For simplicity if blocks provided, ensure per-chunk blocks contain them
		for b in blocks:
			var pos = b["pos"] as Vector3i
			var cc = Vector2i(int(floor(float(pos.x) / float(chunk_size))), int(floor(float(pos.z) / float(chunk_size))))
			if not tree_chunks_blocks.has(cc):
				tree_chunks_blocks[cc] = []
			var already = false
			for existing in tree_chunks_blocks[cc]:
				if existing["pos"] == pos:
					already = true
					break
			if not already:
				tree_chunks_blocks[cc].append(b)
				new_global.append(b)
		tree_blocks = new_global
	else:
		# Finite: just append but avoid duplicates via fast check already
		for b in blocks:
			var exists = tree_block_fast.has(b["pos"]) and tree_blocks.any(func(item): return item["pos"] == b["pos"])
			# Actually fast already merged, just need to avoid duplicate in array
			var dup = false
			for existing in tree_blocks:
				if existing["pos"] == b["pos"]:
					dup = true
					break
			if not dup:
				tree_blocks.append(b)

func apply_tree_chunk_for_coord(coord: Vector2i, tree_data: Dictionary):
	if generated_tree_chunks.has(coord):
		return # dedup: already generated
	var fast = tree_data.get("tree_block_fast", {}) as Dictionary
	var blocks = tree_data.get("tree_blocks", []) as Array
	if fast.is_empty() and blocks.is_empty():
		generated_tree_chunks[coord] = true
		_touch_terrain_chunk(coord)
		return
	# Deduplicate against existing global trees to prevent cross-chunk leaf overlap duplicates
	var filtered_fast: Dictionary = {}
	var filtered_blocks: Array = []
	var seen_pos: Dictionary = {}
	for b in blocks:
		var pos = b.get("pos", null)
		if pos == null:
			continue
		if seen_pos.has(pos):
			continue
		if tree_block_fast.has(pos):
			continue
		seen_pos[pos] = true
		filtered_blocks.append(b)
	# Build filtered fast from filtered blocks to ensure consistency, or use provided fast filtered
	for b in filtered_blocks:
		var p = b["pos"] as Vector3i
		var t = b["type"]
		filtered_fast[p] = t
	# If fast contained entries not in blocks (should not), include those that are not duplicate
	for k in fast.keys():
		if filtered_fast.has(k):
			continue
		if tree_block_fast.has(k):
			continue
		if seen_pos.has(k):
			continue
		filtered_fast[k] = fast[k]
		# Also add to blocks if not already
		filtered_blocks.append({"pos": k, "type": fast[k]})

	tree_chunks_fast[coord] = filtered_fast
	tree_chunks_blocks[coord] = filtered_blocks
	for k in filtered_fast.keys():
		tree_block_fast[k] = filtered_fast[k]
	tree_blocks.append_array(filtered_blocks)
	generated_tree_chunks[coord] = true
	_touch_terrain_chunk(coord)
	# No auto-prune - ChunkManager is sole eviction owner

func _base_terrain_type_at(x: int, y: int, z: int):
	if infinite_world:
		var key = Vector2i(x, z)
		if not height_map_dict.has(key) or not type_map_dict.has(key):
			ensure_column_generated(x, z)
			if not height_map_dict.has(key) or not type_map_dict.has(key):
				return null
		var h = height_map_dict[key]
		if y < 0:
			return null
		# Water layer: only inside lake/river areas to avoid global ocean
		if y > h:
			if y <= water_level and h < water_level:
				if _generator_ref:
					var has_water = false
					if _generator_ref.has_method("_get_lake_factor_fast"):
						if _generator_ref._get_lake_factor_fast(x, z) > 0.01:
							has_water = true
					if not has_water and _generator_ref.has_method("_get_river_factor_fast"):
						if _generator_ref._get_river_factor_fast(x, z) > 0.01:
							has_water = true
					if has_water:
						return BlockId.Type.WATER
				else:
					if type_map_dict.get(key, -1) == BlockId.Type.SAND:
						return BlockId.Type.WATER
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
		if x >= height_map.size() or z >= height_map[x].size():
			return null
		var h = height_map[x][z]
		if y < 0:
			return null
		if y > h:
			if y <= water_level and h < water_level:
				# Finite: water only if type is SAND (lake/lowland) to avoid flooding everything
				if x < type_map.size() and z < type_map[x].size():
					if type_map[x][z] == BlockId.Type.SAND:
						return BlockId.Type.WATER
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
			# Also remove from per-chunk index
			var cc = Vector2i(int(floor(float(p.x) / float(chunk_size))), int(floor(float(p.z) / float(chunk_size))))
			if tree_chunks_fast.has(cc):
				tree_chunks_fast[cc].erase(p)
				# Remove from blocks array for that chunk
				if tree_chunks_blocks.has(cc):
					var arr = tree_chunks_blocks[cc] as Array
					var new_arr: Array = []
					for b in arr:
						if b["pos"] != p:
							new_arr.append(b)
					tree_chunks_blocks[cc] = new_arr
			# Rebuild global blocks array
			var new_global: Array = []
			for b_arr in tree_chunks_blocks.values():
				new_global.append_array(b_arr)
			tree_blocks = new_global

	if torch_attachments.has(p):
		torch_attachments.erase(p)

	_invalidate_highest_cache(p.x, p.z)
	var rev = _increment_revision(p)
	var edit = BlockEdit.success_mine(p, old_id, rev, prev_rev)
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
		# Allow replacing water or other replaceable blocks (e.g., water can be replaced by solid)
		var existing_id = get_block_id_at(p)
		if existing_id != BlockId.Type.AIR:
			var existing_def = BlockCatalog.shared().get_definition(existing_id)
			if existing_def == null or not existing_def.is_replaceable:
				# Special case: water is replaceable, allow solid to replace it
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
		if not infinite_world:
			if support_pos.x < 0 or support_pos.x >= world_size or support_pos.z < 0 or support_pos.z >= world_size:
				return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_TORCH_SUPPORT, "Support out of bounds")
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
					if wy <= water_level and base_h < water_level:
						# Only fill water if column is sand or lake/river influence
						var has_water = false
						if base_top_t == BlockId.Type.SAND:
							has_water = true
						else:
							if _generator_ref:
								if _generator_ref.has_method("_get_lake_factor_fast"):
									if _generator_ref._get_lake_factor_fast(wx, wz) > 0.01:
										has_water = true
								if not has_water and _generator_ref.has_method("_get_river_factor_fast"):
									if _generator_ref._get_river_factor_fast(wx, wz) > 0.01:
										has_water = true
						if has_water:
							cache[idx] = BlockId.Type.WATER
						else:
							cache[idx] = -1
					else:
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

# Optimized snapshot using per-chunk indexing to avoid scanning all tree blocks
func snapshot_edits_for_chunk(origin_x: int, origin_z: int, p_chunk_size: int) -> Dictionary:
	var ox_min = origin_x - 2
	var ox_max = origin_x + p_chunk_size + 1
	var oz_min = origin_z - 2
	var oz_max = origin_z + p_chunk_size + 1
	var placed_snap: Dictionary = {}
	var removed_snap: Dictionary = {}
	for pos in placed_blocks.keys():
		if pos is Vector3i:
			if pos.x >= ox_min and pos.x <= ox_max and pos.z >= oz_min and pos.z <= oz_max and pos.y < max_build_y:
				placed_snap[pos] = placed_blocks[pos]
	for pos in removed_blocks.keys():
		if pos is Vector3i:
			if pos.x >= ox_min and pos.x <= ox_max and pos.z >= oz_min and pos.z <= oz_max:
				removed_snap[pos] = true
	# Use per-chunk index for trees: O(k) where k is trees in nearby chunks, not O(total trees)
	var tree_snap: Dictionary = {}
	var c_min_x = int(floor(float(ox_min) / float(chunk_size)))
	var c_max_x = int(floor(float(ox_max) / float(chunk_size)))
	var c_min_z = int(floor(float(oz_min) / float(chunk_size)))
	var c_max_z = int(floor(float(oz_max) / float(chunk_size)))
	for cx in range(c_min_x - 1, c_max_x + 2):
		for cz in range(c_min_z - 1, c_max_z + 2):
			var chunk_coord = Vector2i(cx, cz)
			if not tree_chunks_fast.has(chunk_coord):
				continue
			var fast = tree_chunks_fast[chunk_coord] as Dictionary
			for pos in fast.keys():
				if pos is Vector3i:
					if pos.x >= ox_min and pos.x <= ox_max and pos.z >= oz_min and pos.z <= oz_max:
						tree_snap[pos] = fast[pos]
	return {"placed": placed_snap, "removed": removed_snap, "trees": tree_snap}

func unload_chunk_data(cx: int, cz: int):
	if not infinite_world:
		return
	_evict_chunk_data(cx, cz, true)

func has_trees_in_chunk(cx: int, cz: int) -> bool:
	if not infinite_world:
		return true
	var coord = Vector2i(cx, cz)
	if generated_tree_chunks.has(coord):
		return true
	var ox = cx * chunk_size
	var oz = cz * chunk_size
	var cs = chunk_size
	var meadow_radius = 24.0
	if Vector2(ox + cs*0.5, oz + cs*0.5).length() < meadow_radius - 2.0:
		return true
	return false

func is_chunk_data_available(cx: int, cz: int) -> bool:
	# Use complete generation marker rather than single origin column test
	var coord = Vector2i(cx, cz)
	if generated_terrain_chunks.has(coord):
		return true
	# Fallback: check LRU contains chunk (chunk-level tracking) and at least one column present
	if infinite_world:
		_terrain_lru_mutex.lock()
		var in_lru = _terrain_chunk_lru.has(coord)
		_terrain_lru_mutex.unlock()
		if in_lru:
			return true
		var origin_x = cx * chunk_size
		var origin_z = cz * chunk_size
		var key = Vector2i(origin_x, origin_z)
		return height_map_dict.has(key)
	else:
		if height_map.is_empty():
			return false
		var origin_x = cx * chunk_size
		var origin_z = cz * chunk_size
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
		"tree_chunks": tree_chunks_fast.size(),
		"generated_tree_chunks": generated_tree_chunks.size(),
		"generated_terrain_chunks": generated_terrain_chunks.size(),
		"revisions": cell_revisions.size(),
		"height_cache": _highest_cache.size(),
		"height_columns": height_map_dict.size(),
		"terrain_lru": _terrain_chunk_lru.size(),
		"max_cache": max_terrain_cache_chunks,
	}

func clear_edits():
	placed_blocks.clear()
	removed_blocks.clear()
	cell_revisions.clear()
	_highest_cache.clear()
	torch_attachments.clear()
