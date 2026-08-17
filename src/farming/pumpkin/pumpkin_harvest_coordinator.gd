extends RefCounted
class_name PumpkinHarvestCoordinator

signal harvest_completed

const NO_TARGET: int = -1
const HARVEST_PROMPT: String = "Left Click  Harvest Pumpkin"
const INVENTORY_FULL_PROMPT: String = "Inventory Full"

var _pumpkin_patch: PumpkinPatchCoordinator
var _inventory: InventoryModel
var _prompt: InteractionPromptCoordinator
var _target_tile_index: int = NO_TARGET
var _target_ray_distance: float = INF

func setup(pumpkin_patch: PumpkinPatchCoordinator, inventory: InventoryModel, prompt: InteractionPromptCoordinator) -> bool:
	assert(pumpkin_patch != null and inventory != null and prompt != null)
	assert(_pumpkin_patch == null and _inventory == null and _prompt == null)
	if not pumpkin_patch.validate_harvest_items(inventory.item_catalog):
		return false
	_pumpkin_patch = pumpkin_patch
	_inventory = inventory
	_prompt = prompt
	return true

func update_target(ray_origin: Vector3, ray_direction: Vector3, ray_max_distance: float, player_position: Vector3, player_reach: float) -> void:
	assert(_pumpkin_patch != null and _inventory != null and _prompt != null)
	if _prompt.is_interaction_blocked():
		clear_target()
		return
	var target := _pumpkin_patch.find_harvest_target(ray_origin, ray_direction, ray_max_distance)
	var tile_index := int(target.get("tile_index", NO_TARGET))
	if tile_index != NO_TARGET:
		var target_position := _pumpkin_patch.get_tile_world_bounds(tile_index).get_center()
		if player_position.distance_squared_to(target_position) > player_reach * player_reach:
			tile_index = NO_TARGET
	if tile_index == NO_TARGET:
		clear_target()
		return
	_target_tile_index = tile_index
	_target_ray_distance = float(target["distance"])
	_refresh_prompt()

func clear_target() -> void:
	_target_tile_index = NO_TARGET
	_target_ray_distance = INF
	if _prompt != null:
		_prompt.set_harvest_prompt("")

func has_target() -> bool:
	return _target_tile_index != NO_TARGET

func get_target_ray_distance() -> float:
	assert(has_target())
	return _target_ray_distance

func get_target_bounds() -> AABB:
	assert(has_target())
	return _pumpkin_patch.get_tile_world_bounds(_target_tile_index)

func can_harvest_target() -> bool:
	if not has_target() or not _pumpkin_patch.can_harvest_tile(_target_tile_index):
		return false
	return _inventory.can_add_batch(_pumpkin_patch.get_harvest_item_ids(_target_tile_index))

func try_harvest_target() -> bool:
	if not can_harvest_target():
		_refresh_prompt()
		return false
	var tile_index := _target_tile_index
	var item_ids := _pumpkin_patch.get_harvest_item_ids(tile_index)
	var harvested := _pumpkin_patch.try_harvest_tile(tile_index)
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
		_prompt.set_harvest_prompt(HARVEST_PROMPT)
	else:
		_prompt.set_harvest_prompt(INVENTORY_FULL_PROMPT)
