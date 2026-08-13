extends RefCounted
class_name InventoryStack

var item_id: StringName
var count: int
var socketed_rune_ids: Array[StringName]

func _init(p_item_id: StringName, p_count: int, p_socketed_rune_ids: Array[StringName] = []):
	item_id = p_item_id
	count = p_count
	socketed_rune_ids = p_socketed_rune_ids.duplicate()

func copy() -> InventoryStack:
	return InventoryStack.new(item_id, count, socketed_rune_ids)

func to_dict() -> Dictionary:
	var encoded_rune_ids: Array[String] = []
	for rune_id in socketed_rune_ids:
		encoded_rune_ids.append(String(rune_id))
	return {
		"item_id": String(item_id),
		"count": count,
		"socketed_rune_ids": encoded_rune_ids,
	}

static func from_dict(data: Dictionary) -> InventoryStack:
	var encoded_rune_ids = data.get("socketed_rune_ids", null)
	if not encoded_rune_ids is Array:
		return null
	var rune_ids: Array[StringName] = []
	for encoded_rune_id in encoded_rune_ids as Array:
		if typeof(encoded_rune_id) != TYPE_STRING and typeof(encoded_rune_id) != TYPE_STRING_NAME:
			return null
		rune_ids.append(StringName(encoded_rune_id))
	return InventoryStack.new(StringName(data.get("item_id", "")), int(data.get("count", 0)), rune_ids)
