extends RefCounted
class_name MiningActionExecutor

var _inventory: InventoryModel
var _inventory_loadout: InventoryLoadoutCoordinator
var _unarmed_action: MiningActionDefinition
var _voxel_world: VoxelWorld
var _block_break_validator: Callable

func setup(
	inventory: InventoryModel,
	inventory_loadout: InventoryLoadoutCoordinator,
	unarmed_action: MiningActionDefinition,
	block_break_validator: Callable,
) -> bool:
	if (
		inventory == null
		or inventory_loadout == null
		or inventory_loadout.inventory_model != inventory
		or unarmed_action == null
		or _inventory != null
	):
		return false
	_inventory = inventory
	_inventory_loadout = inventory_loadout
	_unarmed_action = unarmed_action
	_block_break_validator = block_break_validator
	return true

func bind_world(voxel_world: VoxelWorld) -> void:
	assert(_inventory != null and voxel_world != null)
	_voxel_world = voxel_world

func unbind_world() -> void:
	_voxel_world = null

func try_mine(position: Vector3i, source: SelectedItemSource) -> Array[BlockEdit]:
	var failed: Array[BlockEdit] = []
	if (
		_voxel_world == null
		or not _inventory.is_selected_item_source_current(source)
		or (_block_break_validator.is_valid() and not bool(_block_break_validator.call(position)))
	):
		return failed
	var action := _get_action(source)
	if action == null:
		return failed
	var prepared := _voxel_world.prepare_mine_block(position)
	if prepared == null:
		return failed
	var edits := prepared.get_edits()
	if edits.is_empty() or not action.can_mine(_voxel_world.block_catalog.get_definition(edits[0].old_id)):
		return failed
	var drop_item_ids: Array[StringName] = []
	for edit in edits:
		if not edit.is_success() or not edit.is_mine():
			return failed
		var drop_item_id := _voxel_world.block_catalog.get_definition(edit.old_id).drop_item_id
		if not drop_item_id.is_empty():
			drop_item_ids.append(drop_item_id)
	var inventory_change: PreparedInventoryLoadoutChange
	if not drop_item_ids.is_empty():
		inventory_change = _inventory_loadout.prepare_inventory_change(
			_inventory.prepare_add_batch(drop_item_ids)
		)
		if inventory_change == null:
			return failed
	if (
		not _inventory.is_selected_item_source_current(source)
		or (_block_break_validator.is_valid() and not bool(_block_break_validator.call(position)))
		or not _voxel_world.can_commit_prepared_change(prepared)
		or (inventory_change != null and not _inventory_loadout.can_commit_prepared_change(inventory_change))
	):
		return failed
	if not _voxel_world._commit_prepared_change(prepared, false):
		return failed
	if inventory_change != null:
		var inventory_committed: bool = _inventory_loadout._commit_prepared_change(inventory_change)
		assert(inventory_committed)
	var world_notified: bool = _voxel_world._notify_prepared_change(prepared)
	assert(world_notified)
	if inventory_change != null:
		var inventory_notified: bool = _inventory_loadout._notify_prepared_change(inventory_change)
		assert(inventory_notified)
	return edits

func _get_action(source: SelectedItemSource) -> MiningActionDefinition:
	if source.get_item_id().is_empty():
		return _unarmed_action
	if not _inventory.item_catalog.has_definition(source.get_item_id()):
		return null
	return _inventory.item_catalog.get_definition(source.get_item_id()).primary_action as MiningActionDefinition
