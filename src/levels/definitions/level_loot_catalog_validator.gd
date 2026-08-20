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
	var pools_by_id: Dictionary = {}
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
			if requirement == null or requirement.chest_loot_pool == null:
				continue
			valid = _validate_pool(requirement.chest_loot_pool, level.level_id, item_catalog, chest_slot_count, pools_by_id) and valid
			if requirement.post_first_completion_chest_loot_pool != null:
				valid = _validate_pool(requirement.post_first_completion_chest_loot_pool, level.level_id, item_catalog, chest_slot_count, pools_by_id) and valid
	return valid

static func validate_chest_pool(
	pool: LootPoolDefinition,
	item_catalog: ItemCatalog,
	chest_slot_count: int,
) -> bool:
	if pool == null or item_catalog == null:
		return false
	var valid := true
	if chest_slot_count <= 0:
		push_error("[LevelLootCatalogValidator] Chest slot count must be positive")
		valid = false
	var maximum_drop_count := 0
	var has_guaranteed_drop := false
	for roll in pool.independent_rolls:
		if roll != null and roll.chance > 0.0:
			maximum_drop_count += 1
		if roll != null and roll.chance == 1.0:
			has_guaranteed_drop = true
	for group in pool.exclusive_groups:
		if group != null and group.chance > 0.0:
			maximum_drop_count += 1
		if group != null and group.chance == 1.0:
			has_guaranteed_drop = true
	if chest_slot_count > 0 and maximum_drop_count > chest_slot_count:
		push_error("[LevelLootCatalogValidator] Loot pool %s exceeds chest capacity" % pool.id)
		valid = false
	if not has_guaranteed_drop:
		push_error("[LevelLootCatalogValidator] Loot pool %s has no guaranteed drop" % pool.id)
		valid = false
	return LootCatalogValidator.validate(pool, item_catalog) and valid

static func _validate_pool(
	pool: LootPoolDefinition,
	level_id: StringName,
	item_catalog: ItemCatalog,
	chest_slot_count: int,
	pools_by_id: Dictionary,
) -> bool:
	if pool == null:
		return false
	if pools_by_id.has(pool.id):
		if pools_by_id[pool.id] != pool:
			push_error("[LevelLootCatalogValidator] Non-canonical loot pool %s for %s" % [pool.id, level_id])
			return false
		return true
	pools_by_id[pool.id] = pool
	return validate_chest_pool(pool, item_catalog, chest_slot_count)

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
