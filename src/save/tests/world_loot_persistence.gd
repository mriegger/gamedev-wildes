extends SceneTree

var _errors: Array[String] = []
var _item_catalog: ItemCatalog
var _block_catalog: BlockCatalog
var _chest_block: BlockDefinition

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_item_catalog = load("res://items/item_catalog.tres") as ItemCatalog
	_block_catalog = load("res://blocks/block_catalog.tres") as BlockCatalog
	_chest_block = _block_catalog.get_definition(BlockId.Type.CHEST) if _block_catalog != null else null
	_expect(_item_catalog != null, "item catalog did not load")
	_expect(_block_catalog != null, "block catalog did not load")
	_expect(_chest_block != null and _chest_block.container != null, "chest container definition did not load")
	if _item_catalog != null and _block_catalog != null and _chest_block != null and _chest_block.container != null:
		_test_migration_and_exact_schema()
		_test_identity_collisions()
		_test_save_round_trip()
	if _errors.is_empty():
		print("WORLD_LOOT_PERSISTENCE PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _test_migration_and_exact_schema() -> void:
	var factory := EquipmentInstanceFactory.new(_item_catalog)
	var legacy_affixes: Array[EquipmentAffixDefinition] = [
		_item_catalog.get_equipment_affix(&"vicious"),
	]
	var legacy_runes: Array[StringName] = [&"basic_rune"]
	var sword := factory.create(&"copper_sword", legacy_affixes, legacy_runes)
	_expect(sword != null, "version-eleven equipment fixture was not created")
	if sword == null:
		return
	var expected_instance := sword.to_dict()
	var legacy_instance := expected_instance.duplicate(true)
	legacy_instance["current_durability"] = 37
	legacy_instance["maximum_durability"] = 100
	var legacy_inventory := _empty_inventory_snapshot()
	legacy_inventory["regions"]["hotbar"][0] = {
		"item_id": "copper_sword",
		"count": 1,
		"equipment_instance": legacy_instance,
	}
	var version_eleven := {
		"version": 11,
		"inventory": legacy_inventory,
		"chests": {},
		"next_equipment_instance_id": factory.get_next_instance_id(),
		"player_perks": {"allocations": {}},
		"apple_trees": AppleTreeState.new().snapshot(),
	}
	var malformed_version_eleven := version_eleven.duplicate(true)
	var malformed_legacy_instance: Dictionary = malformed_version_eleven["inventory"]["regions"]["hotbar"][0]["equipment_instance"]
	malformed_legacy_instance.erase("current_durability")
	malformed_legacy_instance.erase("maximum_durability")
	malformed_legacy_instance["legacy_value_a"] = 37
	malformed_legacy_instance["legacy_value_b"] = 100
	_expect_rejected_unchanged(malformed_version_eleven, "arbitrary legacy equipment fields were accepted")
	var excessive_durability_version_eleven := version_eleven.duplicate(true)
	var excessive_durability_instance: Dictionary = excessive_durability_version_eleven["inventory"]["regions"]["hotbar"][0]["equipment_instance"]
	excessive_durability_instance["maximum_durability"] = SaveManager.VERSION_ELEVEN_MAXIMUM_DURABILITY + 1
	_expect_rejected_unchanged(excessive_durability_version_eleven, "out-of-range legacy durability was accepted")
	var version_twelve := version_eleven.duplicate(true)
	version_twelve["version"] = 12
	version_twelve["inventory"]["regions"]["hotbar"][0]["equipment_instance"] = expected_instance.duplicate(true)
	_expect(SaveManager._migrate_save_data(version_eleven, _item_catalog), "version-eleven save did not migrate")
	_expect(version_eleven.get("version", -1) == SaveManager.CURRENT_SAVE_VERSION, "version-eleven migration did not reach the current version")
	_expect(version_eleven.get("world_loot", null) == _empty_world_loot(), "version-eleven migration did not initialize exact world loot")
	var migrated_instance: Dictionary = version_eleven["inventory"]["regions"]["hotbar"][0]["equipment_instance"]
	_expect(migrated_instance == expected_instance, "version-eleven equipment migration changed identity, affixes, or runes")
	var extra_instance := version_eleven.duplicate(true)
	extra_instance["inventory"]["regions"]["hotbar"][0]["equipment_instance"]["future"] = true
	_expect_rejected_unchanged(extra_instance, "extra current equipment instance field was accepted")
	_expect(SaveManager._migrate_save_data(version_twelve, _item_catalog), "version-twelve save did not migrate")
	_expect(version_twelve.get("version", -1) == SaveManager.CURRENT_SAVE_VERSION, "version-twelve migration did not reach the current version")
	_expect(version_twelve.get("world_loot", null) == _empty_world_loot(), "version-twelve migration did not initialize exact world loot")

	var current := _empty_current_save()
	_expect(SaveManager._migrate_save_data(current, _item_catalog), "valid current-version save was rejected")
	var missing := current.duplicate(true)
	missing.erase("world_loot")
	_expect_rejected_unchanged(missing, "missing world loot was accepted")
	var extra := current.duplicate(true)
	extra["world_loot"]["extra"] = true
	_expect_rejected_unchanged(extra, "extra world loot field was accepted")
	var missing_entries := current.duplicate(true)
	missing_entries["world_loot"].erase("entries")
	_expect_rejected_unchanged(missing_entries, "missing world loot entries were accepted")
	var extra_entry_field := current.duplicate(true)
	extra_entry_field["world_loot"] = {
		"next_entry_id": 2,
		"entries": [{
			"entry_id": 1,
			"stack": InventoryStack.new(&"sand_block", 1).to_dict(),
			"world_position": [0.0, 0.0, 0.0],
			"remaining_lifetime": 10.0,
			"extra": true,
		}],
	}
	_expect_rejected_unchanged(extra_entry_field, "extra world loot entry field was accepted")

func _test_identity_collisions() -> void:
	var factory := EquipmentInstanceFactory.new(_item_catalog)
	var sword := factory.create(&"copper_sword")
	_expect(sword != null, "identity fixture sword was not created")
	if sword == null:
		return
	var encoded_stack := InventoryStack.new(&"copper_sword", 1, sword).to_dict()
	var world_entry := WorldLootEntry.new(
		1,
		InventoryStack.new(&"copper_sword", 1, sword),
		Vector3.ZERO,
		WorldLootEntry.NO_LIFETIME,
	).to_dict()

	var inventory_world := _empty_current_save(factory.get_next_instance_id())
	inventory_world["inventory"] = _empty_inventory_snapshot()
	inventory_world["inventory"]["regions"]["hotbar"][0] = encoded_stack.duplicate(true)
	inventory_world["world_loot"] = {
		"next_entry_id": 2,
		"entries": [world_entry.duplicate(true)],
	}
	_expect_rejected_unchanged(inventory_world, "inventory-world equipment collision was accepted")

	var chest_world := _empty_current_save(factory.get_next_instance_id())
	chest_world["chests"] = {"1,2,3": _chest_slots(encoded_stack.duplicate(true))}
	chest_world["world_loot"] = {
		"next_entry_id": 2,
		"entries": [world_entry.duplicate(true)],
	}
	_expect_rejected_unchanged(chest_world, "chest-world equipment collision was accepted")

	var within_world := _empty_current_save(factory.get_next_instance_id())
	var second_entry := world_entry.duplicate(true)
	second_entry["entry_id"] = 2
	second_entry["world_position"] = [4.0, 0.0, 0.0]
	within_world["world_loot"] = {
		"next_entry_id": 3,
		"entries": [world_entry.duplicate(true), second_entry],
	}
	_expect_rejected_unchanged(within_world, "within-world equipment collision was accepted")

	var at_next_id := _empty_current_save(sword.instance_id)
	at_next_id["world_loot"] = {
		"next_entry_id": 2,
		"entries": [world_entry.duplicate(true)],
	}
	_expect_rejected_unchanged(at_next_id, "world equipment ID at the next allocator ID was accepted")

func _test_save_round_trip() -> void:
	var factory := EquipmentInstanceFactory.new(_item_catalog)
	var inventory := InventoryModel.new(_item_catalog, factory)
	_expect(inventory.setup_empty(), "round-trip inventory setup failed")
	var chest_storage := ChestStorage.new(_item_catalog, factory, _chest_block.container.get_slot_count())
	var world_loot_state := WorldLootState.new(_item_catalog, factory)
	_expect(_add_world_stack(world_loot_state, InventoryStack.new(&"sand_block", 7), Vector3(2.25, 3.0, -4.5)), "material world loot setup failed")
	var advance := world_loot_state.prepare_advance_time(41.25)
	_expect(advance != null and world_loot_state.commit_prepared_change(advance), "material lifetime setup failed")
	var affixes: Array[EquipmentAffixDefinition] = [_item_catalog.get_equipment_affix(&"vicious")]
	var rune_ids: Array[StringName] = [&"basic_rune"]
	var sword := factory.create(&"copper_sword", affixes, rune_ids)
	_expect(sword != null, "round-trip equipment was not created")
	if sword == null:
		return
	_expect(_add_world_stack(world_loot_state, InventoryStack.new(&"copper_sword", 1, sword), Vector3(-8.0, 1.5, 12.0)), "equipment world loot setup failed")

	var slot_id := 1200000000 + OS.get_process_id()
	while SaveManager.slot_exists(slot_id):
		slot_id += 1
	var path := SaveManager.get_slot_path(slot_id)
	var current := SaveManager.create_new_world(slot_id, 481516, "World Loot Persistence")
	_expect(current.get("world_loot", null) == _empty_world_loot(), "new world did not initialize exact world loot")
	var file_before_chest_validation := FileAccess.get_file_as_string(path)
	var voxel_world := VoxelWorld.new(20, 36, 5, 12.0, _block_catalog)
	var player_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	_expect(player_stats.set_progression(2, 0), "round-trip player progression setup failed")
	var player_perks := PlayerPerks.new(load("res://progression/player_perk_rules.tres") as PlayerPerkRules)
	_expect(player_perks.restore({"allocations": {"health": 1}}, 2), "round-trip perk setup failed")
	var item_proficiency := ItemProficiency.new(_item_catalog)
	var dungeon_progress := DungeonProgressState.new()
	var apple_trees := AppleTreeState.new().snapshot()
	var expected_snapshot := world_loot_state.snapshot()
	var current_before_chest_validation := current.duplicate(true)
	var wrong_slot_storage := ChestStorage.new(
		_item_catalog,
		factory,
		SaveManager.PERSISTED_CHEST_SLOT_COUNT - 1,
	)
	_expect(
		not SaveManager.save_world_state(
			slot_id,
			current,
			voxel_world,
			Vector3.ZERO,
			player_stats,
			inventory,
			factory,
			player_perks,
			item_proficiency,
			wrong_slot_storage,
			world_loot_state,
			dungeon_progress,
			{"present": false},
			apple_trees,
			0.0,
			6.0,
		),
		"save accepted a noncanonical chest slot count",
	)
	_expect(current == current_before_chest_validation, "invalid chest configuration changed current data")
	_expect(FileAccess.get_file_as_string(path) == file_before_chest_validation, "invalid chest configuration changed the slot file")
	var orphan_chest_storage := ChestStorage.new(
		_item_catalog,
		factory,
		SaveManager.PERSISTED_CHEST_SLOT_COUNT,
	)
	_expect(orphan_chest_storage.create_chest(Vector3i(4, 5, 6)), "orphan chest fixture was not created")
	_expect(
		not SaveManager.save_world_state(
			slot_id,
			current,
			voxel_world,
			Vector3.ZERO,
			player_stats,
			inventory,
			factory,
			player_perks,
			item_proficiency,
			orphan_chest_storage,
			world_loot_state,
			dungeon_progress,
			{"present": false},
			apple_trees,
			0.0,
			6.0,
		),
		"save accepted chest storage without a placed chest",
	)
	_expect(current == current_before_chest_validation, "orphan chest rejection changed current data")
	_expect(FileAccess.get_file_as_string(path) == file_before_chest_validation, "orphan chest rejection changed the slot file")
	var missing_chest_storage_world := VoxelWorld.new(20, 36, 5, 12.0, _block_catalog)
	_expect(
		VoxelWorldTestFixture.commit_place(
			missing_chest_storage_world,
			Vector3i(7, 8, 9),
			BlockId.Type.CHEST,
		) != null,
		"placed chest fixture was not created",
	)
	_expect(
		not SaveManager.save_world_state(
			slot_id,
			current,
			missing_chest_storage_world,
			Vector3.ZERO,
			player_stats,
			inventory,
			factory,
			player_perks,
			item_proficiency,
			chest_storage,
			world_loot_state,
			dungeon_progress,
			{"present": false},
			apple_trees,
			0.0,
			6.0,
		),
		"save accepted a placed chest without storage",
	)
	_expect(current == current_before_chest_validation, "missing chest storage rejection changed current data")
	_expect(FileAccess.get_file_as_string(path) == file_before_chest_validation, "missing chest storage rejection changed the slot file")
	var saved := SaveManager.save_world_state(
		slot_id,
		current,
		voxel_world,
		Vector3(1.25, 6.0, -2.5),
		player_stats,
		inventory,
		factory,
		player_perks,
		item_proficiency,
		chest_storage,
		world_loot_state,
		dungeon_progress,
		{"present": false},
		apple_trees,
		0.0,
		6.0,
	)
	_expect(saved, "world loot save failed")
	_expect(current.get("world_loot", null) == expected_snapshot, "save changed canonical world loot snapshot")
	_expect(current.get("player_perks", null) == player_perks.snapshot(), "save changed player perks")
	_expect(current.get("apple_trees", null) == apple_trees, "save changed apple tree state")
	var loaded := SaveManager.load_slot(slot_id, _item_catalog)
	_expect(bool(loaded.get("exists", false)) and not bool(loaded.get("incompatible", false)), "saved world loot slot did not load")
	var restored_factory := EquipmentInstanceFactory.new(_item_catalog, int(loaded.get("next_equipment_instance_id", 0)))
	var restored := WorldLootState.new(_item_catalog, restored_factory)
	var encoded_world_loot = loaded.get("world_loot", null)
	_expect(encoded_world_loot is Dictionary and restored.restore(encoded_world_loot), "saved world loot did not restore")
	_expect(restored.snapshot() == expected_snapshot, "restored world loot snapshot changed")
	var material := restored.get_entry(1)
	_expect(material != null and material.stack.item_id == &"sand_block" and material.stack.count == 7, "material stack round-trip changed")
	_expect(material != null and is_equal_approx(material.remaining_lifetime, 258.75), "material TTL round-trip changed")
	var equipment := restored.get_entry(2)
	_expect(equipment != null and equipment.stack.equipment_instance != null, "equipment round-trip lost instance data")
	if equipment != null and equipment.stack.equipment_instance != null:
		var instance := equipment.stack.equipment_instance
		_expect(instance.instance_id == sword.instance_id, "equipment instance ID round-trip changed")
		_expect(instance.socketed_rune_ids == rune_ids, "equipment runes round-trip changed")
		_expect(instance.affixes.size() == 1 and instance.affixes[0].affix_id == &"vicious", "equipment affix round-trip changed")
		_expect(instance.affixes.size() == 1 and is_equal_approx(instance.affixes[0].stat_rolls[0].amount, 2.0), "equipment affix roll round-trip changed")

	var file_before_rejected_collisions := FileAccess.get_file_as_string(path)
	var collision_inventory := inventory.to_dict()
	collision_inventory["regions"]["hotbar"][0] = InventoryStack.new(&"copper_sword", 1, sword).to_dict()
	_expect(inventory.from_dict(collision_inventory), "save collision inventory setup failed")
	var before_rejected_save := current.duplicate(true)
	_expect(
		not SaveManager.save_world_state(
			slot_id,
			current,
			voxel_world,
			Vector3.ZERO,
			player_stats,
			inventory,
			factory,
			player_perks,
			item_proficiency,
			chest_storage,
			world_loot_state,
			dungeon_progress,
			{"present": false},
			apple_trees,
			0.0,
			6.0,
		),
		"save accepted an inventory-world equipment collision",
	)
	_expect(current == before_rejected_save, "rejected collision save changed current data")
	_expect(FileAccess.get_file_as_string(path) == file_before_rejected_collisions, "rejected inventory collision changed the slot file")
	_expect(inventory.setup_empty(), "save collision inventory reset failed")
	var chest_position := Vector3i(1, 2, 3)
	_expect(VoxelWorldTestFixture.commit_place(voxel_world, chest_position, BlockId.Type.CHEST) != null, "save collision chest block setup failed")
	_expect(chest_storage.create_chest(chest_position), "save collision chest setup failed")
	_expect(chest_storage.add_stack(chest_position, InventoryStack.new(&"copper_sword", 1, sword)), "save collision chest content setup failed")
	_expect(
		not SaveManager.save_world_state(
			slot_id,
			current,
			voxel_world,
			Vector3.ZERO,
			player_stats,
			inventory,
			factory,
			player_perks,
			item_proficiency,
			chest_storage,
			world_loot_state,
			dungeon_progress,
			{"present": false},
			apple_trees,
			0.0,
			6.0,
		),
		"save accepted a chest-world equipment collision",
	)
	_expect(current == before_rejected_save, "rejected chest collision save changed current data")
	_expect(FileAccess.get_file_as_string(path) == file_before_rejected_collisions, "rejected chest collision changed the slot file")
	var cleanup_error := OK
	if FileAccess.file_exists(path):
		cleanup_error = DirAccess.remove_absolute(path)
	_expect(cleanup_error == OK and not FileAccess.file_exists(path), "temporary save cleanup failed")

func _empty_current_save(next_instance_id: int = 1) -> Dictionary:
	return {
		"version": SaveManager.CURRENT_SAVE_VERSION,
		"inventory": null,
		"chests": {},
		"next_equipment_instance_id": next_instance_id,
		"world_loot": _empty_world_loot(),
		"dungeon_progress": DungeonProgressState.new().snapshot(),
		"player_perks": {"allocations": {}},
		"apple_trees": AppleTreeState.new().snapshot(),
	}

func _empty_world_loot() -> Dictionary:
	return {
		"next_entry_id": 1,
		"entries": [],
	}

func _empty_inventory_snapshot() -> Dictionary:
	var inventory := InventoryModel.new(_item_catalog, EquipmentInstanceFactory.new(_item_catalog))
	inventory.setup_empty()
	return inventory.to_dict()

func _chest_slots(stack: Variant) -> Array:
	var slots: Array = []
	slots.resize(_chest_block.container.get_slot_count())
	slots.fill(null)
	if stack != null:
		slots[0] = stack
	return slots

func _add_world_stack(state: WorldLootState, stack: InventoryStack, position: Vector3) -> bool:
	var prepared := state._prepare_add_stack(stack, position)
	return prepared != null and state.commit_prepared_change(prepared)

func _expect_rejected_unchanged(data: Dictionary, message: String) -> void:
	var before := data.duplicate(true)
	_expect(not SaveManager._migrate_save_data(data, _item_catalog), message)
	_expect(data == before, "%s and changed save data" % message)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
