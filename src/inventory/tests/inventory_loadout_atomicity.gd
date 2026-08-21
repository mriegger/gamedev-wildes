extends SceneTree

var _errors: Array[String] = []
var _item_catalog: ItemCatalog
var _stats_definition: ActorStatsDefinition

func _init() -> void:
	_item_catalog = load("res://items/item_catalog.tres") as ItemCatalog
	_stats_definition = load("res://player/player_stats.tres") as ActorStatsDefinition
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	_expect(_item_catalog != null and _item_catalog.validate(block_catalog), "item catalog invalid")
	_expect(_stats_definition != null and _stats_definition.validate(), "stats definition invalid")
	_test_prepared_guards()
	_test_exact_multi_stack_preparation()
	_test_constrained_inventory_bounds()
	_test_equipped_item_toggle()
	_test_owner_bindings()
	_test_reserved_stat_sources()
	_test_deep_copy_isolation()
	_test_prepared_stat_copy_isolation()
	_test_dormant_affix_schema_rejection()
	_test_observer_order_and_stat_noop()
	_test_invalid_combined_projection()
	_test_invalid_combined_affixes()
	_test_taxonomy_rune_activation()
	_test_invalid_active_runes()
	_test_timed_projection_expiry()
	_test_invalid_intermediate_final_projection()
	_test_chest_rollback(block_catalog)
	if _errors.is_empty():
		print("INVENTORY_LOADOUT_ATOMICITY PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _test_prepared_guards() -> void:
	var inventory := _empty_inventory()
	var stats := ActorStats.new(_stats_definition)
	var loadout := _bind(inventory, stats)
	var stale_inventory_change := inventory.prepare_add_backpack_item(&"sand_block", 1)
	var stale_inventory := loadout.prepare_inventory_change(stale_inventory_change)
	_expect(stale_inventory != null, "inventory-stale change did not prepare")
	_expect(loadout.add_backpack_item(&"dirt_block", 1), "inventory-stale setup mutation failed")
	var inventory_after_mutation := inventory.to_dict()
	_expect(not loadout.commit_prepared_change(stale_inventory), "stale inventory change committed")
	_expect(inventory.to_dict() == inventory_after_mutation, "stale inventory commit changed inventory")

	var stat_inventory := _empty_inventory()
	var stat_owner := ActorStats.new(_stats_definition)
	var stat_loadout := _bind(stat_inventory, stat_owner)
	var stale_stat := stat_loadout.prepare_inventory_change(stat_inventory.prepare_add_backpack_item(&"sand_block", 1))
	_expect(stale_stat != null, "stat-stale change did not prepare")
	stat_owner.damage(1.0)
	var stat_inventory_before := stat_inventory.to_dict()
	_expect(not stat_loadout.commit_prepared_change(stale_stat), "stale stat change committed")
	_expect(stat_inventory.to_dict() == stat_inventory_before, "stale stat commit changed inventory")

	var allocator_inventory := _empty_inventory()
	var allocator_stats := ActorStats.new(_stats_definition)
	var allocator_loadout := _bind(allocator_inventory, allocator_stats)
	var equipment_ids: Array[StringName] = [&"copper_sword"]
	var allocator_change := allocator_loadout.prepare_inventory_change(allocator_inventory.prepare_add_batch(equipment_ids))
	_expect(allocator_change != null, "allocator-bound change did not prepare")
	var allocated := allocator_inventory.equipment_instance_factory.create(&"copper_sword")
	_expect(allocated != null, "allocator drift fixture did not allocate")
	var allocator_before := allocator_inventory.to_dict()
	_expect(not allocator_loadout.commit_prepared_change(allocator_change), "allocator-stale change committed")
	_expect(allocator_inventory.to_dict() == allocator_before, "allocator-stale commit changed inventory")

	var first_stats := ActorStats.new(_stats_definition)
	var second_stats := ActorStats.new(_stats_definition)
	var stat_change := first_stats.prepare_noop_change()
	_expect(not second_stats.can_commit_prepared_modifier_change(stat_change), "cross-owner stat change was accepted")
	var first_inventory := _empty_inventory()
	var second_inventory := _empty_inventory()
	var inventory_change := first_inventory.prepare_add_backpack_item(&"sand_block", 1)
	_expect(not second_inventory.can_commit_prepared_change(inventory_change), "cross-owner inventory change was accepted")

func _test_exact_multi_stack_preparation() -> void:
	var constrained := _empty_inventory()
	var max_stack := _item_catalog.get_definition(&"dirt_block").max_stack
	for index in range(InventoryModel.FILLABLE_SIZE - 1):
		_expect(
			InventoryTestFixture.restore_slot(
				constrained,
				index,
				InventoryStack.new(&"dirt_block", max_stack),
			),
			"exact multi-stack capacity fixture failed at %d" % index,
		)
	var constrained_before := constrained.to_dict()
	var constrained_revision := constrained.get_revision()
	var oversized: Array[InventoryStack] = [
		InventoryStack.new(&"copper", 1),
		InventoryStack.new(&"basic_rune", 1),
	]
	_expect(
		constrained.prepare_add_stacks_exact(oversized) == null,
		"exact multi-stack preparation accepted a partial batch",
	)
	_expect(constrained.to_dict() == constrained_before, "failed exact multi-stack preparation changed inventory")
	_expect(constrained.get_revision() == constrained_revision, "failed exact multi-stack preparation revised inventory")
	_expect(constrained.prepare_add_stacks_exact([]) == null, "empty exact multi-stack preparation produced a change")

	var inventory := _empty_inventory()
	var sword := inventory.equipment_instance_factory.create(&"copper_sword")
	var batch: Array[InventoryStack] = [
		InventoryStack.new(&"copper", 3),
		InventoryStack.new(&"copper_sword", 1, sword),
	]
	var inventory_before := inventory.to_dict()
	var revision_before := inventory.get_revision()
	var prepared_inventory := inventory.prepare_add_stacks_exact(batch)
	_expect(prepared_inventory != null, "valid exact multi-stack batch did not prepare")
	_expect(inventory.to_dict() == inventory_before, "exact multi-stack preparation changed live inventory")
	_expect(inventory.get_revision() == revision_before, "exact multi-stack preparation revised live inventory")
	batch[0].count = 99
	batch[1].equipment_instance.socketed_rune_ids.append(&"basic_rune")
	var loadout := _bind(inventory, ActorStats.new(_stats_definition))
	var prepared_loadout := loadout.prepare_inventory_change(prepared_inventory)
	_expect(prepared_loadout != null, "valid exact multi-stack batch did not prepare through loadout")
	_expect(loadout.commit_prepared_change(prepared_loadout), "valid exact multi-stack batch did not commit")
	var copper_index := _find_item(inventory, &"copper")
	var sword_index := _find_item(inventory, &"copper_sword")
	_expect(copper_index >= 0 and inventory.get_slot(copper_index).count == 3, "exact batch input mutation changed basic reward")
	_expect(
		sword_index >= 0 and inventory.get_slot(sword_index).equipment_instance.socketed_rune_ids.is_empty(),
		"exact batch input mutation changed equipment reward",
	)

func _test_constrained_inventory_bounds() -> void:
	var inventory := InventoryModel.new(
		_item_catalog,
		EquipmentInstanceFactory.new(_item_catalog),
		InventoryModel.HOTBAR_SIZE + 1,
	)
	var before := inventory.to_dict()
	_expect(not inventory.setup_starter(), "constrained inventory accepted fixed starter layout")
	_expect(inventory.to_dict() == before, "rejected constrained starter layout changed inventory")
	_expect(inventory.prepare_starter_item_migration() == null, "constrained inventory accepted oversized starter migration")
	_expect(inventory.to_dict() == before, "rejected constrained starter migration changed inventory")
	_expect(inventory.prepare_select_slot(InventoryModel.HOTBAR_SIZE - 1) != null, "constrained inventory rejected its last hotbar slot")
	_expect(inventory.prepare_select_slot(InventoryModel.HOTBAR_SIZE) == null, "constrained inventory selected a backpack slot")

func _test_equipped_item_toggle() -> void:
	var inventory := _empty_inventory()
	_expect(not inventory.is_item_equipped() and inventory.get_selected_data() == null, "empty inventory did not start unequipped")
	InventoryTestFixture.restore_slot(inventory, 0, InventoryStack.new(&"test_totem", 1))
	InventoryTestFixture.restore_slot(inventory, 2, InventoryStack.new(&"sand_block", 1))
	var stats := ActorStats.new(_stats_definition)
	var loadout := _bind(inventory, stats)
	_expect(inventory.is_item_equipped() and stats.has_modifier(&"selected_item_0"), "selected fixture item was not equipped")
	_expect(loadout.activate_hotbar_slot(0), "active hotbar key did not unequip its item")
	_expect(not inventory.is_item_equipped() and inventory.get_selected_data() == null, "active hotbar key retained the equipped item")
	_expect(not stats.has_modifier(&"selected_item_0"), "unequipped hotbar item retained its stat modifier")
	_expect(loadout.activate_hotbar_slot(0), "repeated hotbar key did not re-equip its item")
	_expect(inventory.is_item_equipped() and inventory.get_selected_item_id() == &"test_totem", "repeated hotbar key restored the wrong item")
	_expect(loadout.toggle_last_equipped_item(), "R-style toggle did not unequip the current item")
	_expect(not inventory.is_item_equipped(), "R-style toggle retained the current item")
	_expect(loadout.activate_hotbar_slot(2), "different hotbar key did not equip its item")
	_expect(inventory.is_item_equipped() and inventory.get_selected_slot() == 2 and inventory.get_selected_item_id() == &"sand_block", "different hotbar key equipped the wrong item")
	_expect(loadout.toggle_last_equipped_item(), "R-style toggle did not unequip the replacement item")
	_expect(loadout.toggle_last_equipped_item(), "second R-style toggle did not restore the most recent item")
	_expect(inventory.is_item_equipped() and inventory.get_selected_slot() == 2 and inventory.get_selected_item_id() == &"sand_block", "R-style toggle restored an older hotbar item")

func _test_owner_bindings() -> void:
	var shared_stats := ActorStats.new(_stats_definition)
	var first_inventory := _empty_inventory()
	var first := InventoryLoadoutCoordinator.new()
	_expect(first.setup(first_inventory, shared_stats, ItemProficiency.new(_item_catalog)), "first owner binding failed")
	var second_inventory := _empty_inventory()
	var second := InventoryLoadoutCoordinator.new()
	_expect(not second.setup(second_inventory, shared_stats, ItemProficiency.new(_item_catalog)), "actor stats accepted a second loadout owner")
	var replacement_stats := ActorStats.new(_stats_definition)
	_expect(second.setup(second_inventory, replacement_stats, ItemProficiency.new(_item_catalog)), "failed actor binding stranded the second inventory")
	var duplicate_inventory := InventoryLoadoutCoordinator.new()
	_expect(not duplicate_inventory.setup(first_inventory, ActorStats.new(_stats_definition), ItemProficiency.new(_item_catalog)), "inventory accepted a second loadout owner")

func _test_reserved_stat_sources() -> void:
	var setup_stats := ActorStats.new(_stats_definition)
	var setup_modifiers := _modifiers([_modifier(&"strength", 1.0)])
	_expect(
		setup_stats.replace_source_modifiers(&"setup", InventoryLoadoutCoordinator.SELECTED_ITEM_INSTANCE_ID, setup_modifiers),
		"pre-bind reserved-name setup replacement failed",
	)
	_expect(
		setup_stats.remove_modifiers_from_source_instance(InventoryLoadoutCoordinator.SELECTED_ITEM_INSTANCE_ID) == 1,
		"pre-bind reserved-name setup removal failed",
	)

	var stats := ActorStats.new(_stats_definition)
	var prebound_replacement := StatModifierReplacement.new(
		&"prebound",
		InventoryLoadoutCoordinator.SELECTED_ITEM_INSTANCE_ID,
		setup_modifiers,
	)
	var prebound_replacements: Array[StatModifierReplacement] = [prebound_replacement]
	var prebound_change := stats.prepare_modifier_sources(prebound_replacements)
	_expect(prebound_change != null, "pre-bind reserved-source change did not prepare")
	var loadout := _bind(_empty_inventory(), stats)
	_expect(
		prebound_change != null and prebound_change.get_expected_revision() == stats.get_revision(),
		"pre-bind reserved-source bypass fixture became stale",
	)
	_expect(
		prebound_change != null and not stats.can_commit_prepared_modifier_change(prebound_change),
		"pre-bind reserved-source change remained committable after binding",
	)

	var direct := _modifier(&"strength", 1.0)
	direct.id = &"reserved_direct"
	direct.source_instance_id = InventoryLoadoutCoordinator.SELECTED_ITEM_INSTANCE_ID
	_expect(not stats.add_modifier(direct), "public add entered a loadout-owned source")
	_expect(
		not stats.can_replace_source_modifiers(
			&"public",
			InventoryLoadoutCoordinator.SELECTED_ITEM_INSTANCE_ID,
			setup_modifiers,
		),
		"public replacement preflight accepted a loadout-owned source",
	)
	_expect(
		not stats.replace_source_modifiers(
			&"public",
			InventoryLoadoutCoordinator.SELECTED_ITEM_INSTANCE_ID,
			setup_modifiers,
		),
		"public replacement entered a loadout-owned source",
	)

	_expect(loadout.add_stack(InventoryStack.new(&"test_totem", 1)), "loadout-owned modifier fixture failed")
	_expect(
		loadout.assign_slot_to_hotbar(_find_item(loadout.inventory_model, &"test_totem"), 0),
		"loadout-owned modifier fixture could not select its item",
	)
	_expect(loadout.select_slot(0), "loadout-owned modifier fixture could not equip its item")
	_expect(stats.has_modifier(&"selected_item_0"), "loadout coordinator did not populate its reserved source")
	_expect(not stats.remove_modifier(&"selected_item_0"), "public removal erased a loadout-owned modifier")
	_expect(
		stats.remove_modifiers_from_source_instance(InventoryLoadoutCoordinator.SELECTED_ITEM_INSTANCE_ID) == 0,
		"public source removal erased loadout-owned modifiers",
	)
	_expect(stats.has_modifier(&"selected_item_0"), "rejected public removal changed loadout-owned modifiers")

	var external := _modifier(&"strength", 1.0)
	external.id = &"external_direct"
	external.source_instance_id = &"external_direct"
	_expect(stats.add_modifier(external), "binding blocked an unrelated public modifier add")
	_expect(stats.remove_modifier(external.id), "binding blocked an unrelated public modifier removal")
	_expect(
		stats.replace_source_modifiers(&"external", &"external_replacement", setup_modifiers),
		"binding blocked an unrelated public modifier replacement",
	)
	_expect(
		stats.remove_modifiers_from_source_instance(&"external_replacement") == 1,
		"binding blocked an unrelated public source removal",
	)

func _test_deep_copy_isolation() -> void:
	var inventory := _empty_inventory()
	InventoryTestFixture.restore_slot(inventory, 0, InventoryStack.new(&"sand_block", 5))
	var queried := inventory.get_slot(0)
	queried.count = 1
	_expect(inventory.get_slot(0).count == 5, "slot query exposed inventory state")
	var prepared := inventory.prepare_remove_stack(0, 2)
	var prepared_slot := prepared.get_slot(0)
	var prepared_result := prepared.get_result_stack()
	prepared_slot.count = 99
	prepared_result.count = 99
	_expect(prepared.get_slot(0).count == 3, "prepared slot query exposed prepared state")
	_expect(prepared.get_result_stack().count == 2, "prepared result query exposed prepared state")

func _test_prepared_stat_copy_isolation() -> void:
	var stats := ActorStats.new(_stats_definition)
	var replacement := StatModifierReplacement.new(
		&"atomic",
		&"atomic_copy",
		_modifiers([_modifier(&"strength", 2.0)]),
	)
	var replacements: Array[StatModifierReplacement] = [replacement]
	var prepared := stats.prepare_modifier_sources(replacements)
	_expect(prepared != null, "stat copy isolation fixture did not prepare")
	if prepared == null:
		return
	var copied := prepared._copy_modifiers()
	var modifier_id: StringName = copied.keys()[0]
	(copied[modifier_id] as StatModifier).amount = 90.0
	stats._commit_prepared_modifier_change(prepared)
	_expect(is_equal_approx(stats.get_value(&"strength"), 12.0), "prepared stat copy mutation changed committed stats")
	(prepared._modifiers[modifier_id] as StatModifier).amount = 80.0
	_expect(is_equal_approx(stats.get_value(&"strength"), 12.0), "committed stats retained a prepared modifier alias")

func _test_dormant_affix_schema_rejection() -> void:
	var inventory := _empty_inventory()
	var affixes: Array[EquipmentAffixDefinition] = [_item_catalog.get_equipment_affix(&"vicious")]
	var instance := inventory.equipment_instance_factory.create(&"copper_sword", affixes)
	InventoryTestFixture.restore_slot(inventory, InventoryModel.HOTBAR_SIZE, InventoryStack.new(&"copper_sword", 1, instance))
	var encoded := inventory.to_dict()
	encoded["regions"]["backpack"][0]["equipment_instance"]["affixes"][0]["stat_rolls"][0]["stat_id"] = "removed_stat"
	var restored := InventoryModel.new(
		_item_catalog,
		EquipmentInstanceFactory.new(_item_catalog, inventory.equipment_instance_factory.get_next_instance_id()),
	)
	var before := restored.to_dict()
	_expect(not restored.from_dict(encoded), "dormant affix with removed stat schema restored")
	_expect(restored.to_dict() == before, "failed dormant affix restore changed inventory")

func _test_observer_order_and_stat_noop() -> void:
	var inventory := InventoryModel.new(_item_catalog, EquipmentInstanceFactory.new(_item_catalog))
	inventory.setup_starter()
	var stats := ActorStats.new(_stats_definition)
	var loadout := _bind(inventory, stats)
	var helmet_source := _find_item(inventory, &"copper_helmet")
	var observed_defense: Array[float] = []
	var observer := func(): observed_defense.append(stats.get_value(&"defense"))
	inventory.inventory_changed.connect(observer)
	_expect(loadout.try_equip_armor(helmet_source), "observer-order helmet equip failed")
	_expect(observed_defense == [1.0], "inventory observer saw stale stats")
	inventory.inventory_changed.disconnect(observer)
	var stat_revision := stats.get_revision()
	var inventory_revision := inventory.get_revision()
	_expect(loadout.add_backpack_item(&"sand_block", 1), "stat no-op inventory change failed")
	_expect(inventory.get_revision() == inventory_revision + 1, "stat no-op did not commit inventory")
	_expect(stats.get_revision() == stat_revision, "stat no-op changed stat revision")

func _test_invalid_combined_projection() -> void:
	var inventory := InventoryModel.new(_item_catalog, EquipmentInstanceFactory.new(_item_catalog))
	inventory.setup_starter()
	var stats := ActorStats.new(_stats_definition)
	var loadout := _bind(inventory, stats)
	for armor_id in [&"copper_helmet", &"copper_chest_plate", &"copper_pants"]:
		_expect(loadout.try_equip_armor(_find_item(inventory, armor_id)), "combined projection setup equip failed for %s" % armor_id)
	var shoes := _item_catalog.get_definition(&"copper_shoes") as ArmorDefinition
	var armor_set := shoes.armor_set
	var original_shoes_modifiers := shoes.stat_modifiers
	var original_set_modifiers := armor_set.full_set_modifiers
	shoes.stat_modifiers = _modifiers([_modifier(&"hp", -60.0)])
	armor_set.full_set_modifiers = _modifiers([_modifier(&"hp", -60.0)])
	var before_inventory := inventory.to_dict()
	var before_stat_revision := stats.get_revision()
	var change_count := [0]
	var observer := func(): change_count[0] += 1
	inventory.inventory_changed.connect(observer)
	_expect(not loadout.try_equip_armor(_find_item(inventory, &"copper_shoes")), "invalid combined projection committed")
	_expect(inventory.to_dict() == before_inventory, "invalid combined projection changed inventory")
	_expect(stats.get_revision() == before_stat_revision, "invalid combined projection changed stats")
	_expect(change_count[0] == 0, "invalid combined projection emitted inventory change")
	inventory.inventory_changed.disconnect(observer)
	shoes.stat_modifiers = original_shoes_modifiers
	armor_set.full_set_modifiers = original_set_modifiers

func _test_invalid_combined_affixes() -> void:
	var first := _item_catalog.get_equipment_affix(&"vicious").duplicate(true) as EquipmentAffixDefinition
	var second := _item_catalog.get_equipment_affix(&"vicious").duplicate(true) as EquipmentAffixDefinition
	first.id = &"atomic_first"
	first.display_name_suffix = "Atomic First"
	second.id = &"atomic_second"
	second.display_name_suffix = "Atomic Second"
	for affix in [first, second]:
		affix.stat_rolls[0].stat_id = &"strength"
		affix.stat_rolls[0].operation = StatModifier.Operation.ADD
		affix.stat_rolls[0].minimum_amount = 1.0
		affix.stat_rolls[0].maximum_amount = 1.0
	var catalog := ItemCatalog.new()
	catalog.equipment_types = _item_catalog.equipment_types
	catalog.definitions = _item_catalog.definitions
	var affixes: Array[EquipmentAffixDefinition] = [first, second]
	catalog.equipment_affixes = affixes
	var inventory := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	inventory.setup_empty()
	var stats := ActorStats.new(_stats_definition)
	var loadout := _bind(inventory, stats)
	var instance := inventory.equipment_instance_factory.create(&"copper_sword", affixes)
	instance.affixes[0].stat_rolls[0].amount = -6.0
	instance.affixes[1].stat_rolls[0].amount = -6.0
	_expect(loadout.add_stack(InventoryStack.new(&"copper_sword", 1, instance)), "combined affix fixture could not enter the backpack")
	var source := _find_item(inventory, &"copper_sword")
	_expect(loadout.assign_slot_to_hotbar(source, 0), "invalid combined affix fixture could not enter the hotbar while unequipped")
	var before := inventory.to_dict()
	var stat_revision := stats.get_revision()
	_expect(not loadout.select_slot(0), "invalid combined affixes became selected")
	_expect(inventory.to_dict() == before, "invalid combined affixes changed inventory")
	_expect(stats.get_revision() == stat_revision, "invalid combined affixes changed stats")

func _test_taxonomy_rune_activation() -> void:
	var sword_definition := _item_catalog.get_definition(&"copper_sword")
	var original_action := sword_definition.primary_action
	sword_definition.primary_action = null
	var inventory := _empty_inventory()
	var rune_ids: Array[StringName] = [&"basic_rune"]
	var empty_affixes: Array[EquipmentAffixDefinition] = []
	var sword := inventory.equipment_instance_factory.create(&"copper_sword", empty_affixes, rune_ids)
	InventoryTestFixture.restore_slot(inventory, 0, InventoryStack.new(&"copper_sword", 1, sword))
	var stats := ActorStats.new(_stats_definition)
	_bind(inventory, stats)
	_expect(stats.has_modifier(&"socketed_runes_0"), "canonical non-melee weapon did not activate its rune")
	sword_definition.primary_action = original_action

func _test_invalid_active_runes() -> void:
	var weapon_rune := _item_catalog.get_definition(&"basic_rune").duplicate(true) as RuneDefinition
	weapon_rune.id = &"atomic_weapon_rune"
	weapon_rune.display_name = "Atomic Weapon Rune"
	weapon_rune.compatible_equipment_types = [_item_catalog.get_equipment_type(&"weapon")]
	weapon_rune.compatible_armor_slots = 0
	weapon_rune.socket_modifiers[0].id = &"atomic_weapon_rune_hp"
	weapon_rune.socket_modifiers[0].source_id = weapon_rune.id
	weapon_rune.socket_modifiers[0].amount = -60.0
	var armor_rune := _item_catalog.get_definition(&"basic_rune").duplicate(true) as RuneDefinition
	armor_rune.id = &"atomic_armor_rune"
	armor_rune.display_name = "Atomic Armor Rune"
	armor_rune.compatible_equipment_types = [_item_catalog.get_equipment_type(&"armor")]
	armor_rune.compatible_armor_slots = RuneDefinition.ALL_ARMOR_SLOTS
	armor_rune.socket_modifiers[0].id = &"atomic_armor_rune_hp"
	armor_rune.socket_modifiers[0].source_id = armor_rune.id
	armor_rune.socket_modifiers[0].amount = -60.0
	var catalog := ItemCatalog.new()
	catalog.equipment_types = _item_catalog.equipment_types
	var definitions: Array[ItemDefinition] = _item_catalog.definitions.duplicate()
	definitions.append(weapon_rune)
	definitions.append(armor_rune)
	catalog.definitions = definitions
	catalog.equipment_affixes = _item_catalog.equipment_affixes
	var inventory := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	inventory.setup_empty()
	var empty_affixes: Array[EquipmentAffixDefinition] = []
	var weapon_rune_ids: Array[StringName] = [weapon_rune.id]
	var armor_rune_ids: Array[StringName] = [armor_rune.id]
	var sword := inventory.equipment_instance_factory.create(&"copper_sword", empty_affixes, weapon_rune_ids)
	var helmet := inventory.equipment_instance_factory.create(&"copper_helmet", empty_affixes, armor_rune_ids)
	InventoryTestFixture.restore_slot(inventory, 0, InventoryStack.new(&"copper_sword", 1, sword))
	InventoryTestFixture.restore_slot(inventory, InventoryModel.HOTBAR_SIZE, InventoryStack.new(&"copper_helmet", 1, helmet))
	var stats := ActorStats.new(_stats_definition)
	var loadout := _bind(inventory, stats)
	_expect(is_equal_approx(stats.get_value(&"hp"), 40.0), "individually valid weapon rune did not activate")
	var before_inventory := inventory.to_dict()
	var before_stat_revision := stats.get_revision()
	_expect(not loadout.try_equip_armor(InventoryModel.HOTBAR_SIZE), "invalid active rune combination committed")
	_expect(inventory.to_dict() == before_inventory, "invalid active runes changed inventory")
	_expect(stats.get_revision() == before_stat_revision, "invalid active runes changed stats")

func _test_timed_projection_expiry() -> void:
	var totem := _item_catalog.get_definition(&"test_totem")
	var modifier := totem.stat_modifiers[0]
	var original_duration := modifier.duration_seconds
	modifier.duration_seconds = 0.1
	var inventory := _empty_inventory()
	InventoryTestFixture.restore_slot(inventory, 0, InventoryStack.new(&"test_totem", 1))
	var stats := ActorStats.new(_stats_definition)
	var loadout := _bind(inventory, stats)
	_expect(stats.has_modifier(&"selected_item_0"), "timed selected modifier did not activate")
	_expect(not stats.remove_modifier(&"selected_item_0"), "public removal erased a timed loadout modifier")
	stats.advance_time(0.2)
	_expect(not stats.has_modifier(&"selected_item_0"), "timed selected modifier did not expire")
	var expired_revision := stats.get_revision()
	_expect(loadout.add_backpack_item(&"sand_block", 1), "timed expiry unrelated add failed")
	_expect(not stats.has_modifier(&"selected_item_0"), "unrelated inventory change resurrected expired modifier")
	_expect(stats.get_revision() == expired_revision, "unrelated inventory change revised expired modifier state")
	_expect(loadout.select_slot(1), "timed source deactivation failed")
	_expect(loadout.select_slot(0), "timed source reactivation failed")
	_expect(stats.has_modifier(&"selected_item_0"), "changed timed source did not reactivate")
	modifier.duration_seconds = original_duration

func _test_invalid_intermediate_final_projection() -> void:
	var stout := _item_catalog.get_equipment_affix(&"stout")
	var roll := stout.stat_rolls[0]
	var original_stat_id := roll.stat_id
	var original_operation := roll.operation
	var original_minimum := roll.minimum_amount
	var original_maximum := roll.maximum_amount
	roll.stat_id = &"hp"
	roll.operation = StatModifier.Operation.ADD
	roll.minimum_amount = -60.0
	roll.maximum_amount = -60.0
	var inventory := _empty_inventory()
	var stout_affixes: Array[EquipmentAffixDefinition] = [stout]
	var replacement_helmet := inventory.equipment_instance_factory.create(&"copper_helmet", stout_affixes)
	var rune_ids: Array[StringName] = [&"basic_rune"]
	var empty_affixes: Array[EquipmentAffixDefinition] = []
	var equipped_helmet := inventory.equipment_instance_factory.create(&"copper_helmet", empty_affixes, rune_ids)
	var helmet_index := InventoryModel.get_equipment_index(ArmorDefinition.Slot.HEAD)
	InventoryTestFixture.restore_slot(inventory, InventoryModel.HOTBAR_SIZE, InventoryStack.new(&"copper_helmet", 1, replacement_helmet))
	InventoryTestFixture.restore_slot(inventory, helmet_index, InventoryStack.new(&"copper_helmet", 1, equipped_helmet))
	var rune := _item_catalog.get_definition(&"basic_rune") as RuneDefinition
	var original_rune_amount := rune.socket_modifiers[0].amount
	rune.socket_modifiers[0].amount = -60.0
	var stats := ActorStats.new(_stats_definition)
	var loadout := _bind(inventory, stats)
	var observed: Array[Dictionary] = []
	var health_observed: Array[Dictionary] = []
	var notification_order: Array[StringName] = []
	var depletion_count := [0]
	var inventory_observer := func():
		notification_order.append(&"inventory")
		observed.append({
			"maximum_hp": stats.get_value(&"hp"),
			"current_hp": stats.current_hp,
			"equipped": inventory.get_slot(helmet_index).equipment_instance.instance_id,
		})
	var health_observer := func(current_hp: float, maximum_hp: float):
		notification_order.append(&"health")
		health_observed.append({
			"maximum_hp": maximum_hp,
			"current_hp": current_hp,
			"equipped": inventory.get_slot(helmet_index).equipment_instance.instance_id,
		})
	var depletion_observer := func(): depletion_count[0] += 1
	inventory.inventory_changed.connect(inventory_observer)
	stats.health_changed.connect(health_observer)
	stats.health_depleted.connect(depletion_observer)
	_expect(loadout.handle_drop(InventoryModel.HOTBAR_SIZE, helmet_index, 1), "final-valid projection with invalid intermediate was rejected")
	_expect(observed.size() == 1, "final-valid projection emitted the wrong inventory change count")
	if observed.size() == 1:
		_expect(is_equal_approx(observed[0]["maximum_hp"], 40.0), "observer saw stale final maximum HP")
		_expect(is_equal_approx(observed[0]["current_hp"], 40.0), "observer saw stale final current HP")
		_expect(observed[0]["equipped"] == replacement_helmet.instance_id, "observer saw stale equipped inventory")
	_expect(notification_order == [&"inventory"], "unchanged final health emitted an intermediate notification")
	_expect(health_observed.is_empty(), "unchanged final health emitted health changed")
	_expect(depletion_count[0] == 0, "invalid intermediate emitted health depletion")
	inventory.inventory_changed.disconnect(inventory_observer)
	stats.health_changed.disconnect(health_observer)
	stats.health_depleted.disconnect(depletion_observer)
	rune.socket_modifiers[0].amount = original_rune_amount
	roll.stat_id = original_stat_id
	roll.operation = original_operation
	roll.minimum_amount = original_minimum
	roll.maximum_amount = original_maximum
	var health_inventory := _empty_inventory()
	InventoryTestFixture.restore_slot(health_inventory, 1, InventoryStack.new(&"test_totem", 1))
	var health_stats := ActorStats.new(_stats_definition)
	var health_loadout := _bind(health_inventory, health_stats)
	var health_notification_order: Array[StringName] = []
	var maximum_hp_payloads: Array[Vector2] = []
	var health_inventory_observer := func():
		health_notification_order.append(&"inventory")
		_expect(health_inventory.get_selected_slot() == 1 and is_equal_approx(health_stats.get_value(&"hp"), 200.0), "inventory observer saw a partial health loadout commit")
	var maximum_hp_observer := func(current_hp: float, maximum_hp: float):
		health_notification_order.append(&"health")
		maximum_hp_payloads.append(Vector2(current_hp, maximum_hp))
		_expect(health_inventory.get_selected_slot() == 1, "health observer saw a partial inventory loadout commit")
	health_inventory.inventory_changed.connect(health_inventory_observer)
	health_stats.health_changed.connect(maximum_hp_observer)
	_expect(health_loadout.select_slot(1), "maximum HP loadout change failed")
	_expect(health_notification_order == [&"inventory", &"health"], "loadout health notification did not follow the committed inventory notification")
	_expect(maximum_hp_payloads == [Vector2(100.0, 200.0)], "loadout maximum HP change emitted the wrong committed payload")
	health_inventory.inventory_changed.disconnect(health_inventory_observer)
	health_stats.health_changed.disconnect(maximum_hp_observer)
	var stale_change := health_loadout.prepare_inventory_change(health_inventory.prepare_add_stack(InventoryStack.new(&"sand_block", 1)))
	_expect(stale_change != null, "stale health notification fixture did not prepare")
	var failed_health_changes: Array[int] = [0]
	var failed_health_observer := func(_current_hp: float, _maximum_hp: float): failed_health_changes[0] += 1
	health_stats.health_changed.connect(failed_health_observer)
	_expect(is_equal_approx(health_stats.damage(1.0), 1.0), "stale health notification fixture did not change stats")
	var failed_health_count_before: int = failed_health_changes[0]
	var inventory_before_failed_commit := health_inventory.to_dict()
	_expect(not health_loadout.commit_prepared_change(stale_change), "stale loadout change committed")
	_expect(failed_health_changes[0] == failed_health_count_before, "failed prepared loadout change emitted health changed")
	_expect(health_inventory.to_dict() == inventory_before_failed_commit, "failed prepared loadout change changed inventory")
	health_stats.health_changed.disconnect(failed_health_observer)

func _test_chest_rollback(block_catalog: BlockCatalog) -> void:
	var inventory := _empty_inventory()
	var max_stack := _item_catalog.get_definition(&"dirt_block").max_stack
	for index in range(InventoryModel.FILLABLE_SIZE):
		InventoryTestFixture.restore_slot(inventory, index, InventoryStack.new(&"dirt_block", max_stack))
	var stats := ActorStats.new(_stats_definition)
	var loadout := _bind(inventory, stats)
	var chest_block := block_catalog.get_definition(BlockId.Type.CHEST)
	var storage := ChestStorage.new(_item_catalog, inventory.equipment_instance_factory, chest_block.container.get_slot_count())
	var position := Vector3i(4, 3, 2)
	storage.create_chest(position)
	storage.add_stack(position, InventoryStack.new(&"stone_block", 4), 0)
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	world.restore_block_edits({position: BlockId.Type.CHEST}, {})
	var coordinator := ChestCoordinator.new()
	_expect(coordinator.setup(storage, inventory, loadout, world, chest_block), "chest coordinator binding failed")
	_expect(coordinator.try_open(position, chest_block.container), "chest did not open for rollback test")
	var inventory_before := inventory.to_dict()
	var storage_before := storage.snapshot()
	var inventory_revision := inventory.get_revision()
	var storage_revision := storage.get_revision()
	var stat_revision := stats.get_revision()
	_expect(not coordinator.quick_transfer(ChestCoordinator.CHEST_SCOPE, 0), "full inventory accepted chest transfer")
	_expect(inventory.to_dict() == inventory_before, "failed chest transfer changed inventory")
	_expect(storage.snapshot() == storage_before, "failed chest transfer changed storage")
	_expect(inventory.get_revision() == inventory_revision, "failed chest transfer revised inventory")
	_expect(storage.get_revision() == storage_revision, "failed chest transfer revised storage")
	_expect(stats.get_revision() == stat_revision, "failed chest transfer revised stats")
	_expect(not storage.create_chest(position + Vector3i.ONE), "bound chest storage allowed direct creation")
	_expect(not storage.add_stack(position, InventoryStack.new(&"sand_block", 1)), "bound chest storage allowed direct add")
	_expect(storage.remove_stack(position, 0) == null, "bound chest storage allowed direct removal")
	_expect(not storage.restore(storage_before), "bound chest storage allowed direct restore")
	_expect(storage.snapshot() == storage_before, "bound chest storage mutation rejection changed storage")
	var duplicate := ChestCoordinator.new()
	_expect(not duplicate.setup(storage, inventory, loadout, world, chest_block), "chest storage accepted a second coordinator")

func _empty_inventory() -> InventoryModel:
	var inventory := InventoryModel.new(_item_catalog, EquipmentInstanceFactory.new(_item_catalog))
	inventory.setup_empty()
	return inventory

func _bind(inventory: InventoryModel, stats: ActorStats) -> InventoryLoadoutCoordinator:
	var loadout := InventoryLoadoutCoordinator.new()
	_expect(loadout.setup(inventory, stats, ItemProficiency.new(inventory.item_catalog)), "loadout binding failed")
	return loadout

func _find_item(inventory: InventoryModel, item_id: StringName) -> int:
	for index in range(inventory.get_size()):
		var stack := inventory.get_slot(index)
		if stack != null and stack.item_id == item_id:
			return index
	return -1

func _modifier(stat_id: StringName, amount: float) -> StatModifier:
	var modifier := StatModifier.new()
	modifier.id = StringName("atomic_%s_%s" % [stat_id, amount])
	modifier.source_id = &"atomic"
	modifier.stat_id = stat_id
	modifier.amount = amount
	return modifier

func _modifiers(values: Array[StatModifier]) -> Array[StatModifier]:
	return values

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
