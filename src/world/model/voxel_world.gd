extends VoxelSpace
class_name VoxelWorld

signal block_edit_committed(edit: BlockEdit)
signal foliage_visibility_changed(cells: Array[Vector3i])
signal terrain_chunk_evicted(coord: Vector2i)

const MAXIMUM_TRANSACTION_MUTATION_HISTORY: int = 256

var chunk_size: int
var max_build_y: int
var water_level: int
var spawn_search_radius: float

var type_map_dict: Dictionary = {}
var height_map_dict: Dictionary = {}

var _generator_ref: TerrainGenerator = null

var tree_block_fast: Dictionary = {}
var tree_chunks_fast: Dictionary = {}
var generated_tree_chunks: Dictionary = {}
var generated_terrain_chunks: Dictionary = {}
var copper_block_fast: Dictionary = {}
var copper_chunks_fast: Dictionary = {}
var generated_copper_chunks: Dictionary = {}
var _foliage_block_fast: Dictionary = {}
var _foliage_chunks_fast: Dictionary = {}

var _terrain_chunk_lru: Dictionary = {}
var max_terrain_cache_chunks: int = 257
var _terrain_lru_mutex: Mutex = Mutex.new()

var _placed_blocks: Dictionary = {}
var _removed_blocks: Dictionary = {}
var _placed_edits_by_chunk: Dictionary = {}
var _removed_edits_by_chunk: Dictionary = {}
var _foliage_clearance_cells: Dictionary = {}
var _foliage_clearance_by_chunk: Dictionary = {}
var cell_revisions: Dictionary = {}
var _highest_cache: Dictionary = {}
var torch_attachments: Dictionary = {}
var _emplacement_block_by_anchor: Dictionary = {}
var _emplacement_blocks_by_chunk: Dictionary = {}
var _emplacement_anchor_by_cell: Dictionary = {}
var _emplacement_anchors_by_support_cell: Dictionary = {}
var _protected_edit_cells: Dictionary = {}
var _transaction_sequence: int = 0
var _transaction_eviction_watermark: int = 0
var _transaction_history_positions: Array[Vector3i] = []
var _transaction_history_sequences: Array[int] = []
var _transaction_history_cursor: int = 0
var _latest_transaction_sequences: Dictionary = {}

func _init(p_chunk_size: int, p_max_build_y: int, p_water_level: int, p_spawn_search_radius: float, p_block_catalog: BlockCatalog):
	chunk_size = p_chunk_size
	max_build_y = p_max_build_y
	water_level = p_water_level
	spawn_search_radius = p_spawn_search_radius
	block_catalog = p_block_catalog

func set_generator_ref(gen: TerrainGenerator):
	_generator_ref = gen

func restore_block_edits(p_placed_blocks: Dictionary, p_removed_blocks: Dictionary) -> void:
	_invalidate_prepared_transactions()
	_placed_blocks = p_placed_blocks.duplicate()
	_removed_blocks = p_removed_blocks.duplicate()
	_rebuild_edit_index(_placed_blocks, _placed_edits_by_chunk)
	_rebuild_edit_index(_removed_blocks, _removed_edits_by_chunk)

func restore_emplacements(emplacements: Dictionary) -> bool:
	_invalidate_prepared_transactions()
	_clear_emplacements()
	for anchor in emplacements:
		if not anchor is Vector3i:
			_clear_emplacements()
			return false
		var block_id := int(emplacements[anchor])
		if not BlockId.is_valid(block_id):
			_clear_emplacements()
			return false
		var definition := block_catalog.get_definition(block_id)
		if definition.emplacement == null:
			_clear_emplacements()
			return false
		_ensure_emplacement_columns_generated(anchor, definition.emplacement)
		if not can_place_emplacement(anchor, block_id):
			_clear_emplacements()
			return false
		_index_emplacement(anchor, block_id)
	return true

func _ensure_emplacement_columns_generated(anchor: Vector3i, emplacement: BlockEmplacementDefinition) -> void:
	var minimum := Vector2i.ZERO
	var maximum := Vector2i.ZERO
	for offset in emplacement.occupied_offsets + emplacement.support_offsets:
		minimum = Vector2i(mini(minimum.x, offset.x), mini(minimum.y, offset.z))
		maximum = Vector2i(maxi(maximum.x, offset.x), maxi(maximum.y, offset.z))
	ensure_region_generated(
		anchor.x + minimum.x,
		anchor.z + minimum.y,
		maximum.x - minimum.x + 1,
		maximum.y - minimum.y + 1,
	)

func _clear_emplacements() -> void:
	_emplacement_block_by_anchor.clear()
	_emplacement_blocks_by_chunk.clear()
	_emplacement_anchor_by_cell.clear()
	_emplacement_anchors_by_support_cell.clear()

func snapshot_emplacements() -> Dictionary:
	return _emplacement_block_by_anchor.duplicate()

func snapshot_block_edits() -> Dictionary:
	return {
		"placed": _placed_blocks.duplicate(),
		"removed": _removed_blocks.duplicate(),
	}

func get_tree_blocks_for_chunk(coord: Vector2i) -> Dictionary:
	if not tree_chunks_fast.has(coord):
		return {}
	var live_blocks: Dictionary = {}
	for position in tree_chunks_fast[coord]:
		var block_id := int(tree_chunks_fast[coord][position])
		if get_block_id_at(position) == block_id:
			live_blocks[position] = block_id
	return live_blocks

func get_foliage_blocks_for_chunk(coord: Vector2i) -> Dictionary:
	if not _foliage_chunks_fast.has(coord):
		return {}
	return (_foliage_chunks_fast[coord] as Dictionary).duplicate()

func has_generated_foliage(position: Vector3i) -> bool:
	return _foliage_block_fast.has(position)

func get_visible_foliage_cells_for_chunk(coord: Vector2i) -> PackedInt32Array:
	var candidates: Dictionary = {}
	if _foliage_chunks_fast.has(coord):
		for position in _foliage_chunks_fast[coord]:
			candidates[position] = true
	if _placed_edits_by_chunk.has(coord):
		for position in _placed_edits_by_chunk[coord]:
			if BlockId.is_foliage(int(_placed_blocks[position])):
				candidates[position] = true
	var visible_foliage: Dictionary = {}
	for position in candidates:
		var block_id := get_block_id_at(position)
		if BlockId.is_foliage(block_id):
			visible_foliage[position] = block_id
	return FoliageCellSnapshot.pack(visible_foliage, coord.x * chunk_size, coord.y * chunk_size, chunk_size, chunk_size, max_build_y)

func get_terrain_height(x: int, z: int) -> int:
	return int(height_map_dict.get(Vector2i(x, z), -1))

func get_block_edit_count() -> int:
	return _placed_blocks.size() + _removed_blocks.size() + _emplacement_block_by_anchor.size()

func has_persisted_edit(position: Vector3i) -> bool:
	return _placed_blocks.has(position) or _removed_blocks.has(position) or torch_attachments.has(position) or _emplacement_anchor_by_cell.has(position)

func protect_edit_cells(cells: Array[Vector3i]) -> void:
	for cell in cells:
		_protected_edit_cells[cell] = true

func is_edit_protected(position: Vector3i) -> bool:
	return _protected_edit_cells.has(position)

func _rebuild_edit_index(edits: Dictionary, index: Dictionary) -> void:
	index.clear()
	for pos in edits:
		var coord := ChunkCoord.world_to_chunk_vec3i(pos, chunk_size)
		if not index.has(coord):
			index[coord] = {}
		var chunk_edits := index[coord] as Dictionary
		chunk_edits[pos] = edits[pos]

func _put_indexed_edit(edits: Dictionary, index: Dictionary, pos: Vector3i, value: Variant) -> void:
	edits[pos] = value
	var coord := ChunkCoord.world_to_chunk_vec3i(pos, chunk_size)
	if not index.has(coord):
		index[coord] = {}
	var chunk_edits := index[coord] as Dictionary
	chunk_edits[pos] = value

func _erase_indexed_edit(edits: Dictionary, index: Dictionary, pos: Vector3i) -> void:
	edits.erase(pos)
	var coord := ChunkCoord.world_to_chunk_vec3i(pos, chunk_size)
	if not index.has(coord):
		return
	var chunk_edits := index[coord] as Dictionary
	chunk_edits.erase(pos)
	if chunk_edits.is_empty():
		index.erase(coord)

func configure_terrain_cache(render_dist: int, unload_padding: int):
	var keep = render_dist + unload_padding
	var touched_area = ((keep + 1) * 2 + 1) * ((keep + 1) * 2 + 1)
	max_terrain_cache_chunks = touched_area + 128

func _touch_terrain_chunk(coord: Vector2i):
	_terrain_lru_mutex.lock()
	if _terrain_chunk_lru.has(coord):
		_terrain_chunk_lru.erase(coord)
	_terrain_chunk_lru[coord] = true
	_terrain_lru_mutex.unlock()
	generated_terrain_chunks[coord] = true

func prune_terrain_cache(max_to_evict: int) -> int:
	_terrain_lru_mutex.lock()
	if _terrain_chunk_lru.size() <= max_terrain_cache_chunks:
		_terrain_lru_mutex.unlock()
		return 0
	var to_remove = _terrain_chunk_lru.size() - max_terrain_cache_chunks
	to_remove = min(to_remove, max_to_evict)
	var to_evict: Array[Vector2i] = []
	for key in _terrain_chunk_lru:
		var coord = key as Vector2i
		to_evict.append(coord)
		if to_evict.size() >= to_remove:
			break
	for coord in to_evict:
		_terrain_chunk_lru.erase(coord)
	_terrain_lru_mutex.unlock()

	var evicted: Array[Vector2i] = []
	var foliage_visibility_changes: Dictionary = {}
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
				if BlockId.is_foliage(get_block_id_at(tree_pos)):
					foliage_visibility_changes[tree_pos] = true
			tree_chunks_fast.erase(coord)
		generated_tree_chunks.erase(coord)
		if copper_chunks_fast.has(coord):
			var chunk_copper := copper_chunks_fast[coord] as Dictionary
			for copper_pos in chunk_copper:
				copper_block_fast.erase(copper_pos)
			copper_chunks_fast.erase(coord)
		generated_copper_chunks.erase(coord)
		if _foliage_chunks_fast.has(coord):
			var chunk_foliage := _foliage_chunks_fast[coord] as Dictionary
			for foliage_pos in chunk_foliage:
				_foliage_block_fast.erase(foliage_pos)
			_foliage_chunks_fast.erase(coord)
		evicted.append(coord)

	var changed_foliage_cells: Array[Vector3i] = []
	for position in foliage_visibility_changes:
		if BlockId.is_foliage(get_block_id_at(position as Vector3i)):
			changed_foliage_cells.append(position as Vector3i)
	if not changed_foliage_cells.is_empty():
		foliage_visibility_changed.emit(changed_foliage_cells)
	for coord in evicted:
		terrain_chunk_evicted.emit(coord)
	return evicted.size()

func ensure_column_generated(x: int, z: int):
	if _generator_ref == null:
		return
	var key = Vector2i(x, z)
	if height_map_dict.has(key) and type_map_dict.has(key):
		return
	var column = _generator_ref.compute_column_at_world(x, z)
	height_map_dict[key] = column.x
	type_map_dict[key] = column.y
	var cc = Vector2i(int(floor(float(x) / float(chunk_size))), int(floor(float(z) / float(chunk_size))))
	_touch_terrain_chunk(cc)

func ensure_region_generated(origin_x: int, origin_z: int, size_x: int, size_z: int):
	if _generator_ref == null:
		return
	for x in range(origin_x, origin_x+size_x):
		for z in range(origin_z, origin_z+size_z):
			ensure_column_generated(x, z)

func apply_chunk_gen(chunk_data: Dictionary):
	var h_dict = chunk_data.get("height", {}) as Dictionary
	var t_dict = chunk_data.get("type", {}) as Dictionary
	var counts: Dictionary = {}
	for k in h_dict.keys():
		height_map_dict[k] = h_dict[k]
		if k is Vector2i:
			var cc = Vector2i(int(floor(float(k.x) / float(chunk_size))), int(floor(float(k.y) / float(chunk_size))))
			counts[cc] = counts.get(cc, 0) + 1
	for k in t_dict.keys():
		type_map_dict[k] = t_dict[k]
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
	var changed_foliage_cells: Array[Vector3i] = []
	for k in fast.keys():
		if k is Vector3i:
			var foliage_was_visible := BlockId.is_foliage(get_block_id_at(k))
			tree_block_fast[k] = fast[k]
			var cc = Vector2i(int(floor(float(k.x) / float(chunk_size))), int(floor(float(k.z) / float(chunk_size))))
			if not tree_chunks_fast.has(cc):
				tree_chunks_fast[cc] = {}
			tree_chunks_fast[cc][k] = fast[k]
			generated_tree_chunks[cc] = true
			_touch_terrain_chunk(cc)
			if foliage_was_visible and not BlockId.is_foliage(get_block_id_at(k)):
				changed_foliage_cells.append(k)
	if not changed_foliage_cells.is_empty():
		foliage_visibility_changed.emit(changed_foliage_cells)

func apply_tree_chunk_for_coord(coord: Vector2i, tree_data: Dictionary):
	if generated_tree_chunks.has(coord):
		return
	var fast = tree_data.get("tree_block_fast", {}) as Dictionary
	if fast.is_empty():
		generated_tree_chunks[coord] = true
		return
	var changed_foliage_cells: Array[Vector3i] = []
	for k in fast.keys():
		if k is Vector3i:
			var foliage_was_visible := BlockId.is_foliage(get_block_id_at(k))
			tree_block_fast[k] = fast[k]
			if not tree_chunks_fast.has(coord):
				tree_chunks_fast[coord] = {}
			tree_chunks_fast[coord][k] = fast[k]
			if foliage_was_visible and not BlockId.is_foliage(get_block_id_at(k)):
				changed_foliage_cells.append(k)
	generated_tree_chunks[coord] = true
	if not changed_foliage_cells.is_empty():
		foliage_visibility_changed.emit(changed_foliage_cells)

func apply_copper_chunk_for_coord(coord: Vector2i, copper_data: Dictionary):
	if generated_copper_chunks.has(coord):
		return
	var fast := copper_data.get("copper_block_fast", {}) as Dictionary
	var chunk_copper: Dictionary = {}
	for position in fast:
		if position is Vector3i:
			copper_block_fast[position] = fast[position]
			chunk_copper[position] = fast[position]
	if not chunk_copper.is_empty():
		copper_chunks_fast[coord] = chunk_copper
	generated_copper_chunks[coord] = true

func apply_foliage_chunk_for_coord(coord: Vector2i, foliage_data: Dictionary) -> void:
	if _foliage_chunks_fast.has(coord):
		var previous_foliage := _foliage_chunks_fast[coord] as Dictionary
		for position in previous_foliage:
			_foliage_block_fast.erase(position)
		_foliage_chunks_fast.erase(coord)
	var fast := foliage_data.get("foliage_block_fast", {}) as Dictionary
	var chunk_foliage: Dictionary = {}
	for position in fast:
		if position is Vector3i:
			_foliage_block_fast[position] = fast[position]
			chunk_foliage[position] = fast[position]
	if not chunk_foliage.is_empty():
		_foliage_chunks_fast[coord] = chunk_foliage

func get_block_at(p: Vector3i):
	if _emplacement_anchor_by_cell.has(p):
		return _emplacement_block_by_anchor[_emplacement_anchor_by_cell[p]]
	if _placed_blocks.has(p):
		return _placed_blocks[p]
	if _removed_blocks.has(p):
		return null
	if tree_block_fast.has(p):
		return tree_block_fast[p]
	if copper_block_fast.has(p):
		return copper_block_fast[p]
	if _foliage_block_fast.has(p):
		if _foliage_clearance_cells.has(p):
			return null
		return _foliage_block_fast[p]
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
	if _emplacement_anchor_by_cell.has(p):
		var anchor := _emplacement_anchor_by_cell[p] as Vector3i
		var definition := block_catalog.get_definition(int(_emplacement_block_by_anchor[anchor]))
		return definition.emplacement.is_solid_offset(p - anchor)
	var bt = get_block_at(p)
	if bt == null:
		return false
	return block_catalog.is_solid(bt)

func is_opaque(p: Vector3i) -> bool:
	var bt = get_block_at(p)
	if bt == null:
		return false
	return block_catalog.is_opaque(bt)

func is_raycast_solid(p: Vector3i) -> bool:
	var bt = get_block_at(p)
	if bt == null:
		return false
	return block_catalog.is_raycast_solid(bt)

func is_face_targetable(_block_position: Vector3i, _face_normal: Vector3i) -> bool:
	return true

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
	return block_catalog.is_breakable(bt)

func _invalidate_highest_cache(x: int, z: int):
	_highest_cache.erase(Vector2i(x, z))

func get_highest_solid_y(x: int, z: int) -> int:
	var key = Vector2i(x, z)
	if _highest_cache.has(key):
		return _highest_cache[key]
	for y in range(max_build_y - 1, -1, -1):
		var p = Vector3i(x, y, z)
		if is_solid(p):
			_highest_cache[key] = y
			return y
	_highest_cache[key] = -1
	return -1

func get_highest_top(x: int, z: int) -> float:
	var y = get_highest_solid_y(x, z)
	if y == -1:
		return NO_SURFACE_Y
	return float(y) + 1.0
func get_terrain_surface_y(x: int, z: int) -> float:
	var height: Variant = height_map_dict.get(Vector2i(x, z), null)
	return float(height) if height is int else NO_SURFACE_Y

func get_terrain_surface_top(x: int, z: int) -> float:
	ensure_column_generated(x, z)
	var height: Variant = height_map_dict.get(Vector2i(x, z), null)
	if height == null:
		return NO_SURFACE_Y
	return float(height as int) + 1.0

func get_terrain_surface_block_id(x: int, z: int) -> int:
	ensure_column_generated(x, z)
	return int(type_map_dict.get(Vector2i(x, z), BlockId.Type.AIR))

func is_occupied(p: Vector3i) -> bool:
	var bt = get_block_at(p)
	return bt != null and bt != BlockId.Type.AIR and bt != BlockId.Type.WATER

func get_attached_torches(support_pos: Vector3i) -> Array[Vector3i]:
	var attached: Array[Vector3i] = []
	for attach_dir in TorchPlacement.CARDINAL_DIRECTIONS:
		var torch_pos = support_pos - attach_dir
		if torch_attachments.get(torch_pos, Vector3i.ZERO) == attach_dir:
			attached.append(torch_pos)
	return attached

func get_emplacement_anchor(position: Vector3i) -> Variant:
	return _emplacement_anchor_by_cell.get(position, null)

func get_emplacement_cells(anchor: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	if not _emplacement_block_by_anchor.has(anchor):
		return cells
	var definition := block_catalog.get_definition(int(_emplacement_block_by_anchor[anchor]))
	for offset in definition.emplacement.occupied_offsets:
		cells.append(anchor + offset)
	return cells

func get_emplacement_bounds(anchor: Vector3i) -> AABB:
	var cells := get_emplacement_cells(anchor)
	if cells.is_empty():
		return AABB(Vector3(anchor), Vector3.ONE)
	var minimum := cells[0]
	var maximum := cells[0]
	for cell in cells:
		minimum = Vector3i(mini(minimum.x, cell.x), mini(minimum.y, cell.y), mini(minimum.z, cell.z))
		maximum = Vector3i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y), maxi(maximum.z, cell.z))
	return AABB(Vector3(minimum), Vector3(maximum - minimum + Vector3i.ONE))

func get_supported_emplacements(support_position: Vector3i) -> Array[Vector3i]:
	var anchors: Array[Vector3i] = []
	var indexed := _emplacement_anchors_by_support_cell.get(support_position, {}) as Dictionary
	for anchor in indexed:
		anchors.append(anchor as Vector3i)
	anchors.sort_custom(_vector3i_less)
	return anchors

func get_emplacements_for_chunk(cx: int, cz: int) -> Dictionary:
	return (_emplacement_blocks_by_chunk.get(Vector2i(cx, cz), {}) as Dictionary).duplicate()

func can_place_emplacement(anchor: Vector3i, block_id: int) -> bool:
	return _evaluate_place_emplacement(anchor, block_id) is PreparedVoxelWorldChange

func _get_unreplaced_generated_foliage_id(p: Vector3i) -> int:
	if _placed_blocks.has(p) or _removed_blocks.has(p) or _emplacement_anchor_by_cell.has(p):
		return BlockId.Type.AIR
	return int(_foliage_block_fast.get(p, BlockId.Type.AIR))

func _effective_mined_block_id(p: Vector3i) -> int:
	var block_id := get_block_id_at(p)
	if block_id == BlockId.Type.AIR:
		var generated_foliage_id := _get_unreplaced_generated_foliage_id(p)
		if BlockId.is_foliage(generated_foliage_id):
			return generated_foliage_id
	return block_id

func _get_foliage_above(support_pos: Vector3i) -> Variant:
	var foliage_pos := support_pos + Vector3i.UP
	var foliage_id := get_block_id_at(foliage_pos)
	return foliage_pos if BlockId.is_foliage(foliage_id) or BlockId.is_foliage(_get_unreplaced_generated_foliage_id(foliage_pos)) else null

func _erase_foliage_block(p: Vector3i) -> void:
	if not _foliage_block_fast.has(p):
		return
	_foliage_block_fast.erase(p)
	var coord := ChunkCoord.world_to_chunk_vec3i(p, chunk_size)
	if not _foliage_chunks_fast.has(coord):
		return
	var chunk_foliage := _foliage_chunks_fast[coord] as Dictionary
	chunk_foliage.erase(p)
	if chunk_foliage.is_empty():
		_foliage_chunks_fast.erase(coord)

func _foliage_clearance_is_valid(cells: Array[Vector3i]) -> bool:
	var unique_cells: Dictionary = {}
	for position in cells:
		if position.y < 0 or position.y >= max_build_y or unique_cells.has(position) or is_edit_protected(position):
			return false
		unique_cells[position] = true
	return true

func can_replace_foliage_clearance(cells: Array[Vector3i]) -> bool:
	return _foliage_clearance_is_valid(cells)

func try_replace_foliage_clearance(cells: Array[Vector3i]) -> bool:
	if not _foliage_clearance_is_valid(cells):
		return false
	var next_cells: Dictionary = {}
	for position in cells:
		next_cells[position] = true
	var changed_cells: Array[Vector3i] = []
	for position_value in _foliage_clearance_cells.keys():
		var position := position_value as Vector3i
		if next_cells.has(position):
			continue
		_erase_indexed_edit(_foliage_clearance_cells, _foliage_clearance_by_chunk, position)
		changed_cells.append(position)
	for position_value in next_cells:
		var position := position_value as Vector3i
		if _foliage_clearance_cells.has(position):
			continue
		_put_indexed_edit(_foliage_clearance_cells, _foliage_clearance_by_chunk, position, true)
		changed_cells.append(position)
	if changed_cells.is_empty():
		return true
	for position in changed_cells:
		_increment_revision(position)
		_record_transaction_mutation(position)
	foliage_visibility_changed.emit(changed_cells)
	return true

func is_foliage_clearance_reserved(position: Vector3i) -> bool:
	return _foliage_clearance_cells.has(position)

func prepare_mine_block(p: Vector3i) -> PreparedVoxelWorldChange:
	var evaluated: Variant = _evaluate_mine_block(p)
	return evaluated as PreparedVoxelWorldChange

func prepare_place_block(
	p: Vector3i,
	block_type: int,
	attach_dir: Vector3i = Vector3i.ZERO,
) -> PreparedVoxelWorldChange:
	var evaluated: Variant = _evaluate_place_block(p, block_type, attach_dir)
	return evaluated as PreparedVoxelWorldChange

func prepare_place_emplacement(anchor: Vector3i, block_id: int) -> PreparedVoxelWorldChange:
	var evaluated: Variant = _evaluate_place_emplacement(anchor, block_id)
	return evaluated as PreparedVoxelWorldChange

func can_place_block(p: Vector3i, block_type: int, attach_dir: Vector3i = Vector3i.ZERO) -> bool:
	return _evaluate_place_block(p, block_type, attach_dir) is PreparedVoxelWorldChange

func prepare_replace_block(
	p: Vector3i,
	expected_old_id: int,
	new_id: int,
) -> PreparedVoxelWorldChange:
	var evaluated: Variant = _evaluate_replace_block(p, expected_old_id, new_id)
	return evaluated as PreparedVoxelWorldChange

func can_commit_prepared_change(prepared: PreparedVoxelWorldChange) -> bool:
	if prepared == null or not prepared._is_for(self) or not prepared._is_prepared():
		return false
	var expected_transaction_sequence := prepared._get_expected_transaction_sequence()
	if expected_transaction_sequence < _transaction_eviction_watermark:
		return false
	var expected_revisions := prepared._get_expected_revisions()
	for position in expected_revisions:
		if int(_latest_transaction_sequences.get(position, 0)) > expected_transaction_sequence:
			return false
		if get_revision(position) != int(expected_revisions[position]):
			return false
	var expected_contents := prepared._get_expected_contents()
	for position in expected_contents:
		if _snapshot_transaction_cell(position) != expected_contents[position]:
			return false
	return true

func commit_prepared_changes(prepared_changes: Array[PreparedVoxelWorldChange]) -> bool:
	if prepared_changes.is_empty():
		return false
	var edited_by_change: Dictionary = {}
	for prepared in prepared_changes:
		if not can_commit_prepared_change(prepared):
			return false
		for edit in prepared.get_edits():
			if edited_by_change.has(edit.pos):
				return false
			edited_by_change[edit.pos] = prepared
	for prepared in prepared_changes:
		for position in prepared._get_expected_revisions():
			if edited_by_change.has(position) and edited_by_change[position] != prepared:
				return false
	for prepared in prepared_changes:
		var committed := _commit_prepared_change(prepared, false)
		assert(committed)
	for prepared in prepared_changes:
		var notified := _notify_prepared_change(prepared)
		assert(notified)
	return true

func _commit_prepared_change(
	prepared: PreparedVoxelWorldChange,
	emit_signals: bool = true,
) -> bool:
	if not can_commit_prepared_change(prepared):
		return false
	match prepared._get_operation():
		BlockEdit.Operation.MINE:
			_apply_prepared_mine(prepared)
		BlockEdit.Operation.PLACE:
			_apply_prepared_place(prepared)
		BlockEdit.Operation.REPLACE:
			_apply_prepared_replace(prepared)
		_:
			return false
	var marked := prepared._mark_committed(self)
	assert(marked)
	if emit_signals:
		var notified := _notify_prepared_change(prepared)
		assert(notified)
	return true

func _notify_prepared_change(prepared: PreparedVoxelWorldChange) -> bool:
	if prepared == null or not prepared._mark_notified(self):
		return false
	for edit in prepared._copy_committed_edits():
		block_edit_committed.emit(edit)
	return true

func _evaluate_mine_block(p: Vector3i) -> Variant:
	var emplacement_anchor: Variant = get_emplacement_anchor(p)
	if emplacement_anchor is Vector3i:
		return _evaluate_mine_emplacement(emplacement_anchor)
	if is_edit_protected(p):
		return BlockEdit.fail(p, BlockEdit.Operation.MINE, BlockEdit.Result.FAIL_PROTECTED)
	var attached_torches := get_attached_torches(p)
	for torch_position in attached_torches:
		if is_edit_protected(torch_position):
			return BlockEdit.fail(p, BlockEdit.Operation.MINE, BlockEdit.Result.FAIL_PROTECTED)
	var supported_emplacements := get_supported_emplacements(p)
	for anchor in supported_emplacements:
		for cell in get_emplacement_cells(anchor):
			if is_edit_protected(cell):
				return BlockEdit.fail(p, BlockEdit.Operation.MINE, BlockEdit.Result.FAIL_PROTECTED)
	var foliage_above: Variant = _get_foliage_above(p)
	if foliage_above != null and is_edit_protected(foliage_above as Vector3i):
		return BlockEdit.fail(p, BlockEdit.Operation.MINE, BlockEdit.Result.FAIL_PROTECTED)
	if not is_breakable(p):
		return BlockEdit.fail(p, BlockEdit.Operation.MINE, BlockEdit.Result.FAIL_NOT_BREAKABLE)
	var expected_revisions: Dictionary = {p: get_revision(p)}
	var expected_contents: Dictionary = {p: _snapshot_transaction_cell(p)}
	for attach_dir in TorchPlacement.CARDINAL_DIRECTIONS:
		var candidate_position := p - attach_dir
		expected_revisions[candidate_position] = get_revision(candidate_position)
		expected_contents[candidate_position] = _snapshot_transaction_cell(candidate_position)
	for anchor in supported_emplacements:
		for cell in get_emplacement_cells(anchor):
			expected_revisions[cell] = get_revision(cell)
			expected_contents[cell] = _snapshot_transaction_cell(cell)
	var foliage_position := p + Vector3i.UP
	expected_revisions[foliage_position] = get_revision(foliage_position)
	expected_contents[foliage_position] = _snapshot_transaction_cell(foliage_position)
	var cascade_positions: Array[Vector3i] = []
	var edits: Array[BlockEdit] = [BlockEdit.success_mine(p, _effective_mined_block_id(p), get_revision(p) + 1)]
	if foliage_above != null:
		var foliage_cell := foliage_above as Vector3i
		cascade_positions.append(foliage_cell)
		edits.append(BlockEdit.success_mine(foliage_cell, _effective_mined_block_id(foliage_cell), get_revision(foliage_cell) + 1))
	for torch_position in attached_torches:
		cascade_positions.append(torch_position)
		edits.append(BlockEdit.success_mine(
			torch_position,
			int(_placed_blocks.get(torch_position, BlockId.Type.TORCH)),
			get_revision(torch_position) + 1,
		))
	for anchor in supported_emplacements:
		cascade_positions.append(anchor)
		edits.append(BlockEdit.success_mine(
			anchor,
			int(_emplacement_block_by_anchor[anchor]),
			get_revision(anchor) + 1,
		))
	return PreparedVoxelWorldChange.new(
		self,
		expected_revisions,
		expected_contents,
		_transaction_sequence,
		BlockEdit.Operation.MINE,
		p,
		BlockId.Type.AIR,
		Vector3i.ZERO,
		cascade_positions,
		edits,
	)

func _evaluate_mine_emplacement(anchor: Vector3i) -> Variant:
	var expected_revisions: Dictionary = {}
	var expected_contents: Dictionary = {}
	for cell in get_emplacement_cells(anchor):
		if is_edit_protected(cell):
			return BlockEdit.fail(anchor, BlockEdit.Operation.MINE, BlockEdit.Result.FAIL_PROTECTED)
		expected_revisions[cell] = get_revision(cell)
		expected_contents[cell] = _snapshot_transaction_cell(cell)
	var block_id := int(_emplacement_block_by_anchor[anchor])
	if not block_catalog.is_breakable(block_id):
		return BlockEdit.fail(anchor, BlockEdit.Operation.MINE, BlockEdit.Result.FAIL_NOT_BREAKABLE)
	return PreparedVoxelWorldChange.new(
		self,
		expected_revisions,
		expected_contents,
		_transaction_sequence,
		BlockEdit.Operation.MINE,
		anchor,
		BlockId.Type.AIR,
		Vector3i.ZERO,
		[],
		[BlockEdit.success_mine(anchor, block_id, get_revision(anchor) + 1)],
	)

func _evaluate_place_block(p: Vector3i, block_type: int, attach_dir: Vector3i) -> Variant:
	if is_edit_protected(p):
		return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_PROTECTED)
	if block_type == BlockId.Type.AIR:
		return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_INVALID_POS, "AIR not placeable")
	if not BlockId.is_valid(block_type):
		return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_INVALID_POS, "Invalid block id")
	if block_catalog.get_definition(block_type).emplacement != null:
		return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_INVALID_POS, "Emplacement requires atomic placement")
	if p.y < 0 or p.y >= max_build_y:
		return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_Y_OUT_OF_RANGE)
	var existing_id := get_block_id_at(p)
	if is_occupied(p) and not block_catalog.get_definition(existing_id).is_replaceable:
		return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_OCCUPIED)
	var expected_revisions: Dictionary = {p: get_revision(p)}
	if block_type == BlockId.Type.TORCH:
		if attach_dir == Vector3i.ZERO:
			return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_SUPPORT, "Torch requires attach_dir")
		if attach_dir not in TorchPlacement.CARDINAL_DIRECTIONS:
			return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_SUPPORT, "Torch attach_dir must be cardinal")
		var support_pos := p + attach_dir
		if support_pos.y < 0 or support_pos.y >= max_build_y:
			return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_TORCH_SUPPORT, "Support Y out of bounds")
		ensure_region_generated(support_pos.x - 1, support_pos.z - 1, 3, 3)
		var support_id := get_block_id_at(support_pos)
		if support_id != BlockId.Type.AIR and block_catalog.get_definition(support_id).emplacement != null:
			return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_TORCH_SUPPORT)
		if not is_opaque(support_pos) and not is_solid(support_pos):
			return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_TORCH_SUPPORT)
		expected_revisions[support_pos] = get_revision(support_pos)
	var expected_contents: Dictionary = {p: _snapshot_transaction_cell(p)}
	if block_type == BlockId.Type.TORCH:
		expected_contents[p + attach_dir] = _snapshot_transaction_cell(p + attach_dir)
	var edit := BlockEdit.success_place(p, existing_id, block_type, get_revision(p) + 1, attach_dir)
	return PreparedVoxelWorldChange.new(
		self,
		expected_revisions,
		expected_contents,
		_transaction_sequence,
		BlockEdit.Operation.PLACE,
		p,
		block_type,
		attach_dir,
		[],
		[edit],
	)

func _evaluate_place_emplacement(anchor: Vector3i, block_id: int) -> Variant:
	if not BlockId.is_valid(block_id):
		return BlockEdit.fail(anchor, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_INVALID_POS)
	var definition := block_catalog.get_definition(block_id)
	if definition.emplacement == null:
		return BlockEdit.fail(anchor, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_INVALID_POS)
	var expected_revisions: Dictionary = {}
	var expected_contents: Dictionary = {}
	for offset in definition.emplacement.occupied_offsets:
		var cell := anchor + offset
		if cell.y < 0 or cell.y >= max_build_y or is_edit_protected(cell):
			return BlockEdit.fail(anchor, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_SUPPORT, "Emplacement requires a clear supported footprint")
		var existing_id := get_block_id_at(cell)
		if is_occupied(cell) and not block_catalog.get_definition(existing_id).is_replaceable:
			return BlockEdit.fail(anchor, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_SUPPORT, "Emplacement requires a clear supported footprint")
		expected_revisions[cell] = get_revision(cell)
		expected_contents[cell] = _snapshot_transaction_cell(cell)
	for offset in definition.emplacement.support_offsets:
		var support_cell := anchor + offset
		if support_cell.y < 0 or support_cell.y >= max_build_y or not is_solid(support_cell):
			return BlockEdit.fail(anchor, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_SUPPORT, "Emplacement requires a clear supported footprint")
		expected_revisions[support_cell] = get_revision(support_cell)
		expected_contents[support_cell] = _snapshot_transaction_cell(support_cell)
	return PreparedVoxelWorldChange.new(
		self,
		expected_revisions,
		expected_contents,
		_transaction_sequence,
		BlockEdit.Operation.PLACE,
		anchor,
		block_id,
		Vector3i.ZERO,
		[],
		[BlockEdit.success_place(anchor, get_block_id_at(anchor), block_id, get_revision(anchor) + 1, Vector3i.ZERO)],
	)

func _evaluate_replace_block(p: Vector3i, expected_old_id: int, new_id: int) -> Variant:
	if _emplacement_anchor_by_cell.has(p):
		return BlockEdit.fail(p, BlockEdit.Operation.REPLACE, BlockEdit.Result.FAIL_INVALID_POS, "Emplacement cells cannot be replaced individually")
	if not BlockId.is_valid(expected_old_id) or expected_old_id == BlockId.Type.AIR:
		return BlockEdit.fail(p, BlockEdit.Operation.REPLACE, BlockEdit.Result.FAIL_INVALID_POS, "Invalid expected block id")
	if not BlockId.is_valid(new_id) or new_id == BlockId.Type.AIR:
		return BlockEdit.fail(p, BlockEdit.Operation.REPLACE, BlockEdit.Result.FAIL_INVALID_POS, "Invalid replacement block id")
	if block_catalog.get_definition(new_id).emplacement != null:
		return BlockEdit.fail(p, BlockEdit.Operation.REPLACE, BlockEdit.Result.FAIL_INVALID_POS, "Emplacement requires atomic placement")
	if p.y < 0 or p.y >= max_build_y:
		return BlockEdit.fail(p, BlockEdit.Operation.REPLACE, BlockEdit.Result.FAIL_Y_OUT_OF_RANGE)
	if get_block_id_at(p) != expected_old_id:
		return BlockEdit.fail(p, BlockEdit.Operation.REPLACE, BlockEdit.Result.FAIL_BLOCK_CHANGED)
	var edit := BlockEdit.success_replace(p, expected_old_id, new_id, get_revision(p) + 1)
	return PreparedVoxelWorldChange.new(
		self,
		{p: get_revision(p)},
		{p: _snapshot_transaction_cell(p)},
		_transaction_sequence,
		BlockEdit.Operation.REPLACE,
		p,
		new_id,
		Vector3i.ZERO,
		[],
		[edit],
	)

func _apply_prepared_mine(prepared: PreparedVoxelWorldChange) -> void:
	var p := prepared._get_position()
	if _emplacement_block_by_anchor.has(p):
		_remove_emplacement_state(p)
	else:
		_apply_prepared_mined_cell(p)
	for position in prepared._get_cascade_positions():
		if _emplacement_block_by_anchor.has(position):
			_remove_emplacement_state(position)
		else:
			_apply_prepared_mined_cell(position)

func _apply_prepared_mined_cell(p: Vector3i) -> void:
	var old_id := _effective_mined_block_id(p)
	var was_placed := _placed_blocks.has(p)
	var surviving_after := _removed_blocks.has(p)
	if was_placed:
		_erase_indexed_edit(_placed_blocks, _placed_edits_by_chunk, p)
		var column_key := Vector2i(p.x, p.z)
		var terrain_height := height_map_dict.get(column_key, -1) as int
		if terrain_height != -1 and p.y <= terrain_height:
			_put_indexed_edit(_removed_blocks, _removed_edits_by_chunk, p, true)
			surviving_after = true
	else:
		_put_indexed_edit(_removed_blocks, _removed_edits_by_chunk, p, true)
		surviving_after = true
		if tree_block_fast.has(p):
			tree_block_fast.erase(p)
			var tree_coord := ChunkCoord.world_to_chunk_vec3i(p, chunk_size)
			if tree_chunks_fast.has(tree_coord):
				(tree_chunks_fast[tree_coord] as Dictionary).erase(p)
		if BlockId.is_foliage(old_id):
			_erase_foliage_block(p)
	if torch_attachments.has(p):
		torch_attachments.erase(p)
	_invalidate_highest_cache(p.x, p.z)
	if surviving_after:
		_increment_revision(p)
	else:
		cell_revisions.erase(p)
	_record_transaction_mutation(p)

func _apply_prepared_place(prepared: PreparedVoxelWorldChange) -> void:
	var p := prepared._get_position()
	var block_type := prepared._get_new_id()
	var block_definition := block_catalog.get_definition(block_type)
	if block_definition.emplacement != null:
		for offset in block_definition.emplacement.occupied_offsets:
			_clear_foliage_for_placement(p + offset)
		_index_emplacement(p, block_type)
		for cell in get_emplacement_cells(p):
			_invalidate_highest_cache(cell.x, cell.z)
			_increment_revision(cell)
			_record_transaction_mutation(cell)
		return
	var replaced_foliage := _clear_foliage_for_placement(p)
	if not replaced_foliage and _removed_blocks.has(p):
		var terrain_height := height_map_dict.get(Vector2i(p.x, p.z), -1) as int
		if terrain_height == -1 or p.y <= terrain_height:
			_erase_indexed_edit(_removed_blocks, _removed_edits_by_chunk, p)
	_put_indexed_edit(_placed_blocks, _placed_edits_by_chunk, p, block_type)
	if block_type == BlockId.Type.TORCH:
		torch_attachments[p] = prepared._get_attach_dir()
	_invalidate_highest_cache(p.x, p.z)
	_increment_revision(p)
	_record_transaction_mutation(p)

func _clear_foliage_for_placement(p: Vector3i) -> bool:
	var replaced_id := get_block_id_at(p)
	var generated_foliage_id := _get_unreplaced_generated_foliage_id(p)
	if not BlockId.is_foliage(replaced_id) and not BlockId.is_foliage(generated_foliage_id):
		return false
	_erase_indexed_edit(_placed_blocks, _placed_edits_by_chunk, p)
	_put_indexed_edit(_removed_blocks, _removed_edits_by_chunk, p, true)
	_erase_foliage_block(p)
	return true

func _remove_emplacement_state(anchor: Vector3i) -> void:
	var block_id := int(_emplacement_block_by_anchor[anchor])
	var definition := block_catalog.get_definition(block_id)
	for offset in definition.emplacement.support_offsets:
		var support_cell := anchor + offset
		var indexed := _emplacement_anchors_by_support_cell.get(support_cell, {}) as Dictionary
		indexed.erase(anchor)
		if indexed.is_empty():
			_emplacement_anchors_by_support_cell.erase(support_cell)
	for cell in get_emplacement_cells(anchor):
		_emplacement_anchor_by_cell.erase(cell)
		_invalidate_highest_cache(cell.x, cell.z)
		_increment_revision(cell)
		_record_transaction_mutation(cell)
	var coord := ChunkCoord.world_to_chunk_vec3i(anchor, chunk_size)
	var chunk_emplacements := _emplacement_blocks_by_chunk.get(coord, {}) as Dictionary
	chunk_emplacements.erase(anchor)
	if chunk_emplacements.is_empty():
		_emplacement_blocks_by_chunk.erase(coord)
	_emplacement_block_by_anchor.erase(anchor)

func _index_emplacement(anchor: Vector3i, block_id: int) -> void:
	_emplacement_block_by_anchor[anchor] = block_id
	var coord := ChunkCoord.world_to_chunk_vec3i(anchor, chunk_size)
	if not _emplacement_blocks_by_chunk.has(coord):
		_emplacement_blocks_by_chunk[coord] = {}
	(_emplacement_blocks_by_chunk[coord] as Dictionary)[anchor] = block_id
	var definition := block_catalog.get_definition(block_id)
	for offset in definition.emplacement.occupied_offsets:
		_emplacement_anchor_by_cell[anchor + offset] = anchor
	for offset in definition.emplacement.support_offsets:
		var support_cell := anchor + offset
		if not _emplacement_anchors_by_support_cell.has(support_cell):
			_emplacement_anchors_by_support_cell[support_cell] = {}
		(_emplacement_anchors_by_support_cell[support_cell] as Dictionary)[anchor] = true

func _vector3i_less(left: Vector3i, right: Vector3i) -> bool:
	if left.x != right.x:
		return left.x < right.x
	if left.y != right.y:
		return left.y < right.y
	return left.z < right.z

func _apply_prepared_replace(prepared: PreparedVoxelWorldChange) -> void:
	var p := prepared._get_position()
	var new_id := prepared._get_new_id()
	_put_indexed_edit(_placed_blocks, _placed_edits_by_chunk, p, new_id)
	_erase_indexed_edit(_removed_blocks, _removed_edits_by_chunk, p)
	_invalidate_highest_cache(p.x, p.z)
	_increment_revision(p)
	_record_transaction_mutation(p)

func _record_transaction_mutation(position: Vector3i) -> void:
	_transaction_sequence += 1
	if _transaction_history_positions.size() < MAXIMUM_TRANSACTION_MUTATION_HISTORY:
		_transaction_history_positions.append(position)
		_transaction_history_sequences.append(_transaction_sequence)
	else:
		var evicted_position := _transaction_history_positions[_transaction_history_cursor]
		var evicted_sequence := _transaction_history_sequences[_transaction_history_cursor]
		if int(_latest_transaction_sequences.get(evicted_position, 0)) == evicted_sequence:
			_latest_transaction_sequences.erase(evicted_position)
		_transaction_eviction_watermark = evicted_sequence
		_transaction_history_positions[_transaction_history_cursor] = position
		_transaction_history_sequences[_transaction_history_cursor] = _transaction_sequence
	_latest_transaction_sequences[position] = _transaction_sequence
	_transaction_history_cursor = (
		_transaction_history_cursor + 1
	) % MAXIMUM_TRANSACTION_MUTATION_HISTORY

func _invalidate_prepared_transactions() -> void:
	_transaction_sequence += 1
	_transaction_eviction_watermark = _transaction_sequence
	_transaction_history_positions.clear()
	_transaction_history_sequences.clear()
	_transaction_history_cursor = 0
	_latest_transaction_sequences.clear()

func _snapshot_transaction_cell(position: Vector3i) -> Dictionary:
	var column := Vector2i(position.x, position.z)
	var emplacement_anchor: Variant = _emplacement_anchor_by_cell.get(position, null)
	return {
		"block_id": get_block_id_at(position),
		"has_placed_edit": _placed_blocks.has(position),
		"placed_edit": _placed_blocks.get(position, null),
		"has_removed_edit": _removed_blocks.has(position),
		"has_tree_block": tree_block_fast.has(position),
		"tree_block": tree_block_fast.get(position, null),
		"has_copper_block": copper_block_fast.has(position),
		"copper_block": copper_block_fast.get(position, null),
		"has_foliage_block": _foliage_block_fast.has(position),
		"foliage_block": _foliage_block_fast.get(position, null),
		"has_foliage_clearance": _foliage_clearance_cells.has(position),
		"torch_attachment": torch_attachments.get(position, Vector3i.ZERO),
		"emplacement_anchor": emplacement_anchor,
		"emplacement_block": _emplacement_block_by_anchor.get(emplacement_anchor, null),
		"protected": is_edit_protected(position),
		"terrain_height": height_map_dict.get(column, null),
		"terrain_type": type_map_dict.get(column, null),
	}

func get_spawn_position() -> Vector3:
	var meadow_radius_squared = spawn_search_radius * spawn_search_radius
	var best = Vector3(0.5, 10.5, 0.5)
	var best_score = 9999.0
	for dx in range(-int(spawn_search_radius), int(spawn_search_radius) + 1):
		for dz in range(-int(spawn_search_radius), int(spawn_search_radius) + 1):
			var x = dx
			var z = dz
			if x * x + z * z > meadow_radius_squared:
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

func snapshot_edits_for_chunk(origin_x: int, origin_z: int) -> Dictionary:
	var ox_min = origin_x - 2
	var ox_max = origin_x + chunk_size + 1
	var oz_min = origin_z - 2
	var oz_max = origin_z + chunk_size + 1
	var min_coord := ChunkCoord.world_to_chunk_vec3i(Vector3i(ox_min, 0, oz_min), chunk_size)
	var max_coord := ChunkCoord.world_to_chunk_vec3i(Vector3i(ox_max, 0, oz_max), chunk_size)
	var placed_snap: Dictionary = {}
	var removed_snap: Dictionary = {}
	var foliage_clearance_snap: Dictionary = {}
	_copy_indexed_edits(_placed_edits_by_chunk, placed_snap, min_coord, max_coord, ox_min, ox_max, oz_min, oz_max)
	_copy_indexed_edits(_foliage_clearance_by_chunk, foliage_clearance_snap, min_coord, max_coord, ox_min, ox_max, oz_min, oz_max)
	_copy_indexed_edits(_removed_edits_by_chunk, removed_snap, min_coord, max_coord, ox_min, ox_max, oz_min, oz_max)
	var tree_snap: Dictionary = {}
	var copper_snap: Dictionary = {}
	for cx in range(min_coord.x, max_coord.x + 1):
		for cz in range(min_coord.y, max_coord.y + 1):
			var c = Vector2i(cx, cz)
			if tree_chunks_fast.has(c):
				var tree_dict = tree_chunks_fast[c] as Dictionary
				for pos in tree_dict.keys():
					if pos is Vector3i:
						if pos.x >= ox_min and pos.x <= ox_max and pos.z >= oz_min and pos.z <= oz_max:
							tree_snap[pos] = tree_dict[pos]
			if copper_chunks_fast.has(c):
				var copper_dict = copper_chunks_fast[c] as Dictionary
				for pos in copper_dict:
					if pos is Vector3i and pos.x >= ox_min and pos.x <= ox_max and pos.z >= oz_min and pos.z <= oz_max:
						copper_snap[pos] = copper_dict[pos]
	return {"placed": placed_snap, "removed": removed_snap, "foliage_clearance": foliage_clearance_snap, "trees": tree_snap, "copper": copper_snap}

func _copy_indexed_edits(index: Dictionary, target: Dictionary, min_coord: Vector2i, max_coord: Vector2i, min_x: int, max_x: int, min_z: int, max_z: int) -> void:
	for cx in range(min_coord.x, max_coord.x + 1):
		for cz in range(min_coord.y, max_coord.y + 1):
			var coord := Vector2i(cx, cz)
			if not index.has(coord):
				continue
			var chunk_edits := index[coord] as Dictionary
			for pos in chunk_edits:
				if pos.x >= min_x and pos.x <= max_x and pos.z >= min_z and pos.z <= max_z:
					target[pos] = chunk_edits[pos]

func is_chunk_data_available(cx: int, cz: int) -> bool:
	var coord = Vector2i(cx, cz)
	return generated_terrain_chunks.has(coord)
