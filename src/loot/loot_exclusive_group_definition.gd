extends Resource
class_name LootExclusiveGroupDefinition

@export var id: StringName
@export_range(0.0, 1.0, 0.001) var chance: float = 1.0
@export var choices: Array[LootWeightedChoiceDefinition]

func validate(source: String) -> bool:
	var valid := true
	if id.is_empty():
		push_error("[LootExclusiveGroupDefinition] Empty group ID at %s" % source)
		valid = false
	if not is_finite(chance) or chance < 0.0 or chance > 1.0:
		push_error("[LootExclusiveGroupDefinition] Invalid chance for %s at %s" % [id, source])
		valid = false
	if choices.is_empty():
		push_error("[LootExclusiveGroupDefinition] Missing choices for %s at %s" % [id, source])
		valid = false
	var choice_ids: Dictionary = {}
	var weight_total := 0.0
	for choice_index in range(choices.size()):
		var choice := choices[choice_index]
		var choice_source := "%s choice %d" % [source, choice_index]
		if choice == null:
			push_error("[LootExclusiveGroupDefinition] Missing choice %d for %s at %s" % [choice_index, id, source])
			valid = false
			continue
		valid = choice.validate(choice_source) and valid
		weight_total += choice.weight
		if choice_ids.has(choice.id):
			push_error("[LootExclusiveGroupDefinition] Duplicate choice ID %s for %s at %s" % [choice.id, id, source])
			valid = false
		choice_ids[choice.id] = true
	if not is_finite(weight_total):
		push_error("[LootExclusiveGroupDefinition] Choice weight total is not finite for %s at %s" % [id, source])
		valid = false
	return valid
