extends RefCounted
class_name RuneEffectCoordinator

const EFFECT_SOURCE_ID: StringName = &"socketed_runes"
const EFFECT_SOURCE_INSTANCE_ID: StringName = &"socketed_runes"
const MAXIMUM_ACTIVE_RUNE_COUNT: int = ProficiencyDefinition.MAXIMUM_SLOT_COUNT * (ArmorDefinition.SLOT_COUNT + 1)

var inventory_model: InventoryModel
var actor_stats: ActorStats

var _active_loadout_fingerprint: Array[StringName] = []

func setup(p_inventory_model: InventoryModel, p_actor_stats: ActorStats) -> bool:
	assert(p_inventory_model != null)
	assert(p_actor_stats != null)
	if inventory_model != null or actor_stats != null:
		return false
	if not _validate_rune_definitions(p_inventory_model.item_catalog, p_actor_stats):
		return false
	inventory_model = p_inventory_model
	actor_stats = p_actor_stats
	if not _synchronize_active_runes(true):
		inventory_model = null
		actor_stats = null
		return false
	inventory_model.inventory_changed.connect(_on_inventory_changed)
	return true

func _validate_rune_definitions(item_catalog: ItemCatalog, p_actor_stats: ActorStats) -> bool:
	for definition in item_catalog.definitions:
		var rune := definition as RuneDefinition
		if rune == null:
			continue
		if not p_actor_stats.can_replace_source_modifiers(
			EFFECT_SOURCE_ID,
			EFFECT_SOURCE_INSTANCE_ID,
			rune.socket_modifiers,
		):
			push_error("[RuneEffectCoordinator] Invalid modifiers for %s" % rune.id)
			return false
	if not _can_apply_maximum_active_loadout(item_catalog, p_actor_stats):
		push_error("[RuneEffectCoordinator] Rune catalog permits an invalid active modifier loadout")
		return false
	return true

func _can_apply_maximum_active_loadout(item_catalog: ItemCatalog, p_actor_stats: ActorStats) -> bool:
	var maximum_active_modifiers: Array[StatModifier] = []
	for definition in item_catalog.definitions:
		var rune := definition as RuneDefinition
		if rune == null:
			continue
		for _active_slot in range(MAXIMUM_ACTIVE_RUNE_COUNT):
			maximum_active_modifiers.append_array(rune.socket_modifiers)
	return p_actor_stats.can_replace_source_modifiers(
		EFFECT_SOURCE_ID,
		EFFECT_SOURCE_INSTANCE_ID,
		maximum_active_modifiers,
	)

func _on_inventory_changed() -> void:
	var synchronized := _synchronize_active_runes(false)
	assert(synchronized)

func _synchronize_active_runes(force: bool) -> bool:
	var next_fingerprint := _get_active_rune_ids()
	if not force and _fingerprints_match(next_fingerprint, _active_loadout_fingerprint):
		return true
	var modifiers: Array[StatModifier] = []
	for rune_id in next_fingerprint:
		if not inventory_model.item_catalog.has_definition(rune_id):
			return false
		var rune := inventory_model.item_catalog.get_definition(rune_id) as RuneDefinition
		if rune == null:
			return false
		modifiers.append_array(rune.socket_modifiers)
	if not actor_stats.replace_source_modifiers_preserving_health_ratio(
		EFFECT_SOURCE_ID,
		EFFECT_SOURCE_INSTANCE_ID,
		modifiers,
	):
		return false
	_active_loadout_fingerprint = next_fingerprint
	return true

func _get_active_rune_ids() -> Array[StringName]:
	var rune_ids: Array[StringName] = []
	var selected_stack := inventory_model.get_selected_data()
	if selected_stack != null:
		var selected_definition := inventory_model.item_catalog.get_definition(selected_stack.item_id)
		if selected_definition.primary_action is MeleeAttackActionDefinition:
			_append_socketed_rune_ids(selected_stack, rune_ids)
	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		var equipment_index := InventoryModel.get_equipment_index(armor_slot)
		var equipment_stack := inventory_model.get_slot(equipment_index)
		if equipment_stack == null:
			continue
		var equipment_definition := inventory_model.item_catalog.get_definition(equipment_stack.item_id)
		if equipment_definition is ArmorDefinition:
			_append_socketed_rune_ids(equipment_stack, rune_ids)
	rune_ids.sort()
	return rune_ids

func _append_socketed_rune_ids(stack: InventoryStack, rune_ids: Array[StringName]) -> void:
	for rune_id in stack.socketed_rune_ids:
		if not rune_id.is_empty():
			rune_ids.append(rune_id)

func _fingerprints_match(first: Array[StringName], second: Array[StringName]) -> bool:
	if first.size() != second.size():
		return false
	for index in range(first.size()):
		if first[index] != second[index]:
			return false
	return true
