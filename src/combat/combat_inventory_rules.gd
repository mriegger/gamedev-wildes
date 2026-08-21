extends RefCounted
class_name CombatInventoryRules

static func has_ready_weapon(inventory: InventoryModel) -> bool:
	assert(inventory != null)
	var owned_item_ids: Dictionary[StringName, bool] = {}
	var bow_actions: Array[BowDrawActionDefinition] = []
	for index in range(mini(inventory.get_size(), InventoryModel.FILLABLE_SIZE)):
		var stack := inventory.get_slot(index)
		if stack == null:
			continue
		owned_item_ids[stack.item_id] = true
		var item := inventory.item_catalog.get_definition(stack.item_id)
		if item.primary_action is MeleeAttackActionDefinition:
			return true
		if item.primary_action is BowDrawActionDefinition:
			bow_actions.append(item.primary_action as BowDrawActionDefinition)
	for bow_action in bow_actions:
		for ammunition in bow_action.ammunition:
			if owned_item_ids.has(ammunition.id):
				return true
	return false
