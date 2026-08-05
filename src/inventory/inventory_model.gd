extends RefCounted
class_name InventoryModel

signal inventory_changed()

const HOTBAR_SIZE: int = 9
const BACKPACK_SIZE: int = 40
const EQUIPMENT_SIZE: int = 4
const REGIONS: Array = [
	{"name": "hotbar", "start": 0, "size": HOTBAR_SIZE, "accepted_types": null},
	{"name": "backpack", "start": HOTBAR_SIZE, "size": BACKPACK_SIZE, "accepted_types": null},
	{"name": "equipment", "start": HOTBAR_SIZE + BACKPACK_SIZE, "size": EQUIPMENT_SIZE, "accepted_types": []},
]
const TOTAL_SIZE: int = HOTBAR_SIZE + BACKPACK_SIZE + EQUIPMENT_SIZE
const DEFAULT_SIZE: int = TOTAL_SIZE
const DEFAULT_MAX_STACK: int = 99
const FILLABLE_REGION_IDS: Array = ["hotbar", "backpack"]

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

func clear():
	for i in range(size):
		slots[i] = null
	inventory_changed.emit()

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
	if ids.is_empty():
		return slots.duplicate(true)

	var sim = slots.duplicate(true)
	var fillable_indices: Array = []
	for rid in FILLABLE_REGION_IDS:
		fillable_indices.append_array(get_region_indices(rid))

	for block_id in ids:
		var added = false
		for i in fillable_indices:
			if not can_slot_accept_type(i, block_id):
				continue
			var s = sim[i]
			if s != null and s["type"] == block_id:
				if max_stack <= 0:
					s["count"] += 1
					added = true
					break
				if s["count"] < max_stack:
					s["count"] += 1
					added = true
					break
		if added:
			continue
		var empty_idx = -1
		for j in fillable_indices:
			if not can_slot_accept_type(j, block_id):
				continue
			if sim[j] == null:
				empty_idx = j
				break
		if empty_idx != -1:
			sim[empty_idx] = {"type": block_id, "count": 1}
			added = true
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

func consume_selected(count: int = 1) -> bool:
	if not is_hotbar_index(selected_slot):
		return false
	var s = slots[selected_slot]
	if s == null or s["count"] < count:
		return false
	s["count"] -= count
	if s["count"] <= 0:
		slots[selected_slot] = null
	inventory_changed.emit()
	return true

func can_consume_selected() -> bool:
	var s = get_selected_data()
	return s != null and s["count"] > 0

func is_valid_index(idx: int) -> bool:
	return idx >= 0 and idx < size

func _region_for_index(idx: int) -> Dictionary:
	for r in REGIONS:
		if idx >= r["start"] and idx < r["start"] + r["size"]:
			return r
	return {}

func _is_in_regions(idx: int, region_ids: Array) -> bool:
	var r = _region_for_index(idx)
	if r.is_empty():
		return false
	return r["name"] in region_ids

func is_hotbar_index(idx: int) -> bool:
	return _is_in_regions(idx, ["hotbar"])

func is_equipment_index(idx: int) -> bool:
	return _is_in_regions(idx, ["equipment"])

func get_region_indices(region_name: String) -> Array:
	for r in REGIONS:
		if r["name"] == region_name:
			var out: Array = []
			for i in range(r["size"]):
				out.append(r["start"] + i)
			return out
	return []

func can_slot_accept_type(idx: int, type) -> bool:
	if not is_valid_index(idx):
		return false
	var region = _region_for_index(idx)
	if region.is_empty():
		return false
	if region.has("accepted_types"):
		var at = region["accepted_types"]
		if at == null:
			return type != null and type != BlockId.Type.AIR
		if at is Array:
			if at.is_empty():
				return false
			return type in at
	if is_equipment_index(idx):
		return _can_equipment_accept(type)
	return true

func _can_equipment_accept(type) -> bool:
	if type == null or type == BlockId.Type.AIR:
		return false
	var region = _region_for_index(_get_equipment_start())
	if not region.is_empty() and region.has("accepted_types"):
		var at = region["accepted_types"]
		if at is Array:
			return type in at
	return false

func _get_equipment_start() -> int:
	for r in REGIONS:
		if r["name"] == "equipment":
			return int(r["start"])
	return HOTBAR_SIZE + BACKPACK_SIZE

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
		var space = 999999 if max_stack <= 0 else max_stack - dst["count"]
		return space > 0 and min(drag_count, space) > 0
	return drag_count == src["count"] and can_slot_accept_type(src_idx, dst["type"])

func handle_drop(src_idx: int, dst_idx: int, drag_count: int) -> bool:
	if not can_handle_drop(src_idx, dst_idx, drag_count):
		return false
	var src = slots[src_idx]
	var dst = slots[dst_idx]
	var drag_type = src["type"]
	if dst == null:
		if drag_count == src["count"]:
			slots[dst_idx] = {"type": drag_type, "count": drag_count}
			slots[src_idx] = null
		else:
			slots[dst_idx] = {"type": drag_type, "count": drag_count}
			slots[src_idx]["count"] = src["count"] - drag_count
			if slots[src_idx]["count"] <= 0:
				slots[src_idx] = null
		inventory_changed.emit()
		return true
	if dst["type"] == drag_type:
		var space = max_stack - dst["count"] if max_stack > 0 else 999999
		if space <= 0:
			return false
		var to_move = min(drag_count, space)
		if to_move <= 0:
			return false
		dst["count"] += to_move
		if drag_count == src["count"]:
			if to_move == drag_count:
				slots[src_idx] = null
			else:
				slots[src_idx]["count"] = src["count"] - to_move
				if slots[src_idx]["count"] <= 0:
					slots[src_idx] = null
		else:
			slots[src_idx]["count"] = src["count"] - to_move
			if slots[src_idx]["count"] <= 0:
				slots[src_idx] = null
		inventory_changed.emit()
		return true
	if drag_count != src["count"]:
		return false
	if not can_slot_accept_type(src_idx, dst["type"]):
		return false
	slots[src_idx] = dst
	slots[dst_idx] = src
	inventory_changed.emit()
	return true

func to_dict() -> Dictionary:
	# Per-region persistence to avoid positional reindex when REGIONS change order/size.
	var regions_dict: Dictionary = {}
	for r in REGIONS:
		var rname: String = r["name"]
		var indices: Array = get_region_indices(rname)
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
	# Keep flat slots for backward compat with old saves while new code prefers regions.
	return {"size": size, "selected": selected_slot, "slots": slots.duplicate(true), "regions": regions_dict, "max_stack": max_stack, "version": 1}

func from_dict(d: Dictionary):
	max_stack = int(d.get("max_stack", max_stack))
	# Prefer per-region load to survive reindex/reorder; fallback to positional flat slots.
	if d.has("regions") and d["regions"] is Dictionary:
		var regions_dict: Dictionary = d["regions"] as Dictionary
		slots.resize(size)
		for i in range(size):
			slots[i] = null
		for r in REGIONS:
			var rname: String = r["name"]
			var indices: Array = get_region_indices(rname)
			var arr = regions_dict.get(rname, null)
			if arr == null or not arr is Array:
				continue
			for j in range(min(indices.size(), (arr as Array).size())):
				var idx = int(indices[j])
				var raw = (arr as Array)[j]
				if raw == null:
					slots[idx] = null
				elif raw is Dictionary and raw.has("type") and raw.has("count"):
					slots[idx] = {"type": int(raw.get("type", 0)), "count": int(raw.get("count", 0))}
				else:
					slots[idx] = null
	else:
		var sl = d.get("slots", [])
		slots.resize(size)
		for i in range(size):
			if i < (sl as Array).size():
				var raw = (sl as Array)[i]
				if raw == null:
					slots[i] = null
				elif raw is Dictionary:
					if raw.has("type") and raw.has("count"):
						slots[i] = {
							"type": int(raw.get("type", 0)),
							"count": int(raw.get("count", 0))
						}
					else:
						slots[i] = null
				else:
					slots[i] = null
			else:
				slots[i] = null
	selected_slot = int(d.get("selected", 0))
	if not is_hotbar_index(selected_slot):
		selected_slot = 0
	inventory_changed.emit()

func setup_starter():
	clear()
	slots[6] = {"type": BlockId.Type.TORCH, "count": 16}
	slots[0] = {"type": BlockId.Type.GRASS, "count": 12}
	slots[1] = {"type": BlockId.Type.STONE, "count": 8}
	select_slot(0)
	inventory_changed.emit()
