extends RefCounted
class_name EquipmentInstance

const MAXIMUM_INSTANCE_ID: int = 2147483646

var instance_id: int
var affixes: Array[EquipmentAffixInstance]
var socketed_rune_ids: Array[StringName]

func _init(
	p_instance_id: int,
	p_affixes: Array[EquipmentAffixInstance] = [],
	p_socketed_rune_ids: Array[StringName] = [],
):
	instance_id = p_instance_id
	affixes = []
	for affix in p_affixes:
		affixes.append(affix.copy())
	socketed_rune_ids = p_socketed_rune_ids.duplicate()

func copy() -> EquipmentInstance:
	return EquipmentInstance.new(instance_id, affixes, socketed_rune_ids)

func to_dict() -> Dictionary:
	var encoded_affixes: Array = []
	for affix in affixes:
		encoded_affixes.append(affix.to_dict())
	var encoded_rune_ids: Array[String] = []
	for rune_id in socketed_rune_ids:
		encoded_rune_ids.append(String(rune_id))
	return {
		"instance_id": instance_id,
		"affixes": encoded_affixes,
		"socketed_rune_ids": encoded_rune_ids,
	}

static func from_dict(data: Dictionary) -> EquipmentInstance:
	if (
		data.size() != 3
		or not data.has("instance_id")
		or not data.has("affixes")
		or not data.has("socketed_rune_ids")
		or (typeof(data["instance_id"]) != TYPE_INT and typeof(data["instance_id"]) != TYPE_FLOAT)
		or not data["affixes"] is Array
		or not data["socketed_rune_ids"] is Array
	):
		return null
	var affixes: Array[EquipmentAffixInstance] = []
	for raw_affix in data["affixes"] as Array:
		if not raw_affix is Dictionary:
			return null
		var affix := EquipmentAffixInstance.from_dict(raw_affix)
		if affix == null:
			return null
		affixes.append(affix)
	var rune_ids: Array[StringName] = []
	for raw_rune_id in data["socketed_rune_ids"] as Array:
		if typeof(raw_rune_id) != TYPE_STRING and typeof(raw_rune_id) != TYPE_STRING_NAME:
			return null
		rune_ids.append(StringName(raw_rune_id))
	var instance_id := int(data["instance_id"])
	if (
		not is_finite(float(data["instance_id"]))
		or float(data["instance_id"]) != float(instance_id)
		or instance_id < 1
		or instance_id > MAXIMUM_INSTANCE_ID
	):
		return null
	return EquipmentInstance.new(instance_id, affixes, rune_ids)
