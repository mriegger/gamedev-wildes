extends RefCounted
class_name LevelLootCatalogValidator

static func validate(level_catalog: LevelCatalog, item_catalog: ItemCatalog, chest_slot_count: int) -> bool:
	if level_catalog == null or item_catalog == null or not level_catalog.validate():
		return false
	if chest_slot_count <= 0:
		push_error("[LevelLootCatalogValidator] Chest slot count must be positive")
		return false
	var valid := true
	var bundles_by_id: Dictionary = {}
	var reward_ids: Dictionary = {}
	for level in level_catalog.levels:
		if level == null:
			continue
		if level.one_time_chest_reward != null:
			var reward := level.one_time_chest_reward
			if reward_ids.has(reward.reward_id):
				push_error("[LevelLootCatalogValidator] Duplicate one-time reward ID %s for %s" % [reward.reward_id, level.level_id])
				valid = false
			else:
				reward_ids[reward.reward_id] = true
			valid = _validate_bundle(reward.loot_bundle, level.level_id, item_catalog, chest_slot_count, bundles_by_id) and valid
		for requirement in level.room_requirements:
			if requirement == null or requirement.chest_loot_bundle == null:
				continue
			valid = _validate_bundle(requirement.chest_loot_bundle, level.level_id, item_catalog, chest_slot_count, bundles_by_id) and valid
	return valid

static func _validate_bundle(
	bundle: LootBundleDefinition,
	level_id: StringName,
	item_catalog: ItemCatalog,
	chest_slot_count: int,
	bundles_by_id: Dictionary,
) -> bool:
	if bundle == null:
		return false
	if bundles_by_id.has(bundle.id):
		if bundles_by_id[bundle.id] != bundle:
			push_error("[LevelLootCatalogValidator] Non-canonical loot bundle %s for %s" % [bundle.id, level_id])
			return false
		return true
	bundles_by_id[bundle.id] = bundle
	var valid := true
	if bundle.max_rewards > chest_slot_count:
		push_error("[LevelLootCatalogValidator] Loot bundle %s exceeds chest capacity for %s" % [bundle.id, level_id])
		valid = false
	return LootCatalogValidator.validate_bundle(bundle, item_catalog) and valid
