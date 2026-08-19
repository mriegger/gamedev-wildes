extends VoxelSpace
class_name VoxelWorld

signal block_edit_committed(edit: BlockEdit)
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

var _terrain_chunk_lru: Dictionary = {}
var max_terrain_cache_chunks: int = 257
var _terrain_lru_mutex: Mutex = Mutex.new()

var _placed_blocks: Dictionary = {}
var _removed_blocks: Dictionary = {}
var _placed_edits_by_chunk: Dictionary = {}
var _removed_edits_by_chunk: Dictionary = {}
var cell_revisions: Dictionary = {}
var _highest_cache: Dictionary = {}
var torch_attachments: Dictionary = {}
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

func snapshot_block_edits() -> Dictionary:
	return {
		"placed": _placed_blocks.duplicate(),
		"removed": _removed_blocks.duplicate(),
	}

func get_tree_blocks_for_chunk(coord: Vector2i) -> Dictionary:
	if not tree_chunks_fast.has(coord):
		return {}
	return (tree_chunks_fast[coord] as Dictionary).duplicate()

func get_terrain_height(x: int, z: int) -> int:
	return int(height_map_dict.get(Vector2i(x, z), -1))

func get_block_edit_count() -> int:
	return _placed_blocks.size() + _removed_blocks.size()

func has_persisted_edit(position: Vector3i) -> bool:
	return _placed_blocks.has(position) or _removed_blocks.has(position) or torch_attachments.has(position)

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
		if copper_chunks_fast.has(coord):
			var chunk_copper := copper_chunks_fast[coord] as Dictionary
			for copper_pos in chunk_copper:
				copper_block_fast.erase(copper_pos)
			copper_chunks_fast.erase(coord)
		generated_copper_chunks.erase(coord)
		evicted.append(coord)

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

func get_block_at(p: Vector3i):
	if _placed_blocks.has(p):
		return _placed_blocks[p]
	if _removed_blocks.has(p):
		return null
	if tree_block_fast.has(p):
		return tree_block_fast[p]
	if copper_block_fast.has(p):
		return copper_block_fast[p]
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

func is_face_targetable(block_position: Vector3i, _face_normal: Vector3i) -> bool:
	return is_raycast_solid(block_position)

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
		var bt = get_block_at(p)
		if bt != null and block_catalog.is_solid(bt):
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
	if is_edit_protected(p):
		return BlockEdit.fail(p, BlockEdit.Operation.MINE, BlockEdit.Result.FAIL_PROTECTED)
	for torch_position in get_attached_torches(p):
		if is_edit_protected(torch_position):
			return BlockEdit.fail(p, BlockEdit.Operation.MINE, BlockEdit.Result.FAIL_PROTECTED)
	if not is_breakable(p):
		return BlockEdit.fail(p, BlockEdit.Operation.MINE, BlockEdit.Result.FAIL_NOT_BREAKABLE)
	var attached_torches := get_attached_torches(p)
	var expected_revisions: Dictionary = {p: get_revision(p)}
	var expected_contents: Dictionary = {p: _snapshot_transaction_cell(p)}
	for attach_dir in TorchPlacement.CARDINAL_DIRECTIONS:
		var candidate_position := p - attach_dir
		expected_revisions[candidate_position] = get_revision(candidate_position)
		expected_contents[candidate_position] = _snapshot_transaction_cell(candidate_position)
	var edits: Array[BlockEdit] = [BlockEdit.success_mine(p, get_block_id_at(p), get_revision(p) + 1)]
	for torch_position in attached_torches:
		edits.append(BlockEdit.success_mine(
			torch_position,
			int(_placed_blocks.get(torch_position, BlockId.Type.TORCH)),
			get_revision(torch_position) + 1,
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
		attached_torches,
		edits,
	)

func _evaluate_place_block(p: Vector3i, block_type: int, attach_dir: Vector3i) -> Variant:
	if is_edit_protected(p):
		return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_PROTECTED)
	if block_type == BlockId.Type.AIR:
		return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_INVALID_POS, "AIR not placeable")
	if not BlockId.is_valid(block_type):
		return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_INVALID_POS, "Invalid block id")
	if p.y < 0 or p.y >= max_build_y:
		return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_Y_OUT_OF_RANGE)
	if is_occupied(p):
		var existing_id = get_block_id_at(p)
		if not block_catalog.get_definition(existing_id).is_replaceable:
			return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_OCCUPIED)
	var expected_revisions: Dictionary = {p: get_revision(p)}
	if block_type == BlockId.Type.TORCH:
		if attach_dir == Vector3i.ZERO:
			return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_SUPPORT, "Torch requires attach_dir")
		if attach_dir not in TorchPlacement.CARDINAL_DIRECTIONS:
			return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_SUPPORT, "Torch attach_dir must be cardinal")
		var support_pos = p + attach_dir
		if support_pos.y < 0 or support_pos.y >= max_build_y:
			return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_TORCH_SUPPORT, "Support Y out of bounds")
		ensure_region_generated(support_pos.x -1, support_pos.z -1, 3, 3)
		if not is_opaque(support_pos) and not is_solid(support_pos):
			return BlockEdit.fail(p, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NO_TORCH_SUPPORT)
		expected_revisions[support_pos] = get_revision(support_pos)
	var expected_contents: Dictionary = {p: _snapshot_transaction_cell(p)}
	if block_type == BlockId.Type.TORCH:
		expected_contents[p + attach_dir] = _snapshot_transaction_cell(p + attach_dir)
	var edit := BlockEdit.success_place(p, block_type, get_revision(p) + 1, attach_dir)
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

func _evaluate_replace_block(p: Vector3i, expected_old_id: int, new_id: int) -> Variant:
	if not BlockId.is_valid(expected_old_id) or expected_old_id == BlockId.Type.AIR:
		return BlockEdit.fail(p, BlockEdit.Operation.REPLACE, BlockEdit.Result.FAIL_INVALID_POS, "Invalid expected block id")
	if not BlockId.is_valid(new_id) or new_id == BlockId.Type.AIR:
		return BlockEdit.fail(p, BlockEdit.Operation.REPLACE, BlockEdit.Result.FAIL_INVALID_POS, "Invalid replacement block id")
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
	var was_placed = _placed_blocks.has(p)
	var surviving_after := false
	if was_placed:
		_erase_indexed_edit(_placed_blocks, _placed_edits_by_chunk, p)
		var col_key = Vector2i(p.x, p.z)
		var h = height_map_dict.get(col_key, -1) as int
		if h != -1 and p.y <= h:
			_put_indexed_edit(_removed_blocks, _removed_edits_by_chunk, p, true)
			surviving_after = true
	else:
		_put_indexed_edit(_removed_blocks, _removed_edits_by_chunk, p, true)
		surviving_after = true
		if tree_block_fast.has(p):
			tree_block_fast.erase(p)
			var cc = Vector2i(int(floor(float(p.x) / float(chunk_size))), int(floor(float(p.z) / float(chunk_size))))
			if tree_chunks_fast.has(cc):
				tree_chunks_fast[cc].erase(p)
	if torch_attachments.has(p):
		torch_attachments.erase(p)
	_invalidate_highest_cache(p.x, p.z)
	if surviving_after:
		_increment_revision(p)
	else:
		cell_revisions.erase(p)
	_record_transaction_mutation(p)
	for torch_pos in prepared._get_cascade_positions():
		_erase_indexed_edit(_placed_blocks, _placed_edits_by_chunk, torch_pos)
		torch_attachments.erase(torch_pos)
		_invalidate_highest_cache(torch_pos.x, torch_pos.z)
		cell_revisions.erase(torch_pos)
		_record_transaction_mutation(torch_pos)

func _apply_prepared_place(prepared: PreparedVoxelWorldChange) -> void:
	var p := prepared._get_position()
	var block_type := prepared._get_new_id()
	if _removed_blocks.has(p):
		_erase_indexed_edit(_removed_blocks, _removed_edits_by_chunk, p)
	_put_indexed_edit(_placed_blocks, _placed_edits_by_chunk, p, block_type)
	if block_type == BlockId.Type.TORCH:
		torch_attachments[p] = prepared._get_attach_dir()
	_invalidate_highest_cache(p.x, p.z)
	_increment_revision(p)
	_record_transaction_mutation(p)

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
	return {
		"block_id": get_block_id_at(position),
		"has_placed_edit": _placed_blocks.has(position),
		"placed_edit": _placed_blocks.get(position, null),
		"has_removed_edit": _removed_blocks.has(position),
		"has_tree_block": tree_block_fast.has(position),
		"tree_block": tree_block_fast.get(position, null),
		"has_copper_block": copper_block_fast.has(position),
		"copper_block": copper_block_fast.get(position, null),
		"torch_attachment": torch_attachments.get(position, Vector3i.ZERO),
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
	_copy_indexed_edits(_placed_edits_by_chunk, placed_snap, min_coord, max_coord, ox_min, ox_max, oz_min, oz_max)
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
	return {"placed": placed_snap, "removed": removed_snap, "trees": tree_snap, "copper": copper_snap}

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
