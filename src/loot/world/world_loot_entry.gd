extends RefCounted
class_name WorldLootEntry

var entry_id: int
var stack: InventoryStack
var world_position: Vector3

func _init(
	p_entry_id: int,
	p_stack: InventoryStack,
	p_world_position: Vector3,
) -> void:
	entry_id = p_entry_id
	stack = p_stack.copy()
	world_position = p_world_position

func copy() -> WorldLootEntry:
	return WorldLootEntry.new(entry_id, stack, world_position)
