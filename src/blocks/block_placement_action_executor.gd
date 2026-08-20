extends RefCounted
class_name BlockPlacementActionExecutor

var _inventory: InventoryModel
var _inventory_loadout: InventoryLoadoutCoordinator
var _voxel_world: VoxelWorld

func setup(
	inventory: InventoryModel,
	inventory_loadout: InventoryLoadoutCoordinator,
) -> bool:
	if (
		inventory == null
		or inventory_loadout == null
		or inventory_loadout.inventory_model != inventory
		or _inventory != null
	):
		return false
	_inventory = inventory
	_inventory_loadout = inventory_loadout
	return true

func bind_world(voxel_world: VoxelWorld) -> void:
	assert(_inventory != null and voxel_world != null)
	_voxel_world = voxel_world

func unbind_world() -> void:
	_voxel_world = null

func try_place(
	position: Vector3i,
	attach_direction: Vector3i,
	source: SelectedItemSource,
) -> BlockEdit:
	if _voxel_world == null or not _inventory.is_selected_item_source_current(source):
		return BlockEdit.fail(position, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_BLOCK_CHANGED)
	var action := _get_action(source)
	if action == null:
		return BlockEdit.fail(position, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_NOT_BREAKABLE)
	var world_change := (
		_voxel_world.prepare_place_emplacement(position, action.block.id)
		if action.block.emplacement != null
		else _voxel_world.prepare_place_block(position, action.block.id, attach_direction)
	)
	var inventory_change := _inventory_loadout.prepare_inventory_change(
		_inventory.prepare_consume_selected_source(source)
	)
	if (
		world_change == null
		or inventory_change == null
		or not _inventory.is_selected_item_source_current(source)
		or not _voxel_world.can_commit_prepared_change(world_change)
		or not _inventory_loadout.can_commit_prepared_change(inventory_change)
	):
		return BlockEdit.fail(position, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_BLOCK_CHANGED)
	if not _voxel_world._commit_prepared_change(world_change, false):
		return BlockEdit.fail(position, BlockEdit.Operation.PLACE, BlockEdit.Result.FAIL_BLOCK_CHANGED)
	var inventory_committed: bool = _inventory_loadout._commit_prepared_change(inventory_change)
	assert(inventory_committed)
	var world_notified: bool = _voxel_world._notify_prepared_change(world_change)
	assert(world_notified)
	var inventory_notified: bool = _inventory_loadout._notify_prepared_change(inventory_change)
	assert(inventory_notified)
	return world_change.get_edits()[0]

func _get_action(source: SelectedItemSource) -> BlockPlacementActionDefinition:
	if source.get_item_id().is_empty() or not _inventory.item_catalog.has_definition(source.get_item_id()):
		return null
	return _inventory.item_catalog.get_definition(source.get_item_id()).secondary_action as BlockPlacementActionDefinition
