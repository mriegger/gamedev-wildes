extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var config := (load("res://world/settings/world_config.tres") as WorldConfig).runtime_copy_for_seed(1337)
	var catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var foliage_catalog := load("res://foliage/foliage_catalog.tres") as FoliageCatalog
	var generator := TerrainGenerator.new(config, FoliageGenerator.new(foliage_catalog, config.seed_value))
	var initial_generation := generator.generate_all()
	var initial_trees := initial_generation["tree_block_fast"] as Dictionary
	_expect(initial_trees.is_empty(), "startup terrain generated a tree layout outside the chunk pipeline")

	var model := VoxelWorld.new(config.chunk_size, config.max_build_y, config.water_level, config.meadow_radius, catalog)
	model.set_generator_ref(generator)
	model.apply_chunk_gen(initial_generation)
	model.apply_tree_chunk(initial_generation)

	var center := Vector2i.ZERO
	var coords := ChunkCoord.sort_by_distance(ChunkCoord.get_chunks_in_radius_infinite(center, config.render_distance), center)
	var mineable_log := Vector3i(-999, -999, -999)
	var log_owner := Vector2i.ZERO
	var rendered_tree_blocks := 0
	for coord in coords:
		var origin_x := coord.x * config.chunk_size
		var origin_z := coord.y * config.chunk_size
		var edits := model.snapshot_edits_for_chunk(origin_x, origin_z)
		var payload := generator.build_cache_with_generation(
			origin_x,
			origin_z,
			config.chunk_size,
			config.max_build_y,
			edits["placed"],
			edits["removed"],
			edits["trees"],
			false
		)
		var rendered_trees := payload["tree_block_fast"] as Dictionary
		model.apply_chunk_gen_for_coord(coord, payload)
		model.apply_tree_chunk_for_coord(coord, payload)
		for position in rendered_trees:
			rendered_tree_blocks += 1
			_expect(model.get_block_id_at(position) == rendered_trees[position], "rendered tree block %s was absent from the voxel model" % position)
			if mineable_log.x == -999 and rendered_trees[position] == BlockId.Type.LOG:
				mineable_log = position
				log_owner = coord

	_expect(rendered_tree_blocks > 0, "test world generated no chunk trees")
	_expect(mineable_log.x != -999, "test world generated no mineable log")
	if mineable_log.x != -999:
		_expect(model.is_raycast_solid(mineable_log), "rendered log was invisible to voxel targeting")
		_expect(model.is_breakable(mineable_log), "rendered log was not mineable")
		var mined := VoxelWorldTestFixture.commit_mine(model, mineable_log)
		_expect(mined != null and not mined.get_edits().is_empty(), "rendered log could not be mined")
		_expect(model.get_block_id_at(mineable_log) == BlockId.Type.AIR, "mined log remained in the voxel model")

		var rebuild_origin_x := log_owner.x * config.chunk_size
		var rebuild_origin_z := log_owner.y * config.chunk_size
		var rebuild_edits := model.snapshot_edits_for_chunk(rebuild_origin_x, rebuild_origin_z)
		var rebuilt := generator.build_cache_with_generation(
			rebuild_origin_x,
			rebuild_origin_z,
			config.chunk_size,
			config.max_build_y,
			rebuild_edits["placed"],
			rebuild_edits["removed"],
			rebuild_edits["trees"],
			false
		)
		var rebuilt_cache := rebuilt["cache_dict"] as Dictionary
		var rebuilt_blocks := rebuilt_cache["cache"] as PackedInt32Array
		var rebuilt_cache_z := rebuilt_cache["cache_z"] as int
		var rebuilt_size_y := rebuilt_cache["size_y"] as int
		var rebuilt_local_x := mineable_log.x - rebuild_origin_x + 1
		var rebuilt_local_z := mineable_log.z - rebuild_origin_z + 1
		var rebuilt_index := rebuilt_local_x * rebuilt_size_y * rebuilt_cache_z + mineable_log.y * rebuilt_cache_z + rebuilt_local_z
		_expect(rebuilt_blocks[rebuilt_index] == -1, "chunk rebuild restored a mined log")

	if _failures.is_empty():
		print("TREE_TARGETING PASS rendered_tree_blocks=%d" % rendered_tree_blocks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
