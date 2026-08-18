extends Resource
class_name CraftingStationBlockDefinition

@export var id: StringName
@export var display_name: String

func validate(source: String) -> bool:
	if not id.is_empty() and not display_name.is_empty():
		return true
	push_error("[CraftingStationBlockDefinition] Missing ID or display name at %s" % source)
	return false
