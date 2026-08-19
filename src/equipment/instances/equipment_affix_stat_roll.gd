extends RefCounted
class_name EquipmentAffixStatRoll

var stat_id: StringName
var operation: StatModifier.Operation
var amount: float

func _init(
	p_stat_id: StringName,
	p_operation: StatModifier.Operation,
	p_amount: float,
):
	stat_id = p_stat_id
	operation = p_operation
	amount = p_amount

func copy() -> EquipmentAffixStatRoll:
	return EquipmentAffixStatRoll.new(stat_id, operation, amount)

func to_dict() -> Dictionary:
	return {
		"stat_id": String(stat_id),
		"operation": int(operation),
		"amount": amount,
	}

static func from_dict(data: Dictionary) -> EquipmentAffixStatRoll:
	if (
		data.size() != 3
		or not data.has("stat_id")
		or not data.has("operation")
		or not data.has("amount")
		or (typeof(data["stat_id"]) != TYPE_STRING and typeof(data["stat_id"]) != TYPE_STRING_NAME)
		or (typeof(data["operation"]) != TYPE_INT and typeof(data["operation"]) != TYPE_FLOAT)
		or (typeof(data["amount"]) != TYPE_INT and typeof(data["amount"]) != TYPE_FLOAT)
	):
		return null
	var stat_id := StringName(data["stat_id"])
	if not is_finite(float(data["operation"])) or float(data["operation"]) != float(int(data["operation"])):
		return null
	var operation := int(data["operation"])
	var amount := float(data["amount"])
	if (
		stat_id.is_empty()
		or operation < StatModifier.Operation.ADD
		or operation > StatModifier.Operation.MULTIPLY
		or not is_finite(amount)
		or (operation == StatModifier.Operation.MULTIPLY and amount < 0.0)
	):
		return null
	return EquipmentAffixStatRoll.new(stat_id, operation as StatModifier.Operation, amount)
