extends RefCounted
class_name WorldLootEntry

const NO_LIFETIME: float = -1.0

var entry_id: int
var stack: InventoryStack
var world_position: Vector3
var remaining_lifetime: float

func _init(
	p_entry_id: int,
	p_stack: InventoryStack,
	p_world_position: Vector3,
	p_remaining_lifetime: float,
) -> void:
	entry_id = p_entry_id
	stack = p_stack.copy()
	world_position = p_world_position
	remaining_lifetime = p_remaining_lifetime

func copy() -> WorldLootEntry:
	return WorldLootEntry.new(entry_id, stack, world_position, remaining_lifetime)

func has_lifetime() -> bool:
	return remaining_lifetime >= 0.0

func to_dict() -> Dictionary:
	return {
		"entry_id": entry_id,
		"stack": stack.to_dict(),
		"world_position": [world_position.x, world_position.y, world_position.z],
		"remaining_lifetime": remaining_lifetime if has_lifetime() else null,
	}

static func from_dict(data: Dictionary) -> WorldLootEntry:
	if (
		data.size() != 4
		or not data.has("entry_id")
		or not data.has("stack")
		or not data.has("world_position")
		or not data.has("remaining_lifetime")
		or (typeof(data["entry_id"]) != TYPE_INT and typeof(data["entry_id"]) != TYPE_FLOAT)
		or not data["stack"] is Dictionary
		or not data["world_position"] is Array
	):
		return null
	var raw_entry_id: float = float(data["entry_id"])
	var parsed_entry_id := int(raw_entry_id)
	if not is_finite(raw_entry_id) or raw_entry_id != float(parsed_entry_id):
		return null
	var raw_stack := data["stack"] as Dictionary
	if (
		raw_stack.size() != 3
		or not raw_stack.has("item_id")
		or not raw_stack.has("count")
		or not raw_stack.has("equipment_instance")
	):
		return null
	var parsed_stack := InventoryStack.from_dict(raw_stack)
	if parsed_stack == null:
		return null
	var raw_position := data["world_position"] as Array
	if raw_position.size() != 3:
		return null
	var coordinates: Array[float] = []
	for raw_coordinate in raw_position:
		if typeof(raw_coordinate) != TYPE_INT and typeof(raw_coordinate) != TYPE_FLOAT:
			return null
		var coordinate := float(raw_coordinate)
		if not is_finite(coordinate):
			return null
		coordinates.append(coordinate)
	var parsed_lifetime := NO_LIFETIME
	if data["remaining_lifetime"] != null:
		if typeof(data["remaining_lifetime"]) != TYPE_INT and typeof(data["remaining_lifetime"]) != TYPE_FLOAT:
			return null
		parsed_lifetime = float(data["remaining_lifetime"])
		if not is_finite(parsed_lifetime) or parsed_lifetime < 0.0:
			return null
	return WorldLootEntry.new(
		parsed_entry_id,
		parsed_stack,
		Vector3(coordinates[0], coordinates[1], coordinates[2]),
		parsed_lifetime,
	)
