extends SceneTree

var _errors: Array[String] = []

func _init() -> void:
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	_expect(item_catalog != null and item_catalog.validate(block_catalog), "item catalog invalid")
	if item_catalog != null:
		_test_identity_and_persistence(item_catalog)
		_test_main_version_nine_migration(item_catalog)
		_test_version_ten_migration(item_catalog)
	if _errors.is_empty():
		print("INVENTORY_SOCKET_PERSISTENCE PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _test_identity_and_persistence(item_catalog: ItemCatalog) -> void:
	var factory := EquipmentInstanceFactory.new(item_catalog)
	var inventory := InventoryModel.new(item_catalog, factory)
	inventory.setup_empty()
	var rune_ids: Array[StringName] = [&"basic_rune"]
	var affixes: Array[EquipmentAffixDefinition] = [item_catalog.get_equipment_affix(&"vicious")]
	var affixed := factory.create(&"copper_sword", affixes, rune_ids)
	var plain := factory.create(&"copper_sword")
	_expect(affixed != null and plain != null and affixed.instance_id != plain.instance_id, "duplicate swords did not receive distinct IDs")
	var loadout := InventoryTestFixture.create_loadout(inventory)
	_expect(loadout.add_stack(InventoryStack.new(&"copper_sword", 1, affixed)), "affixed sword was not added")
	_expect(loadout.add_stack(InventoryStack.new(&"copper_sword", 1, plain)), "plain sword was not added")
	var encoded := inventory.to_dict()
	var restored_factory := EquipmentInstanceFactory.new(item_catalog, factory.get_next_instance_id())
	var restored := InventoryModel.new(item_catalog, restored_factory)
	_expect(restored.from_dict(encoded), "equipment instances did not restore")
	var first := restored.get_slot(InventoryModel.HOTBAR_SIZE)
	var second := restored.get_slot(InventoryModel.HOTBAR_SIZE + 1)
	_expect(first.equipment_instance.instance_id == affixed.instance_id, "affixed sword ID changed during restore")
	_expect(second.equipment_instance.instance_id == plain.instance_id, "plain sword ID changed during restore")
	_expect(first.equipment_instance.socketed_rune_ids == rune_ids, "socketed rune changed during restore")
	_expect(first.equipment_instance.affixes[0].stat_rolls[0].amount == 2.0, "rolled affix value changed during restore")
	var queried := restored.get_equipment_instance_copy(InventoryModel.HOTBAR_SIZE)
	queried.socketed_rune_ids.clear()
	queried.affixes[0].stat_rolls[0].amount = 99.0
	_expect(restored.get_socketed_rune_ids(InventoryModel.HOTBAR_SIZE) == rune_ids, "instance query exposed rune state")
	_expect(restored.get_slot(InventoryModel.HOTBAR_SIZE).equipment_instance.affixes[0].stat_rolls[0].amount == 2.0, "instance query exposed affix state")
	var duplicate := encoded.duplicate(true)
	duplicate["regions"]["backpack"][1]["equipment_instance"]["instance_id"] = affixed.instance_id
	var before := restored.to_dict()
	_expect(not restored.from_dict(duplicate), "duplicate inventory equipment IDs were accepted")
	_expect(restored.to_dict() == before, "failed duplicate-ID restore changed inventory")

func _test_main_version_nine_migration(item_catalog: ItemCatalog) -> void:
	var chest_slots := _empty_chest_slots(_version_nine_stack("copper_sword", []))
	chest_slots[1] = _version_nine_stack("chest", [])
	var main_inventory := _version_nine_inventory()
	main_inventory["regions"]["backpack"][0] = null
	var player_perks := {"allocations": {"health": 1}}
	var apple_trees := {
		"version": 1,
		"collected_slots": [[0, 0, 0, 2]],
	}
	var save := {
		"version": 9,
		"inventory": main_inventory,
		"chest_inventories": {
			"4,5,6": {
				"size": SaveManager.PERSISTED_CHEST_SLOT_COUNT,
				"slots": chest_slots,
			},
		},
		"player_perks": player_perks.duplicate(true),
		"apple_trees": apple_trees.duplicate(true),
		"placed_blocks": {"4,5,6": BlockId.Type.CHEST},
	}
	_expect(BlockId.Type.CHEST == 17, "main chest block ID changed")
	_expect(item_catalog.has_definition(&"chest"), "main chest item ID was not preserved")
	_expect(SaveManager._migrate_save_data(save, item_catalog), "main version-nine save did not migrate")
	_expect(save["version"] == SaveManager.CURRENT_SAVE_VERSION, "main version-nine save reached the wrong version")
	_expect(not save.has("chest_inventories"), "main chest storage key survived migration")
	_expect(save["player_perks"] == player_perks, "main perk allocations changed during migration")
	_expect(save["apple_trees"] == apple_trees, "main apple tree state changed during migration")
	_expect(save["placed_blocks"]["4,5,6"] == BlockId.Type.CHEST, "main chest block ID changed during migration")
	var inventory_sword: Dictionary = save["inventory"]["regions"]["hotbar"][0]
	var migrated_chest_slots: Array = save["chests"]["4,5,6"]
	var chest_sword: Dictionary = migrated_chest_slots[0]
	var chest_item: Dictionary = migrated_chest_slots[1]
	_expect(inventory_sword["equipment_instance"]["instance_id"] == 1, "main inventory gear did not receive the first equipment ID")
	_expect(chest_sword["equipment_instance"]["instance_id"] == 2, "main chest gear did not receive the second equipment ID")
	_expect(chest_item["item_id"] == "chest" and chest_item["equipment_instance"] == null, "main chest item changed during migration")
	_expect(save["next_equipment_instance_id"] == 3, "main migration next equipment ID changed")
	var malformed_size := {
		"version": 9,
		"inventory": null,
		"chest_inventories": {
			"4,5,6": {"size": 14, "slots": []},
		},
		"player_perks": player_perks.duplicate(true),
		"apple_trees": apple_trees.duplicate(true),
	}
	_expect_rejected_unchanged(malformed_size, item_catalog, "malformed main chest size was accepted")
	var aliased_position := {
		"version": 9,
		"inventory": null,
		"chest_inventories": {
			"04,5,6": {
				"size": SaveManager.PERSISTED_CHEST_SLOT_COUNT,
				"slots": _empty_chest_slots(null),
			},
		},
		"player_perks": player_perks.duplicate(true),
		"apple_trees": apple_trees.duplicate(true),
	}
	_expect_rejected_unchanged(aliased_position, item_catalog, "aliased main chest position was accepted")
	var ambiguous_storage := {
		"version": 9,
		"inventory": null,
		"chest_inventories": {},
		"chests": {},
		"player_perks": player_perks.duplicate(true),
		"apple_trees": apple_trees.duplicate(true),
	}
	_expect_rejected_unchanged(ambiguous_storage, item_catalog, "ambiguous chest storage was accepted")

func _test_version_ten_migration(item_catalog: ItemCatalog) -> void:
	var vicious := item_catalog.get_equipment_affix(&"vicious")
	vicious.stat_rolls[0].minimum_amount = 4.0
	vicious.stat_rolls[0].maximum_amount = 6.0
	var save := {
		"version": 10,
		"inventory": _version_ten_inventory(),
		"chests": {
			"10,0,0": _empty_chest_slots(_version_ten_stack("copper_helmet", "stout", [])),
			"-2,0,0": _empty_chest_slots(_version_ten_stack("copper_sword", "", [])),
		},
		"player_perks": {"allocations": {}},
		"apple_trees": {"version": 1, "collected_slots": []},
	}
	_expect(SaveManager._migrate_save_data(save, item_catalog), "version-ten equipment migration failed")
	_expect(save["version"] == SaveManager.CURRENT_SAVE_VERSION, "version-ten migration reached the wrong version")
	var hotbar_sword: Dictionary = save["inventory"]["regions"]["hotbar"][0]
	var backpack_sword: Dictionary = save["inventory"]["regions"]["backpack"][0]
	var sorted_chest_sword: Dictionary = save["chests"]["-2,0,0"][0]
	var sorted_chest_helmet: Dictionary = save["chests"]["10,0,0"][0]
	_expect(hotbar_sword["equipment_instance"]["instance_id"] == 1, "hotbar did not receive the first migrated ID")
	_expect(backpack_sword["equipment_instance"]["instance_id"] == 2, "backpack did not receive the second migrated ID")
	_expect(sorted_chest_sword["equipment_instance"]["instance_id"] == 3, "numeric chest sorting did not assign the third ID")
	_expect(sorted_chest_helmet["equipment_instance"]["instance_id"] == 4, "numeric chest sorting did not assign the fourth ID")
	_expect(save["next_equipment_instance_id"] == 5, "migration next equipment ID changed")
	_expect(hotbar_sword["equipment_instance"]["affixes"].is_empty(), "plain migrated gear gained an affix")
	_expect(backpack_sword["equipment_instance"]["affixes"][0]["affix_id"] == "vicious", "vicious affix ID changed during migration")
	_expect(backpack_sword["equipment_instance"]["affixes"][0]["stat_rolls"][0]["amount"] == 2.0, "vicious fixed roll changed during migration")
	_expect(backpack_sword["equipment_instance"]["socketed_rune_ids"] == ["basic_rune"], "migrated rune changed")
	_expect(hotbar_sword["equipment_instance"].size() == 3, "migrated equipment instance shape changed")
	_expect(save["inventory"]["regions"]["hotbar"][1]["equipment_instance"] == null, "non-equipment item gained an instance")
	var duplicate := save.duplicate(true)
	duplicate["chests"]["-2,0,0"][0]["equipment_instance"]["instance_id"] = 1
	var duplicate_before := duplicate.duplicate(true)
	_expect(not SaveManager._migrate_save_data(duplicate, item_catalog), "cross-container duplicate equipment ID was accepted")
	_expect(duplicate == duplicate_before, "duplicate-ID rejection changed save data")
	var collision := save.duplicate(true)
	collision["next_equipment_instance_id"] = 4
	var collision_before := collision.duplicate(true)
	_expect(not SaveManager._migrate_save_data(collision, item_catalog), "next equipment ID collision was accepted")
	_expect(collision == collision_before, "next-ID rejection changed save data")
	var aliased_chest := save.duplicate(true)
	aliased_chest["chests"]["-02,0,0"] = (aliased_chest["chests"]["-2,0,0"] as Array).duplicate(true)
	var aliased_before := aliased_chest.duplicate(true)
	_expect(not SaveManager._migrate_save_data(aliased_chest, item_catalog), "aliased chest position was accepted")
	_expect(aliased_chest == aliased_before, "aliased chest rejection changed save data")
	_expect(SaveManager.decode_chest_state(aliased_chest) == null, "aliased chest positions collapsed during decoding")

func _version_nine_inventory() -> Dictionary:
	var inventory := _version_ten_inventory()
	for region_name in ["hotbar", "backpack", "equipment"]:
		for raw_stack in inventory["regions"][region_name]:
			if raw_stack is Dictionary:
				raw_stack.erase("equipment_variant_id")
	return inventory

func _version_nine_stack(item_id: String, rune_ids: Array) -> Dictionary:
	return {
		"item_id": item_id,
		"count": 1,
		"socketed_rune_ids": rune_ids,
	}

func _version_ten_inventory() -> Dictionary:
	var hotbar: Array = []
	hotbar.resize(InventoryModel.HOTBAR_SIZE)
	hotbar.fill(null)
	hotbar[0] = _version_ten_stack("copper_sword", "", [])
	hotbar[1] = _version_ten_stack("chest", "", [])
	var backpack: Array = []
	backpack.resize(InventoryModel.BACKPACK_SIZE)
	backpack.fill(null)
	backpack[0] = _version_ten_stack("copper_sword", "vicious", ["basic_rune"])
	var equipment: Array = []
	equipment.resize(InventoryModel.EQUIPMENT_SIZE)
	equipment.fill(null)
	return {
		"selected": 0,
		"starter_item_migration_version": InventoryModel.STARTER_ITEM_MIGRATION_VERSION,
		"regions": {
			"hotbar": hotbar,
			"backpack": backpack,
			"equipment": equipment,
		},
	}

func _version_ten_stack(item_id: String, affix_id: String, rune_ids: Array) -> Dictionary:
	return {
		"item_id": item_id,
		"count": 1,
		"socketed_rune_ids": rune_ids,
		"equipment_variant_id": affix_id,
	}

func _empty_chest_slots(stack: Variant) -> Array:
	var slots: Array = []
	slots.resize(SaveManager.PERSISTED_CHEST_SLOT_COUNT)
	slots.fill(null)
	if stack != null:
		slots[0] = stack
	return slots

func _expect_rejected_unchanged(data: Dictionary, item_catalog: ItemCatalog, message: String) -> void:
	var before := data.duplicate(true)
	_expect(not SaveManager._migrate_save_data(data, item_catalog), message)
	_expect(data == before, "%s and changed save data" % message)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
