extends RefCounted
class_name InventoryStack

var item_id: StringName
var count: int

func _init(p_item_id: StringName, p_count: int):
	item_id = p_item_id
	count = p_count

func copy() -> InventoryStack:
	return InventoryStack.new(item_id, count)

func to_dict() -> Dictionary:
	return {"item_id": String(item_id), "count": count}

static func from_dict(data: Dictionary) -> InventoryStack:
	return InventoryStack.new(StringName(data.get("item_id", "")), int(data.get("count", 0)))
