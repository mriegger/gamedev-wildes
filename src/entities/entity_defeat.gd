extends RefCounted
class_name EntityDefeat

var runtime_id: int:
	get:
		return _runtime_id
var definition_id: StringName:
	get:
		return _definition_id
var _runtime_id: int
var _definition_id: StringName

func _init(
	p_runtime_id: int,
	p_definition_id: StringName,
) -> void:
	assert(p_runtime_id > 0)
	assert(not p_definition_id.is_empty())
	_runtime_id = p_runtime_id
	_definition_id = p_definition_id
