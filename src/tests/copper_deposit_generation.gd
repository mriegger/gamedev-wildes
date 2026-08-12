extends SceneTree

var _failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[copper_deposit_generation] FAIL: %s" % message)

func _cache_block(payload: Dictionary, position: Vector3i) -> int:
	var cache_data := payload["cache_dict"] as Dictionary
	var cache := cache_data["cache"] as PackedInt32Array
	var lx := position.x - (cache_data["origin_x"] as int) + 1
	var lz := position.z - (cache_data["origin_z"] as int) + 1
	var index := lx * (cache_data["size_y"] as int) * (cache_data["cache_z"] as int)
	index += position.y * (cache_data["cache_z"] as int) + lz
	return cache[index]

func _is_face_connected(deposit: Dictionary) -> bool:
	if deposit.is_empty():
		return false
	var pending: Array[Vector3i] = [deposit.keys()[0] as Vector3i]
	var visited: Dictionary = {pending[0]: true}
	while not pending.is_empty():
		var current: Vector3i = pending.pop_front()
		for direction_value in TerrainGenerator.COPPER_GROWTH_DIRECTIONS:
			var direction := direction_value as Vector3i
			var neighbor: Vector3i = current + direction
			if deposit.has(neighbor) and not visited.has(neighbor):
				visited[neighbor] = true
				pending.append(neighbor)
	return visited.size() == deposit.size()

func _run() -> void:
	var default_config := load("res://world/settings/world_config.tres") as WorldConfig
	_expect(is_equal_approx(default_config.copper_deposit_chance_per_chunk, 0.22), "default copper deposits are not frequent enough")
	_expect(is_equal_approx(default_config.copper_surface_exposure_chance, 0.55), "default copper deposits are not visible enough")
	var config := default_config.runtime_copy_for_seed(1337)
	config.copper_deposit_chance_per_chunk = 1.0
	config.copper_surface_exposure_chance = 1.0
	var catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	_expect(config.validate(), "test world config did not validate")
	_expect(catalog.validate(), "block catalog did not validate")
	var copper_definition := catalog.get_definition(BlockId.Type.COPPER)
	_expect(copper_definition.drop_item_id == &"copper", "copper block does not drop the copper item")
	_expect(copper_definition.mining_tool_tag == &"pickaxe", "copper block does not require a pickaxe")
	_expect(copper_definition.minimum_mining_power == 1, "copper mining power is not one")

	var generator := TerrainGenerator.new(config)
	generator.setup_noises()
	var checked_deposits := 0
	var test_coords: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(2, 1), Vector2i(-2, -1)]
	for coord in test_coords:
		var origin_x: int = coord.x * config.chunk_size
		var origin_z: int = coord.y * config.chunk_size
		var base := generator.build_cache_with_generation(origin_x, origin_z, config.chunk_size, config.max_build_y, {}, {}, {}, false, {}, false)
		_expect((base["copper_block_fast"] as Dictionary).is_empty(), "base terrain pass generated copper")
		var generated := generator.build_cache_with_generation(origin_x, origin_z, config.chunk_size, config.max_build_y, {}, {}, {}, false, {}, true)
		var deposit := generated["copper_block_fast"] as Dictionary
		if deposit.is_empty():
			continue
		checked_deposits += 1
		_expect(deposit.size() >= 5 and deposit.size() <= 30, "deposit size %d is outside 5..30" % deposit.size())
		_expect(_is_face_connected(deposit), "deposit is not a face-connected blob")
		var surface_blocks := 0
		for position in deposit:
			_expect(position.x >= origin_x and position.x < origin_x + config.chunk_size, "deposit crossed its owning chunk on X")
			_expect(position.z >= origin_z and position.z < origin_z + config.chunk_size, "deposit crossed its owning chunk on Z")
			_expect(_cache_block(base, position) in [BlockId.Type.GRASS, BlockId.Type.DIRT, BlockId.Type.SAND, BlockId.Type.STONE], "copper did not replace a terrain block")
			_expect(_cache_block(generated, position) == BlockId.Type.COPPER, "generated cache omitted a copper block")
			if position.y == (generated["height"] as Dictionary)[Vector2i(position.x, position.z)]:
				surface_blocks += 1
		_expect(surface_blocks >= 1, "forced surface exposure produced no visible outcrop")
		_expect(surface_blocks <= config.copper_max_surface_blocks, "deposit exposed too many surface blocks")
		_expect(deposit.size() - surface_blocks > surface_blocks, "deposit bulk was not underground")

		var world := VoxelWorld.new(config.chunk_size, config.max_build_y, config.water_level, config.meadow_radius, catalog)
		world.apply_chunk_gen_for_coord(coord, generated)
		world.apply_copper_chunk_for_coord(coord, generated)
		var first_position := deposit.keys()[0] as Vector3i
		_expect(world.get_block_id_at(first_position) == BlockId.Type.COPPER, "voxel model did not expose generated copper")
		var snapshot := world.snapshot_edits_for_chunk(origin_x, origin_z)
		_expect((snapshot["copper"] as Dictionary).size() == deposit.size(), "chunk snapshot did not retain its deposit")
		var rebuilt := generator.build_cache_with_generation(origin_x, origin_z, config.chunk_size, config.max_build_y, {}, {}, snapshot["trees"], false, snapshot["copper"], false)
		_expect((rebuilt["copper_block_fast"] as Dictionary).is_empty(), "chunk rebuild rerolled copper")
		for position in deposit:
			_expect(_cache_block(rebuilt, position) == BlockId.Type.COPPER, "chunk rebuild did not reuse stored copper")
		world.try_mine_block(first_position)
		_expect(world.get_block_id_at(first_position) == BlockId.Type.AIR, "mined copper remained in the world")
		_expect((world.snapshot_edits_for_chunk(origin_x, origin_z)["removed"] as Dictionary).has(first_position), "mined copper was not recorded as removed")
		var saved_copper := world.snapshot_copper_generation()
		var saved_edits := world.snapshot_block_edits()
		var decoded := SaveManager.decode_world_state({
			"seed": 1337,
			"copper_blocks": SaveManager.serialize_vector3i_dict(saved_copper["blocks"]),
			"generated_copper_chunks": SaveManager.serialize_vector2i_dict(saved_copper["chunks"]),
			"removed_blocks": SaveManager.serialize_vector3i_dict(saved_edits["removed"]),
		})
		var restored_world := VoxelWorld.new(config.chunk_size, config.max_build_y, config.water_level, config.meadow_radius, catalog)
		restored_world.apply_chunk_gen_for_coord(coord, generated)
		restored_world.restore_copper_generation(decoded.copper_blocks, decoded.generated_copper_chunks)
		restored_world.restore_block_edits(decoded.placed_blocks, decoded.removed_blocks)
		_expect(restored_world.generated_copper_chunks.has(coord), "save reload forgot the generated chunk marker")
		_expect(restored_world.copper_block_fast.size() == deposit.size(), "save reload changed the deposit layout")
		_expect(restored_world.get_block_id_at(first_position) == BlockId.Type.AIR, "save reload lost a mined copper removal")

	_expect(checked_deposits >= 4, "too few dry chunks produced deposits during forced generation")
	var first_random := generator.build_cache_with_generation(0, 0, config.chunk_size, config.max_build_y, {}, {}, {}, false, {}, true)["copper_block_fast"] as Dictionary
	var saw_random_variation := false
	for _attempt in range(4):
		var next_random := generator.build_cache_with_generation(0, 0, config.chunk_size, config.max_build_y, {}, {}, {}, false, {}, true)["copper_block_fast"] as Dictionary
		if next_random != first_random:
			saw_random_variation = true
			break
	_expect(saw_random_variation, "repeated generation reused a deterministic deposit")
	if _failures == 0:
		print("COPPER_DEPOSITS PASS deposits=%d" % checked_deposits)
		quit(0)
	else:
		print("COPPER_DEPOSITS FAIL failures=%d" % _failures)
		quit(1)
