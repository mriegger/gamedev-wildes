extends RefCounted
class_name InventoryModel

signal inventory_changed()

const HOTBAR_SIZE: int = 9
const BACKPACK_SIZE: int = 40
const EQUIPMENT_SIZE: int = ArmorDefinition.SLOT_COUNT
const REGIONS: Array = [
	{"name": "hotbar", "start": 0, "size": HOTBAR_SIZE},
	{"name": "backpack", "start": HOTBAR_SIZE, "size": BACKPACK_SIZE},
	{"name": "equipment", "start": HOTBAR_SIZE + BACKPACK_SIZE, "size": EQUIPMENT_SIZE},
]
const TOTAL_SIZE: int = HOTBAR_SIZE + BACKPACK_SIZE + EQUIPMENT_SIZE
const DEFAULT_SIZE: int = TOTAL_SIZE
const FILLABLE_SIZE: int = HOTBAR_SIZE + BACKPACK_SIZE
const STARTER_ITEM_MIGRATION_VERSION: int = 3
const STARTER_ITEMS_BY_SLOT: Dictionary[int, StringName] = {
	3: &"copper_sword",
	FILLABLE_SIZE - 5: &"copper_helmet",
	FILLABLE_SIZE - 4: &"copper_chest_plate",
	FILLABLE_SIZE - 3: &"copper_pants",
	FILLABLE_SIZE - 2: &"copper_shoes",
	FILLABLE_SIZE - 1: &"test_totem",
}

var _size: int = TOTAL_SIZE
var item_catalog: ItemCatalog
var equipment_instance_factory: EquipmentInstanceFactory

var _slots: Array[InventoryStack] = []
var _selected_slot: int = 0
var _starter_item_migration_version: int = 0
var _revision: int = 0
var _runtime_bound: bool = false

func _init(
	p_item_catalog: ItemCatalog,
	p_equipment_instance_factory: EquipmentInstanceFactory,
	p_size: int = DEFAULT_SIZE,
):
	assert(p_item_catalog != null)
	assert(p_equipment_instance_factory != null)
	assert(p_equipment_instance_factory.item_catalog == p_item_catalog)
	assert(p_size >= HOTBAR_SIZE and p_size <= TOTAL_SIZE)
	item_catalog = p_item_catalog
	equipment_instance_factory = p_equipment_instance_factory
	_size = p_size
	_slots.resize(_size)
	_slots.fill(null)
	_selected_slot = 0

func get_slot(idx: int) -> InventoryStack:
	if idx < 0 or idx >= _size:
		return null
	return null if _slots[idx] == null else _slots[idx].copy()

func get_selected_slot() -> int:
	return _selected_slot

func get_size() -> int:
	return _size

func get_revision() -> int:
	return _revision

func get_starter_item_migration_version() -> int:
	return _starter_item_migration_version

func _can_bind_runtime() -> bool:
	return not _runtime_bound

func _bind_runtime() -> bool:
	if not _can_bind_runtime():
		return false
	_runtime_bound = true
	return true

func has_item(item_id: StringName) -> bool:
	if not item_catalog.has_definition(item_id):
		return false
	for stack in _slots:
		if stack != null and stack.item_id == item_id:
			return true
	return false

func prepare_add_stack(stack: InventoryStack) -> PreparedInventoryChange:
	var simulated := _create_simulation()
	if not simulated._apply_add_stack(stack):
		return null
	return _prepare_simulated_change(simulated)

func prepare_add_stack_up_to(stack: InventoryStack) -> PreparedInventoryChange:
	var simulated := _create_simulation()
	var accepted := simulated._apply_add_stack_up_to(stack)
	if accepted == null:
		return null
	return _prepare_simulated_change(simulated, accepted)

func prepare_remove_stack(source_index: int, count: int = -1) -> PreparedInventoryChange:
	var simulated := _create_simulation()
	var removed := simulated._apply_remove_stack(source_index, count)
	if removed == null:
		return null
	return _prepare_simulated_change(simulated, removed)

func prepare_select_slot(index: int) -> PreparedInventoryChange:
	var simulated := _create_simulation()
	if not simulated._apply_select_slot(index):
		return null
	return _prepare_simulated_change(simulated)

func prepare_assign_slot_to_hotbar(source_index: int, hotbar_index: int) -> PreparedInventoryChange:
	var simulated := _create_simulation()
	if not simulated._apply_assign_slot_to_hotbar(source_index, hotbar_index):
		return null
	return _prepare_simulated_change(simulated)

func prepare_move_hotbar_slot_to_backpack(hotbar_index: int) -> PreparedInventoryChange:
	var simulated := _create_simulation()
	if not simulated._apply_move_hotbar_slot_to_backpack(hotbar_index):
		return null
	return _prepare_simulated_change(simulated)

func prepare_discard_stack(source_index: int, count: int) -> PreparedInventoryChange:
	var simulated := _create_simulation()
	if not simulated._apply_discard_stack(source_index, count):
		return null
	return _prepare_simulated_change(simulated)

func prepare_ensure_item(item_id: StringName) -> PreparedInventoryChange:
	if has_item(item_id):
		return null
	var simulated := _create_simulation()
	if not simulated._apply_ensure_item(item_id):
		return null
	return _prepare_simulated_change(simulated)

func prepare_starter_item_migration() -> PreparedInventoryChange:
	if _starter_item_migration_version >= STARTER_ITEM_MIGRATION_VERSION:
		return null
	var simulated := _create_simulation()
	if not simulated._apply_migrate_starter_items():
		return null
	return _prepare_simulated_change(simulated)

func prepare_add_backpack_item(item_id: StringName, count: int) -> PreparedInventoryChange:
	var simulated := _create_simulation()
	if not simulated._apply_add_backpack_item(item_id, count):
		return null
	return _prepare_simulated_change(simulated)

func prepare_inventory_exchange(
	consumed: Dictionary[StringName, int],
	granted: Dictionary[StringName, int],
) -> PreparedInventoryChange:
	var simulated := _create_simulation()
	if not simulated._apply_exchange_inventory_items(consumed, granted, simulated.equipment_instance_factory):
		return null
	return _prepare_simulated_change(simulated)

func prepare_add_batch(ids: Array[StringName]) -> PreparedInventoryChange:
	var simulated := _create_simulation()
	if not simulated._apply_add_batch(ids):
		return null
	return _prepare_simulated_change(simulated)

func prepare_consume_selected() -> PreparedInventoryChange:
	var simulated := _create_simulation()
	if not simulated._apply_consume_selected():
		return null
	return _prepare_simulated_change(simulated)

func prepare_handle_drop(source_index: int, destination_index: int, drag_count: int) -> PreparedInventoryChange:
	var simulated := _create_simulation()
	if not simulated._apply_handle_drop(source_index, destination_index, drag_count):
		return null
	return _prepare_simulated_change(simulated)

func prepare_replace_stack_at(
	index: int,
	expected_stack: InventoryStack,
	replacement_stack: InventoryStack,
) -> PreparedInventoryChange:
	var simulated := _create_simulation()
	if not simulated._apply_replace_stack_at(index, expected_stack, replacement_stack):
		return null
	return _prepare_simulated_change(simulated, expected_stack)

func prepare_socketed_rune(
	gear_index: int,
	expected_rune_ids: Array[StringName],
	next_rune_ids: Array[StringName],
	rune_source_index: int,
	rune_id: StringName,
) -> PreparedInventoryChange:
	var simulated := _create_simulation()
	if not simulated._apply_socketed_rune(
		gear_index,
		expected_rune_ids,
		next_rune_ids,
		rune_source_index,
		rune_id,
	):
		return null
	return _prepare_simulated_change(simulated)

func prepare_unsocketed_rune(
	gear_index: int,
	expected_rune_ids: Array[StringName],
	next_rune_ids: Array[StringName],
	returned_rune_id: StringName,
) -> PreparedInventoryChange:
	var simulated := _create_simulation()
	if not simulated._apply_unsocketed_rune(
		gear_index,
		expected_rune_ids,
		next_rune_ids,
		returned_rune_id,
	):
		return null
	return _prepare_simulated_change(simulated)

func can_commit_prepared_change(prepared: PreparedInventoryChange) -> bool:
	return (
		prepared != null
		and prepared._is_for(self)
		and prepared.get_expected_revision() == _revision
		and prepared._get_expected_next_instance_id() == equipment_instance_factory.get_next_instance_id()
		and prepared.get_size() == _size
	)

func _commit_prepared_change(prepared: PreparedInventoryChange, emit_signal: bool = true) -> void:
	assert(can_commit_prepared_change(prepared))
	var advanced := equipment_instance_factory.try_advance_next_instance_id(
		prepared._get_expected_next_instance_id(),
		prepared._get_next_instance_id(),
	)
	assert(advanced)
	_slots = prepared._copy_committed_slots()
	_selected_slot = prepared.get_selected_slot()
	_starter_item_migration_version = prepared._get_starter_item_migration_version()
	_revision += 1
	if emit_signal:
		inventory_changed.emit()

func _emit_inventory_changed() -> void:
	inventory_changed.emit()

func _create_simulation() -> InventoryModel:
	var simulated := InventoryModel.new(item_catalog, equipment_instance_factory.copy(), _size)
	simulated._slots = _copy_slots()
	simulated._selected_slot = _selected_slot
	simulated._starter_item_migration_version = _starter_item_migration_version
	simulated._revision = _revision
	return simulated

func _prepare_simulated_change(
	simulated: InventoryModel,
	result_stack: InventoryStack = null,
) -> PreparedInventoryChange:
	return PreparedInventoryChange.new(
		self,
		_revision,
		equipment_instance_factory.get_next_instance_id(),
		simulated.equipment_instance_factory.get_next_instance_id(),
		simulated._slots,
		simulated._selected_slot,
		simulated._starter_item_migration_version,
		result_stack,
	)

func _apply_add_stack(stack: InventoryStack) -> bool:
	var simulated := _simulate_stack_add(stack)
	if simulated.is_empty():
		return false
	_slots = simulated
	return true

func _apply_add_stack_up_to(stack: InventoryStack) -> InventoryStack:
	if not _is_valid_incoming_stack(stack):
		return null
	if stack.equipment_instance != null:
		return stack.copy() if _apply_add_stack(stack) else null
	var remaining := _grant_item_to_indices(
		_slots,
		stack.item_id,
		stack.count,
		item_catalog.get_definition(stack.item_id).max_stack,
		_get_backpack_indices(),
		equipment_instance_factory,
	)
	if remaining > 0:
		remaining = _grant_item_to_indices(
			_slots,
			stack.item_id,
			remaining,
			item_catalog.get_definition(stack.item_id).max_stack,
			_get_hotbar_indices(),
			equipment_instance_factory,
		)
	var accepted_count := stack.count - remaining
	return null if accepted_count == 0 else InventoryStack.new(stack.item_id, accepted_count)

func _can_remove_stack(source_index: int, count: int = -1) -> bool:
	if source_index < 0 or source_index >= mini(_size, FILLABLE_SIZE):
		return false
	var stack := _slots[source_index]
	if stack == null:
		return false
	var removed_count := stack.count if count == -1 else count
	if removed_count < 1 or removed_count > stack.count:
		return false
	return not stack.has_instance_data() or removed_count == stack.count

func _apply_remove_stack(source_index: int, count: int = -1) -> InventoryStack:
	if not _can_remove_stack(source_index, count):
		return null
	var stack := _slots[source_index]
	var removed_count := stack.count if count == -1 else count
	var removed := InventoryStack.new(stack.item_id, removed_count, stack.equipment_instance)
	stack.count -= removed_count
	if stack.count == 0:
		_slots[source_index] = null
	return removed

func get_selected_data() -> InventoryStack:
	return get_slot(_selected_slot)

func get_selected_item_id():
	var stack := get_selected_data()
	if stack == null:
		return null
	return stack.item_id

func create_selected_item_source() -> SelectedItemSource:
	var stack := get_selected_data()
	return SelectedItemSource.new(
		self,
		_selected_slot,
		&"" if stack == null else stack.item_id,
		_get_stack_instance_id(stack),
		_get_stack_fingerprint(stack),
	)

func is_selected_item_source_current(source: SelectedItemSource) -> bool:
	if source == null:
		return false
	var stack := get_selected_data()
	return source._matches(
		self,
		_selected_slot,
		&"" if stack == null else stack.item_id,
		_get_stack_instance_id(stack),
		_get_stack_fingerprint(stack),
	)

func prepare_consume_selected_source(source: SelectedItemSource) -> PreparedInventoryChange:
	if not is_selected_item_source_current(source):
		return null
	return prepare_consume_selected()

func get_socketed_rune_ids(idx: int) -> Array[StringName]:
	var stack := get_slot(idx)
	var rune_ids: Array[StringName] = []
	if stack != null and stack.equipment_instance != null:
		rune_ids.assign(stack.equipment_instance.socketed_rune_ids)
	return rune_ids

func get_equipment_instance_copy(idx: int) -> EquipmentInstance:
	var stack := get_slot(idx)
	return null if stack == null or stack.equipment_instance == null else stack.equipment_instance.copy()

func _apply_select_slot(idx: int) -> bool:
	if not is_hotbar_index(idx):
		return false
	if idx == _selected_slot:
		return false
	_selected_slot = idx
	return true

func _apply_assign_slot_to_hotbar(source_idx: int, hotbar_idx: int) -> bool:
	if source_idx < 0 or source_idx >= min(_size, FILLABLE_SIZE):
		return false
	if not is_hotbar_index(hotbar_idx) or hotbar_idx >= _size:
		return false
	if source_idx == hotbar_idx:
		return false
	var source_stack := _slots[source_idx]
	if source_stack == null or not can_slot_accept_item_id(hotbar_idx, source_stack.item_id):
		return false
	var hotbar_stack := _slots[hotbar_idx]
	if hotbar_stack != null and not can_slot_accept_item_id(source_idx, hotbar_stack.item_id):
		return false
	_slots[source_idx] = hotbar_stack
	_slots[hotbar_idx] = source_stack
	return true

func _apply_move_hotbar_slot_to_backpack(hotbar_idx: int) -> bool:
	if not is_hotbar_index(hotbar_idx) or hotbar_idx >= _size:
		return false
	var hotbar_stack := _slots[hotbar_idx]
	if hotbar_stack == null:
		return false
	var max_stack: int = item_catalog.get_definition(hotbar_stack.item_id).max_stack
	var backpack_end: int = mini(_size, FILLABLE_SIZE)
	var available_capacity: int = 0
	for backpack_idx in range(HOTBAR_SIZE, backpack_end):
		var backpack_stack := _slots[backpack_idx]
		if backpack_stack == null:
			available_capacity += max_stack
		elif backpack_stack.item_id == hotbar_stack.item_id and not backpack_stack.has_instance_data() and not hotbar_stack.has_instance_data():
			available_capacity += max_stack - backpack_stack.count
	if available_capacity < hotbar_stack.count:
		return false
	var remaining: int = hotbar_stack.count
	for backpack_idx in range(HOTBAR_SIZE, backpack_end):
		var backpack_stack := _slots[backpack_idx]
		if backpack_stack == null or backpack_stack.item_id != hotbar_stack.item_id or backpack_stack.has_instance_data() or hotbar_stack.has_instance_data():
			continue
		var moved := mini(remaining, max_stack - backpack_stack.count)
		backpack_stack.count += moved
		remaining -= moved
		if remaining == 0:
			break
	if remaining > 0:
		for backpack_idx in range(HOTBAR_SIZE, backpack_end):
			if _slots[backpack_idx] == null:
				if remaining == hotbar_stack.count:
					_slots[backpack_idx] = hotbar_stack
				else:
					assert(not hotbar_stack.has_instance_data())
					_slots[backpack_idx] = InventoryStack.new(hotbar_stack.item_id, remaining)
				remaining = 0
				break
	assert(remaining == 0)
	_slots[hotbar_idx] = null
	return true

func _can_discard_stack(source_index: int, count: int) -> bool:
	if source_index < 0 or source_index >= mini(_size, TOTAL_SIZE):
		return false
	var stack := _slots[source_index]
	return stack != null and count > 0 and count <= stack.count

func _apply_discard_stack(source_index: int, count: int) -> bool:
	if not _can_discard_stack(source_index, count):
		return false
	var stack := _slots[source_index]
	stack.count -= count
	if stack.count == 0:
		_slots[source_index] = null
	return true

func _apply_ensure_item(item_id: StringName) -> bool:
	if not item_catalog.has_definition(item_id):
		return false
	for stack in _slots:
		if stack != null and stack.item_id == item_id:
			return true
	for index in range(min(_size, HOTBAR_SIZE)):
		if _slots[index] == null:
			_slots[index] = _create_stack(item_id, 1, equipment_instance_factory)
			if _slots[index] == null:
				return false
			return true
	for index in range(HOTBAR_SIZE, min(_size, FILLABLE_SIZE)):
		if _slots[index] == null:
			_slots[index] = _slots[0]
			_slots[0] = _create_stack(item_id, 1, equipment_instance_factory)
			if _slots[0] == null:
				return false
			return true
	return false

func _apply_migrate_starter_items() -> bool:
	if _starter_item_migration_version >= STARTER_ITEM_MIGRATION_VERSION:
		return true
	var expected_next_instance_id := equipment_instance_factory.get_next_instance_id()
	var simulated_factory := equipment_instance_factory.copy()
	var simulated := InventoryModel.new(item_catalog, simulated_factory, _size)
	simulated._slots = _copy_slots()
	for starter_slot in STARTER_ITEMS_BY_SLOT:
		var item_id: StringName = STARTER_ITEMS_BY_SLOT[starter_slot]
		var item_ensured := simulated._apply_ensure_item(item_id) if starter_slot < HOTBAR_SIZE else simulated._apply_ensure_backpack_item(item_id)
		if not item_ensured:
			return false
	if not equipment_instance_factory.try_advance_next_instance_id(
		expected_next_instance_id,
		simulated_factory.get_next_instance_id(),
	):
		return false
	_slots = simulated._slots
	_starter_item_migration_version = STARTER_ITEM_MIGRATION_VERSION
	return true

func _apply_ensure_backpack_item(item_id: StringName) -> bool:
	if not item_catalog.has_definition(item_id):
		return false
	for stack in _slots:
		if stack != null and stack.item_id == item_id:
			return true
	for index in range(HOTBAR_SIZE, min(_size, FILLABLE_SIZE)):
		if _slots[index] == null:
			_slots[index] = _create_stack(item_id, 1, equipment_instance_factory)
			if _slots[index] == null:
				return false
			return true
	return false

func get_backpack_item_count(item_id: StringName) -> int:
	if not item_catalog.has_definition(item_id):
		return 0
	var total := 0
	for index in range(HOTBAR_SIZE, min(_size, FILLABLE_SIZE)):
		var stack := _slots[index]
		if stack != null and stack.item_id == item_id:
			total += stack.count
	return total

func _apply_add_backpack_item(item_id: StringName, count: int) -> bool:
	if count < 1 or not item_catalog.has_definition(item_id):
		return false
	var expected_next_instance_id := equipment_instance_factory.get_next_instance_id()
	var simulated := _copy_slots()
	var simulated_factory := equipment_instance_factory.copy()
	var max_stack: int = item_catalog.get_definition(item_id).max_stack
	var remaining := _grant_item_to_indices(simulated, item_id, count, max_stack, _get_backpack_indices(), simulated_factory)
	if remaining > 0:
		return false
	if not equipment_instance_factory.try_advance_next_instance_id(
		expected_next_instance_id,
		simulated_factory.get_next_instance_id(),
	):
		return false
	_slots = simulated
	return true

func get_inventory_item_count(item_id: StringName) -> int:
	if not item_catalog.has_definition(item_id):
		return 0
	var total := 0
	for index in _get_inventory_indices():
		var stack := _slots[index]
		if stack != null and stack.item_id == item_id:
			total += stack.count
	return total

func _apply_exchange_inventory_items(
	consumed: Dictionary[StringName, int],
	granted: Dictionary[StringName, int],
	creation_factory: EquipmentInstanceFactory,
) -> bool:
	assert(creation_factory == equipment_instance_factory)
	var expected_next_instance_id := creation_factory.get_next_instance_id()
	var simulated_factory := creation_factory.copy()
	var simulated := _simulate_inventory_exchange(consumed, granted, simulated_factory)
	if simulated.is_empty():
		return false
	if not creation_factory.try_advance_next_instance_id(
		expected_next_instance_id,
		simulated_factory.get_next_instance_id(),
	):
		return false
	_slots = simulated
	return true

func _simulate_inventory_exchange(
	consumed: Dictionary[StringName, int],
	granted: Dictionary[StringName, int],
	simulated_factory: EquipmentInstanceFactory,
) -> Array[InventoryStack]:
	if consumed.is_empty() and granted.is_empty():
		return []
	var simulated := _copy_slots()
	var inventory_indices := _get_inventory_indices()
	for item_id in consumed:
		var remaining: int = consumed[item_id]
		if remaining < 1 or not item_catalog.has_definition(item_id):
			return []
		for index in inventory_indices:
			var stack := simulated[index]
			if stack == null or stack.item_id != item_id or stack.has_instance_data():
				continue
			var removed: int = mini(stack.count, remaining)
			stack.count -= removed
			remaining -= removed
			if stack.count == 0:
				simulated[index] = null
			if remaining == 0:
				break
		if remaining > 0:
			return []
	for item_id in granted:
		var remaining: int = granted[item_id]
		if remaining < 1 or not item_catalog.has_definition(item_id):
			return []
		var max_stack: int = item_catalog.get_definition(item_id).max_stack
		remaining = _grant_item_to_indices(simulated, item_id, remaining, max_stack, _get_backpack_indices(), simulated_factory)
		if remaining > 0:
			remaining = _grant_item_to_indices(simulated, item_id, remaining, max_stack, _get_hotbar_indices(), simulated_factory)
		if remaining > 0:
			return []
	return simulated

func _get_inventory_indices() -> Array[int]:
	var indices := _get_backpack_indices()
	indices.append_array(_get_hotbar_indices())
	return indices

func _get_backpack_indices() -> Array[int]:
	var indices: Array[int] = []
	# Prefer the backpack so crafting does not disturb hotbar assignments unless needed.
	for index in range(HOTBAR_SIZE, mini(_size, FILLABLE_SIZE)):
		indices.append(index)
	return indices

func _get_hotbar_indices() -> Array[int]:
	var indices: Array[int] = []
	for index in range(mini(_size, HOTBAR_SIZE)):
		indices.append(index)
	return indices

func _simulate_stack_add(stack: InventoryStack) -> Array[InventoryStack]:
	var simulated := _copy_slots()
	if not _try_add_stack_to_slots(stack, simulated):
		return []
	return simulated

func _try_add_stack_to_slots(stack: InventoryStack, simulated: Array[InventoryStack]) -> bool:
	if not _is_valid_incoming_stack(stack):
		return false
	if stack.has_instance_data():
		for existing_stack in simulated:
			if (
				existing_stack != null
				and existing_stack.equipment_instance != null
				and existing_stack.equipment_instance.instance_id == stack.equipment_instance.instance_id
			):
				return false
		for index in _get_inventory_indices():
			if simulated[index] == null:
				simulated[index] = stack.copy()
				return true
		return false
	var remaining := _grant_item_to_indices(
		simulated,
		stack.item_id,
		stack.count,
		item_catalog.get_definition(stack.item_id).max_stack,
		_get_backpack_indices(),
		equipment_instance_factory,
	)
	if remaining > 0:
		remaining = _grant_item_to_indices(
			simulated,
			stack.item_id,
			remaining,
			item_catalog.get_definition(stack.item_id).max_stack,
			_get_hotbar_indices(),
			equipment_instance_factory,
		)
	return remaining == 0

func _is_valid_incoming_stack(stack: InventoryStack) -> bool:
	return (
		stack != null
		and stack.count >= 1
		and item_catalog.has_definition(stack.item_id)
		and stack.count <= item_catalog.get_definition(stack.item_id).max_stack
		and _is_valid_stack(stack)
	)

func _grant_item_to_indices(
	simulated: Array[InventoryStack],
	item_id: StringName,
	count: int,
	max_stack: int,
	indices: Array[int],
	creation_factory: EquipmentInstanceFactory,
) -> int:
	var remaining := count
	for index in indices:
		var stack := simulated[index]
		if stack == null or stack.item_id != item_id or stack.has_instance_data() or stack.count >= max_stack:
			continue
		var added: int = mini(remaining, max_stack - stack.count)
		stack.count += added
		remaining -= added
		if remaining == 0:
			return 0
	for index in indices:
		if simulated[index] != null:
			continue
		var stack_count: int = mini(remaining, max_stack)
		var created_stack := _create_stack(item_id, stack_count, creation_factory)
		if created_stack == null:
			return remaining
		simulated[index] = created_stack
		remaining -= stack_count
		if remaining == 0:
			return 0
	return remaining

func _copy_slots() -> Array[InventoryStack]:
	var copied: Array[InventoryStack] = []
	copied.resize(_size)
	for index in range(_size):
		if _slots[index] != null:
			copied[index] = _slots[index].copy()
	return copied

func _get_stack_instance_id(stack: InventoryStack) -> int:
	if stack == null or stack.equipment_instance == null:
		return 0
	return stack.equipment_instance.instance_id

func _get_stack_fingerprint(stack: InventoryStack) -> String:
	return "" if stack == null else JSON.stringify(stack.to_dict())

func _create_stack(
	item_id: StringName,
	count: int,
	creation_factory: EquipmentInstanceFactory,
) -> InventoryStack:
	if count < 1 or not item_catalog.has_definition(item_id):
		return null
	var definition := item_catalog.get_definition(item_id)
	if definition.equipment_type == null:
		return InventoryStack.new(item_id, count)
	if count != 1:
		return null
	var instance := creation_factory.create(item_id)
	return null if instance == null else InventoryStack.new(item_id, 1, instance)

func _is_valid_stack(stack: InventoryStack) -> bool:
	if stack == null or not item_catalog.has_definition(stack.item_id):
		return false
	var definition := item_catalog.get_definition(stack.item_id)
	if definition.equipment_type == null:
		return stack.equipment_instance == null
	return stack.count == 1 and equipment_instance_factory.is_valid_instance(stack.item_id, stack.equipment_instance)

func _simulate_slots(ids: Array[StringName], simulated_factory: EquipmentInstanceFactory) -> Array[InventoryStack]:
	var sim := _copy_slots()
	for item_id in ids:
		if item_id.is_empty() or not item_catalog.has_definition(item_id):
			return []
		var max_stack := item_catalog.get_definition(item_id).max_stack
		var added := false
		var empty_idx := -1
		for index in range(min(_size, FILLABLE_SIZE)):
			var stack := sim[index]
			if stack == null:
				if empty_idx == -1:
					empty_idx = index
				continue
			if stack.item_id == item_id and stack.count < max_stack:
				stack.count += 1
				added = true
				break
		if added:
			continue
		if empty_idx != -1:
			var created_stack := _create_stack(item_id, 1, simulated_factory)
			if created_stack == null:
				return []
			sim[empty_idx] = created_stack
			continue
		return []
	return sim

func _apply_add_batch(ids: Array[StringName]) -> bool:
	if ids.is_empty():
		return true
	var expected_next_instance_id := equipment_instance_factory.get_next_instance_id()
	var simulated_factory := equipment_instance_factory.copy()
	var sim := _simulate_slots(ids, simulated_factory)
	if sim.is_empty():
		return false
	if not equipment_instance_factory.try_advance_next_instance_id(
		expected_next_instance_id,
		simulated_factory.get_next_instance_id(),
	):
		return false
	_slots = sim
	return true

func _apply_consume_selected() -> bool:
	if not _can_consume_selected():
		return false
	var stack := _slots[_selected_slot]
	stack.count -= 1
	if stack.count <= 0:
		_slots[_selected_slot] = null
	return true

func _can_consume_selected() -> bool:
	if not is_hotbar_index(_selected_slot):
		return false
	var stack := get_selected_data()
	return stack != null and stack.count > 0

func is_hotbar_index(idx: int) -> bool:
	return idx >= 0 and idx < min(_size, HOTBAR_SIZE)

static func is_equipment_index(idx: int) -> bool:
	return idx >= FILLABLE_SIZE and idx < TOTAL_SIZE

static func get_equipment_index(armor_slot: int) -> int:
	if not ArmorDefinition.is_valid_slot(armor_slot):
		return -1
	return FILLABLE_SIZE + armor_slot

func get_equipped_armor(armor_slot: int) -> ArmorDefinition:
	var stack := get_slot(get_equipment_index(armor_slot))
	if stack == null:
		return null
	return item_catalog.get_definition(stack.item_id) as ArmorDefinition

static func get_region_indices(region_name: String) -> Array:
	for region in REGIONS:
		if region["name"] == region_name:
			var out: Array = []
			for index in range(region["size"]):
				out.append(region["start"] + index)
			return out
	return []

func can_slot_accept_item_id(idx: int, item_id) -> bool:
	if idx < 0 or idx >= _size or not item_id is StringName or not item_catalog.has_definition(item_id):
		return false
	if idx < FILLABLE_SIZE:
		return true
	if not is_equipment_index(idx):
		return false
	var armor := item_catalog.get_definition(item_id) as ArmorDefinition
	return armor != null and get_equipment_index(armor.armor_slot) == idx

func _can_handle_drop(src_idx: int, dst_idx: int, drag_count: int) -> bool:
	if src_idx < 0 or src_idx >= _size or dst_idx < 0 or dst_idx >= _size:
		return false
	if src_idx == dst_idx:
		return false
	var src := _slots[src_idx]
	if src == null:
		return false
	if drag_count <= 0 or drag_count > src.count:
		return false
	if src.has_instance_data() and drag_count != src.count:
		return false
	var drag_item_id := src.item_id
	if not can_slot_accept_item_id(dst_idx, drag_item_id):
		return false
	var dst := _slots[dst_idx]
	if dst == null:
		return true
	if dst.item_id == drag_item_id:
		if src.has_instance_data() or dst.has_instance_data():
			return drag_count == src.count and can_slot_accept_item_id(src_idx, dst.item_id)
		return dst.count < item_catalog.get_definition(drag_item_id).max_stack
	return drag_count == src.count and can_slot_accept_item_id(src_idx, dst.item_id)

func _apply_handle_drop(src_idx: int, dst_idx: int, drag_count: int) -> bool:
	if not _can_handle_drop(src_idx, dst_idx, drag_count):
		return false
	var src := _slots[src_idx]
	var dst := _slots[dst_idx]
	var drag_item_id := src.item_id
	if dst == null:
		if drag_count == src.count:
			_slots[dst_idx] = src
			_slots[src_idx] = null
		else:
			assert(not src.has_instance_data())
			_slots[dst_idx] = InventoryStack.new(drag_item_id, drag_count)
			src.count -= drag_count
		return true
	if dst.item_id == drag_item_id:
		if src.has_instance_data() or dst.has_instance_data():
			_slots[src_idx] = dst
			_slots[dst_idx] = src
			return true
		var max_stack := item_catalog.get_definition(drag_item_id).max_stack
		var to_move: int = mini(drag_count, max_stack - dst.count)
		dst.count += to_move
		src.count -= to_move
		if src.count <= 0:
			_slots[src_idx] = null
		return true
	_slots[src_idx] = dst
	_slots[dst_idx] = src
	return true

func _apply_replace_stack_at(
	index: int,
	expected_stack: InventoryStack,
	replacement_stack: InventoryStack,
) -> bool:
	if index < 0 or index >= _size:
		return false
	if _get_stack_fingerprint(_slots[index]) != _get_stack_fingerprint(expected_stack):
		return false
	if _get_stack_fingerprint(expected_stack) == _get_stack_fingerprint(replacement_stack):
		return false
	if replacement_stack != null:
		if not _is_valid_incoming_stack(replacement_stack) or not can_slot_accept_item_id(index, replacement_stack.item_id):
			return false
		var replacement_instance_id := _get_stack_instance_id(replacement_stack)
		if replacement_instance_id > 0:
			for slot_index in range(_size):
				if slot_index != index and _get_stack_instance_id(_slots[slot_index]) == replacement_instance_id:
					return false
	_slots[index] = null if replacement_stack == null else replacement_stack.copy()
	return true

func _apply_socketed_rune(
	gear_index: int,
	expected_rune_ids: Array[StringName],
	next_rune_ids: Array[StringName],
	rune_source_index: int,
	rune_id: StringName,
) -> bool:
	var simulated := _simulate_socketed_rune(
		gear_index,
		expected_rune_ids,
		next_rune_ids,
		rune_source_index,
		rune_id,
	)
	if simulated.is_empty():
		return false
	_slots = simulated
	return true

func _simulate_socketed_rune(
	gear_index: int,
	expected_rune_ids: Array[StringName],
	next_rune_ids: Array[StringName],
	rune_source_index: int,
	rune_id: StringName,
) -> Array[InventoryStack]:
	if (
		gear_index < 0
		or gear_index >= _size
		or rune_source_index < 0
		or rune_source_index >= min(_size, FILLABLE_SIZE)
		or gear_index == rune_source_index
		or rune_id.is_empty()
	):
		return []
	var gear := _slots[gear_index]
	var rune_stack := _slots[rune_source_index]
	if (
		gear == null
		or gear.count != 1
		or gear.equipment_instance == null
		or gear.equipment_instance.socketed_rune_ids != expected_rune_ids
		or not item_catalog.is_valid_persisted_socket_loadout(expected_rune_ids)
		or not item_catalog.is_valid_socket_loadout(gear.item_id, next_rune_ids)
		or not _is_single_socket_addition(expected_rune_ids, next_rune_ids, rune_id)
		or rune_stack == null
		or rune_stack.item_id != rune_id
		or rune_stack.count < 1
		or rune_stack.equipment_instance != null
	):
		return []
	var simulated := _copy_slots()
	var simulated_gear := simulated[gear_index]
	simulated_gear.equipment_instance.socketed_rune_ids = next_rune_ids.duplicate()
	var simulated_rune := simulated[rune_source_index]
	simulated_rune.count -= 1
	if simulated_rune.count == 0:
		simulated[rune_source_index] = null
	return simulated

func _apply_unsocketed_rune(
	gear_index: int,
	expected_rune_ids: Array[StringName],
	next_rune_ids: Array[StringName],
	returned_rune_id: StringName,
) -> bool:
	var simulated := _simulate_unsocketed_rune(
		gear_index,
		expected_rune_ids,
		next_rune_ids,
		returned_rune_id,
	)
	if simulated.is_empty():
		return false
	_slots = simulated
	return true

func _simulate_unsocketed_rune(
	gear_index: int,
	expected_rune_ids: Array[StringName],
	next_rune_ids: Array[StringName],
	returned_rune_id: StringName,
) -> Array[InventoryStack]:
	if (
		gear_index < 0
		or gear_index >= _size
		or returned_rune_id.is_empty()
		or not item_catalog.has_definition(returned_rune_id)
		or not item_catalog.get_definition(returned_rune_id) is RuneDefinition
	):
		return []
	var gear := _slots[gear_index]
	if (
		gear == null
		or gear.count != 1
		or gear.equipment_instance == null
		or gear.equipment_instance.socketed_rune_ids != expected_rune_ids
		or not item_catalog.is_valid_persisted_socket_loadout(expected_rune_ids)
		or not item_catalog.is_valid_persisted_socket_loadout(next_rune_ids)
		or not _is_single_socket_removal(expected_rune_ids, next_rune_ids, returned_rune_id)
	):
		return []
	var simulated := _copy_slots()
	simulated[gear_index].equipment_instance.socketed_rune_ids = next_rune_ids.duplicate()
	var rune_definition := item_catalog.get_definition(returned_rune_id)
	var remaining := _grant_item_to_indices(
		simulated,
		returned_rune_id,
		1,
		rune_definition.max_stack,
		_get_backpack_indices(),
		equipment_instance_factory,
	)
	if remaining > 0:
		remaining = _grant_item_to_indices(
			simulated,
			returned_rune_id,
			remaining,
			rune_definition.max_stack,
			_get_hotbar_indices(),
			equipment_instance_factory,
		)
	if remaining > 0:
		var failed: Array[InventoryStack] = []
		return failed
	return simulated

func _is_single_socket_addition(
	expected_rune_ids: Array[StringName],
	next_rune_ids: Array[StringName],
	rune_id: StringName,
) -> bool:
	if next_rune_ids.size() < expected_rune_ids.size():
		return false
	var additions := 0
	for index in range(next_rune_ids.size()):
		var previous_id: StringName = expected_rune_ids[index] if index < expected_rune_ids.size() else &""
		var next_id := next_rune_ids[index]
		if previous_id == next_id:
			continue
		if not previous_id.is_empty() or next_id != rune_id:
			return false
		additions += 1
	return additions == 1

func _is_single_socket_removal(
	expected_rune_ids: Array[StringName],
	next_rune_ids: Array[StringName],
	rune_id: StringName,
) -> bool:
	if next_rune_ids.size() > expected_rune_ids.size():
		return false
	var removals := 0
	for index in range(expected_rune_ids.size()):
		var next_id: StringName = next_rune_ids[index] if index < next_rune_ids.size() else &""
		var previous_id := expected_rune_ids[index]
		if previous_id == next_id:
			continue
		if previous_id != rune_id or not next_id.is_empty():
			return false
		removals += 1
	return removals == 1

func to_dict() -> Dictionary:
	var regions_dict: Dictionary = {}
	for region in REGIONS:
		var region_name: String = region["name"]
		var indices: Array = InventoryModel.get_region_indices(region_name)
		var encoded: Array = []
		for idx in indices:
			var stack := _slots[idx] if idx >= 0 and idx < _slots.size() else null
			encoded.append(null if stack == null else stack.to_dict())
		regions_dict[region_name] = encoded
	return {
		"selected": _selected_slot,
		"starter_item_migration_version": _starter_item_migration_version,
		"regions": regions_dict,
	}

func get_equipment_instance_ids() -> Array[int]:
	var instance_ids: Array[int] = []
	for stack in _slots:
		if stack != null and stack.equipment_instance != null:
			instance_ids.append(stack.equipment_instance.instance_id)
	return instance_ids

func from_dict(data: Dictionary) -> bool:
	if _runtime_bound:
		return false
	var raw_regions = data.get("regions", null)
	if not raw_regions is Dictionary:
		return false
	var regions_dict := raw_regions as Dictionary
	var restored_slots: Array[InventoryStack] = []
	restored_slots.resize(_size)
	restored_slots.fill(null)
	var restored_instance_ids: Dictionary = {}
	for region in REGIONS:
		var region_name: String = region["name"]
		var indices: Array = InventoryModel.get_region_indices(region_name)
		var encoded = regions_dict.get(region_name, null)
		if encoded == null or not encoded is Array or (encoded as Array).size() != indices.size():
			return false
		for offset in range(indices.size()):
			var idx := int(indices[offset])
			var raw = (encoded as Array)[offset]
			if raw == null:
				continue
			if idx >= _size:
				return false
			if (
				not raw is Dictionary
				or not raw.has("item_id")
				or not raw.has("count")
				or not raw.has("equipment_instance")
			):
				return false
			var stack := InventoryStack.from_dict(raw)
			if stack == null:
				return false
			if not can_slot_accept_item_id(idx, stack.item_id):
				return false
			if stack.count < 1 or stack.count > item_catalog.get_definition(stack.item_id).max_stack:
				return false
			if not _is_valid_stack(stack):
				return false
			if stack.equipment_instance != null:
				var instance_id := stack.equipment_instance.instance_id
				if restored_instance_ids.has(instance_id):
					return false
				restored_instance_ids[instance_id] = true
			restored_slots[idx] = stack
	var raw_migration_version = data.get("starter_item_migration_version", 0)
	if (
		(typeof(raw_migration_version) != TYPE_INT and typeof(raw_migration_version) != TYPE_FLOAT)
		or not is_finite(float(raw_migration_version))
		or float(raw_migration_version) != float(int(raw_migration_version))
	):
		return false
	var restored_migration_version := int(raw_migration_version)
	if restored_migration_version < 0 or restored_migration_version > STARTER_ITEM_MIGRATION_VERSION:
		return false
	var raw_selected_slot = data.get("selected", 0)
	if (
		(typeof(raw_selected_slot) != TYPE_INT and typeof(raw_selected_slot) != TYPE_FLOAT)
		or not is_finite(float(raw_selected_slot))
		or float(raw_selected_slot) != float(int(raw_selected_slot))
	):
		return false
	var restored_selected_slot := int(raw_selected_slot)
	if not is_hotbar_index(restored_selected_slot):
		return false
	_slots = restored_slots
	_starter_item_migration_version = restored_migration_version
	_selected_slot = restored_selected_slot
	_revision += 1
	inventory_changed.emit()
	return true

func setup_starter() -> bool:
	if _runtime_bound or _size < FILLABLE_SIZE:
		return false
	_slots.fill(null)
	for starter_slot in STARTER_ITEMS_BY_SLOT:
		_slots[starter_slot] = _create_stack(STARTER_ITEMS_BY_SLOT[starter_slot], 1, equipment_instance_factory)
		assert(_slots[starter_slot] != null)
	_slots[1] = InventoryStack.new(item_catalog.get_item_for_block(BlockId.Type.GRASS).id, 12)
	_slots[2] = InventoryStack.new(item_catalog.get_item_for_block(BlockId.Type.STONE).id, 8)
	_slots[6] = InventoryStack.new(item_catalog.get_item_for_block(BlockId.Type.TORCH).id, 16)
	_selected_slot = 0
	_starter_item_migration_version = STARTER_ITEM_MIGRATION_VERSION
	_revision += 1
	inventory_changed.emit()
	return true

func setup_empty() -> bool:
	if _runtime_bound:
		return false
	_slots.fill(null)
	_selected_slot = 0
	_starter_item_migration_version = STARTER_ITEM_MIGRATION_VERSION
	_revision += 1
	inventory_changed.emit()
	return true
