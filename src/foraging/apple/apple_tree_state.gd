extends RefCounted
class_name AppleTreeState

const SNAPSHOT_VERSION: int = 1
const MAXIMUM_GROUND_APPLES: int = 6

var _collected_slots: Dictionary = {}

func is_collected(tree_position: Vector3i, slot_index: int) -> bool:
	return _collected_slots.has(_slot_key(tree_position, slot_index))

func collect(tree_position: Vector3i, slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= MAXIMUM_GROUND_APPLES:
		return false
	var key := _slot_key(tree_position, slot_index)
	if _collected_slots.has(key):
		return false
	_collected_slots[key] = [tree_position.x, tree_position.y, tree_position.z, slot_index]
	return true

func restore(encoded: Variant) -> bool:
	if encoded == null:
		_collected_slots.clear()
		return true
	if not encoded is Dictionary or encoded.size() != 2:
		return false
	var raw_version = encoded.get("version", null)
	if (not raw_version is int and not raw_version is float) or raw_version != int(raw_version) or int(raw_version) != SNAPSHOT_VERSION:
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
			if not raw_value is int and not raw_value is float:
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
	_collected_slots = decoded_slots
	return true

func snapshot() -> Dictionary:
	var keys := _collected_slots.keys()
	keys.sort()
	var encoded_slots: Array = []
	for key in keys:
		encoded_slots.append((_collected_slots[key] as Array).duplicate())
	return {"version": SNAPSHOT_VERSION, "collected_slots": encoded_slots}

func _slot_key(tree_position: Vector3i, slot_index: int) -> String:
	return "%d,%d,%d,%d" % [tree_position.x, tree_position.y, tree_position.z, slot_index]
