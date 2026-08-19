extends SceneTree

const STACKING_WEAPON_ID: StringName = &"tooltip_test_sword"

var _frame: int = 0
var _errors: Array[String] = []
var _inventory: InventoryModel
var _item_proficiency: ItemProficiency
var _slot: InventorySlot

func _init() -> void:
	var item_catalog := _build_catalog()
	_inventory = InventoryModel.new(item_catalog)
	_inventory.slots[0] = InventoryStack.new(&"basic_rune", 1)
	_inventory.slots[1] = InventoryStack.new(&"copper_sword", 1, _rune_ids([&"basic_rune"]))
	_inventory.slots[2] = InventoryStack.new(&"copper_sword", 1)
	_inventory.slots[3] = InventoryStack.new(&"copper_helmet", 1, _rune_ids([&"basic_rune"]))
	_inventory.slots[4] = InventoryStack.new(STACKING_WEAPON_ID, 1, _rune_ids([&"basic_rune", &"basic_rune"]))
	_item_proficiency = ItemProficiency.new(item_catalog)
	_expect(_item_proficiency.add_experience(&"copper_sword", 100.0) == 1, "sword proficiency fixture did not unlock")
	_expect(_item_proficiency.add_experience(&"copper_helmet", 100.0) == 1, "helmet proficiency fixture did not unlock")
	_expect(_item_proficiency.add_experience(STACKING_WEAPON_ID, 100.0) == 1, "stacking weapon fixture did not unlock")
	_expect(RuneSocketingCoordinator.new().setup(_inventory, _item_proficiency), "tooltip socket fixture is invalid")
	_slot = (load("res://inventory/ui/inventory_slot.tscn") as PackedScene).instantiate() as InventorySlot
	_slot.set_inventory_styles(StyleBoxFlat.new(), StyleBoxFlat.new())
	_slot.set_inventory(_inventory)
	_slot.set_item_proficiency(_item_proficiency)
	root.add_child(_slot)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_slot.set_slot_index(0)
		_slot.set_item(&"basic_rune", 1)
	elif _frame == 3:
		_test_rune_tooltip()
		_test_socketed_weapon_tooltip()
		_test_unsocketed_weapon_tooltip()
		_test_socketed_armor_tooltip()
		_test_duplicate_rune_aggregation()
		_slot.free()
	elif _frame == 10:
		_finish()
	return false

func _test_rune_tooltip() -> void:
	_expect(_slot.tooltip_text == "Basic Rune", "rune inventory slot has no tooltip text")
	var tooltip := _create_slot_tooltip("rune")
	if tooltip == null:
		return
	_expect(tooltip.item_name_label.text == "Basic Rune", "rune tooltip name changed")
	_expect(tooltip.rarity_label.text == "Common", "rune tooltip rarity changed")
	_expect(not tooltip.proficiency_level_label.visible, "rune tooltip shows a proficiency level")
	_expect(not tooltip.proficiency_experience_label.visible, "rune tooltip shows proficiency experience")
	_expect(tooltip.stats_label.text.contains("Compatible: Weapons, All Armor"), "rune tooltip compatibility is missing")
	_expect(tooltip.stats_label.text.contains("HP: +100"), "rune tooltip socket stat is missing")
	_expect(not tooltip.rune_stats_label.visible, "unsocketed rune item shows installed bonuses")
	tooltip.free()

func _test_socketed_weapon_tooltip() -> void:
	_slot.set_slot_index(1)
	_slot.set_item(&"copper_sword", 1)
	var tooltip := _create_slot_tooltip("socketed weapon")
	if tooltip == null:
		return
	_expect(tooltip.stats_label.text.contains("Base Damage: 10"), "socketed weapon lost its base stats")
	_expect(tooltip.rune_stats_label.visible, "socketed weapon rune bonus is hidden")
	_expect(tooltip.rune_stats_label.text == "(+100 HP)", "socketed weapon rune bonus is incorrect")
	_expect(tooltip.rune_stats_label.get_theme_color("font_color") == ItemTooltip.RUNE_BONUS_COLOR, "socketed weapon rune bonus is not red")
	tooltip.free()

func _test_unsocketed_weapon_tooltip() -> void:
	_slot.set_slot_index(2)
	_slot.set_item(&"copper_sword", 1)
	var tooltip := _create_slot_tooltip("unsocketed weapon")
	if tooltip == null:
		return
	_expect(not tooltip.rune_stats_label.visible, "unsocketed copy inherited another copy's rune bonus")
	_expect(tooltip.rune_stats_label.text.is_empty(), "unsocketed copy has rune bonus text")
	tooltip.free()

func _test_socketed_armor_tooltip() -> void:
	_slot.set_slot_index(3)
	_slot.set_item(&"copper_helmet", 1)
	var tooltip := _create_slot_tooltip("socketed armor")
	if tooltip == null:
		return
	_expect(tooltip.stats_label.text.contains("Slot: Head"), "socketed armor lost its slot stat")
	_expect(tooltip.stats_label.text.contains("Defense: +1"), "socketed armor lost its defense stat")
	_expect(tooltip.rune_stats_label.text == "(+100 HP)", "socketed armor rune bonus is incorrect")
	tooltip.free()

func _test_duplicate_rune_aggregation() -> void:
	_slot.set_slot_index(4)
	_slot.set_item(STACKING_WEAPON_ID, 1)
	var tooltip := _create_slot_tooltip("stacked-rune weapon")
	if tooltip == null:
		return
	_expect(tooltip.stats_label.text.contains("Base Damage: 15"), "weapon tooltip ignored its damage multiplier")
	_expect(tooltip.rune_stats_label.text == "(+200 HP)", "duplicate rune bonuses were not aggregated")
	_expect(tooltip.rune_stats_label.get_theme_color("font_color") == ItemTooltip.RUNE_BONUS_COLOR, "aggregated rune bonus is not red")
	tooltip.free()

func _build_catalog() -> ItemCatalog:
	var source := load("res://items/item_catalog.tres") as ItemCatalog
	var stacking_weapon := source.get_definition(&"copper_sword").duplicate(true) as ItemDefinition
	stacking_weapon.id = STACKING_WEAPON_ID
	stacking_weapon.proficiency = ProficiencyDefinition.new()
	stacking_weapon.proficiency.experience_requirements = PackedFloat64Array([100.0, 100.0, 100.0])
	stacking_weapon.proficiency.slot_unlock_levels = PackedInt32Array([0, 1, 2])
	var stacking_action := stacking_weapon.primary_action.duplicate(true) as MeleeAttackActionDefinition
	stacking_action.attack_profile = stacking_action.attack_profile.duplicate(true) as MeleeAttackProfile
	stacking_action.attack_profile.damage_multiplier = 1.5
	stacking_weapon.primary_action = stacking_action
	var definitions: Array[ItemDefinition] = []
	definitions.assign(source.definitions)
	definitions.append(stacking_weapon)
	var catalog := ItemCatalog.new()
	catalog.equipment_types = source.equipment_types
	catalog.definitions = definitions
	return catalog

func _create_slot_tooltip(context: String) -> ItemTooltip:
	var tooltip := _slot._make_custom_tooltip(_slot.tooltip_text) as ItemTooltip
	if tooltip == null:
		_errors.append("%s tooltip was not created" % context)
		return null
	root.add_child(tooltip)
	return tooltip

func _rune_ids(values: Array[StringName]) -> Array[StringName]:
	return values

func _finish() -> void:
	if _errors.is_empty():
		print("RUNE_TOOLTIP PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
