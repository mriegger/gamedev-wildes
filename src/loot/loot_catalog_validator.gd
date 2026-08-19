extends RefCounted
class_name LootCatalogValidator

static func validate_entity_catalog(entity_catalog: EntityCatalog, item_catalog: ItemCatalog) -> bool:
	if entity_catalog == null or item_catalog == null or not entity_catalog.validate():
		return false
	var valid := true
	var pools_by_id: Dictionary = {}
	for entity in entity_catalog.definitions:
		if entity == null or entity.loot_pool == null:
			continue
		var pool := entity.loot_pool
		if pools_by_id.has(pool.id):
			if pools_by_id[pool.id] != pool:
				push_error("[LootCatalogValidator] Non-canonical loot pool %s for %s" % [pool.id, entity.id])
				valid = false
			continue
		pools_by_id[pool.id] = pool
		valid = validate(pool, item_catalog) and valid
	return valid

static func validate(pool: LootPoolDefinition, item_catalog: ItemCatalog) -> bool:
	if pool == null or item_catalog == null or not pool.validate():
		return false
	var valid := true
	for roll in pool.independent_rolls:
		valid = _validate_drop(roll.drop, item_catalog, "independent roll %s" % roll.id) and valid
	for group in pool.exclusive_groups:
		for choice in group.choices:
			valid = _validate_drop(
				choice.drop,
				item_catalog,
				"exclusive group %s choice %s" % [group.id, choice.id],
			) and valid
	return valid

static func _validate_drop(drop: LootDropDefinition, item_catalog: ItemCatalog, source: String) -> bool:
	if drop == null or drop.item == null:
		return false
	var valid := true
	if (
		not item_catalog.has_definition(drop.item.id)
		or item_catalog.get_definition(drop.item.id) != drop.item
	):
		push_error("[LootCatalogValidator] Non-canonical item %s in %s" % [drop.item.id, source])
		valid = false
	var equipment_roll := drop.equipment_roll
	if equipment_roll == null:
		return valid
	for affix in equipment_roll.fixed_affixes:
		valid = _validate_affix(affix, item_catalog, source) and valid
	for choice in equipment_roll.random_affixes:
		if choice != null:
			valid = _validate_affix(choice.affix, item_catalog, source) and valid
	var fixed_rune_ids: Array[StringName] = []
	for rune in equipment_roll.fixed_runes:
		if rune != null:
			fixed_rune_ids.append(rune.id)
		valid = _validate_rune(rune, item_catalog, source) and valid
	if not fixed_rune_ids.is_empty() and not item_catalog.is_valid_socket_loadout(drop.item.id, fixed_rune_ids):
		push_error("[LootCatalogValidator] Invalid fixed rune loadout in %s" % source)
		valid = false
	for choice in equipment_roll.random_runes:
		if choice == null:
			continue
		valid = _validate_rune(choice.rune, item_catalog, source) and valid
		if choice.rune != null:
			var candidate_ids: Array[StringName] = []
			for _slot_index in range(equipment_roll.random_rune_slot_count):
				candidate_ids.append(choice.rune.id)
			if not item_catalog.is_valid_socket_loadout(drop.item.id, candidate_ids):
				push_error("[LootCatalogValidator] Invalid random rune %s in %s" % [choice.rune.id, source])
				valid = false
	return valid

static func _validate_affix(
	affix: EquipmentAffixDefinition,
	item_catalog: ItemCatalog,
	source: String,
) -> bool:
	if (
		affix == null
		or not item_catalog.has_equipment_affix(affix.id)
		or item_catalog.get_equipment_affix(affix.id) != affix
	):
		var affix_id: StringName = &"" if affix == null else affix.id
		push_error("[LootCatalogValidator] Non-canonical equipment affix %s in %s" % [affix_id, source])
		return false
	return true

static func _validate_rune(rune: RuneDefinition, item_catalog: ItemCatalog, source: String) -> bool:
	if (
		rune == null
		or not item_catalog.has_definition(rune.id)
		or item_catalog.get_definition(rune.id) != rune
	):
		var rune_id: StringName = &"" if rune == null else rune.id
		push_error("[LootCatalogValidator] Non-canonical rune %s in %s" % [rune_id, source])
		return false
	return true
