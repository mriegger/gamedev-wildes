extends EntityDefinition
class_name BirdEntityDefinition

@export_range(-1, BirdColorVariant.Type.OWL, 1) var color_variant_override: int = -1
@export var color_variant_loot_pools: Array[LootPoolDefinition] = []

func validate(source: String) -> bool:
	var valid := super.validate(source)
	if color_variant_override < -1 or color_variant_override >= BirdColorVariant.COUNT:
		push_error("[BirdEntityDefinition] Invalid color variant override at %s" % source)
		valid = false
	if not color_variant_loot_pools.is_empty() and color_variant_loot_pools.size() != BirdColorVariant.COUNT:
		push_error("[BirdEntityDefinition] Color variant loot pool count mismatch at %s" % source)
		valid = false
	for pool in color_variant_loot_pools:
		if pool != null and not pool.validate():
			valid = false
	return valid

func get_color_variant(seed_value: int) -> BirdColorVariant.Type:
	if color_variant_override >= 0:
		return color_variant_override as BirdColorVariant.Type
	return BirdColorVariant.common_for_seed(seed_value)

func resolve_loot_pool(behavior_seed: int) -> LootPoolDefinition:
	if color_variant_loot_pools.is_empty():
		return super.resolve_loot_pool(behavior_seed)
	return color_variant_loot_pools[get_color_variant(behavior_seed)]

func get_loot_pools() -> Array[LootPoolDefinition]:
	var pools := super.get_loot_pools()
	for pool in color_variant_loot_pools:
		if pool != null and pool not in pools:
			pools.append(pool)
	return pools
