extends RefCounted
class_name HarvestCoordinator

signal harvest_completed
signal items_harvested(item_ids: Array[StringName])

const NO_TARGET: int = -1
const INVENTORY_FULL_PROMPT: String = "Inventory Full"

var _sources: Array[HarvestSource] = []
var _inventory: InventoryModel
var _inventory_loadout: InventoryLoadoutCoordinator
var _prompt: InteractionPromptCoordinator
var _target_source: HarvestSource
var _target_id: int = NO_TARGET
var _target_ray_distance: float = INF

func setup(
	sources: Array[HarvestSource],
	inventory: InventoryModel,
	inventory_loadout: InventoryLoadoutCoordinator,
	prompt: InteractionPromptCoordinator,
) -> bool:
	assert(not sources.is_empty() and inventory != null and inventory_loadout != null and prompt != null)
	assert(_sources.is_empty() and _inventory == null and _inventory_loadout == null and _prompt == null)
	assert(inventory_loadout.inventory_model == inventory)
	for source in sources:
		if source == null or not source.validate_harvest_items(inventory.item_catalog):
			return false
	_sources = sources.duplicate()
	_inventory = inventory
	_inventory_loadout = inventory_loadout
	_prompt = prompt
	return true

func update_target(ray_origin: Vector3, ray_direction: Vector3, ray_max_distance: float, player_position: Vector3, player_reach: float) -> void:
	assert(not _sources.is_empty() and _inventory != null and _prompt != null)
	if _prompt.is_interaction_blocked():
		clear_target()
		return
	var nearest_source: HarvestSource
	var nearest_id := NO_TARGET
	var nearest_distance := ray_max_distance
	for source in _sources:
		var target := source.find_harvest_target(ray_origin, ray_direction, ray_max_distance)
		var target_id := int(target.get("target_id", NO_TARGET))
		if target_id == NO_TARGET:
			continue
		var distance := float(target.get("distance", INF))
		var target_position := source.get_harvest_target_bounds(target_id).get_center()
		if distance <= nearest_distance and player_position.distance_squared_to(target_position) <= player_reach * player_reach:
			nearest_source = source
			nearest_id = target_id
			nearest_distance = distance
	if nearest_source == null:
		clear_target()
		return
	_target_source = nearest_source
	_target_id = nearest_id
	_target_ray_distance = nearest_distance
	_refresh_prompt()

func clear_target() -> void:
	_target_source = null
	_target_id = NO_TARGET
	_target_ray_distance = INF
	if _prompt != null:
		_prompt.set_harvest_prompt("")

func has_target() -> bool:
	return _target_source != null and _target_id != NO_TARGET

func get_target_ray_distance() -> float:
	assert(has_target())
	return _target_ray_distance

func get_target_bounds() -> AABB:
	assert(has_target())
	return _target_source.get_harvest_target_bounds(_target_id)

func find_nearby_target_bounds(
	player_position: Vector3,
	horizontal_radius: float,
	accepted_item_ids: Array[StringName],
) -> Variant:
	assert(horizontal_radius > 0.0 and not accepted_item_ids.is_empty())
	var nearest_bounds: Variant = null
	var nearest_distance_squared := horizontal_radius * horizontal_radius
	for source in _sources:
		for target_id in source.get_harvest_target_ids():
			if not source.can_harvest_target(target_id):
				continue
			var bounds := source.get_harvest_target_bounds(target_id)
			var center := bounds.get_center()
			var distance_squared := Vector2(player_position.x - center.x, player_position.z - center.z).length_squared()
			if distance_squared > nearest_distance_squared:
				continue
			var item_ids := source.get_harvest_item_ids(target_id)
			var has_accepted_item := false
			for item_id in item_ids:
				if accepted_item_ids.has(item_id):
					has_accepted_item = true
					break
			if not has_accepted_item or not _inventory_loadout.can_add_batch(item_ids):
				continue
			nearest_distance_squared = distance_squared
			nearest_bounds = bounds
	return nearest_bounds

func can_harvest_target() -> bool:
	return _prepare_target_harvest() != null

func try_harvest_target() -> bool:
	var prepared := _prepare_target_harvest()
	if prepared == null or not _can_commit_prepared_harvest(prepared):
		_refresh_prompt()
		return false
	var source := prepared._get_source()
	var source_change := prepared._get_source_change()
	var inventory_change := prepared._get_inventory_change()
	var harvested := source._commit_prepared_harvest(source_change, false)
	assert(harvested)
	var collected := _inventory_loadout._commit_prepared_change(inventory_change)
	assert(collected)
	clear_target()
	var source_notified := source._notify_prepared_harvest(source_change)
	assert(source_notified)
	var inventory_notified := _inventory_loadout._notify_prepared_change(inventory_change)
	assert(inventory_notified)
	harvest_completed.emit()
	items_harvested.emit(source_change.get_harvest_item_ids())
	return true

func _prepare_target_harvest() -> PreparedHarvestTransaction:
	if not has_target() or not _target_source.can_harvest_target(_target_id):
		return null
	var source_change := _target_source.prepare_harvest_target(_target_id)
	if source_change == null:
		return null
	var inventory_change := _inventory_loadout.prepare_inventory_change(
		_inventory.prepare_add_batch(source_change.get_harvest_item_ids()),
	)
	if inventory_change == null:
		return null
	return PreparedHarvestTransaction.new(
		self,
		_target_source,
		source_change,
		inventory_change,
	)

func _can_commit_prepared_harvest(prepared: PreparedHarvestTransaction) -> bool:
	return (
		prepared != null
		and prepared._is_for(self)
		and prepared._get_source().can_commit_prepared_harvest(prepared._get_source_change())
		and _inventory_loadout.can_commit_prepared_change(prepared._get_inventory_change())
	)

func _refresh_prompt() -> void:
	if not has_target():
		_prompt.set_harvest_prompt("")
	elif can_harvest_target():
		_prompt.set_harvest_prompt(_target_source.get_harvest_prompt())
	else:
		_prompt.set_harvest_prompt(INVENTORY_FULL_PROMPT)
