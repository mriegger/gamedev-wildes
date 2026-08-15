extends RefCounted
class_name EntitySpawnRequest

var definition_id: StringName
var feet_position: Vector3
var behavior_seed: int

func _init(p_definition_id: StringName, p_feet_position: Vector3, p_behavior_seed: int):
	definition_id = p_definition_id
	feet_position = p_feet_position
	behavior_seed = p_behavior_seed
