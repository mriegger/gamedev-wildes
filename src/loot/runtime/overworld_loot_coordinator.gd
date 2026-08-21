extends Node3D
class_name OverworldLootCoordinator

signal state_changed()
signal pickup_committed(item_id: StringName, count: int)

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
var _voxel_world: VoxelWorld
var _position_ready: Callable
var _drop_scene: PackedScene
var _views: Dictionary = {}
var _streaming_entry_ids: Array[int] = []
var _streaming_cursor: int = 0
var _lifetime_accumulator: float = 0.0
var _maximum_collection_radius: float = COLLECTION_RADIUS
var _suspended: bool = false
var _transaction_in_progress: bool = false
var _pending_defeats: Array[EntityDefeat] = []
var _draining_pending_defeats: bool = false
var _hovered_entry_id: int = 0

func setup(
	p_entity_catalog: EntityCatalog,
	p_item_catalog: ItemCatalog,
	p_equipment_instance_factory: EquipmentInstanceFactory,
	p_world_loot_state: WorldLootState,
	p_inventory_model: InventoryModel,
	p_inventory_loadout: InventoryLoadoutCoordinator,
	p_player: PlayerMotor,
	p_entity_runtime: EntityRuntime,
	p_voxel_world: VoxelWorld,
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
	assert(p_voxel_world != null)
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
	_voxel_world = p_voxel_world
	_position_ready = p_position_ready
	_drop_scene = p_drop_scene
	_maximum_collection_radius = COLLECTION_RADIUS
	for definition in _item_catalog.definitions:
		_maximum_collection_radius = maxf(
			_maximum_collection_radius,
			COLLECTION_RADIUS * definition.world_pickup_radius_multiplier,
		)
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
	var loot_pool := definition.resolve_loot_pool(defeat.loot_seed)
	if loot_pool == null:
		return
	var resolution := LootResolver.prepare(
		loot_pool,
		defeat.loot_seed,
		_equipment_instance_factory,
	)
	if resolution == null:
		return
	var drops := resolution.get_drops()
	if drops.is_empty():
		return
	var existing_entry_ids: Dictionary = {}
	for entry in _world_loot_state.get_entries():
		existing_entry_ids[entry.entry_id] = true
	var drop_position := _resolve_drop_position(definition, defeat.world_position)
	_transaction_in_progress = true
	if not WorldLootDropTransaction.try_commit(
		resolution,
		_world_loot_state,
		drop_position,
	):
		_finish_transaction()
		return
	_sync_all_views()
	if not drop_position.is_equal_approx(defeat.world_position):
		_begin_new_drop_falls(existing_entry_ids, defeat.world_position, drop_position)
	state_changed.emit()
	_finish_transaction()

func _resolve_drop_position(definition: EntityDefinition, world_position: Vector3) -> Vector3:
	if not definition.loot_drops_to_terrain:
		return world_position
	var terrain_y := _voxel_world.get_terrain_surface_top(floori(world_position.x), floori(world_position.z))
	if terrain_y == VoxelSpace.NO_SURFACE_Y or terrain_y >= world_position.y:
		return world_position
	return Vector3(world_position.x, terrain_y, world_position.z)

func _begin_new_drop_falls(existing_entry_ids: Dictionary, start_position: Vector3, resting_position: Vector3) -> void:
	for entry in _world_loot_state.get_entries():
		if existing_entry_ids.has(entry.entry_id) or not entry.world_position.is_equal_approx(resting_position):
			continue
		var view := _views.get(entry.entry_id) as LootDropView
		if view != null:
			view.begin_fall(start_position)

func _collect_nearby_drops() -> void:
	if _player.is_defeated():
		return
	var state := _world_loot_state
	for entry in state.query_nearby(_player.global_position, _maximum_collection_radius):
		if _world_loot_state != state or _suspended:
			break
		_try_collect_entry(entry.entry_id)

func _try_collect_entry(entry_id: int, maximum_distance: float = -1.0) -> bool:
	if _transaction_in_progress or _suspended or _player.is_defeated():
		return false
	var entry := _world_loot_state.get_entry(entry_id)
	if entry == null:
		return false
	var definition := _item_catalog.get_definition(entry.stack.item_id)
	var collection_radius := maximum_distance if maximum_distance >= 0.0 else COLLECTION_RADIUS * definition.world_pickup_radius_multiplier
	if entry.world_position.distance_squared_to(_player.global_position) > collection_radius * collection_radius:
		return false
	if not bool(_position_ready.call(entry.world_position)):
		return false
	_collect_entry(entry_id)
	return true

func handle_hovered_pickup(maximum_distance: float) -> bool:
	if not is_finite(maximum_distance) or maximum_distance < 0.0 or _hovered_entry_id < 1:
		return false
	if _world_loot_state.get_entry(_hovered_entry_id) == null:
		_hovered_entry_id = 0
		return false
	_try_collect_entry(_hovered_entry_id, maximum_distance)
	return true

func _on_view_hover_changed(hovered: bool, entry_id: int) -> void:
	if hovered:
		_hovered_entry_id = entry_id
	elif _hovered_entry_id == entry_id:
		_hovered_entry_id = 0

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
	state_changed.emit()
	var inventory_notified := loadout._notify_prepared_change(loadout_change)
	assert(inventory_notified)
	pickup_committed.emit(accepted.item_id, accepted.count)
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
		state_changed.emit()
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
		var item_definition := _item_catalog.get_definition(entry.stack.item_id)
		view.setup(item_definition)
		view.hover_changed.connect(_on_view_hover_changed.bind(entry.entry_id))
		_views[entry.entry_id] = view
	view.sync_world_position(entry.world_position)

func _remove_view(entry_id: int) -> void:
	var view := _views.get(entry_id) as LootDropView
	if view == null:
		return
	_views.erase(entry_id)
	if _hovered_entry_id == entry_id:
		_hovered_entry_id = 0
	if is_instance_valid(view):
		if view.get_parent() == self:
			remove_child(view)
		view.queue_free()

func _clear_views() -> void:
	for entry_id in _views.keys():
		_remove_view(int(entry_id))
	_views.clear()

func _uses_world_loot_state(world_loot_state: WorldLootState) -> bool:
	return _world_loot_state == world_loot_state

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
	_voxel_world = null
	_position_ready = Callable()
	_drop_scene = null
	_streaming_entry_ids.clear()
	_pending_defeats.clear()
	_draining_pending_defeats = false
	_hovered_entry_id = 0
	_streaming_cursor = 0
	_lifetime_accumulator = 0.0
	_maximum_collection_radius = COLLECTION_RADIUS
	_suspended = false
	visible = false
