extends SceneTree

var _errors: Array[String] = []
var _item_catalog: ItemCatalog
var _block_catalog: BlockCatalog
var _slot_id: int
var _save_path: String

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_item_catalog = load("res://items/item_catalog.tres") as ItemCatalog
	_block_catalog = load("res://blocks/block_catalog.tres") as BlockCatalog
	_expect(_item_catalog != null, "item catalog did not load")
	_expect(_block_catalog != null, "block catalog did not load")
	if _item_catalog != null and _block_catalog != null:
		_test_version_thirteen_migration()
		_test_version_fourteen_migration()
		_test_strict_current_schema()
		_test_save_round_trip()
	_finish()

func _test_version_thirteen_migration() -> void:
	var legacy := _base_save(13)
	var original_world_loot: Dictionary = legacy["world_loot"].duplicate(true)
	_expect(SaveManager._migrate_save_data(legacy, _item_catalog), "version-thirteen save did not migrate")
	_expect(legacy["version"] == SaveManager.CURRENT_SAVE_VERSION, "version-thirteen save reached the wrong version")
	_expect(legacy["dungeon_progress"] == DungeonProgressState.new().snapshot(), "version-thirteen migration did not initialize exact dungeon progress")
	_expect(legacy["world_loot"] == original_world_loot, "version-thirteen migration changed world loot")

	var conflicting := _base_save(13)
	conflicting["dungeon_progress"] = DungeonProgressState.new().snapshot()
	_expect_rejected_unchanged(conflicting, "version-thirteen save with future dungeon progress migrated")

func _test_version_fourteen_migration() -> void:
	var legacy := _base_save(14)
	_expect(SaveManager._migrate_save_data(legacy, _item_catalog), "version-fourteen save did not migrate")
	_expect(legacy["version"] == SaveManager.CURRENT_SAVE_VERSION, "version-fourteen save reached the wrong version")
	_expect(legacy["emplacements"] == {}, "version-fourteen migration changed emplacements")
	_expect(legacy["dungeon_progress"] == DungeonProgressState.new().snapshot(), "version-fourteen migration did not initialize exact dungeon progress")

	var conflicting := _base_save(14)
	conflicting["dungeon_progress"] = DungeonProgressState.new().snapshot()
	_expect_rejected_unchanged(conflicting, "version-fourteen save with future dungeon progress migrated")

func _test_strict_current_schema() -> void:
	var current := _base_save(SaveManager.CURRENT_SAVE_VERSION)
	current["dungeon_progress"] = {
		"version": 1,
		"instances": {
			"stone_story": {
				"next_attempt_index": 3,
				"completion_count": 1,
				"claimed_reward_ids": ["basic_rune_reward"],
			},
		},
	}
	_expect(SaveManager._migrate_save_data(current, _item_catalog), "valid current dungeon progress was rejected")
	var missing := current.duplicate(true)
	missing.erase("dungeon_progress")
	_expect_rejected_unchanged(missing, "current save without dungeon progress migrated")
	var future_snapshot := current.duplicate(true)
	future_snapshot["dungeon_progress"]["version"] = 2
	_expect_rejected_unchanged(future_snapshot, "future dungeon progress snapshot migrated")
	var malformed_instance := current.duplicate(true)
	malformed_instance["dungeon_progress"]["instances"]["stone_story"]["completion_count"] = 1.5
	_expect_rejected_unchanged(malformed_instance, "fractional dungeon completion count migrated")
	var extra_snapshot_field := current.duplicate(true)
	extra_snapshot_field["dungeon_progress"]["extra"] = true
	_expect_rejected_unchanged(extra_snapshot_field, "extra dungeon progress field migrated")

func _test_save_round_trip() -> void:
	var chest_block := _block_catalog.get_definition(BlockId.Type.CHEST)
	_expect(chest_block != null and chest_block.container != null, "chest definition did not load")
	if chest_block == null or chest_block.container == null:
		return
	_slot_id = 1200000000 + OS.get_process_id()
	while SaveManager.slot_exists(_slot_id):
		_slot_id += 1
	_save_path = SaveManager.get_slot_path(_slot_id)
	var save_data := SaveManager.create_new_world(_slot_id, 98765, "Dungeon Progress Persistence")
	var empty_snapshot := DungeonProgressState.new().snapshot()
	_expect(save_data.get("dungeon_progress", null) == empty_snapshot, "new world did not initialize dungeon progress")

	var factory := EquipmentInstanceFactory.new(_item_catalog)
	var inventory := InventoryModel.new(_item_catalog, factory)
	_expect(inventory.setup_empty(), "inventory setup failed")
	var player_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	var player_perks := PlayerPerks.new(load("res://progression/player_perk_rules.tres") as PlayerPerkRules)
	var item_proficiency := ItemProficiency.new(_item_catalog)
	var chest_storage := ChestStorage.new(_item_catalog, factory, chest_block.container.get_slot_count())
	var world_loot := WorldLootState.new(_item_catalog, factory)
	var progress := DungeonProgressState.new()
	_expect(progress.begin_attempt(&"stone_story") == 0, "progress attempt setup failed")
	var completion := progress.prepare_completion(&"stone_story", &"basic_rune_reward")
	_expect(completion != null and progress.commit_prepared_completion(completion), "progress completion setup failed")
	_expect(progress.begin_attempt(&"stone_story") == 1, "second progress attempt setup failed")
	var expected_snapshot := progress.snapshot()
	var voxel_world := VoxelWorld.new(20, 36, 5, 12.0, _block_catalog)
	var saved := SaveManager.save_world_state(
		_slot_id,
		save_data,
		voxel_world,
		Vector3(2.5, 4.0, -3.5),
		player_stats,
		inventory,
		factory,
		player_perks,
		item_proficiency,
		chest_storage,
		world_loot,
		progress,
		{"present": false},
		AppleTreeState.new().snapshot(),
		0.0,
		6.0,
	)
	_expect(saved, "dungeon progress save failed")
	_expect(save_data.get("dungeon_progress", null) == expected_snapshot, "in-memory save changed dungeon progress")
	var loaded := SaveManager.load_slot(_slot_id, _item_catalog)
	_expect(not bool(loaded.get("incompatible", false)), "saved dungeon progress was marked incompatible")
	var restored := DungeonProgressState.new()
	_expect(restored.restore(loaded.get("dungeon_progress", null)), "saved dungeon progress did not restore")
	_expect(restored.snapshot() == expected_snapshot, "saved dungeon progress did not round-trip")

func _base_save(version: int) -> Dictionary:
	var data := {
		"version": version,
		"inventory": null,
		"chests": {},
		"next_equipment_instance_id": 1,
		"world_loot": {"next_entry_id": 1, "entries": []},
		"player_perks": {"allocations": {}},
		"apple_trees": AppleTreeState.new().snapshot(),
	}
	if version >= 14:
		data["emplacements"] = {}
	return data

func _expect_rejected_unchanged(data: Dictionary, message: String) -> void:
	var before := data.duplicate(true)
	_expect(not SaveManager._migrate_save_data(data, _item_catalog), message)
	_expect(data == before, "%s and changed save data" % message)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)

func _finish() -> void:
	var cleanup_error := OK
	if not _save_path.is_empty() and FileAccess.file_exists(_save_path):
		cleanup_error = DirAccess.remove_absolute(_save_path)
	_expect(cleanup_error == OK and (_save_path.is_empty() or not FileAccess.file_exists(_save_path)), "temporary save cleanup failed")
	if _errors.is_empty():
		print("DUNGEON_PROGRESS_PERSISTENCE PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)
