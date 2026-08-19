extends RefCounted
class_name EntityDefeat

var runtime_id: int:
	get:
		return _runtime_id
var definition_id: StringName:
	get:
		return _definition_id
var world_position: Vector3:
	get:
		return _world_position
var loot_seed: int:
	get:
		return _loot_seed

var _runtime_id: int
var _definition_id: StringName
var _world_position: Vector3
var _loot_seed: int

func _init(
	p_runtime_id: int,
	p_definition_id: StringName,
	p_world_position: Vector3,
	p_loot_seed: int,
) -> void:
	assert(p_runtime_id > 0)
	assert(not p_definition_id.is_empty())
	assert(p_world_position.is_finite())
	_runtime_id = p_runtime_id
	_definition_id = p_definition_id
	_world_position = p_world_position
	_loot_seed = p_loot_seed
