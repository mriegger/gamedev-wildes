extends Resource
class_name DamageTypeDefinition

@export var id: StringName

func validate(source: String) -> bool:
	if id.is_empty():
		push_error("[DamageTypeDefinition] Empty ID at %s" % source)
		return false
	return true
