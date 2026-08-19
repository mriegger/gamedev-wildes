extends Resource
class_name EquipmentAffixStatDefinition

@export var stat_id: StringName
@export var operation: StatModifier.Operation = StatModifier.Operation.ADD
@export var minimum_amount: float
@export var maximum_amount: float

func validate(source: String) -> bool:
	if stat_id.is_empty():
		push_error("[EquipmentAffixStatDefinition] Missing stat ID at %s" % source)
		return false
	if operation != StatModifier.Operation.ADD and operation != StatModifier.Operation.MULTIPLY:
		push_error("[EquipmentAffixStatDefinition] Invalid operation for %s at %s" % [stat_id, source])
		return false
	if not is_finite(minimum_amount) or not is_finite(maximum_amount) or maximum_amount < minimum_amount:
		push_error("[EquipmentAffixStatDefinition] Invalid amount range for %s at %s" % [stat_id, source])
		return false
	if operation == StatModifier.Operation.MULTIPLY and minimum_amount < 0.0:
		push_error("[EquipmentAffixStatDefinition] Negative multiplier range for %s at %s" % [stat_id, source])
		return false
	return true
