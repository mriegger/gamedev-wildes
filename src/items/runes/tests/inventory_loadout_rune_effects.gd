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
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	inventory.setup_empty()
	InventoryTestFixture.restore_slot(inventory, 0, _equipment_stack(inventory, &"copper_sword", basic_rune_ids))
	InventoryTestFixture.restore_slot(inventory, 1, InventoryStack.new(&"sand_block", 1))
	InventoryTestFixture.restore_slot(inventory, InventoryModel.HOTBAR_SIZE, _equipment_stack(inventory, &"copper_helmet", basic_rune_ids))
	InventoryTestFixture.restore_slot(inventory, InventoryModel.HOTBAR_SIZE + 1, _equipment_stack(inventory, &"copper_chest_plate", basic_rune_ids))

	var stats := ActorStats.new(stats_definition)
	var coordinator := InventoryLoadoutCoordinator.new()
	_expect(coordinator.setup(inventory, stats, ItemProficiency.new(item_catalog)), "inventory loadout coordinator setup failed")
	_expect(is_equal_approx(stats.get_value(&"hp"), 200.0), "selected weapon rune did not increase maximum HP")
	_expect(is_equal_approx(stats.current_hp, 200.0), "selected weapon rune did not preserve full health")
	_expect(stats.has_modifier(&"socketed_runes_0"), "selected weapon rune modifier is missing")
	_expect(not stats.has_modifier(&"socketed_runes_1"), "unequipped armor rune became active")

	_expect(stats.set_current_hp(74.0), "rune health-ratio setup failed")
	_expect(coordinator.add_backpack_item(&"sand_block", 1), "unrelated inventory change setup failed")
	_expect(is_equal_approx(stats.get_value(&"hp"), 200.0), "unrelated inventory change altered rune maximum HP")
	_expect(is_equal_approx(stats.current_hp, 74.0), "unrelated inventory change altered current HP")

	var helmet_index := InventoryModel.get_equipment_index(ArmorDefinition.Slot.HEAD)
	var chest_index := InventoryModel.get_equipment_index(ArmorDefinition.Slot.CHEST)
	_expect(coordinator.handle_drop(InventoryModel.HOTBAR_SIZE, helmet_index, 1), "socketed helmet equip failed")
	_expect(is_equal_approx(stats.get_value(&"hp"), 300.0), "equipped helmet rune did not stack")
	_expect(is_equal_approx(stats.current_hp, 111.0), "helmet rune did not preserve health percentage")
	_expect(coordinator.handle_drop(InventoryModel.HOTBAR_SIZE + 1, chest_index, 1), "socketed chest armor equip failed")
	_expect(is_equal_approx(stats.get_value(&"hp"), 400.0), "equipped armor runes did not stack with weapon rune")
	_expect(is_equal_approx(stats.current_hp, 148.0), "stacked armor runes did not preserve health percentage")
	_expect(stats.has_modifier(&"socketed_runes_2"), "stacked rune modifier is missing")

	_expect(coordinator.select_slot(1), "non-weapon selection failed")
	_expect(is_equal_approx(stats.get_value(&"hp"), 300.0), "unselected weapon rune remained active")
	_expect(is_equal_approx(stats.current_hp, 111.0), "weapon rune deactivation did not preserve health percentage")
	_expect(not stats.has_modifier(&"socketed_runes_2"), "unselected weapon rune modifier remained active")
	_expect(coordinator.select_slot(0), "weapon reselection failed")
	_expect(is_equal_approx(stats.get_value(&"hp"), 400.0), "reselected weapon rune did not reactivate")
	_expect(is_equal_approx(stats.current_hp, 148.0), "weapon rune reactivation did not preserve health percentage")

	_expect(coordinator.unsocket_rune(helmet_index, basic_rune_ids, no_rune_ids, &"basic_rune"), "equipped helmet rune removal failed")
	_expect(is_equal_approx(stats.get_value(&"hp"), 300.0), "removed armor rune remained active")
	_expect(is_equal_approx(stats.current_hp, 111.0), "armor rune removal did not preserve health percentage")
	_expect(coordinator.handle_drop(chest_index, InventoryModel.HOTBAR_SIZE + 1, 1), "socketed chest armor unequip failed")
	_expect(is_equal_approx(stats.get_value(&"hp"), 200.0), "unequipped armor rune remained active")
	_expect(is_equal_approx(stats.current_hp, 74.0), "armor rune unequip did not preserve health percentage")

	if _errors.is_empty():
		print("INVENTORY_LOADOUT_RUNE_EFFECTS PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)

func _equipment_stack(
	inventory: InventoryModel,
	item_id: StringName,
	rune_ids: Array[StringName],
) -> InventoryStack:
	var affixes: Array[EquipmentAffixDefinition] = []
	var instance := inventory.equipment_instance_factory.create(item_id, affixes, rune_ids)
	assert(instance != null)
	return InventoryStack.new(item_id, 1, instance)
