extends RefCounted
class_name GameplayLocationState

enum Location {
	WORLD,
	LEVEL,
}

var _active_location: Location = Location.WORLD
var _overworld_position: Vector3

func _init(initial_overworld_position: Vector3):
	_overworld_position = initial_overworld_position

func enter_level(return_position: Vector3):
	_overworld_position = return_position
	_active_location = Location.LEVEL

func return_to_world():
	_active_location = Location.WORLD

func update_world_position(position: Vector3):
	if _active_location == Location.WORLD:
		_overworld_position = position

func get_persisted_position() -> Vector3:
	return _overworld_position

func is_in_level() -> bool:
	return _active_location == Location.LEVEL
