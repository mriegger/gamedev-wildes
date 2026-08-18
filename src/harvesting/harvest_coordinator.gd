extends RefCounted
class_name HarvestCoordinator

signal harvest_completed

const NO_TARGET: int = -1
const INVENTORY_FULL_PROMPT: String = "Inventory Full"

var _sources: Array[HarvestSource] = []
var _inventory: InventoryModel
var _prompt: InteractionPromptCoordinator
var _target_source: HarvestSource
var _target_id: int = NO_TARGET
var _target_ray_distance: float = INF

func setup(sources: Array[HarvestSource], inventory: InventoryModel, prompt: InteractionPromptCoordinator) -> bool:
	assert(not sources.is_empty() and inventory != null and prompt != null)
	assert(_sources.is_empty() and _inventory == null and _prompt == null)
	for source in sources:
		if source == null or not source.validate_harvest_items(inventory.item_catalog):
			return false
	_sources = sources.duplicate()
	_inventory = inventory
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

func can_harvest_target() -> bool:
	if not has_target() or not _target_source.can_harvest_target(_target_id):
		return false
	return _inventory.can_add_batch(_target_source.get_harvest_item_ids(_target_id))

func try_harvest_target() -> bool:
	if not can_harvest_target():
		_refresh_prompt()
		return false
	var item_ids := _target_source.get_harvest_item_ids(_target_id)
	var harvested := _target_source.try_harvest_target(_target_id)
	assert(harvested)
	var collected := _inventory.add_batch(item_ids)
	assert(collected)
	clear_target()
	harvest_completed.emit()
	return true

func _refresh_prompt() -> void:
	if not has_target():
		_prompt.set_harvest_prompt("")
	elif can_harvest_target():
		_prompt.set_harvest_prompt(_target_source.get_harvest_prompt())
	else:
		_prompt.set_harvest_prompt(INVENTORY_FULL_PROMPT)
