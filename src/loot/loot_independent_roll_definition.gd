extends Resource
class_name LootIndependentRollDefinition

@export var id: StringName
@export_range(0.0, 1.0, 0.001) var chance: float = 1.0
@export var drop: LootDropDefinition

func validate(source: String) -> bool:
	var valid := true
	if id.is_empty():
		push_error("[LootIndependentRollDefinition] Empty roll ID at %s" % source)
		valid = false
	if not is_finite(chance) or chance < 0.0 or chance > 1.0:
		push_error("[LootIndependentRollDefinition] Invalid chance for %s at %s" % [id, source])
		valid = false
	if drop == null:
		push_error("[LootIndependentRollDefinition] Missing drop for %s at %s" % [id, source])
		valid = false
	else:
		valid = drop.validate("%s drop" % source) and valid
	return valid
