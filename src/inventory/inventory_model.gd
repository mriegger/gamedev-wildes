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

var size: int = TOTAL_SIZE
var item_catalog: ItemCatalog
var equipment_instance_factory: EquipmentInstanceFactory

var slots: Array[InventoryStack] = []
var selected_slot: int = 0
var starter_item_migration_version: int = 0

func _init(
	p_item_catalog: ItemCatalog,
	p_equipment_instance_factory: EquipmentInstanceFactory,
	p_size: int = DEFAULT_SIZE,
):
	assert(p_item_catalog != null)
	assert(p_equipment_instance_factory != null)
	assert(p_equipment_instance_factory.item_catalog == p_item_catalog)
	item_catalog = p_item_catalog
	equipment_instance_factory = p_equipment_instance_factory
	size = p_size
	slots.resize(size)
	slots.fill(null)
	selected_slot = 0

func get_slot(idx: int) -> InventoryStack:
	if idx < 0 or idx >= size:
		return null
	return slots[idx]

func add_stack(stack: InventoryStack) -> bool:
	var simulated := _simulate_stack_add(stack)
	if simulated.is_empty():
		return false
	slots = simulated
	inventory_changed.emit()
	return true

func get_selected_data() -> InventoryStack:
	return get_slot(selected_slot)

func get_selected_item_id():
	var stack := get_selected_data()
	if stack == null:
		return null
	return stack.item_id

func get_socketed_rune_ids(idx: int) -> Array[StringName]:
	var stack := get_slot(idx)
	var rune_ids: Array[StringName] = []
	if stack != null and stack.equipment_instance != null:
		rune_ids.assign(stack.equipment_instance.socketed_rune_ids)
	return rune_ids

func get_equipment_instance_copy(idx: int) -> EquipmentInstance:
	var stack := get_slot(idx)
	return null if stack == null or stack.equipment_instance == null else stack.equipment_instance.copy()

func select_slot(idx: int) -> bool:
	if not is_hotbar_index(idx):
		return false
	if idx == selected_slot:
		return true
	selected_slot = idx
	inventory_changed.emit()
	return true

func assign_slot_to_hotbar(source_idx: int, hotbar_idx: int) -> bool:
	if source_idx < 0 or source_idx >= min(size, FILLABLE_SIZE):
		return false
	if not is_hotbar_index(hotbar_idx) or hotbar_idx >= size:
		return false
	if source_idx == hotbar_idx:
		return false
	var source_stack := slots[source_idx]
	if source_stack == null or not can_slot_accept_item_id(hotbar_idx, source_stack.item_id):
		return false
	var hotbar_stack := slots[hotbar_idx]
	if hotbar_stack != null and not can_slot_accept_item_id(source_idx, hotbar_stack.item_id):
		return false
	slots[source_idx] = hotbar_stack
	slots[hotbar_idx] = source_stack
	inventory_changed.emit()
	return true

func move_hotbar_slot_to_backpack(hotbar_idx: int) -> bool:
	if not is_hotbar_index(hotbar_idx) or hotbar_idx >= size:
		return false
	var hotbar_stack := slots[hotbar_idx]
	if hotbar_stack == null:
		return false
	var max_stack: int = item_catalog.get_definition(hotbar_stack.item_id).max_stack
	var backpack_end: int = mini(size, FILLABLE_SIZE)
	var available_capacity: int = 0
	for backpack_idx in range(HOTBAR_SIZE, backpack_end):
		var backpack_stack := slots[backpack_idx]
		if backpack_stack == null:
			available_capacity += max_stack
		elif backpack_stack.item_id == hotbar_stack.item_id and not backpack_stack.has_instance_data() and not hotbar_stack.has_instance_data():
			available_capacity += max_stack - backpack_stack.count
	if available_capacity < hotbar_stack.count:
		return false
	var remaining: int = hotbar_stack.count
	for backpack_idx in range(HOTBAR_SIZE, backpack_end):
		var backpack_stack := slots[backpack_idx]
		if backpack_stack == null or backpack_stack.item_id != hotbar_stack.item_id or backpack_stack.has_instance_data() or hotbar_stack.has_instance_data():
			continue
		var moved := mini(remaining, max_stack - backpack_stack.count)
		backpack_stack.count += moved
		remaining -= moved
		if remaining == 0:
			break
	if remaining > 0:
		for backpack_idx in range(HOTBAR_SIZE, backpack_end):
			if slots[backpack_idx] == null:
				if remaining == hotbar_stack.count:
					slots[backpack_idx] = hotbar_stack
				else:
					assert(not hotbar_stack.has_instance_data())
					slots[backpack_idx] = InventoryStack.new(hotbar_stack.item_id, remaining)
				remaining = 0
				break
	assert(remaining == 0)
	slots[hotbar_idx] = null
	inventory_changed.emit()
	return true

func can_discard_stack(source_index: int, count: int) -> bool:
	if source_index < 0 or source_index >= mini(size, TOTAL_SIZE):
		return false
	var stack := slots[source_index]
	return stack != null and count > 0 and count <= stack.count

func discard_stack(source_index: int, count: int) -> bool:
	if not can_discard_stack(source_index, count):
		return false
	var stack := slots[source_index]
	stack.count -= count
	if stack.count == 0:
		slots[source_index] = null
	inventory_changed.emit()
	return true

func ensure_item(item_id: StringName) -> bool:
	if not item_catalog.has_definition(item_id):
		return false
	for stack in slots:
		if stack != null and stack.item_id == item_id:
			return true
	for index in range(min(size, HOTBAR_SIZE)):
		if slots[index] == null:
			slots[index] = _create_stack(item_id, 1, equipment_instance_factory)
			if slots[index] == null:
				return false
			inventory_changed.emit()
			return true
	for index in range(HOTBAR_SIZE, min(size, FILLABLE_SIZE)):
		if slots[index] == null:
			slots[index] = slots[0]
			slots[0] = _create_stack(item_id, 1, equipment_instance_factory)
			if slots[0] == null:
				return false
			inventory_changed.emit()
			return true
	return false

func migrate_starter_items() -> bool:
	if starter_item_migration_version >= STARTER_ITEM_MIGRATION_VERSION:
		return true
	var simulated_factory := equipment_instance_factory.copy()
	var simulated := InventoryModel.new(item_catalog, simulated_factory, size)
	simulated.slots = _copy_slots()
	for starter_slot in STARTER_ITEMS_BY_SLOT:
		var item_id: StringName = STARTER_ITEMS_BY_SLOT[starter_slot]
		var item_ensured := simulated.ensure_item(item_id) if starter_slot < HOTBAR_SIZE else simulated.ensure_backpack_item(item_id)
		if not item_ensured:
			return false
	slots = simulated.slots
	assert(equipment_instance_factory.try_advance_next_instance_id(
		equipment_instance_factory.get_next_instance_id(),
		simulated_factory.get_next_instance_id(),
	))
	starter_item_migration_version = STARTER_ITEM_MIGRATION_VERSION
	inventory_changed.emit()
	return true

func ensure_backpack_item(item_id: StringName) -> bool:
	if not item_catalog.has_definition(item_id):
		return false
	for stack in slots:
		if stack != null and stack.item_id == item_id:
			return true
	for index in range(HOTBAR_SIZE, FILLABLE_SIZE):
		if slots[index] == null:
			slots[index] = _create_stack(item_id, 1, equipment_instance_factory)
			if slots[index] == null:
				return false
			inventory_changed.emit()
			return true
	return false

func get_backpack_item_count(item_id: StringName) -> int:
	if not item_catalog.has_definition(item_id):
		return 0
	var total := 0
	for index in range(HOTBAR_SIZE, min(size, FILLABLE_SIZE)):
		var stack := slots[index]
		if stack != null and stack.item_id == item_id:
			total += stack.count
	return total

func add_backpack_item(item_id: StringName, count: int) -> bool:
	if count < 1 or not item_catalog.has_definition(item_id):
		return false
	var simulated := _copy_slots()
	var simulated_factory := equipment_instance_factory.copy()
	var max_stack: int = item_catalog.get_definition(item_id).max_stack
	var remaining := _grant_item_to_indices(simulated, item_id, count, max_stack, _get_backpack_indices(), simulated_factory)
	if remaining > 0:
		return false
	slots = simulated
	assert(equipment_instance_factory.try_advance_next_instance_id(
		equipment_instance_factory.get_next_instance_id(),
		simulated_factory.get_next_instance_id(),
	))
	inventory_changed.emit()
	return true

func get_inventory_item_count(item_id: StringName) -> int:
	if not item_catalog.has_definition(item_id):
		return 0
	var total := 0
	for index in _get_inventory_indices():
		var stack := slots[index]
		if stack != null and stack.item_id == item_id:
			total += stack.count
	return total

func can_exchange_inventory_items(
	consumed: Dictionary[StringName, int],
	granted: Dictionary[StringName, int],
	creation_factory: EquipmentInstanceFactory,
) -> bool:
	assert(creation_factory == equipment_instance_factory)
	return not _simulate_inventory_exchange(consumed, granted, creation_factory.copy()).is_empty()

func exchange_inventory_items(
	consumed: Dictionary[StringName, int],
	granted: Dictionary[StringName, int],
	creation_factory: EquipmentInstanceFactory,
) -> bool:
	assert(creation_factory == equipment_instance_factory)
	var simulated_factory := creation_factory.copy()
	var simulated := _simulate_inventory_exchange(consumed, granted, simulated_factory)
	if simulated.is_empty():
		return false
	slots = simulated
	assert(creation_factory.try_advance_next_instance_id(
		creation_factory.get_next_instance_id(),
		simulated_factory.get_next_instance_id(),
	))
	inventory_changed.emit()
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
	for index in range(HOTBAR_SIZE, mini(size, FILLABLE_SIZE)):
		indices.append(index)
	return indices

func _get_hotbar_indices() -> Array[int]:
	var indices: Array[int] = []
	for index in range(mini(size, HOTBAR_SIZE)):
		indices.append(index)
	return indices

func _simulate_stack_add(stack: InventoryStack) -> Array[InventoryStack]:
	var simulated := _copy_slots()
	if not _try_add_stack_to_slots(stack, simulated):
		return []
	return simulated

func _try_add_stack_to_slots(stack: InventoryStack, simulated: Array[InventoryStack]) -> bool:
	if (
		stack == null
		or stack.count < 1
		or not item_catalog.has_definition(stack.item_id)
		or stack.count > item_catalog.get_definition(stack.item_id).max_stack
		or not _is_valid_stack(stack)
	):
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
	copied.resize(size)
	for index in range(size):
		if slots[index] != null:
			copied[index] = slots[index].copy()
	return copied

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
		for index in range(min(size, FILLABLE_SIZE)):
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

func can_add_batch(ids: Array[StringName]) -> bool:
	if ids.is_empty():
		return true
	return not _simulate_slots(ids, equipment_instance_factory.copy()).is_empty()

func add_batch(ids: Array[StringName]) -> bool:
	if ids.is_empty():
		return true
	var simulated_factory := equipment_instance_factory.copy()
	var sim := _simulate_slots(ids, simulated_factory)
	if sim.is_empty():
		return false
	slots = sim
	assert(equipment_instance_factory.try_advance_next_instance_id(
		equipment_instance_factory.get_next_instance_id(),
		simulated_factory.get_next_instance_id(),
	))
	inventory_changed.emit()
	return true

func consume_selected() -> bool:
	if not can_consume_selected():
		return false
	var stack := slots[selected_slot]
	stack.count -= 1
	if stack.count <= 0:
		slots[selected_slot] = null
	inventory_changed.emit()
	return true

func can_consume_selected() -> bool:
	if not is_hotbar_index(selected_slot):
		return false
	var stack := get_selected_data()
	return stack != null and stack.count > 0

func is_hotbar_index(idx: int) -> bool:
	return idx >= 0 and idx < HOTBAR_SIZE

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
	if idx < 0 or idx >= size or not item_id is StringName or not item_catalog.has_definition(item_id):
		return false
	if idx < FILLABLE_SIZE:
		return true
	if not is_equipment_index(idx):
		return false
	var armor := item_catalog.get_definition(item_id) as ArmorDefinition
	return armor != null and get_equipment_index(armor.armor_slot) == idx

func can_handle_drop(src_idx: int, dst_idx: int, drag_count: int) -> bool:
	if src_idx < 0 or src_idx >= size or dst_idx < 0 or dst_idx >= size:
		return false
	if src_idx == dst_idx:
		return false
	var src := slots[src_idx]
	if src == null:
		return false
	if drag_count <= 0 or drag_count > src.count:
		return false
	if src.has_instance_data() and drag_count != src.count:
		return false
	var drag_item_id := src.item_id
	if not can_slot_accept_item_id(dst_idx, drag_item_id):
		return false
	var dst := slots[dst_idx]
	if dst == null:
		return true
	if dst.item_id == drag_item_id:
		if src.has_instance_data() or dst.has_instance_data():
			return drag_count == src.count and can_slot_accept_item_id(src_idx, dst.item_id)
		return dst.count < item_catalog.get_definition(drag_item_id).max_stack
	return drag_count == src.count and can_slot_accept_item_id(src_idx, dst.item_id)

func handle_drop(src_idx: int, dst_idx: int, drag_count: int) -> bool:
	if not can_handle_drop(src_idx, dst_idx, drag_count):
		return false
	var src := slots[src_idx]
	var dst := slots[dst_idx]
	var drag_item_id := src.item_id
	if dst == null:
		if drag_count == src.count:
			slots[dst_idx] = src
			slots[src_idx] = null
		else:
			assert(not src.has_instance_data())
			slots[dst_idx] = InventoryStack.new(drag_item_id, drag_count)
			src.count -= drag_count
		inventory_changed.emit()
		return true
	if dst.item_id == drag_item_id:
		if src.has_instance_data() or dst.has_instance_data():
			slots[src_idx] = dst
			slots[dst_idx] = src
			inventory_changed.emit()
			return true
		var max_stack := item_catalog.get_definition(drag_item_id).max_stack
		var to_move: int = mini(drag_count, max_stack - dst.count)
		dst.count += to_move
		src.count -= to_move
		if src.count <= 0:
			slots[src_idx] = null
		inventory_changed.emit()
		return true
	slots[src_idx] = dst
	slots[dst_idx] = src
	inventory_changed.emit()
	return true

func can_transfer_stack_to(destination: InventoryModel, src_idx: int, dst_idx: int, drag_count: int) -> bool:
	if destination == self:
		return can_handle_drop(src_idx, dst_idx, drag_count)
	return not _simulate_transfer_to(destination, src_idx, dst_idx, drag_count).is_empty()

func transfer_stack_to(destination: InventoryModel, src_idx: int, dst_idx: int, drag_count: int) -> bool:
	if destination == self:
		return handle_drop(src_idx, dst_idx, drag_count)
	var simulated := _simulate_transfer_to(destination, src_idx, dst_idx, drag_count)
	if simulated.is_empty():
		return false
	slots = simulated["source"]
	destination.slots = simulated["destination"]
	inventory_changed.emit()
	destination.inventory_changed.emit()
	return true

func can_transfer_stack_to_indices(destination: InventoryModel, src_idx: int, destination_indices: Array[int]) -> bool:
	return not _simulate_transfer_to_indices(destination, src_idx, destination_indices).is_empty()

func transfer_stack_to_indices(destination: InventoryModel, src_idx: int, destination_indices: Array[int]) -> bool:
	var simulated := _simulate_transfer_to_indices(destination, src_idx, destination_indices)
	if simulated.is_empty():
		return false
	slots = simulated["source"]
	destination.slots = simulated["destination"]
	inventory_changed.emit()
	destination.inventory_changed.emit()
	return true

func _simulate_transfer_to_indices(destination: InventoryModel, src_idx: int, destination_indices: Array[int]) -> Dictionary:
	if (
		destination == null
		or destination == self
		or item_catalog != destination.item_catalog
		or equipment_instance_factory != destination.equipment_instance_factory
	):
		return {}
	if src_idx < 0 or src_idx >= size or destination_indices.is_empty():
		return {}
	var source_stack := slots[src_idx]
	if source_stack == null:
		return {}
	var unique_indices: Array[int] = []
	for index in destination_indices:
		if index < 0 or index >= destination.size or unique_indices.has(index):
			return {}
		if not destination.can_slot_accept_item_id(index, source_stack.item_id):
			return {}
		unique_indices.append(index)
	var source_slots := _copy_slots()
	var destination_slots := destination._copy_slots()
	var remaining := source_stack.count
	var max_stack := item_catalog.get_definition(source_stack.item_id).max_stack
	if not source_stack.has_instance_data():
		for index in unique_indices:
			var destination_stack := destination_slots[index]
			if destination_stack == null or destination_stack.item_id != source_stack.item_id:
				continue
			if destination_stack.has_instance_data() or destination_stack.count >= max_stack:
				continue
			var moved := mini(remaining, max_stack - destination_stack.count)
			destination_stack.count += moved
			remaining -= moved
			if remaining == 0:
				break
	if remaining > 0:
		for index in unique_indices:
			if destination_slots[index] != null:
				continue
			if source_stack.has_instance_data():
				if remaining != source_stack.count:
					return {}
				destination_slots[index] = source_stack.copy()
				remaining = 0
				break
			var moved := mini(remaining, max_stack)
			destination_slots[index] = InventoryStack.new(source_stack.item_id, moved)
			remaining -= moved
			if remaining == 0:
				break
	if remaining > 0:
		return {}
	source_slots[src_idx] = null
	return {
		"source": source_slots,
		"destination": destination_slots,
	}

func _simulate_transfer_to(destination: InventoryModel, src_idx: int, dst_idx: int, drag_count: int) -> Dictionary:
	if (
		destination == null
		or item_catalog != destination.item_catalog
		or equipment_instance_factory != destination.equipment_instance_factory
	):
		return {}
	if src_idx < 0 or src_idx >= size or dst_idx < 0 or dst_idx >= destination.size:
		return {}
	var source_stack := slots[src_idx]
	if source_stack == null or drag_count <= 0 or drag_count > source_stack.count:
		return {}
	if source_stack.has_instance_data() and drag_count != source_stack.count:
		return {}
	if not destination.can_slot_accept_item_id(dst_idx, source_stack.item_id):
		return {}
	var destination_stack := destination.slots[dst_idx]
	if destination_stack != null:
		if destination_stack.item_id == source_stack.item_id:
			if source_stack.has_instance_data() or destination_stack.has_instance_data():
				if drag_count != source_stack.count or not can_slot_accept_item_id(src_idx, destination_stack.item_id):
					return {}
			elif destination_stack.count >= item_catalog.get_definition(source_stack.item_id).max_stack:
				return {}
		elif drag_count != source_stack.count or not can_slot_accept_item_id(src_idx, destination_stack.item_id):
			return {}
	var source_slots := _copy_slots()
	var destination_slots := destination._copy_slots()
	var simulated_source := source_slots[src_idx]
	var simulated_destination := destination_slots[dst_idx]
	if simulated_destination == null:
		if drag_count == simulated_source.count:
			destination_slots[dst_idx] = simulated_source
			source_slots[src_idx] = null
		else:
			assert(not simulated_source.has_instance_data())
			destination_slots[dst_idx] = InventoryStack.new(simulated_source.item_id, drag_count)
			simulated_source.count -= drag_count
	elif simulated_destination.item_id == simulated_source.item_id:
		if simulated_source.has_instance_data() or simulated_destination.has_instance_data():
			source_slots[src_idx] = simulated_destination
			destination_slots[dst_idx] = simulated_source
		else:
			var max_stack := item_catalog.get_definition(simulated_source.item_id).max_stack
			var moved := mini(drag_count, max_stack - simulated_destination.count)
			simulated_destination.count += moved
			simulated_source.count -= moved
			if simulated_source.count == 0:
				source_slots[src_idx] = null
	else:
		source_slots[src_idx] = simulated_destination
		destination_slots[dst_idx] = simulated_source
	return {
		"source": source_slots,
		"destination": destination_slots,
	}

func can_commit_socketed_rune(
	gear_index: int,
	expected_rune_ids: Array[StringName],
	next_rune_ids: Array[StringName],
	rune_source_index: int,
	rune_id: StringName,
) -> bool:
	return not _simulate_socketed_rune(
		gear_index,
		expected_rune_ids,
		next_rune_ids,
		rune_source_index,
		rune_id,
	).is_empty()

func commit_socketed_rune(
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
	slots = simulated
	inventory_changed.emit()
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
		or gear_index >= size
		or rune_source_index < 0
		or rune_source_index >= min(size, FILLABLE_SIZE)
		or gear_index == rune_source_index
		or rune_id.is_empty()
	):
		return []
	var gear := slots[gear_index]
	var rune_stack := slots[rune_source_index]
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

func can_commit_unsocketed_rune(
	gear_index: int,
	expected_rune_ids: Array[StringName],
	next_rune_ids: Array[StringName],
	returned_rune_id: StringName,
) -> bool:
	return not _simulate_unsocketed_rune(
		gear_index,
		expected_rune_ids,
		next_rune_ids,
		returned_rune_id,
	).is_empty()

func commit_unsocketed_rune(
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
	slots = simulated
	inventory_changed.emit()
	return true

func _simulate_unsocketed_rune(
	gear_index: int,
	expected_rune_ids: Array[StringName],
	next_rune_ids: Array[StringName],
	returned_rune_id: StringName,
) -> Array[InventoryStack]:
	if (
		gear_index < 0
		or gear_index >= size
		or returned_rune_id.is_empty()
		or not item_catalog.has_definition(returned_rune_id)
		or not item_catalog.get_definition(returned_rune_id) is RuneDefinition
	):
		return []
	var gear := slots[gear_index]
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
	return [] if remaining > 0 else simulated

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
			var stack := slots[idx] if idx >= 0 and idx < slots.size() else null
			encoded.append(null if stack == null else stack.to_dict())
		regions_dict[region_name] = encoded
	return {
		"selected": selected_slot,
		"starter_item_migration_version": starter_item_migration_version,
		"regions": regions_dict,
	}

func get_equipment_instance_ids() -> Array[int]:
	var instance_ids: Array[int] = []
	for stack in slots:
		if stack != null and stack.equipment_instance != null:
			instance_ids.append(stack.equipment_instance.instance_id)
	return instance_ids

func encode_slots() -> Array:
	var encoded: Array = []
	for stack in slots:
		encoded.append(null if stack == null else stack.to_dict())
	return encoded

func restore_slots(encoded: Array) -> bool:
	if encoded.size() != size:
		return false
	var restored: Array[InventoryStack] = []
	restored.resize(size)
	restored.fill(null)
	var restored_instance_ids: Dictionary = {}
	for index in range(size):
		var raw = encoded[index]
		if raw == null:
			continue
		if not raw is Dictionary:
			return false
		var stack := InventoryStack.from_dict(raw)
		if not _is_valid_stack(stack):
			return false
		if stack.equipment_instance != null:
			var instance_id := stack.equipment_instance.instance_id
			if restored_instance_ids.has(instance_id):
				return false
			restored_instance_ids[instance_id] = true
		restored[index] = stack
	slots = restored
	inventory_changed.emit()
	return true

func from_dict(data: Dictionary) -> bool:
	var regions_dict = data.get("regions", {}) as Dictionary
	var restored_slots: Array[InventoryStack] = []
	restored_slots.resize(size)
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
			if idx >= size:
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
	var restored_migration_version := int(data.get("starter_item_migration_version", 0))
	if restored_migration_version < 0 or restored_migration_version > STARTER_ITEM_MIGRATION_VERSION:
		return false
	slots = restored_slots
	starter_item_migration_version = restored_migration_version
	selected_slot = int(data.get("selected", 0))
	if not is_hotbar_index(selected_slot):
		selected_slot = 0
	inventory_changed.emit()
	return true

func setup_starter():
	slots.fill(null)
	for starter_slot in STARTER_ITEMS_BY_SLOT:
		slots[starter_slot] = _create_stack(STARTER_ITEMS_BY_SLOT[starter_slot], 1, equipment_instance_factory)
		assert(slots[starter_slot] != null)
	slots[1] = InventoryStack.new(item_catalog.get_item_for_block(BlockId.Type.GRASS).id, 12)
	slots[2] = InventoryStack.new(item_catalog.get_item_for_block(BlockId.Type.STONE).id, 8)
	slots[6] = InventoryStack.new(item_catalog.get_item_for_block(BlockId.Type.TORCH).id, 16)
	selected_slot = 0
	starter_item_migration_version = STARTER_ITEM_MIGRATION_VERSION
	inventory_changed.emit()

func setup_empty():
	slots.fill(null)
	selected_slot = 0
	starter_item_migration_version = STARTER_ITEM_MIGRATION_VERSION
	inventory_changed.emit()
