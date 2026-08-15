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
var fill_block_id: int:
	get:
		return _fill_block_id

var _door_id: int
var _room_id: int
var _direction: LevelSocketDefinition.Direction
var _aperture_cells: Array[Vector3i] = []
var _fill_block_id: int

func _init(
	p_door_id: int,
	p_room_id: int,
	p_direction: LevelSocketDefinition.Direction,
	p_aperture_cells: Array[Vector3i],
	p_fill_block_id: int,
) -> void:
	assert(p_door_id >= 0 and p_room_id >= 0)
	assert(LevelSocketDefinition.is_valid_direction(p_direction))
	assert(not p_aperture_cells.is_empty())
	assert(StructureCell.is_structure_solid(p_fill_block_id))
	_door_id = p_door_id
	_room_id = p_room_id
	_direction = p_direction
	_aperture_cells.assign(p_aperture_cells)
	_fill_block_id = p_fill_block_id
