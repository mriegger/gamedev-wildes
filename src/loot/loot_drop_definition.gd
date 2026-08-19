extends Resource
class_name LootDropDefinition

@export var item: ItemDefinition
@export_range(1, 999, 1, "or_greater") var minimum_count: int = 1
@export_range(1, 999, 1, "or_greater") var maximum_count: int = 1
@export var equipment_roll: LootEquipmentRollDefinition

func validate(source: String) -> bool:
	var valid := true
	if item == null:
		push_error("[LootDropDefinition] Missing item at %s" % source)
		valid = false
	if minimum_count < 1 or maximum_count < minimum_count:
		push_error("[LootDropDefinition] Invalid count range at %s" % source)
		valid = false
	if item != null and maximum_count > item.max_stack:
		push_error("[LootDropDefinition] Count exceeds stack limit for %s at %s" % [item.id, source])
		valid = false
	if item != null and item.equipment_type != null and (minimum_count != 1 or maximum_count != 1):
		push_error("[LootDropDefinition] Equipment drop must have a count of one at %s" % source)
		valid = false
	if equipment_roll != null:
		valid = equipment_roll.validate(item, "%s equipment roll" % source) and valid
	return valid
