extends RefCounted
class_name ChestInventoryStore

var item_catalog: ItemCatalog
var equipment_instance_factory: EquipmentInstanceFactory
var _inventories: Dictionary[Vector3i, InventoryModel] = {}

func _init(
	p_item_catalog: ItemCatalog,
	p_equipment_instance_factory: EquipmentInstanceFactory,
):
	assert(p_item_catalog != null)
	assert(p_equipment_instance_factory != null)
	assert(p_equipment_instance_factory.item_catalog == p_item_catalog)
	item_catalog = p_item_catalog
	equipment_instance_factory = p_equipment_instance_factory

func get_or_create(position: Vector3i, slot_count: int) -> InventoryModel:
	if _inventories.has(position):
		var existing := _inventories[position] as InventoryModel
		if existing.size != slot_count:
			return null
		return existing
	var inventory := InventoryModel.new(item_catalog, equipment_instance_factory, slot_count)
	_inventories[position] = inventory
	return inventory

func get_inventory(position: Vector3i) -> InventoryModel:
	return _inventories.get(position, null)

func remove(position: Vector3i) -> bool:
	return _inventories.erase(position)

func snapshot() -> Dictionary:
	var encoded: Dictionary = {}
	for position in _inventories:
		encoded[position] = (_inventories[position] as InventoryModel).encode_slots()
	return encoded

func get_equipment_instance_ids() -> Array[int]:
	var instance_ids: Array[int] = []
	for inventory in _inventories.values():
		instance_ids.append_array((inventory as InventoryModel).get_equipment_instance_ids())
	return instance_ids

func restore(encoded: Dictionary) -> bool:
	var restored: Dictionary[Vector3i, InventoryModel] = {}
	for position in encoded:
		if typeof(position) != TYPE_VECTOR3I:
			return false
		var raw_slots = encoded[position]
		if not raw_slots is Array:
			return false
		var slot_count := (raw_slots as Array).size()
		if slot_count < 1 or slot_count > ContainerBlockDefinition.MAX_SLOT_COUNT:
			return false
		var inventory := InventoryModel.new(item_catalog, equipment_instance_factory, slot_count)
		if not inventory.restore_slots(raw_slots):
			return false
		restored[position] = inventory
	_inventories = restored
	return true
