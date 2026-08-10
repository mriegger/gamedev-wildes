extends SceneTree

const ARMOR_IDS: Array[StringName] = [
	&"copper_helmet",
	&"copper_chest_plate",
	&"copper_pants",
	&"copper_shoes",
]
const DEFENSE_VALUES: Array[float] = [1.0, 3.0, 2.0, 1.0]

var _errors: Array[String] = []
var _inventory_change_count: int = 0
var _invalid_signal_count: int = 0

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var stats_definition := load("res://player/player_stats.tres") as ActorStatsDefinition
	_expect(block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog.validate(block_catalog), "item catalog invalid")
	_expect(stats_definition.validate(), "player stats invalid")
	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		var armor := item_catalog.get_definition(ARMOR_IDS[armor_slot]) as ArmorDefinition
		_expect(armor != null, "armor definition missing for slot %d" % armor_slot)
		if armor == null:
			continue
		_expect(armor.armor_slot == armor_slot, "armor slot mismatch for %s" % armor.id)
		_expect(armor.max_stack == 1, "armor stack limit mismatch for %s" % armor.id)
		_expect(armor.stat_modifier_activation == ItemDefinition.StatModifierActivation.EQUIPPED, "armor activation mismatch for %s" % armor.id)
		_expect(armor.stat_modifiers.size() == 1, "armor modifier missing for %s" % armor.id)
		if armor.stat_modifiers.size() == 1:
			_expect(armor.stat_modifiers[0].stat_id == &"defense", "armor modifier stat mismatch for %s" % armor.id)
			_expect(is_equal_approx(armor.stat_modifiers[0].amount, DEFENSE_VALUES[armor_slot]), "armor defense mismatch for %s" % armor.id)
		_expect(armor.resource_path.ends_with(".tres"), "armor is not a tres resource for %s" % armor.id)

	var selected_armor_inventory := InventoryModel.new(item_catalog)
	selected_armor_inventory.setup_starter()
	var selected_armor_source := _find_item(selected_armor_inventory, &"copper_helmet")
	_expect(selected_armor_inventory.handle_drop(selected_armor_source, 4, 1), "selected armor setup move failed")
	_expect(selected_armor_inventory.select_slot(4), "selected armor hotbar selection failed")
	var selected_armor_stats := ActorStats.new(stats_definition)
	var selected_armor_coordinator := InventoryStatCoordinator.new()
	_expect(selected_armor_coordinator.setup(selected_armor_inventory, selected_armor_stats), "selected armor coordinator setup failed")
	_expect(is_equal_approx(selected_armor_stats.get_value(&"defense"), 0.0), "selected armor applied equipped modifiers")
	var selected_helmet_index := InventoryModel.get_equipment_index(ArmorDefinition.Slot.HELMET)
	_expect(selected_armor_inventory.handle_drop(4, selected_helmet_index, 1), "direct equipment model move failed")
	_expect(is_equal_approx(selected_armor_stats.get_value(&"defense"), 1.0), "direct equipment model move did not synchronize stats")
	_expect(selected_armor_inventory.handle_drop(selected_helmet_index, 4, 1), "direct equipment model return failed")
	_expect(is_equal_approx(selected_armor_stats.get_value(&"defense"), 0.0), "direct equipment model return retained stats")

	var selected_item_inventory := InventoryModel.new(item_catalog)
	selected_item_inventory.setup_starter()
	var totem_source := _find_item(selected_item_inventory, &"test_totem")
	_expect(selected_item_inventory.handle_drop(totem_source, 4, 1), "selected modifier item setup move failed")
	_expect(selected_item_inventory.select_slot(4), "selected modifier item selection failed")
	var selected_item_stats := ActorStats.new(stats_definition)
	var selected_item_coordinator := InventoryStatCoordinator.new()
	_expect(selected_item_coordinator.setup(selected_item_inventory, selected_item_stats), "selected modifier coordinator setup failed")
	_expect(is_equal_approx(selected_item_stats.get_value(&"hp"), 200.0), "selected item maximum HP modifier missing")
	_expect(selected_item_stats.set_current_hp(150.0), "selected item current HP setup failed")
	var selected_item_helmet_source := _find_item(selected_item_inventory, &"copper_helmet")
	_expect(selected_item_coordinator.try_equip_armor(selected_item_helmet_source), "armor equip with selected modifier item failed")
	_expect(is_equal_approx(selected_item_stats.current_hp, 150.0), "armor inventory change clamped selected-item HP")
	_expect(is_equal_approx(selected_item_stats.get_value(&"defense"), 1.0), "selected and equipped modifiers did not coexist")
	var selected_item_snapshot := selected_item_inventory.to_dict()
	var selected_progression := selected_item_stats.snapshot_progression()
	var selected_restore_inventory := InventoryModel.new(item_catalog)
	_expect(selected_restore_inventory.from_dict(selected_item_snapshot), "selected-item inventory restore failed")
	var selected_restore_stats := ActorStats.new(stats_definition)
	var selected_restore_coordinator := InventoryStatCoordinator.new()
	_expect(selected_restore_coordinator.setup(selected_restore_inventory, selected_restore_stats), "selected-item restored coordinator setup failed")
	_expect(selected_restore_stats.restore_progression(selected_progression), "selected-item progression restore failed")
	_expect(is_equal_approx(selected_restore_stats.current_hp, 150.0), "selected-item load order clamped restored HP")
	_expect(selected_restore_inventory.select_slot(0), "selected modifier deactivation selection failed")
	_expect(is_equal_approx(selected_restore_stats.get_value(&"hp"), 100.0), "selected modifier remained active after selection changed")
	_expect(is_equal_approx(selected_restore_stats.current_hp, 100.0), "selected modifier removal did not clamp current HP")
	_expect(selected_restore_inventory.select_slot(4), "selected modifier reactivation selection failed")
	_expect(is_equal_approx(selected_restore_stats.get_value(&"hp"), 200.0), "selected modifier did not reactivate")
	_expect(is_equal_approx(selected_restore_stats.current_hp, 100.0), "selected modifier reactivation healed current HP")

	var inventory := InventoryModel.new(item_catalog)
	inventory.setup_starter()
	var stats := ActorStats.new(stats_definition)
	var coordinator := InventoryStatCoordinator.new()
	_expect(coordinator.setup(inventory, stats), "equipment coordinator setup failed")
	inventory.inventory_changed.connect(_on_inventory_changed)
	var observed_defense: Array[float] = []
	inventory.inventory_changed.connect(func(): observed_defense.append(stats.get_value(&"defense")))
	var unchanged_count := _inventory_change_count
	_expect(not coordinator.try_equip_armor(0), "non-armor item equipped")
	_expect(_inventory_change_count == unchanged_count, "failed equip emitted a change")
	_expect(is_equal_approx(stats.get_value(&"defense"), 0.0), "failed equip changed defense")
	var helmet_source := _find_item(inventory, &"copper_helmet")
	var chest_index := InventoryModel.get_equipment_index(ArmorDefinition.Slot.CHEST_PLATE)
	_expect(not coordinator.can_handle_drop(helmet_source, chest_index, 1), "helmet accepted by chest slot")

	var expected_defense := 0.0
	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		var source := _find_item(inventory, ARMOR_IDS[armor_slot])
		var equipment_index := InventoryModel.get_equipment_index(armor_slot)
		var changes_before := _inventory_change_count
		_expect(source >= 0, "starter armor missing for slot %d" % armor_slot)
		_expect(coordinator.try_equip_armor(source), "armor equip failed for slot %d" % armor_slot)
		expected_defense += DEFENSE_VALUES[armor_slot]
		var equipped := inventory.get_slot(equipment_index)
		_expect(equipped != null and equipped.item_id == ARMOR_IDS[armor_slot], "equipped item mismatch for slot %d" % armor_slot)
		_expect(is_equal_approx(stats.get_value(&"defense"), expected_defense), "equipped defense mismatch for slot %d" % armor_slot)
		_expect(not observed_defense.is_empty() and is_equal_approx(observed_defense.back(), expected_defense), "inventory observer saw stale defense for slot %d" % armor_slot)
		_expect(stats.has_modifier(StringName("equipment_slot_%d_0" % armor_slot)), "equipment modifier ID missing for slot %d" % armor_slot)
		_expect(_inventory_change_count == changes_before + 1, "equip emitted the wrong change count for slot %d" % armor_slot)

	var encoded := inventory.to_dict()
	var restored_inventory := InventoryModel.new(item_catalog)
	_expect(restored_inventory.from_dict(encoded), "equipped armor did not restore")
	var restored_stats := ActorStats.new(stats_definition)
	var restored_coordinator := InventoryStatCoordinator.new()
	_expect(restored_coordinator.setup(restored_inventory, restored_stats), "restored equipment coordinator setup failed")
	_expect(is_equal_approx(restored_stats.get_value(&"defense"), 7.0), "restored armor defense mismatch")

	var restored_before_invalid := restored_inventory.to_dict()
	var wrong_slot_save := encoded.duplicate(true)
	wrong_slot_save["regions"]["equipment"][ArmorDefinition.Slot.HELMET] = {"item_id": "copper_chest_plate", "count": 1}
	_expect(not restored_inventory.from_dict(wrong_slot_save), "wrong-slot armor save restored")
	_expect(restored_inventory.to_dict() == restored_before_invalid, "failed wrong-slot restore changed inventory")
	var stacked_armor_save := encoded.duplicate(true)
	stacked_armor_save["regions"]["equipment"][ArmorDefinition.Slot.HELMET]["count"] = 2
	_expect(not restored_inventory.from_dict(stacked_armor_save), "stacked armor save restored")
	_expect(restored_inventory.to_dict() == restored_before_invalid, "failed stacked restore changed inventory")

	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		var equipment_index := InventoryModel.get_equipment_index(armor_slot)
		_expect(restored_coordinator.try_unequip_armor(equipment_index), "armor unequip failed for slot %d" % armor_slot)
		expected_defense -= DEFENSE_VALUES[armor_slot]
		_expect(restored_inventory.get_slot(equipment_index) == null, "equipment slot not cleared for slot %d" % armor_slot)
		_expect(_find_item(restored_inventory, ARMOR_IDS[armor_slot]) >= 0, "unequipped armor did not return to inventory for slot %d" % armor_slot)
		_expect(is_equal_approx(restored_stats.get_value(&"defense"), expected_defense), "unequipped defense mismatch for slot %d" % armor_slot)

	var blocked := InventoryModel.new(item_catalog)
	blocked.setup_starter()
	var blocked_stats := ActorStats.new(stats_definition)
	var blocked_coordinator := InventoryStatCoordinator.new()
	_expect(blocked_coordinator.setup(blocked, blocked_stats), "blocked equipment coordinator setup failed")
	var blocked_helmet_source := _find_item(blocked, &"copper_helmet")
	var helmet_index := InventoryModel.get_equipment_index(ArmorDefinition.Slot.HELMET)
	_expect(blocked_coordinator.try_equip_armor(blocked_helmet_source), "blocked inventory helmet setup failed")
	var grass_id := item_catalog.get_item_for_block(BlockId.Type.GRASS).id
	for index in range(InventoryModel.FILLABLE_SIZE):
		if blocked.get_slot(index) == null:
			blocked.slots[index] = InventoryStack.new(grass_id, 1)
	var blocked_before := blocked.to_dict()
	_expect(not blocked_coordinator.try_unequip_armor(helmet_index), "full inventory accepted unequipped armor")
	_expect(blocked.to_dict() == blocked_before, "failed unequip changed inventory")
	_expect(is_equal_approx(blocked_stats.get_value(&"defense"), 1.0), "failed unequip removed armor defense")

	var invalid_definitions: Array[ItemDefinition] = []
	for source_definition in item_catalog.definitions:
		invalid_definitions.append(source_definition.duplicate(true) as ItemDefinition)
	var invalid_catalog := ItemCatalog.new()
	invalid_catalog.definitions = invalid_definitions
	var invalid_inventory := InventoryModel.new(invalid_catalog)
	invalid_inventory.setup_starter()
	var invalid_stats := ActorStats.new(stats_definition)
	var invalid_coordinator := InventoryStatCoordinator.new()
	_expect(invalid_coordinator.setup(invalid_inventory, invalid_stats), "valid duplicated equipment setup failed")
	var invalid_helmet := invalid_catalog.get_definition(&"copper_helmet") as ArmorDefinition
	invalid_helmet.stat_modifiers[0].stat_id = &"unknown_stat"
	var invalid_source := _find_item(invalid_inventory, &"copper_helmet")
	var invalid_before := invalid_inventory.to_dict()
	_invalid_signal_count = 0
	invalid_inventory.inventory_changed.connect(_on_invalid_inventory_changed)
	_expect(not invalid_coordinator.try_equip_armor(invalid_source), "invalid armor modifiers equipped")
	_expect(invalid_inventory.to_dict() == invalid_before, "invalid modifier equip changed inventory")
	_expect(is_equal_approx(invalid_stats.get_value(&"defense"), 0.0), "invalid modifier equip changed stats")
	_expect(_invalid_signal_count == 0, "invalid modifier equip emitted inventory change")

	var legacy_source := InventoryModel.new(item_catalog)
	legacy_source.setup_starter()
	var legacy_encoded := legacy_source.to_dict()
	for backpack_offset in range(legacy_encoded["regions"]["backpack"].size()):
		var raw = legacy_encoded["regions"]["backpack"][backpack_offset]
		if raw != null and ARMOR_IDS.has(StringName(raw["item_id"])):
			legacy_encoded["regions"]["backpack"][backpack_offset] = null
	legacy_encoded["starter_item_migration_version"] = 2
	var legacy := InventoryModel.new(item_catalog)
	_expect(legacy.from_dict(legacy_encoded), "pre-armor inventory did not restore")
	_expect(legacy.migrate_starter_items(), "pre-armor inventory migration failed")
	for armor_id in ARMOR_IDS:
		_expect(_find_item(legacy, armor_id) >= 0, "migrated armor missing for %s" % armor_id)

	var crowded := InventoryModel.new(item_catalog)
	for index in range(InventoryModel.FILLABLE_SIZE):
		crowded.slots[index] = InventoryStack.new(grass_id, 1)
	crowded.slots[InventoryModel.FILLABLE_SIZE - 1] = null
	crowded.slots[InventoryModel.FILLABLE_SIZE - 2] = null
	var crowded_before := crowded.to_dict()
	_expect(not crowded.migrate_starter_items(), "crowded inventory completed starter migration")
	_expect(crowded.to_dict() == crowded_before, "failed starter migration partially changed inventory")

	if _errors.is_empty():
		print("ARMOR_SYSTEM PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _find_item(inventory: InventoryModel, item_id: StringName) -> int:
	for index in range(inventory.size):
		var stack := inventory.get_slot(index)
		if stack != null and stack.item_id == item_id:
			return index
	return -1

func _on_inventory_changed() -> void:
	_inventory_change_count += 1

func _on_invalid_inventory_changed() -> void:
	_invalid_signal_count += 1

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
