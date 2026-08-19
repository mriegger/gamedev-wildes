extends RefCounted
class_name TillingActionExecutor

var _inventory: InventoryModel
var _voxel_world: VoxelWorld

func setup(inventory: InventoryModel) -> bool:
	if inventory == null or _inventory != null:
		return false
	_inventory = inventory
	return true

func bind_world(voxel_world: VoxelWorld) -> void:
	assert(_inventory != null and voxel_world != null)
	_voxel_world = voxel_world

func unbind_world() -> void:
	_voxel_world = null

func try_till(position: Vector3i, source: SelectedItemSource) -> BlockEdit:
	if (
		_voxel_world == null
		or _voxel_world.is_edit_protected(position)
		or not _inventory.is_selected_item_source_current(source)
	):
		return BlockEdit.fail(position, BlockEdit.Operation.REPLACE, BlockEdit.Result.FAIL_BLOCK_CHANGED)
	var action := _get_action(source)
	if action == null or _voxel_world.get_block_id_at(position + Vector3i.UP) != BlockId.Type.AIR:
		return BlockEdit.fail(position, BlockEdit.Operation.REPLACE, BlockEdit.Result.FAIL_NOT_BREAKABLE)
	var old_id := _voxel_world.get_block_id_at(position)
	if old_id == BlockId.Type.AIR or not action.can_till(_voxel_world.block_catalog.get_definition(old_id)):
		return BlockEdit.fail(position, BlockEdit.Operation.REPLACE, BlockEdit.Result.FAIL_NOT_BREAKABLE)
	var prepared := _voxel_world.prepare_replace_block(position, old_id, action.result_block.id)
	if (
		prepared == null
		or _voxel_world.is_edit_protected(position)
		or not _inventory.is_selected_item_source_current(source)
		or not _voxel_world.can_commit_prepared_change(prepared)
		or not _voxel_world._commit_prepared_change(prepared)
	):
		return BlockEdit.fail(position, BlockEdit.Operation.REPLACE, BlockEdit.Result.FAIL_BLOCK_CHANGED)
	return prepared.get_edits()[0]

func _get_action(source: SelectedItemSource) -> TillingActionDefinition:
	if source.get_item_id().is_empty() or not _inventory.item_catalog.has_definition(source.get_item_id()):
		return null
	return _inventory.item_catalog.get_definition(source.get_item_id()).primary_action as TillingActionDefinition
