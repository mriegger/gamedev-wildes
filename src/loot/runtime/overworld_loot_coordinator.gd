extends Node3D
class_name OverworldLootCoordinator

var _entity_catalog: EntityCatalog
var _item_catalog: ItemCatalog
var _equipment_instance_factory: EquipmentInstanceFactory
var _world_loot_state: WorldLootState
var _entity_runtime: EntityRuntime
var _drop_scene: PackedScene
var _views: Dictionary = {}
var _suspended: bool = false

func setup(
	p_entity_catalog: EntityCatalog,
	p_item_catalog: ItemCatalog,
	p_equipment_instance_factory: EquipmentInstanceFactory,
	p_world_loot_state: WorldLootState,
	p_entity_runtime: EntityRuntime,
	p_drop_scene: PackedScene,
) -> void:
	assert(p_entity_catalog != null)
	assert(p_item_catalog != null)
	assert(p_equipment_instance_factory != null)
	assert(p_equipment_instance_factory.item_catalog == p_item_catalog)
	assert(p_world_loot_state != null)
	assert(p_world_loot_state.item_catalog == p_item_catalog)
	assert(p_world_loot_state.equipment_instance_factory == p_equipment_instance_factory)
	assert(p_entity_runtime != null)
	assert(p_drop_scene != null and p_drop_scene.can_instantiate())
	shutdown()
	_entity_catalog = p_entity_catalog
	_item_catalog = p_item_catalog
	_equipment_instance_factory = p_equipment_instance_factory
	_world_loot_state = p_world_loot_state
	_entity_runtime = p_entity_runtime
	_drop_scene = p_drop_scene
	_entity_runtime.entity_defeated.connect(_on_entity_defeated)
	_suspended = false
	visible = true
	_sync_views()

func shutdown() -> void:
	if (
		_entity_runtime != null
		and _entity_runtime.entity_defeated.is_connected(_on_entity_defeated)
	):
		_entity_runtime.entity_defeated.disconnect(_on_entity_defeated)
	_clear_views()
	_entity_catalog = null
	_item_catalog = null
	_equipment_instance_factory = null
	_world_loot_state = null
	_entity_runtime = null
	_drop_scene = null
	_suspended = false
	visible = false

func _exit_tree() -> void:
	shutdown()

func _on_entity_defeated(defeat: EntityDefeat) -> void:
	assert(defeat != null)
	assert(_entity_catalog != null and _entity_catalog.has_definition(defeat.definition_id))
	if _suspended:
		return
	var definition := _entity_catalog.get_definition(defeat.definition_id)
	if definition.loot_pool == null:
		return
	var resolution := LootResolver.prepare(
		definition.loot_pool,
		defeat.loot_seed,
		_equipment_instance_factory,
	)
	if (
		resolution == null
		or resolution.get_drops().is_empty()
		or not WorldLootDropTransaction.try_commit(
			resolution,
			_world_loot_state,
			defeat.world_position,
		)
	):
		return
	_sync_views()

func _sync_views() -> void:
	var retained: Dictionary = {}
	for entry in _world_loot_state.get_entries():
		retained[entry.entry_id] = true
		var view := _views.get(entry.entry_id) as LootDropView
		if view == null:
			view = _drop_scene.instantiate() as LootDropView
			assert(view != null)
			add_child(view)
			view.setup(_item_catalog.get_definition(entry.stack.item_id).icon)
			_views[entry.entry_id] = view
		view.global_position = entry.world_position
	for raw_entry_id in _views.keys():
		var entry_id := int(raw_entry_id)
		if retained.has(entry_id):
			continue
		var view := _views[entry_id] as LootDropView
		_views.erase(entry_id)
		if is_instance_valid(view):
			view.free()

func _clear_views() -> void:
	for view in _views.values():
		if is_instance_valid(view):
			(view as LootDropView).free()
	_views.clear()

func suspend() -> void:
	if _suspended:
		return
	_suspended = true
	_clear_views()
	visible = false

func resume() -> void:
	if not _suspended:
		return
	assert(_entity_runtime != null)
	visible = true
	_suspended = false
	_sync_views()
