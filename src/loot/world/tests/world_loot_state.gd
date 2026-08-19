extends SceneTree

var _errors: Array[String] = []
var _item_catalog: ItemCatalog
var _factory: EquipmentInstanceFactory

func _init() -> void:
	_item_catalog = load("res://items/item_catalog.tres") as ItemCatalog
	_factory = EquipmentInstanceFactory.new(_item_catalog)
	_test_deterministic_merging_and_copy_queries()
	_test_partial_take_and_lifetime()
	_test_prepared_change_safety()
	_test_atomic_batches()
	_test_bounded_capacity_and_eviction()
	_test_spatial_bounds()
	_finish()

func _test_deterministic_merging_and_copy_queries() -> void:
	var state := WorldLootState.new(_item_catalog, _factory)
	var max_stack := _item_catalog.get_definition(&"copper").max_stack
	_expect(state.get_revision() == 0, "new world loot revision was not zero")
	_expect(_add(state, InventoryStack.new(&"copper", max_stack), Vector3(1.0, 0.0, 0.0)), "first merge fixture add failed")
	_expect(state.get_revision() == 1, "committed world loot change did not advance revision")
	_expect(_add(state, InventoryStack.new(&"copper", max_stack), Vector3(-1.0, 0.0, 0.0)), "second merge fixture add failed")
	_expect(state.get_entry_count() == 2, "full nearby stacks merged")
	_expect(_take(state, 1, 1), "first fixture partial take failed")
	_expect(_take(state, 2, 1), "second fixture partial take failed")
	_expect(_advance(state, 10.0), "merge fixture lifetime advance failed")
	_expect(_add(state, InventoryStack.new(&"copper", 1), Vector3(-0.25, 0.0, 0.0)), "nearest-distance merge failed")
	_expect(state.get_entry(1).stack.count == max_stack - 1, "nearest-distance merge used the lower but farther ID")
	_expect(state.get_entry(2).stack.count == max_stack, "nearest-distance merge did not use the nearest stack")
	_expect(_take(state, 2, 1), "nearest-distance fixture reset failed")
	_expect(_advance(state, 10.0), "tie-distance fixture lifetime advance failed")
	var merge_only := state._prepare_add_stack(InventoryStack.new(&"copper", 1), Vector3.ZERO)
	_expect(merge_only != null and not merge_only._changes_entries(), "merge-only change altered the entry set")
	_expect(merge_only != null and state.commit_prepared_change(merge_only), "tie-distance merge failed")
	var first := state.get_entry(1)
	var second := state.get_entry(2)
	_expect(first != null and first.stack.count == max_stack, "equal-distance merge did not prefer lower stable ID")
	_expect(second != null and second.stack.count == max_stack - 1, "equal-distance merge changed the wrong stack")
	_expect(first != null and is_equal_approx(first.remaining_lifetime, WorldLootState.MATERIAL_LIFETIME), "merged material lifetime did not refresh")
	_expect(second != null and is_equal_approx(second.remaining_lifetime, WorldLootState.MATERIAL_LIFETIME - 10.0), "unmerged material lifetime refreshed")
	var nearby := state.query_nearby(Vector3.ZERO, 1.0)
	_expect(nearby.size() == 2 and nearby[0].entry_id == 1 and nearby[1].entry_id == 2, "spatial query was incomplete or unstable")
	_expect(state.query_nearby(Vector3.ZERO, 0.5).is_empty(), "spatial query exceeded its radius")
	if first != null:
		first.stack.count = 1
		first.world_position = Vector3(100.0, 0.0, 0.0)
	var queried := state.get_entry(1)
	_expect(queried != null and queried.stack.count == max_stack and queried.world_position == Vector3(1.0, 0.0, 0.0), "entry query leaked mutable state")
	if not nearby.is_empty():
		nearby[0].remaining_lifetime = 1.0
	_expect(is_equal_approx(state.get_entry(1).remaining_lifetime, WorldLootState.MATERIAL_LIFETIME), "spatial query leaked mutable state")
	var entries := state.get_entries()
	if not entries.is_empty():
		entries[0].stack.count = 1
	_expect(state.get_entry(1).stack.count == max_stack, "entries query leaked mutable state")

func _test_partial_take_and_lifetime() -> void:
	var state := WorldLootState.new(_item_catalog, _factory)
	_expect(_add(state, InventoryStack.new(&"sand_block", 5), Vector3.ZERO), "material lifetime fixture add failed")
	var sword := _factory.create(&"copper_sword")
	_expect(sword != null, "equipment lifetime fixture allocation failed")
	_expect(_add(state, InventoryStack.new(&"copper_sword", 1, sword), Vector3(4.0, 0.0, 0.0)), "equipment lifetime fixture add failed")
	var second_sword := _factory.create(&"copper_sword")
	_expect(second_sword != null, "second equipment lifetime fixture allocation failed")
	_expect(_add(state, InventoryStack.new(&"copper_sword", 1, second_sword), Vector3(4.0, 0.0, 0.0)), "nearby equipment fixture add failed")
	_expect(state.get_entry_count() == 3 and state.has_entry(2) and state.has_entry(3), "nearby equipment entries merged")
	_expect(state.get_entry(1).has_lifetime(), "material did not receive a lifetime")
	_expect(not state.get_entry(2).has_lifetime(), "equipment received a lifetime")
	_expect(not state.get_entry(3).has_lifetime(), "second equipment received a lifetime")
	var lifetime_only := state.prepare_advance_time(100.0)
	_expect(lifetime_only != null and not lifetime_only._changes_entries(), "lifetime-only change altered the entry set")
	_expect(lifetime_only != null and state.commit_prepared_change(lifetime_only), "lifetime advance failed")
	var partial := state.prepare_take(1, 2)
	_expect(partial != null, "material partial take was rejected")
	if partial != null:
		_expect(not partial._changes_entries(), "partial take altered the entry set")
		var result := partial.get_result_stack()
		_expect(result != null and result.item_id == &"sand_block" and result.count == 2 and result.equipment_instance == null, "partial take result changed")
		_expect(state.commit_prepared_change(partial), "material partial take commit failed")
	var remaining := state.get_entry(1)
	_expect(remaining != null and remaining.stack.count == 3, "material partial take removed the wrong count")
	_expect(remaining != null and is_equal_approx(remaining.remaining_lifetime, 200.0), "partial pickup refreshed material lifetime")
	_expect(state.prepare_take(2, 0) == null and state.prepare_take(2, 2) == null, "equipment accepted a non-exact take")
	var equipment_take := state.prepare_take(2)
	_expect(equipment_take != null, "equipment exact take was rejected")
	if equipment_take != null:
		_expect(equipment_take._changes_entries(), "full take did not alter the entry set")
		var result := equipment_take.get_result_stack()
		_expect(result != null and result.equipment_instance != null and result.equipment_instance.instance_id == sword.instance_id, "equipment take lost instance identity")
		_expect(state.commit_prepared_change(equipment_take), "equipment exact take commit failed")
	var expiration := state.prepare_advance_time(200.0)
	_expect(expiration != null and expiration._changes_entries(), "expiration did not alter the entry set")
	_expect(expiration != null and state.commit_prepared_change(expiration), "material expiration advance failed")
	_expect(state.get_entry_count() == 1 and state.has_entry(3), "material expiration removed equipment or retained material")
	_expect(state.prepare_advance_time(1.0) == null, "empty state prepared a lifetime change")
	_expect(_take(state, 3), "second equipment exact take failed")
	_expect(state.get_entry_count() == 0, "equipment exact take did not clear its entry")
	_expect(state.prepare_advance_time(0.0) == null and state.prepare_advance_time(NAN) == null, "invalid lifetime delta was accepted")

func _test_prepared_change_safety() -> void:
	var state := WorldLootState.new(_item_catalog, _factory)
	_expect(_add(state, InventoryStack.new(&"copper", 5), Vector3.ZERO), "prepared fixture add failed")
	var first := state.prepare_take(1, 1)
	var stale := state.prepare_take(1, 1)
	_expect(first != null and stale != null, "parallel prepares failed")
	if first == null or stale == null:
		return
	_expect(state.can_commit_prepared_change(first), "fresh prepared change was not committable")
	_expect(state.commit_prepared_change(first), "first prepared commit failed")
	_expect(not state.can_commit_prepared_change(first), "consumed prepared change remained committable")
	_expect(not state.commit_prepared_change(first), "prepared change replay succeeded")
	var after_first := _state_view(state)
	_expect(not state.commit_prepared_change(stale), "stale prepared change committed")
	_expect(_state_view(state) == after_first, "stale commit changed world loot")
	var other := WorldLootState.new(_item_catalog, _factory)
	_expect(not other.commit_prepared_change(stale), "foreign owner committed prepared change")
	var duplicate_instance := _factory.create(&"copper_sword")
	_expect(duplicate_instance != null, "duplicate instance fixture allocation failed")
	_expect(_add(state, InventoryStack.new(&"copper_sword", 1, duplicate_instance), Vector3(12.0, 0.0, 0.0)), "duplicate instance fixture add failed")
	var duplicate_before := _state_view(state)
	_expect(state._prepare_add_stack(InventoryStack.new(&"copper_sword", 1, duplicate_instance), Vector3(16.0, 0.0, 0.0)) == null, "duplicate equipment instance was accepted")
	_expect(_state_view(state) == duplicate_before, "duplicate equipment rejection changed state")

func _test_atomic_batches() -> void:
	var factory := EquipmentInstanceFactory.new(_item_catalog)
	var state := WorldLootState.new(_item_catalog, factory)
	var expected_next_instance_id := factory.get_next_instance_id()
	var pending := factory.copy()
	var first_sword := pending.create(&"copper_sword")
	var second_sword := pending.create(&"copper_sword")
	var equipment_batch: Array[InventoryStack] = [
		InventoryStack.new(&"copper_sword", 1, first_sword),
		InventoryStack.new(&"copper_sword", 1, second_sword),
	]
	var prepared := state._prepare_add_batch(
		equipment_batch,
		Vector3.ZERO,
		pending.get_next_instance_id(),
	)
	_expect(prepared != null and prepared._changes_entries(), "two-equipment batch did not alter the entry set")
	_expect(prepared != null and not state.can_commit_prepared_change(prepared), "provisional equipment committed without allocator advancement")
	_expect(prepared != null and not state.commit_prepared_change(prepared), "provisional equipment bypassed the cross-owner transaction")
	_expect(factory.get_next_instance_id() == expected_next_instance_id, "rejected provisional commit advanced the allocator")
	_expect(state.get_entry_count() == 0, "rejected provisional commit changed world state")
	var resolution := PreparedLootResolution.new(
		factory,
		expected_next_instance_id,
		pending.get_next_instance_id(),
		equipment_batch,
	)
	_expect(WorldLootDropTransaction.try_commit(resolution, state, Vector3.ZERO), "two-equipment transaction did not commit")
	_expect(factory.get_next_instance_id() == pending.get_next_instance_id(), "two-equipment transaction did not advance the allocator")
	_expect(not WorldLootDropTransaction.try_commit(resolution, state, Vector3.ZERO), "two-equipment transaction replayed")
	_expect(state.get_entry_count() == 2, "two-equipment batch emitted the wrong entry count")
	_expect(state.get_equipment_instance_ids() == [first_sword.instance_id, second_sword.instance_id], "two-equipment batch changed instance identity")

	var mixed_expected_next_instance_id := factory.get_next_instance_id()
	var mixed_pending := factory.copy()
	var mixed_sword := mixed_pending.create(&"copper_sword")
	var mixed_batch: Array[InventoryStack] = [
		InventoryStack.new(&"copper", 4),
		InventoryStack.new(&"copper_sword", 1, mixed_sword),
	]
	var mixed_resolution := PreparedLootResolution.new(
		factory,
		mixed_expected_next_instance_id,
		mixed_pending.get_next_instance_id(),
		mixed_batch,
	)
	_expect(WorldLootDropTransaction.try_commit(mixed_resolution, state, Vector3(4.0, 0.0, 0.0)), "material-equipment transaction did not commit")
	_expect(state.get_entry_count() == 4, "material-equipment batch emitted the wrong entry count")
	_expect(state.get_entry(3).stack.item_id == &"copper" and state.get_entry(3).stack.count == 4, "mixed batch material changed")
	_expect(state.get_entry(4).stack.equipment_instance.instance_id == mixed_sword.instance_id, "mixed batch equipment changed")

	var before_rejections := _state_view(state)
	_expect(
		state._prepare_add_batch(
			[InventoryStack.new(&"sand_block", 1)],
			Vector3.ZERO,
			factory.get_next_instance_id() - 1,
		) == null,
		"stale pending equipment ID was accepted",
	)
	_expect(_state_view(state) == before_rejections, "stale pending ID changed batch state")
	var duplicate_pending := factory.copy()
	var duplicate_sword := duplicate_pending.create(&"copper_sword")
	var duplicate_batch: Array[InventoryStack] = [
		InventoryStack.new(&"copper_sword", 1, duplicate_sword),
		InventoryStack.new(&"copper_sword", 1, duplicate_sword),
	]
	_expect(
		state._prepare_add_batch(
			duplicate_batch,
			Vector3.ZERO,
			duplicate_pending.get_next_instance_id(),
		) == null,
		"duplicate batch equipment instance was accepted",
	)
	_expect(_state_view(state) == before_rejections, "duplicate batch instance changed state")
	_expect(
		state._prepare_add_batch(
			[InventoryStack.new(&"copper_sword", 1, first_sword)],
			Vector3.ZERO,
			factory.get_next_instance_id(),
		) == null,
		"equipment instance already in world state was accepted",
	)
	_expect(_state_view(state) == before_rejections, "state equipment duplicate changed state")

func _test_bounded_capacity_and_eviction() -> void:
	var state := WorldLootState.new(_item_catalog, _factory)
	for index in range(WorldLootState.MAXIMUM_ENTRY_COUNT):
		_expect(
			_add(state, InventoryStack.new(&"sand_block", 1), Vector3(float(index) * 2.0, 0.0, 0.0)),
			"material capacity fixture add %d failed" % index,
		)
	_expect(state.get_entry_count() == WorldLootState.MAXIMUM_ENTRY_COUNT, "material capacity fixture size mismatch")
	_expect(_advance(state, 10.0), "capacity fixture lifetime advance failed")
	_expect(_add(state, InventoryStack.new(&"sand_block", 1), Vector3.ZERO), "capacity fixture lifetime refresh failed")
	var sword := _factory.create(&"copper_sword")
	_expect(sword != null, "capacity fixture equipment allocation failed")
	_expect(_add(state, InventoryStack.new(&"copper_sword", 1, sword), Vector3(1000.0, 0.0, 0.0)), "bounded capacity did not evict material for equipment")
	_expect(state.get_entry_count() == WorldLootState.MAXIMUM_ENTRY_COUNT, "bounded state exceeded its cap")
	_expect(state.has_entry(1), "refreshed material was evicted")
	_expect(not state.has_entry(2), "lowest-lifetime and lowest-ID material was not evicted")
	_expect(state.has_entry(WorldLootState.MAXIMUM_ENTRY_COUNT + 1), "new entry did not receive a monotonic ID")
	_expect(state.get_next_entry_id() == WorldLootState.MAXIMUM_ENTRY_COUNT + 2, "next entry ID did not advance after eviction")

	var equipment_only := WorldLootState.new(_item_catalog, _factory)
	for index in range(WorldLootState.MAXIMUM_ENTRY_COUNT - 1):
		var instance := _factory.create(&"copper_sword")
		_expect(instance != null, "equipment-only capacity allocation %d failed" % index)
		if instance != null:
			_expect(
				_add(equipment_only, InventoryStack.new(&"copper_sword", 1, instance), Vector3(float(index) * 2.0, 0.0, 0.0)),
				"equipment-only capacity add %d failed" % index,
			)
	var sand_max_stack := _item_catalog.get_definition(&"sand_block").max_stack
	_expect(_add(equipment_only, InventoryStack.new(&"sand_block", sand_max_stack - 1), Vector3(1000.0, 0.0, 0.0)), "sole-material capacity fixture add failed")
	var overflow_expected_next_instance_id := _factory.get_next_instance_id()
	var overflow_pending := _factory.copy()
	var overflow_first := overflow_pending.create(&"copper_sword")
	var overflow_second := overflow_pending.create(&"copper_sword")
	var overflow_batch: Array[InventoryStack] = [
		InventoryStack.new(&"copper_sword", 1, overflow_first),
		InventoryStack.new(&"copper_sword", 1, overflow_second),
	]
	var overflow_resolution := PreparedLootResolution.new(
		_factory,
		overflow_expected_next_instance_id,
		overflow_pending.get_next_instance_id(),
		overflow_batch,
	)
	_expect(
		WorldLootDropTransaction.try_commit(
			overflow_resolution,
			equipment_only,
			Vector3(1000.0, 0.0, 0.0),
		),
		"full equipment batch was blocked by existing equipment",
	)
	_expect(equipment_only.get_entry_count() == WorldLootState.MAXIMUM_ENTRY_COUNT, "equipment overflow exceeded the cap")
	_expect(not equipment_only.has_entry(1), "equipment overflow did not evict the oldest equipment fallback")
	_expect(not equipment_only.has_entry(WorldLootState.MAXIMUM_ENTRY_COUNT), "equipment overflow did not evict material first")
	_expect(equipment_only.has_entry(WorldLootState.MAXIMUM_ENTRY_COUNT + 1), "equipment overflow lost its first new entry")
	_expect(equipment_only.has_entry(WorldLootState.MAXIMUM_ENTRY_COUNT + 2), "equipment overflow lost its second new entry")
	_expect(_factory.get_next_instance_id() == overflow_pending.get_next_instance_id(), "equipment overflow did not advance the allocator atomically")

	_expect(
		_add(
			equipment_only,
			InventoryStack.new(&"sand_block", sand_max_stack - 1),
			Vector3(1000.0, 0.0, 0.0),
		),
		"all-equipment state did not admit material via equipment fallback",
	)
	_expect(not equipment_only.has_entry(2), "material overflow did not evict the oldest equipment")
	var protected_material_id := WorldLootState.MAXIMUM_ENTRY_COUNT + 3
	_expect(equipment_only.has_entry(protected_material_id), "material overflow did not receive a stable ID")
	var protected_pending := _factory.copy()
	var protected_sword := protected_pending.create(&"copper_sword")
	var protected_batch: Array[InventoryStack] = [
		InventoryStack.new(&"sand_block", 1),
		InventoryStack.new(&"copper_sword", 1, protected_sword),
	]
	var protected_resolution := PreparedLootResolution.new(
		_factory,
		_factory.get_next_instance_id(),
		protected_pending.get_next_instance_id(),
		protected_batch,
	)
	_expect(
		WorldLootDropTransaction.try_commit(
			protected_resolution,
			equipment_only,
			Vector3(1000.0, 0.0, 0.0),
		),
		"protected mixed overflow batch did not commit",
	)
	var protected_material := equipment_only.get_entry(protected_material_id)
	_expect(protected_material != null and protected_material.stack.count == sand_max_stack, "mixed overflow evicted or lost its earlier merged material")
	_expect(not equipment_only.has_entry(3), "mixed overflow did not evict the oldest unprotected equipment")
	_expect(equipment_only.has_entry(WorldLootState.MAXIMUM_ENTRY_COUNT + 4), "mixed overflow lost its equipment entry")
	_expect(
		_add(equipment_only, InventoryStack.new(&"sand_block", 1), Vector3(2000.0, 0.0, 0.0)),
		"full mixed state did not admit replacement material",
	)
	_expect(not equipment_only.has_entry(protected_material_id), "overflow did not prefer material eviction")
	_expect(equipment_only.has_entry(4), "material-first overflow evicted older equipment")
	_expect(equipment_only.get_entry_count() == WorldLootState.MAXIMUM_ENTRY_COUNT, "bounded overflow changed the entry count")

func _test_spatial_bounds() -> void:
	var state := WorldLootState.new(_item_catalog, _factory)
	var maximum_safe_coordinate := float(WorldLootSpatialIndex.MAXIMUM_CELL_COORDINATE - 2047) * WorldLootState.SPATIAL_CELL_SIZE
	var safe_position := Vector3(maximum_safe_coordinate, 0.0, 0.0)
	_expect(_add(state, InventoryStack.new(&"copper", 1), safe_position), "maximum safe spatial position was rejected")
	_expect(state.query_nearby(safe_position, 0.0).size() == 1, "maximum safe spatial position was not indexed")
	_expect(state.query_nearby(Vector3.ZERO, 1.0e300).size() == 1, "huge-radius bounded fallback missed an indexed entry")
	_expect(state.query_nearby(Vector3(1.0e30, 0.0, 0.0), 1.0).is_empty(), "extreme query position returned a distant entry")
	_expect(state.query_nearby(Vector3(1.0e30, 0.0, 0.0), 1.1e30).size() == 1, "extreme query fallback missed an in-range entry")
	var unsafe_position := Vector3(
		float(WorldLootSpatialIndex.MAXIMUM_CELL_COORDINATE + 1) * WorldLootState.SPATIAL_CELL_SIZE,
		0.0,
		0.0,
	)
	var before := _state_view(state)
	_expect(state._prepare_add_stack(InventoryStack.new(&"copper", 1), unsafe_position) == null, "unsafe Vector3i cell position was accepted")
	_expect(_state_view(state) == before, "unsafe position rejection changed state")


func _state_view(state: WorldLootState) -> Dictionary:
	var entries: Array[Dictionary] = []
	for entry in state.get_entries():
		entries.append({
			"entry_id": entry.entry_id,
			"item_id": entry.stack.item_id,
			"count": entry.stack.count,
			"instance_id": -1 if entry.stack.equipment_instance == null else entry.stack.equipment_instance.instance_id,
			"world_position": entry.world_position,
			"remaining_lifetime": entry.remaining_lifetime,
		})
	return {
		"revision": state.get_revision(),
		"next_entry_id": state.get_next_entry_id(),
		"entries": entries,
	}

func _add(state: WorldLootState, stack: InventoryStack, position: Vector3) -> bool:
	var prepared := state._prepare_add_stack(stack, position)
	return prepared != null and state.commit_prepared_change(prepared)

func _take(state: WorldLootState, entry_id: int, count: int = -1) -> bool:
	var prepared := state.prepare_take(entry_id, count)
	return prepared != null and state.commit_prepared_change(prepared)

func _advance(state: WorldLootState, delta: float) -> bool:
	var prepared := state.prepare_advance_time(delta)
	return prepared != null and state.commit_prepared_change(prepared)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)

func _finish() -> void:
	if _errors.is_empty():
		print("WORLD_LOOT_STATE PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)
