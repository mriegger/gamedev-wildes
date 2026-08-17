extends RefCounted
class_name LevelPlacedModule

var placement_id: int:
	get:
		return _placement_id
var definition: LevelModuleDefinition
var origin: Vector3i
var rotation: int
var room_type_id: StringName
var _placement_id: int

func _init(p_placement_id: int, p_definition: LevelModuleDefinition, p_origin: Vector3i, p_rotation: int, p_room_type_id: StringName) -> void:
	_placement_id = p_placement_id
	definition = p_definition
	origin = p_origin
	rotation = posmod(p_rotation, 4)
	room_type_id = p_room_type_id

func world_cell(local_cell: Vector3i) -> Vector3i:
	return origin + definition.rotate_cell(local_cell, rotation)

func world_direction(local_direction: LevelSocketDefinition.Direction) -> LevelSocketDefinition.Direction:
	return LevelSocketDefinition.rotate(local_direction, rotation)

func world_socket_aperture(socket: LevelSocketDefinition) -> Array[Vector3i]:
	var aperture: Array[Vector3i] = []
	for cell in definition.socket_aperture_cells(socket):
		aperture.append(world_cell(cell))
	return aperture
