extends Resource
class_name StructureTorchDefinition

@export var cell: Vector3i
@export var support_direction: Vector3i

static func is_horizontal_support(direction: Vector3i) -> bool:
	return direction.y == 0 and absi(direction.x) + absi(direction.z) == 1
