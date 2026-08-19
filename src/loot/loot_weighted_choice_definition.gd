extends Resource
class_name LootWeightedChoiceDefinition

@export var id: StringName
@export_range(0.001, 999999.0, 0.001, "or_greater") var weight: float = 1.0
@export var drop: LootDropDefinition

func validate(source: String) -> bool:
	var valid := true
	if id.is_empty():
		push_error("[LootWeightedChoiceDefinition] Empty choice ID at %s" % source)
		valid = false
	if not is_finite(weight) or weight <= 0.0:
		push_error("[LootWeightedChoiceDefinition] Invalid weight for %s at %s" % [id, source])
		valid = false
	if drop == null:
		push_error("[LootWeightedChoiceDefinition] Missing drop for %s at %s" % [id, source])
		valid = false
	else:
		valid = drop.validate("%s drop" % source) and valid
	return valid
