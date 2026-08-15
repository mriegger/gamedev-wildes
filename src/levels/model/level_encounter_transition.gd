extends RefCounted
class_name LevelEncounterTransition

var active_enemy_count: int:
	get:
		return _active_enemy_count
var pending_enemy_count: int:
	get:
		return _pending_enemy_count
var room_cleared: bool:
	get:
		return _room_cleared
var door_changes: Dictionary:
	get:
		return _door_changes.duplicate()

var _active_enemy_count: int
var _pending_enemy_count: int
var _room_cleared: bool
var _door_changes: Dictionary

func _init(p_active_enemy_count: int, p_pending_enemy_count: int, p_room_cleared: bool, p_door_changes: Dictionary) -> void:
	assert(p_active_enemy_count >= 0 and p_pending_enemy_count >= 0)
	_active_enemy_count = p_active_enemy_count
	_pending_enemy_count = p_pending_enemy_count
	_room_cleared = p_room_cleared
	_door_changes = p_door_changes.duplicate()
