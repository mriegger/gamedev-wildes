extends SceneTree

var _failures: int = 0

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var chest_block := block_catalog.get_definition(BlockId.Type.CHEST) if block_catalog != null else null
	var player_stats_definition := load("res://player/player_stats.tres") as CombatStatsDefinition
	var player_perk_rules := load("res://progression/player_perk_rules.tres") as PlayerPerkRules
	_expect(SaveManager.CURRENT_SAVE_VERSION == 24, "save version changed")
	_expect(block_catalog != null and block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog != null and item_catalog.validate(block_catalog), "item catalog invalid")
	_expect(chest_block != null and chest_block.container != null, "chest container definition invalid")
	_expect(chest_block != null and chest_block.container != null and chest_block.container.get_slot_count() == SaveManager.PERSISTED_CHEST_SLOT_COUNT, "persisted chest slot count changed")
	_expect(player_stats_definition != null and player_stats_definition.validate(), "player stats definition invalid")
	_expect(player_perk_rules != null and player_perk_rules.validate(player_stats_definition), "player perk rules invalid")
	var version_six := {"version": 6}
	_expect(SaveManager._migrate_save_data(version_six, item_catalog), "version six migration failed")
	_expect(version_six.get("version", -1) == SaveManager.CURRENT_SAVE_VERSION, "version six migration version changed")
	_expect(version_six.get("pumpkin_patch", null) == {"present": false}, "version six pumpkin migration shape changed")
	_expect(version_six.get("player_perks", null) == {"allocations": {}}, "version six perk migration shape changed")
	_expect(version_six.get("apple_trees", null) == AppleTreeState.new().snapshot(), "version six apple migration shape changed")
	_expect(version_six.get("chests", null) == {}, "version six chest migration shape changed")
	_expect(version_six.get("emplacements", null) == {}, "version six emplacement migration shape changed")
	_expect(version_six.get("dungeon_progress", null) == DungeonProgressState.new().snapshot(), "version six dungeon progress migration shape changed")
	_expect(version_six.get("tutorial_progress", null) == {"mining_tip_completed": false, "food_tip_completed": false, "crafting_tip_completed": false, "crafting_ingredients_tip_completed": false, "copper_mining_tip_completed": true, "sundown_weapon_tip_completed": false, "damage_affinity_tip_completed": false}, "version six tutorial migration shape changed")
	var version_fourteen := {
		"version": 14,
		"inventory": null,
		"chests": {},
		"next_equipment_instance_id": 1,
		"world_loot": {"next_entry_id": 1, "entries": []},
		"removed_blocks": {"2,3,4": true},
	}
	_expect(SaveManager._migrate_save_data(version_fourteen, item_catalog), "version fourteen migration failed")
	_expect(version_fourteen.get("tutorial_progress", null) == {"mining_tip_completed": true, "food_tip_completed": false, "crafting_tip_completed": false, "crafting_ingredients_tip_completed": false, "copper_mining_tip_completed": true, "sundown_weapon_tip_completed": false, "damage_affinity_tip_completed": false}, "version fourteen tutorial migration changed")
	_expect(version_fourteen.get("dungeon_progress", null) == DungeonProgressState.new().snapshot(), "version fourteen dungeon progress migration shape changed")
	var version_fifteen := {
		"version": 15,
		"inventory": null,
		"chests": {},
		"next_equipment_instance_id": 1,
		"world_loot": {"next_entry_id": 1, "entries": []},
		"dungeon_progress": DungeonProgressState.new().snapshot(),
		"removed_blocks": {},
	}
	_expect(SaveManager._migrate_save_data(version_fifteen, item_catalog), "version fifteen migration failed")
	_expect(version_fifteen.get("tutorial_progress", null) == {"mining_tip_completed": false, "food_tip_completed": false, "crafting_tip_completed": false, "crafting_ingredients_tip_completed": false, "copper_mining_tip_completed": true, "sundown_weapon_tip_completed": false, "damage_affinity_tip_completed": false}, "version fifteen tutorial migration changed")
	var version_sixteen_with_food := version_fifteen.duplicate(true)
	version_sixteen_with_food["version"] = 16
	version_sixteen_with_food["tutorial_progress"] = {"mining_tip_completed": false}
	version_sixteen_with_food["apple_trees"] = {"version": 2, "collected_slots": [[0, 1, 0, 0]], "fallen_apples": []}
	_expect(SaveManager._migrate_save_data(version_sixteen_with_food, item_catalog), "version sixteen food-history migration failed")
	_expect(version_sixteen_with_food.get("tutorial_progress", null) == {"mining_tip_completed": false, "food_tip_completed": true, "crafting_tip_completed": false, "crafting_ingredients_tip_completed": false, "copper_mining_tip_completed": true, "sundown_weapon_tip_completed": false, "damage_affinity_tip_completed": false}, "version sixteen food history did not complete the tutorial")
	var version_seventeen := version_fifteen.duplicate(true)
	version_seventeen["version"] = 17
	version_seventeen["tutorial_progress"] = {"mining_tip_completed": true, "food_tip_completed": true}
	_expect(SaveManager._migrate_save_data(version_seventeen, item_catalog), "version seventeen migration failed")
	_expect(version_seventeen.get("tutorial_progress", null) == {"mining_tip_completed": true, "food_tip_completed": true, "crafting_tip_completed": false, "crafting_ingredients_tip_completed": false, "copper_mining_tip_completed": true, "sundown_weapon_tip_completed": false, "damage_affinity_tip_completed": false}, "version seventeen crafting tutorial migration changed")
	var version_eighteen := version_fifteen.duplicate(true)
	version_eighteen["version"] = 18
	version_eighteen["tutorial_progress"] = {"mining_tip_completed": true, "food_tip_completed": true, "crafting_tip_completed": true}
	_expect(SaveManager._migrate_save_data(version_eighteen, item_catalog), "version eighteen migration failed")
	_expect(version_eighteen.get("tutorial_progress", null) == {"mining_tip_completed": true, "food_tip_completed": true, "crafting_tip_completed": true, "crafting_ingredients_tip_completed": false, "copper_mining_tip_completed": true, "sundown_weapon_tip_completed": false, "damage_affinity_tip_completed": false}, "version eighteen crafting ingredients tutorial migration changed")
	var version_nineteen := version_eighteen.duplicate(true)
	version_nineteen["version"] = 19
	version_nineteen["tutorial_progress"] = {"mining_tip_completed": true, "food_tip_completed": true, "crafting_tip_completed": true, "crafting_ingredients_tip_completed": true}
	_expect(SaveManager._migrate_save_data(version_nineteen, item_catalog), "version nineteen migration failed")
	_expect(version_nineteen.get("tutorial_progress", null) == {"mining_tip_completed": true, "food_tip_completed": true, "crafting_tip_completed": true, "crafting_ingredients_tip_completed": true, "copper_mining_tip_completed": true, "sundown_weapon_tip_completed": false, "damage_affinity_tip_completed": false}, "version nineteen copper mining tutorial migration changed")
	var version_twenty := version_nineteen.duplicate(true)
	version_twenty["version"] = 20
	version_twenty["tutorial_progress"] = {"mining_tip_completed": true, "food_tip_completed": true, "crafting_tip_completed": true, "crafting_ingredients_tip_completed": true, "copper_mining_tip_completed": true}
	_expect(SaveManager._migrate_save_data(version_twenty, item_catalog), "version twenty migration failed")
	_expect(version_twenty.get("tutorial_progress", null) == {"mining_tip_completed": true, "food_tip_completed": true, "crafting_tip_completed": true, "crafting_ingredients_tip_completed": true, "copper_mining_tip_completed": true, "sundown_weapon_tip_completed": false, "damage_affinity_tip_completed": false}, "version twenty sundown weapon tutorial migration changed")
	var version_twenty_one := version_twenty.duplicate(true)
	version_twenty_one["version"] = 21
	(version_twenty_one["tutorial_progress"] as Dictionary).erase("damage_affinity_tip_completed")
	_expect(SaveManager._migrate_save_data(version_twenty_one, item_catalog), "version twenty-one migration failed")
	_expect(version_twenty_one.get("tutorial_progress", null) == {"mining_tip_completed": true, "food_tip_completed": true, "crafting_tip_completed": true, "crafting_ingredients_tip_completed": true, "copper_mining_tip_completed": true, "sundown_weapon_tip_completed": false, "damage_affinity_tip_completed": false}, "version twenty-one damage affinity tutorial migration changed")
	var version_twenty_two := version_twenty_one.duplicate(true)
	version_twenty_two["version"] = 22
	var version_twenty_two_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	version_twenty_two_inventory.setup_empty()
	var legacy_selection := version_twenty_two_inventory.to_dict()
	legacy_selection.erase("item_equipped")
	legacy_selection.erase("last_equipped")
	legacy_selection["selected"] = 4
	version_twenty_two["inventory"] = legacy_selection
	_expect(SaveManager._migrate_save_data(version_twenty_two, item_catalog), "version twenty-two equipped-item migration failed")
	_expect(version_twenty_two["inventory"].get("item_equipped", null) == true, "version twenty-two migration did not preserve the equipped state")
	_expect(version_twenty_two["inventory"].get("last_equipped", null) == 4, "version twenty-two migration did not preserve the selected hotbar slot")
	var version_twenty_three := version_twenty_two.duplicate(true)
	version_twenty_three["version"] = 23
	version_twenty_three["placed_blocks"] = {"3,4,5": BlockId.Type.CAULDRON, "8,9,10": BlockId.Type.STONE}
	version_twenty_three["emplacements"] = {"12,13,14": BlockId.Type.CAMPFIRE}
	_expect(SaveManager._migrate_save_data(version_twenty_three, item_catalog), "version twenty-three cauldron migration failed")
	_expect(version_twenty_three["placed_blocks"] == {"8,9,10": BlockId.Type.STONE}, "version twenty-three migration retained a single-cell cauldron")
	_expect(version_twenty_three["emplacements"] == {"3,4,5": BlockId.Type.CAULDRON, "12,13,14": BlockId.Type.CAMPFIRE}, "version twenty-three migration did not preserve emplacement anchors")
	var migration_factory := EquipmentInstanceFactory.new(item_catalog)
	var migration_affixes: Array[EquipmentAffixDefinition] = [item_catalog.get_equipment_affix(&"vicious")]
	var migration_runes: Array[StringName] = [&"basic_rune"]
	var migration_sword := migration_factory.create(&"copper_sword", migration_affixes, migration_runes)
	_expect(migration_sword != null, "version eleven equipment fixture was not created")
	if migration_sword != null:
		var expected_instance := migration_sword.to_dict()
		var legacy_instance := expected_instance.duplicate(true)
		legacy_instance["current_durability"] = 37
		legacy_instance["maximum_durability"] = 100
		var legacy_inventory_model := InventoryModel.new(item_catalog, migration_factory)
		legacy_inventory_model.setup_empty()
		var legacy_inventory := legacy_inventory_model.to_dict()
		legacy_inventory.erase("item_equipped")
		legacy_inventory.erase("last_equipped")
		legacy_inventory["regions"]["hotbar"][0] = {
			"item_id": "copper_sword",
			"count": 1,
			"equipment_instance": legacy_instance,
		}
		var version_eleven := {
			"version": 11,
			"inventory": legacy_inventory,
			"chests": {},
			"next_equipment_instance_id": migration_factory.get_next_instance_id(),
		}
		_expect(SaveManager._migrate_save_data(version_eleven, item_catalog), "version eleven equipment save did not migrate")
		_expect(version_eleven.get("version", -1) == SaveManager.CURRENT_SAVE_VERSION, "version eleven equipment migration version changed")
		var migrated_instance: Dictionary = version_eleven["inventory"]["regions"]["hotbar"][0]["equipment_instance"]
		_expect(migrated_instance == expected_instance, "version eleven equipment migration changed identity, affixes, or runes")
	_expect(version_six.get("next_equipment_instance_id", 0) == 1, "version six equipment allocator changed")
	_expect(version_six.get("world_loot", null) == {"next_entry_id": 1, "entries": []}, "version six world loot migration shape changed")
	var legacy_chest_slots: Array = []
	legacy_chest_slots.resize(SaveManager.PERSISTED_CHEST_SLOT_COUNT)
	legacy_chest_slots.fill(null)
	legacy_chest_slots[0] = {
		"item_id": "dirt_block",
		"count": 2,
		"socketed_rune_ids": [],
	}
	var version_nine := {
		"version": 9,
		"placed_blocks": {
			"1,2,3": BlockId.Type.CHEST,
			"4,5,6": BlockId.Type.CHEST,
			"7,8,9": BlockId.Type.STONE,
		},
		"chest_inventories": {
			"1,2,3": {
				"size": SaveManager.PERSISTED_CHEST_SLOT_COUNT,
				"slots": legacy_chest_slots,
			},
		},
	}
	_expect(SaveManager._migrate_save_data(version_nine, item_catalog), "version nine unopened chest migration failed")
	var version_nine_chests = version_nine.get("chests", {})
	_expect(version_nine_chests is Dictionary and version_nine_chests.has("1,2,3"), "version nine populated chest was lost")
	_expect(version_nine_chests is Dictionary and version_nine_chests.has("4,5,6"), "version nine unopened chest storage was not synthesized")
	_expect(version_nine_chests is Dictionary and not version_nine_chests.has("7,8,9"), "version nine non-chest block received storage")
	if version_nine_chests is Dictionary and version_nine_chests.has("1,2,3"):
		var migrated_stack = version_nine_chests["1,2,3"][0]
		_expect(migrated_stack is Dictionary and migrated_stack["item_id"] == "dirt_block" and migrated_stack["count"] == 2, "version nine populated chest contents changed")
	var expected_empty_chest_slots: Array = []
	expected_empty_chest_slots.resize(SaveManager.PERSISTED_CHEST_SLOT_COUNT)
	expected_empty_chest_slots.fill(null)
	if version_nine_chests is Dictionary:
		_expect(version_nine_chests.get("4,5,6", null) == expected_empty_chest_slots, "version nine unopened chest did not receive canonical empty storage")
	var version_eleven := {
		"version": 11,
		"placed_blocks": {
			"10,11,12": BlockId.Type.CHEST,
			"13,14,15": BlockId.Type.STONE,
		},
		"chests": {},
		"next_equipment_instance_id": 1,
	}
	_expect(SaveManager._migrate_save_data(version_eleven, item_catalog), "version eleven unopened chest migration failed")
	var version_eleven_chests = version_eleven.get("chests", {})
	_expect(version_eleven_chests is Dictionary and version_eleven_chests.get("10,11,12", null) == expected_empty_chest_slots, "version eleven unopened chest storage was not synthesized")
	_expect(version_eleven_chests is Dictionary and not version_eleven_chests.has("13,14,15"), "version eleven non-chest block received storage")
	var malformed_legacy := {
		"version": 11,
		"placed_blocks": {"invalid": BlockId.Type.CHEST},
		"chests": {},
		"next_equipment_instance_id": 1,
	}
	var malformed_legacy_before := malformed_legacy.duplicate(true)
	_expect(not SaveManager._migrate_save_data(malformed_legacy, item_catalog), "malformed legacy placed block migrated")
	_expect(malformed_legacy == malformed_legacy_before, "failed legacy chest migration changed save data")
	var fractional_version := {"version": 11.5}
	var fractional_version_before := fractional_version.duplicate(true)
	_expect(not SaveManager._migrate_save_data(fractional_version, item_catalog), "fractional save version migrated")
	_expect(fractional_version == fractional_version_before, "fractional version rejection changed save data")
	var fractional_seed := {
		"version": SaveManager.CURRENT_SAVE_VERSION,
		"seed": 481516.5,
		"inventory": null,
		"chests": {},
		"next_equipment_instance_id": 1,
		"world_loot": {"next_entry_id": 1, "entries": []},
	}
	var fractional_seed_before := fractional_seed.duplicate(true)
	_expect(not SaveManager._migrate_save_data(fractional_seed, item_catalog), "fractional world seed migrated")
	_expect(fractional_seed == fractional_seed_before, "fractional seed rejection changed save data")
	_test_fractional_slot_metadata(item_catalog)
	_expect(SaveManager.decode_chest_state({"chests": {"invalid": []}}) == null, "malformed chest position decoded")
	_expect(SaveManager.decode_world_state({"seed": 1, "placed_blocks": {"0,1,0": BlockId.Type.COUNT}, "removed_blocks": {}, "torch_attachments": {}, "emplacements": {}, "player_position": null}) == null, "unknown placed block decoded")
	_expect(SaveManager.decode_world_state({"seed": 1, "placed_blocks": {"0,1,0": BlockId.Type.TORCH}, "removed_blocks": {}, "torch_attachments": {}, "emplacements": {}, "player_position": null}) == null, "torch without attachment decoded")
	_expect(SaveManager.decode_world_state({"seed": 1, "placed_blocks": {"0,1,0": BlockId.Type.CAULDRON}, "removed_blocks": {}, "torch_attachments": {}, "emplacements": {}, "player_position": null}) == null, "single-cell cauldron decoded in the current save format")
	_expect(SaveManager.decode_world_state({"seed": 1, "placed_blocks": {}, "removed_blocks": {"invalid": true}, "torch_attachments": {}, "emplacements": {}, "player_position": null}) == null, "malformed removed block decoded")
	_expect(BlockId.Type.ANVIL == 16 and BlockId.Type.CHEST == 17 and BlockId.Type.CAULDRON == 18 and BlockId.Type.CAMPFIRE == 19, "main station block IDs changed")
	_expect(item_catalog != null and item_catalog.has_definition(&"chest"), "main chest item ID changed")
	if block_catalog == null or item_catalog == null or chest_block == null or chest_block.container == null or player_stats_definition == null or player_perk_rules == null:
		_finish("")
		return
	var voxel_world := VoxelWorld.new(20, 36, 5, 12.0, block_catalog)
	var campfire_anchor := Vector3i(2, 21, 2)
	var campfire_definition := block_catalog.get_definition(BlockId.Type.CAMPFIRE)
	for offset in campfire_definition.emplacement.support_offsets:
		_expect(VoxelWorldTestFixture.commit_place(voxel_world, campfire_anchor + offset, BlockId.Type.STONE) != null, "campfire save support placement failed")
	_expect(VoxelWorldTestFixture.commit_place_emplacement(voxel_world, campfire_anchor, BlockId.Type.CAMPFIRE) != null, "campfire save placement failed")
	var cauldron_anchor := Vector3i(7, 21, 7)
	var cauldron_definition := block_catalog.get_definition(BlockId.Type.CAULDRON)
	for offset in cauldron_definition.emplacement.support_offsets:
		_expect(VoxelWorldTestFixture.commit_place(voxel_world, cauldron_anchor + offset, BlockId.Type.STONE) != null, "cauldron save support placement failed")
	_expect(VoxelWorldTestFixture.commit_place_emplacement(voxel_world, cauldron_anchor, BlockId.Type.CAULDRON) != null, "cauldron save placement failed")
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	inventory.setup_starter()
	var item_proficiency := ItemProficiency.new(item_catalog)
	var chest_storage := ChestStorage.new(item_catalog, inventory.equipment_instance_factory, chest_block.container.get_slot_count())
	var world_loot_state := WorldLootState.new(item_catalog, inventory.equipment_instance_factory)
	var chest_position := Vector3i(3, 8, -4)
	_expect(VoxelWorldTestFixture.commit_place(voxel_world, chest_position, BlockId.Type.CHEST) != null, "chest persistence block placement failed")
	_expect(chest_storage.create_chest(chest_position), "chest persistence storage creation failed")
	_expect(chest_storage.add_stack(chest_position, InventoryStack.new(&"dirt_block", 4), 0), "chest persistence content setup failed")
	var player_stats := ActorStats.new(player_stats_definition)
	var player_perks := PlayerPerks.new(player_perk_rules)
	var doorway_anchor := Vector3(11.5, 7.0, -9.5)
	var location := GameplayLocationState.new(Vector3(2.5, 5.0, 2.5))
	location.enter_level(doorway_anchor)
	location.update_world_position(Vector3(500.0, 4.0, 500.0))
	var slot_id := 1000000000 + OS.get_process_id()
	while SaveManager.slot_exists(slot_id):
		slot_id += 1
	var path := SaveManager.get_slot_path(slot_id)
	var current_data := {
		"slot_id": slot_id,
		"exists": true,
		"seed": 1337,
		"world_name": "Level Save Probe",
		"version": SaveManager.CURRENT_SAVE_VERSION,
		"placed_blocks": {},
		"removed_blocks": {},
		"torch_attachments": {},
		"emplacements": {},
		"chests": {},
		"world_loot": {"next_entry_id": 1, "entries": []},
		"dungeon_progress": DungeonProgressState.new().snapshot(),
		"tutorial_progress": {"mining_tip_completed": true, "food_tip_completed": true, "crafting_tip_completed": true, "crafting_ingredients_tip_completed": true, "copper_mining_tip_completed": true, "sundown_weapon_tip_completed": true, "damage_affinity_tip_completed": false},
		"playtime_seconds": 0.0,
		"time_of_day": 6.0,
	}
	var pumpkin_patch := {"present": false}
	var apple_trees := AppleTreeState.new().snapshot()
	var saved := SaveManager.save_world_state(slot_id, current_data, voxel_world, location.get_persisted_position(), player_stats, inventory, inventory.equipment_instance_factory, player_perks, item_proficiency, chest_storage, world_loot_state, DungeonProgressState.new(), pumpkin_patch, apple_trees, 2.5, 27.5)
	_expect(saved, "save_world_state failed")
	if saved:
		_expect(int(current_data.get("version", -1)) == SaveManager.CURRENT_SAVE_VERSION, "current_data version changed")
		_expect(current_data.get("player_position", []) == [doorway_anchor.x, doorway_anchor.y, doorway_anchor.z], "current_data position differs")
		_expect(current_data.get("player_stats", {}) == player_stats.snapshot_progression(), "current_data player stats differ")
		_expect(current_data.get("player_perks", {}) == player_perks.snapshot(), "current_data player perks differ")
		_expect(not current_data.has("chest_inventories"), "current_data retained legacy chest inventories")
		_expect(current_data.get("item_proficiency", {}) == item_proficiency.snapshot(), "current_data item proficiency differs")
		_expect(current_data.get("pumpkin_patch", {}) == pumpkin_patch, "current_data pumpkin patch differs")
		_expect(current_data.get("apple_trees", {}) == apple_trees, "current_data apple tree state differs")
		_expect(current_data.get("tutorial_progress", {}) == {"mining_tip_completed": true, "food_tip_completed": true, "crafting_tip_completed": true, "crafting_ingredients_tip_completed": true, "copper_mining_tip_completed": true, "sundown_weapon_tip_completed": true, "damage_affinity_tip_completed": false}, "current_data tutorial progress differs")
		_expect(current_data.get("world_loot", {}) == world_loot_state.snapshot(), "current_data world loot differs")
		_expect(current_data.get("emplacements", {}).get("2,21,2", -1) == BlockId.Type.CAMPFIRE, "current_data campfire emplacement differs")
		_expect(current_data.get("emplacements", {}).get("7,21,7", -1) == BlockId.Type.CAULDRON, "current_data cauldron emplacement differs")
		var encoded_chests := current_data.get("chests", {}) as Dictionary
		_expect(encoded_chests.has("3,8,-4") and encoded_chests["3,8,-4"][0]["item_id"] == "dirt_block" and encoded_chests["3,8,-4"][0]["count"] == 4, "current_data chest state differs")
		_expect(is_equal_approx(float(current_data.get("playtime_seconds", -1.0)), 2.5), "playtime changed")
		_expect(is_equal_approx(float(current_data.get("time_of_day", -1.0)), 3.5), "time wrapping changed")
		var loaded := SaveManager.load_slot(slot_id, item_catalog)
		_expect(bool(loaded.get("exists", false)), "saved slot did not load")
		_expect(int(loaded.get("version", -1)) == SaveManager.CURRENT_SAVE_VERSION and not bool(loaded.get("incompatible", false)), "current-version slot marked incompatible")
		var decoded := SaveManager.decode_world_state(loaded) as WorldState
		_expect(decoded != null, "saved world state did not decode")
		if decoded == null:
			_finish(path)
			return
		_expect(decoded.seed == 1337, "decoded seed changed")
		_expect(decoded.player_position.is_equal_approx(doorway_anchor), "decoded persisted position differs")
		_expect(decoded.emplacements.get(campfire_anchor, BlockId.Type.AIR) == BlockId.Type.CAMPFIRE, "decoded campfire emplacement differs")
		_expect(decoded.emplacements.get(cauldron_anchor, BlockId.Type.AIR) == BlockId.Type.CAULDRON, "decoded cauldron emplacement differs")
		var restored_factory := EquipmentInstanceFactory.new(item_catalog, int(loaded["next_equipment_instance_id"]))
		var restored_inventory := InventoryModel.new(item_catalog, restored_factory)
		var loaded_inventory: Variant = loaded.get("inventory", null)
		_expect(loaded_inventory is Dictionary and restored_inventory.from_dict(loaded_inventory as Dictionary), "loaded inventory did not decode")
		_expect(restored_inventory.to_dict() == inventory.to_dict(), "decoded inventory differs")
		var decoded_chests = SaveManager.decode_chest_state(loaded)
		var restored_chests := ChestStorage.new(item_catalog, restored_inventory.equipment_instance_factory, chest_block.container.get_slot_count())
		_expect(decoded_chests is Dictionary and restored_chests.restore(decoded_chests), "loaded chest state did not decode")
		_expect(restored_chests.snapshot() == chest_storage.snapshot(), "decoded chest state differs")
		_expect(Game._get_chest_state_error(voxel_world, restored_chests, BlockId.Type.CHEST).is_empty(), "nonempty chest round-trip failed strict validation")
		var missing_chest_storage := ChestStorage.new(item_catalog, restored_inventory.equipment_instance_factory, chest_block.container.get_slot_count())
		_expect(not Game._get_chest_state_error(voxel_world, missing_chest_storage, BlockId.Type.CHEST).is_empty(), "placed chest without storage passed strict validation")
	var cleanup_error := OK
	if FileAccess.file_exists(path):
		cleanup_error = DirAccess.remove_absolute(path)
	_expect(cleanup_error == OK and not FileAccess.file_exists(path), "temporary slot cleanup failed")
	_finish(path)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		print("[level_save_probe] %s" % message)

func _finish(path: String) -> void:
	if _failures == 0:
		print("LEVEL_SAVE_PROBE PASS path=%s" % path)
		quit(0)
	else:
		print("LEVEL_SAVE_PROBE FAILED failures=%d path=%s" % [_failures, path])
		quit(1)

func _test_fractional_slot_metadata(item_catalog: ItemCatalog) -> void:
	var slot_id := 1050000000 + OS.get_process_id()
	while SaveManager.slot_exists(slot_id):
		slot_id += 1
	var path := SaveManager.get_slot_path(slot_id)
	_expect(SaveManager._save_dict_to_file(slot_id, {"version": 11.5, "seed": 481516.5}), "fractional metadata fixture was not written")
	var info := SaveManager.get_slot_info(slot_id)
	_expect(typeof(info.get("version", null)) == TYPE_FLOAT and is_equal_approx(float(info["version"]), 11.5), "slot metadata coerced a fractional version")
	_expect(typeof(info.get("seed", null)) == TYPE_FLOAT and is_equal_approx(float(info["seed"]), 481516.5), "slot metadata coerced a fractional seed")
	var loaded := SaveManager.load_slot(slot_id, item_catalog)
	_expect(bool(loaded.get("incompatible", false)), "fractional slot metadata loaded as compatible")
	var cleanup_error := OK
	if FileAccess.file_exists(path):
		cleanup_error = DirAccess.remove_absolute(path)
	_expect(cleanup_error == OK and not FileAccess.file_exists(path), "fractional metadata fixture cleanup failed")
