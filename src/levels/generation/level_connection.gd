extends RefCounted
class_name LevelConnection

var connection_id: int:
	get:
		return _connection_id
var first_placement_id: int:
	get:
		return _first_placement_id
var first_socket_id: StringName:
	get:
		return _first_socket_id
var first_direction: LevelSocketDefinition.Direction:
	get:
		return _first_direction
var first_aperture_cells: Array[Vector3i]:
	get:
		return _first_aperture_cells.duplicate()
var second_placement_id: int:
	get:
		return _second_placement_id
var second_socket_id: StringName:
	get:
		return _second_socket_id
var second_direction: LevelSocketDefinition.Direction:
	get:
		return _second_direction
var second_aperture_cells: Array[Vector3i]:
	get:
		return _second_aperture_cells.duplicate()

var _connection_id: int
var _first_placement_id: int
var _first_socket_id: StringName
var _first_direction: LevelSocketDefinition.Direction
var _first_aperture_cells: Array[Vector3i] = []
var _second_placement_id: int
var _second_socket_id: StringName
var _second_direction: LevelSocketDefinition.Direction
var _second_aperture_cells: Array[Vector3i] = []

func _init(
	p_connection_id: int,
	p_first_placement_id: int,
	p_first_socket_id: StringName,
	p_first_direction: LevelSocketDefinition.Direction,
	p_first_aperture_cells: Array[Vector3i],
	p_second_placement_id: int,
	p_second_socket_id: StringName,
	p_second_direction: LevelSocketDefinition.Direction,
	p_second_aperture_cells: Array[Vector3i],
) -> void:
	_connection_id = p_connection_id
	_first_placement_id = p_first_placement_id
	_first_socket_id = p_first_socket_id
	_first_direction = p_first_direction
	_first_aperture_cells.assign(p_first_aperture_cells)
	_second_placement_id = p_second_placement_id
	_second_socket_id = p_second_socket_id
	_second_direction = p_second_direction
	_second_aperture_cells.assign(p_second_aperture_cells)
