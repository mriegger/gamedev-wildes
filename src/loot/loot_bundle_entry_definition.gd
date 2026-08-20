extends Resource
class_name LootBundleEntryDefinition

@export var id: StringName
@export var drop: LootDropDefinition

func validate(source: String) -> bool:
	var valid := true
	if id.is_empty():
		push_error("[LootBundleEntryDefinition] Empty entry ID at %s" % source)
		valid = false
	if drop == null:
		push_error("[LootBundleEntryDefinition] Missing drop for %s at %s" % [id, source])
		valid = false
	else:
		valid = drop.validate("%s drop" % source) and valid
	return valid
