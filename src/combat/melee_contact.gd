extends RefCounted
class_name MeleeContact

var source_runtime_id: int:
	get:
		return _source_runtime_id
var source_definition_id: StringName:
	get:
		return _source_definition_id
var target_runtime_id: int:
	get:
		return _target_runtime_id
var target_definition_id: StringName:
	get:
		return _target_definition_id
var attack_id: StringName:
	get:
		return _attack_id
var world_position: Vector3:
	get:
		return _world_position
var hit_direction: Vector3:
	get:
		return _hit_direction

var _source_runtime_id: int
var _source_definition_id: StringName
var _target_runtime_id: int
var _target_definition_id: StringName
var _attack_id: StringName
var _world_position: Vector3
var _hit_direction: Vector3

func _init(
	p_source_runtime_id: int,
	p_source_definition_id: StringName,
	p_target_runtime_id: int,
	p_target_definition_id: StringName,
	p_attack_id: StringName,
	p_world_position: Vector3,
	p_hit_direction: Vector3,
) -> void:
	assert(p_source_runtime_id >= 0)
	assert(not p_source_definition_id.is_empty())
	assert(p_target_runtime_id >= 0)
	assert(not p_target_definition_id.is_empty())
	assert(not p_attack_id.is_empty())
	assert(p_world_position.is_finite())
	assert(p_hit_direction.is_finite() and p_hit_direction.length_squared() > 0.0)
	_source_runtime_id = p_source_runtime_id
	_source_definition_id = p_source_definition_id
	_target_runtime_id = p_target_runtime_id
	_target_definition_id = p_target_definition_id
	_attack_id = p_attack_id
	_world_position = p_world_position
	_hit_direction = p_hit_direction.normalized()
