extends RefCounted
class_name PumpkinPatchState

const TILE_COUNT: int = 20
const SNAPSHOT_VERSION: int = 2
const LEGACY_SNAPSHOT_VERSION: int = 1
const LEGACY_HARVESTED_STATE_ID: StringName = &"harvested"
const EMPTY_STATE_ID: StringName = &"empty"

var _present: bool = false
var _origin: Vector3i
var _growth_state_ids: Array[StringName] = []
var _quarter_turns: PackedInt32Array = []

func is_present() -> bool:
	return _present

func get_origin() -> Vector3i:
	return _origin

func get_growth_state_id(tile_index: int) -> StringName:
	assert(tile_index >= 0 and tile_index < _growth_state_ids.size())
	return _growth_state_ids[tile_index]

func get_quarter_turns(tile_index: int) -> int:
	assert(tile_index >= 0 and tile_index < _quarter_turns.size())
	return _quarter_turns[tile_index]

func transition_growth_state(tile_index: int, expected_state_id: StringName, result_state_id: StringName, valid_state_ids: Array[StringName]) -> bool:
	if not _present or tile_index < 0 or tile_index >= _growth_state_ids.size():
		return false
	if expected_state_id.is_empty() or result_state_id not in valid_state_ids:
		return false
	if _growth_state_ids[tile_index] != expected_state_id:
		return false
	_growth_state_ids[tile_index] = result_state_id
	return true

func replace(origin: Vector3i, growth_state_ids: Array[StringName], quarter_turns: PackedInt32Array, valid_state_ids: Array[StringName]) -> bool:
	if not _values_are_valid(origin, growth_state_ids, quarter_turns, valid_state_ids):
		return false
	_present = true
	_origin = origin
	_growth_state_ids = growth_state_ids.duplicate()
	_quarter_turns = quarter_turns.duplicate()
	return true

func restore(encoded: Dictionary, valid_state_ids: Array[StringName]) -> bool:
	var raw_version = encoded.get("version", LEGACY_SNAPSHOT_VERSION)
	if not raw_version is int and not raw_version is float:
		return false
	var version := int(raw_version)
	if raw_version != version or version not in [LEGACY_SNAPSHOT_VERSION, SNAPSHOT_VERSION]:
		return false
	if encoded.get("present", null) is not bool:
		return false
	if not bool(encoded["present"]):
		var absent_size := 1 if version == LEGACY_SNAPSHOT_VERSION else 2
		if encoded.size() != absent_size:
			return false
		_present = false
		_origin = Vector3i.ZERO
		_growth_state_ids.clear()
		_quarter_turns.clear()
		return true
	var present_size := 4 if version == LEGACY_SNAPSHOT_VERSION else 5
	if encoded.size() != present_size:
		return false
	var raw_origin = encoded.get("origin", null)
	var raw_state_ids = encoded.get("growth_state_ids", null)
	var raw_quarter_turns = encoded.get("quarter_turns", null)
	if not raw_origin is Array or raw_origin.size() != 3:
		return false
	if not raw_state_ids is Array or not raw_quarter_turns is Array:
		return false
	var origin := Vector3i(int(raw_origin[0]), int(raw_origin[1]), int(raw_origin[2]))
	if raw_origin[0] != origin.x or raw_origin[1] != origin.y or raw_origin[2] != origin.z:
		return false
	var state_ids: Array[StringName] = []
	for raw_state_id in raw_state_ids:
		if not raw_state_id is String:
			return false
		var state_id := StringName(raw_state_id)
		if version == LEGACY_SNAPSHOT_VERSION and state_id == LEGACY_HARVESTED_STATE_ID:
			state_id = EMPTY_STATE_ID
		state_ids.append(state_id)
	var rotations := PackedInt32Array()
	for raw_quarter_turns_value in raw_quarter_turns:
		if not raw_quarter_turns_value is float and not raw_quarter_turns_value is int:
			return false
		var quarter_turns := int(raw_quarter_turns_value)
		if raw_quarter_turns_value != quarter_turns:
			return false
		rotations.append(quarter_turns)
	return replace(origin, state_ids, rotations, valid_state_ids)

func snapshot() -> Dictionary:
	if not _present:
		return {"version": SNAPSHOT_VERSION, "present": false}
	var encoded_state_ids: Array[String] = []
	for state_id in _growth_state_ids:
		encoded_state_ids.append(String(state_id))
	var encoded_quarter_turns: Array[int] = []
	for quarter_turns in _quarter_turns:
		encoded_quarter_turns.append(quarter_turns)
	return {
		"version": SNAPSHOT_VERSION,
		"present": true,
		"origin": [_origin.x, _origin.y, _origin.z],
		"growth_state_ids": encoded_state_ids,
		"quarter_turns": encoded_quarter_turns,
	}

func _values_are_valid(origin: Vector3i, growth_state_ids: Array[StringName], quarter_turns: PackedInt32Array, valid_state_ids: Array[StringName]) -> bool:
	if origin.y < 0 or growth_state_ids.size() != TILE_COUNT or quarter_turns.size() != TILE_COUNT:
		return false
	for index in range(TILE_COUNT):
		var state_id := growth_state_ids[index]
		if state_id not in valid_state_ids or quarter_turns[index] < 0 or quarter_turns[index] > 3:
			return false
	return true
