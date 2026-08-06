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

var slots: Array = []
var selected_slot: int = 0

func _init(p_item_catalog: ItemCatalog, p_size: int = DEFAULT_SIZE):
	assert(p_item_catalog != null)
	item_catalog = p_item_catalog
	size = p_size
	slots.resize(size)
	for i in range(size):
		slots[i] = null
	selected_slot = 0

func get_slot(idx: int):
	if idx < 0 or idx >= size:
		return null
	return slots[idx]

func get_selected_data():
	return get_slot(selected_slot)

func get_selected_item_id():
	var s = get_selected_data()
	if s == null:
		return null
	return s["item_id"]

func select_slot(idx: int) -> bool:
	if not is_hotbar_index(idx):
		return false
	if idx == selected_slot:
		return true
	selected_slot = idx
	inventory_changed.emit()
	return true

func _simulate_slots(ids: Array[StringName]) -> Array:
	var sim = slots.duplicate(true)
	for item_id in ids:
		if item_id.is_empty() or not item_catalog.has_definition(item_id):
			return []
		var max_stack := item_catalog.get_definition(item_id).max_stack
		var added = false
		var empty_idx = -1
		for i in range(min(size, FILLABLE_SIZE)):
			var s = sim[i]
			if s == null:
				if empty_idx == -1:
					empty_idx = i
				continue
			if s["item_id"] == item_id and s["count"] < max_stack:
				s["count"] += 1
				added = true
				break
		if added:
			continue
		if empty_idx != -1:
			sim[empty_idx] = {"item_id": item_id, "count": 1}
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
	var sim = _simulate_slots(ids)
	if sim.is_empty():
		return false
	slots = sim
	inventory_changed.emit()
	return true

func consume_selected() -> bool:
	if not can_consume_selected():
		return false
	var s = slots[selected_slot]
	s["count"] -= 1
	if s["count"] <= 0:
		slots[selected_slot] = null
	inventory_changed.emit()
	return true

func can_consume_selected() -> bool:
	if not is_hotbar_index(selected_slot):
		return false
	var s = get_selected_data()
	return s != null and s["count"] > 0

func is_hotbar_index(idx: int) -> bool:
	return idx >= 0 and idx < HOTBAR_SIZE

static func get_region_indices(region_name: String) -> Array:
	for r in REGIONS:
		if r["name"] == region_name:
			var out: Array = []
			for i in range(r["size"]):
				out.append(r["start"] + i)
			return out
	return []

func can_slot_accept_item_id(idx: int, item_id) -> bool:
	return idx >= 0 and idx < min(size, FILLABLE_SIZE) and item_id is StringName and item_catalog.has_definition(item_id)

func can_handle_drop(src_idx: int, dst_idx: int, drag_count: int) -> bool:
	if src_idx < 0 or src_idx >= size or dst_idx < 0 or dst_idx >= size:
		return false
	if src_idx == dst_idx:
		return false
	var src = slots[src_idx]
	if src == null:
		return false
	if drag_count <= 0 or drag_count > src["count"]:
		return false
	var drag_item_id := src["item_id"] as StringName
	if not can_slot_accept_item_id(dst_idx, drag_item_id):
		return false
	var dst = slots[dst_idx]
	if dst == null:
		return true
	if dst["item_id"] == drag_item_id:
		return dst["count"] < item_catalog.get_definition(drag_item_id).max_stack
	return drag_count == src["count"] and can_slot_accept_item_id(src_idx, dst["item_id"])

func handle_drop(src_idx: int, dst_idx: int, drag_count: int) -> bool:
	if not can_handle_drop(src_idx, dst_idx, drag_count):
		return false
	var src = slots[src_idx]
	var dst = slots[dst_idx]
	var drag_item_id := src["item_id"] as StringName
	if dst == null:
		slots[dst_idx] = {"item_id": drag_item_id, "count": drag_count}
		src["count"] -= drag_count
		if src["count"] <= 0:
			slots[src_idx] = null
		inventory_changed.emit()
		return true
	if dst["item_id"] == drag_item_id:
		var max_stack := item_catalog.get_definition(drag_item_id).max_stack
		var to_move = min(drag_count, max_stack - dst["count"])
		dst["count"] += to_move
		src["count"] -= to_move
		if src["count"] <= 0:
			slots[src_idx] = null
		inventory_changed.emit()
		return true
	slots[src_idx] = dst
	slots[dst_idx] = src
	inventory_changed.emit()
	return true

func to_dict() -> Dictionary:
	var regions_dict: Dictionary = {}
	for r in REGIONS:
		var rname: String = r["name"]
		var indices: Array = InventoryModel.get_region_indices(rname)
		var arr: Array = []
		for idx in indices:
			var v = slots[idx] if idx >= 0 and idx < slots.size() else null
			if v == null:
				arr.append(null)
			elif v is Dictionary and v.has("item_id") and v.has("count"):
				arr.append({"item_id": String(v["item_id"]), "count": int(v["count"])})
			else:
				arr.append(null)
		regions_dict[rname] = arr
	return {"selected": selected_slot, "regions": regions_dict}

func from_dict(d: Dictionary) -> bool:
	var regions_dict = d.get("regions", {}) as Dictionary
	var restored_slots: Array = []
	restored_slots.resize(size)
	restored_slots.fill(null)
	for r in REGIONS:
		var rname: String = r["name"]
		var indices: Array = InventoryModel.get_region_indices(rname)
		var arr = regions_dict.get(rname, null)
		if arr == null or not arr is Array:
			return false
		for j in range(min(indices.size(), (arr as Array).size())):
			var idx = int(indices[j])
			var raw = (arr as Array)[j]
			if raw == null:
				continue
			if not raw is Dictionary or not raw.has("item_id") or not raw.has("count"):
				return false
			var item_id := StringName(raw.get("item_id", ""))
			var count := int(raw.get("count", 0))
			if not item_catalog.has_definition(item_id):
				return false
			if count < 1 or count > item_catalog.get_definition(item_id).max_stack:
				return false
			restored_slots[idx] = {"item_id": item_id, "count": count}
	slots = restored_slots
	selected_slot = int(d.get("selected", 0))
	if not is_hotbar_index(selected_slot):
		selected_slot = 0
	inventory_changed.emit()
	return true

func setup_starter():
	slots.fill(null)
	slots[6] = {"item_id": item_catalog.get_item_for_block(BlockId.Type.TORCH).id, "count": 16}
	slots[0] = {"item_id": item_catalog.get_item_for_block(BlockId.Type.GRASS).id, "count": 12}
	slots[1] = {"item_id": item_catalog.get_item_for_block(BlockId.Type.STONE).id, "count": 8}
	selected_slot = 0
	inventory_changed.emit()
