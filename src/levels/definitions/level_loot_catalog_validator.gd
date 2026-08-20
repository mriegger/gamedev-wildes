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
	for level in level_catalog.levels:
		if level == null:
			continue
		for requirement in level.room_requirements:
			if requirement == null or requirement.chest_loot_bundle == null:
				continue
			var bundle := requirement.chest_loot_bundle
			if bundles_by_id.has(bundle.id):
				if bundles_by_id[bundle.id] != bundle:
					push_error("[LevelLootCatalogValidator] Non-canonical loot bundle %s for %s" % [bundle.id, level.level_id])
					valid = false
				continue
			bundles_by_id[bundle.id] = bundle
			if bundle.max_rewards > chest_slot_count:
				push_error("[LevelLootCatalogValidator] Loot bundle %s exceeds chest capacity for %s" % [bundle.id, level.level_id])
				valid = false
			valid = LootCatalogValidator.validate_bundle(bundle, item_catalog) and valid
	return valid
