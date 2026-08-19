extends RefCounted
class_name InventoryStack

var item_id: StringName
var count: int
var equipment_instance: EquipmentInstance

func _init(
	p_item_id: StringName,
	p_count: int,
	p_equipment_instance: EquipmentInstance = null,
):
	item_id = p_item_id
	count = p_count
	equipment_instance = null if p_equipment_instance == null else p_equipment_instance.copy()

func copy() -> InventoryStack:
	return InventoryStack.new(item_id, count, equipment_instance)

func has_instance_data() -> bool:
	return equipment_instance != null

func to_dict() -> Dictionary:
	return {
		"item_id": String(item_id),
		"count": count,
		"equipment_instance": null if equipment_instance == null else equipment_instance.to_dict(),
	}

static func from_dict(data: Dictionary) -> InventoryStack:
	if not data.has("item_id") or not data.has("count") or not data.has("equipment_instance"):
		return null
	if (
		(typeof(data["item_id"]) != TYPE_STRING and typeof(data["item_id"]) != TYPE_STRING_NAME)
		or (typeof(data["count"]) != TYPE_INT and typeof(data["count"]) != TYPE_FLOAT)
	):
		return null
	var count := int(data["count"])
	if not is_finite(float(data["count"])) or float(data["count"]) != float(count) or count < 1:
		return null
	var instance: EquipmentInstance
	if data["equipment_instance"] != null:
		if not data["equipment_instance"] is Dictionary:
			return null
		instance = EquipmentInstance.from_dict(data["equipment_instance"])
		if instance == null:
			return null
	return InventoryStack.new(
		StringName(data["item_id"]),
		count,
		instance,
	)
