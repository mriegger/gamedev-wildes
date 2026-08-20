extends SceneTree

var _errors: Array[String] = []
var _item_catalog: ItemCatalog

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	_item_catalog = load("res://items/item_catalog.tres") as ItemCatalog
	_expect(block_catalog != null and block_catalog.validate(), "block catalog invalid")
	_expect(_item_catalog != null and _item_catalog.validate(block_catalog), "item catalog invalid")
	_test_candidate_only_bounds()
	_test_fixed_entries_and_stack_counts()
	_test_distinct_weighted_selection()
	_test_definition_order_invariance()
	_test_equipment_variants_and_allocator_atomicity()
	_test_parallel_preparations()
	_test_malformed_definitions()
	_finish()

func _test_candidate_only_bounds() -> void:
	var bundle := _bundle(
		&"candidate_only",
		3,
		[],
		_choices([
			_choice(&"copper", 1.0, _drop(&"copper")),
			_choice(&"dirt", 1.0, _drop(&"dirt_block")),
			_choice(&"sand", 1.0, _drop(&"sand_block")),
		]),
	)
	_expect(bundle.validate(), "candidate-only bundle invalid")
	_expect(LootCatalogValidator.validate_bundle(bundle, _item_catalog), "candidate-only bundle is not canonical")
	var observed_counts: Dictionary = {}
	for seed in range(300):
		var drops := _resolve(bundle, seed, EquipmentInstanceFactory.new(_item_catalog))
		_expect(drops.size() >= 1 and drops.size() <= 3, "candidate-only reward count left 1..max")
		observed_counts[drops.size()] = true
		_expect(_unique_item_count(drops) == drops.size(), "candidate repeated within one bundle")
	_expect(observed_counts.size() == 3, "candidate-only rewards did not reach every count from 1..max")

func _test_fixed_entries_and_stack_counts() -> void:
	var bundle := _bundle(
		&"fixed_and_weighted",
		4,
		_entries([
			_entry(&"guaranteed_copper", _drop(&"copper", 5, 5)),
			_entry(&"guaranteed_rune", _drop(&"basic_rune")),
		]),
		_choices([
			_choice(&"dirt", 1.0, _drop(&"dirt_block")),
			_choice(&"sand", 1.0, _drop(&"sand_block")),
		]),
	)
	var observed_counts: Dictionary = {}
	for seed in range(300):
		var drops := _resolve(bundle, seed, EquipmentInstanceFactory.new(_item_catalog))
		observed_counts[drops.size()] = true
		_expect(drops.size() >= 2 and drops.size() <= 4, "fixed bundle reward count ignored fixed-entry minimum")
		_expect(_stack_count(drops, &"copper") == 5, "guaranteed material stack count changed")
		_expect(_stack_count(drops, &"basic_rune") == 1, "guaranteed rune was omitted")
	_expect(observed_counts.size() == 3, "fixed bundle did not reach fixed_count..max")
	var one_stack := _bundle(
		&"stack_count",
		1,
		_entries([_entry(&"copper_stack", _drop(&"copper", 7, 7))]),
		[],
	)
	var resolved := _resolve(one_stack, 4, EquipmentInstanceFactory.new(_item_catalog))
	_expect(resolved.size() == 1 and resolved[0].count == 7, "max_rewards counted units instead of resolved entries")

func _test_distinct_weighted_selection() -> void:
	var bundle := _bundle(
		&"without_replacement",
		3,
		[],
		_choices([
			_choice(&"likely", 1000.0, _drop(&"copper")),
			_choice(&"dirt", 1.0, _drop(&"dirt_block")),
			_choice(&"sand", 1.0, _drop(&"sand_block")),
		]),
	)
	var three_reward_seed := -1
	for seed in range(100):
		var drops := _resolve(bundle, seed, EquipmentInstanceFactory.new(_item_catalog))
		if drops.size() == 3:
			three_reward_seed = seed
			_expect(_unique_item_count(drops) == 3, "weighted candidate repeated after selection")
			break
	_expect(three_reward_seed >= 0, "no three-reward seed found for without-replacement test")

func _test_definition_order_invariance() -> void:
	var copper := _entry(&"fixed_copper", _drop(&"copper", 2, 4))
	var rune := _entry(&"fixed_rune", _drop(&"basic_rune"))
	var dirt := _choice(&"dirt", 2.0, _drop(&"dirt_block"))
	var sword := _choice(&"sword", 1.0, _drop(&"copper_sword"))
	var first := _bundle(
		&"stable_bundle",
		4,
		_entries([copper, rune]),
		_choices([dirt, sword]),
	)
	var reordered := _bundle(
		&"stable_bundle",
		4,
		_entries([rune, copper]),
		_choices([sword, dirt]),
	)
	for seed in range(100):
		var first_result := _resolve(first, seed, EquipmentInstanceFactory.new(_item_catalog, 50))
		var second_result := _resolve(reordered, seed, EquipmentInstanceFactory.new(_item_catalog, 50))
		_expect(_encode(first_result) == _encode(second_result), "bundle definition order changed deterministic output")

func _test_equipment_variants_and_allocator_atomicity() -> void:
	var equipment_roll := LootEquipmentRollDefinition.new()
	equipment_roll.fixed_affixes = _affixes([_item_catalog.get_equipment_affix(&"vicious")])
	equipment_roll.fixed_runes = _runes([_item_catalog.get_definition(&"basic_rune") as RuneDefinition])
	var bundle := _bundle(
		&"equipment_bundle",
		1,
		_entries([_entry(&"runed_sword", _drop(&"copper_sword", 1, 1, equipment_roll))]),
		[],
	)
	_expect(bundle.validate(), "equipment bundle invalid")
	_expect(LootCatalogValidator.validate_bundle(bundle, _item_catalog), "equipment bundle variants are not canonical")
	var factory := EquipmentInstanceFactory.new(_item_catalog, 90)
	var prepared := LootResolver.prepare_bundle(bundle, 17, factory)
	_expect(prepared != null, "equipment bundle did not prepare")
	_expect(factory.get_next_instance_id() == 90, "bundle preparation changed the root allocator")
	if prepared != null:
		var stack := prepared.get_drops()[0]
		_expect(stack.equipment_instance != null and stack.equipment_instance.instance_id == 90, "equipment bundle used the wrong pending instance ID")
		_expect(stack.equipment_instance.affixes[0].affix_id == &"vicious", "fixed equipment affix changed")
		_expect(stack.equipment_instance.socketed_rune_ids == _ids([&"basic_rune"]), "fixed equipment rune changed")
		_expect(LootResolver._commit(prepared, factory), "prepared equipment bundle did not commit")
		_expect(factory.get_next_instance_id() == 91, "equipment bundle did not advance allocator exactly once")
	var two_swords := _bundle(
		&"exhausted_bundle",
		2,
		_entries([
			_entry(&"first", _drop(&"copper_sword")),
			_entry(&"second", _drop(&"copper_sword")),
		]),
		[],
	)
	var exhausted_factory := EquipmentInstanceFactory.new(_item_catalog, EquipmentInstance.MAXIMUM_INSTANCE_ID)
	_expect(LootResolver.prepare_bundle(two_swords, 3, exhausted_factory) == null, "partially allocatable bundle prepared")
	_expect(exhausted_factory.get_next_instance_id() == EquipmentInstance.MAXIMUM_INSTANCE_ID, "failed bundle consumed an equipment ID")

func _test_parallel_preparations() -> void:
	var bundle := _bundle(
		&"parallel_bundle",
		1,
		_entries([_entry(&"sword", _drop(&"copper_sword"))]),
		[],
	)
	var factory := EquipmentInstanceFactory.new(_item_catalog, 300)
	var first := LootResolver.prepare_bundle(bundle, 11, factory)
	var second := LootResolver.prepare_bundle(bundle, 11, factory)
	_expect(first != null and second != null, "parallel bundle resolutions were not prepared")
	if first == null or second == null:
		return
	_expect(LootResolver._can_commit(first, factory), "first bundle preparation was not committable")
	_expect(LootResolver._can_commit(second, factory), "second bundle preparation was not initially committable")
	_expect(LootResolver._commit(first, factory), "first bundle preparation did not commit")
	_expect(not LootResolver._commit(second, factory), "stale bundle preparation committed")
	_expect(not LootResolver._commit(first, factory), "bundle preparation replayed")
	var foreign := EquipmentInstanceFactory.new(_item_catalog, 300)
	_expect(not LootResolver._commit(second, foreign), "bundle preparation committed against a foreign allocator")

func _test_malformed_definitions() -> void:
	var output: Array = []
	var exit_code := OS.execute(
		OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://loot/tests/loot_bundle_malformed_probe.gd"],
		output,
		true,
	)
	var probe_output := "\n".join(PackedStringArray(output))
	_expect(exit_code == 0, "malformed bundle probe exited %d" % exit_code)
	_expect(probe_output.contains("LOOT_BUNDLE_MALFORMED PASS"), "malformed bundle definitions were accepted")

func _resolve(
	bundle: LootBundleDefinition,
	seed: int,
	factory: EquipmentInstanceFactory,
) -> Array[InventoryStack]:
	var prepared := LootResolver.prepare_bundle(bundle, seed, factory)
	if prepared == null or not LootResolver._commit(prepared, factory):
		return []
	return prepared.get_drops()

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

func _drop(
	item_id: StringName,
	minimum_count: int = 1,
	maximum_count: int = 1,
	equipment_roll: LootEquipmentRollDefinition = null,
) -> LootDropDefinition:
	var drop := LootDropDefinition.new()
	drop.item = _item_catalog.get_definition(item_id)
	drop.minimum_count = minimum_count
	drop.maximum_count = maximum_count
	drop.equipment_roll = equipment_roll
	return drop

func _encode(drops: Array[InventoryStack]) -> Array[Dictionary]:
	var encoded: Array[Dictionary] = []
	for stack in drops:
		encoded.append(stack.to_dict())
	return encoded

func _stack_count(drops: Array[InventoryStack], item_id: StringName) -> int:
	for stack in drops:
		if stack.item_id == item_id:
			return stack.count
	return 0

func _unique_item_count(drops: Array[InventoryStack]) -> int:
	var item_ids: Dictionary = {}
	for stack in drops:
		item_ids[stack.item_id] = true
	return item_ids.size()

func _entries(values: Array) -> Array[LootBundleEntryDefinition]:
	var result: Array[LootBundleEntryDefinition] = []
	result.assign(values)
	return result

func _choices(values: Array) -> Array[LootWeightedChoiceDefinition]:
	var result: Array[LootWeightedChoiceDefinition] = []
	result.assign(values)
	return result

func _affixes(values: Array) -> Array[EquipmentAffixDefinition]:
	var result: Array[EquipmentAffixDefinition] = []
	result.assign(values)
	return result

func _runes(values: Array) -> Array[RuneDefinition]:
	var result: Array[RuneDefinition] = []
	result.assign(values)
	return result

func _ids(values: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(values)
	return result

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)

func _finish() -> void:
	if _errors.is_empty():
		print("LOOT_BUNDLE_SYSTEM PASS")
		quit(0)
		return
	for message in _errors:
		push_error(message)
	print("LOOT_BUNDLE_SYSTEM FAIL count=%d" % _errors.size())
	quit(1)
