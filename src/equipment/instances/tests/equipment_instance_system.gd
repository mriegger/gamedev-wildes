extends SceneTree

var _errors: Array[String] = []

func _init() -> void:
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var recipe_catalog := load("res://crafting/stations/anvil_recipe_catalog.tres") as CraftingRecipeCatalog
	_test_multi_affix_persistence(item_catalog)
	_test_failed_allocations(item_catalog)
	_test_starter_and_crafting_identity(item_catalog, recipe_catalog)
	if _errors.is_empty():
		print("EQUIPMENT_INSTANCE_SYSTEM PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _test_multi_affix_persistence(source: ItemCatalog) -> void:
	var tempered := _affix(
		&"tempered_test",
		"of Tempering",
		source.get_equipment_type(&"weapon_sword"),
		_rolls([
			_roll(&"strength", StatModifier.Operation.ADD, 1.0, 3.0),
			_roll(&"defense", StatModifier.Operation.ADD, 0.5, 1.5),
		]),
	)
	var swift := _affix(
		&"swift_test",
		"of Swiftness",
		source.get_equipment_type(&"weapon_sword"),
		_rolls([
			_roll(&"move_speed", StatModifier.Operation.MULTIPLY, 1.1, 1.4),
		]),
	)
	var catalog := ItemCatalog.new()
	catalog.equipment_types = source.equipment_types
	catalog.definitions = source.definitions
	catalog.equipment_affixes = _affixes([tempered, swift])
	var factory := EquipmentInstanceFactory.new(catalog)
	var instance := factory.create(
		&"copper_sword",
		_affixes([tempered, swift]),
		_rune_ids([&"basic_rune"]),
		_resolve_affix_amount,
	)
	_expect(instance != null, "multi-affix equipment instance was not created")
	if instance == null:
		return
	_expect(instance.affixes.size() == 2, "multi-affix equipment lost an affix")
	_expect(instance.affixes[0].affix_id == &"swift_test", "created affixes were not canonicalized by ID")
	_expect(instance.affixes[1].affix_id == &"tempered_test", "created affixes were not canonicalized by ID")
	_expect(instance.affixes[1].stat_rolls.size() == 2, "per-stat affix rolls were not created")
	_expect(instance.affixes[1].stat_rolls[0].stat_id == &"defense", "created stat rolls were not canonicalized by ID")
	_expect(instance.affixes[1].stat_rolls[1].stat_id == &"strength", "created stat rolls were not canonicalized by ID")
	_expect(_in_range(instance.affixes[0].stat_rolls[0].amount, 1.1, 1.4), "multiplier roll left its configured range")
	_expect(_in_range(instance.affixes[1].stat_rolls[0].amount, 0.5, 1.5), "defense roll left its configured range")
	_expect(_in_range(instance.affixes[1].stat_rolls[1].amount, 1.0, 3.0), "strength roll left its configured range")
	var canonical_dict := instance.to_dict()
	tempered.stat_rolls.reverse()
	var reordered_factory := EquipmentInstanceFactory.new(catalog)
	var reordered := reordered_factory.create(
		&"copper_sword",
		_affixes([swift, tempered]),
		_rune_ids([&"basic_rune"]),
		_resolve_affix_amount,
	)
	_expect(reordered != null and reordered.to_dict() == canonical_dict, "definition reordering changed canonical equipment data")
	var encoded := instance.to_dict()
	var restored := EquipmentInstance.from_dict(encoded)
	_expect(restored != null, "persisted multi-affix instance did not decode")
	if restored == null:
		return
	_expect(restored.to_dict() == encoded, "persisted rolled values changed during decoding")
	_expect(factory.is_valid_instance(&"copper_sword", restored), "decoded multi-affix instance failed catalog validation")
	var extra_instance_field := encoded.duplicate(true)
	extra_instance_field["future"] = true
	_expect(EquipmentInstance.from_dict(extra_instance_field) == null, "equipment instance accepted an extra persisted field")
	var extra_affix_field := encoded.duplicate(true)
	extra_affix_field["affixes"][0]["future"] = true
	_expect(EquipmentInstance.from_dict(extra_affix_field) == null, "equipment instance accepted a nested affix field")
	var extra_roll_field := encoded.duplicate(true)
	extra_roll_field["affixes"][0]["stat_rolls"][0]["future"] = true
	_expect(EquipmentInstance.from_dict(extra_roll_field) == null, "equipment instance accepted a nested stat roll field")
	tempered.stat_rolls[0].minimum_amount = 10.0
	tempered.stat_rolls[0].maximum_amount = 20.0
	tempered.stat_rolls[0].operation = StatModifier.Operation.MULTIPLY
	tempered.compatible_equipment_types = [source.get_equipment_type(&"armor")]
	var basic_rune := catalog.get_definition(&"basic_rune") as RuneDefinition
	basic_rune.compatible_equipment_types = [source.get_equipment_type(&"armor")]
	_expect(factory.is_valid_instance(&"copper_sword", restored), "persisted instance was invalidated by generation balance changes")

func _test_failed_allocations(item_catalog: ItemCatalog) -> void:
	var factory := EquipmentInstanceFactory.new(item_catalog, 50)
	var unallocated := EquipmentInstance.new(50)
	_expect(not factory.is_valid_instance(&"copper_sword", unallocated), "unallocated next equipment ID was accepted")
	_expect(factory.create(&"sand_block") == null, "non-equipment received an instance")
	_expect(factory.get_next_instance_id() == 50, "rejected factory creation consumed an ID")
	var inventory := InventoryModel.new(item_catalog, factory, InventoryModel.HOTBAR_SIZE + 1)
	for index in range(InventoryModel.HOTBAR_SIZE):
		InventoryTestFixture.restore_slot(inventory, index, InventoryStack.new(&"dirt_block", 1))
	var swords: Array[StringName] = [&"copper_sword", &"copper_sword"]
	var loadout := InventoryTestFixture.create_loadout(inventory)
	_expect(not loadout.can_add_batch(swords), "over-capacity equipment simulation succeeded")
	_expect(factory.get_next_instance_id() == 50, "capacity simulation consumed an ID")
	_expect(not loadout.add_batch(swords), "over-capacity equipment batch committed")
	_expect(factory.get_next_instance_id() == 50, "failed equipment batch consumed an ID")
	_expect(inventory.get_slot(InventoryModel.HOTBAR_SIZE) == null, "failed equipment batch changed inventory")
	var first_valid := factory.create(&"copper_sword")
	_expect(first_valid != null and first_valid.instance_id == 50, "first successful allocation skipped a reserved ID")
	var final_factory := EquipmentInstanceFactory.new(item_catalog, EquipmentInstance.MAXIMUM_INSTANCE_ID)
	var final_instance := final_factory.create(&"copper_sword")
	_expect(final_instance != null and final_instance.instance_id == EquipmentInstance.MAXIMUM_INSTANCE_ID, "final equipment ID was not allocatable")
	_expect(final_factory.create(&"copper_sword") == null, "exhausted equipment allocator wrapped")
	_expect(final_factory.get_next_instance_id() == EquipmentInstanceFactory.MAXIMUM_NEXT_INSTANCE_ID, "exhausted allocator state changed")

func _test_starter_and_crafting_identity(
	item_catalog: ItemCatalog,
	recipe_catalog: CraftingRecipeCatalog,
) -> void:
	var factory := EquipmentInstanceFactory.new(item_catalog)
	var inventory := InventoryModel.new(item_catalog, factory)
	inventory.setup_starter()
	var starter_sword := inventory.get_slot(3)
	_expect(starter_sword != null and starter_sword.equipment_instance != null, "starter sword was not instanced")
	var seen_ids: Dictionary = {}
	for stack in InventoryTestFixture.get_slots(inventory):
		if stack == null:
			continue
		if item_catalog.get_definition(stack.item_id).equipment_type == null:
			_expect(stack.equipment_instance == null, "non-equipment starter item received an instance")
			continue
		_expect(stack.equipment_instance != null, "plain starter equipment lacked an instance")
		if stack.equipment_instance == null:
			continue
		_expect(stack.equipment_instance.instance_id > 0, "starter equipment ID was not positive")
		_expect(not seen_ids.has(stack.equipment_instance.instance_id), "starter equipment IDs were duplicated")
		seen_ids[stack.equipment_instance.instance_id] = true
	var loadout := InventoryTestFixture.create_loadout(inventory)
	_expect(loadout.add_backpack_item(&"copper", 15), "copper crafting fixture could not be added")
	_expect(loadout.add_backpack_item(&"log_block", 5), "wood crafting fixture could not be added")
	var crafting := CraftingCoordinator.new()
	crafting.setup(inventory, loadout, recipe_catalog)
	_expect(crafting.craft(&"copper_sword"), "equipment recipe did not craft")
	var sword_ids: Array[int] = []
	for stack in InventoryTestFixture.get_slots(inventory):
		if stack != null and stack.item_id == &"copper_sword" and stack.equipment_instance != null:
			sword_ids.append(stack.equipment_instance.instance_id)
	_expect(sword_ids.size() == 2, "starter and crafted swords were not both present")
	if sword_ids.size() == 2:
		_expect(sword_ids[0] > 0 and sword_ids[1] > 0, "crafted equipment ID was not positive")
		_expect(sword_ids[0] != sword_ids[1], "starter and crafted equipment shared an ID")

func _affix(
	id: StringName,
	display_name_suffix: String,
	equipment_type: EquipmentTypeDefinition,
	stat_rolls: Array[EquipmentAffixStatDefinition],
) -> EquipmentAffixDefinition:
	var definition := EquipmentAffixDefinition.new()
	definition.id = id
	definition.display_name_suffix = display_name_suffix
	var compatible_types: Array[EquipmentTypeDefinition] = [equipment_type]
	definition.compatible_equipment_types = compatible_types
	definition.stat_rolls = stat_rolls
	return definition

func _roll(
	stat_id: StringName,
	operation: StatModifier.Operation,
	minimum_amount: float,
	maximum_amount: float,
) -> EquipmentAffixStatDefinition:
	var definition := EquipmentAffixStatDefinition.new()
	definition.stat_id = stat_id
	definition.operation = operation
	definition.minimum_amount = minimum_amount
	definition.maximum_amount = maximum_amount
	return definition

func _rolls(values: Array[EquipmentAffixStatDefinition]) -> Array[EquipmentAffixStatDefinition]:
	return values

func _affixes(values: Array[EquipmentAffixDefinition]) -> Array[EquipmentAffixDefinition]:
	return values

func _rune_ids(values: Array[StringName]) -> Array[StringName]:
	return values

func _in_range(value: float, minimum_amount: float, maximum_amount: float) -> bool:
	return value >= minimum_amount and value <= maximum_amount

func _resolve_affix_amount(
	_affix_id: StringName,
	_stat_id: StringName,
	minimum_amount: float,
	maximum_amount: float,
) -> float:
	return lerpf(minimum_amount, maximum_amount, 0.5)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
