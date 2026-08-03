extends RefCounted
class_name InventoryModel

signal inventory_changed()

const DEFAULT_SIZE: int = 9
const DEFAULT_MAX_STACK: int = 99

var size: int = DEFAULT_SIZE
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
	if idx < 0 or idx >= size:
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

	for block_id in ids:
		var added = false
		for i in range(size):
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
		for j in range(size):
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
	if selected_slot < 0 or selected_slot >= size:
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

func to_dict() -> Dictionary:
	return {"size": size, "selected": selected_slot, "slots": slots.duplicate(true), "max_stack": max_stack}

func from_dict(d: Dictionary):
	size = int(d.get("size", size))
	max_stack = int(d.get("max_stack", max_stack))
	var sl = d.get("slots", [])
	slots.resize(size)
	for i in range(size):
		if i < sl.size():
			var raw = sl[i]
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
	inventory_changed.emit()

func setup_starter():
	clear()
	slots[6] = {"type": BlockId.Type.TORCH, "count": 16}
	slots[0] = {"type": BlockId.Type.GRASS, "count": 12}
	slots[1] = {"type": BlockId.Type.STONE, "count": 8}
	select_slot(0)
	inventory_changed.emit()
