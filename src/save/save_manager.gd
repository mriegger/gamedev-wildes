extends RefCounted
class_name SaveManager

const SAVE_DIR: String = "user://saves"
const SLOT_COUNT: int = 3
const CURRENT_SAVE_VERSION: int = 5
const MIGRATABLE_SAVE_VERSION: int = 4

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
		"copper_blocks": {},
		"generated_copper_chunks": {},
		"player_position": null,
		"player_stats": null,
		"item_proficiency": {},
		"inventory": null,
		"playtime_seconds": 0,
		"time_of_day": 6.0,
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

static func serialize_vector2i_dict(dict: Dictionary) -> Dictionary:
	var out := {}
	for position in dict:
		out["%d,%d" % [position.x, position.y]] = dict[position]
	return out

static func _deserialize_vector2i_dict(dict: Dictionary) -> Dictionary:
	var out := {}
	for key in dict:
		var parts := (key as String).split(",")
		if parts.size() == 2:
			out[Vector2i(int(parts[0]), int(parts[1]))] = dict[key]
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
	var copper_raw = data.get("copper_blocks", {})
	var generated_copper_raw = data.get("generated_copper_chunks", {})
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
		position,
		_deserialize_block_ids(copper_raw) if copper_raw is Dictionary else {},
		_deserialize_vector2i_dict(generated_copper_raw) if generated_copper_raw is Dictionary else {}
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
	if not info.has("copper_blocks"):
		info["copper_blocks"] = {}
	if not info.has("generated_copper_chunks"):
		info["generated_copper_chunks"] = {}
	if not info.has("time_of_day"):
		info["time_of_day"] = 6.0
	if not info.has("playtime_seconds"):
		info["playtime_seconds"] = 0
	if not info.has("player_stats"):
		info["player_stats"] = null
	if not info.has("item_proficiency"):
		info["item_proficiency"] = {}
	return info

static func _migrate_save_data(data: Dictionary) -> bool:
	var version := int(data.get("version", 0))
	if version == MIGRATABLE_SAVE_VERSION:
		data["item_proficiency"] = {}
		data["version"] = CURRENT_SAVE_VERSION
		return true
	return version == CURRENT_SAVE_VERSION

static func save_world_state(slot_id: int, current_data: Dictionary, voxel_model: VoxelWorld, player: PlayerMotor, inventory: InventoryModel, item_proficiency: ItemProficiency, extra_seconds: float, time_of_day: float) -> bool:
	assert(item_proficiency != null)
	var updated = current_data.duplicate()
	updated["last_played"] = _now_str()
	updated["version"] = CURRENT_SAVE_VERSION
	updated["playtime_seconds"] = float(updated.get("playtime_seconds", 0)) + extra_seconds

	var block_edits := voxel_model.snapshot_block_edits()
	updated["placed_blocks"] = serialize_vector3i_dict(block_edits["placed"])
	updated["removed_blocks"] = serialize_vector3i_dict(block_edits["removed"])
	updated["torch_attachments"] = serialize_vector3i_dict(voxel_model.torch_attachments)
	var copper_generation := voxel_model.snapshot_copper_generation()
	updated["copper_blocks"] = serialize_vector3i_dict(copper_generation["blocks"])
	updated["generated_copper_chunks"] = serialize_vector2i_dict(copper_generation["chunks"])
	var p = player.global_position
	updated["player_position"] = [p.x, p.y, p.z]
	updated["player_stats"] = player.stats.snapshot_progression()
	updated["inventory"] = inventory.to_dict()
	updated["item_proficiency"] = item_proficiency.snapshot()
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
