extends SceneTree

func _init() -> void:
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var sword := item_catalog.get_definition(&"copper_sword")
	var copper := item_catalog.get_definition(&"copper")
	var duplicate_first := _independent(&"duplicate", 1.0, _drop(copper))
	var duplicate_second := _independent(&"duplicate", 1.0, _drop(copper))
	var duplicate_pool := _pool(_independent_rolls([duplicate_first, duplicate_second]), [])

	var invalid_choice := LootWeightedChoiceDefinition.new()
	invalid_choice.id = &"invalid"
	invalid_choice.weight = 0.0
	invalid_choice.drop = _drop(copper)
	var invalid_group := LootExclusiveGroupDefinition.new()
	invalid_group.id = &"invalid_group"
	invalid_group.chance = 1.0
	invalid_group.choices = _choices([invalid_choice])
	var invalid_weight_pool := _pool([], _groups([invalid_group]))

	var mixed := LootEquipmentRollDefinition.new()
	mixed.fixed_affixes = _affixes([item_catalog.get_equipment_affix(&"vicious")])
	mixed.minimum_random_affix_count = 1
	mixed.maximum_random_affix_count = 1
	mixed.random_affixes = _affix_choices([_affix_choice(&"nimble", item_catalog.get_equipment_affix(&"nimble"))])
	var mixed_pool := _pool(_independent_rolls([_independent(&"mixed", 1.0, _drop(sword, 1, 1, mixed))]), [])

	var missing_runes := LootEquipmentRollDefinition.new()
	missing_runes.random_rune_slot_count = 1
	var missing_rune_pool := _pool(_independent_rolls([_independent(&"runes", 1.0, _drop(sword, 1, 1, missing_runes))]), [])

	var stacked_equipment_pool := _pool(_independent_rolls([_independent(&"stacked", 1.0, _drop(sword, 1, 2))]), [])
	var bad_chance_pool := _pool(_independent_rolls([_independent(&"chance", 2.0, _drop(copper))]), [])
	if (
		not duplicate_pool.validate()
		and not invalid_weight_pool.validate()
		and not mixed_pool.validate()
		and not missing_rune_pool.validate()
		and not stacked_equipment_pool.validate()
		and not bad_chance_pool.validate()
	):
		print("LOOT_MALFORMED PASS")
		quit(0)
	else:
		print("LOOT_MALFORMED FAILED")
		quit(1)

func _pool(
	independent_rolls: Array[LootIndependentRollDefinition],
	exclusive_groups: Array[LootExclusiveGroupDefinition],
) -> LootPoolDefinition:
	var pool := LootPoolDefinition.new()
	pool.id = &"malformed"
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

func _affix_choice(id: StringName, affix: EquipmentAffixDefinition) -> LootAffixChoiceDefinition:
	var choice := LootAffixChoiceDefinition.new()
	choice.id = id
	choice.affix = affix
	return choice

func _independent_rolls(values: Array[LootIndependentRollDefinition]) -> Array[LootIndependentRollDefinition]:
	return values

func _choices(values: Array[LootWeightedChoiceDefinition]) -> Array[LootWeightedChoiceDefinition]:
	return values

func _groups(values: Array[LootExclusiveGroupDefinition]) -> Array[LootExclusiveGroupDefinition]:
	return values

func _affixes(values: Array[EquipmentAffixDefinition]) -> Array[EquipmentAffixDefinition]:
	return values

func _affix_choices(values: Array[LootAffixChoiceDefinition]) -> Array[LootAffixChoiceDefinition]:
	return values
