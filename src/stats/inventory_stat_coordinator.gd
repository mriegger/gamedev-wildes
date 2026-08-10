extends RefCounted
class_name InventoryStatCoordinator

const SELECTED_ITEM_INSTANCE_ID: StringName = &"selected_item"

var inventory_model: InventoryModel
var actor_stats: ActorStats

var _selected_item_id: StringName = &""
var _selected_slot: int = -1
var _equipped_item_ids: Array[StringName] = []

func setup(p_inventory_model: InventoryModel, p_actor_stats: ActorStats) -> bool:
	assert(p_inventory_model != null)
	assert(p_actor_stats != null)
	if not _validate_definitions(p_inventory_model, p_actor_stats):
		return false
	inventory_model = p_inventory_model
	actor_stats = p_actor_stats
	_equipped_item_ids.resize(ArmorDefinition.SLOT_COUNT)
	_equipped_item_ids.fill(&"")
	if not _synchronize_selected_item(true) or not _synchronize_equipment(true):
		return false
	inventory_model.inventory_changed.connect(_on_inventory_changed)
	return true

func can_handle_drop(source_index: int, destination_index: int, drag_count: int) -> bool:
	return not _prepare_drop(source_index, destination_index, drag_count).is_empty()

func handle_drop(source_index: int, destination_index: int, drag_count: int) -> bool:
	var prepared := _prepare_drop(source_index, destination_index, drag_count)
	if prepared.is_empty():
		return false
	var equipment_index := int(prepared["equipment_index"])
	if equipment_index >= 0:
		var armor := prepared["armor"] as ArmorDefinition
		var modifier_instance_id := _get_equipment_instance_id(equipment_index)
		if armor == null:
			actor_stats.remove_modifiers_from_item_instance(modifier_instance_id)
		else:
			if not actor_stats.replace_item_modifiers(armor.id, modifier_instance_id, armor.stat_modifiers):
				return false
		_equipped_item_ids[equipment_index - InventoryModel.FILLABLE_SIZE] = &"" if armor == null else armor.id
	var moved := inventory_model.handle_drop(source_index, destination_index, drag_count)
	assert(moved)
	return moved

func try_equip_armor(source_index: int) -> bool:
	if source_index < 0 or source_index >= min(inventory_model.size, InventoryModel.FILLABLE_SIZE):
		return false
	var stack := inventory_model.get_slot(source_index)
	if stack == null:
		return false
	var armor := inventory_model.item_catalog.get_definition(stack.item_id) as ArmorDefinition
	if armor == null:
		return false
	return handle_drop(source_index, InventoryModel.get_equipment_index(armor.armor_slot), stack.count)

func try_unequip_armor(equipment_index: int) -> bool:
	if equipment_index < 0 or equipment_index >= inventory_model.size or not InventoryModel.is_equipment_index(equipment_index):
		return false
	var stack := inventory_model.get_slot(equipment_index)
	if stack == null:
		return false
	for region_name in [&"backpack", &"hotbar"]:
		for destination_index in InventoryModel.get_region_indices(region_name):
			if destination_index >= inventory_model.size or inventory_model.get_slot(destination_index) != null:
				continue
			if handle_drop(equipment_index, destination_index, stack.count):
				return true
	return false

func _validate_definitions(p_inventory_model: InventoryModel, p_actor_stats: ActorStats) -> bool:
	for definition in p_inventory_model.item_catalog.definitions:
		if definition.stat_modifiers.is_empty():
			continue
		var modifier_instance_id := SELECTED_ITEM_INSTANCE_ID
		if definition.stat_modifier_activation == ItemDefinition.StatModifierActivation.EQUIPPED:
			var armor := definition as ArmorDefinition
			if armor == null:
				push_error("[InventoryStatCoordinator] Equipped modifiers require an armor definition for %s" % definition.id)
				return false
			modifier_instance_id = _get_equipment_instance_id(InventoryModel.get_equipment_index(armor.armor_slot))
		if not p_actor_stats.can_replace_item_modifiers(definition.id, modifier_instance_id, definition.stat_modifiers):
			push_error("[InventoryStatCoordinator] Invalid modifiers for %s" % definition.id)
			return false
	return true

func _prepare_drop(source_index: int, destination_index: int, drag_count: int) -> Dictionary:
	if inventory_model == null or actor_stats == null or not inventory_model.can_handle_drop(source_index, destination_index, drag_count):
		return {}
	var source_is_equipment := InventoryModel.is_equipment_index(source_index)
	var destination_is_equipment := InventoryModel.is_equipment_index(destination_index)
	if not source_is_equipment and not destination_is_equipment:
		return {"equipment_index": -1, "armor": null}
	var equipment_index := destination_index if destination_is_equipment else source_index
	var resulting_item_id: StringName = &""
	if destination_is_equipment:
		resulting_item_id = inventory_model.get_slot(source_index).item_id
	else:
		var destination_stack := inventory_model.get_slot(destination_index)
		if destination_stack != null:
			resulting_item_id = destination_stack.item_id
	if resulting_item_id.is_empty():
		return {"equipment_index": equipment_index, "armor": null}
	var armor := inventory_model.item_catalog.get_definition(resulting_item_id) as ArmorDefinition
	if armor == null or not actor_stats.can_replace_item_modifiers(armor.id, _get_equipment_instance_id(equipment_index), armor.stat_modifiers):
		return {}
	return {"equipment_index": equipment_index, "armor": armor}

func _on_inventory_changed() -> void:
	assert(_synchronize_selected_item(false))
	assert(_synchronize_equipment(false))

func _synchronize_selected_item(force: bool) -> bool:
	var next_item_id: StringName = &""
	var next_slot := -1
	var definition: ItemDefinition = null
	var stack := inventory_model.get_selected_data()
	if stack != null:
		var selected_definition := inventory_model.item_catalog.get_definition(stack.item_id)
		if selected_definition.stat_modifier_activation == ItemDefinition.StatModifierActivation.SELECTED and not selected_definition.stat_modifiers.is_empty():
			next_item_id = selected_definition.id
			next_slot = inventory_model.selected_slot
			definition = selected_definition
	if not force and next_item_id == _selected_item_id and next_slot == _selected_slot:
		return true
	if definition == null:
		actor_stats.remove_modifiers_from_item_instance(SELECTED_ITEM_INSTANCE_ID)
	elif not actor_stats.replace_item_modifiers(definition.id, SELECTED_ITEM_INSTANCE_ID, definition.stat_modifiers):
		return false
	_selected_item_id = next_item_id
	_selected_slot = next_slot
	return true

func _synchronize_equipment(force: bool) -> bool:
	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		var armor := inventory_model.get_equipped_armor(armor_slot)
		var next_item_id: StringName = &"" if armor == null else armor.id
		if not force and _equipped_item_ids[armor_slot] == next_item_id:
			continue
		var equipment_index := InventoryModel.get_equipment_index(armor_slot)
		var modifier_instance_id := _get_equipment_instance_id(equipment_index)
		if armor == null:
			actor_stats.remove_modifiers_from_item_instance(modifier_instance_id)
		elif not actor_stats.replace_item_modifiers(armor.id, modifier_instance_id, armor.stat_modifiers):
			return false
		_equipped_item_ids[armor_slot] = next_item_id
	return true

func _get_equipment_instance_id(equipment_index: int) -> StringName:
	return StringName("equipment_slot_%d" % (equipment_index - InventoryModel.FILLABLE_SIZE))
