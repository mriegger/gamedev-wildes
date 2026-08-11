extends RefCounted
class_name LevelPlacedModule

var definition: LevelModuleDefinition
var origin: Vector3i
var rotation: int

func _init(p_definition: LevelModuleDefinition, p_origin: Vector3i, p_rotation: int) -> void:
	definition = p_definition
	origin = p_origin
	rotation = posmod(p_rotation, 4)

func world_cell(local_cell: Vector3i) -> Vector3i:
	return origin + definition.rotate_cell(local_cell, rotation)

func world_direction(local_direction: LevelSocketDefinition.Direction) -> LevelSocketDefinition.Direction:
	return LevelSocketDefinition.rotate(local_direction, rotation)
