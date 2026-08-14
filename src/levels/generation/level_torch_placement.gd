extends RefCounted
class_name LevelTorchPlacement

var cell: Vector3i
var wall_direction: LevelSocketDefinition.Direction
var module_id: StringName

func _init(p_cell: Vector3i, p_wall_direction: LevelSocketDefinition.Direction, p_module_id: StringName) -> void:
	cell = p_cell
	wall_direction = p_wall_direction
	module_id = p_module_id
