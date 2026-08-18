extends RefCounted
class_name ChestInventoryStore

var item_catalog: ItemCatalog
var _inventories: Dictionary[Vector3i, InventoryModel] = {}

func _init(p_item_catalog: ItemCatalog):
	assert(p_item_catalog != null)
	item_catalog = p_item_catalog

func get_or_create(position: Vector3i, slot_count: int) -> InventoryModel:
	if _inventories.has(position):
		var existing := _inventories[position] as InventoryModel
		if existing.size != slot_count:
			return null
		return existing
	var inventory := InventoryModel.new(item_catalog, slot_count)
	_inventories[position] = inventory
	return inventory

func get_inventory(position: Vector3i) -> InventoryModel:
	return _inventories.get(position, null)

func remove(position: Vector3i) -> bool:
	return _inventories.erase(position)

func snapshot() -> Dictionary:
	var keys: Array[String] = []
	var inventories_by_key: Dictionary[String, InventoryModel] = {}
	for position in _inventories:
		var key := _encode_position(position)
		keys.append(key)
		inventories_by_key[key] = _inventories[position]
	keys.sort()
	var encoded: Dictionary = {}
	for key in keys:
		var inventory := inventories_by_key[key]
		encoded[key] = {
			"size": inventory.size,
			"slots": inventory.encode_slots(),
		}
	return encoded

func restore(encoded: Dictionary) -> bool:
	var restored: Dictionary[Vector3i, InventoryModel] = {}
	for raw_key in encoded:
		if not raw_key is String:
			return false
		var position = _decode_position(raw_key)
		var raw_inventory = encoded[raw_key]
		if position == null or _encode_position(position) != raw_key or not raw_inventory is Dictionary:
			return false
		var slot_count := int(raw_inventory.get("size", 0))
		var raw_slots = raw_inventory.get("slots", null)
		if slot_count < 1 or slot_count > ContainerBlockDefinition.MAX_SLOT_COUNT or not raw_slots is Array:
			return false
		if raw_slots.size() != slot_count:
			return false
		var inventory := InventoryModel.new(item_catalog, slot_count)
		if not inventory.restore_slots(raw_slots):
			return false
		restored[position] = inventory
	_inventories = restored
	return true

func _encode_position(position: Vector3i) -> String:
	return "%d,%d,%d" % [position.x, position.y, position.z]

func _decode_position(encoded: String):
	var parts := encoded.split(",")
	if parts.size() != 3:
		return null
	for part in parts:
		if not part.is_valid_int():
			return null
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
