extends SceneTree

const DEFAULT_SEQS: int = 50000
const DEFAULT_OPS: int = 20
const MAX_STACK_OPTIONS: Array[int] = [1, 2, 5, 10, 32, 64, 99]

var _rng := RandomNumberGenerator.new()
var _failures: int = 0
var _tests_run: int = 0
var _asserts: int = 0
var _block_catalog: BlockCatalog
var _base_item_catalog: ItemCatalog
var _valid_item_ids: Array[StringName] = []
var _catalogs_by_limit: Dictionary = {}

func _init() -> void:
	var seqs: int = DEFAULT_SEQS
	var ops: int = DEFAULT_OPS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seqs="):
			seqs = int(argument.split("=")[1])
		elif argument.begins_with("--ops="):
			ops = int(argument.split("=")[1])
	_block_catalog = load("res://blocks/block_catalog.tres") as BlockCatalog
	_base_item_catalog = load("res://items/item_catalog.tres") as ItemCatalog
	assert(_block_catalog.validate())
	assert(_base_item_catalog.validate(_block_catalog))
	for definition in _base_item_catalog.definitions:
		_valid_item_ids.append(definition.id)
	_rng.seed = 123456789
	var ok := true
	ok = _run_edge_cases() and ok
	ok = _run_raw_throughput() and ok
	ok = _run_fuzz(seqs, ops) and ok
	ok = _run_add_batch_properties() and ok
	if ok and _failures == 0:
		print("ALL PASS | tests_run=%d asserts=%d" % [_tests_run, _asserts])
		quit(0)
	else:
		print("FAIL | failures=%d tests_run=%d asserts=%d" % [_failures, _tests_run, _asserts])
		quit(1)

func _make_catalog(max_stack: int, include_nonplaceable: bool = false) -> ItemCatalog:
	if not include_nonplaceable and _catalogs_by_limit.has(max_stack):
		return _catalogs_by_limit[max_stack] as ItemCatalog
	var definitions: Array[ItemDefinition] = []
	for source in _base_item_catalog.definitions:
		var definition := source.duplicate() as ItemDefinition
		definition.max_stack = 1 if definition.equipment_type != null else max_stack
		definitions.append(definition)
	if include_nonplaceable:
		var nonplaceable := ItemDefinition.new()
		nonplaceable.id = &"test_tool"
		nonplaceable.display_name = "Test Tool"
		nonplaceable.icon = _base_item_catalog.definitions[0].icon
		nonplaceable.max_stack = 1
		definitions.append(nonplaceable)
	var catalog := ItemCatalog.new()
	catalog.equipment_types = _base_item_catalog.equipment_types
	catalog.definitions = definitions
	assert(catalog.validate(_block_catalog))
	if not include_nonplaceable:
		_catalogs_by_limit[max_stack] = catalog
	return catalog

func _compute_totals(inv: InventoryModel) -> Dictionary:
	var totals: Dictionary = {}
	for slot in InventoryTestFixture.get_slots(inv):
		if slot != null:
			var item_id := slot.item_id
			totals[item_id] = int(totals.get(item_id, 0)) + slot.count
	return totals

func _find_item(inv: InventoryModel, item_id: StringName) -> int:
	for index in range(inv.get_size()):
		var stack := inv.get_slot(index)
		if stack != null and stack.item_id == item_id:
			return index
	return -1

func _copy_stacks(stacks: Array[InventoryStack]) -> Array[InventoryStack]:
	var copied: Array[InventoryStack] = []
	copied.resize(stacks.size())
	for index in range(stacks.size()):
		if stacks[index] != null:
			copied[index] = stacks[index].copy()
	return copied

func _slots_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for index in range(a.size()):
		var left = a[index]
		var right = b[index]
		if left == null and right == null:
			continue
		if left == null or right == null:
			return false
		if left.item_id != right.item_id or left.count != right.count:
			return false
		if (left.equipment_instance == null) != (right.equipment_instance == null):
			return false
		if left.equipment_instance != null and left.equipment_instance.to_dict() != right.equipment_instance.to_dict():
			return false
	return true

func _validate_inv(inv: InventoryModel) -> bool:
	for index in range(inv.get_size()):
		var slot: InventoryStack = inv.get_slot(index)
		if slot == null:
			continue
		if not slot is InventoryStack:
			return false
		var item_id: StringName = slot.item_id
		if not inv.item_catalog.has_definition(item_id):
			return false
		var count: int = slot.count
		if count < 1 or count > inv.item_catalog.get_definition(item_id).max_stack:
			return false
		var definition := inv.item_catalog.get_definition(item_id)
		if definition.equipment_type == null:
			if slot.equipment_instance != null:
				return false
		elif count != 1 or not inv.equipment_instance_factory.is_valid_instance(item_id, slot.equipment_instance):
			return false
		if not inv.can_slot_accept_item_id(index, item_id):
			return false
	return true

func _equipment_stack(inventory: InventoryModel, item_id: StringName) -> InventoryStack:
	var instance := inventory.equipment_instance_factory.create(item_id)
	assert(instance != null)
	return InventoryStack.new(item_id, 1, instance)

func _assert(condition: bool, message: String) -> bool:
	_asserts += 1
	if condition:
		return true
	_failures += 1
	print("ASSERT FAIL: %s" % message)
	return false

func _random_item_id(rng: RandomNumberGenerator) -> StringName:
	return _valid_item_ids[rng.randi_range(0, _valid_item_ids.size() - 1)]

func _random_batch(rng: RandomNumberGenerator, size: int) -> Array[StringName]:
	var batch: Array[StringName] = []
	for _index in range(size):
		var pick := rng.randi_range(0, _valid_item_ids.size() + 3)
		if pick < _valid_item_ids.size():
			batch.append(_valid_item_ids[pick])
		elif pick == _valid_item_ids.size():
			batch.append(&"")
		else:
			batch.append(&"unknown_item")
	return batch

func _make_random_inventory(rng: RandomNumberGenerator) -> Dictionary:
	var max_stack := MAX_STACK_OPTIONS[rng.randi_range(0, MAX_STACK_OPTIONS.size() - 1)]
	var catalog := _make_catalog(max_stack)
	var inv := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	for _fill_index in range(rng.randi_range(0, 4)):
		var index := rng.randi_range(0, InventoryModel.FILLABLE_SIZE - 1)
		if rng.randf() < 0.5:
			InventoryTestFixture.restore_slot(inv, index, null)
		else:
			var item_id := _random_item_id(rng)
			var limit := inv.item_catalog.get_definition(item_id).max_stack
			if inv.item_catalog.get_definition(item_id).equipment_type == null:
				InventoryTestFixture.restore_slot(inv, index, InventoryStack.new(item_id, rng.randi_range(1, limit)))
			else:
				InventoryTestFixture.restore_slot(inv, index, _equipment_stack(inv, item_id))
	var loadout := InventoryTestFixture.create_loadout(inv)
	assert(loadout != null)
	for _batch_index in range(rng.randi_range(0, 6)):
		var batch := _random_batch(rng, rng.randi_range(0, 14))
		var can_add := loadout.can_add_batch(batch)
		var added := loadout.add_batch(batch)
		_assert(can_add == added, "can_add_batch mismatch")
	assert(_validate_inv(inv))
	return {"inventory": inv, "loadout": loadout}

func _run_edge_cases() -> bool:
	print("[edge] starting")
	_tests_run += 1
	var catalog := _make_catalog(99)
	var grass_id := catalog.get_item_for_block(BlockId.Type.GRASS).id
	var dirt_id := catalog.get_item_for_block(BlockId.Type.DIRT).id
	var stone_id := catalog.get_item_for_block(BlockId.Type.STONE).id
	var sand_id := catalog.get_item_for_block(BlockId.Type.SAND).id
	var torch_id := catalog.get_item_for_block(BlockId.Type.TORCH).id
	var helmet := catalog.get_definition(&"copper_helmet") as ArmorDefinition

	var empty := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	var empty_loadout := InventoryTestFixture.create_loadout(empty)
	_assert(empty.get_size() == InventoryModel.TOTAL_SIZE, "default size")
	_assert(not empty_loadout.can_handle_drop(0, 1, 1), "empty source rejected")
	var empty_before := _copy_stacks(InventoryTestFixture.get_slots(empty))
	_assert(not empty_loadout.handle_drop(0, 1, 1), "empty drop rejected")
	_assert(_slots_equal(empty_before, InventoryTestFixture.get_slots(empty)), "empty drop unchanged")

	var moved := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	InventoryTestFixture.restore_slot(moved, 0, InventoryStack.new(grass_id, 10))
	var moved_loadout := InventoryTestFixture.create_loadout(moved)
	var moved_totals := _compute_totals(moved)
	_assert(moved_loadout.can_handle_drop(0, 1, 10), "full move accepted")
	_assert(moved_loadout.handle_drop(0, 1, 10), "full move succeeds")
	_assert(moved.get_slot(0) == null, "full move clears source")
	_assert(moved.get_slot(1).item_id == grass_id and moved.get_slot(1).count == 10, "full move preserves stack")
	_assert(_compute_totals(moved) == moved_totals, "full move conserves totals")

	var split := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	InventoryTestFixture.restore_slot(split, 0, InventoryStack.new(stone_id, 10))
	var split_loadout := InventoryTestFixture.create_loadout(split)
	_assert(split_loadout.handle_drop(0, 5, 3), "split succeeds")
	_assert(split.get_slot(0).count == 7 and split.get_slot(5).count == 3, "split counts")

	var discarded := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	InventoryTestFixture.restore_slot(discarded, 0, InventoryStack.new(stone_id, 10))
	InventoryTestFixture.restore_slot(discarded, InventoryModel.HOTBAR_SIZE, InventoryStack.new(grass_id, 4))
	var discarded_helmet_index := InventoryModel.get_equipment_index(ArmorDefinition.Slot.HEAD)
	InventoryTestFixture.restore_slot(discarded, discarded_helmet_index, _equipment_stack(discarded, helmet.id))
	var discarded_loadout := InventoryTestFixture.create_loadout(discarded)
	_assert(discarded_loadout.can_discard_stack(0, 3), "partial hotbar discard accepted")
	_assert(discarded_loadout.discard_stack(0, 3), "partial hotbar discard succeeds")
	_assert(discarded.get_slot(0).count == 7, "partial hotbar discard count")
	_assert(discarded_loadout.discard_stack(InventoryModel.HOTBAR_SIZE, 4), "full backpack discard succeeds")
	_assert(discarded.get_slot(InventoryModel.HOTBAR_SIZE) == null, "full backpack discard clears slot")
	_assert(discarded_loadout.can_discard_stack(discarded_helmet_index, 1), "equipment discard accepted")
	_assert(discarded_loadout.discard_stack(discarded_helmet_index, 1), "equipment discard succeeds")
	_assert(discarded.get_slot(discarded_helmet_index) == null, "equipment discard clears slot")
	_assert(not discarded_loadout.discard_stack(0, 8), "oversized discard rejected")
	_assert(not discarded_loadout.discard_stack(InventoryModel.TOTAL_SIZE, 1), "out-of-range discard rejected")

	var merged := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	InventoryTestFixture.restore_slot(merged, 0, InventoryStack.new(dirt_id, 5))
	InventoryTestFixture.restore_slot(merged, 1, InventoryStack.new(dirt_id, 3))
	var merged_loadout := InventoryTestFixture.create_loadout(merged)
	_assert(merged_loadout.handle_drop(0, 1, 5), "merge succeeds")
	_assert(merged.get_slot(0) == null and merged.get_slot(1).count == 8, "merge counts")

	var overflow := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	InventoryTestFixture.restore_slot(overflow, 0, InventoryStack.new(sand_id, 10))
	InventoryTestFixture.restore_slot(overflow, 1, InventoryStack.new(sand_id, 95))
	var overflow_loadout := InventoryTestFixture.create_loadout(overflow)
	_assert(overflow_loadout.handle_drop(0, 1, 10), "overflow merge succeeds")
	_assert(overflow.get_slot(0).count == 6 and overflow.get_slot(1).count == 99, "overflow capped")

	var swapped := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	InventoryTestFixture.restore_slot(swapped, 0, InventoryStack.new(grass_id, 4))
	InventoryTestFixture.restore_slot(swapped, 1, InventoryStack.new(stone_id, 6))
	var swapped_loadout := InventoryTestFixture.create_loadout(swapped)
	_assert(swapped_loadout.handle_drop(0, 1, 4), "swap succeeds")
	_assert(swapped.get_slot(0).item_id == stone_id and swapped.get_slot(1).item_id == grass_id, "swap identities")
	var swap_before := _copy_stacks(InventoryTestFixture.get_slots(swapped))
	_assert(not swapped_loadout.handle_drop(0, 1, 2), "partial swap rejected")
	_assert(_slots_equal(swap_before, InventoryTestFixture.get_slots(swapped)), "partial swap unchanged")

	var assigned := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	InventoryTestFixture.restore_slot(assigned, 2, InventoryStack.new(stone_id, 6))
	InventoryTestFixture.restore_slot(assigned, InventoryModel.HOTBAR_SIZE, InventoryStack.new(grass_id, 4))
	var assigned_loadout := InventoryTestFixture.create_loadout(assigned)
	var assigned_totals := _compute_totals(assigned)
	_assert(assigned_loadout.assign_slot_to_hotbar(InventoryModel.HOTBAR_SIZE, 2), "backpack hotbar assignment succeeds")
	_assert(assigned.get_slot(2).item_id == grass_id and assigned.get_slot(2).count == 4, "backpack item assigned to hotbar")
	_assert(assigned.get_slot(InventoryModel.HOTBAR_SIZE).item_id == stone_id and assigned.get_slot(InventoryModel.HOTBAR_SIZE).count == 6, "hotbar item swapped into backpack")
	_assert(_compute_totals(assigned) == assigned_totals, "backpack hotbar assignment conserves totals")
	var assigned_before := _copy_stacks(InventoryTestFixture.get_slots(assigned))
	_assert(not assigned_loadout.assign_slot_to_hotbar(InventoryModel.HOTBAR_SIZE + 1, 2), "empty backpack assignment rejected")
	_assert(not assigned_loadout.assign_slot_to_hotbar(2, 2), "same hotbar assignment rejected")
	_assert(not assigned_loadout.assign_slot_to_hotbar(InventoryModel.HOTBAR_SIZE, InventoryModel.HOTBAR_SIZE), "backpack destination assignment rejected")
	_assert(_slots_equal(assigned_before, InventoryTestFixture.get_slots(assigned)), "invalid backpack hotbar assignments unchanged")
	var assigned_to_empty := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	InventoryTestFixture.restore_slot(assigned_to_empty, InventoryModel.HOTBAR_SIZE, InventoryStack.new(grass_id, 4))
	var assigned_to_empty_loadout := InventoryTestFixture.create_loadout(assigned_to_empty)
	_assert(assigned_to_empty_loadout.assign_slot_to_hotbar(InventoryModel.HOTBAR_SIZE, 2), "empty hotbar assignment succeeds")
	_assert(assigned_to_empty.get_slot(InventoryModel.HOTBAR_SIZE) == null, "empty hotbar assignment clears backpack slot")
	_assert(assigned_to_empty.get_slot(2).item_id == grass_id and assigned_to_empty.get_slot(2).count == 4, "empty hotbar receives backpack item")
	var reassigned := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	InventoryTestFixture.restore_slot(reassigned, 2, InventoryStack.new(grass_id, 4))
	InventoryTestFixture.restore_slot(reassigned, 4, InventoryStack.new(stone_id, 6))
	var reassigned_loadout := InventoryTestFixture.create_loadout(reassigned)
	var reassigned_totals := _compute_totals(reassigned)
	_assert(reassigned_loadout.assign_slot_to_hotbar(2, 4), "hotbar reassignment succeeds")
	_assert(reassigned.get_slot(2).item_id == stone_id and reassigned.get_slot(2).count == 6, "reassigned hotbar destination swaps back")
	_assert(reassigned.get_slot(4).item_id == grass_id and reassigned.get_slot(4).count == 4, "hotbar item assigned to another hotkey")
	_assert(_compute_totals(reassigned) == reassigned_totals, "hotbar reassignment conserves totals")
	_assert(assigned_to_empty_loadout.move_hotbar_slot_to_backpack(2), "hotbar item moves to backpack")
	_assert(assigned_to_empty.get_slot(2) == null, "hotbar to backpack move clears hotbar slot")
	_assert(assigned_to_empty.get_slot(InventoryModel.HOTBAR_SIZE).item_id == grass_id and assigned_to_empty.get_slot(InventoryModel.HOTBAR_SIZE).count == 4, "backpack receives hotbar item")

	var merged_into_backpack := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	InventoryTestFixture.restore_slot(merged_into_backpack, 0, InventoryStack.new(grass_id, 4))
	InventoryTestFixture.restore_slot(merged_into_backpack, InventoryModel.HOTBAR_SIZE, InventoryStack.new(grass_id, 97))
	var merged_into_backpack_loadout := InventoryTestFixture.create_loadout(merged_into_backpack)
	_assert(merged_into_backpack_loadout.move_hotbar_slot_to_backpack(0), "hotbar item merges into backpack")
	_assert(merged_into_backpack.get_slot(0) == null, "merged hotbar stack cleared")
	_assert(merged_into_backpack.get_slot(InventoryModel.HOTBAR_SIZE).count == 99, "existing backpack stack filled first")
	_assert(merged_into_backpack.get_slot(InventoryModel.HOTBAR_SIZE + 1).count == 2, "merge remainder moved to empty backpack slot")

	var full_backpack := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	InventoryTestFixture.restore_slot(full_backpack, 0, InventoryStack.new(grass_id, 4))
	for backpack_idx in range(InventoryModel.HOTBAR_SIZE, InventoryModel.FILLABLE_SIZE):
		InventoryTestFixture.restore_slot(full_backpack, backpack_idx, InventoryStack.new(stone_id, 99))
	var full_backpack_loadout := InventoryTestFixture.create_loadout(full_backpack)
	var full_backpack_before := _copy_stacks(InventoryTestFixture.get_slots(full_backpack))
	_assert(not full_backpack_loadout.move_hotbar_slot_to_backpack(0), "full backpack rejects hotbar move")
	_assert(_slots_equal(full_backpack_before, InventoryTestFixture.get_slots(full_backpack)), "failed hotbar move leaves inventory unchanged")

	var equipment := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	InventoryTestFixture.restore_slot(equipment, 0, InventoryStack.new(torch_id, 5))
	var equipment_loadout := InventoryTestFixture.create_loadout(equipment)
	for index in range(InventoryModel.FILLABLE_SIZE, equipment.get_size()):
		_assert(not equipment_loadout.handle_drop(0, index, 5), "non-armor equipment drop rejected")
	_assert(equipment_loadout.discard_stack(0, 5), "non-armor equipment fixture could not be cleared")
	_assert(equipment_loadout.add_stack(_equipment_stack(equipment, helmet.id)), "armor fixture could not be added")
	var helmet_source := _find_item(equipment, helmet.id)
	var helmet_index := InventoryModel.get_equipment_index(ArmorDefinition.Slot.HEAD)
	var chest_index := InventoryModel.get_equipment_index(ArmorDefinition.Slot.CHEST)
	_assert(not equipment_loadout.handle_drop(helmet_source, chest_index, 1), "wrong armor slot rejected")
	_assert(equipment_loadout.handle_drop(helmet_source, helmet_index, 1), "matching armor drop failed")
	_assert(equipment.get_slot(helmet_index).item_id == helmet.id, "helmet did not move to equipment")
	_assert(equipment_loadout.handle_drop(helmet_index, 0, 1), "armor return to inventory failed")
	_assert(equipment.get_slot(helmet_index) == null, "helmet equipment slot did not clear")
	_assert(not equipment_loadout.handle_drop(0, 0, 1), "same slot rejected")
	_assert(not equipment_loadout.handle_drop(-1, 1, 1), "invalid source rejected")
	_assert(not equipment_loadout.handle_drop(0, 999, 1), "invalid destination rejected")

	var capped_catalog := _make_catalog(10)
	var capped_log := capped_catalog.get_item_for_block(BlockId.Type.LOG).id
	var capped := InventoryModel.new(capped_catalog, EquipmentInstanceFactory.new(capped_catalog))
	InventoryTestFixture.restore_slot(capped, 0, InventoryStack.new(capped_log, 10))
	InventoryTestFixture.restore_slot(capped, 1, InventoryStack.new(capped_log, 10))
	var capped_loadout := InventoryTestFixture.create_loadout(capped)
	var capped_before := _copy_stacks(InventoryTestFixture.get_slots(capped))
	_assert(not capped_loadout.handle_drop(0, 1, 5), "full destination rejected")
	_assert(_slots_equal(capped_before, InventoryTestFixture.get_slots(capped)), "full destination unchanged")

	var general_catalog := _make_catalog(99, true)
	var general := InventoryModel.new(general_catalog, EquipmentInstanceFactory.new(general_catalog))
	var tool_batch: Array[StringName] = [&"test_tool"]
	var general_loadout := InventoryTestFixture.create_loadout(general)
	_assert(general_loadout.add_batch(tool_batch), "non-placeable item accepted")
	_assert(general.get_selected_item_id() == &"test_tool", "non-placeable item selected")
	_assert(general_catalog.get_definition(&"test_tool").secondary_action == null, "non-placeable item has no secondary action")

	var saved_source := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	saved_source.setup_starter()
	var saved_helmet_source := _find_item(saved_source, &"copper_helmet")
	_assert(saved_helmet_source >= 0, "starter helmet missing")
	var saved_source_loadout := InventoryTestFixture.create_loadout(saved_source)
	_assert(saved_source_loadout.handle_drop(saved_helmet_source, InventoryModel.get_equipment_index(ArmorDefinition.Slot.HEAD), 1), "starter helmet equip before save failed")
	var encoded := saved_source.to_dict()
	var encoded_slot = encoded["regions"]["hotbar"][3]
	_assert(encoded_slot["item_id"] is String, "save item ID is string")
	_assert(not encoded_slot.has("type"), "old save key absent")
	_assert(saved_source.get_slot(3).item_id == &"copper_sword", "starter sword missing")
	var restored := InventoryModel.new(
		catalog,
		EquipmentInstanceFactory.new(catalog, saved_source.equipment_instance_factory.get_next_instance_id())
	)
	_assert(restored.from_dict(encoded), "version 3 inventory restores")
	_assert(_slots_equal(InventoryTestFixture.get_slots(saved_source), InventoryTestFixture.get_slots(restored)), "save round trip")
	_assert(restored.get_equipped_armor(ArmorDefinition.Slot.HEAD).id == &"copper_helmet", "equipped armor round trip failed")
	_assert(restored.get_starter_item_migration_version() == InventoryModel.STARTER_ITEM_MIGRATION_VERSION, "starter migration version round trip")
	var old_shape := encoded.duplicate(true)
	old_shape["regions"]["hotbar"][0] = {"type": 1, "count": 12}
	_assert(not restored.from_dict(old_shape), "old inventory shape rejected")
	var short_region := encoded.duplicate(true)
	short_region["regions"]["hotbar"].pop_back()
	_assert(not restored.from_dict(short_region), "short inventory region rejected")
	var long_region := encoded.duplicate(true)
	long_region["regions"]["hotbar"].append(null)
	_assert(not restored.from_dict(long_region), "long inventory region rejected")
	var occupied_equipment := encoded.duplicate(true)
	occupied_equipment["regions"]["equipment"][0] = {"item_id": String(grass_id), "count": 1, "equipment_instance": null}
	_assert(not restored.from_dict(occupied_equipment), "non-armor equipment save rejected")
	var restored_before_invalid_metadata := restored.to_dict()
	var restored_revision_before_invalid_metadata := restored.get_revision()
	var restored_change_count := [0]
	var restored_observer := func(): restored_change_count[0] += 1
	restored.inventory_changed.connect(restored_observer)
	var invalid_regions := encoded.duplicate(true)
	invalid_regions["regions"] = []
	_assert(not restored.from_dict(invalid_regions), "non-dictionary inventory regions accepted")
	_assert(restored.to_dict() == restored_before_invalid_metadata, "invalid inventory regions changed restored state")
	_assert(restored.get_revision() == restored_revision_before_invalid_metadata, "invalid inventory regions changed revision")
	var fractional_migration_version := encoded.duplicate(true)
	fractional_migration_version["starter_item_migration_version"] = 0.5
	_assert(not restored.from_dict(fractional_migration_version), "fractional starter migration version accepted")
	_assert(restored.to_dict() == restored_before_invalid_metadata, "fractional starter migration version changed restored state")
	_assert(restored.get_revision() == restored_revision_before_invalid_metadata, "fractional starter migration version changed revision")
	var fractional_selected_slot := encoded.duplicate(true)
	fractional_selected_slot["selected"] = 1.5
	_assert(not restored.from_dict(fractional_selected_slot), "fractional selected slot accepted")
	_assert(restored.to_dict() == restored_before_invalid_metadata, "fractional selected slot changed restored state")
	_assert(restored.get_revision() == restored_revision_before_invalid_metadata, "fractional selected slot changed revision")
	var out_of_range_selected_slot := encoded.duplicate(true)
	out_of_range_selected_slot["selected"] = InventoryModel.HOTBAR_SIZE
	_assert(not restored.from_dict(out_of_range_selected_slot), "out-of-range selected slot accepted")
	_assert(restored.to_dict() == restored_before_invalid_metadata, "out-of-range selected slot changed restored state")
	_assert(restored.get_revision() == restored_revision_before_invalid_metadata, "out-of-range selected slot changed revision")
	_assert(restored_change_count[0] == 0, "invalid inventory metadata emitted inventory changes")
	restored.inventory_changed.disconnect(restored_observer)

	_assert(_validate_inv(moved), "moved inventory valid")
	_assert(_validate_inv(split), "split inventory valid")
	_assert(_validate_inv(discarded), "discarded inventory valid")
	_assert(_validate_inv(merged), "merged inventory valid")
	_assert(_validate_inv(overflow), "overflow inventory valid")
	_assert(_validate_inv(assigned), "assigned inventory valid")
	_assert(_validate_inv(assigned_to_empty), "empty hotbar assignment inventory valid")
	_assert(_validate_inv(reassigned), "reassigned hotbar inventory valid")
	_assert(_validate_inv(merged_into_backpack), "merged backpack inventory valid")
	_assert(_validate_inv(full_backpack), "full backpack inventory valid")
	print("[edge] done failures=%d" % _failures)
	return _failures == 0

func _run_raw_throughput() -> bool:
	print("[perf] measuring raw model throughput")
	_tests_run += 1
	var catalog := _make_catalog(99)
	var inv := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	InventoryTestFixture.restore_slot(inv, 0, InventoryStack.new(catalog.get_item_for_block(BlockId.Type.GRASS).id, 50))
	InventoryTestFixture.restore_slot(inv, 1, InventoryStack.new(catalog.get_item_for_block(BlockId.Type.STONE).id, 50))
	InventoryTestFixture.restore_slot(inv, 2, InventoryStack.new(catalog.get_item_for_block(BlockId.Type.DIRT).id, 50))
	var rng := RandomNumberGenerator.new()
	rng.seed = 987654321
	var loadout := InventoryTestFixture.create_loadout(inv)
	assert(loadout != null)
	var operations := 300000
	var started := Time.get_ticks_msec()
	for _index in range(operations):
		var source := rng.randi_range(0, 2)
		var destination := rng.randi_range(0, 2)
		if destination == source:
			destination = (destination + 1) % 3
		loadout.can_handle_drop(source, destination, rng.randi_range(1, 2))
	var elapsed: int = max(1, Time.get_ticks_msec() - started)
	var rate: float = float(operations) / elapsed * 1000.0
	print("[perf] can_handle_drop: %.0f ops/s" % rate)
	_assert(rate > 50000, "raw throughput sanity")
	return _failures == 0

func _run_add_batch_properties() -> bool:
	print("[add_batch] starting")
	_tests_run += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x12345678
	for iteration in range(5000):
		var max_stack := MAX_STACK_OPTIONS[rng.randi_range(0, MAX_STACK_OPTIONS.size() - 1)]
		var catalog := _make_catalog(max_stack)
		var inv := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
		var loadout := InventoryTestFixture.create_loadout(inv)
		assert(loadout != null)
		var batch := _random_batch(rng, rng.randi_range(0, 20))
		var before := _copy_stacks(InventoryTestFixture.get_slots(inv))
		var can_add := loadout.can_add_batch(batch)
		var added := loadout.add_batch(batch)
		_assert(can_add == added, "add_batch can matches result")
		var mutated := not _slots_equal(before, InventoryTestFixture.get_slots(inv))
		if batch.is_empty():
			_assert(not mutated, "empty batch unchanged")
		else:
			_assert(mutated == can_add, "batch mutation matches result")
		if not can_add:
			_assert(_slots_equal(before, InventoryTestFixture.get_slots(inv)), "failed batch unchanged")
		_assert(_validate_inv(inv), "batch inventory valid")
		if _failures > 0:
			print("[add_batch] failed at iteration %d" % iteration)
			return false
	print("[add_batch] done")
	return true

func _run_fuzz(sequence_count: int, operations_per_sequence: int) -> bool:
	print("[fuzz] starting seqs=%d ops_per_seq=%d total_ops=%d seed=%d" % [sequence_count, operations_per_sequence, sequence_count * operations_per_sequence, _rng.seed])
	_tests_run += 1
	var started := Time.get_ticks_msec()
	for sequence_index in range(sequence_count):
		var state := _make_random_inventory(_rng)
		var inv := state["inventory"] as InventoryModel
		var loadout := state["loadout"] as InventoryLoadoutCoordinator
		var initial_totals := _compute_totals(inv)
		for operation_index in range(operations_per_sequence):
			var source := _rng.randi_range(-5, inv.get_size() + 4) if _rng.randf() < 0.06 else _rng.randi_range(0, inv.get_size() - 1)
			var destination := _rng.randi_range(-5, inv.get_size() + 4) if _rng.randf() < 0.06 else _rng.randi_range(0, inv.get_size() - 1)
			if _rng.randf() < 0.35:
				source = destination
			var source_slot = inv.get_slot(source) if source >= 0 and source < inv.get_size() else null
			var drag: int
			if source_slot == null:
				drag = _rng.randi_range(-2, 6)
			else:
				var coin := _rng.randf()
				if coin < 0.62:
					drag = _rng.randi_range(1, source_slot.count)
				elif coin < 0.75:
					drag = 0
				elif coin < 0.85:
					drag = -_rng.randi_range(1, 3)
				elif coin < 0.92:
					drag = source_slot.count + _rng.randi_range(1, 5)
				else:
					drag = source_slot.count
			var before_slots := _copy_stacks(InventoryTestFixture.get_slots(inv))
			var before_totals := _compute_totals(inv)
			var can_drop := loadout.can_handle_drop(source, destination, drag)
			var dropped := loadout.handle_drop(source, destination, drag)
			var mutated := not _slots_equal(before_slots, InventoryTestFixture.get_slots(inv))
			if not _assert(can_drop == dropped, "can/result mismatch seq %d op %d" % [sequence_index, operation_index]):
				return false
			if not _assert(mutated == can_drop, "mutation/result mismatch seq %d op %d" % [sequence_index, operation_index]):
				return false
			if not _assert(_compute_totals(inv) == before_totals, "operation conservation"):
				return false
			if not _assert(_compute_totals(inv) == initial_totals, "sequence conservation"):
				return false
			if not _assert(_validate_inv(inv), "inventory valid after drop"):
				return false
		if sequence_index > 0 and sequence_index % 10000 == 0:
			var elapsed: int = max(1, Time.get_ticks_msec() - started)
			var completed := (sequence_index + 1) * operations_per_sequence
			print("[fuzz] progress %d/%d seqs rate %.0f ops/s" % [sequence_index, sequence_count, float(completed) / elapsed * 1000.0])
	var elapsed_total: int = max(1, Time.get_ticks_msec() - started)
	var total_operations := sequence_count * operations_per_sequence
	print("[fuzz] done seqs=%d ops=%d elapsed=%d ms rate=%.0f ops/s failures=%d" % [sequence_count, total_operations, elapsed_total, float(total_operations) / elapsed_total * 1000.0, _failures])
	return _failures == 0
