extends RefCounted
class_name ItemConsumptionCoordinator

signal item_consumed(item_id: StringName)

var _inventory: InventoryModel
var _stats: ActorStats

func setup(inventory: InventoryModel, stats: ActorStats) -> void:
	assert(inventory != null and stats != null)
	assert(_inventory == null and _stats == null)
	_inventory = inventory
	_stats = stats

func can_consume_selected() -> bool:
	assert(_inventory != null)
	return can_consume_at(_inventory.selected_slot)

func can_consume_at(slot_index: int) -> bool:
	assert(_inventory != null and _stats != null)
	var action := _get_action_at(slot_index)
	if action == null or not _inventory.can_discard_stack(slot_index, 1) or _stats.is_dead():
		return false
	return _stats.current_hp < _stats.get_value(&"hp")

func try_consume_selected() -> bool:
	assert(_inventory != null)
	return try_consume_at(_inventory.selected_slot)

func try_consume_at(slot_index: int) -> bool:
	if not can_consume_at(slot_index):
		return false
	var item_id := _inventory.get_slot(slot_index).item_id
	var action := _get_action_at(slot_index)
	var consumed := _inventory.discard_stack(slot_index, 1)
	assert(consumed)
	var healed := _stats.heal(_stats.get_value(&"hp") * action.health_restore_fraction)
	assert(healed > 0.0)
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
