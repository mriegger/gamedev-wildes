extends Node3D
class_name OverworldLootCoordinator

const COLLECTION_RADIUS: float = 1.5
const STREAMING_CHECKS_PER_TICK: int = 4
const LIFETIME_STEP_SECONDS: float = 1.0
const MAX_PENDING_DEFEATS: int = WorldLootState.MAXIMUM_ENTRY_COUNT

var _entity_catalog: EntityCatalog
var _item_catalog: ItemCatalog
var _equipment_instance_factory: EquipmentInstanceFactory
var _world_loot_state: WorldLootState
var _inventory_model: InventoryModel
var _inventory_loadout: InventoryLoadoutCoordinator
var _player: PlayerMotor
var _entity_runtime: EntityRuntime
var _position_ready: Callable
var _drop_scene: PackedScene
var _views: Dictionary = {}
var _streaming_entry_ids: Array[int] = []
var _streaming_cursor: int = 0
var _lifetime_accumulator: float = 0.0
var _suspended: bool = false
var _transaction_in_progress: bool = false
var _pending_defeats: Array[EntityDefeat] = []
var _draining_pending_defeats: bool = false

func setup(
	p_entity_catalog: EntityCatalog,
	p_item_catalog: ItemCatalog,
	p_equipment_instance_factory: EquipmentInstanceFactory,
	p_world_loot_state: WorldLootState,
	p_inventory_model: InventoryModel,
	p_inventory_loadout: InventoryLoadoutCoordinator,
	p_player: PlayerMotor,
	p_entity_runtime: EntityRuntime,
	p_position_ready: Callable,
	p_drop_scene: PackedScene,
) -> void:
	assert(p_entity_catalog != null)
	assert(p_item_catalog != null)
	assert(p_equipment_instance_factory != null and p_equipment_instance_factory.item_catalog == p_item_catalog)
	assert(p_world_loot_state != null and p_world_loot_state.item_catalog == p_item_catalog)
	assert(p_world_loot_state.equipment_instance_factory == p_equipment_instance_factory)
	assert(p_inventory_model != null and p_inventory_model.item_catalog == p_item_catalog)
	assert(p_inventory_loadout != null and p_inventory_loadout.inventory_model == p_inventory_model)
	assert(p_inventory_model.equipment_instance_factory == p_equipment_instance_factory)
	assert(p_player != null)
	assert(p_entity_runtime != null)
	assert(p_position_ready.is_valid())
	assert(p_drop_scene != null and p_drop_scene.can_instantiate())
	shutdown()
	_entity_catalog = p_entity_catalog
	_item_catalog = p_item_catalog
	_equipment_instance_factory = p_equipment_instance_factory
	_world_loot_state = p_world_loot_state
	_inventory_model = p_inventory_model
	_inventory_loadout = p_inventory_loadout
	_player = p_player
	_entity_runtime = p_entity_runtime
	_position_ready = p_position_ready
	_drop_scene = p_drop_scene
	_entity_runtime.entity_defeated.connect(_on_entity_defeated)
	_lifetime_accumulator = 0.0
	_suspended = false
	visible = true
	_sync_all_views()
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if _entity_runtime == null or _suspended:
		return
	tick(delta)

func tick(delta: float = 0.0) -> void:
	if _transaction_in_progress:
		return
	assert(is_finite(delta) and delta >= 0.0)
	assert(_entity_runtime != null)
	if _suspended:
		return
	_advance_lifetimes(delta)
	if _entity_runtime == null or _suspended:
		return
	_advance_streaming_views()
	_collect_nearby_drops()

func _on_entity_defeated(defeat: EntityDefeat) -> void:
	assert(defeat != null)
	assert(_entity_catalog.has_definition(defeat.definition_id))
	if _suspended:
		return
	if _transaction_in_progress:
		assert(_pending_defeats.size() < MAX_PENDING_DEFEATS)
		if _pending_defeats.size() < MAX_PENDING_DEFEATS:
			_pending_defeats.append(defeat)
		return
	_resolve_entity_defeat(defeat)

func _resolve_entity_defeat(defeat: EntityDefeat) -> void:
	var definition := _entity_catalog.get_definition(defeat.definition_id)
	if definition.loot_pool == null:
		return
	var resolution := LootResolver.prepare(
		definition.loot_pool,
		defeat.loot_seed,
		_equipment_instance_factory,
	)
	if resolution == null:
		return
	var drops := resolution.get_drops()
	if drops.is_empty():
		return
	_transaction_in_progress = true
	if not WorldLootDropTransaction.try_commit(
		resolution,
		_world_loot_state,
		defeat.world_position,
	):
		_finish_transaction()
		return
	_sync_all_views()
	_finish_transaction()

func _collect_nearby_drops() -> void:
	if _player.is_defeated():
		return
	var state := _world_loot_state
	for entry in state.query_nearby(_player.global_position, COLLECTION_RADIUS):
		if _world_loot_state != state or _suspended:
			break
		if not bool(_position_ready.call(entry.world_position)):
			continue
		_collect_entry(entry.entry_id)

func _collect_entry(entry_id: int) -> void:
	var state := _world_loot_state
	var inventory := _inventory_model
	var loadout := _inventory_loadout
	var entry := state.get_entry(entry_id)
	if entry == null:
		return
	var inventory_change := inventory.prepare_add_stack_up_to(entry.stack)
	if inventory_change == null:
		return
	var accepted := inventory_change.get_result_stack()
	assert(accepted != null and accepted.count >= 1 and accepted.count <= entry.stack.count)
	var loadout_change := loadout.prepare_inventory_change(inventory_change)
	var world_change := state.prepare_take(entry_id, accepted.count)
	if (
		loadout_change == null
		or world_change == null
		or not state.can_commit_prepared_change(world_change)
		or not loadout.can_commit_prepared_change(loadout_change)
	):
		return
	_transaction_in_progress = true
	state._commit_prepared_change(world_change)
	var inventory_committed := loadout._commit_prepared_change(loadout_change)
	assert(inventory_committed)
	if not inventory_committed:
		_finish_transaction()
		return
	_sync_all_views()
	var inventory_notified := loadout._notify_prepared_change(loadout_change)
	assert(inventory_notified)
	_finish_transaction()

func _advance_lifetimes(delta: float) -> void:
	_lifetime_accumulator += delta
	var elapsed_steps := floori(_lifetime_accumulator / LIFETIME_STEP_SECONDS)
	if elapsed_steps < 1:
		return
	_lifetime_accumulator -= float(elapsed_steps) * LIFETIME_STEP_SECONDS
	var prepared := _world_loot_state.prepare_advance_time(
		float(elapsed_steps) * LIFETIME_STEP_SECONDS,
	)
	if prepared == null:
		return
	var expired := prepared._changes_entries()
	_transaction_in_progress = true
	if not _world_loot_state.commit_prepared_change(prepared):
		_finish_transaction()
		return
	if expired:
		_sync_all_views()
	_finish_transaction()

func _finish_transaction() -> void:
	_transaction_in_progress = false
	_drain_pending_defeats()

func _drain_pending_defeats() -> void:
	if _draining_pending_defeats or _transaction_in_progress or _entity_runtime == null or _suspended:
		return
	_draining_pending_defeats = true
	var remaining_budget := MAX_PENDING_DEFEATS
	while not _pending_defeats.is_empty() and remaining_budget > 0 and _entity_runtime != null and not _suspended:
		var defeat := _pending_defeats.pop_front() as EntityDefeat
		_resolve_entity_defeat(defeat)
		remaining_budget -= 1
	_draining_pending_defeats = false
	if not _pending_defeats.is_empty() and _entity_runtime != null and not _suspended:
		call_deferred("_drain_pending_defeats")

func _advance_streaming_views() -> void:
	if _streaming_entry_ids.is_empty():
		_streaming_cursor = 0
		_clear_views()
		return
	var checks := mini(STREAMING_CHECKS_PER_TICK, _streaming_entry_ids.size())
	for _check in range(checks):
		_streaming_cursor %= _streaming_entry_ids.size()
		var entry_id := _streaming_entry_ids[_streaming_cursor]
		var entry := _world_loot_state.get_entry(entry_id)
		if entry == null:
			_remove_view(entry_id)
		else:
			_sync_view(entry)
		_streaming_cursor = (_streaming_cursor + 1) % _streaming_entry_ids.size()

func _sync_all_views() -> void:
	if _world_loot_state == null or _suspended:
		_clear_views()
		return
	var retained: Dictionary = {}
	var entries := _world_loot_state.get_entries()
	_streaming_entry_ids.clear()
	for entry in entries:
		retained[entry.entry_id] = true
		_streaming_entry_ids.append(entry.entry_id)
		_sync_view(entry)
	for entry_id in _views.keys():
		if not retained.has(entry_id):
			_remove_view(int(entry_id))
	if entries.is_empty():
		_streaming_cursor = 0

func _sync_view(entry: WorldLootEntry) -> void:
	if not bool(_position_ready.call(entry.world_position)):
		_remove_view(entry.entry_id)
		return
	var view := _views.get(entry.entry_id) as LootDropView
	if view == null:
		view = _drop_scene.instantiate() as LootDropView
		assert(view != null)
		add_child(view)
		view.setup(_item_catalog.get_definition(entry.stack.item_id).icon)
		_views[entry.entry_id] = view
	view.global_position = entry.world_position

func _remove_view(entry_id: int) -> void:
	var view := _views.get(entry_id) as LootDropView
	if view == null:
		return
	_views.erase(entry_id)
	if is_instance_valid(view):
		if view.get_parent() == self:
			remove_child(view)
		view.queue_free()

func _clear_views() -> void:
	for entry_id in _views.keys():
		_remove_view(int(entry_id))
	_views.clear()

func suspend() -> void:
	if _suspended:
		return
	_suspended = true
	_clear_views()
	visible = false
	set_physics_process(false)

func resume() -> void:
	if not _suspended:
		return
	assert(_entity_runtime != null)
	visible = true
	_suspended = false
	_sync_all_views()
	set_physics_process(true)
	_drain_pending_defeats()

func shutdown() -> void:
	set_physics_process(false)
	if _entity_runtime != null and _entity_runtime.entity_defeated.is_connected(_on_entity_defeated):
		_entity_runtime.entity_defeated.disconnect(_on_entity_defeated)
	_clear_views()
	_entity_catalog = null
	_item_catalog = null
	_equipment_instance_factory = null
	_world_loot_state = null
	_inventory_model = null
	_inventory_loadout = null
	_player = null
	_entity_runtime = null
	_position_ready = Callable()
	_drop_scene = null
	_streaming_entry_ids.clear()
	_pending_defeats.clear()
	_draining_pending_defeats = false
	_streaming_cursor = 0
	_lifetime_accumulator = 0.0
	_suspended = false
	visible = false
