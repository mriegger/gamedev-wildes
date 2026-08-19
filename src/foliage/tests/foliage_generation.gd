extends SceneTree

const TEST_COORDS: Array[Vector2i] = [
	Vector2i.ZERO,
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(-1, -1),
]

var _errors: Array[String] = []
var _config: WorldConfig
var _block_catalog: BlockCatalog
var _foliage_catalog: FoliageCatalog
var _generator: TerrainGenerator

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_config = (load("res://world/settings/world_config.tres") as WorldConfig).runtime_copy_for_seed(1337)
	_block_catalog = load("res://blocks/block_catalog.tres") as BlockCatalog
	_foliage_catalog = load("res://foliage/foliage_catalog.tres") as FoliageCatalog
	_expect(_config.validate(), "world config invalid")
	_expect(_block_catalog.validate(), "block catalog invalid")
	_expect(_foliage_catalog.validate(_block_catalog), "foliage catalog invalid")
	_generator = _make_generator(_config)
	var startup := _generator.generate_all()
	_expect((startup["foliage_block_fast"] as Dictionary).is_empty(), "startup generation bypassed the chunk foliage pipeline")
	var payloads: Dictionary = {}
	var total_foliage := 0
	var first_coord := Vector2i.ZERO
	var first_position := Vector3i.ZERO
	var found_first := false
	for coord in TEST_COORDS:
		var payload := _build_payload(_generator, _config, coord)
		var matching := _build_payload(_make_generator(_config), _config, coord)
		var foliage := payload["foliage_block_fast"] as Dictionary
		_expect(foliage == (matching["foliage_block_fast"] as Dictionary), "same seed changed foliage at %s" % coord)
		_validate_payload(coord, payload)
		payloads[coord] = payload
		total_foliage += foliage.size()
		if not found_first and not foliage.is_empty():
			first_coord = coord
			first_position = foliage.keys()[0] as Vector3i
			found_first = true
	_test_order_independence(payloads)
	_test_seed_variance(payloads)
	_expect(total_foliage > 0, "test region generated no foliage")
	if found_first:
		_test_atomic_foliage_clearance(first_coord, payloads[first_coord] as Dictionary)
		_test_authoritative_state(first_coord, first_position, payloads[first_coord] as Dictionary)
	if _errors.is_empty():
		print("FOLIAGE_GENERATION PASS plants=%d" % total_foliage)
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _make_generator(config: WorldConfig) -> TerrainGenerator:
	var generator := TerrainGenerator.new(config, FoliageGenerator.new(_foliage_catalog, config.seed_value))
	generator.setup_noises()
	return generator

func _build_payload(generator: TerrainGenerator, config: WorldConfig, coord: Vector2i, removed: Dictionary = {}, foliage_clearance: Dictionary = {}) -> Dictionary:
	return generator.build_cache_with_generation(
		coord.x * config.chunk_size,
		coord.y * config.chunk_size,
		config.chunk_size,
		config.max_build_y,
		{},
		removed,
		{},
		false,
		{},
		false,
		foliage_clearance
	)

func _validate_payload(coord: Vector2i, payload: Dictionary) -> void:
	var foliage := payload["foliage_block_fast"] as Dictionary
	var sparse_foliage := _sparse_foliage(payload)
	var heights := payload["height"] as Dictionary
	var types := payload["type"] as Dictionary
	var trees := payload["tree_block_fast"] as Dictionary
	var columns: Dictionary = {}
	var origin_x := coord.x * _config.chunk_size
	var origin_z := coord.y * _config.chunk_size
	_expect(foliage.size() <= _config.chunk_size * _config.chunk_size, "chunk foliage exceeded one plant per column")
	_expect(sparse_foliage == foliage, "sparse foliage mesh snapshot diverged from generated foliage")
	for position_value in foliage:
		var position := position_value as Vector3i
		var column := Vector2i(position.x, position.z)
		var block_id := int(foliage[position])
		_expect(position.x >= origin_x and position.x < origin_x + _config.chunk_size, "foliage crossed owning chunk X")
		_expect(position.z >= origin_z and position.z < origin_z + _config.chunk_size, "foliage crossed owning chunk Z")
		_expect(not columns.has(column), "column generated multiple foliage blocks")
		columns[column] = true
		_expect(BlockId.is_foliage(block_id), "generation selected a non-foliage block")
		_expect(int(types[column]) == BlockId.Type.GRASS, "foliage generated above non-grass terrain")
		var height := int(heights[column])
		_expect(position.y == height + 1, "foliage was not one cell above terrain")
		_expect(height >= _config.water_level, "foliage generated below the water level")
		_expect(position.y < _config.max_build_y, "foliage exceeded the build height")
		_expect(not trees.has(position), "foliage overlapped a tree")
		_expect(_cache_block(payload, position) == block_id, "chunk cache omitted generated foliage")

func _test_order_independence(expected_payloads: Dictionary) -> void:
	var coords := TEST_COORDS.duplicate()
	coords.reverse()
	var reverse_generator := _make_generator(_config)
	for coord in coords:
		var payload := _build_payload(reverse_generator, _config, coord)
		var expected := expected_payloads[coord] as Dictionary
		_expect((payload["foliage_block_fast"] as Dictionary) == (expected["foliage_block_fast"] as Dictionary), "chunk order changed foliage at %s" % coord)

func _test_seed_variance(expected_payloads: Dictionary) -> void:
	var other_config := (load("res://world/settings/world_config.tres") as WorldConfig).runtime_copy_for_seed(7331)
	var other_generator := _make_generator(other_config)
	var changed := false
	for coord in TEST_COORDS:
		var other_payload := _build_payload(other_generator, other_config, coord)
		var expected := expected_payloads[coord] as Dictionary
		if (other_payload["foliage_block_fast"] as Dictionary) != (expected["foliage_block_fast"] as Dictionary):
			changed = true
			break
	_expect(changed, "different world seed preserved every foliage layout")

func _test_authoritative_state(coord: Vector2i, position: Vector3i, payload: Dictionary) -> void:
	var expected_id := int((payload["foliage_block_fast"] as Dictionary)[position])
	var world := _make_world(coord, payload)
	_expect(_unpack_foliage(world.get_visible_foliage_cells_for_chunk(coord)) == _sparse_foliage(payload), "voxel model sparse foliage snapshot diverged from the generated mesh snapshot")
	_expect(world.get_block_id_at(position) == expected_id, "voxel model omitted generated foliage")
	_expect(world.get_foliage_blocks_for_chunk(coord).has(position), "foliage chunk index omitted a plant")
	_expect(not world.is_solid(position), "foliage blocked movement")
	_expect(world.is_raycast_solid(position), "foliage could not be targeted")
	var mined := VoxelWorldTestFixture.commit_mine(world, position)
	_expect(mined != null and mined.get_edits().size() == 1 and mined.get_primary_edit().is_success(), "foliage could not be mined")
	_expect(world.get_block_id_at(position) == BlockId.Type.AIR, "mined foliage remained in the world")
	_expect(not _unpack_foliage(world.get_visible_foliage_cells_for_chunk(coord)).has(position), "voxel model sparse foliage snapshot retained mined foliage")
	var saved_edits := world.snapshot_block_edits()
	var removed := saved_edits["removed"] as Dictionary
	_expect(removed.has(position), "mined foliage did not persist a removal")
	var rebuilt := _build_payload(_generator, _config, coord, removed)
	_expect((rebuilt["foliage_block_fast"] as Dictionary).has(position), "derived foliage layout changed after mining")
	_expect(_cache_block(rebuilt, position) == -1, "chunk rebuild restored mined foliage")
	_expect(not _sparse_foliage(rebuilt).has(position), "sparse foliage mesh snapshot retained mined foliage")
	var restored := _make_world(coord, rebuilt, saved_edits["placed"] as Dictionary, removed)
	_expect(restored.get_block_id_at(position) == BlockId.Type.AIR, "restored edits resurrected mined foliage")
	_test_support_removal(coord, position, payload)
	_test_foliage_replacement(coord, position, payload)
	_test_foliage_eviction(coord, position, payload)

func _test_atomic_foliage_clearance(coord: Vector2i, payload: Dictionary) -> void:
	var positions := payload["foliage_block_fast"].keys() as Array
	_expect(positions.size() >= 2, "atomic foliage fixture generated fewer than two plants")
	if positions.size() < 2:
		return
	var cells: Array[Vector3i] = [positions[0] as Vector3i, positions[1] as Vector3i]
	cells.append(cells[0] + Vector3i.UP)
	var protected_world := _make_world(coord, payload)
	protected_world.protect_edit_cells([cells[2]])
	_expect(not protected_world.can_replace_foliage_clearance(cells), "protected clearance batch passed validation")
	_expect(not protected_world.try_replace_foliage_clearance(cells), "protected clearance batch committed")
	_expect(BlockId.is_foliage(protected_world.get_block_id_at(cells[0])), "failed clearance batch partially cleared its first plant")
	_expect(BlockId.is_foliage(protected_world.get_block_id_at(cells[1])), "failed clearance batch partially cleared its second plant")
	_expect(protected_world.get_block_edit_count() == 0, "failed clearance batch persisted edits")
	var world := _make_world(coord, payload)
	_expect(world.can_replace_foliage_clearance(cells), "valid clearance batch failed validation")
	_expect(world.try_replace_foliage_clearance(cells), "valid clearance batch failed to commit")
	var removed := world.snapshot_block_edits()["removed"] as Dictionary
	for position in cells:
		_expect(world.is_foliage_clearance_reserved(position), "clearance batch omitted a reserved cell")
		_expect(world.get_block_id_at(position) == BlockId.Type.AIR, "clearance batch left a cell occupied")
		_expect(not removed.has(position), "clearance batch fabricated a block removal")
	_expect(world.get_block_edit_count() == 0, "clearance batch changed persistent block edits")
	var clearance_snapshot := world.snapshot_edits_for_chunk(coord.x * _config.chunk_size, coord.y * _config.chunk_size)
	var masked_payload := _build_payload(_generator, _config, coord, {}, clearance_snapshot["foliage_clearance"] as Dictionary)
	_expect((masked_payload["foliage_block_fast"] as Dictionary).has(cells[0]), "clearance discarded authoritative foliage state")
	_expect((masked_payload["foliage_block_fast"] as Dictionary).has(cells[1]), "clearance discarded second authoritative foliage state")
	_expect(_cache_block(masked_payload, cells[0]) == -1, "clearance left foliage in the chunk cache")
	_expect(_cache_block(masked_payload, cells[1]) == -1, "clearance left second foliage in the chunk cache")
	_expect(not _sparse_foliage(masked_payload).has(cells[0]) and not _sparse_foliage(masked_payload).has(cells[1]), "sparse foliage mesh snapshot ignored clearance")
	world.apply_foliage_chunk_for_coord(coord, masked_payload)
	_expect(world.get_block_id_at(cells[0]) == BlockId.Type.AIR, "reconciled clearance exposed hidden foliage")
	var retained_cells: Array[Vector3i] = [cells[2]]
	_expect(world.try_replace_foliage_clearance(retained_cells), "clearance replacement failed")
	_expect(not world.is_foliage_clearance_reserved(cells[0]) and not world.is_foliage_clearance_reserved(cells[1]), "clearance replacement retained stale plant cells")
	_expect(world.is_foliage_clearance_reserved(cells[2]), "clearance replacement lost its retained cell")
	_expect(BlockId.is_foliage(world.get_block_id_at(cells[0])), "clearance replacement did not restore its first plant")
	_expect(BlockId.is_foliage(world.get_block_id_at(cells[1])), "clearance replacement did not restore its second plant")
	var released_snapshot := world.snapshot_edits_for_chunk(coord.x * _config.chunk_size, coord.y * _config.chunk_size)
	var released_payload := _build_payload(_generator, _config, coord, {}, released_snapshot["foliage_clearance"] as Dictionary)
	_expect(_cache_block(released_payload, cells[0]) == int((payload["foliage_block_fast"] as Dictionary)[cells[0]]), "released foliage did not return to the chunk cache")
	_expect(_cache_block(released_payload, cells[1]) == int((payload["foliage_block_fast"] as Dictionary)[cells[1]]), "second released foliage did not return to the chunk cache")
	world.apply_foliage_chunk_for_coord(coord, released_payload)
	_expect(BlockId.is_foliage(world.get_block_id_at(cells[0])), "reconciled foliage chunk lost released foliage")
	_expect(BlockId.is_foliage(world.get_block_id_at(cells[1])), "reconciled foliage chunk lost second released foliage")
	var no_cells: Array[Vector3i] = []
	var support_world := _make_world(coord, payload)
	_expect(support_world.try_replace_foliage_clearance(cells), "support-edit clearance failed")
	var support_change := VoxelWorldTestFixture.commit_mine(support_world, cells[0] + Vector3i.DOWN)
	var support_batch: Array[BlockEdit] = []
	if support_change != null:
		support_batch = support_change.get_edits()
	_expect(support_batch.size() == 2, "masked foliage was omitted from support removal")
	_expect(BlockId.is_foliage((support_batch[1] as BlockEdit).old_id), "masked support removal emitted an AIR edit")
	_expect((support_world.snapshot_block_edits()["removed"] as Dictionary).has(cells[0]), "masked support removal was not persisted")
	_expect(support_world.try_replace_foliage_clearance(no_cells), "support-edit clearance release failed")
	_expect(support_world.get_block_id_at(cells[0]) == BlockId.Type.AIR, "support removal resurrected masked foliage")
	var placement_world := _make_world(coord, payload)
	_expect(placement_world.try_replace_foliage_clearance(cells), "placement clearance failed")
	var placed := VoxelWorldTestFixture.commit_place(placement_world, cells[1], BlockId.Type.STONE)
	_expect(placed != null and placed.get_primary_edit().is_success(), "placement into cleared foliage failed")
	_expect((placement_world.snapshot_block_edits()["removed"] as Dictionary).has(cells[1]), "placement did not consume masked foliage")
	_expect(placement_world.try_replace_foliage_clearance(no_cells), "placement clearance release failed")
	_expect(placement_world.get_block_id_at(cells[1]) == BlockId.Type.STONE, "clearance release replaced a player block")
	var mined := VoxelWorldTestFixture.commit_mine(placement_world, cells[1])
	_expect(mined != null and mined.get_primary_edit().is_success(), "player block over masked foliage could not be mined")
	_expect(placement_world.get_block_id_at(cells[1]) == BlockId.Type.AIR, "mining a player block resurrected masked foliage")

func _test_support_removal(coord: Vector2i, position: Vector3i, payload: Dictionary) -> void:
	var support := position + Vector3i.DOWN
	var protected_world := _make_world(coord, payload)
	protected_world.protect_edit_cells([position])
	var rejected := VoxelWorldTestFixture.commit_mine(protected_world, support)
	_expect(rejected == null, "protected foliage allowed partial support removal")
	_expect(protected_world.get_block_id_at(support) == BlockId.Type.GRASS, "failed support removal changed terrain")
	_expect(BlockId.is_foliage(protected_world.get_block_id_at(position)), "failed support removal changed foliage")
	var world := _make_world(coord, payload)
	var support_change := VoxelWorldTestFixture.commit_mine(world, support)
	var batch: Array[BlockEdit] = []
	if support_change != null:
		batch = support_change.get_edits()
	_expect(batch.size() == 2, "support removal did not include foliage")
	_expect((batch[0] as BlockEdit).old_id == BlockId.Type.GRASS, "support removal changed the wrong terrain block")
	_expect(BlockId.is_foliage((batch[1] as BlockEdit).old_id), "support removal omitted the foliage edit")
	_expect(world.get_block_id_at(support) == BlockId.Type.AIR, "mined foliage support remained")
	_expect(world.get_block_id_at(position) == BlockId.Type.AIR, "unsupported foliage remained")

func _test_foliage_replacement(coord: Vector2i, position: Vector3i, payload: Dictionary) -> void:
	var world := _make_world(coord, payload)
	var replaced_id := world.get_block_id_at(position)
	_expect(world.can_place_block(position, BlockId.Type.STONE), "replaceable foliage rejected block placement")
	var placed := VoxelWorldTestFixture.commit_place(world, position, BlockId.Type.STONE)
	_expect(placed != null and placed.get_primary_edit().is_success(), "placing over foliage failed")
	_expect(placed != null and placed.get_primary_edit().old_id == replaced_id, "foliage replacement edit lost the replaced block ID")
	_expect(world.get_block_id_at(position) == BlockId.Type.STONE, "placed block did not replace foliage")
	var placed_snapshot := world.snapshot_block_edits()
	_expect((placed_snapshot["placed"] as Dictionary).has(position), "foliage replacement omitted placed edit")
	_expect((placed_snapshot["removed"] as Dictionary).has(position), "foliage replacement omitted removal edit")
	var mined := VoxelWorldTestFixture.commit_mine(world, position)
	_expect(mined != null and mined.get_primary_edit().is_success(), "replacement block could not be mined")
	_expect(world.get_block_id_at(position) == BlockId.Type.AIR, "mining replacement resurrected foliage")
	_expect((world.snapshot_block_edits()["removed"] as Dictionary).has(position), "replacement mining lost foliage removal")
	var rebuilt := _build_payload(_generator, _config, coord, world.snapshot_block_edits()["removed"] as Dictionary)
	var restored := _make_world(coord, rebuilt, {}, world.snapshot_block_edits()["removed"] as Dictionary)
	_expect(restored.get_block_id_at(position) == BlockId.Type.AIR, "reloading replacement resurrected foliage")
	var mined_first := _make_world(coord, payload)
	VoxelWorldTestFixture.commit_mine(mined_first, position)
	_expect(VoxelWorldTestFixture.commit_place(mined_first, position, BlockId.Type.STONE) != null, "placement after mining foliage failed")
	VoxelWorldTestFixture.commit_mine(mined_first, position)
	var mined_first_edits := mined_first.snapshot_block_edits()
	_expect((mined_first_edits["removed"] as Dictionary).has(position), "placement cleared a mined foliage removal")
	var mined_first_payload := _build_payload(_generator, _config, coord, mined_first_edits["removed"] as Dictionary)
	var mined_first_restored := _make_world(coord, mined_first_payload, {}, mined_first_edits["removed"] as Dictionary)
	_expect(mined_first_restored.get_block_id_at(position) == BlockId.Type.AIR, "mined foliage returned after build removal and reload")

func _test_foliage_eviction(coord: Vector2i, position: Vector3i, payload: Dictionary) -> void:
	var world := _make_world(coord, payload)
	world.max_terrain_cache_chunks = 0
	_expect(world.prune_terrain_cache(1) == 1, "foliage chunk did not evict with terrain")
	_expect(not world.generated_foliage_chunks.has(coord), "eviction retained foliage generation marker")
	_expect(not world.foliage_chunks_fast.has(coord), "eviction retained foliage chunk index")
	_expect(not world.foliage_block_fast.has(position), "eviction retained foliage block state")
	var regenerated := _build_payload(_generator, _config, coord)
	world.apply_chunk_gen_for_coord(coord, regenerated)
	world.apply_tree_chunk_for_coord(coord, regenerated)
	world.apply_foliage_chunk_for_coord(coord, regenerated)
	_expect(world.get_block_id_at(position) == int((payload["foliage_block_fast"] as Dictionary)[position]), "evicted foliage regenerated differently")

func _make_world(coord: Vector2i, payload: Dictionary, placed: Dictionary = {}, removed: Dictionary = {}) -> VoxelWorld:
	var world := VoxelWorld.new(_config.chunk_size, _config.max_build_y, _config.water_level, _config.meadow_radius, _block_catalog)
	world.restore_block_edits(placed, removed)
	world.apply_chunk_gen_for_coord(coord, payload)
	world.apply_tree_chunk_for_coord(coord, payload)
	world.apply_foliage_chunk_for_coord(coord, payload)
	return world

func _cache_block(payload: Dictionary, position: Vector3i) -> int:
	var cache_data := payload["cache_dict"] as Dictionary
	var cache := cache_data["cache"] as PackedInt32Array
	var local_x := position.x - int(cache_data["origin_x"]) + 1
	var local_z := position.z - int(cache_data["origin_z"]) + 1
	var cache_z := int(cache_data["cache_z"])
	var size_y := int(cache_data["size_y"])
	return cache[local_x * size_y * cache_z + position.y * cache_z + local_z]

func _sparse_foliage(payload: Dictionary) -> Dictionary:
	var cache_data := payload["cache_dict"] as Dictionary
	var cells := cache_data["foliage_cells"] as PackedInt32Array
	var result: Dictionary = {}
	var previous_index := -1
	var origin_x := int(cache_data["origin_x"])
	var origin_z := int(cache_data["origin_z"])
	var size_y := int(cache_data["size_y"])
	_expect(cells.size() % FoliageCellSnapshot.STRIDE == 0, "sparse foliage mesh snapshot has an invalid stride")
	for offset in range(0, cells.size(), FoliageCellSnapshot.STRIDE):
		var position := Vector3i(cells[offset], cells[offset + 1], cells[offset + 2])
		var block_id := cells[offset + 3]
		var cache_index := ((position.x - origin_x) * _config.chunk_size + position.z - origin_z) * size_y + position.y
		_expect(cache_index > previous_index, "sparse foliage mesh snapshot order is unstable")
		_expect(_cache_block(payload, position) == block_id, "sparse foliage mesh snapshot differs from the final cache")
		previous_index = cache_index
		result[position] = block_id
	return result

func _unpack_foliage(cells: PackedInt32Array) -> Dictionary:
	var result: Dictionary = {}
	for offset in range(0, cells.size(), FoliageCellSnapshot.STRIDE):
		result[Vector3i(cells[offset], cells[offset + 1], cells[offset + 2])] = cells[offset + 3]
	return result

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
