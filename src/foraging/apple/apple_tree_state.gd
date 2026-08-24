extends RefCounted
class_name AppleTreeState

const SNAPSHOT_VERSION: int = 4
const MAXIMUM_GROUND_APPLES: int = 6
const MAXIMUM_DECORATIVE_APPLES: int = 20
const MAXIMUM_PLANTED_TREES: int = 256
const GROWTH_DURATION_HOURS: float = 12.0

var _collected_slots: Dictionary = {}
var _fallen_apples: Dictionary = {}
var _retained_trees: Dictionary = {}
var _planted_trees: Dictionary = {}

func is_collected(tree_position: Vector3i, slot_index: int) -> bool:
	return _collected_slots.has(_slot_key(tree_position, slot_index))

func collect(tree_position: Vector3i, slot_index: int) -> bool:
	if tree_position.y < 0 or slot_index < 0 or slot_index >= MAXIMUM_GROUND_APPLES:
		return false
	var key := _slot_key(tree_position, slot_index)
	if _collected_slots.has(key):
		return false
	_collected_slots[key] = [tree_position.x, tree_position.y, tree_position.z, slot_index]
	return true

func add_fallen_apple(tree_position: Vector3i, decorative_index: int, position: Vector3) -> bool:
	if tree_position.y < 0 or decorative_index < 0 or decorative_index >= MAXIMUM_DECORATIVE_APPLES or not position.is_finite():
		return false
	var key := _fallen_key(tree_position, decorative_index)
	if _fallen_apples.has(key):
		return false
	_fallen_apples[key] = [tree_position.x, tree_position.y, tree_position.z, decorative_index, position.x, position.y, position.z]
	return true

func collect_fallen_apple(tree_position: Vector3i, decorative_index: int) -> bool:
	return _fallen_apples.erase(_fallen_key(tree_position, decorative_index))

func has_fallen_apple(tree_position: Vector3i, decorative_index: int) -> bool:
	return _fallen_apples.has(_fallen_key(tree_position, decorative_index))

func retain_tree(tree_position: Vector3i) -> bool:
	if tree_position.y < 0:
		return false
	var key := _tree_key(tree_position)
	if _retained_trees.has(key):
		return false
	_retained_trees[key] = [tree_position.x, tree_position.y, tree_position.z]
	return true

func has_retained_tree(tree_position: Vector3i) -> bool:
	return _retained_trees.has(_tree_key(tree_position))

func get_retained_trees() -> Array[Vector3i]:
	var keys := _retained_trees.keys()
	keys.sort()
	var trees: Array[Vector3i] = []
	for key in keys:
		var values := _retained_trees[key] as Array
		trees.append(Vector3i(int(values[0]), int(values[1]), int(values[2])))
	return trees

func has_planted_seed(soil_position: Vector3i) -> bool:
	return _planted_trees.has(_tree_key(soil_position))

func add_planted_seed(soil_position: Vector3i) -> bool:
	var key := _tree_key(soil_position)
	if soil_position.y < 0 or _planted_trees.size() >= MAXIMUM_PLANTED_TREES or _planted_trees.has(key):
		return false
	_planted_trees[key] = [soil_position.x, soil_position.y, soil_position.z, 0.0, false]
	return true

func remove_planted_seed(soil_position: Vector3i) -> bool:
	return _planted_trees.erase(_tree_key(soil_position))

func get_planted_soil_positions() -> Array[Vector3i]:
	var keys := _planted_trees.keys()
	keys.sort()
	var positions: Array[Vector3i] = []
	for key in keys:
		var values := _planted_trees[key] as Array
		positions.append(Vector3i(int(values[0]), int(values[1]), int(values[2])))
	return positions

func get_growth_hours(soil_position: Vector3i) -> float:
	assert(has_planted_seed(soil_position))
	return float((_planted_trees[_tree_key(soil_position)] as Array)[3])

func advance_planted_trees(hours: float) -> bool:
	if not is_finite(hours) or hours <= 0.0:
		return false
	var advanced := false
	for key in _planted_trees:
		var values := _planted_trees[key] as Array
		var previous_hours := float(values[3])
		var next_hours := minf(previous_hours + hours, GROWTH_DURATION_HOURS)
		if is_equal_approx(previous_hours, next_hours):
			continue
		values[3] = next_hours
		advanced = true
	return advanced

func mark_tree_mature(soil_position: Vector3i) -> bool:
	if not has_planted_seed(soil_position):
		return false
	var values := _planted_trees[_tree_key(soil_position)] as Array
	if bool(values[4]) or not is_equal_approx(float(values[3]), GROWTH_DURATION_HOURS):
		return false
	values[4] = true
	return true

func is_tree_mature(soil_position: Vector3i) -> bool:
	return has_planted_seed(soil_position) and bool((_planted_trees[_tree_key(soil_position)] as Array)[4])

func has_planted_tree(tree_position: Vector3i) -> bool:
	var soil_position := tree_position + Vector3i.DOWN
	return is_tree_mature(soil_position)

func get_fallen_apples() -> Array[Dictionary]:
	var keys := _fallen_apples.keys()
	keys.sort()
	var fallen: Array[Dictionary] = []
	for key in keys:
		var values := _fallen_apples[key] as Array
		fallen.append({
			"tree_position": Vector3i(int(values[0]), int(values[1]), int(values[2])),
			"decorative_index": int(values[3]),
			"position": Vector3(float(values[4]), float(values[5]), float(values[6])),
		})
	return fallen

func restore(encoded: Variant) -> bool:
	if encoded == null:
		_collected_slots.clear()
		_fallen_apples.clear()
		_retained_trees.clear()
		_planted_trees.clear()
		return true
	if not encoded is Dictionary:
		return false
	var raw_version = encoded.get("version", null)
	if (not raw_version is int and not raw_version is float) or not is_finite(float(raw_version)) or raw_version != int(raw_version):
		return false
	var version := int(raw_version)
	if version not in [1, 2, 3, SNAPSHOT_VERSION] or encoded.size() != version + 1:
		return false
	var raw_slots = encoded.get("collected_slots", null)
	if not raw_slots is Array:
		return false
	var decoded_slots: Dictionary = {}
	for raw_slot in raw_slots:
		if not raw_slot is Array or raw_slot.size() != 4:
			return false
		var values: Array[int] = []
		for raw_value in raw_slot:
			if (not raw_value is int and not raw_value is float) or not is_finite(float(raw_value)):
				return false
			var value := int(raw_value)
			if raw_value != value:
				return false
			values.append(value)
		if values[1] < 0 or values[3] < 0 or values[3] >= MAXIMUM_GROUND_APPLES:
			return false
		var tree_position := Vector3i(values[0], values[1], values[2])
		var key := _slot_key(tree_position, values[3])
		if decoded_slots.has(key):
			return false
		decoded_slots[key] = values
	var decoded_fallen: Dictionary = {}
	if version >= 2:
		var raw_fallen = encoded.get("fallen_apples", null)
		if not raw_fallen is Array:
			return false
		for raw_apple in raw_fallen:
			if not raw_apple is Array or raw_apple.size() != 7:
				return false
			for index in 7:
				if (not raw_apple[index] is int and not raw_apple[index] is float) or not is_finite(float(raw_apple[index])):
					return false
			var tree_position := Vector3i(int(raw_apple[0]), int(raw_apple[1]), int(raw_apple[2]))
			var decorative_index := int(raw_apple[3])
			var position := Vector3(float(raw_apple[4]), float(raw_apple[5]), float(raw_apple[6]))
			if raw_apple[0] != tree_position.x or raw_apple[1] != tree_position.y or raw_apple[2] != tree_position.z or raw_apple[3] != decorative_index:
				return false
			if tree_position.y < 0 or decorative_index < 0 or decorative_index >= MAXIMUM_DECORATIVE_APPLES or not position.is_finite():
				return false
			var key := _fallen_key(tree_position, decorative_index)
			if decoded_fallen.has(key):
				return false
			decoded_fallen[key] = [tree_position.x, tree_position.y, tree_position.z, decorative_index, position.x, position.y, position.z]
	var decoded_retained: Dictionary = {}
	if version >= 3:
		var raw_retained = encoded.get("retained_trees", null)
		if not raw_retained is Array:
			return false
		for raw_tree in raw_retained:
			if not raw_tree is Array or raw_tree.size() != 3:
				return false
			var values: Array[int] = []
			for raw_value in raw_tree:
				if (not raw_value is int and not raw_value is float) or not is_finite(float(raw_value)):
					return false
				var value := int(raw_value)
				if raw_value != value:
					return false
				values.append(value)
			if values[1] < 0:
				return false
			var tree_position := Vector3i(values[0], values[1], values[2])
			var key := _tree_key(tree_position)
			if decoded_retained.has(key):
				return false
			decoded_retained[key] = values
	var decoded_planted: Dictionary = {}
	if version == SNAPSHOT_VERSION:
		var raw_planted = encoded.get("planted_trees", null)
		if not raw_planted is Array or raw_planted.size() > MAXIMUM_PLANTED_TREES:
			return false
		for raw_tree in raw_planted:
			if not raw_tree is Array or raw_tree.size() != 5 or not raw_tree[4] is bool:
				return false
			for raw_value in raw_tree.slice(0, 4):
				if (not raw_value is int and not raw_value is float) or not is_finite(float(raw_value)):
					return false
			var soil_position := Vector3i(int(raw_tree[0]), int(raw_tree[1]), int(raw_tree[2]))
			var growth_hours := float(raw_tree[3])
			if raw_tree[0] != soil_position.x or raw_tree[1] != soil_position.y or raw_tree[2] != soil_position.z or soil_position.y < 0 or growth_hours < 0.0 or growth_hours > GROWTH_DURATION_HOURS:
				return false
			var key := _tree_key(soil_position)
			if decoded_planted.has(key):
				return false
			var mature := bool(raw_tree[4])
			if mature and not is_equal_approx(growth_hours, GROWTH_DURATION_HOURS):
				return false
			decoded_planted[key] = [soil_position.x, soil_position.y, soil_position.z, growth_hours, mature]
	_collected_slots = decoded_slots
	_fallen_apples = decoded_fallen
	_retained_trees = decoded_retained
	_planted_trees = decoded_planted
	return true

func snapshot() -> Dictionary:
	var keys := _collected_slots.keys()
	keys.sort()
	var encoded_slots: Array = []
	for key in keys:
		encoded_slots.append((_collected_slots[key] as Array).duplicate())
	var fallen_keys := _fallen_apples.keys()
	fallen_keys.sort()
	var encoded_fallen: Array = []
	for key in fallen_keys:
		encoded_fallen.append((_fallen_apples[key] as Array).duplicate())
	var retained_keys := _retained_trees.keys()
	retained_keys.sort()
	var encoded_retained: Array = []
	for key in retained_keys:
		encoded_retained.append((_retained_trees[key] as Array).duplicate())
	var planted_keys := _planted_trees.keys()
	planted_keys.sort()
	var encoded_planted: Array = []
	for key in planted_keys:
		encoded_planted.append((_planted_trees[key] as Array).duplicate())
	return {"version": SNAPSHOT_VERSION, "collected_slots": encoded_slots, "fallen_apples": encoded_fallen, "retained_trees": encoded_retained, "planted_trees": encoded_planted}

func _tree_key(tree_position: Vector3i) -> String:
	return "%d,%d,%d" % [tree_position.x, tree_position.y, tree_position.z]

func _slot_key(tree_position: Vector3i, slot_index: int) -> String:
	return "%d,%d,%d,%d" % [tree_position.x, tree_position.y, tree_position.z, slot_index]

func _fallen_key(tree_position: Vector3i, decorative_index: int) -> String:
	return "%d,%d,%d,%d" % [tree_position.x, tree_position.y, tree_position.z, decorative_index]
