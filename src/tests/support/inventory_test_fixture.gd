extends RefCounted
class_name InventoryTestFixture

static func restore_slot(inventory: InventoryModel, index: int, stack: InventoryStack) -> bool:
	return restore_slots(inventory, {index: stack})

static func restore_slots(inventory: InventoryModel, replacements: Dictionary) -> bool:
	if inventory == null:
		return false
	var data := inventory.to_dict()
	var regions := data["regions"] as Dictionary
	for index_value in replacements:
		if typeof(index_value) != TYPE_INT:
			return false
		var index := int(index_value)
		var location := _get_location(index, inventory.get_size())
		if location.is_empty():
			return false
		var stack = replacements[index_value]
		if stack != null and not stack is InventoryStack:
			return false
		var encoded := regions[location["region"]] as Array
		encoded[location["offset"]] = null if stack == null else (stack as InventoryStack).to_dict()
	return inventory.from_dict(data)

static func get_slots(inventory: InventoryModel) -> Array[InventoryStack]:
	var slots: Array[InventoryStack] = []
	slots.resize(inventory.get_size())
	for index in range(inventory.get_size()):
		slots[index] = inventory.get_slot(index)
	return slots

static func create_loadout(
	inventory: InventoryModel,
	actor_stats: ActorStats = null,
	item_proficiency: ItemProficiency = null,
) -> InventoryLoadoutCoordinator:
	if actor_stats == null:
		actor_stats = ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	if item_proficiency == null:
		item_proficiency = ItemProficiency.new(inventory.item_catalog)
	var coordinator := InventoryLoadoutCoordinator.new()
	if not coordinator.setup(inventory, actor_stats, item_proficiency):
		return null
	return coordinator

static func _get_location(index: int, inventory_size: int) -> Dictionary:
	if index < 0 or index >= inventory_size:
		return {}
	for region in InventoryModel.REGIONS:
		var start := int(region["start"])
		var region_size := int(region["size"])
		if index >= start and index < start + region_size:
			return {"region": region["name"], "offset": index - start}
	return {}
