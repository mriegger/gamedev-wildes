extends RefCounted
class_name ItemConsumptionCoordinator

signal item_consumed(item_id: StringName)

var _inventory: InventoryModel
var _loadout: InventoryLoadoutCoordinator
var _stats: ActorStats

func setup(
	inventory: InventoryModel,
	loadout: InventoryLoadoutCoordinator,
	stats: ActorStats,
) -> void:
	assert(inventory != null and loadout != null and stats != null)
	assert(_inventory == null and _loadout == null and _stats == null)
	assert(loadout.inventory_model == inventory and loadout.actor_stats == stats)
	_inventory = inventory
	_loadout = loadout
	_stats = stats

func can_consume_selected() -> bool:
	assert(_inventory != null)
	return can_consume_at(_inventory.get_equipped_slot())

func can_consume_at(slot_index: int) -> bool:
	assert(_inventory != null and _loadout != null and _stats != null)
	var action := _get_action_at(slot_index)
	if action == null or _stats.is_dead():
		return false
	return _prepare_consumption(slot_index, action) != null

func try_consume_selected() -> bool:
	assert(_inventory != null)
	return try_consume_at(_inventory.get_equipped_slot())

func try_consume_at(slot_index: int) -> bool:
	var action := _get_action_at(slot_index)
	if action == null or _stats.is_dead():
		return false
	var item_id := _inventory.get_slot(slot_index).item_id
	var prepared := _prepare_consumption(slot_index, action)
	if prepared == null or not _loadout.commit_prepared_change(prepared):
		return false
	item_consumed.emit(item_id)
	return true

func has_consumable_at(slot_index: int) -> bool:
	assert(_inventory != null)
	return _get_action_at(slot_index) != null

func _get_action_at(slot_index: int) -> ConsumableActionDefinition:
	var stack := _inventory.get_slot(slot_index)
	if stack == null:
		return null
	return _inventory.item_catalog.get_definition(stack.item_id).secondary_action as ConsumableActionDefinition

func _prepare_consumption(
	slot_index: int,
	action: ConsumableActionDefinition,
) -> PreparedInventoryLoadoutChange:
	var output_stack: InventoryStack
	if not action.output_item_id.is_empty():
		output_stack = InventoryStack.new(action.output_item_id, action.output_count)
	var inventory_change := _inventory.prepare_consume_item(slot_index, output_stack)
	if inventory_change == null:
		return null
	if action.can_consume_at_full_health and _stats.current_hp >= _stats.get_value(&"hp"):
		return _loadout.prepare_inventory_change(inventory_change)
	return _loadout.prepare_inventory_change_with_health_restore(
		inventory_change,
		action.health_restore_fraction,
	)
