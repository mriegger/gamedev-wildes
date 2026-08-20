extends InventoryTransferCoordinator
class_name ChestCoordinator

signal opened(position: Vector3i, definition: ContainerBlockDefinition)
signal closed
signal contents_changed(position: Vector3i)

const CHEST_SCOPE: StringName = &"chest"

var _storage: ChestStorage
var _inventory_model: InventoryModel
var _inventory_loadout: InventoryLoadoutCoordinator
var _voxel_world: VoxelWorld
var _chest_block: BlockDefinition
var _container_definition: ContainerBlockDefinition
var _active_position: Variant = null
var _transaction_active: bool = false

func setup(
	p_storage: ChestStorage,
	p_inventory_model: InventoryModel,
	p_inventory_loadout: InventoryLoadoutCoordinator,
	p_voxel_world: VoxelWorld,
	p_chest_block: BlockDefinition,
) -> bool:
	assert(p_storage != null)
	assert(p_inventory_model != null)
	assert(p_inventory_loadout != null and p_inventory_loadout.inventory_model == p_inventory_model)
	assert(p_voxel_world != null)
	assert(p_chest_block != null and p_chest_block.container != null)
	var canonical_block := p_voxel_world.block_catalog.get_definition(int(p_chest_block.id))
	if (
		_storage != null
		or int(p_chest_block.id) != BlockId.Type.CHEST
		or canonical_block != p_chest_block
		or not p_storage._can_bind_runtime()
		or not p_storage._uses_configuration(
			p_inventory_model.item_catalog,
			p_inventory_model.equipment_instance_factory,
			p_chest_block.container.get_slot_count(),
		)
	):
		return false
	var storage_bound := p_storage._bind_runtime()
	assert(storage_bound)
	_storage = p_storage
	_inventory_model = p_inventory_model
	_inventory_loadout = p_inventory_loadout
	_voxel_world = p_voxel_world
	_chest_block = p_chest_block
	_container_definition = p_chest_block.container
	return true

func can_open(position: Vector3i) -> bool:
	return (
		not _transaction_active
		and _storage != null
		and _is_chest_block(position)
		and _storage.has_chest(position)
	)

func try_open(position: Vector3i, definition: ContainerBlockDefinition) -> bool:
	if definition != _container_definition or not can_open(position):
		return false
	_active_position = position
	opened.emit(position, definition)
	return true

func close() -> void:
	if _active_position == null:
		return
	_active_position = null
	closed.emit()

func is_open() -> bool:
	return _active_position != null

func get_active_position() -> Variant:
	return _active_position

func can_break(position: Vector3i) -> bool:
	if not _is_chest_block(position):
		return true
	return _storage.has_chest(position) and _storage.is_chest_empty(position)

func handle_block_edit(edit: BlockEdit) -> void:
	if edit == null or not edit.is_success() or _storage == null:
		return
	var chest_id := int(_chest_block.id)
	if edit.old_id != chest_id and edit.new_id == chest_id:
		var created := _storage._create_chest(edit.pos)
		assert(created)
		contents_changed.emit(edit.pos)
	elif edit.old_id == chest_id and edit.new_id != chest_id:
		var removed := _storage._remove_empty_chest(edit.pos)
		assert(removed)
		if _active_position != null and _active_position == edit.pos:
			_active_position = null
			closed.emit()
		contents_changed.emit(edit.pos)

func get_inventory_stack(scope: StringName, index: int) -> InventoryStack:
	if not _is_valid_index(scope, index):
		return null
	if scope == PLAYER_SCOPE:
		return _inventory_model.get_slot(index)
	return _storage.get_slot(_active_position, index)

func get_socketed_rune_ids(scope: StringName, index: int) -> Array[StringName]:
	var stack := get_inventory_stack(scope, index)
	var rune_ids: Array[StringName] = []
	if stack != null and stack.equipment_instance != null:
		rune_ids.assign(stack.equipment_instance.socketed_rune_ids)
	return rune_ids

func can_handle_drop(
	source_scope: StringName,
	source_index: int,
	destination_scope: StringName,
	destination_index: int,
	drag_count: int,
) -> bool:
	return not _prepare_drop(
		source_scope,
		source_index,
		destination_scope,
		destination_index,
		drag_count,
	).is_empty()

func handle_drop(
	source_scope: StringName,
	source_index: int,
	destination_scope: StringName,
	destination_index: int,
	drag_count: int,
) -> bool:
	var prepared := _prepare_drop(
		source_scope,
		source_index,
		destination_scope,
		destination_index,
		drag_count,
	)
	if prepared.is_empty():
		return false
	if prepared.has("loadout_only"):
		_transaction_active = true
		var committed := _inventory_loadout.commit_prepared_change(
			prepared["loadout_only"] as PreparedInventoryLoadoutChange,
		)
		_transaction_active = false
		return committed
	if prepared.has("storage_only"):
		var storage_only := prepared["storage_only"] as PreparedChestStorageChange
		if not _storage.can_commit_prepared_change(storage_only):
			return false
		_transaction_active = true
		_storage._commit_prepared_change(storage_only)
		contents_changed.emit(_active_position)
		_transaction_active = false
		return true
	return _commit_cross_scope(prepared)

func quick_transfer(source_scope: StringName, source_index: int) -> bool:
	var prepared := _prepare_quick_transfer(source_scope, source_index)
	if prepared.is_empty():
		return false
	return _commit_cross_scope(prepared)

func can_quick_transfer(source_scope: StringName, source_index: int) -> bool:
	return not _prepare_quick_transfer(source_scope, source_index, true).is_empty()

func move_all_to_backpack() -> bool:
	if not is_open() or _transaction_active:
		return false
	var changed := false
	for slot_index in range(_storage.get_slot_count()):
		if quick_transfer(CHEST_SCOPE, slot_index):
			changed = true
	return changed

func can_move_all_to_backpack() -> bool:
	if not is_open():
		return false
	for slot_index in range(_storage.get_slot_count()):
		if can_quick_transfer(CHEST_SCOPE, slot_index):
			return true
	return false

func _prepare_drop(
	source_scope: StringName,
	source_index: int,
	destination_scope: StringName,
	destination_index: int,
	drag_count: int,
) -> Dictionary:
	if (
		_transaction_active
		or not is_open()
		or not _is_valid_index(source_scope, source_index)
		or not _is_valid_index(destination_scope, destination_index)
		or source_scope == destination_scope and source_index == destination_index
	):
		return {}
	if source_scope == PLAYER_SCOPE and destination_scope == PLAYER_SCOPE:
		var inventory_change := _inventory_model.prepare_handle_drop(
			source_index,
			destination_index,
			drag_count,
		)
		var loadout_change := _inventory_loadout.prepare_inventory_change(inventory_change)
		return {} if loadout_change == null else {"loadout_only": loadout_change}
	if source_scope == CHEST_SCOPE and destination_scope == CHEST_SCOPE:
		var storage_change := _storage._prepare_handle_drop(
			_active_position,
			source_index,
			destination_index,
			drag_count,
		)
		return {} if storage_change == null else {"storage_only": storage_change}
	if not (
		source_scope == PLAYER_SCOPE and destination_scope == CHEST_SCOPE
		or source_scope == CHEST_SCOPE and destination_scope == PLAYER_SCOPE
	):
		return {}
	var source := get_inventory_stack(source_scope, source_index)
	var destination := get_inventory_stack(destination_scope, destination_index)
	var projection := _project_drop(source, destination, drag_count)
	if projection.is_empty():
		return {}
	var inventory_index := source_index if source_scope == PLAYER_SCOPE else destination_index
	var inventory_expected := source if source_scope == PLAYER_SCOPE else destination
	var inventory_replacement := (
		projection["source"] as InventoryStack
		if source_scope == PLAYER_SCOPE
		else projection["destination"] as InventoryStack
	)
	var chest_index := source_index if source_scope == CHEST_SCOPE else destination_index
	var chest_expected := source if source_scope == CHEST_SCOPE else destination
	var chest_replacement := (
		projection["source"] as InventoryStack
		if source_scope == CHEST_SCOPE
		else projection["destination"] as InventoryStack
	)
	var inventory_change := _inventory_model.prepare_replace_stack_at(
		inventory_index,
		inventory_expected,
		inventory_replacement,
	)
	var loadout_change := _inventory_loadout.prepare_inventory_change(inventory_change)
	if loadout_change == null:
		return {}
	var storage_change := _storage._prepare_replace_stack_at(
		_active_position,
		chest_index,
		chest_expected,
		chest_replacement,
	)
	if storage_change == null:
		return {}
	return {"storage": storage_change, "loadout": loadout_change}

func _prepare_quick_transfer(
	source_scope: StringName,
	source_index: int,
	allow_during_transaction: bool = false,
) -> Dictionary:
	if (
		_transaction_active and not allow_during_transaction
		or not is_open()
		or not _is_quick_transfer_source(source_scope, source_index)
	):
		return {}
	if source_scope == PLAYER_SCOPE:
		var inventory_change := _inventory_model.prepare_remove_stack(source_index)
		var loadout_change := _inventory_loadout.prepare_inventory_change(inventory_change)
		if loadout_change == null:
			return {}
		var storage_change := _storage.prepare_add_stack(
			_active_position,
			inventory_change.get_result_stack(),
		)
		if storage_change == null:
			return {}
		return {"storage": storage_change, "loadout": loadout_change}
	var storage_change := _storage.prepare_remove_stack(_active_position, source_index)
	if storage_change == null:
		return {}
	var inventory_change := _inventory_model.prepare_add_stack(storage_change.get_result_stack())
	if inventory_change == null or not _changes_backpack_only(inventory_change):
		return {}
	var loadout_change := _inventory_loadout.prepare_inventory_change(inventory_change)
	if loadout_change == null:
		return {}
	return {"storage": storage_change, "loadout": loadout_change}

func _commit_cross_scope(prepared: Dictionary) -> bool:
	var storage_change := prepared.get("storage") as PreparedChestStorageChange
	var loadout_change := prepared.get("loadout") as PreparedInventoryLoadoutChange
	if (
		_transaction_active
		or not _storage.can_commit_prepared_change(storage_change)
		or not _inventory_loadout.can_commit_prepared_change(loadout_change)
	):
		return false
	var position := storage_change._get_position()
	_transaction_active = true
	var inventory_committed := _inventory_loadout._commit_prepared_change(loadout_change)
	assert(inventory_committed)
	_storage._commit_prepared_change(storage_change)
	var inventory_notified := _inventory_loadout._notify_prepared_change(loadout_change)
	assert(inventory_notified)
	contents_changed.emit(position)
	_transaction_active = false
	return true

func _project_drop(
	source: InventoryStack,
	destination: InventoryStack,
	drag_count: int,
) -> Dictionary:
	if source == null or drag_count < 1 or drag_count > source.count:
		return {}
	if source.has_instance_data() and drag_count != source.count:
		return {}
	var source_replacement := source.copy()
	var destination_replacement: InventoryStack
	if destination == null:
		destination_replacement = InventoryStack.new(
			source.item_id,
			drag_count,
			source.equipment_instance,
		)
		source_replacement.count -= drag_count
		if source_replacement.count == 0:
			source_replacement = null
	elif destination.item_id == source.item_id and not source.has_instance_data() and not destination.has_instance_data():
		var max_stack := _inventory_model.item_catalog.get_definition(source.item_id).max_stack
		var moved := mini(drag_count, max_stack - destination.count)
		if moved < 1:
			return {}
		destination_replacement = destination.copy()
		destination_replacement.count += moved
		source_replacement.count -= moved
		if source_replacement.count == 0:
			source_replacement = null
	else:
		if drag_count != source.count:
			return {}
		source_replacement = destination
		destination_replacement = source
	return {"source": source_replacement, "destination": destination_replacement}

func _changes_backpack_only(change: PreparedInventoryChange) -> bool:
	for index in range(_inventory_model.get_size()):
		if index >= InventoryModel.HOTBAR_SIZE and index < mini(_inventory_model.get_size(), InventoryModel.FILLABLE_SIZE):
			continue
		if not _stacks_match(_inventory_model.get_slot(index), change.get_slot(index)):
			return false
	return true

func _is_valid_index(scope: StringName, index: int) -> bool:
	if scope == PLAYER_SCOPE:
		return (
			_inventory_model != null
			and index >= 0
			and index < mini(_inventory_model.get_size(), InventoryModel.FILLABLE_SIZE)
		)
	if scope == CHEST_SCOPE:
		return is_open() and index >= 0 and index < _storage.get_slot_count()
	return false

func _is_quick_transfer_source(scope: StringName, index: int) -> bool:
	if not _is_valid_index(scope, index):
		return false
	if scope == PLAYER_SCOPE:
		return index >= InventoryModel.HOTBAR_SIZE
	return scope == CHEST_SCOPE

func _is_chest_block(position: Vector3i) -> bool:
	return (
		_voxel_world != null
		and _chest_block != null
		and _voxel_world.get_block_id_at(position) == int(_chest_block.id)
	)

static func _stacks_match(first: InventoryStack, second: InventoryStack) -> bool:
	if first == null or second == null:
		return first == null and second == null
	return first.to_dict() == second.to_dict()
