extends SceneTree

var _errors: Array[String] = []

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var stats_definition := load("res://player/player_stats.tres") as ActorStatsDefinition
	_expect(block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog.validate(block_catalog), "item catalog invalid")
	_expect(stats_definition.validate(), "player stats invalid")

	var basic_rune_ids: Array[StringName] = [&"basic_rune"]
	var no_rune_ids: Array[StringName] = []
	var inventory := InventoryModel.new(item_catalog)
	inventory.setup_empty()
	inventory.slots[0] = InventoryStack.new(&"copper_sword", 1, basic_rune_ids)
	inventory.slots[1] = InventoryStack.new(&"sand_block", 1)
	inventory.slots[InventoryModel.HOTBAR_SIZE] = InventoryStack.new(&"copper_helmet", 1, basic_rune_ids)
	inventory.slots[InventoryModel.HOTBAR_SIZE + 1] = InventoryStack.new(&"copper_chest_plate", 1, basic_rune_ids)

	var stats := ActorStats.new(stats_definition)
	var coordinator := RuneEffectCoordinator.new()
	_expect(coordinator.setup(inventory, stats), "rune effect coordinator setup failed")
	_expect(is_equal_approx(stats.get_value(&"hp"), 200.0), "selected weapon rune did not increase maximum HP")
	_expect(is_equal_approx(stats.current_hp, 200.0), "selected weapon rune did not preserve full health")
	_expect(stats.has_modifier(&"socketed_runes_0"), "selected weapon rune modifier is missing")
	_expect(not stats.has_modifier(&"socketed_runes_1"), "unequipped armor rune became active")

	_expect(stats.set_current_hp(74.0), "rune health-ratio setup failed")
	_expect(inventory.add_backpack_item(&"sand_block", 1), "unrelated inventory change setup failed")
	_expect(is_equal_approx(stats.get_value(&"hp"), 200.0), "unrelated inventory change altered rune maximum HP")
	_expect(is_equal_approx(stats.current_hp, 74.0), "unrelated inventory change altered current HP")

	var helmet_index := InventoryModel.get_equipment_index(ArmorDefinition.Slot.HEAD)
	var chest_index := InventoryModel.get_equipment_index(ArmorDefinition.Slot.CHEST)
	_expect(inventory.handle_drop(InventoryModel.HOTBAR_SIZE, helmet_index, 1), "socketed helmet equip failed")
	_expect(is_equal_approx(stats.get_value(&"hp"), 300.0), "equipped helmet rune did not stack")
	_expect(is_equal_approx(stats.current_hp, 111.0), "helmet rune did not preserve health percentage")
	_expect(inventory.handle_drop(InventoryModel.HOTBAR_SIZE + 1, chest_index, 1), "socketed chest armor equip failed")
	_expect(is_equal_approx(stats.get_value(&"hp"), 400.0), "equipped armor runes did not stack with weapon rune")
	_expect(is_equal_approx(stats.current_hp, 148.0), "stacked armor runes did not preserve health percentage")
	_expect(stats.has_modifier(&"socketed_runes_2"), "stacked rune modifier is missing")

	_expect(inventory.select_slot(1), "non-weapon selection failed")
	_expect(is_equal_approx(stats.get_value(&"hp"), 300.0), "unselected weapon rune remained active")
	_expect(is_equal_approx(stats.current_hp, 111.0), "weapon rune deactivation did not preserve health percentage")
	_expect(not stats.has_modifier(&"socketed_runes_2"), "unselected weapon rune modifier remained active")
	_expect(inventory.select_slot(0), "weapon reselection failed")
	_expect(is_equal_approx(stats.get_value(&"hp"), 400.0), "reselected weapon rune did not reactivate")
	_expect(is_equal_approx(stats.current_hp, 148.0), "weapon rune reactivation did not preserve health percentage")

	_expect(inventory.commit_unsocketed_rune(helmet_index, basic_rune_ids, no_rune_ids, &"basic_rune"), "equipped helmet rune removal failed")
	_expect(is_equal_approx(stats.get_value(&"hp"), 300.0), "removed armor rune remained active")
	_expect(is_equal_approx(stats.current_hp, 111.0), "armor rune removal did not preserve health percentage")
	_expect(inventory.handle_drop(chest_index, InventoryModel.HOTBAR_SIZE + 1, 1), "socketed chest armor unequip failed")
	_expect(is_equal_approx(stats.get_value(&"hp"), 200.0), "unequipped armor rune remained active")
	_expect(is_equal_approx(stats.current_hp, 74.0), "armor rune unequip did not preserve health percentage")

	var unsafe_definitions: Array[ItemDefinition] = []
	for definition in item_catalog.definitions:
		unsafe_definitions.append(definition.duplicate(true) as ItemDefinition)
	var unsafe_catalog := ItemCatalog.new()
	unsafe_catalog.definitions = unsafe_definitions
	var unsafe_rune := unsafe_catalog.get_definition(&"basic_rune") as RuneDefinition
	unsafe_rune.socket_modifiers[0].amount = -10.0
	var unsafe_stats := ActorStats.new(stats_definition)
	_expect(
		unsafe_stats.can_replace_source_modifiers(&"fixture", &"fixture", unsafe_rune.socket_modifiers),
		"unsafe catalog fixture was not individually valid",
	)
	var unsafe_coordinator := RuneEffectCoordinator.new()
	_expect(
		not unsafe_coordinator._can_apply_maximum_active_loadout(unsafe_catalog, unsafe_stats),
		"rune catalog with an invalid maximum active loadout was accepted",
	)

	if _errors.is_empty():
		print("RUNE_EFFECT_COORDINATOR PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
