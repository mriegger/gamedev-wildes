extends RefCounted
class_name StatModifierReplacement

var source_id: StringName
var source_instance_id: StringName
var modifiers: Array[StatModifier]

func _init(p_source_id: StringName, p_source_instance_id: StringName, p_modifiers: Array[StatModifier]) -> void:
	source_id = p_source_id
	source_instance_id = p_source_instance_id
	modifiers = p_modifiers.duplicate()
