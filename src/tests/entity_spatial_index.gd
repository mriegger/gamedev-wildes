extends SceneTree

var _failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[entity_spatial_index] FAIL: %s" % message)

func _bounds_at(position: Vector3) -> AABB:
	return AABB(position + Vector3(-0.25, 0.0, -0.25), Vector3(0.5, 1.5, 0.5))

func _test_insert_update_and_queries() -> void:
	var index := EntitySpatialIndex.new(2.0)
	_expect(index.get_entry_count() == 0, "new index contained entries")
	_expect(index.get_cell_count() == 0, "new index contained cells")

	var position_20 := Vector3(0.5, 0.0, 0.5)
	var position_3 := Vector3(1.5, 0.0, 0.5)
	var position_11 := Vector3(4.5, 0.0, 0.5)
	index.upsert(20, position_20, _bounds_at(position_20))
	index.upsert(3, position_3, _bounds_at(position_3))
	index.upsert(11, position_11, _bounds_at(position_11))
	_expect(index.get_entry_count() == 3, "insert count changed")
	_expect(index.get_cell_count() == 2, "shared-cell insert created stale cells")
	_expect(index.query_nearby(Vector3.ZERO, 2.0) == [3, 20], "nearby query was not exact and sorted")
	_expect(index.query_overlapping(AABB(Vector3.ZERO, Vector3(2.0, 2.0, 1.0))) == [3, 20], "overlap query was not exact and sorted")
	_expect(index.query_ray(Vector3(-1.0, 0.75, 0.5), Vector3.RIGHT, 7.0) == [3, 11, 20], "ray query did not return sorted candidates along its traversed cells")
	_expect(index.query_ray(Vector3(-1.0, 0.75, 0.5), Vector3.RIGHT, 3.0) == [3, 20], "ray query included candidates beyond its maximum distance")
	var original_entry := index._entries[20] as EntitySpatialIndex.Entry
	var original_bucket := index._cells[Vector3i.ZERO] as Dictionary
	var same_cell_position := Vector3(0.75, 0.0, 0.5)
	index.upsert(20, same_cell_position, _bounds_at(same_cell_position))
	_expect(is_same(original_entry, index._entries[20]), "same-cell update replaced its entry")
	_expect(is_same(original_bucket, index._cells[Vector3i.ZERO]), "same-cell update rebuilt its bucket")
	_expect(index.query_nearby(same_cell_position, 0.1) == [20], "same-cell update retained a stale position")

	var moved_position := Vector3(8.5, 0.0, 0.5)
	index.upsert(20, moved_position, _bounds_at(moved_position))
	_expect(index.get_entry_count() == 3, "update duplicated an entry")
	_expect(index.get_cell_count() == 3, "update did not replace cell membership")
	_expect(index.query_nearby(Vector3.ZERO, 2.0) == [3], "updated entry remained in its old nearby query")
	_expect(index.query_nearby(moved_position, 0.1) == [20], "updated entry was absent from its new nearby query")
	_expect(index.query_overlapping(_bounds_at(position_20)).is_empty(), "updated bounds remained indexed at the old position")

	var spanning_position := Vector3(2.0, 0.0, 4.0)
	index.upsert(7, spanning_position, AABB(Vector3(1.75, 0.0, 3.75), Vector3(0.5, 1.5, 0.5)))
	var spanning_query := AABB(Vector3(1.9, 0.0, 3.9), Vector3(0.2, 1.0, 0.2))
	_expect(index.query_overlapping(spanning_query) == [7], "multi-cell entry was duplicated or omitted")

func _test_removal_and_clear() -> void:
	var index := EntitySpatialIndex.new(2.0)
	var first := Vector3(0.5, 0.0, 0.5)
	var second := Vector3(4.5, 0.0, 0.5)
	index.upsert(1, first, _bounds_at(first))
	index.upsert(2, second, _bounds_at(second))
	_expect(index.remove(1), "existing entry was not removed")
	_expect(not index.remove(1), "missing entry reported removal")
	_expect(index.get_entry_count() == 1, "remove did not update entry count")
	_expect(index.get_cell_count() == 1, "remove retained an empty cell")
	_expect(index.query_nearby(first, 1.0).is_empty(), "removed entry remained queryable")
	index.clear()
	_expect(index.get_entry_count() == 0, "clear retained entries")
	_expect(index.get_cell_count() == 0, "clear retained cells")
	_expect(index.query_nearby(second, 1.0).is_empty(), "clear retained query results")

func _test_repeated_update_cleanup() -> void:
	var index := EntitySpatialIndex.new(2.0)
	const ACTIVE_COUNT: int = 32
	for cycle in range(80):
		for runtime_id in range(ACTIVE_COUNT):
			var position := Vector3(float(cycle * 100 + runtime_id * 3) + 0.5, 0.0, 0.5)
			index.upsert(runtime_id, position, _bounds_at(position))
		_expect(index.get_entry_count() == ACTIVE_COUNT, "repeated updates changed the active count")
		_expect(index.get_cell_count() <= ACTIVE_COUNT, "repeated updates accumulated stale cells")
	for runtime_id in range(0, ACTIVE_COUNT, 2):
		index.remove(runtime_id)
	_expect(index.get_entry_count() == ACTIVE_COUNT / 2, "bulk removal changed the surviving count")
	_expect(index.get_cell_count() <= ACTIVE_COUNT / 2, "bulk removal retained stale cells")
	index.clear()
	_expect(index.get_entry_count() == 0 and index.get_cell_count() == 0, "bounded cleanup did not reach zero")

func _run() -> void:
	_test_insert_update_and_queries()
	_test_removal_and_clear()
	_test_repeated_update_cleanup()
	if _failures == 0:
		print("ENTITY_SPATIAL_INDEX PASS")
		quit(0)
	else:
		print("ENTITY_SPATIAL_INDEX FAIL failures=%d" % _failures)
		quit(1)
