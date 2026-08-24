extends ItemActionDefinition
class_name PlantingActionDefinition

@export var crop_id: StringName

func validate(source: String) -> bool:
	if crop_id.is_empty():
		push_error("[PlantingActionDefinition] Missing crop ID at %s" % source)
		return false
	return true
