extends SceneTree

var _errors: Array[String] = []

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var recipe_catalog := load("res://crafting/crafting_recipe_catalog.tres") as CraftingRecipeCatalog
	var player_stats := load("res://player/player_stats.tres") as ActorStatsDefinition
	_expect(block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog.validate(block_catalog), "item catalog invalid")
	_expect(recipe_catalog.validate(item_catalog), "crafting catalog invalid")

	var rune := item_catalog.get_definition(&"basic_rune") as RuneDefinition
	var sand := item_catalog.get_definition(&"sand_block")
	var common := load("res://items/rarity/definitions/common.tres") as ItemRarityDefinition
	var weapon_type := item_catalog.get_equipment_type(&"weapon")
	var armor_type := item_catalog.get_equipment_type(&"armor")
	_expect(rune != null, "Basic Rune is missing")
	if rune != null:
		_expect(rune.validate(rune.resource_path, armor_type), "Basic Rune definition is invalid")
		_expect(rune.display_name == "Basic Rune", "Basic Rune display name changed")
		_expect(rune.max_stack == 99, "Basic Rune is not stackable")
		_expect(rune.icon != sand.icon, "Basic Rune still shares the Sand icon")
		_expect(rune.icon.resource_path == "res://assets/textures/items/basic_rune.svg", "Basic Rune does not use its dedicated icon")
		_expect(rune.rarity == common, "Basic Rune does not use canonical Common rarity")
		_expect(rune.stat_modifiers.is_empty(), "Basic Rune has ordinary selected-item modifiers")
		_expect(rune.compatible_equipment_types == _equipment_types([weapon_type, armor_type]), "Basic Rune does not target weapons and armor")
		_expect(rune.compatible_armor_slots == RuneDefinition.ALL_ARMOR_SLOTS, "Basic Rune does not target every armor slot")
		_expect(rune.socket_modifiers.size() == 1, "Basic Rune socket modifier count changed")
		if rune.socket_modifiers.size() == 1:
			var modifier := rune.socket_modifiers[0]
			_expect(modifier.stat_id == &"hp", "Basic Rune does not modify maximum HP")
			_expect(modifier.operation == StatModifier.Operation.ADD, "Basic Rune HP modifier is not additive")
			_expect(is_equal_approx(modifier.amount, 100.0), "Basic Rune HP modifier is not +100")
			_expect(modifier.is_valid(player_stats), "Basic Rune HP modifier is invalid for player stats")

	var weapon_count := 0
	var armor_count := 0
	for definition in item_catalog.definitions:
		if definition.equipment_type != null and definition.equipment_type.is_or_inherits(weapon_type):
			weapon_count += 1
			_expect(rune != null and rune.is_compatible_with(definition), "Basic Rune rejected weapon %s" % definition.id)
		var armor := definition as ArmorDefinition
		if armor != null:
			armor_count += 1
			_expect(rune != null and rune.is_compatible_with(armor), "Basic Rune rejected armor %s" % definition.id)
	_expect(weapon_count > 0, "item catalog has no weapon compatibility fixture")
	_expect(armor_count == ArmorDefinition.SLOT_COUNT, "item catalog does not cover every armor slot")
	_expect(rune != null and not rune.is_compatible_with(sand), "Basic Rune accepted a block item")
	_expect(rune != null and not rune.is_compatible_with(rune), "Basic Rune accepted another rune")

	if rune != null:
		var weapon_only := rune.duplicate() as RuneDefinition
		weapon_only.compatible_equipment_types = _equipment_types([weapon_type])
		weapon_only.compatible_armor_slots = 0
		_expect(weapon_only.validate("weapon-only test rune", armor_type), "weapon-only compatibility is invalid")
		_expect(weapon_only.is_compatible_with(item_catalog.get_definition(&"copper_sword")), "weapon-only rune rejected a weapon")
		_expect(not weapon_only.is_compatible_with(item_catalog.get_definition(&"copper_helmet")), "weapon-only rune accepted armor")

		var head_only := rune.duplicate() as RuneDefinition
		head_only.compatible_equipment_types = _equipment_types([armor_type])
		head_only.compatible_armor_slots = RuneDefinition.ArmorSlotMask.HEAD
		_expect(head_only.validate("head-only test rune", armor_type), "head-only compatibility is invalid")
		_expect(head_only.is_compatible_with(item_catalog.get_definition(&"copper_helmet")), "head-only rune rejected a helmet")
		_expect(not head_only.is_compatible_with(item_catalog.get_definition(&"copper_chest_plate")), "head-only rune accepted chest armor")
		_expect(not head_only.is_compatible_with(item_catalog.get_definition(&"copper_sword")), "head-only rune accepted a weapon")

	var recipe := recipe_catalog.get_definition(&"basic_rune")
	_expect(recipe.output_item == rune and recipe.output_count == 1, "Basic Rune recipe output is not canonical")
	_expect(recipe.get_ingredient_counts() == {&"sand_block": 32}, "Basic Rune recipe does not consume 32 Sand")

	if _errors.is_empty():
		print("RUNE_DEFINITION PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)

func _equipment_types(values: Array[EquipmentTypeDefinition]) -> Array[EquipmentTypeDefinition]:
	return values
