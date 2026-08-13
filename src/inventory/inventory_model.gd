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

var slots: Array[InventoryStack] = []
var selected_slot: int = 0
var starter_item_migration_version: int = 0

func _init(p_item_catalog: ItemCatalog, p_size: int = DEFAULT_SIZE):
	assert(p_item_catalog != null)
	item_catalog = p_item_catalog
	size = p_size
	slots.resize(size)
	slots.fill(null)
	selected_slot = 0

func get_slot(idx: int) -> InventoryStack:
	if idx < 0 or idx >= size:
		return null
	return slots[idx]

func get_selected_data() -> InventoryStack:
	return get_slot(selected_slot)

func get_selected_item_id():
	var stack := get_selected_data()
	if stack == null:
		return null
	return stack.item_id

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
		elif backpack_stack.item_id == hotbar_stack.item_id:
			available_capacity += max_stack - backpack_stack.count
	if available_capacity < hotbar_stack.count:
		return false
	var remaining: int = hotbar_stack.count
	for backpack_idx in range(HOTBAR_SIZE, backpack_end):
		var backpack_stack := slots[backpack_idx]
		if backpack_stack == null or backpack_stack.item_id != hotbar_stack.item_id:
			continue
		var moved := mini(remaining, max_stack - backpack_stack.count)
		backpack_stack.count += moved
		remaining -= moved
		if remaining == 0:
			break
	if remaining > 0:
		for backpack_idx in range(HOTBAR_SIZE, backpack_end):
			if slots[backpack_idx] == null:
				slots[backpack_idx] = InventoryStack.new(hotbar_stack.item_id, remaining)
				remaining = 0
				break
	assert(remaining == 0)
	slots[hotbar_idx] = null
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
			slots[index] = InventoryStack.new(item_id, 1)
			inventory_changed.emit()
			return true
	for index in range(HOTBAR_SIZE, min(size, FILLABLE_SIZE)):
		if slots[index] == null:
			slots[index] = slots[0]
			slots[0] = InventoryStack.new(item_id, 1)
			inventory_changed.emit()
			return true
	return false

func migrate_starter_items() -> bool:
	if starter_item_migration_version >= STARTER_ITEM_MIGRATION_VERSION:
		return true
	var simulated := InventoryModel.new(item_catalog, size)
	simulated.slots = _copy_slots()
	for starter_slot in STARTER_ITEMS_BY_SLOT:
		var item_id: StringName = STARTER_ITEMS_BY_SLOT[starter_slot]
		var item_ensured := simulated.ensure_item(item_id) if starter_slot < HOTBAR_SIZE else simulated.ensure_backpack_item(item_id)
		if not item_ensured:
			return false
	slots = simulated.slots
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
			slots[index] = InventoryStack.new(item_id, 1)
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
	var max_stack: int = item_catalog.get_definition(item_id).max_stack
	var remaining := _grant_item_to_indices(simulated, item_id, count, max_stack, _get_backpack_indices())
	if remaining > 0:
		return false
	slots = simulated
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

func can_exchange_inventory_items(consumed: Dictionary[StringName, int], granted: Dictionary[StringName, int]) -> bool:
	return not _simulate_inventory_exchange(consumed, granted).is_empty()

func exchange_inventory_items(consumed: Dictionary[StringName, int], granted: Dictionary[StringName, int]) -> bool:
	var simulated := _simulate_inventory_exchange(consumed, granted)
	if simulated.is_empty():
		return false
	slots = simulated
	inventory_changed.emit()
	return true

func _simulate_inventory_exchange(consumed: Dictionary[StringName, int], granted: Dictionary[StringName, int]) -> Array[InventoryStack]:
	if consumed.is_empty() or granted.is_empty():
		return []
	var simulated := _copy_slots()
	var inventory_indices := _get_inventory_indices()
	for item_id in consumed:
		var remaining: int = consumed[item_id]
		if remaining < 1 or not item_catalog.has_definition(item_id):
			return []
		for index in inventory_indices:
			var stack := simulated[index]
			if stack == null or stack.item_id != item_id:
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
		remaining = _grant_item_to_indices(simulated, item_id, remaining, max_stack, _get_backpack_indices())
		if remaining > 0:
			remaining = _grant_item_to_indices(simulated, item_id, remaining, max_stack, _get_hotbar_indices())
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

func _grant_item_to_indices(
	simulated: Array[InventoryStack],
	item_id: StringName,
	count: int,
	max_stack: int,
	indices: Array[int],
) -> int:
	var remaining := count
	for index in indices:
		var stack := simulated[index]
		if stack == null or stack.item_id != item_id or stack.count >= max_stack:
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
		simulated[index] = InventoryStack.new(item_id, stack_count)
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

func _simulate_slots(ids: Array[StringName]) -> Array[InventoryStack]:
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
			sim[empty_idx] = InventoryStack.new(item_id, 1)
			continue
		return []
	return sim

func can_add_batch(ids: Array[StringName]) -> bool:
	if ids.is_empty():
		return true
	return not _simulate_slots(ids).is_empty()

func add_batch(ids: Array[StringName]) -> bool:
	if ids.is_empty():
		return true
	var sim := _simulate_slots(ids)
	if sim.is_empty():
		return false
	slots = sim
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
	var drag_item_id := src.item_id
	if not can_slot_accept_item_id(dst_idx, drag_item_id):
		return false
	var dst := slots[dst_idx]
	if dst == null:
		return true
	if dst.item_id == drag_item_id:
		return dst.count < item_catalog.get_definition(drag_item_id).max_stack
	return drag_count == src.count and can_slot_accept_item_id(src_idx, dst.item_id)

func handle_drop(src_idx: int, dst_idx: int, drag_count: int) -> bool:
	if not can_handle_drop(src_idx, dst_idx, drag_count):
		return false
	var src := slots[src_idx]
	var dst := slots[dst_idx]
	var drag_item_id := src.item_id
	if dst == null:
		slots[dst_idx] = InventoryStack.new(drag_item_id, drag_count)
		src.count -= drag_count
		if src.count <= 0:
			slots[src_idx] = null
		inventory_changed.emit()
		return true
	if dst.item_id == drag_item_id:
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

func from_dict(data: Dictionary) -> bool:
	var regions_dict = data.get("regions", {}) as Dictionary
	var restored_slots: Array[InventoryStack] = []
	restored_slots.resize(size)
	restored_slots.fill(null)
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
			if not raw is Dictionary or not raw.has("item_id") or not raw.has("count"):
				return false
			var stack := InventoryStack.from_dict(raw)
			if not can_slot_accept_item_id(idx, stack.item_id):
				return false
			if stack.count < 1 or stack.count > item_catalog.get_definition(stack.item_id).max_stack:
				return false
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
		slots[starter_slot] = InventoryStack.new(STARTER_ITEMS_BY_SLOT[starter_slot], 1)
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
