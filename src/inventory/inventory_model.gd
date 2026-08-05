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
const DEFAULT_MAX_STACK: int = 99
const FILLABLE_SIZE: int = HOTBAR_SIZE + BACKPACK_SIZE

var size: int = TOTAL_SIZE
var max_stack: int = DEFAULT_MAX_STACK

var slots: Array = []
var selected_slot: int = 0

func _init(p_size: int = DEFAULT_SIZE, p_max_stack: int = DEFAULT_MAX_STACK):
	size = p_size
	max_stack = p_max_stack
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

func get_selected_block_type():
	var s = get_selected_data()
	if s == null:
		return null
	return s["type"]

func select_slot(idx: int) -> bool:
	if not is_hotbar_index(idx):
		return false
	if idx == selected_slot:
		return true
	selected_slot = idx
	inventory_changed.emit()
	return true

func _simulate_slots(ids: Array[int]) -> Array:
	var sim = slots.duplicate(true)
	for block_id in ids:
		if block_id == BlockId.Type.AIR:
			return []
		var added = false
		var empty_idx = -1
		for i in range(min(size, FILLABLE_SIZE)):
			var s = sim[i]
			if s == null:
				if empty_idx == -1:
					empty_idx = i
				continue
			if s["type"] == block_id and (max_stack <= 0 or s["count"] < max_stack):
				s["count"] += 1
				added = true
				break
		if added:
			continue
		if empty_idx != -1:
			sim[empty_idx] = {"type": block_id, "count": 1}
			continue
		return []

	return sim

func can_add_batch(ids: Array[int]) -> bool:
	if ids.is_empty():
		return true
	return not _simulate_slots(ids).is_empty()

func add_batch(ids: Array[int]) -> bool:
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

func can_slot_accept_type(idx: int, type) -> bool:
	return idx >= 0 and idx < min(size, FILLABLE_SIZE) and type != null and type != BlockId.Type.AIR

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
	var drag_type = src["type"]
	if not can_slot_accept_type(dst_idx, drag_type):
		return false
	var dst = slots[dst_idx]
	if dst == null:
		return true
	if dst["type"] == drag_type:
		return max_stack <= 0 or dst["count"] < max_stack
	return drag_count == src["count"] and can_slot_accept_type(src_idx, dst["type"])

func handle_drop(src_idx: int, dst_idx: int, drag_count: int) -> bool:
	if not can_handle_drop(src_idx, dst_idx, drag_count):
		return false
	var src = slots[src_idx]
	var dst = slots[dst_idx]
	var drag_type = src["type"]
	if dst == null:
		slots[dst_idx] = {"type": drag_type, "count": drag_count}
		src["count"] -= drag_count
		if src["count"] <= 0:
			slots[src_idx] = null
		inventory_changed.emit()
		return true
	if dst["type"] == drag_type:
		var to_move = min(drag_count, max_stack - dst["count"]) if max_stack > 0 else drag_count
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
			elif v is Dictionary and v.has("type") and v.has("count"):
				arr.append({"type": int(v["type"]), "count": int(v["count"])})
			else:
				arr.append(null)
		regions_dict[rname] = arr
	return {"selected": selected_slot, "regions": regions_dict, "max_stack": max_stack}

func from_dict(d: Dictionary):
	max_stack = int(d.get("max_stack", max_stack))
	var regions_dict = d.get("regions", {}) as Dictionary
	slots.fill(null)
	for r in REGIONS:
		var rname: String = r["name"]
		var indices: Array = InventoryModel.get_region_indices(rname)
		var arr = regions_dict.get(rname, null)
		if arr == null or not arr is Array:
			continue
		for j in range(min(indices.size(), (arr as Array).size())):
			var idx = int(indices[j])
			var raw = (arr as Array)[j]
			if raw is Dictionary and raw.has("type") and raw.has("count"):
				slots[idx] = {"type": int(raw.get("type", 0)), "count": int(raw.get("count", 0))}
	selected_slot = int(d.get("selected", 0))
	if not is_hotbar_index(selected_slot):
		selected_slot = 0
	inventory_changed.emit()

func setup_starter():
	slots.fill(null)
	slots[6] = {"type": BlockId.Type.TORCH, "count": 16}
	slots[0] = {"type": BlockId.Type.GRASS, "count": 12}
	slots[1] = {"type": BlockId.Type.STONE, "count": 8}
	selected_slot = 0
	inventory_changed.emit()
