extends RefCounted
class_name AppleTreeState

const SNAPSHOT_VERSION: int = 2
const MAXIMUM_GROUND_APPLES: int = 6
const MAXIMUM_DECORATIVE_APPLES: int = 20

var _collected_slots: Dictionary = {}
var _fallen_apples: Dictionary = {}

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
		return true
	if not encoded is Dictionary:
		return false
	var raw_version = encoded.get("version", null)
	if (not raw_version is int and not raw_version is float) or not is_finite(float(raw_version)) or raw_version != int(raw_version):
		return false
	var version := int(raw_version)
	if version not in [1, SNAPSHOT_VERSION] or encoded.size() != (2 if version == 1 else 3):
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
	if version == SNAPSHOT_VERSION:
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
	_collected_slots = decoded_slots
	_fallen_apples = decoded_fallen
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
	return {"version": SNAPSHOT_VERSION, "collected_slots": encoded_slots, "fallen_apples": encoded_fallen}

func _slot_key(tree_position: Vector3i, slot_index: int) -> String:
	return "%d,%d,%d,%d" % [tree_position.x, tree_position.y, tree_position.z, slot_index]

func _fallen_key(tree_position: Vector3i, decorative_index: int) -> String:
	return "%d,%d,%d,%d" % [tree_position.x, tree_position.y, tree_position.z, decorative_index]
