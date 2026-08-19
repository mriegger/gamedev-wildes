extends RefCounted
class_name RuneSocketingCoordinator

enum SlotState {
	UNAVAILABLE,
	LOCKED,
	EMPTY,
	FILLED,
}

var _inventory_model: InventoryModel
var _inventory_loadout: InventoryLoadoutCoordinator
var _item_proficiency: ItemProficiency

func setup(
	p_inventory_model: InventoryModel,
	p_inventory_loadout: InventoryLoadoutCoordinator,
	p_item_proficiency: ItemProficiency,
) -> bool:
	assert(p_inventory_model != null)
	assert(p_inventory_loadout != null and p_inventory_loadout.inventory_model == p_inventory_model)
	assert(p_item_proficiency != null)
	if _inventory_model != null or _inventory_loadout != null or _item_proficiency != null:
		return false
	if not p_inventory_loadout.uses_item_proficiency(p_item_proficiency) or not _validate_existing_loadouts(p_inventory_model):
		return false
	_inventory_model = p_inventory_model
	_inventory_loadout = p_inventory_loadout
	_item_proficiency = p_item_proficiency
	return true

func is_socketable_gear_index(gear_index: int) -> bool:
	return get_total_slot_count(gear_index) > 0

func get_total_slot_count(gear_index: int) -> int:
	var gear := _get_gear_definition(_inventory_model, _item_proficiency, gear_index)
	var configured_slot_count := 0 if gear == null else gear.proficiency.slot_unlock_levels.size()
	if _get_persisted_gear_definition(_inventory_model, gear_index) == null:
		return configured_slot_count
	return maxi(configured_slot_count, _inventory_model.get_socketed_rune_ids(gear_index).size())

func get_unlocked_slot_count(gear_index: int) -> int:
	var gear := _get_gear_definition(_inventory_model, _item_proficiency, gear_index)
	if gear == null:
		return 0
	return mini(
		gear.proficiency.slot_unlock_levels.size(),
		_item_proficiency.get_unlocked_slot_count(gear.id),
	)

func get_socketed_rune_id(gear_index: int, slot_index: int) -> StringName:
	if not is_socketable_gear_index(gear_index) or slot_index < 0 or slot_index >= get_total_slot_count(gear_index):
		return &""
	var rune_ids := _inventory_model.get_socketed_rune_ids(gear_index)
	return &"" if slot_index >= rune_ids.size() else rune_ids[slot_index]

func get_slot_state(gear_index: int, slot_index: int) -> SlotState:
	if slot_index < 0 or slot_index >= get_total_slot_count(gear_index):
		return SlotState.UNAVAILABLE
	if not get_socketed_rune_id(gear_index, slot_index).is_empty():
		return SlotState.FILLED
	if slot_index >= get_unlocked_slot_count(gear_index):
		return SlotState.LOCKED
	return SlotState.EMPTY

func can_socket(gear_index: int, slot_index: int, rune_source_index: int) -> bool:
	return not _prepare_socket(gear_index, slot_index, rune_source_index).is_empty()

func try_socket(gear_index: int, slot_index: int, rune_source_index: int) -> bool:
	var prepared := _prepare_socket(gear_index, slot_index, rune_source_index)
	if prepared.is_empty():
		return false
	var expected_rune_ids: Array[StringName] = prepared["expected_rune_ids"]
	var next_rune_ids: Array[StringName] = prepared["next_rune_ids"]
	var rune_id: StringName = prepared["rune_id"]
	return _inventory_loadout.socket_rune(
		gear_index,
		expected_rune_ids,
		next_rune_ids,
		rune_source_index,
		rune_id,
	)

func can_unsocket(gear_index: int, slot_index: int) -> bool:
	return not _prepare_unsocket(gear_index, slot_index).is_empty()

func try_unsocket(gear_index: int, slot_index: int) -> bool:
	var prepared := _prepare_unsocket(gear_index, slot_index)
	if prepared.is_empty():
		return false
	var expected_rune_ids: Array[StringName] = prepared["expected_rune_ids"]
	var next_rune_ids: Array[StringName] = prepared["next_rune_ids"]
	var rune_id: StringName = prepared["rune_id"]
	return _inventory_loadout.unsocket_rune(
		gear_index,
		expected_rune_ids,
		next_rune_ids,
		rune_id,
	)

func _prepare_socket(gear_index: int, slot_index: int, rune_source_index: int) -> Dictionary:
	var gear := _get_gear_definition(_inventory_model, _item_proficiency, gear_index)
	if gear == null or slot_index < 0 or slot_index >= get_unlocked_slot_count(gear_index):
		return {}
	if rune_source_index == gear_index:
		return {}
	var rune_stack := _inventory_model.get_slot(rune_source_index)
	if rune_stack == null or not _inventory_model.item_catalog.has_definition(rune_stack.item_id):
		return {}
	var rune := _inventory_model.item_catalog.get_definition(rune_stack.item_id) as RuneDefinition
	if rune == null or not rune.is_compatible_with(gear):
		return {}
	var current_rune_ids := _inventory_model.get_socketed_rune_ids(gear_index)
	if (
		not _is_valid_loadout(_inventory_model, _item_proficiency, gear_index, current_rune_ids)
		or (slot_index < current_rune_ids.size() and not current_rune_ids[slot_index].is_empty())
	):
		return {}
	var next_rune_ids := current_rune_ids.duplicate()
	while next_rune_ids.size() <= slot_index:
		next_rune_ids.append(&"")
	next_rune_ids[slot_index] = rune.id
	_trim_trailing_empty_slots(next_rune_ids)
	if (
		not _is_valid_loadout(_inventory_model, _item_proficiency, gear_index, next_rune_ids)
		or not _inventory_loadout.can_socket_rune(
			gear_index,
			current_rune_ids,
			next_rune_ids,
			rune_source_index,
			rune.id,
		)
	):
		return {}
	return {
		"expected_rune_ids": current_rune_ids,
		"next_rune_ids": next_rune_ids,
		"rune_id": rune.id,
	}

func _prepare_unsocket(gear_index: int, slot_index: int) -> Dictionary:
	if get_slot_state(gear_index, slot_index) != SlotState.FILLED:
		return {}
	var current_rune_ids := _inventory_model.get_socketed_rune_ids(gear_index)
	if not _is_valid_persisted_loadout(_inventory_model, gear_index, current_rune_ids):
		return {}
	var rune_id := current_rune_ids[slot_index]
	var next_rune_ids := current_rune_ids.duplicate()
	next_rune_ids[slot_index] = &""
	_trim_trailing_empty_slots(next_rune_ids)
	if not _inventory_loadout.can_unsocket_rune(
		gear_index,
		current_rune_ids,
		next_rune_ids,
		rune_id,
	):
		return {}
	return {
		"expected_rune_ids": current_rune_ids,
		"next_rune_ids": next_rune_ids,
		"rune_id": rune_id,
	}

func _validate_existing_loadouts(p_inventory_model: InventoryModel) -> bool:
	for gear_index in range(p_inventory_model.get_size()):
		if p_inventory_model.get_slot(gear_index) == null:
			continue
		var rune_ids := p_inventory_model.get_socketed_rune_ids(gear_index)
		if rune_ids.is_empty():
			continue
		if not _is_valid_persisted_loadout(p_inventory_model, gear_index, rune_ids):
			return false
	return true

func _is_valid_persisted_loadout(
	p_inventory_model: InventoryModel,
	gear_index: int,
	rune_ids: Array[StringName],
) -> bool:
	return (
		_get_persisted_gear_definition(p_inventory_model, gear_index) != null
		and p_inventory_model.item_catalog.is_valid_persisted_socket_loadout(rune_ids)
	)

func _is_valid_loadout(
	p_inventory_model: InventoryModel,
	p_item_proficiency: ItemProficiency,
	gear_index: int,
	rune_ids: Array[StringName],
) -> bool:
	var gear := _get_gear_definition(p_inventory_model, p_item_proficiency, gear_index)
	if gear == null:
		return false
	return p_inventory_model.item_catalog.is_valid_socket_loadout(gear.id, rune_ids)

func _get_gear_definition(
	p_inventory_model: InventoryModel,
	p_item_proficiency: ItemProficiency,
	gear_index: int,
) -> ItemDefinition:
	if p_inventory_model == null or p_item_proficiency == null:
		return null
	var stack := p_inventory_model.get_slot(gear_index)
	if (
		stack == null
		or stack.count != 1
		or not p_inventory_model.item_catalog.has_definition(stack.item_id)
		or not p_inventory_model.item_catalog.is_combat_item(stack.item_id)
		or not p_item_proficiency.has_proficiency(stack.item_id)
	):
		return null
	var gear := p_inventory_model.item_catalog.get_definition(stack.item_id)
	var total_slot_count := gear.proficiency.slot_unlock_levels.size()
	return gear if total_slot_count > 0 and total_slot_count <= ProficiencyDefinition.MAXIMUM_SLOT_COUNT else null

func _get_persisted_gear_definition(
	p_inventory_model: InventoryModel,
	gear_index: int,
) -> ItemDefinition:
	if p_inventory_model == null:
		return null
	var stack := p_inventory_model.get_slot(gear_index)
	if (
		stack == null
		or stack.count != 1
		or stack.equipment_instance == null
		or not p_inventory_model.item_catalog.has_definition(stack.item_id)
		or not p_inventory_model.item_catalog.is_combat_item(stack.item_id)
	):
		return null
	return p_inventory_model.item_catalog.get_definition(stack.item_id)

func _trim_trailing_empty_slots(rune_ids: Array[StringName]) -> void:
	while not rune_ids.is_empty() and rune_ids.back().is_empty():
		rune_ids.pop_back()
