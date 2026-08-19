extends Resource
class_name LootAffixChoiceDefinition

@export var id: StringName
@export_range(0.001, 999999.0, 0.001, "or_greater") var weight: float = 1.0
@export var affix: EquipmentAffixDefinition

func validate(item: ItemDefinition, source: String) -> bool:
	var valid := true
	if id.is_empty():
		push_error("[LootAffixChoiceDefinition] Empty choice ID at %s" % source)
		valid = false
	if not is_finite(weight) or weight <= 0.0:
		push_error("[LootAffixChoiceDefinition] Invalid weight for %s at %s" % [id, source])
		valid = false
	if affix == null or item == null or not affix.is_compatible_with(item):
		push_error("[LootAffixChoiceDefinition] Invalid affix for %s at %s" % [id, source])
		valid = false
	return valid
