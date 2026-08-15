extends RefCounted
class_name LevelDoorway

var door_id: int:
	get:
		return _door_id
var room_id: int:
	get:
		return _room_id
var direction: LevelSocketDefinition.Direction:
	get:
		return _direction
var aperture_cells: Array[Vector3i]:
	get:
		return _aperture_cells.duplicate()

var _door_id: int
var _room_id: int
var _direction: LevelSocketDefinition.Direction
var _aperture_cells: Array[Vector3i] = []

func _init(
	p_door_id: int,
	p_room_id: int,
	p_direction: LevelSocketDefinition.Direction,
	p_aperture_cells: Array[Vector3i],
) -> void:
	assert(p_door_id >= 0 and p_room_id >= 0)
	assert(LevelSocketDefinition.is_valid_direction(p_direction))
	assert(not p_aperture_cells.is_empty())
	_door_id = p_door_id
	_room_id = p_room_id
	_direction = p_direction
	_aperture_cells.assign(p_aperture_cells)
