extends SceneTree

var _failures: int = 0

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var player_stats_definition := load("res://player/player_stats.tres") as CombatStatsDefinition
	var player_perk_rules := load("res://progression/player_perk_rules.tres") as PlayerPerkRules
	_expect(SaveManager.CURRENT_SAVE_VERSION == 12, "save version changed")
	_expect(block_catalog != null and block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog != null and item_catalog.validate(block_catalog), "item catalog invalid")
	_expect(player_stats_definition != null and player_stats_definition.validate(), "player stats definition invalid")
	_expect(player_perk_rules != null and player_perk_rules.validate(player_stats_definition), "player perk rules invalid")
	var version_six := {"version": 6}
	_expect(SaveManager._migrate_save_data(version_six, item_catalog), "version six migration failed")
	_expect(version_six.get("version", -1) == SaveManager.CURRENT_SAVE_VERSION, "version six migration version changed")
	_expect(version_six.get("pumpkin_patch", null) == {"present": false}, "version six pumpkin migration shape changed")
	_expect(version_six.get("player_perks", null) == {"allocations": {}}, "version six perk migration shape changed")
	_expect(version_six.get("chests", null) == {}, "version six chest migration shape changed")
	_expect(version_six.get("apple_trees", null) == AppleTreeState.new().snapshot(), "version six apple migration shape changed")
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
	_expect(SaveManager.decode_world_state({"seed": 1, "placed_blocks": {"0,1,0": BlockId.Type.COUNT}, "removed_blocks": {}, "torch_attachments": {}, "player_position": null}) == null, "unknown placed block decoded")
	_expect(SaveManager.decode_world_state({"seed": 1, "placed_blocks": {"0,1,0": BlockId.Type.TORCH}, "removed_blocks": {}, "torch_attachments": {}, "player_position": null}) == null, "torch without attachment decoded")
	_expect(SaveManager.decode_world_state({"seed": 1, "placed_blocks": {}, "removed_blocks": {"invalid": true}, "torch_attachments": {}, "player_position": null}) == null, "malformed removed block decoded")
	if block_catalog == null or item_catalog == null or player_stats_definition == null or player_perk_rules == null:
		_finish("")
		return
	var voxel_world := VoxelWorld.new(20, 36, 5, 12.0, block_catalog)
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	inventory.setup_starter()
	var chest_storage := ChestInventoryStore.new(item_catalog, inventory.equipment_instance_factory)
	var chest_position := Vector3i(4, 5, 6)
	var chest_inventory := chest_storage.get_or_create(chest_position, 15)
	chest_inventory.slots[0] = InventoryStack.new(&"log_block", 7)
	var item_proficiency := ItemProficiency.new(item_catalog)
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
		"playtime_seconds": 0.0,
		"time_of_day": 6.0,
	}
	var pumpkin_patch := {"present": false}
	var saved := SaveManager.save_world_state(slot_id, current_data, voxel_world, location.get_persisted_position(), player_stats, inventory, inventory.equipment_instance_factory, player_perks, item_proficiency, chest_storage, pumpkin_patch, AppleTreeState.new().snapshot(), 2.5, 27.5)
	_expect(saved, "save_world_state failed")
	if saved:
		_expect(int(current_data.get("version", -1)) == SaveManager.CURRENT_SAVE_VERSION, "current_data version changed")
		_expect(current_data.get("player_position", []) == [doorway_anchor.x, doorway_anchor.y, doorway_anchor.z], "current_data position differs")
		_expect(current_data.get("player_stats", {}) == player_stats.snapshot_progression(), "current_data player stats differ")
		_expect(current_data.get("player_perks", {}) == player_perks.snapshot(), "current_data player perks differ")
		_expect(current_data.get("chests", {}) == SaveManager.serialize_vector3i_dict(chest_storage.snapshot()), "current_data chest inventories differ")
		_expect(current_data.get("item_proficiency", {}) == item_proficiency.snapshot(), "current_data item proficiency differs")
		_expect(current_data.get("pumpkin_patch", {}) == pumpkin_patch, "current_data pumpkin patch differs")
		_expect(current_data.get("apple_trees", {}) == AppleTreeState.new().snapshot(), "current_data apple tree state differs")
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
		var restored_factory := EquipmentInstanceFactory.new(item_catalog, int(loaded.get("next_equipment_instance_id", 1)))
		var restored_inventory := InventoryModel.new(item_catalog, restored_factory)
		var loaded_inventory: Variant = loaded.get("inventory", null)
		_expect(loaded_inventory is Dictionary and restored_inventory.from_dict(loaded_inventory as Dictionary), "loaded inventory did not decode")
		_expect(restored_inventory.to_dict() == inventory.to_dict(), "decoded inventory differs")
		var restored_chest_storage := ChestInventoryStore.new(item_catalog, restored_factory)
		var loaded_chests: Variant = SaveManager.decode_chest_state(loaded)
		_expect(loaded_chests is Dictionary and restored_chest_storage.restore(loaded_chests as Dictionary), "loaded chest inventories did not decode")
		var restored_chest := restored_chest_storage.get_inventory(chest_position)
		_expect(restored_chest != null and restored_chest.get_slot(0).item_id == &"log_block" and restored_chest.get_slot(0).count == 7, "decoded chest inventory differs")
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
