extends ChestTransferCoordinator
class_name DungeonChestCoordinator

signal transfer_rejected(message: String)

const INVENTORY_FULL_MESSAGE: String = "Inventory full — drop items first"

var repeatable_reward_taken: bool:
	get:
		return _repeatable_reward_taken

var _storage: ChestStorage
var _inventory_model: InventoryModel
var _inventory_loadout: InventoryLoadoutCoordinator
var _container_definition: ContainerBlockDefinition
var _active_position: Variant = null
var _transaction_active: bool = false
var _one_time_chest_position: Variant = null
var _one_time_reward_id: StringName
var _pending_one_time_stacks: Array[InventoryStack] = []
var _escrow_revision: int = 0
var _repeatable_reward_taken: bool = false

func setup(
	placements: Array[LevelChestPlacement],
	p_repeat_loot_seed: int,
	p_one_time_reward: LevelOneTimeChestRewardDefinition,
	p_one_time_reward_claimed: bool,
	p_one_time_loot_seed: int,
	p_inventory_model: InventoryModel,
	p_inventory_loadout: InventoryLoadoutCoordinator,
	p_container_definition: ContainerBlockDefinition,
) -> bool:
	assert(p_inventory_model != null)
	assert(p_inventory_loadout != null and p_inventory_loadout.inventory_model == p_inventory_model)
	assert(p_container_definition != null)
	if _storage != null or not p_container_definition.validate("dungeon chest container"):
		return false
	var live_factory := p_inventory_model.equipment_instance_factory
	var expected_next_instance_id := live_factory.get_next_instance_id()
	var pending_factory := live_factory.copy()
	var initialization := _prepare_storage(
		placements,
		p_repeat_loot_seed,
		p_one_time_reward,
		p_one_time_reward_claimed,
		p_one_time_loot_seed,
		p_inventory_model.item_catalog,
		pending_factory,
		p_container_definition.get_slot_count(),
	)
	var pending_storage := initialization.get("storage") as ChestStorage
	if pending_storage == null:
		return false
	if (
		not pending_storage._can_bind_runtime()
		or not pending_storage._uses_configuration(
			p_inventory_model.item_catalog,
			pending_factory,
			p_container_definition.get_slot_count(),
		)
		or not live_factory.can_advance_next_instance_id(
			expected_next_instance_id,
			pending_factory.get_next_instance_id(),
		)
	):
		return false
	if not live_factory.try_advance_next_instance_id(
		expected_next_instance_id,
		pending_factory.get_next_instance_id(),
	):
		return false
	var replaced_factory := pending_storage._replace_equipment_instance_factory(
		pending_factory,
		live_factory,
	)
	assert(replaced_factory)
	if not replaced_factory:
		return false
	var bound := pending_storage._bind_runtime()
	assert(bound)
	if not bound:
		return false
	_storage = pending_storage
	_inventory_model = p_inventory_model
	_inventory_loadout = p_inventory_loadout
	_container_definition = p_container_definition
	_one_time_chest_position = initialization.get("one_time_chest_position", null)
	_one_time_reward_id = initialization.get("one_time_reward_id", &"")
	return true

func can_open(position: Vector3i) -> bool:
	return not _transaction_active and _storage != null and _storage.has_chest(position)

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
		if destination_scope == PLAYER_SCOPE and _is_valid_index(destination_scope, destination_index):
			_notify_full_inventory(source_scope, source_index, drag_count)
		return false
	if prepared.has("loadout_only"):
		_transaction_active = true
		var committed := _inventory_loadout.commit_prepared_change(
			prepared["loadout_only"] as PreparedInventoryLoadoutChange,
		)
		_transaction_active = false
		return committed
	if prepared.has("escrow"):
		return _commit_escrow_take(prepared)
	return _commit_take(prepared)

func quick_transfer(source_scope: StringName, source_index: int) -> bool:
	var prepared := _prepare_quick_take(source_scope, source_index)
	if prepared.is_empty():
		_notify_full_inventory(source_scope, source_index)
		return false
	if prepared.has("escrow"):
		return _commit_escrow_take(prepared)
	return _commit_take(prepared)

func can_quick_transfer(source_scope: StringName, source_index: int) -> bool:
	return not _prepare_quick_take(source_scope, source_index, true).is_empty()

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
	if source_scope != CHEST_SCOPE or destination_scope != PLAYER_SCOPE:
		return {}
	if _is_one_time_chest(_active_position):
		return _prepare_escrow_take(source_index, drag_count)
	var source := _storage.get_slot(_active_position, source_index)
	var destination := _inventory_model.get_slot(destination_index)
	var projection := _project_take(source, destination, drag_count)
	if projection.is_empty():
		return {}
	var storage_change := _storage._prepare_replace_stack_at(
		_active_position,
		source_index,
		source,
		projection["source"] as InventoryStack,
	)
	if storage_change == null:
		return {}
	var inventory_change := _inventory_model.prepare_replace_stack_at(
		destination_index,
		destination,
		projection["destination"] as InventoryStack,
	)
	var loadout_change := _inventory_loadout.prepare_inventory_change(inventory_change)
	if loadout_change == null:
		return {}
	return {"storage": storage_change, "loadout": loadout_change}

func _prepare_quick_take(
	source_scope: StringName,
	source_index: int,
	allow_during_transaction: bool = false,
) -> Dictionary:
	if (
		_transaction_active and not allow_during_transaction
		or not is_open()
		or source_scope != CHEST_SCOPE
		or not _is_valid_index(source_scope, source_index)
	):
		return {}
	if _is_one_time_chest(_active_position):
		return _prepare_escrow_take(source_index)
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

func _commit_take(prepared: Dictionary) -> bool:
	var storage_change := prepared.get("storage") as PreparedChestStorageChange
	var loadout_change := prepared.get("loadout") as PreparedInventoryLoadoutChange
	if (
		_transaction_active
		or storage_change == null
		or _is_one_time_chest(storage_change._get_position())
		or not _storage.can_commit_prepared_change(storage_change)
		or not _inventory_loadout.can_commit_prepared_change(loadout_change)
	):
		return false
	var position := storage_change._get_position()
	_transaction_active = true
	var inventory_committed := _inventory_loadout._commit_prepared_change(loadout_change)
	assert(inventory_committed)
	_storage._commit_prepared_change(storage_change)
	_repeatable_reward_taken = true
	var inventory_notified := _inventory_loadout._notify_prepared_change(loadout_change)
	assert(inventory_notified)
	contents_changed.emit(position)
	_transaction_active = false
	return true

func _prepare_escrow_take(source_index: int, count: int = -1) -> Dictionary:
	if not _is_one_time_chest(_active_position):
		return {}
	var storage_change := _storage.prepare_remove_stack(_active_position, source_index, count)
	if storage_change == null:
		return {}
	var candidate := storage_change.get_result_stack()
	var projected_stacks := _copy_stacks(_pending_one_time_stacks)
	projected_stacks.append(candidate)
	if _inventory_model.prepare_add_stacks_exact(projected_stacks) == null:
		return {}
	return {"storage": storage_change, "escrow": candidate}

func _commit_escrow_take(prepared: Dictionary) -> bool:
	var storage_change := prepared.get("storage") as PreparedChestStorageChange
	var candidate := prepared.get("escrow") as InventoryStack
	if (
		_transaction_active
		or storage_change == null
		or candidate == null
		or not _is_one_time_chest(storage_change._get_position())
		or not _storage.can_commit_prepared_change(storage_change)
	):
		return false
	var position := storage_change._get_position()
	_transaction_active = true
	_storage._commit_prepared_change(storage_change)
	_pending_one_time_stacks.append(candidate.copy())
	_escrow_revision += 1
	contents_changed.emit(position)
	_transaction_active = false
	return true

func _project_take(
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
	elif (
		destination.item_id == source.item_id
		and not source.has_instance_data()
		and not destination.has_instance_data()
	):
		var max_stack := _inventory_model.item_catalog.get_definition(source.item_id).max_stack
		var moved := mini(drag_count, max_stack - destination.count)
		if moved < 1:
			return {}
		destination_replacement = destination.copy()
		destination_replacement.count += moved
		source_replacement.count -= moved
	else:
		return {}
	if source_replacement.count == 0:
		source_replacement = null
	return {"source": source_replacement, "destination": destination_replacement}

func _changes_backpack_only(change: PreparedInventoryChange) -> bool:
	for index in range(_inventory_model.get_size()):
		if index >= InventoryModel.HOTBAR_SIZE and index < mini(_inventory_model.get_size(), InventoryModel.FILLABLE_SIZE):
			continue
		if not _stacks_match(_inventory_model.get_slot(index), change.get_slot(index)):
			return false
	return true

func _notify_full_inventory(source_scope: StringName, source_index: int, count: int = -1) -> void:
	if source_scope != CHEST_SCOPE or not _is_valid_index(source_scope, source_index):
		return
	var stack := _storage.get_slot(_active_position, source_index)
	if stack == null:
		return
	var requested_count := stack.count if count == -1 else count
	if requested_count < 1 or requested_count > stack.count or stack.has_instance_data() and requested_count != stack.count:
		return
	var requested := InventoryStack.new(stack.item_id, requested_count, stack.equipment_instance)
	var requested_stacks: Array[InventoryStack] = [requested]
	if _is_one_time_chest(_active_position):
		requested_stacks = _copy_stacks(_pending_one_time_stacks)
		requested_stacks.append(requested)
	if _inventory_model.prepare_add_stacks_exact(requested_stacks) == null:
		transfer_rejected.emit(INVENTORY_FULL_MESSAGE)

func prepare_one_time_claim() -> PreparedDungeonChestClaim:
	if (
		_transaction_active
		or _one_time_chest_position == null
		or _one_time_reward_id.is_empty()
		or _pending_one_time_stacks.is_empty()
		or not _storage.is_chest_empty(_one_time_chest_position)
	):
		return null
	return PreparedDungeonChestClaim.new(
		self,
		_escrow_revision,
		_one_time_reward_id,
		_pending_one_time_stacks,
	)

func can_commit_prepared_claim(prepared: PreparedDungeonChestClaim) -> bool:
	return (
		prepared != null
		and not _transaction_active
		and prepared._is_for(self)
		and prepared._is_prepared()
		and prepared._get_expected_revision() == _escrow_revision
		and prepared.get_reward_id() == _one_time_reward_id
		and _one_time_chest_position != null
		and not _pending_one_time_stacks.is_empty()
		and _storage.is_chest_empty(_one_time_chest_position)
	)

func commit_prepared_claim(prepared: PreparedDungeonChestClaim) -> bool:
	if not can_commit_prepared_claim(prepared):
		return false
	var marked := prepared._mark_committed(self)
	assert(marked)
	if not marked:
		return false
	_pending_one_time_stacks.clear()
	_escrow_revision += 1
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

func _prepare_storage(
	placements: Array[LevelChestPlacement],
	repeat_loot_seed: int,
	one_time_reward: LevelOneTimeChestRewardDefinition,
	one_time_reward_claimed: bool,
	one_time_loot_seed: int,
	item_catalog: ItemCatalog,
	pending_factory: EquipmentInstanceFactory,
	slot_count: int,
) -> Dictionary:
	var room_ids: Dictionary = {}
	var cells: Dictionary = {}
	var sorted_placements: Array[LevelChestPlacement] = placements.duplicate()
	sorted_placements.sort_custom(_placement_less)
	for placement in sorted_placements:
		if (
			placement == null
			or placement.room_id < 0
			or room_ids.has(placement.room_id)
			or cells.has(placement.cell)
			or not LootCatalogValidator.validate_bundle(placement.loot_bundle, item_catalog)
		):
			return {}
		room_ids[placement.room_id] = true
		cells[placement.cell] = true
	if one_time_reward != null and (
		not one_time_reward.validate("dungeon one-time chest reward")
		or not LootCatalogValidator.validate_bundle(one_time_reward.loot_bundle, item_catalog)
	):
		return {}
	var one_time_placement: LevelChestPlacement
	if one_time_reward != null and not one_time_reward_claimed:
		if sorted_placements.is_empty():
			return {}
		var one_time_index := LootKeyedRandom.integer_inclusive(
			one_time_loot_seed,
			one_time_reward.reward_id,
			[&"one_time_chest"],
			0,
			sorted_placements.size() - 1,
		)
		one_time_placement = sorted_placements[one_time_index]
	var pending_storage := ChestStorage.new(item_catalog, pending_factory, slot_count)
	for placement in sorted_placements:
		if not pending_storage.create_chest(placement.cell):
			return {}
		var bundle := placement.loot_bundle
		var resolved_seed := _placement_loot_seed(repeat_loot_seed, placement)
		if placement == one_time_placement:
			bundle = one_time_reward.loot_bundle
			resolved_seed = one_time_loot_seed
		var resolution := LootResolver.prepare_bundle(
			bundle,
			resolved_seed,
			pending_factory,
		)
		if resolution == null or not LootResolver._commit(resolution, pending_factory):
			return {}
		for stack in resolution.get_drops():
			if not pending_storage.add_stack(placement.cell, stack):
				return {}
	return {
		"storage": pending_storage,
		"one_time_chest_position": null if one_time_placement == null else one_time_placement.cell,
		"one_time_reward_id": &"" if one_time_placement == null else one_time_reward.reward_id,
	}

func _placement_loot_seed(loot_seed: int, placement: LevelChestPlacement) -> int:
	return LootKeyedRandom.u53(
		loot_seed,
		placement.loot_bundle.id,
		[
			&"dungeon_chest",
			StringName(str(placement.room_id)),
			StringName(str(placement.cell.x)),
			StringName(str(placement.cell.y)),
			StringName(str(placement.cell.z)),
		],
	)

static func _placement_less(left: LevelChestPlacement, right: LevelChestPlacement) -> bool:
	if left == null:
		return right != null
	if right == null:
		return false
	if left.room_id != right.room_id:
		return left.room_id < right.room_id
	if left.cell.x != right.cell.x:
		return left.cell.x < right.cell.x
	if left.cell.y != right.cell.y:
		return left.cell.y < right.cell.y
	return left.cell.z < right.cell.z

static func _stacks_match(first: InventoryStack, second: InventoryStack) -> bool:
	if first == null or second == null:
		return first == null and second == null
	return first.to_dict() == second.to_dict()

func _is_one_time_chest(position: Variant) -> bool:
	return _one_time_chest_position != null and position == _one_time_chest_position

static func _copy_stacks(source: Array[InventoryStack]) -> Array[InventoryStack]:
	var copied: Array[InventoryStack] = []
	for stack in source:
		copied.append(stack.copy())
	return copied
