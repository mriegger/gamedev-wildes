extends RefCounted
class_name SaveManager

## SaveManager - Handles 3 save slots locally with JSON persistence
## Each slot stores seed, metadata, and voxel edits
## Location: user://saves/slot_{id}.json

const SAVE_DIR: String = "user://saves"
const SLOT_COUNT: int = 3

# --- Static helpers (no instance needed) ---

static func ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)

static func get_slot_path(slot_id: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot_id]

static func slot_exists(slot_id: int) -> bool:
	ensure_save_dir()
	return FileAccess.file_exists(get_slot_path(slot_id))

static func get_slot_info(slot_id: int) -> Dictionary:
	ensure_save_dir()
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
	if not parsed.has("slot_id"):
		parsed["slot_id"] = slot_id
	return parsed

static func get_all_slots() -> Array:
	var out: Array = []
	for i in range(SLOT_COUNT):
		out.append(get_slot_info(i))
	return out

static func generate_random_seed() -> int:
	# Use global RNG seeded from randomize, produce 31-bit positive seed
	var r = RandomNumberGenerator.new()
	r.randomize()
	return r.randi_range(1, 2147483646)

static func create_new_world(slot_id: int, custom_seed: int = -1, world_name: String = "") -> Dictionary:
	ensure_save_dir()
	var seed_val: int
	if custom_seed == -1:
		seed_val = generate_random_seed()
	else:
		seed_val = custom_seed

	if world_name == "":
		world_name = "World %d" % (slot_id + 1)

	var now = Time.get_datetime_dict_from_system()
	var now_str = "%04d-%02d-%02d %02d:%02d" % [now.year, now.month, now.day, now.hour, now.minute]

	var data := {
		"slot_id": slot_id,
		"exists": true,
		"seed": seed_val,
		"world_name": world_name,
		"created_at": now_str,
		"last_played": now_str,
		"version": 2,
		# Voxel state - starts empty
		"placed_blocks": {},     # {"x,y,z": type}
		"removed_blocks": {},    # {"x,y,z": true}
		"torch_attachments": {}, # {"x,y,z": "x,y,z" attach dir encoded}
		# Player & inventory
		"player_position": null, # [x,y,z] or null = use spawn
		"inventory": null,
		"playtime_seconds": 0,
		# Day-night cycle - save time of day so world doesn't reset to 6am
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
	ensure_save_dir()
	var path = get_slot_path(slot_id)
	if not FileAccess.file_exists(path):
		return true
	var err = DirAccess.remove_absolute(path)
	if err != OK:
		push_error("[SaveManager] Failed to delete slot %d" % slot_id)
		return false
	return true

# --- Instance methods for active game session saving ---

static func serialize_vector3i_dict(dict: Dictionary) -> Dictionary:
	# dict: Vector3i -> variant  =>  String -> variant for JSON
	var out := {}
	for k in dict.keys():
		var key_str: String
		if k is Vector3i:
			key_str = "%d,%d,%d" % [k.x, k.y, k.z]
		else:
			key_str = str(k)
		var v = dict[k]
		# also encode Vector3i values (torch attach)
		if v is Vector3i:
			out[key_str] = "%d,%d,%d" % [v.x, v.y, v.z]
		else:
			out[key_str] = v
	return out

static func deserialize_vector3i_dict_to_placed(dict: Dictionary) -> Dictionary:
	# {"x,y,z": int} -> {Vector3i: int}
	var out := {}
	for k in dict.keys():
		var parts = k.split(",")
		if parts.size() != 3:
			continue
		var pos = Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		out[pos] = int(dict[k])
	return out

static func deserialize_vector3i_dict_to_removed(dict: Dictionary) -> Dictionary:
	# {"x,y,z": true} -> {Vector3i: true}
	var out := {}
	for k in dict.keys():
		var parts = k.split(",")
		if parts.size() != 3:
			continue
		var pos = Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		out[pos] = true
	return out

static func deserialize_torch_dict(dict: Dictionary) -> Dictionary:
	# {"x,y,z": "ax,ay,az"} -> {Vector3i: Vector3i}
	var out := {}
	for k in dict.keys():
		var kp = k.split(",")
		if kp.size() != 3:
			continue
		var pos = Vector3i(int(kp[0]), int(kp[1]), int(kp[2]))
		var v_str = dict[k] as String
		var vp = v_str.split(",")
		if vp.size() != 3:
			continue
		var attach = Vector3i(int(vp[0]), int(vp[1]), int(vp[2]))
		out[pos] = attach
	return out

static func load_slot(slot_id: int) -> Dictionary:
	var info = get_slot_info(slot_id)
	if not info.get("exists", false):
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
	if not info.has("time_of_day"):
		info["time_of_day"] = 6.0
	if not info.has("playtime_seconds"):
		info["playtime_seconds"] = 0
	return info

static func save_world_state(slot_id: int, voxel_model: VoxelWorld, player: PlayerMotor = null, inventory: InventoryModel = null, extra_seconds: float = 0, time_of_day: float = -1.0) -> bool:
	ensure_save_dir()
	var existing = get_slot_info(slot_id)
	if not existing.get("exists", false):
		push_warning("[SaveManager] save_world_state called on non-existent slot %d, creating fallback" % slot_id)
		existing = create_new_world(slot_id)

	var now = Time.get_datetime_dict_from_system()
	var now_str = "%04d-%02d-%02d %02d:%02d" % [now.year, now.month, now.day, now.hour, now.minute]
	existing["last_played"] = now_str
	existing["playtime_seconds"] = float(existing.get("playtime_seconds", 0)) + extra_seconds

	if voxel_model:
		existing["placed_blocks"] = serialize_vector3i_dict(voxel_model.placed_blocks)
		existing["removed_blocks"] = serialize_vector3i_dict(voxel_model.removed_blocks)
		existing["torch_attachments"] = serialize_vector3i_dict(voxel_model.torch_attachments)

	if player:
		var p = player.global_position
		existing["player_position"] = [p.x, p.y, p.z]

	if inventory:
		existing["inventory"] = inventory.to_dict()

	# Save time of day - crucial so worlds don't reset to 6am
	if time_of_day >= 0.0:
		existing["time_of_day"] = fmod(time_of_day, 24.0)

	return _save_dict_to_file(slot_id, existing)

static func touch_last_played(slot_id: int) -> void:
	var info = get_slot_info(slot_id)
	if not info.get("exists", false):
		return
	var now = Time.get_datetime_dict_from_system()
	var now_str = "%04d-%02d-%02d %02d:%02d" % [now.year, now.month, now.day, now.hour, now.minute]
	info["last_played"] = now_str
	_save_dict_to_file(slot_id, info)
