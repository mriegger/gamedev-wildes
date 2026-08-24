extends RefCounted
class_name ApplePlantingCoordinator

var _apple_trees: AppleTreeCoordinator
var _inventory: InventoryModel
var _inventory_loadout: InventoryLoadoutCoordinator

func setup(
	apple_trees: AppleTreeCoordinator,
	inventory: InventoryModel,
	inventory_loadout: InventoryLoadoutCoordinator,
) -> bool:
	if (
		apple_trees == null
		or inventory == null
		or inventory_loadout == null
		or inventory_loadout.inventory_model != inventory
		or _apple_trees != null
	):
		return false
	var has_supported_seed := false
	for definition in inventory.item_catalog.definitions:
		var action := definition.secondary_action as PlantingActionDefinition
		if action == null:
			continue
		if not apple_trees.supports_crop(action.crop_id):
			return false
		has_supported_seed = true
	if not has_supported_seed:
		return false
	_apple_trees = apple_trees
	_inventory = inventory
	_inventory_loadout = inventory_loadout
	return true

func try_plant(voxel_world: VoxelWorld, soil_position: Vector3i, source: SelectedItemSource) -> bool:
	var prepared := _prepare_planting(voxel_world, soil_position, source)
	if prepared == null or not prepared._is_for(self):
		return false
	var plant_change := prepared._get_plant_change()
	var inventory_change := prepared._get_inventory_change()
	if not _apple_trees.can_commit_prepared_plant(plant_change) or not _inventory_loadout.can_commit_prepared_change(inventory_change):
		return false
	var planted := _apple_trees._commit_prepared_plant(plant_change, false)
	assert(planted)
	var consumed := _inventory_loadout._commit_prepared_change(inventory_change)
	assert(consumed)
	var plant_notified := _apple_trees._notify_prepared_plant(plant_change)
	assert(plant_notified)
	var inventory_notified := _inventory_loadout._notify_prepared_change(inventory_change)
	assert(inventory_notified)
	return true

func _prepare_planting(
	voxel_world: VoxelWorld,
	soil_position: Vector3i,
	source: SelectedItemSource,
) -> PreparedApplePlantingTransaction:
	if not _apple_trees.uses_world(voxel_world) or not _inventory.is_selected_item_source_current(source):
		return null
	var action := _get_action(source)
	if action == null:
		return null
	var plant_change := _apple_trees.prepare_plant(soil_position, action.crop_id)
	var inventory_change := _inventory_loadout.prepare_inventory_change(_inventory.prepare_consume_selected_source(source))
	if plant_change == null or inventory_change == null:
		return null
	return PreparedApplePlantingTransaction.new(self, plant_change, inventory_change)

func _get_action(source: SelectedItemSource) -> PlantingActionDefinition:
	if source.get_item_id().is_empty() or not _inventory.item_catalog.has_definition(source.get_item_id()):
		return null
	return _inventory.item_catalog.get_definition(source.get_item_id()).secondary_action as PlantingActionDefinition
