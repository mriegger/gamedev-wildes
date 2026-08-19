extends RefCounted
class_name EquipmentAffixInstance

var affix_id: StringName
var stat_rolls: Array[EquipmentAffixStatRoll]

func _init(
	p_affix_id: StringName,
	p_stat_rolls: Array[EquipmentAffixStatRoll],
):
	affix_id = p_affix_id
	stat_rolls = []
	for stat_roll in p_stat_rolls:
		stat_rolls.append(stat_roll.copy())

func copy() -> EquipmentAffixInstance:
	return EquipmentAffixInstance.new(affix_id, stat_rolls)

func to_dict() -> Dictionary:
	var encoded_rolls: Array = []
	for stat_roll in stat_rolls:
		encoded_rolls.append(stat_roll.to_dict())
	return {
		"affix_id": String(affix_id),
		"stat_rolls": encoded_rolls,
	}

static func from_dict(data: Dictionary) -> EquipmentAffixInstance:
	if (
		data.size() != 2
		or not data.has("affix_id")
		or not data.has("stat_rolls")
		or (typeof(data["affix_id"]) != TYPE_STRING and typeof(data["affix_id"]) != TYPE_STRING_NAME)
		or not data["stat_rolls"] is Array
	):
		return null
	var affix_id := StringName(data["affix_id"])
	if affix_id.is_empty():
		return null
	var rolls: Array[EquipmentAffixStatRoll] = []
	for raw_roll in data["stat_rolls"] as Array:
		if not raw_roll is Dictionary:
			return null
		var roll := EquipmentAffixStatRoll.from_dict(raw_roll)
		if roll == null:
			return null
		rolls.append(roll)
	if rolls.is_empty():
		return null
	return EquipmentAffixInstance.new(affix_id, rolls)
