extends RefCounted
class_name InventoryLoadoutCoordinator

const StatModifierReplacementType = preload("res://stats/stat_modifier_replacement.gd")

const SELECTED_ITEM_INSTANCE_ID: StringName = &"selected_item"
const ARMOR_SET_INSTANCE_ID: StringName = &"armor_set"
const RUNE_EFFECT_SOURCE_ID: StringName = &"socketed_runes"
const RUNE_EFFECT_INSTANCE_ID: StringName = &"socketed_runes"
var inventory_model: InventoryModel
var actor_stats: ActorStats
var _item_proficiency: ItemProficiency

func setup(
	p_inventory_model: InventoryModel,
	p_actor_stats: ActorStats,
	p_item_proficiency: ItemProficiency,
) -> bool:
	assert(p_inventory_model != null)
	assert(p_actor_stats != null)
	assert(p_item_proficiency != null)
	if inventory_model != null or actor_stats != null or _item_proficiency != null:
		return false
	if not p_item_proficiency.is_for_catalog(p_inventory_model.item_catalog):
		return false
	var reserved_source_instance_ids := _get_reserved_stat_source_instance_ids()
	if (
		not p_inventory_model._can_bind_runtime()
		or not p_actor_stats._can_bind_loadout(reserved_source_instance_ids)
	):
		return false
	if not _validate_definitions(p_inventory_model, p_actor_stats):
		return false
	if _prepare_stat_projection(p_inventory_model, p_inventory_model, p_actor_stats, true, false) == null:
		return false
	assert(p_inventory_model._bind_runtime())
	assert(p_actor_stats._bind_loadout(reserved_source_instance_ids))
	var stat_change := _prepare_stat_projection(p_inventory_model, p_inventory_model, p_actor_stats, true)
	assert(stat_change != null)
	p_actor_stats._commit_prepared_loadout_modifier_change(stat_change)
	inventory_model = p_inventory_model
	actor_stats = p_actor_stats
	_item_proficiency = p_item_proficiency
	return true

func uses_item_proficiency(p_item_proficiency: ItemProficiency) -> bool:
	return _item_proficiency == p_item_proficiency

func prepare_inventory_change(inventory_change: PreparedInventoryChange) -> PreparedInventoryLoadoutChange:
	if (
		inventory_model == null
		or actor_stats == null
		or not inventory_model.can_commit_prepared_change(inventory_change)
	):
		return null
	var stat_change := _prepare_stat_projection(inventory_change, inventory_model, actor_stats)
	if stat_change == null:
		return null
	return PreparedInventoryLoadoutChange.new(self, inventory_change, stat_change)

func prepare_inventory_change_with_health_restore(
	inventory_change: PreparedInventoryChange,
	health_restore_fraction: float,
) -> PreparedInventoryLoadoutChange:
	var prepared := prepare_inventory_change(inventory_change)
	if prepared == null:
		return null
	var stat_change := actor_stats._prepare_health_restore_on_loadout_change(
		prepared._get_stat_change(),
		health_restore_fraction,
	)
	if stat_change == null:
		return null
	return PreparedInventoryLoadoutChange.new(self, inventory_change, stat_change)

func can_commit_prepared_change(prepared: PreparedInventoryLoadoutChange) -> bool:
	return (
		prepared != null
		and prepared._is_for(self)
		and inventory_model.can_commit_prepared_change(prepared._get_inventory_change())
		and actor_stats._can_commit_prepared_loadout_modifier_change(prepared._get_stat_change())
	)

func commit_prepared_change(prepared: PreparedInventoryLoadoutChange) -> bool:
	if not _commit_prepared_change(prepared):
		return false
	return _notify_prepared_change(prepared)

func _commit_prepared_change(prepared: PreparedInventoryLoadoutChange) -> bool:
	if not can_commit_prepared_change(prepared):
		return false
	var health_changed := actor_stats._prepared_modifier_change_changes_health(prepared._get_stat_change())
	var depleted := actor_stats._commit_prepared_loadout_modifier_change(prepared._get_stat_change(), false)
	inventory_model._commit_prepared_change(prepared._get_inventory_change(), false)
	return prepared._mark_committed(depleted, health_changed)

func _notify_prepared_change(prepared: PreparedInventoryLoadoutChange) -> bool:
	if prepared == null or not prepared._is_for(self) or not prepared._consume_notification():
		return false
	inventory_model._emit_inventory_changed()
	if prepared._should_notify_health_changed():
		actor_stats._emit_health_changed()
	if prepared._should_notify_health_depleted():
		actor_stats._emit_health_depleted()
	return true

func add_stack(stack: InventoryStack) -> bool:
	return commit_prepared_change(_prepare(inventory_model.prepare_add_stack(stack)))

func select_slot(index: int) -> bool:
	if inventory_model.is_hotbar_index(index) and inventory_model.get_selected_slot() == index:
		return true
	return commit_prepared_change(_prepare(inventory_model.prepare_select_slot(index)))

func assign_slot_to_hotbar(source_index: int, hotbar_index: int) -> bool:
	return commit_prepared_change(_prepare(inventory_model.prepare_assign_slot_to_hotbar(source_index, hotbar_index)))

func move_hotbar_slot_to_backpack(hotbar_index: int) -> bool:
	return commit_prepared_change(_prepare(inventory_model.prepare_move_hotbar_slot_to_backpack(hotbar_index)))

func can_discard_stack(source_index: int, count: int) -> bool:
	return _prepare(inventory_model.prepare_discard_stack(source_index, count)) != null

func discard_stack(source_index: int, count: int) -> bool:
	return commit_prepared_change(_prepare(inventory_model.prepare_discard_stack(source_index, count)))

func ensure_item(item_id: StringName) -> bool:
	if inventory_model.has_item(item_id):
		return true
	return commit_prepared_change(_prepare(inventory_model.prepare_ensure_item(item_id)))

func migrate_starter_items() -> bool:
	if inventory_model.get_starter_item_migration_version() >= InventoryModel.STARTER_ITEM_MIGRATION_VERSION:
		return true
	return commit_prepared_change(_prepare(inventory_model.prepare_starter_item_migration()))

func add_backpack_item(item_id: StringName, count: int) -> bool:
	return commit_prepared_change(_prepare(inventory_model.prepare_add_backpack_item(item_id, count)))

func can_exchange_inventory_items(
	consumed: Dictionary[StringName, int],
	granted: Dictionary[StringName, int],
) -> bool:
	return _prepare(inventory_model.prepare_inventory_exchange(consumed, granted)) != null

func exchange_inventory_items(
	consumed: Dictionary[StringName, int],
	granted: Dictionary[StringName, int],
) -> bool:
	return commit_prepared_change(_prepare(inventory_model.prepare_inventory_exchange(consumed, granted)))

func can_add_batch(ids: Array[StringName]) -> bool:
	if ids.is_empty():
		return true
	return _prepare(inventory_model.prepare_add_batch(ids)) != null

func add_batch(ids: Array[StringName]) -> bool:
	if ids.is_empty():
		return true
	return commit_prepared_change(_prepare(inventory_model.prepare_add_batch(ids)))

func can_consume_selected() -> bool:
	return _prepare(inventory_model.prepare_consume_selected()) != null

func can_handle_drop(source_index: int, destination_index: int, drag_count: int) -> bool:
	return _prepare(inventory_model.prepare_handle_drop(source_index, destination_index, drag_count)) != null

func handle_drop(source_index: int, destination_index: int, drag_count: int) -> bool:
	return commit_prepared_change(_prepare(inventory_model.prepare_handle_drop(source_index, destination_index, drag_count)))

func try_equip_armor(source_index: int) -> bool:
	if source_index < 0 or source_index >= mini(inventory_model.get_size(), InventoryModel.FILLABLE_SIZE):
		return false
	var stack := inventory_model.get_slot(source_index)
	if stack == null:
		return false
	var armor := inventory_model.item_catalog.get_definition(stack.item_id) as ArmorDefinition
	if armor == null:
		return false
	return handle_drop(source_index, InventoryModel.get_equipment_index(armor.armor_slot), stack.count)

func try_unequip_armor(equipment_index: int) -> bool:
	if (
		equipment_index < 0
		or equipment_index >= inventory_model.get_size()
		or not InventoryModel.is_equipment_index(equipment_index)
	):
		return false
	var stack := inventory_model.get_slot(equipment_index)
	if stack == null:
		return false
	for region_name in [&"backpack", &"hotbar"]:
		for destination_index in InventoryModel.get_region_indices(region_name):
			if destination_index >= inventory_model.get_size() or inventory_model.get_slot(destination_index) != null:
				continue
			if handle_drop(equipment_index, destination_index, stack.count):
				return true
	return false

func socket_rune(
	gear_index: int,
	expected_rune_ids: Array[StringName],
	next_rune_ids: Array[StringName],
	rune_source_index: int,
	rune_id: StringName,
) -> bool:
	return commit_prepared_change(_prepare_socket_rune_change(
		gear_index,
		expected_rune_ids,
		next_rune_ids,
		rune_source_index,
		rune_id,
	))

func can_socket_rune(
	gear_index: int,
	expected_rune_ids: Array[StringName],
	next_rune_ids: Array[StringName],
	rune_source_index: int,
	rune_id: StringName,
) -> bool:
	return _prepare_socket_rune_change(
		gear_index,
		expected_rune_ids,
		next_rune_ids,
		rune_source_index,
		rune_id,
	) != null

func unsocket_rune(
	gear_index: int,
	expected_rune_ids: Array[StringName],
	next_rune_ids: Array[StringName],
	returned_rune_id: StringName,
) -> bool:
	return commit_prepared_change(_prepare(inventory_model.prepare_unsocketed_rune(
		gear_index,
		expected_rune_ids,
		next_rune_ids,
		returned_rune_id,
	)))

func can_unsocket_rune(
	gear_index: int,
	expected_rune_ids: Array[StringName],
	next_rune_ids: Array[StringName],
	returned_rune_id: StringName,
) -> bool:
	return _prepare(inventory_model.prepare_unsocketed_rune(
		gear_index,
		expected_rune_ids,
		next_rune_ids,
		returned_rune_id,
	)) != null

func _prepare(inventory_change: PreparedInventoryChange) -> PreparedInventoryLoadoutChange:
	return prepare_inventory_change(inventory_change)

func _prepare_socket_rune_change(
	gear_index: int,
	expected_rune_ids: Array[StringName],
	next_rune_ids: Array[StringName],
	rune_source_index: int,
	rune_id: StringName,
) -> PreparedInventoryLoadoutChange:
	if not _is_socket_addition_unlocked(gear_index, expected_rune_ids, next_rune_ids, rune_id):
		return null
	return _prepare(inventory_model.prepare_socketed_rune(
		gear_index,
		expected_rune_ids,
		next_rune_ids,
		rune_source_index,
		rune_id,
	))

func _is_socket_addition_unlocked(
	gear_index: int,
	expected_rune_ids: Array[StringName],
	next_rune_ids: Array[StringName],
	rune_id: StringName,
) -> bool:
	if inventory_model == null or _item_proficiency == null or gear_index < 0 or gear_index >= inventory_model.get_size():
		return false
	var gear_stack := inventory_model.get_slot(gear_index)
	if gear_stack == null or not _item_proficiency.has_proficiency(gear_stack.item_id):
		return false
	var changed_index := -1
	for index in range(maxi(expected_rune_ids.size(), next_rune_ids.size())):
		var previous_id: StringName = expected_rune_ids[index] if index < expected_rune_ids.size() else &""
		var next_id: StringName = next_rune_ids[index] if index < next_rune_ids.size() else &""
		if previous_id == next_id:
			continue
		if changed_index >= 0 or not previous_id.is_empty() or next_id != rune_id:
			return false
		changed_index = index
	return changed_index >= 0 and changed_index < _item_proficiency.get_unlocked_slot_count(gear_stack.item_id)

func _validate_definitions(p_inventory_model: InventoryModel, p_actor_stats: ActorStats) -> bool:
	var validated_armor_sets: Dictionary = {}
	for definition in p_inventory_model.item_catalog.definitions:
		if definition == null:
			return false
		var armor := definition as ArmorDefinition
		var modifier_instance_id := SELECTED_ITEM_INSTANCE_ID
		if definition.stat_modifier_activation == ItemDefinition.StatModifierActivation.EQUIPPED:
			if armor == null:
				push_error("[InventoryLoadoutCoordinator] Equipped modifiers require armor for %s" % definition.id)
				return false
			modifier_instance_id = _get_equipment_instance_id(InventoryModel.get_equipment_index(armor.armor_slot))
		if not p_actor_stats.can_replace_source_modifiers(
			definition.id,
			modifier_instance_id,
			definition.stat_modifiers,
		):
			push_error("[InventoryLoadoutCoordinator] Invalid modifiers for %s" % definition.id)
			return false
		var minimum_affix_modifiers: Array[StatModifier] = definition.stat_modifiers.duplicate()
		var maximum_affix_modifiers: Array[StatModifier] = definition.stat_modifiers.duplicate()
		for affix in p_inventory_model.item_catalog.equipment_affixes:
			if affix == null or not affix.is_compatible_with(definition):
				continue
			_append_affix_definition_modifiers(minimum_affix_modifiers, affix, false)
			_append_affix_definition_modifiers(maximum_affix_modifiers, affix, true)
		if (
			not p_actor_stats.can_replace_source_modifiers(
				definition.id,
				modifier_instance_id,
				minimum_affix_modifiers,
			)
			or not p_actor_stats.can_replace_source_modifiers(
				definition.id,
				modifier_instance_id,
				maximum_affix_modifiers,
			)
		):
			push_error("[InventoryLoadoutCoordinator] Compatible affixes permit invalid modifiers for %s" % definition.id)
			return false
		if armor != null and armor.armor_set != null and not validated_armor_sets.has(armor.armor_set.id):
			validated_armor_sets[armor.armor_set.id] = true
			if not p_actor_stats.can_replace_source_modifiers(
				armor.armor_set.id,
				ARMOR_SET_INSTANCE_ID,
				armor.armor_set.full_set_modifiers,
			):
				push_error("[InventoryLoadoutCoordinator] Invalid full-set modifiers for %s" % armor.armor_set.id)
				return false
		var rune := definition as RuneDefinition
		if rune == null:
			continue
		if not p_actor_stats.can_replace_source_modifiers(
			RUNE_EFFECT_SOURCE_ID,
			RUNE_EFFECT_INSTANCE_ID,
			rune.socket_modifiers,
		):
			push_error("[InventoryLoadoutCoordinator] Invalid socket modifiers for %s" % rune.id)
			return false
	return true

func _append_affix_definition_modifiers(
	modifiers: Array[StatModifier],
	affix: EquipmentAffixDefinition,
	use_maximum: bool,
) -> void:
	for stat_roll in affix.stat_rolls:
		var modifier := StatModifier.new()
		modifier.stat_id = stat_roll.stat_id
		modifier.operation = stat_roll.operation
		modifier.amount = stat_roll.maximum_amount if use_maximum else stat_roll.minimum_amount
		modifiers.append(modifier)

func _prepare_stat_projection(
	candidate,
	p_inventory_model: InventoryModel,
	p_actor_stats: ActorStats,
	force_full: bool = false,
	loadout_bound: bool = true,
) -> PreparedStatModifierChange:
	var replacements: Array[StatModifierReplacementType] = []
	var ratio_sources: Array[StringName] = []
	var selected_projection := _get_selected_projection(candidate, p_inventory_model.item_catalog)
	var current_selected_projection := _get_selected_projection(p_inventory_model, p_inventory_model.item_catalog)
	if force_full or selected_projection["fingerprint"] != current_selected_projection["fingerprint"]:
		replacements.append(StatModifierReplacementType.new(
			selected_projection["source_id"],
			SELECTED_ITEM_INSTANCE_ID,
			selected_projection["modifiers"],
		))
	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		var equipment_index := InventoryModel.get_equipment_index(armor_slot)
		var equipment_instance_id := _get_equipment_instance_id(equipment_index)
		var equipment_projection := _get_equipment_projection(candidate, p_inventory_model.item_catalog, armor_slot)
		var current_equipment_projection := _get_equipment_projection(p_inventory_model, p_inventory_model.item_catalog, armor_slot)
		if equipment_projection.is_empty() or current_equipment_projection.is_empty():
			return null
		if force_full or equipment_projection["fingerprint"] != current_equipment_projection["fingerprint"]:
			replacements.append(StatModifierReplacementType.new(
				equipment_projection["source_id"],
				equipment_instance_id,
				equipment_projection["modifiers"],
			))
	var armor_set_projection := _get_armor_set_projection(candidate, p_inventory_model.item_catalog)
	var current_armor_set_projection := _get_armor_set_projection(p_inventory_model, p_inventory_model.item_catalog)
	if force_full or armor_set_projection["fingerprint"] != current_armor_set_projection["fingerprint"]:
		replacements.append(StatModifierReplacementType.new(
			armor_set_projection["source_id"],
			ARMOR_SET_INSTANCE_ID,
			armor_set_projection["modifiers"],
		))
	var rune_projection := _get_active_rune_modifiers(candidate, p_inventory_model.item_catalog)
	var current_rune_projection := _get_active_rune_modifiers(p_inventory_model, p_inventory_model.item_catalog)
	if rune_projection.is_empty() or current_rune_projection.is_empty():
		return null
	if force_full or rune_projection["fingerprint"] != current_rune_projection["fingerprint"]:
		replacements.append(StatModifierReplacementType.new(
			RUNE_EFFECT_SOURCE_ID,
			RUNE_EFFECT_INSTANCE_ID,
			rune_projection["modifiers"],
		))
		ratio_sources.append(RUNE_EFFECT_INSTANCE_ID)
	if replacements.is_empty():
		return p_actor_stats.prepare_noop_change()
	if loadout_bound:
		return p_actor_stats._prepare_loadout_modifier_sources(replacements, ratio_sources)
	return p_actor_stats.prepare_modifier_sources(replacements, ratio_sources)

func _get_selected_projection(candidate, item_catalog: ItemCatalog) -> Dictionary:
	var source_id := SELECTED_ITEM_INSTANCE_ID
	var modifiers: Array[StatModifier] = []
	var stack := candidate.get_selected_data() as InventoryStack
	if stack != null:
		var definition := item_catalog.get_definition(stack.item_id)
		if definition.stat_modifier_activation == ItemDefinition.StatModifierActivation.SELECTED:
			source_id = definition.id
			modifiers = _get_stack_modifiers(stack, item_catalog)
	return {
		"source_id": source_id,
		"modifiers": modifiers,
		"fingerprint": _get_modifier_projection_fingerprint(source_id, modifiers, _get_stack_instance_id(stack)),
	}

func _get_equipment_projection(candidate, item_catalog: ItemCatalog, armor_slot: int) -> Dictionary:
	var equipment_index := InventoryModel.get_equipment_index(armor_slot)
	var source_id := _get_equipment_instance_id(equipment_index)
	var modifiers: Array[StatModifier] = []
	var stack := candidate.get_slot(equipment_index) as InventoryStack
	if stack != null:
		var armor := item_catalog.get_definition(stack.item_id) as ArmorDefinition
		if armor == null or armor.armor_slot != armor_slot:
			return {}
		source_id = armor.id
		modifiers = _get_stack_modifiers(stack, item_catalog)
	return {
		"source_id": source_id,
		"modifiers": modifiers,
		"fingerprint": _get_modifier_projection_fingerprint(source_id, modifiers, _get_stack_instance_id(stack)),
	}

func _get_armor_set_projection(candidate, item_catalog: ItemCatalog) -> Dictionary:
	var source_id := ARMOR_SET_INSTANCE_ID
	var modifiers: Array[StatModifier] = []
	var armor_set := _get_complete_armor_set(candidate, item_catalog)
	if armor_set != null:
		source_id = armor_set.id
		modifiers = armor_set.full_set_modifiers
	return {
		"source_id": source_id,
		"modifiers": modifiers,
		"fingerprint": _get_modifier_projection_fingerprint(source_id, modifiers),
	}

func _get_modifier_projection_fingerprint(
	source_id: StringName,
	modifiers: Array[StatModifier],
	instance_id: int = 0,
) -> String:
	var encoded: Array[Dictionary] = []
	for modifier in modifiers:
		if modifier == null:
			encoded.append({})
			continue
		encoded.append({
			"stat_id": String(modifier.stat_id),
			"operation": modifier.operation,
			"amount": modifier.amount,
			"duration_seconds": modifier.duration_seconds,
		})
	return "%s:%d:%s" % [source_id, instance_id, JSON.stringify(encoded)]

func _get_stack_instance_id(stack: InventoryStack) -> int:
	return 0 if stack == null or stack.equipment_instance == null else stack.equipment_instance.instance_id

func _get_stack_modifiers(stack: InventoryStack, item_catalog: ItemCatalog) -> Array[StatModifier]:
	var modifiers: Array[StatModifier] = []
	if stack == null:
		return modifiers
	var definition := item_catalog.get_definition(stack.item_id)
	modifiers.append_array(definition.stat_modifiers)
	if stack.equipment_instance != null:
		for affix in stack.equipment_instance.affixes:
			for stat_roll in affix.stat_rolls:
				var modifier := StatModifier.new()
				modifier.stat_id = stat_roll.stat_id
				modifier.operation = stat_roll.operation
				modifier.amount = stat_roll.amount
				modifiers.append(modifier)
	return modifiers

func _get_complete_armor_set(candidate, item_catalog: ItemCatalog) -> ArmorSetDefinition:
	var armor_set: ArmorSetDefinition
	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		var stack := candidate.get_slot(InventoryModel.get_equipment_index(armor_slot)) as InventoryStack
		if stack == null:
			return null
		var armor := item_catalog.get_definition(stack.item_id) as ArmorDefinition
		if armor == null or armor.armor_set == null:
			return null
		if armor_set == null:
			armor_set = armor.armor_set
		elif armor.armor_set != armor_set:
			return null
	return armor_set

func _get_active_rune_modifiers(candidate, item_catalog: ItemCatalog) -> Dictionary:
	var rune_ids: Array[StringName] = []
	var selected_stack := candidate.get_selected_data() as InventoryStack
	if selected_stack != null:
		var selected_definition := item_catalog.get_definition(selected_stack.item_id)
		if _is_weapon(selected_definition, item_catalog):
			_append_socketed_rune_ids(selected_stack, rune_ids)
	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		var equipment_stack := candidate.get_slot(InventoryModel.get_equipment_index(armor_slot)) as InventoryStack
		if equipment_stack != null:
			_append_socketed_rune_ids(equipment_stack, rune_ids)
	var modifiers: Array[StatModifier] = []
	for rune_id in rune_ids:
		if not item_catalog.has_definition(rune_id):
			return {}
		var rune := item_catalog.get_definition(rune_id) as RuneDefinition
		if rune == null:
			return {}
		modifiers.append_array(rune.socket_modifiers)
	return {
		"modifiers": modifiers,
		"fingerprint": _get_modifier_projection_fingerprint(RUNE_EFFECT_SOURCE_ID, modifiers),
	}

func _append_socketed_rune_ids(stack: InventoryStack, rune_ids: Array[StringName]) -> void:
	if stack.equipment_instance == null:
		return
	for rune_id in stack.equipment_instance.socketed_rune_ids:
		if not rune_id.is_empty():
			rune_ids.append(rune_id)

func _get_equipment_instance_id(equipment_index: int) -> StringName:
	return StringName("equipment_slot_%d" % (equipment_index - InventoryModel.FILLABLE_SIZE))

func _get_reserved_stat_source_instance_ids() -> Array[StringName]:
	var source_instance_ids: Array[StringName] = [
		SELECTED_ITEM_INSTANCE_ID,
		ARMOR_SET_INSTANCE_ID,
		RUNE_EFFECT_INSTANCE_ID,
	]
	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		source_instance_ids.append(_get_equipment_instance_id(InventoryModel.get_equipment_index(armor_slot)))
	return source_instance_ids

func _is_weapon(definition: ItemDefinition, item_catalog: ItemCatalog) -> bool:
	if definition == null or definition.equipment_type == null or not item_catalog.has_equipment_type(&"weapon"):
		return false
	return definition.equipment_type.is_or_inherits(item_catalog.get_equipment_type(&"weapon"))
