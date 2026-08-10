extends SceneTree

const CHUNK_SIZE: int = 20
const MAX_BUILD_Y: int = 36

var _failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[world_edit_index] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	return VoxelWorld.new(CHUNK_SIZE, MAX_BUILD_Y, 5, 12.0, catalog)

func _reference_snapshot(edits: Dictionary, origin_x: int, origin_z: int) -> Dictionary:
	var min_x := origin_x - 2
	var max_x := origin_x + CHUNK_SIZE + 1
	var min_z := origin_z - 2
	var max_z := origin_z + CHUNK_SIZE + 1
	var placed: Dictionary = {}
	var removed: Dictionary = {}
	for pos in edits["placed"]:
		if pos.x >= min_x and pos.x <= max_x and pos.z >= min_z and pos.z <= max_z:
			placed[pos] = edits["placed"][pos]
	for pos in edits["removed"]:
		if pos.x >= min_x and pos.x <= max_x and pos.z >= min_z and pos.z <= max_z:
			removed[pos] = edits["removed"][pos]
	return {"placed": placed, "removed": removed}

func _expect_snapshot_matches_reference(world: VoxelWorld, origin_x: int, origin_z: int) -> void:
	var actual := world.snapshot_edits_for_chunk(origin_x, origin_z)
	var expected := _reference_snapshot(world.snapshot_block_edits(), origin_x, origin_z)
	_expect(actual["placed"] == expected["placed"], "placed snapshot mismatch at %d,%d" % [origin_x, origin_z])
	_expect(actual["removed"] == expected["removed"], "removed snapshot mismatch at %d,%d" % [origin_x, origin_z])

func _test_boundaries_and_restore() -> void:
	var world := _make_world()
	var overlap := Vector3i(5, 7, 5)
	var placed := {
		Vector3i(-22, 7, -22): BlockId.Type.DIRT,
		Vector3i(-2, 7, -2): BlockId.Type.GRASS,
		Vector3i(21, 7, 21): BlockId.Type.STONE,
		Vector3i(-3, 7, 0): BlockId.Type.SAND,
		Vector3i(22, 7, 0): BlockId.Type.LOG,
		overlap: BlockId.Type.LEAVES,
	}
	var removed := {
		Vector3i(-22, 8, 1): true,
		Vector3i(-2, 8, 21): true,
		Vector3i(21, 8, -2): true,
		Vector3i(0, 8, -3): true,
		Vector3i(0, 8, 22): true,
		overlap: true,
	}
	world.restore_block_edits(placed, removed)
	placed.clear()
	removed.clear()
	_expect(world.get_block_id_at(overlap) == BlockId.Type.LEAVES, "placed edit did not win restored overlap")
	var all_edits := world.snapshot_block_edits()
	(all_edits["placed"] as Dictionary).clear()
	(all_edits["removed"] as Dictionary).clear()
	_expect(world.get_block_edit_count() == 12, "block edit snapshot exposed mutable model storage")
	_expect_snapshot_matches_reference(world, 0, 0)
	_expect_snapshot_matches_reference(world, -20, -20)
	var origin_snapshot := world.snapshot_edits_for_chunk(0, 0)
	_expect((origin_snapshot["placed"] as Dictionary).has(Vector3i(-2, 7, -2)), "minimum placed margin excluded")
	_expect((origin_snapshot["placed"] as Dictionary).has(Vector3i(21, 7, 21)), "maximum placed margin excluded")
	_expect(not (origin_snapshot["placed"] as Dictionary).has(Vector3i(-3, 7, 0)), "placed edit before margin included")
	_expect(not (origin_snapshot["placed"] as Dictionary).has(Vector3i(22, 7, 0)), "placed edit after margin included")
	_expect((origin_snapshot["removed"] as Dictionary).has(Vector3i(-2, 8, 21)), "removed corner margin excluded")
	_expect((origin_snapshot["removed"] as Dictionary).has(Vector3i(21, 8, -2)), "removed opposite margin excluded")
	_expect(not (origin_snapshot["removed"] as Dictionary).has(Vector3i(0, 8, -3)), "removed edit before margin included")
	_expect(not (origin_snapshot["removed"] as Dictionary).has(Vector3i(0, 8, 22)), "removed edit after margin included")

func _test_mutation_transitions() -> void:
	var world := _make_world()
	var placed_pos := Vector3i(2, 8, 2)
	world.restore_block_edits({placed_pos: BlockId.Type.STONE}, {})
	_expect((world.snapshot_edits_for_chunk(0, 0)["placed"] as Dictionary).has(placed_pos), "restored placement missing")
	world.try_mine_block(placed_pos)
	var mined_placement := world.snapshot_edits_for_chunk(0, 0)
	_expect(not (mined_placement["placed"] as Dictionary).has(placed_pos), "mined placement remained indexed")
	_expect(not (mined_placement["removed"] as Dictionary).has(placed_pos), "mined placement created removal without terrain")

	var terrain_pos := Vector3i(4, 5, 4)
	var terrain_column := Vector2i(terrain_pos.x, terrain_pos.z)
	world.height_map_dict[terrain_column] = terrain_pos.y
	world.type_map_dict[terrain_column] = BlockId.Type.GRASS
	world.try_mine_block(terrain_pos)
	_expect((world.snapshot_edits_for_chunk(0, 0)["removed"] as Dictionary).has(terrain_pos), "mined terrain removal missing")
	world.try_place_block(terrain_pos, BlockId.Type.DIRT)
	var replaced_terrain := world.snapshot_edits_for_chunk(0, 0)
	_expect((replaced_terrain["placed"] as Dictionary).get(terrain_pos) == BlockId.Type.DIRT, "replacement placement missing")
	_expect(not (replaced_terrain["removed"] as Dictionary).has(terrain_pos), "replacement removal remained indexed")

	var support_pos := Vector3i(8, 8, 8)
	var torch_pos := Vector3i(9, 8, 8)
	world.restore_block_edits({
		support_pos: BlockId.Type.STONE,
		torch_pos: BlockId.Type.TORCH,
	}, {})
	world.torch_attachments[torch_pos] = Vector3i.LEFT
	var edits := world.try_mine_block(support_pos)
	var cascade_snapshot := world.snapshot_edits_for_chunk(0, 0)
	_expect(edits.size() == 2, "support mining did not cascade to torch")
	_expect(not (cascade_snapshot["placed"] as Dictionary).has(support_pos), "mined support remained indexed")
	_expect(not (cascade_snapshot["placed"] as Dictionary).has(torch_pos), "detached torch remained indexed")

func _test_scale() -> Dictionary:
	var world := _make_world()
	var placed: Dictionary = {Vector3i.ZERO: BlockId.Type.GRASS}
	var removed: Dictionary = {Vector3i(1, 0, 1): true}
	for index in range(100000):
		var pos := Vector3i(10000 + index % 1000, 10, 10000 + index / 1000)
		if index % 2 == 0:
			placed[pos] = BlockId.Type.DIRT
		else:
			removed[pos] = true
	world.restore_block_edits(placed, removed)
	var all_edits := world.snapshot_block_edits()
	var indexed_count := 0
	var indexed_started := Time.get_ticks_usec()
	for _iteration in range(50):
		var snapshot := world.snapshot_edits_for_chunk(0, 0)
		indexed_count += (snapshot["placed"] as Dictionary).size()
		indexed_count += (snapshot["removed"] as Dictionary).size()
	var indexed_usec := Time.get_ticks_usec() - indexed_started
	var reference_count := 0
	var reference_started := Time.get_ticks_usec()
	for _iteration in range(50):
		var snapshot := _reference_snapshot(all_edits, 0, 0)
		reference_count += (snapshot["placed"] as Dictionary).size()
		reference_count += (snapshot["removed"] as Dictionary).size()
	var reference_usec := Time.get_ticks_usec() - reference_started
	_expect(indexed_count == reference_count, "indexed benchmark changed snapshot contents")
	_expect(indexed_usec * 10 < reference_usec, "indexed snapshots were not at least 10x faster: %dus vs %dus" % [indexed_usec, reference_usec])
	return {"indexed_usec": indexed_usec, "reference_usec": reference_usec}

func _run() -> void:
	_test_boundaries_and_restore()
	_test_mutation_transitions()
	var timings := _test_scale()
	if _failures == 0:
		print("WORLD_EDIT_INDEX PASS indexed_usec=%d reference_usec=%d" % [timings["indexed_usec"], timings["reference_usec"]])
		quit(0)
	else:
		print("WORLD_EDIT_INDEX FAIL failures=%d" % _failures)
		quit(1)
