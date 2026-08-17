extends RefCounted
class_name LevelEncounterSummary

var active_wave_count: int:
	get:
		return _active_wave_count
var active_enemy_count: int:
	get:
		return _active_enemy_count
var pending_enemy_count: int:
	get:
		return _pending_enemy_count

var _active_wave_count: int
var _active_enemy_count: int
var _pending_enemy_count: int

func _init(p_active_wave_count: int, p_active_enemy_count: int, p_pending_enemy_count: int) -> void:
	assert(p_active_wave_count >= 0 and p_active_enemy_count >= 0 and p_pending_enemy_count >= 0)
	_active_wave_count = p_active_wave_count
	_active_enemy_count = p_active_enemy_count
	_pending_enemy_count = p_pending_enemy_count
