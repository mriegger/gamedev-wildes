extends RefCounted
class_name InventoryModel

signal inventory_changed()

const HOTBAR_SIZE: int = 9
const BACKPACK_SIZE: int = 40
const EQUIPMENT_SIZE: int = 4
const REGIONS: Array = [
	{"name": "hotbar", "start": 0, "size": HOTBAR_SIZE},
	{"name": "backpack", "start": HOTBAR_SIZE, "size": BACKPACK_SIZE},
	{"name": "equipment", "start": HOTBAR_SIZE + BACKPACK_SIZE, "size": EQUIPMENT_SIZE},
]
const TOTAL_SIZE: int = HOTBAR_SIZE + BACKPACK_SIZE + EQUIPMENT_SIZE
const DEFAULT_SIZE: int = TOTAL_SIZE
const FILLABLE_SIZE: int = HOTBAR_SIZE + BACKPACK_SIZE

var size: int = TOTAL_SIZE
var item_catalog: ItemCatalog

var slots: Array[InventoryStack] = []
var selected_slot: int = 0

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
	for index in range(HOTBAR_SIZE, size):
		if slots[index] == null:
			slots[index] = slots[0]
			slots[0] = InventoryStack.new(item_id, 1)
			inventory_changed.emit()
			return true
	return false

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

static func get_region_indices(region_name: String) -> Array:
	for region in REGIONS:
		if region["name"] == region_name:
			var out: Array = []
			for index in range(region["size"]):
				out.append(region["start"] + index)
			return out
	return []

func can_slot_accept_item_id(idx: int, item_id) -> bool:
	return idx >= 0 and idx < min(size, FILLABLE_SIZE) and item_id is StringName and item_catalog.has_definition(item_id)

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
	return {"selected": selected_slot, "regions": regions_dict}

func from_dict(data: Dictionary) -> bool:
	var regions_dict = data.get("regions", {}) as Dictionary
	var restored_slots: Array[InventoryStack] = []
	restored_slots.resize(size)
	restored_slots.fill(null)
	for region in REGIONS:
		var region_name: String = region["name"]
		var indices: Array = InventoryModel.get_region_indices(region_name)
		var encoded = regions_dict.get(region_name, null)
		if encoded == null or not encoded is Array:
			return false
		for offset in range(min(indices.size(), (encoded as Array).size())):
			var idx := int(indices[offset])
			var raw = (encoded as Array)[offset]
			if raw == null:
				continue
			if not raw is Dictionary or not raw.has("item_id") or not raw.has("count"):
				return false
			var stack := InventoryStack.from_dict(raw)
			if not item_catalog.has_definition(stack.item_id):
				return false
			if stack.count < 1 or stack.count > item_catalog.get_definition(stack.item_id).max_stack:
				return false
			restored_slots[idx] = stack
	slots = restored_slots
	selected_slot = int(data.get("selected", 0))
	if not is_hotbar_index(selected_slot):
		selected_slot = 0
	inventory_changed.emit()
	return true

func setup_starter():
	slots.fill(null)
	slots[0] = InventoryStack.new(&"copper_pickaxe", 1)
	slots[1] = InventoryStack.new(item_catalog.get_item_for_block(BlockId.Type.GRASS).id, 12)
	slots[2] = InventoryStack.new(item_catalog.get_item_for_block(BlockId.Type.STONE).id, 8)
	slots[3] = InventoryStack.new(&"copper_sword", 1)
	slots[6] = InventoryStack.new(item_catalog.get_item_for_block(BlockId.Type.TORCH).id, 16)
	selected_slot = 0
	inventory_changed.emit()
