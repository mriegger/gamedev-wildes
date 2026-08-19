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
