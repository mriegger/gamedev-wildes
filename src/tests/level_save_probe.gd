extends SceneTree

var _failures: int = 0

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var player_stats_definition := load("res://player/player_stats.tres") as CombatStatsDefinition
	var player_perk_rules := load("res://progression/player_perk_rules.tres") as PlayerPerkRules
	_expect(SaveManager.CURRENT_SAVE_VERSION == 8, "save version changed")
	_expect(block_catalog != null and block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog != null and item_catalog.validate(block_catalog), "item catalog invalid")
	_expect(player_stats_definition != null and player_stats_definition.validate(), "player stats definition invalid")
	_expect(player_perk_rules != null and player_perk_rules.validate(player_stats_definition), "player perk rules invalid")
	if block_catalog == null or item_catalog == null or player_stats_definition == null or player_perk_rules == null:
		_finish("")
		return
	var voxel_world := VoxelWorld.new(20, 36, 5, 12.0, block_catalog)
	var inventory := InventoryModel.new(item_catalog)
	inventory.setup_starter()
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
	var saved := SaveManager.save_world_state(slot_id, current_data, voxel_world, location.get_persisted_position(), player_stats, inventory, player_perks, item_proficiency, pumpkin_patch, 2.5, 27.5)
	_expect(saved, "save_world_state failed")
	if saved:
		_expect(int(current_data.get("version", -1)) == SaveManager.CURRENT_SAVE_VERSION, "current_data version changed")
		_expect(current_data.get("player_position", []) == [doorway_anchor.x, doorway_anchor.y, doorway_anchor.z], "current_data position differs")
		_expect(current_data.get("player_stats", {}) == player_stats.snapshot_progression(), "current_data player stats differ")
		_expect(current_data.get("player_perks", {}) == player_perks.snapshot(), "current_data player perks differ")
		_expect(current_data.get("item_proficiency", {}) == item_proficiency.snapshot(), "current_data item proficiency differs")
		_expect(current_data.get("pumpkin_patch", {}) == pumpkin_patch, "current_data pumpkin patch differs")
		_expect(is_equal_approx(float(current_data.get("playtime_seconds", -1.0)), 2.5), "playtime changed")
		_expect(is_equal_approx(float(current_data.get("time_of_day", -1.0)), 3.5), "time wrapping changed")
		var loaded := SaveManager.load_slot(slot_id)
		_expect(bool(loaded.get("exists", false)), "saved slot did not load")
		_expect(int(loaded.get("version", -1)) == SaveManager.CURRENT_SAVE_VERSION and not bool(loaded.get("incompatible", false)), "current-version slot marked incompatible")
		var decoded := SaveManager.decode_world_state(loaded)
		_expect(decoded.seed == 1337, "decoded seed changed")
		_expect(decoded.player_position.is_equal_approx(doorway_anchor), "decoded persisted position differs")
		var restored_inventory := InventoryModel.new(item_catalog)
		var loaded_inventory: Variant = loaded.get("inventory", null)
		_expect(loaded_inventory is Dictionary and restored_inventory.from_dict(loaded_inventory as Dictionary), "loaded inventory did not decode")
		_expect(restored_inventory.to_dict() == inventory.to_dict(), "decoded inventory differs")
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
