extends SceneTree

var _errors: Array[String] = []
var _block_catalog: BlockCatalog
var _item_catalog: ItemCatalog

func _init() -> void:
	_block_catalog = load("res://blocks/block_catalog.tres") as BlockCatalog
	_item_catalog = load("res://items/item_catalog.tres") as ItemCatalog
	_test_catalog_and_zombie_configuration()
	_test_stone_post_completion_chest_pool()
	_test_golden_keyed_random()
	_test_order_and_unrelated_content_invariance()
	_test_exclusive_groups()
	_test_random_equipment_rolls()
	_test_fixed_equipment_rolls()
	_test_allocator_atomicity()
	_test_parallel_allocator_preparations()
	_test_malformed_definitions()
	_test_zombie_distribution()
	_finish()

func _test_catalog_and_zombie_configuration() -> void:
	var entity_catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	var zombie_pool := load("res://loot/pools/zombie.tres") as LootPoolDefinition
	_expect(_block_catalog != null and _block_catalog.validate(), "block catalog invalid")
	_expect(_item_catalog != null and _item_catalog.validate(_block_catalog), "item catalog invalid")
	_expect(entity_catalog != null and entity_catalog.validate(), "entity catalog invalid")
	_expect(zombie_pool != null and zombie_pool.validate(), "zombie loot pool invalid")
	_expect(LootCatalogValidator.validate(zombie_pool, _item_catalog), "zombie loot pool references invalid content")
	_expect(LootCatalogValidator.validate_entity_catalog(entity_catalog, _item_catalog), "entity loot pools reference invalid content")
	var feather_pools: Dictionary = {
		&"black_feather": load("res://loot/pools/bird_black_feather.tres") as LootPoolDefinition,
		&"red_feather": load("res://loot/pools/bird_red_feather.tres") as LootPoolDefinition,
		&"blue_feather": load("res://loot/pools/bird_blue_feather.tres") as LootPoolDefinition,
	}
	for item_id in feather_pools:
		var feather_pool := feather_pools[item_id] as LootPoolDefinition
		_expect(_item_catalog.has_definition(item_id), "feather item %s is missing" % item_id)
		_expect(feather_pool != null and LootCatalogValidator.validate(feather_pool, _item_catalog), "feather loot pool %s is invalid" % item_id)
		if feather_pool != null:
			var feather_drops := _resolve(feather_pool, 1, EquipmentInstanceFactory.new(_item_catalog))
			_expect(feather_drops.size() == 1 and feather_drops[0].item_id == item_id and feather_drops[0].count == 1, "feather loot pool %s did not guarantee one matching feather" % item_id)
	if zombie_pool == null:
		return
	_expect(zombie_pool.id == &"zombie", "zombie loot pool ID mismatch")
	_expect(zombie_pool.independent_rolls.size() == 1, "zombie independent roll count mismatch")
	_expect(zombie_pool.exclusive_groups.size() == 1, "zombie exclusive group count mismatch")
	if zombie_pool.independent_rolls.size() == 1:
		var copper := zombie_pool.independent_rolls[0]
		_expect(copper.id == &"copper" and is_equal_approx(copper.chance, 0.75), "zombie copper chance mismatch")
		_expect(copper.drop.item == _item_catalog.get_definition(&"copper"), "zombie copper item is not canonical")
		_expect(copper.drop.minimum_count == 1 and copper.drop.maximum_count == 3, "zombie copper count mismatch")
	if zombie_pool.exclusive_groups.size() == 1:
		var gear := zombie_pool.exclusive_groups[0]
		_expect(gear.id == &"gear" and is_equal_approx(gear.chance, 0.17), "zombie gear group chance mismatch")
		var weights: Dictionary = {}
		for choice in gear.choices:
			weights[choice.id] = choice.weight
		_expect(weights == {&"plain_copper_sword": 10.0, &"rolled_runed_copper_sword": 4.0, &"stout_copper_helmet": 3.0}, "zombie gear weights mismatch")
		var rolled := _choice_by_id(gear, &"rolled_runed_copper_sword")
		if rolled != null:
			var equipment_roll := rolled.drop.equipment_roll
			_expect(equipment_roll.minimum_random_affix_count == 1 and equipment_roll.maximum_random_affix_count == 2, "zombie sword affix range mismatch")
			_expect(equipment_roll.random_affixes.size() == 2, "zombie sword affix candidates missing")
			_expect(equipment_roll.random_rune_slot_count == 1 and equipment_roll.random_runes.size() == 1, "zombie sword rune configuration changed")
			if equipment_roll.random_runes.size() == 1:
				_expect(equipment_roll.random_runes[0].rune == _item_catalog.get_definition(&"power_rune"), "zombie sword does not use the canonical Power Rune")
	_expect(_item_catalog.has_equipment_affix(&"nimble"), "second sword affix missing")
	_expect(_item_catalog.has_definition(&"power_rune"), "second weapon rune missing")
	_expect(_item_catalog.get_equipment_affix(&"nimble").is_compatible_with(_item_catalog.get_definition(&"copper_sword")), "Nimble rejected copper sword")
	_expect((_item_catalog.get_definition(&"power_rune") as RuneDefinition).is_compatible_with(_item_catalog.get_definition(&"copper_sword")), "Power Rune rejected copper sword")

func _test_stone_post_completion_chest_pool() -> void:
	var pool := load("res://levels/content/dungeons/stone/stone_post_completion_chest_loot.tres") as LootPoolDefinition
	_expect(pool != null and pool.validate(), "stone post-completion chest pool invalid")
	_expect(LootCatalogValidator.validate(pool, _item_catalog), "stone post-completion chest pool references invalid content")
	if pool == null:
		return
	var rolls: Dictionary = {}
	for roll in pool.independent_rolls:
		rolls[roll.id] = roll
	_expect(rolls.size() == 2 and rolls.has(&"pumpkin") and rolls.has(&"iron_pickaxe"), "stone post-completion chest rolls changed")
	if not rolls.has(&"pumpkin") or not rolls.has(&"iron_pickaxe"):
		return
	var pumpkin_roll := rolls[&"pumpkin"] as LootIndependentRollDefinition
	var iron_roll := rolls[&"iron_pickaxe"] as LootIndependentRollDefinition
	_expect(is_equal_approx(pumpkin_roll.chance, 1.0), "stone post-completion Pumpkin is not guaranteed")
	_expect(is_equal_approx(iron_roll.chance, 0.25), "stone post-completion Iron Pickaxe chance is not 25%")
	var saw_bonus := false
	var saw_no_bonus := false
	for seed in range(100):
		var drops := _resolve(pool, seed, EquipmentInstanceFactory.new(_item_catalog))
		var pumpkin_count := 0
		var iron_count := 0
		for stack in drops:
			if stack.item_id == &"pumpkin":
				pumpkin_count += stack.count
			elif stack.item_id == &"iron_pickaxe":
				iron_count += stack.count
			else:
				_expect(false, "stone post-completion chest resolved an unexpected item")
		var expected_bonus := LootKeyedRandom.unit(
			seed,
			pool.id,
			_path([&"independent", &"iron_pickaxe", &"chance"]),
		) < 0.25
		_expect(pumpkin_count >= 5 and pumpkin_count <= 10, "stone post-completion chest omitted its 5-10 Pumpkins")
		_expect(iron_count == (1 if expected_bonus else 0), "stone post-completion chest did not honor its keyed 25% Iron roll")
		saw_bonus = saw_bonus or iron_count == 1
		saw_no_bonus = saw_no_bonus or iron_count == 0
	_expect(saw_bonus and saw_no_bonus, "stone post-completion Iron roll did not cover both outcomes")

func _test_golden_keyed_random() -> void:
	var path := _path([&"independent", &"copper", &"chance"])
	var digest := LootKeyedRandom._digest_hex(927451, &"deterministic", path)
	var value := LootKeyedRandom.u53(927451, &"deterministic", path)
	var unit := LootKeyedRandom.unit(927451, &"deterministic", path)
	_expect(digest == "e8e58ff1f100aa99bf09d82c631a2f2817a94f182b329de4ebd58a7ddc52face", "keyed random SHA-256 golden vector changed")
	_expect(value == 2504206215872682, "keyed random u53 golden vector changed")
	_expect(is_equal_approx(unit, 0.27802273992712867), "keyed random unit golden vector changed")
	var seen: Dictionary = {}
	for seed in range(200):
		var rolled := LootKeyedRandom.integer_inclusive(seed, &"range", _path([&"count"]), 2, 7)
		_expect(rolled >= 2 and rolled <= 7, "rejection-sampled integer left its range")
		seen[rolled] = true
	_expect(seen.size() == 6, "rejection-sampled integer did not cover its range")

func _test_order_and_unrelated_content_invariance() -> void:
	var copper := _independent(&"copper", 1.0, _drop(_item_catalog.get_definition(&"copper"), 2, 4))
	var fixed_roll := LootEquipmentRollDefinition.new()
	fixed_roll.fixed_affixes = _affixes([_item_catalog.get_equipment_affix(&"vicious")])
	fixed_roll.fixed_runes = _runes([_item_catalog.get_definition(&"basic_rune") as RuneDefinition])
	var plain := _choice(&"plain", 2.0, _drop(_item_catalog.get_definition(&"copper_sword")))
	var special := _choice(&"special", 1.0, _drop(_item_catalog.get_definition(&"copper_sword"), 1, 1, fixed_roll))
	var gear := _group(&"gear", 1.0, _choices([plain, special]))
	var base := _pool(&"stable", _independent_rolls([copper]), _groups([gear]))
	var reordered := _pool(&"stable", _independent_rolls([copper]), _groups([_group(&"gear", 1.0, _choices([special, plain]))]))
	var first := _resolve(base, 73591, EquipmentInstanceFactory.new(_item_catalog))
	var second := _resolve(reordered, 73591, EquipmentInstanceFactory.new(_item_catalog))
	_expect(_encode(first) == _encode(second), "definition reordering changed resolved loot")

	var sand := _independent(&"zz_sand", 1.0, _drop(_item_catalog.get_definition(&"sand_block"), 1, 1))
	var with_independent := _pool(&"stable", _independent_rolls([sand, copper]), _groups([gear]))
	var independent_result := _resolve(with_independent, 73591, EquipmentInstanceFactory.new(_item_catalog))
	_expect(_without_item(independent_result, &"sand_block") == _encode(first), "unrelated independent roll perturbed existing outcomes")

	var extra_group := _group(&"zz_material", 1.0, _choices([_choice(&"sand", 1.0, _drop(_item_catalog.get_definition(&"sand_block")))]))
	var with_group := _pool(&"stable", _independent_rolls([copper]), _groups([extra_group, gear]))
	var group_result := _resolve(with_group, 73591, EquipmentInstanceFactory.new(_item_catalog))
	_expect(_without_item(group_result, &"sand_block") == _encode(first), "unrelated exclusive group perturbed existing outcomes")

func _test_exclusive_groups() -> void:
	var copper := _choice(&"copper", 1.0, _drop(_item_catalog.get_definition(&"copper")))
	var sand := _choice(&"sand", 1.0, _drop(_item_catalog.get_definition(&"sand_block")))
	var group := _group(&"material", 1.0, _choices([copper, sand]))
	var pool := _pool(&"exclusive", [], _groups([group]))
	var seen: Dictionary = {}
	for seed in range(100):
		var drops := _resolve(pool, seed, EquipmentInstanceFactory.new(_item_catalog))
		_expect(drops.size() == 1, "exclusive group emitted more or less than one choice")
		if drops.size() == 1:
			seen[drops[0].item_id] = true
	_expect(seen.has(&"copper") and seen.has(&"sand_block"), "exclusive weighted choices were not both reachable")
	var dirt := _choice(&"dirt", 1.0, _drop(_item_catalog.get_definition(&"dirt_block")))
	var expanded := _pool(&"exclusive", [], _groups([_group(&"material", 1.0, _choices([copper, sand, dirt]))]))
	var changed := false
	for seed in range(100):
		var before := _resolve(pool, seed, EquipmentInstanceFactory.new(_item_catalog))
		var after := _resolve(expanded, seed, EquipmentInstanceFactory.new(_item_catalog))
		if before[0].item_id != after[0].item_id:
			changed = true
			break
	_expect(changed, "adding a choice to one group did not affect that group")

func _test_random_equipment_rolls() -> void:
	var fixture := _three_slot_catalog()
	var sword := fixture.get_definition(&"three_slot_sword")
	var equipment_roll := LootEquipmentRollDefinition.new()
	equipment_roll.minimum_random_affix_count = 2
	equipment_roll.maximum_random_affix_count = 2
	equipment_roll.random_affixes = _affix_choices([
		_affix_choice(&"vicious", 1.0, fixture.get_equipment_affix(&"vicious")),
		_affix_choice(&"nimble", 1.0, fixture.get_equipment_affix(&"nimble")),
	])
	equipment_roll.random_rune_slot_count = 3
	equipment_roll.random_runes = _rune_choices([
		_rune_choice(&"basic", 1.0, fixture.get_definition(&"basic_rune") as RuneDefinition),
		_rune_choice(&"power", 1.0, fixture.get_definition(&"power_rune") as RuneDefinition),
	])
	var pool := _pool(&"rolled", _independent_rolls([_independent(&"weapon", 1.0, _drop(sword, 1, 1, equipment_roll))]), [])
	_expect(pool.validate(), "random equipment fixture invalid")
	_expect(LootCatalogValidator.validate(pool, fixture), "random equipment fixture is not canonical")
	var drops := _resolve(pool, 2481, EquipmentInstanceFactory.new(fixture))
	_expect(drops.size() == 1 and drops[0].equipment_instance != null, "random equipment did not resolve")
	if drops.size() != 1 or drops[0].equipment_instance == null:
		return
	var instance: EquipmentInstance = drops[0].equipment_instance
	_expect(instance.affixes.size() == 2, "random affix count mismatch")
	var affix_ids: Dictionary = {}
	for affix in instance.affixes:
		affix_ids[affix.affix_id] = true
		if affix.affix_id == &"nimble":
			_expect(affix.stat_rolls[0].stat_id == &"defense", "Nimble rolled an unused stat")
			_expect(affix.stat_rolls[0].amount >= 1.0 and affix.stat_rolls[0].amount <= 3.0, "ranged affix amount left configured range")
	_expect(affix_ids.size() == 2 and affix_ids.has(&"vicious") and affix_ids.has(&"nimble"), "random affixes repeated despite without-replacement selection")
	_expect(instance.socketed_rune_ids.size() == 3, "random rune slot count mismatch")
	var rune_ids: Dictionary = {}
	for rune_id in instance.socketed_rune_ids:
		rune_ids[rune_id] = true
	_expect(rune_ids.size() < instance.socketed_rune_ids.size(), "random rune slots did not allow a repeated rune")
	var nimble_amounts: Dictionary = {}
	var observed_runes: Dictionary = {}
	for seed in range(40):
		var sample: EquipmentInstance = _resolve(pool, seed, EquipmentInstanceFactory.new(fixture))[0].equipment_instance
		for affix in sample.affixes:
			if affix.affix_id == &"nimble":
				nimble_amounts[snappedf(affix.stat_rolls[0].amount, 0.000001)] = true
		for rune_id in sample.socketed_rune_ids:
			observed_runes[rune_id] = true
	_expect(nimble_amounts.size() > 1, "ranged affix values did not vary by seed")
	_expect(observed_runes.has(&"basic_rune") and observed_runes.has(&"power_rune"), "random rune candidates were not both reachable")

func _test_fixed_equipment_rolls() -> void:
	var fixture := _three_slot_catalog()
	var equipment_roll := LootEquipmentRollDefinition.new()
	equipment_roll.fixed_affixes = _affixes([fixture.get_equipment_affix(&"vicious")])
	equipment_roll.fixed_runes = _runes([
		fixture.get_definition(&"power_rune") as RuneDefinition,
		fixture.get_definition(&"basic_rune") as RuneDefinition,
	])
	var pool := _pool(&"fixed", _independent_rolls([_independent(&"special", 1.0, _drop(fixture.get_definition(&"three_slot_sword"), 1, 1, equipment_roll))]), [])
	var drops := _resolve(pool, 52, EquipmentInstanceFactory.new(fixture))
	_expect(drops.size() == 1 and drops[0].equipment_instance.affixes[0].affix_id == &"vicious", "fixed special affix changed")
	_expect(drops.size() == 1 and drops[0].equipment_instance.socketed_rune_ids == _rune_ids([&"power_rune", &"basic_rune"]), "fixed rune slot order changed")

	var no_proficiency := _item_catalog.get_definition(&"copper_sword").duplicate() as ItemDefinition
	no_proficiency.proficiency = null
	var affix_only := LootEquipmentRollDefinition.new()
	affix_only.fixed_affixes = _affixes([_item_catalog.get_equipment_affix(&"vicious")])
	_expect(affix_only.validate(no_proficiency, "affix-only regression"), "affix-only equipment roll required proficiency")

func _test_allocator_atomicity() -> void:
	var sword_drop := _drop(_item_catalog.get_definition(&"copper_sword"))
	var pool := _pool(&"allocator", _independent_rolls([
		_independent(&"first", 1.0, sword_drop),
		_independent(&"second", 1.0, sword_drop),
	]), [])
	var factory := EquipmentInstanceFactory.new(_item_catalog, EquipmentInstance.MAXIMUM_INSTANCE_ID)
	var drops := _resolve(pool, 9, factory)
	_expect(drops.is_empty(), "partially allocatable equipment batch resolved")
	_expect(factory.get_next_instance_id() == EquipmentInstance.MAXIMUM_INSTANCE_ID, "failed equipment batch consumed an instance ID")
	var single := _pool(&"allocator", _independent_rolls([_independent(&"first", 1.0, sword_drop)]), [])
	var success := _resolve(single, 9, factory)
	_expect(success.size() == 1 and success[0].equipment_instance.instance_id == EquipmentInstance.MAXIMUM_INSTANCE_ID, "final equipment ID was not allocated after rollback")
	_expect(factory.get_next_instance_id() == EquipmentInstanceFactory.MAXIMUM_NEXT_INSTANCE_ID, "successful equipment resolution did not adopt allocator state")

func _test_parallel_allocator_preparations() -> void:
	var drop := _drop(_item_catalog.get_definition(&"copper_sword"))
	var pool := _pool(&"parallel_allocator", _independent_rolls([
		_independent(&"sword", 1.0, drop),
	]), [])
	var factory := EquipmentInstanceFactory.new(_item_catalog, 300)
	var first := LootResolver.prepare(pool, 11, factory)
	var second := LootResolver.prepare(pool, 11, factory)
	_expect(first != null and second != null, "parallel loot resolutions were not prepared")
	if first == null or second == null:
		return
	_expect(factory.get_next_instance_id() == 300, "loot preparation advanced the root allocator")
	_expect(first._get_pending_next_instance_id() == 301, "prepared loot did not expose its pending allocator state")
	var copied_drops := first.get_drops()
	copied_drops[0].count = 7
	copied_drops[0].equipment_instance.socketed_rune_ids.append(&"basic_rune")
	var preserved_drops := first.get_drops()
	_expect(preserved_drops[0].count == 1, "prepared loot exposed mutable stack state")
	_expect(preserved_drops[0].equipment_instance.socketed_rune_ids.is_empty(), "prepared loot exposed mutable equipment state")
	_expect(LootResolver._can_commit(first, factory), "first parallel loot preparation was not committable")
	_expect(LootResolver._can_commit(second, factory), "second parallel loot preparation was not initially committable")
	_expect(LootResolver._commit(first, factory), "first parallel loot preparation did not commit")
	_expect(factory.get_next_instance_id() == 301, "committed loot did not advance the allocator exactly once")
	_expect(not LootResolver._can_commit(second, factory), "stale parallel loot preparation remained committable")
	_expect(not LootResolver._commit(second, factory), "stale parallel loot preparation committed")
	_expect(not LootResolver._commit(first, factory), "committed loot preparation replayed")
	var foreign_factory := EquipmentInstanceFactory.new(_item_catalog, 300)
	_expect(not LootResolver._can_commit(second, foreign_factory), "cross-owner loot preparation was accepted")
	_expect(not LootResolver._commit(second, foreign_factory), "cross-owner loot preparation committed")
	var next_instance := factory.create(&"copper_sword")
	_expect(next_instance != null and next_instance.instance_id == 301, "stale loot preparation made a duplicate instance ID observable")

func _resolve(
	pool: LootPoolDefinition,
	seed: int,
	factory: EquipmentInstanceFactory,
) -> Array[InventoryStack]:
	var prepared := LootResolver.prepare(pool, seed, factory)
	if prepared == null or not LootResolver._commit(prepared, factory):
		return []
	return prepared.get_drops()

func _test_malformed_definitions() -> void:
	var output: Array = []
	var exit_code := OS.execute(
		OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://loot/tests/loot_malformed_probe.gd"],
		output,
		true,
	)
	var text := "\n".join(PackedStringArray(output))
	_expect(exit_code == 0, "malformed loot probe exited %d" % exit_code)
	_expect(text.contains("LOOT_MALFORMED PASS"), "malformed loot definitions were accepted")

func _test_zombie_distribution() -> void:
	var pool := load("res://loot/pools/zombie.tres") as LootPoolDefinition
	var copper_count := 0
	var gear_count := 0
	var categories: Dictionary = {}
	var rolled_runes: Dictionary = {}
	var rolled_affixes: Dictionary = {}
	var nimble_amounts: Dictionary = {}
	for seed in range(1000):
		var drops := _resolve(pool, seed, EquipmentInstanceFactory.new(_item_catalog))
		_expect(drops.size() <= 2, "zombie emitted more than copper plus one gear choice")
		var seed_gear_count := 0
		for stack in drops:
			if stack.item_id == &"copper":
				copper_count += 1
				_expect(stack.count >= 1 and stack.count <= 3, "zombie copper count left configured range")
				continue
			seed_gear_count += 1
			gear_count += 1
			if stack.item_id == &"copper_helmet":
				categories[&"helmet"] = true
				_expect(stack.equipment_instance.affixes.size() == 1 and stack.equipment_instance.affixes[0].affix_id == &"stout", "zombie special helmet lost Stout")
			elif stack.item_id == &"copper_sword" and stack.equipment_instance.affixes.is_empty():
				categories[&"plain"] = true
				_expect(stack.equipment_instance.socketed_rune_ids.is_empty(), "plain zombie sword gained runes")
			elif stack.item_id == &"copper_sword":
				categories[&"rolled"] = true
				_expect(stack.equipment_instance.socketed_rune_ids.size() == 1, "rolled zombie sword rune slot mismatch")
				for rune_id in stack.equipment_instance.socketed_rune_ids:
					rolled_runes[rune_id] = true
				for affix in stack.equipment_instance.affixes:
					rolled_affixes[affix.affix_id] = true
					if affix.affix_id == &"nimble":
						nimble_amounts[snappedf(affix.stat_rolls[0].amount, 0.000001)] = true
		_expect(seed_gear_count <= 1, "zombie exclusive gear group emitted multiple items")
	_expect(copper_count >= 680 and copper_count <= 820, "zombie copper frequency left expected tolerance: %d" % copper_count)
	_expect(gear_count >= 115 and gear_count <= 225, "zombie gear frequency left expected tolerance: %d" % gear_count)
	_expect(categories.size() == 3, "zombie gear choices were not all reachable")
	_expect(rolled_runes.size() == 1 and rolled_runes.has(&"power_rune"), "zombie gear exposed a rune outside the Power Rune pool")
	_expect(rolled_affixes.has(&"vicious") and rolled_affixes.has(&"nimble"), "zombie random affixes were not both reachable")
	_expect(nimble_amounts.size() > 1, "zombie ranged Nimble rolls did not vary")

func _three_slot_catalog() -> ItemCatalog:
	var sword := _item_catalog.get_definition(&"copper_sword").duplicate() as ItemDefinition
	sword.id = &"three_slot_sword"
	sword.display_name = "Three Slot Sword"
	sword.proficiency = sword.proficiency.duplicate() as ProficiencyDefinition
	sword.proficiency.slot_unlock_levels = PackedInt32Array([1, 1, 1])
	var definitions: Array[ItemDefinition] = []
	definitions.assign(_item_catalog.definitions)
	definitions.append(sword)
	var catalog := ItemCatalog.new()
	catalog.equipment_types = _item_catalog.equipment_types
	catalog.definitions = definitions
	catalog.equipment_affixes = _item_catalog.equipment_affixes
	return catalog

func _pool(
	id: StringName,
	independent_rolls: Array[LootIndependentRollDefinition],
	exclusive_groups: Array[LootExclusiveGroupDefinition],
) -> LootPoolDefinition:
	var pool := LootPoolDefinition.new()
	pool.id = id
	pool.independent_rolls = independent_rolls
	pool.exclusive_groups = exclusive_groups
	return pool

func _drop(
	item: ItemDefinition,
	minimum_count: int = 1,
	maximum_count: int = 1,
	equipment_roll: LootEquipmentRollDefinition = null,
) -> LootDropDefinition:
	var drop := LootDropDefinition.new()
	drop.item = item
	drop.minimum_count = minimum_count
	drop.maximum_count = maximum_count
	drop.equipment_roll = equipment_roll
	return drop

func _independent(id: StringName, chance: float, drop: LootDropDefinition) -> LootIndependentRollDefinition:
	var roll := LootIndependentRollDefinition.new()
	roll.id = id
	roll.chance = chance
	roll.drop = drop
	return roll

func _choice(id: StringName, weight: float, drop: LootDropDefinition) -> LootWeightedChoiceDefinition:
	var choice := LootWeightedChoiceDefinition.new()
	choice.id = id
	choice.weight = weight
	choice.drop = drop
	return choice

func _group(id: StringName, chance: float, choices: Array[LootWeightedChoiceDefinition]) -> LootExclusiveGroupDefinition:
	var group := LootExclusiveGroupDefinition.new()
	group.id = id
	group.chance = chance
	group.choices = choices
	return group

func _affix_choice(id: StringName, weight: float, affix: EquipmentAffixDefinition) -> LootAffixChoiceDefinition:
	var choice := LootAffixChoiceDefinition.new()
	choice.id = id
	choice.weight = weight
	choice.affix = affix
	return choice

func _rune_choice(id: StringName, weight: float, rune: RuneDefinition) -> LootRuneChoiceDefinition:
	var choice := LootRuneChoiceDefinition.new()
	choice.id = id
	choice.weight = weight
	choice.rune = rune
	return choice

func _choice_by_id(group: LootExclusiveGroupDefinition, id: StringName) -> LootWeightedChoiceDefinition:
	for choice in group.choices:
		if choice.id == id:
			return choice
	return null

func _encode(stacks: Array) -> Array[Dictionary]:
	var encoded: Array[Dictionary] = []
	for stack in stacks:
		encoded.append(stack.to_dict())
	return encoded

func _without_item(stacks: Array, item_id: StringName) -> Array[Dictionary]:
	var encoded: Array[Dictionary] = []
	for stack in stacks:
		if stack.item_id != item_id:
			encoded.append(stack.to_dict())
	return encoded

func _path(values: Array[StringName]) -> Array[StringName]:
	return values

func _affixes(values: Array[EquipmentAffixDefinition]) -> Array[EquipmentAffixDefinition]:
	return values

func _runes(values: Array[RuneDefinition]) -> Array[RuneDefinition]:
	return values

func _rune_ids(values: Array[StringName]) -> Array[StringName]:
	return values

func _independent_rolls(values: Array[LootIndependentRollDefinition]) -> Array[LootIndependentRollDefinition]:
	return values

func _choices(values: Array[LootWeightedChoiceDefinition]) -> Array[LootWeightedChoiceDefinition]:
	return values

func _groups(values: Array[LootExclusiveGroupDefinition]) -> Array[LootExclusiveGroupDefinition]:
	return values

func _affix_choices(values: Array[LootAffixChoiceDefinition]) -> Array[LootAffixChoiceDefinition]:
	return values

func _rune_choices(values: Array[LootRuneChoiceDefinition]) -> Array[LootRuneChoiceDefinition]:
	return values

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)

func _finish() -> void:
	if _errors.is_empty():
		print("LOOT_SYSTEM PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)
