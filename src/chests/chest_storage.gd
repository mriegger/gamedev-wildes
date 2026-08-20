extends RefCounted
class_name ChestStorage

var _item_catalog: ItemCatalog
var _equipment_instance_factory: EquipmentInstanceFactory
var _slot_count: int
var _chests: Dictionary = {}
var _revision: int = 0
var _runtime_bound: bool = false

func _init(
	p_item_catalog: ItemCatalog,
	p_equipment_instance_factory: EquipmentInstanceFactory,
	p_slot_count: int,
) -> void:
	assert(p_item_catalog != null)
	assert(p_equipment_instance_factory != null)
	assert(p_equipment_instance_factory.item_catalog == p_item_catalog)
	assert(p_slot_count > 0)
	_item_catalog = p_item_catalog
	_equipment_instance_factory = p_equipment_instance_factory
	_slot_count = p_slot_count

func _can_bind_runtime() -> bool:
	return not _runtime_bound

func _bind_runtime() -> bool:
	if not _can_bind_runtime():
		return false
	_runtime_bound = true
	return true

func _uses_dependencies(item_catalog: ItemCatalog, equipment_instance_factory: EquipmentInstanceFactory) -> bool:
	return _item_catalog == item_catalog and _equipment_instance_factory == equipment_instance_factory

func _uses_configuration(
	item_catalog: ItemCatalog,
	equipment_instance_factory: EquipmentInstanceFactory,
	slot_count: int,
) -> bool:
	return _uses_dependencies(item_catalog, equipment_instance_factory) and _slot_count == slot_count

func _replace_equipment_instance_factory(
	expected: EquipmentInstanceFactory,
	replacement: EquipmentInstanceFactory,
) -> bool:
	if (
		_runtime_bound
		or _equipment_instance_factory != expected
		or replacement == null
		or replacement.item_catalog != _item_catalog
		or replacement.get_next_instance_id() != expected.get_next_instance_id()
	):
		return false
	_equipment_instance_factory = replacement
	return true

func get_slot_count() -> int:
	return _slot_count

func create_chest(position: Vector3i) -> bool:
	if _runtime_bound:
		return false
	return _create_chest(position)

func _create_chest(position: Vector3i) -> bool:
	if _chests.has(position):
		return false
	var slots: Array[InventoryStack] = []
	slots.resize(_slot_count)
	slots.fill(null)
	_chests[position] = slots
	_revision += 1
	return true

func has_chest(position: Vector3i) -> bool:
	return _chests.has(position)

func is_chest_empty(position: Vector3i) -> bool:
	if not has_chest(position):
		return false
	var slots: Array[InventoryStack] = _chests[position]
	for stack in slots:
		if stack != null:
			return false
	return true

func _remove_empty_chest(position: Vector3i) -> bool:
	if not is_chest_empty(position):
		return false
	var removed := _chests.erase(position)
	if removed:
		_revision += 1
	return removed

func get_revision() -> int:
	return _revision

func get_slot(position: Vector3i, slot_index: int) -> InventoryStack:
	if not has_chest(position) or slot_index < 0 or slot_index >= _slot_count:
		return null
	var slots: Array[InventoryStack] = _chests[position]
	var stack := slots[slot_index]
	return null if stack == null else stack.copy()

func get_slots(position: Vector3i) -> Array[InventoryStack]:
	if not has_chest(position):
		return []
	var slots: Array[InventoryStack] = _chests[position]
	return _copy_slots(slots)

func prepare_add_stack(
	position: Vector3i,
	stack: InventoryStack,
	destination_slot: int = -1,
) -> PreparedChestStorageChange:
	var simulated := _simulate_add_stack(position, stack, destination_slot)
	if simulated.is_empty():
		return null
	return PreparedChestStorageChange.new(self, _revision, position, simulated)

func add_stack(position: Vector3i, stack: InventoryStack, destination_slot: int = -1) -> bool:
	if _runtime_bound:
		return false
	var prepared := prepare_add_stack(position, stack, destination_slot)
	if prepared == null:
		return false
	_commit_prepared_change(prepared)
	return true

func _can_remove_stack(position: Vector3i, slot_index: int, count: int = -1) -> bool:
	var stack := get_slot(position, slot_index)
	if stack == null:
		return false
	var removed_count := stack.count if count == -1 else count
	if removed_count < 1 or removed_count > stack.count:
		return false
	return not stack.has_instance_data() or removed_count == stack.count

func prepare_remove_stack(
	position: Vector3i,
	slot_index: int,
	count: int = -1,
) -> PreparedChestStorageChange:
	if not _can_remove_stack(position, slot_index, count):
		return null
	var simulated := get_slots(position)
	var stack := simulated[slot_index]
	var removed_count := stack.count if count == -1 else count
	var removed := InventoryStack.new(stack.item_id, removed_count, stack.equipment_instance)
	stack.count -= removed_count
	if stack.count == 0:
		simulated[slot_index] = null
	return PreparedChestStorageChange.new(self, _revision, position, simulated, removed)

func remove_stack(position: Vector3i, slot_index: int, count: int = -1) -> InventoryStack:
	if _runtime_bound:
		return null
	var prepared := prepare_remove_stack(position, slot_index, count)
	if prepared == null:
		return null
	_commit_prepared_change(prepared)
	return prepared.get_result_stack()

func _prepare_replace_stack_at(
	position: Vector3i,
	slot_index: int,
	expected_stack: InventoryStack,
	replacement_stack: InventoryStack,
) -> PreparedChestStorageChange:
	if not has_chest(position) or slot_index < 0 or slot_index >= _slot_count:
		return null
	var current := get_slot(position, slot_index)
	if not _stacks_match(current, expected_stack) or _stacks_match(expected_stack, replacement_stack):
		return null
	if replacement_stack != null:
		if not _is_valid_stack(replacement_stack):
			return null
		if (
			replacement_stack.equipment_instance != null
			and _has_equipment_instance_id_except(
				replacement_stack.equipment_instance.instance_id,
				position,
				slot_index,
			)
		):
			return null
	var simulated := get_slots(position)
	simulated[slot_index] = null if replacement_stack == null else replacement_stack.copy()
	return PreparedChestStorageChange.new(self, _revision, position, simulated, expected_stack)

func _prepare_handle_drop(
	position: Vector3i,
	source_index: int,
	destination_index: int,
	drag_count: int,
) -> PreparedChestStorageChange:
	if (
		not has_chest(position)
		or source_index < 0
		or source_index >= _slot_count
		or destination_index < 0
		or destination_index >= _slot_count
		or source_index == destination_index
	):
		return null
	var simulated := get_slots(position)
	var source := simulated[source_index]
	if source == null or drag_count < 1 or drag_count > source.count:
		return null
	if source.has_instance_data() and drag_count != source.count:
		return null
	var destination := simulated[destination_index]
	if destination == null:
		if drag_count == source.count:
			simulated[destination_index] = source
			simulated[source_index] = null
		else:
			simulated[destination_index] = InventoryStack.new(source.item_id, drag_count)
			source.count -= drag_count
	elif destination.item_id == source.item_id:
		if source.has_instance_data() or destination.has_instance_data():
			if drag_count != source.count:
				return null
			simulated[source_index] = destination
			simulated[destination_index] = source
		else:
			var max_stack := _item_catalog.get_definition(source.item_id).max_stack
			var moved := mini(drag_count, max_stack - destination.count)
			if moved < 1:
				return null
			destination.count += moved
			source.count -= moved
			if source.count == 0:
				simulated[source_index] = null
	else:
		if drag_count != source.count:
			return null
		simulated[source_index] = destination
		simulated[destination_index] = source
	return PreparedChestStorageChange.new(self, _revision, position, simulated)

func can_commit_prepared_change(prepared: PreparedChestStorageChange) -> bool:
	return (
		prepared != null
		and prepared._is_for(self)
		and prepared._get_expected_revision() == _revision
		and has_chest(prepared._get_position())
	)

func _commit_prepared_change(prepared: PreparedChestStorageChange) -> void:
	assert(can_commit_prepared_change(prepared))
	_chests[prepared._get_position()] = prepared._copy_committed_slots()
	_revision += 1

func snapshot() -> Dictionary:
	var saved: Dictionary = {}
	for position in _chests:
		var slots: Array[InventoryStack] = _chests[position]
		var encoded: Array = []
		for stack in slots:
			encoded.append(null if stack == null else stack.to_dict())
		saved[position] = encoded
	return saved

func get_equipment_instance_ids() -> Array[int]:
	var instance_ids: Array[int] = []
	for slots in _chests.values():
		for stack in slots as Array[InventoryStack]:
			if stack != null and stack.equipment_instance != null:
				instance_ids.append(stack.equipment_instance.instance_id)
	return instance_ids

func restore(saved: Dictionary) -> bool:
	if _runtime_bound:
		return false
	var restored: Dictionary = {}
	var restored_instance_ids: Dictionary = {}
	for position in saved:
		if typeof(position) != TYPE_VECTOR3I:
			return false
		var encoded = saved[position]
		if not encoded is Array or (encoded as Array).size() != _slot_count:
			return false
		var slots: Array[InventoryStack] = []
		slots.resize(_slot_count)
		slots.fill(null)
		for slot_index in range(_slot_count):
			var raw = (encoded as Array)[slot_index]
			if raw == null:
				continue
			if (
				not raw is Dictionary
				or not raw.has("item_id")
				or not raw.has("count")
				or not raw.has("equipment_instance")
			):
				return false
			var stack := InventoryStack.from_dict(raw)
			if not _is_valid_stack(stack):
				return false
			if stack.equipment_instance != null:
				var instance_id := stack.equipment_instance.instance_id
				if restored_instance_ids.has(instance_id):
					return false
				restored_instance_ids[instance_id] = true
			slots[slot_index] = stack
		restored[position] = slots
	_chests = restored
	_revision += 1
	return true

func _simulate_add_stack(position: Vector3i, stack: InventoryStack, destination_slot: int) -> Array[InventoryStack]:
	if not has_chest(position) or not _is_valid_stack(stack) or destination_slot < -1 or destination_slot >= _slot_count:
		return []
	if stack.equipment_instance != null and _has_equipment_instance_id(stack.equipment_instance.instance_id):
		return []
	var owned_slots: Array[InventoryStack] = _chests[position]
	var simulated := _copy_slots(owned_slots)
	if destination_slot >= 0:
		return _add_to_destination(simulated, stack, destination_slot)
	var remaining := stack.count
	if not stack.has_instance_data():
		for existing in simulated:
			if not _can_merge(existing, stack):
				continue
			var max_stack := _item_catalog.get_definition(stack.item_id).max_stack
			var added := mini(remaining, max_stack - existing.count)
			existing.count += added
			remaining -= added
			if remaining == 0:
				return simulated
	for slot_index in range(_slot_count):
		if simulated[slot_index] != null:
			continue
		if stack.has_instance_data():
			simulated[slot_index] = stack.copy()
			return simulated
		var slot_count := mini(remaining, _item_catalog.get_definition(stack.item_id).max_stack)
		simulated[slot_index] = InventoryStack.new(stack.item_id, slot_count)
		remaining -= slot_count
		if remaining == 0:
			return simulated
	return []

func _add_to_destination(slots: Array[InventoryStack], stack: InventoryStack, destination_slot: int) -> Array[InventoryStack]:
	var destination := slots[destination_slot]
	if destination == null:
		slots[destination_slot] = stack.copy()
		return slots
	if not _can_merge(destination, stack):
		return []
	var max_stack := _item_catalog.get_definition(stack.item_id).max_stack
	if destination.count + stack.count > max_stack:
		return []
	destination.count += stack.count
	return slots

func _can_merge(destination: InventoryStack, incoming: InventoryStack) -> bool:
	return (
		destination != null
		and destination.item_id == incoming.item_id
		and not destination.has_instance_data()
		and not incoming.has_instance_data()
	)

func _is_valid_stack(stack: InventoryStack) -> bool:
	if stack == null or stack.item_id.is_empty() or not _item_catalog.has_definition(stack.item_id):
		return false
	if stack.count < 1 or stack.count > _item_catalog.get_definition(stack.item_id).max_stack:
		return false
	var definition := _item_catalog.get_definition(stack.item_id)
	if definition.equipment_type == null:
		return stack.equipment_instance == null
	return stack.count == 1 and _equipment_instance_factory.is_valid_instance(stack.item_id, stack.equipment_instance)

func _has_equipment_instance_id(instance_id: int) -> bool:
	for slots in _chests.values():
		for stack in slots as Array[InventoryStack]:
			if stack != null and stack.equipment_instance != null and stack.equipment_instance.instance_id == instance_id:
				return true
	return false

func _has_equipment_instance_id_except(
	instance_id: int,
	excluded_position: Vector3i,
	excluded_slot_index: int,
) -> bool:
	for position in _chests:
		var slots: Array[InventoryStack] = _chests[position]
		for slot_index in range(slots.size()):
			if position == excluded_position and slot_index == excluded_slot_index:
				continue
			var stack := slots[slot_index]
			if stack != null and stack.equipment_instance != null and stack.equipment_instance.instance_id == instance_id:
				return true
	return false

static func _stacks_match(first: InventoryStack, second: InventoryStack) -> bool:
	if first == null or second == null:
		return first == null and second == null
	return first.to_dict() == second.to_dict()

func _copy_slots(source: Array[InventoryStack]) -> Array[InventoryStack]:
	var copied: Array[InventoryStack] = []
	copied.resize(_slot_count)
	for slot_index in range(_slot_count):
		var stack := source[slot_index]
		if stack != null:
			copied[slot_index] = stack.copy()
	return copied
