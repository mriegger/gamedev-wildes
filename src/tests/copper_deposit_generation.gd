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

func _test_save_omits_generated_copper(catalog: BlockCatalog) -> void:
	var slot_id := -8734
	SaveManager.delete_slot(slot_id)
	var world := VoxelWorld.new(20, 36, 5, 12.0, catalog)
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as PlayerMotor
	root.add_child(player)
	player.stats = ActorStats.new(load("res://player/player_stats.tres") as PlayerStatsDefinition)
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var inventory := InventoryModel.new(item_catalog)
	var item_proficiency := ItemProficiency.new(item_catalog)
	var save_data := {
		"seed": 1337,
		"copper_blocks": {"1,2,3": BlockId.Type.COPPER},
		"generated_copper_chunks": {"0,0": true},
	}
	_expect(SaveManager.save_world_state(slot_id, save_data, world, player, inventory, item_proficiency, 0.0, 6.0), "save manager could not write deterministic copper test save")
	_expect(not save_data.has("copper_blocks"), "in-memory save retained generated copper blocks")
	_expect(not save_data.has("generated_copper_chunks"), "in-memory save retained generated copper chunk markers")
	var saved_info := SaveManager.get_slot_info(slot_id)
	_expect(not saved_info.has("copper_blocks"), "save file retained generated copper blocks")
	_expect(not saved_info.has("generated_copper_chunks"), "save file retained generated copper chunk markers")
	SaveManager.delete_slot(slot_id)
	player.free()

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
	_test_save_omits_generated_copper(catalog)

	var generator := TerrainGenerator.new(config)
	generator.setup_noises()
	var matching_config := default_config.runtime_copy_for_seed(1337)
	matching_config.copper_deposit_chance_per_chunk = 1.0
	matching_config.copper_surface_exposure_chance = 1.0
	var matching_generator := TerrainGenerator.new(matching_config)
	matching_generator.setup_noises()
	var checked_deposits := 0
	var origin_deposit: Dictionary = {}
	var test_coords: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(2, 1), Vector2i(-2, -1)]
	for coord in test_coords:
		var origin_x: int = coord.x * config.chunk_size
		var origin_z: int = coord.y * config.chunk_size
		var base := generator.build_cache_with_generation(origin_x, origin_z, config.chunk_size, config.max_build_y, {}, {}, {}, false, {}, false)
		_expect((base["copper_block_fast"] as Dictionary).is_empty(), "base terrain pass generated copper")
		var generated := generator.build_cache_with_generation(origin_x, origin_z, config.chunk_size, config.max_build_y, {}, {}, {}, false, {}, true)
		var deposit := generated["copper_block_fast"] as Dictionary
		var matching := matching_generator.build_cache_with_generation(origin_x, origin_z, matching_config.chunk_size, matching_config.max_build_y, {}, {}, {}, false, {}, true)
		_expect(deposit == (matching["copper_block_fast"] as Dictionary), "identical world seeds generated different copper at %s" % coord)
		if coord == Vector2i.ZERO:
			origin_deposit = deposit.duplicate()
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
		var saved_edits := world.snapshot_block_edits()
		var decoded := SaveManager.decode_world_state({
			"seed": 1337,
			"copper_blocks": {"999,9,999": BlockId.Type.COPPER},
			"generated_copper_chunks": {"49,49": true},
			"removed_blocks": SaveManager.serialize_vector3i_dict(saved_edits["removed"]),
		})
		var regenerated := matching_generator.build_cache_with_generation(origin_x, origin_z, matching_config.chunk_size, matching_config.max_build_y, decoded.placed_blocks, decoded.removed_blocks, {}, false, {}, true)
		_expect((regenerated["copper_block_fast"] as Dictionary) == deposit, "save reload changed the deterministic deposit layout")
		_expect(_cache_block(regenerated, first_position) == -1, "save reload restored mined copper in rebuilt chunk data")
		var restored_world := VoxelWorld.new(config.chunk_size, config.max_build_y, config.water_level, config.meadow_radius, catalog)
		restored_world.apply_chunk_gen_for_coord(coord, regenerated)
		restored_world.apply_copper_chunk_for_coord(coord, regenerated)
		restored_world.restore_block_edits(decoded.placed_blocks, decoded.removed_blocks)
		_expect(restored_world.get_block_id_at(first_position) == BlockId.Type.AIR, "save reload lost a mined copper removal")
		world.max_terrain_cache_chunks = 0
		_expect(world.prune_terrain_cache(1) == 1, "generated copper chunk was not evicted with terrain")
		_expect(not world.generated_copper_chunks.has(coord), "evicted chunk retained its copper generation marker")
		_expect(not world.copper_chunks_fast.has(coord), "evicted chunk retained its copper index")
		_expect(not world.copper_block_fast.has(first_position), "evicted chunk retained generated copper blocks")
		var reload_edits := world.snapshot_edits_for_chunk(origin_x, origin_z)
		var reloaded := generator.build_cache_with_generation(origin_x, origin_z, config.chunk_size, config.max_build_y, reload_edits["placed"], reload_edits["removed"], reload_edits["trees"], false, reload_edits["copper"], not world.generated_copper_chunks.has(coord))
		_expect((reloaded["copper_block_fast"] as Dictionary) == deposit, "evicted chunk regenerated a different deposit")
		_expect(_cache_block(reloaded, first_position) == -1, "evicted chunk rebuild restored mined copper")
		world.apply_chunk_gen_for_coord(coord, reloaded)
		world.apply_copper_chunk_for_coord(coord, reloaded)
		_expect(world.generated_copper_chunks.has(coord), "reloaded chunk did not restore its copper generation marker")
		_expect(world.get_block_id_at(first_position) == BlockId.Type.AIR, "reloaded chunk restored mined copper")
		var unmined_position := deposit.keys()[1] as Vector3i
		_expect(world.get_block_id_at(unmined_position) == BlockId.Type.COPPER, "reloaded chunk lost unmined copper")

	_expect(checked_deposits >= 4, "too few dry chunks produced deposits during forced generation")
	var different_config := default_config.runtime_copy_for_seed(7331)
	different_config.copper_deposit_chance_per_chunk = 1.0
	different_config.copper_surface_exposure_chance = 1.0
	var different_generator := TerrainGenerator.new(different_config)
	different_generator.setup_noises()
	var different_seed_deposit := different_generator.build_cache_with_generation(0, 0, different_config.chunk_size, different_config.max_build_y, {}, {}, {}, false, {}, true)["copper_block_fast"] as Dictionary
	_expect(different_seed_deposit != origin_deposit, "different world seeds generated the same origin deposit")
	if _failures == 0:
		print("COPPER_DEPOSITS PASS deposits=%d" % checked_deposits)
		quit(0)
	else:
		print("COPPER_DEPOSITS FAIL failures=%d" % _failures)
		quit(1)
