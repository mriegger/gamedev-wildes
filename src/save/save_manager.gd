extends RefCounted
class_name SaveManager

const SAVE_DIR: String = "user://saves"
const SLOT_COUNT: int = 3
const CURRENT_SAVE_VERSION: int = 9
const MINIMUM_MIGRATABLE_SAVE_VERSION: int = 4
const VERSION_SEVEN_BASE_EXPERIENCE_TO_LEVEL: int = 100
const VERSION_SEVEN_EXPERIENCE_GROWTH: float = 1.25
const VERSION_EIGHT_BASE_EXPERIENCE_TO_LEVEL: int = 100
const VERSION_EIGHT_EXPERIENCE_INCREASE_PER_LEVEL: int = 25

static func ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)

static func _now_str() -> String:
	var now = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d" % [now.year, now.month, now.day, now.hour, now.minute]

static func _try_parse_vector3i(s: String) -> Variant:
	var parts = s.split(",")
	if parts.size() != 3:
		return null
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))

static func get_slot_path(slot_id: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot_id]

static func slot_exists(slot_id: int) -> bool:
	return FileAccess.file_exists(get_slot_path(slot_id))

static func get_slot_info(slot_id: int) -> Dictionary:
	if not slot_exists(slot_id):
		return {
			"exists": false,
			"slot_id": slot_id,
		}
	var path = get_slot_path(slot_id)
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"exists": false, "slot_id": slot_id}
	var txt = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[SaveManager] Corrupt save slot %d" % slot_id)
		return {"exists": false, "slot_id": slot_id, "corrupt": true}
	parsed["exists"] = true
	parsed["slot_id"] = int(parsed.get("slot_id", slot_id))
	if parsed.has("seed"):
		parsed["seed"] = int(parsed["seed"])
	if parsed.has("version"):
		parsed["version"] = int(parsed["version"])
	return parsed

static func get_all_slots() -> Array:
	var out: Array = []
	for i in range(SLOT_COUNT):
		out.append(load_slot(i))
	return out

static func generate_random_seed() -> int:
	var r = RandomNumberGenerator.new()
	r.randomize()
	return r.randi_range(1, 2147483646)

static func create_new_world(slot_id: int, seed_value: int, world_name: String) -> Dictionary:
	var now_str = _now_str()

	var data := {
		"slot_id": slot_id,
		"exists": true,
		"seed": seed_value,
		"world_name": world_name,
		"created_at": now_str,
		"last_played": now_str,
		"version": CURRENT_SAVE_VERSION,
		"placed_blocks": {},
		"removed_blocks": {},
		"torch_attachments": {},
		"player_position": null,
		"player_stats": null,
		"player_perks": {"allocations": {}},
		"item_proficiency": {},
		"inventory": null,
		"chest_inventories": {},
		"playtime_seconds": 0,
		"time_of_day": 6.0,
		"pumpkin_patch": null,
		"apple_trees": null,
	}

	_save_dict_to_file(slot_id, data)
	return data

static func _save_dict_to_file(slot_id: int, data: Dictionary) -> bool:
	ensure_save_dir()
	var path = get_slot_path(slot_id)
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[SaveManager] Failed to write slot %d to %s" % [slot_id, path])
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true

static func delete_slot(slot_id: int) -> bool:
	var path = get_slot_path(slot_id)
	if not FileAccess.file_exists(path):
		return true
	var err = DirAccess.remove_absolute(path)
	if err != OK:
		push_error("[SaveManager] Failed to delete slot %d" % slot_id)
		return false
	return true

static func serialize_vector3i_dict(dict: Dictionary) -> Dictionary:
	var out := {}
	for pos in dict:
		var key_str = "%d,%d,%d" % [pos.x, pos.y, pos.z]
		var v = dict[pos]
		if v is Vector3i:
			out[key_str] = "%d,%d,%d" % [v.x, v.y, v.z]
		else:
			out[key_str] = v
	return out

static func _deserialize_block_ids(dict: Dictionary) -> Dictionary:
	var out := {}
	for key in dict:
		var pos = _try_parse_vector3i(key)
		if pos != null:
			out[pos] = int(dict[key])
	return out

static func _deserialize_removed_blocks(dict: Dictionary) -> Dictionary:
	var out := {}
	for key in dict:
		var pos = _try_parse_vector3i(key)
		if pos != null:
			out[pos] = true
	return out

static func _deserialize_torch_attachments(dict: Dictionary) -> Dictionary:
	var out := {}
	for key in dict:
		var pos = _try_parse_vector3i(key)
		var attach_dir = _try_parse_vector3i(dict[key]) if dict[key] is String else null
		if pos != null and attach_dir != null:
			out[pos] = attach_dir
	return out

static func decode_world_state(data: Dictionary) -> WorldState:
	var placed_raw = data.get("placed_blocks", {})
	var removed_raw = data.get("removed_blocks", {})
	var torch_raw = data.get("torch_attachments", {})
	var position = Vector3.ZERO
	var position_data = data.get("player_position", null)
	if position_data is Array and position_data.size() == 3:
		var decoded = Vector3(float(position_data[0]), float(position_data[1]), float(position_data[2]))
		if decoded.length() > 1.0:
			position = decoded
	return WorldState.new(
		int(data.get("seed", -1)),
		_deserialize_block_ids(placed_raw) if placed_raw is Dictionary else {},
		_deserialize_removed_blocks(removed_raw) if removed_raw is Dictionary else {},
		_deserialize_torch_attachments(torch_raw) if torch_raw is Dictionary else {},
		position
	)

static func load_slot(slot_id: int) -> Dictionary:
	var info = get_slot_info(slot_id)
	if not info.get("exists", false):
		return info
	if not _migrate_save_data(info):
		info["incompatible"] = true
		return info
	if not info.has("seed"):
		info["seed"] = generate_random_seed()
	if not info.has("world_name"):
		info["world_name"] = "World %d" % (slot_id + 1)
	if not info.has("placed_blocks"):
		info["placed_blocks"] = {}
	if not info.has("removed_blocks"):
		info["removed_blocks"] = {}
	if not info.has("torch_attachments"):
		info["torch_attachments"] = {}
	info.erase("copper_blocks")
	info.erase("generated_copper_chunks")
	if not info.has("time_of_day"):
		info["time_of_day"] = 6.0
	if not info.has("playtime_seconds"):
		info["playtime_seconds"] = 0
	if not info.has("player_stats"):
		info["player_stats"] = null
	if not info.has("player_perks"):
		info["player_perks"] = {"allocations": {}}
	if not info.has("item_proficiency"):
		info["item_proficiency"] = {}
	if not info.has("pumpkin_patch"):
		info["pumpkin_patch"] = {"present": false}
	if not info.has("chest_inventories"):
		info["chest_inventories"] = {}
	if not info.has("apple_trees"):
		info["apple_trees"] = AppleTreeState.new().snapshot()
	return info

static func _migrate_save_data(data: Dictionary) -> bool:
	var migrated := data.duplicate(true)
	var version := int(migrated.get("version", 0))
	if version < MINIMUM_MIGRATABLE_SAVE_VERSION or version > CURRENT_SAVE_VERSION:
		return false
	while version < CURRENT_SAVE_VERSION:
		match version:
			4:
				migrated["item_proficiency"] = {}
				version = 5
			5:
				if not _migrate_inventory_socket_data(migrated):
					return false
				version = 6
			6:
				migrated["pumpkin_patch"] = {"present": false}
				version = 7
			7:
				if not _migrate_player_progression_data(migrated):
					return false
				migrated["chest_inventories"] = {}
				version = 8
			8:
				migrated["apple_trees"] = AppleTreeState.new().snapshot()
				version = 9
			_:
				return false
		migrated["version"] = version
	data.clear()
	data.merge(migrated, true)
	return true

static func _migrate_player_progression_data(data: Dictionary) -> bool:
	if data.has("player_perks"):
		return false
	if not data.has("player_stats") or data["player_stats"] == null:
		data["player_perks"] = {"allocations": {}}
		return true
	var raw_player_stats = data["player_stats"]
	if not raw_player_stats is Dictionary:
		return false
	var player_stats := raw_player_stats as Dictionary
	if not _is_valid_version_seven_player_stats(player_stats):
		return false
	var level := int(player_stats["level"])
	var experience := int(player_stats["experience"])
	var previous_requirement := _get_version_seven_experience_requirement(level)
	if previous_requirement <= 0 or experience >= previous_requirement:
		return false
	var next_requirement := VERSION_EIGHT_BASE_EXPERIENCE_TO_LEVEL + VERSION_EIGHT_EXPERIENCE_INCREASE_PER_LEVEL * (level - 1)
	player_stats["experience"] = mini(next_requirement - 1, int(floor(float(experience) * float(next_requirement) / float(previous_requirement))))
	data["player_perks"] = {"allocations": {}}
	return true

static func _is_valid_version_seven_player_stats(player_stats: Dictionary) -> bool:
	if not player_stats.has("level") or not player_stats.has("experience"):
		return false
	for key in player_stats:
		if key != "level" and key != "experience" and key != "current_hp":
			return false
	if not _is_integer_number(player_stats["level"]) or not _is_integer_number(player_stats["experience"]):
		return false
	var level := int(player_stats["level"])
	var experience := int(player_stats["experience"])
	if level < 1 or experience < 0:
		return false
	if player_stats.has("current_hp"):
		var raw_current_hp = player_stats["current_hp"]
		if (typeof(raw_current_hp) != TYPE_INT and typeof(raw_current_hp) != TYPE_FLOAT) or not is_finite(float(raw_current_hp)) or float(raw_current_hp) < 0.0:
			return false
	return true

static func _is_integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number)

static func _get_version_seven_experience_requirement(level: int) -> int:
	var requirement: float = round(float(VERSION_SEVEN_BASE_EXPERIENCE_TO_LEVEL) * pow(VERSION_SEVEN_EXPERIENCE_GROWTH, level - 1))
	if not is_finite(requirement) or requirement < 1.0 or requirement > 9.0e18:
		return 0
	return int(requirement)

static func _migrate_inventory_socket_data(data: Dictionary) -> bool:
	var inventory = data.get("inventory", null)
	if inventory == null:
		return true
	if not inventory is Dictionary:
		return false
	var regions = (inventory as Dictionary).get("regions", null)
	if not regions is Dictionary:
		return false
	for region_name in ["hotbar", "backpack", "equipment"]:
		var encoded_region = (regions as Dictionary).get(region_name, null)
		if not encoded_region is Array:
			return false
		for raw_stack in encoded_region as Array:
			if raw_stack == null:
				continue
			if not raw_stack is Dictionary:
				return false
			var encoded_stack := raw_stack as Dictionary
			if (
				not encoded_stack.has("item_id")
				or not encoded_stack.has("count")
				or encoded_stack.has("socketed_rune_ids")
			):
				return false
			encoded_stack["socketed_rune_ids"] = []
	return true

static func save_world_state(slot_id: int, current_data: Dictionary, voxel_model: VoxelWorld, persisted_player_position: Vector3, player_stats: ActorStats, inventory: InventoryModel, player_perks: PlayerPerks, chest_storage: ChestInventoryStore, item_proficiency: ItemProficiency, pumpkin_patch: Dictionary, apple_trees: Dictionary, extra_seconds: float, time_of_day: float) -> bool:
	assert(player_perks != null)
	assert(item_proficiency != null)
	assert(chest_storage != null)
	var updated = current_data.duplicate()
	updated["last_played"] = _now_str()
	updated["version"] = CURRENT_SAVE_VERSION
	updated["playtime_seconds"] = float(updated.get("playtime_seconds", 0)) + extra_seconds

	var block_edits := voxel_model.snapshot_block_edits()
	updated["placed_blocks"] = serialize_vector3i_dict(block_edits["placed"])
	updated["removed_blocks"] = serialize_vector3i_dict(block_edits["removed"])
	updated["torch_attachments"] = serialize_vector3i_dict(voxel_model.torch_attachments)
	updated.erase("copper_blocks")
	updated.erase("generated_copper_chunks")
	var p = persisted_player_position
	updated["player_position"] = [p.x, p.y, p.z]
	updated["player_stats"] = player_stats.snapshot_progression()
	updated["player_perks"] = player_perks.snapshot()
	updated["inventory"] = inventory.to_dict()
	updated["chest_inventories"] = chest_storage.snapshot()
	updated["item_proficiency"] = item_proficiency.snapshot()
	updated["pumpkin_patch"] = pumpkin_patch.duplicate(true)
	updated["apple_trees"] = apple_trees.duplicate(true)
	updated["time_of_day"] = fmod(time_of_day, GameClock.HOURS_PER_DAY)

	if not _save_dict_to_file(slot_id, updated):
		return false
	current_data.clear()
	current_data.merge(updated, true)
	return true

static func update_last_played(slot_id: int, data: Dictionary) -> bool:
	var updated = data.duplicate()
	updated["last_played"] = _now_str()
	if not _save_dict_to_file(slot_id, updated):
		return false
	data.clear()
	data.merge(updated, true)
	return true
