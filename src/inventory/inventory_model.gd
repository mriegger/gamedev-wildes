extends RefCounted
class_name InventoryModel

## InventoryModel - atomic batch via single private simulation returning resulting slots

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

func set_slot(idx: int, data) -> bool:
	if idx < 0 or idx >= size:
		return false
	slots[idx] = data
	inventory_changed.emit()
	return true

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

func find_slot_with_type(block_type: int) -> int:
	for i in range(size):
		var s = slots[i]
		if s != null and s["type"] == block_type:
			return i
	return -1

func find_empty_slot() -> int:
	for i in range(size):
		if slots[i] == null:
			return i
	return -1

func has_item(block_type: int) -> bool:
	return find_slot_with_type(block_type) != -1

func get_total_count(block_type: int) -> int:
	var total = 0
	for i in range(size):
		var s = slots[i]
		if s != null and s["type"] == block_type:
			total += s["count"]
	return total

# --- single private simulation returning resulting slots (atomic) ---

func _simulate_slots(ids: Array[int]) -> Array:
	# Returns new slots array if batch can be added fully, else [] (failure) - no side effects
	if ids.is_empty():
		return slots.duplicate(true)

	var sim = slots.duplicate(true)

	for block_id in ids:
		var added = false
		# Try existing stacks of same type with space
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
		# Try empty slot
		var empty_idx = -1
		for j in range(size):
			if sim[j] == null:
				empty_idx = j
				break
		if empty_idx != -1:
			sim[empty_idx] = {"type": block_id, "count": 1}
			added = true
			continue
		# No space
		return []

	return sim

func _expand_counts(block_type: int, count: int) -> Array[int]:
	var arr: Array[int] = []
	for _i in range(count):
		arr.append(block_type)
	return arr

func can_add_item(block_type: int, count: int = 1) -> bool:
	if count <= 0:
		return false
	return can_add_batch(_expand_counts(block_type, count))

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

func is_full() -> bool:
	return find_empty_slot() == -1 and not _has_stack_space()

func _has_stack_space() -> bool:
	for i in range(size):
		var s = slots[i]
		if s != null and s["count"] < max_stack:
			return true
	return false

func add_item(block_type: int, count: int = 1) -> int:
	if count <= 0:
		return -1
	var ids = _expand_counts(block_type, count)
	var sim = _simulate_slots(ids)
	if sim.is_empty():
		return -1
	# Find first index that changed for return value
	var first_idx = -1
	for i in range(size):
		var old = slots[i]
		var nw = sim[i]
		if old == null and nw != null and nw["type"] == block_type:
			first_idx = i
			break
		if old != null and nw != null and old["type"] == block_type and nw["count"] != old["count"]:
			first_idx = i
			break
	if first_idx == -1:
		# Fallback: any slot with type
		for i in range(size):
			var s = sim[i]
			if s != null and s["type"] == block_type:
				first_idx = i
				break
	slots = sim
	inventory_changed.emit()
	return first_idx

func consume_from_slot(idx: int, count: int = 1) -> bool:
	if idx < 0 or idx >= size:
		return false
	var s = slots[idx]
	if s == null or s["count"] < count:
		return false
	s["count"] -= count
	if s["count"] <= 0:
		slots[idx] = null
	inventory_changed.emit()
	return true

func consume_selected(count: int = 1) -> bool:
	return consume_from_slot(selected_slot, count)

func can_consume_selected() -> bool:
	var s = get_selected_data()
	return s != null and s["count"] > 0

func swap_slots(a: int, b: int) -> bool:
	if a < 0 or a >= size or b < 0 or b >= size:
		return false
	if a == b:
		return true
	var old_a = slots[a]
	var old_b = slots[b]
	slots[a] = old_b
	slots[b] = old_a
	inventory_changed.emit()
	return true

func move_to_empty(from_idx: int) -> int:
	var empty = find_empty_slot()
	if empty == -1:
		return -1
	if swap_slots(from_idx, empty):
		return empty
	return -1

func get_all_items() -> Array:
	var out: Array = []
	for i in range(size):
		var s = slots[i]
		if s != null:
			out.append({"slot": i, "type": s["type"], "count": s["count"]})
	return out

func to_dict() -> Dictionary:
	return {"size": size, "selected": selected_slot, "slots": slots.duplicate(true), "max_stack": max_stack}

func from_dict(d: Dictionary):
	size = d.get("size", size)
	max_stack = d.get("max_stack", max_stack)
	var sl = d.get("slots", [])
	slots.resize(size)
	for i in range(size):
		slots[i] = sl[i] if i < sl.size() else null
	selected_slot = d.get("selected", 0)
	inventory_changed.emit()

func setup_starter():
	clear()
	set_slot(6, {"type": BlockId.Type.TORCH, "count": 16})
	set_slot(0, {"type": BlockId.Type.GRASS, "count": 12})
	set_slot(1, {"type": BlockId.Type.STONE, "count": 8})
	select_slot(0)

func get_display_name_for_slot(idx: int) -> String:
	var s = get_slot(idx)
	if s == null:
		return ""
	var t = s["type"]
	if BlockId.is_valid(t):
		return BlockId.get_display_name(t as BlockId.Type)
	return "Type %s" % t
