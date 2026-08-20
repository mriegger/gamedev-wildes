extends SceneTree

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	if block_catalog == null or item_catalog == null or not item_catalog.validate(block_catalog):
		quit(1)
		return
	var valid_entry := _entry(&"fixed", _drop(item_catalog.get_definition(&"copper")))
	var valid_choice := _choice(&"candidate", 1.0, _drop(item_catalog.get_definition(&"sand_block")))
	var malformed: Array[LootBundleDefinition] = []
	malformed.append(_bundle(&"", 1, _entries([valid_entry]), []))
	malformed.append(_bundle(&"zero_max", 0, _entries([valid_entry]), []))
	malformed.append(_bundle(&"empty", 1, [], []))
	malformed.append(_bundle(&"fixed_over_max", 1, _entries([valid_entry, _entry(&"second", _drop(item_catalog.get_definition(&"dirt_block")))]), []))
	malformed.append(_bundle(&"unreachable_max", 3, _entries([valid_entry]), _choices([valid_choice])))
	malformed.append(_bundle(&"dead_candidate", 1, _entries([valid_entry]), _choices([valid_choice])))
	malformed.append(_bundle(&"null_fixed", 1, _entries([null]), []))
	malformed.append(_bundle(&"null_candidate", 1, [], _choices([null])))
	malformed.append(_bundle(&"duplicate", 2, _entries([valid_entry]), _choices([_choice(&"fixed", 1.0, _drop(item_catalog.get_definition(&"sand_block")))])))
	malformed.append(_bundle(&"invalid_weight", 1, [], _choices([_choice(&"candidate", INF, _drop(item_catalog.get_definition(&"sand_block")))])))
	for bundle in malformed:
		if bundle.validate():
			quit(1)
			return
	var noncanonical_item := item_catalog.get_definition(&"copper").duplicate() as ItemDefinition
	var noncanonical := _bundle(
		&"noncanonical",
		1,
		_entries([_entry(&"fixed", _drop(noncanonical_item))]),
		[],
	)
	if LootCatalogValidator.validate_bundle(noncanonical, item_catalog):
		quit(1)
		return
	print("LOOT_BUNDLE_MALFORMED PASS")
	quit(0)

func _bundle(
	id: StringName,
	max_rewards: int,
	fixed_entries: Array[LootBundleEntryDefinition],
	weighted_candidates: Array[LootWeightedChoiceDefinition],
) -> LootBundleDefinition:
	var bundle := LootBundleDefinition.new()
	bundle.id = id
	bundle.max_rewards = max_rewards
	bundle.fixed_entries = fixed_entries
	bundle.weighted_candidates = weighted_candidates
	return bundle

func _entry(id: StringName, drop: LootDropDefinition) -> LootBundleEntryDefinition:
	var entry := LootBundleEntryDefinition.new()
	entry.id = id
	entry.drop = drop
	return entry

func _choice(id: StringName, weight: float, drop: LootDropDefinition) -> LootWeightedChoiceDefinition:
	var choice := LootWeightedChoiceDefinition.new()
	choice.id = id
	choice.weight = weight
	choice.drop = drop
	return choice

func _drop(item: ItemDefinition) -> LootDropDefinition:
	var drop := LootDropDefinition.new()
	drop.item = item
	return drop

func _entries(values: Array) -> Array[LootBundleEntryDefinition]:
	var result: Array[LootBundleEntryDefinition] = []
	result.assign(values)
	return result

func _choices(values: Array) -> Array[LootWeightedChoiceDefinition]:
	var result: Array[LootWeightedChoiceDefinition] = []
	result.assign(values)
	return result
