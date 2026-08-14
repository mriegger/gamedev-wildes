extends Resource
class_name ArmorSetDefinition

@export var id: StringName
@export var full_set_modifiers: Array[StatModifier]

func validate(source: String) -> bool:
	var valid := true
	if id.is_empty():
		push_error("[ArmorSetDefinition] Empty armor set ID at %s" % source)
		valid = false
	if full_set_modifiers.is_empty():
		push_error("[ArmorSetDefinition] Full-set modifiers are missing at %s" % source)
		valid = false
	for modifier_index in range(full_set_modifiers.size()):
		if full_set_modifiers[modifier_index] == null:
			push_error("[ArmorSetDefinition] Missing full-set modifier %d at %s" % [modifier_index, source])
			valid = false
	return valid
