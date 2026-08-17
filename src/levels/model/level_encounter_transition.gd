extends RefCounted
class_name LevelEncounterTransition

var room_id: int:
	get:
		return _room_id
var summary: LevelEncounterSummary:
	get:
		return _summary
var room_cleared: bool:
	get:
		return _room_cleared
var opened_seal_ids: Array[int]:
	get:
		return _opened_seal_ids.duplicate()

var _room_id: int
var _summary: LevelEncounterSummary
var _room_cleared: bool
var _opened_seal_ids: Array[int] = []

func _init(
	p_room_id: int,
	p_summary: LevelEncounterSummary,
	p_room_cleared: bool,
	p_opened_seal_ids: Array[int],
) -> void:
	assert(p_room_id >= 0 and p_summary != null)
	_room_id = p_room_id
	_summary = p_summary
	_room_cleared = p_room_cleared
	_opened_seal_ids.assign(p_opened_seal_ids)
	_opened_seal_ids.sort()
	for index in _opened_seal_ids.size():
		assert(_opened_seal_ids[index] >= 0)
		assert(index == 0 or _opened_seal_ids[index - 1] != _opened_seal_ids[index])
