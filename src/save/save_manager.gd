extends RefCounted
class_name SaveManager

const SAVE_DIR: String = "user://saves"
const SLOT_COUNT: int = 3
const CURRENT_SAVE_VERSION: int = 16
const MINIMUM_MIGRATABLE_SAVE_VERSION: int = 4
const VERSION_SEVEN_BASE_EXPERIENCE_TO_LEVEL: int = 100
const VERSION_SEVEN_EXPERIENCE_GROWTH: float = 1.25
const VERSION_EIGHT_BASE_EXPERIENCE_TO_LEVEL: int = 100
const VERSION_EIGHT_EXPERIENCE_INCREASE_PER_LEVEL: int = 25
const VERSION_ELEVEN_MAXIMUM_DURABILITY: int = 1000000
const PERSISTED_CHEST_SLOT_COUNT: int = 15
const VERSION_TEN_AFFIX_ROLLS: Dictionary = {
	&"vicious": [
		{
			"stat_id": "strength",
			"operation": StatModifier.Operation.ADD,
			"amount": 2.0,
		},
	],
	&"stout": [
		{
			"stat_id": "defense",
			"operation": StatModifier.Operation.ADD,
			"amount": 2.0,
		},
	],
}

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
	for part in parts:
		if not part.is_valid_int():
			return null
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))

static func _encode_vector3i(value: Vector3i) -> String:
	return "%d,%d,%d" % [value.x, value.y, value.z]

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
	return parsed

static func get_all_slots(item_catalog: ItemCatalog) -> Array:
	assert(item_catalog != null)
	var out: Array = []
	for i in range(SLOT_COUNT):
		out.append(load_slot(i, item_catalog))
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
		"emplacements": {},
		"chests": {},
		"player_position": null,
		"player_stats": null,
		"player_perks": {"allocations": {}},
		"item_proficiency": {},
		"tutorial_progress": TutorialProgress.new().snapshot(),
		"inventory": null,
		"next_equipment_instance_id": 1,
		"world_loot": {
			"next_entry_id": 1,
			"entries": [],
		},
		"dungeon_progress": DungeonProgressState.new().snapshot(),
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

static func _deserialize_block_ids(dict: Dictionary) -> Variant:
	var out := {}
	for key in dict:
		if not key is String:
			return null
		var pos = _try_parse_vector3i(key)
		var encoded_block_id = dict[key]
		if (
			pos == null
			or (typeof(encoded_block_id) != TYPE_INT and typeof(encoded_block_id) != TYPE_FLOAT)
			or not is_finite(float(encoded_block_id))
			or float(encoded_block_id) != float(int(encoded_block_id))
		):
			return null
		var block_id := int(encoded_block_id)
		if not BlockId.is_valid(block_id) or block_id == BlockId.Type.AIR:
			return null
		out[pos] = block_id
	return out

static func _deserialize_removed_blocks(dict: Dictionary) -> Variant:
	var out := {}
	for key in dict:
		if not key is String or dict[key] != true:
			return null
		var pos = _try_parse_vector3i(key)
		if pos == null:
			return null
		out[pos] = true
	return out

static func _deserialize_torch_attachments(dict: Dictionary) -> Variant:
	var out := {}
	for key in dict:
		if not key is String or not dict[key] is String:
			return null
		var pos = _try_parse_vector3i(key)
		var attach_dir = _try_parse_vector3i(dict[key])
		if pos == null or attach_dir == null or attach_dir not in TorchPlacement.CARDINAL_DIRECTIONS:
			return null
		out[pos] = attach_dir
	return out

static func decode_world_state(data: Dictionary) -> Variant:
	var encoded_seed = data.get("seed", null)
	var placed_raw = data.get("placed_blocks", null)
	var removed_raw = data.get("removed_blocks", null)
	var torch_raw = data.get("torch_attachments", null)
	var emplacements_raw = data.get("emplacements", null)
	if (
		typeof(encoded_seed) != TYPE_INT
		or int(encoded_seed) < 1
		or not placed_raw is Dictionary
		or not removed_raw is Dictionary
		or not torch_raw is Dictionary
		or not emplacements_raw is Dictionary
	):
		return null
	var placed = _deserialize_block_ids(placed_raw)
	var removed = _deserialize_removed_blocks(removed_raw)
	var torch_attachments = _deserialize_torch_attachments(torch_raw)
	var emplacements = _deserialize_block_ids(emplacements_raw)
	if placed == null or removed == null or torch_attachments == null or emplacements == null:
		return null
	for position in placed:
		if removed.has(position):
			return null
	for position in torch_attachments:
		if int(placed.get(position, BlockId.Type.AIR)) != BlockId.Type.TORCH:
			return null
	for position in placed:
		if int(placed[position]) == BlockId.Type.TORCH and not torch_attachments.has(position):
			return null
	var position = Vector3.ZERO
	var position_data = data.get("player_position", null)
	if position_data != null:
		if not position_data is Array or position_data.size() != 3:
			return null
		for component in position_data:
			if (typeof(component) != TYPE_INT and typeof(component) != TYPE_FLOAT) or not is_finite(float(component)):
				return null
		position = Vector3(float(position_data[0]), float(position_data[1]), float(position_data[2]))
	return WorldState.new(
		int(encoded_seed),
		placed,
		removed,
		torch_attachments,
		emplacements,
		position
	)

static func _index_chest_slots(encoded_chests: Dictionary) -> Variant:
	var slots_by_position: Dictionary = {}
	for encoded_position in encoded_chests:
		if (
			not encoded_position is String
			or not encoded_chests[encoded_position] is Array
			or (encoded_chests[encoded_position] as Array).size() != PERSISTED_CHEST_SLOT_COUNT
		):
			return null
		var position = _try_parse_vector3i(encoded_position)
		if position == null or _encode_vector3i(position) != encoded_position or slots_by_position.has(position):
			return null
		slots_by_position[position] = encoded_chests[encoded_position]
	return slots_by_position

static func decode_chest_state(data: Dictionary) -> Variant:
	if not data.has("chests") or not data["chests"] is Dictionary:
		return null
	var indexed = _index_chest_slots(data["chests"])
	if indexed == null:
		return null
	var decoded: Dictionary = {}
	for position in indexed:
		decoded[position] = (indexed[position] as Array).duplicate(true)
	return decoded

static func load_slot(slot_id: int, item_catalog: ItemCatalog) -> Dictionary:
	assert(item_catalog != null)
	var info = get_slot_info(slot_id)
	if not info.get("exists", false):
		return info
	if not _migrate_save_data(info, item_catalog):
		info["incompatible"] = true
		return info
	info["next_equipment_instance_id"] = int(info["next_equipment_instance_id"])
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
	if not info.has("emplacements"):
		info["emplacements"] = {}
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
	if not info.has("apple_trees"):
		info["apple_trees"] = AppleTreeState.new().snapshot()
	if not info.has("tutorial_progress"):
		var removed_blocks = info.get("removed_blocks", {})
		info["tutorial_progress"] = {
			"mining_tip_completed": removed_blocks is Dictionary and not (removed_blocks as Dictionary).is_empty(),
		}
	return info

static func _migrate_save_data(data: Dictionary, item_catalog: ItemCatalog) -> bool:
	if item_catalog == null or not data.has("version") or not _is_integer_number(data["version"]):
		return false
	var migrated := data.duplicate(true)
	var version := int(migrated["version"])
	if version < MINIMUM_MIGRATABLE_SAVE_VERSION or version > CURRENT_SAVE_VERSION:
		return false
	var source_version := version
	migrated["version"] = version
	if migrated.has("seed"):
		if not _is_integer_number(migrated["seed"]) or int(migrated["seed"]) < 1:
			return false
		migrated["seed"] = int(migrated["seed"])
	while version < CURRENT_SAVE_VERSION:
		match version:
			4:
				if migrated.has("item_proficiency"):
					return false
				migrated["item_proficiency"] = {}
				version = 5
			5:
				if not _migrate_inventory_socket_data(migrated):
					return false
				version = 6
			6:
				if migrated.has("pumpkin_patch"):
					return false
				migrated["pumpkin_patch"] = {"present": false}
				version = 7
			7:
				if not _migrate_player_progression_data(migrated):
					return false
				if migrated.has("chest_inventories"):
					return false
				migrated["chest_inventories"] = {}
				version = 8
			8:
				if migrated.has("apple_trees"):
					return false
				migrated["apple_trees"] = AppleTreeState.new().snapshot()
				version = 9
			9:
				if not _migrate_chest_inventory_data(migrated):
					return false
				if not _migrate_equipment_variant_data(migrated):
					return false
				version = 10
			10:
				if not _migrate_equipment_instance_data(migrated, item_catalog):
					return false
				version = 11
			11:
				if not _migrate_version_eleven_equipment_instances(migrated):
					return false
				version = 12
			12:
				if migrated.has("world_loot"):
					return false
				migrated["world_loot"] = {
					"next_entry_id": 1,
					"entries": [],
				}
				version = 13
			13:
				if migrated.has("emplacements"):
					return false
				migrated["emplacements"] = {}
				version = 14
			14:
				if migrated.has("dungeon_progress"):
					return false
				migrated["dungeon_progress"] = DungeonProgressState.new().snapshot()
				version = 15
			15:
				if migrated.has("tutorial_progress"):
					return false
				var removed_blocks: Variant = migrated.get("removed_blocks", {})
				if not removed_blocks is Dictionary:
					return false
				migrated["tutorial_progress"] = {
					"mining_tip_completed": not (removed_blocks as Dictionary).is_empty(),
				}
				version = 16
			_:
				return false
		migrated["version"] = version
	if source_version < CURRENT_SAVE_VERSION and not _synthesize_missing_chest_storage(migrated):
		return false
	if not _validate_dungeon_progress(migrated):
		return false
	if not _validate_equipment_instance_identity(migrated, item_catalog):
		return false
	data.clear()
	data.merge(migrated, true)
	return true

static func _validate_dungeon_progress(data: Dictionary) -> bool:
	if not data.has("dungeon_progress"):
		return false
	var progress := DungeonProgressState.new()
	return progress.restore(data["dungeon_progress"])

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
				encoded_stack.size() != 2
				or not encoded_stack.has("item_id")
				or not encoded_stack.has("count")
				or encoded_stack.has("socketed_rune_ids")
			):
				return false
			encoded_stack["socketed_rune_ids"] = []
	return true

static func _migrate_chest_inventory_data(data: Dictionary) -> bool:
	if data.has("chests"):
		return false
	var encoded_chest_inventories = data.get("chest_inventories", null)
	if not encoded_chest_inventories is Dictionary:
		return false
	var encoded_chests: Dictionary = {}
	var indexed_positions: Dictionary = {}
	for encoded_position in encoded_chest_inventories:
		if not encoded_position is String:
			return false
		var position = _try_parse_vector3i(encoded_position)
		if position == null or _encode_vector3i(position) != encoded_position or indexed_positions.has(position):
			return false
		var encoded_inventory = encoded_chest_inventories[encoded_position]
		if not encoded_inventory is Dictionary or (encoded_inventory as Dictionary).size() != 2:
			return false
		if not encoded_inventory.has("size") or not encoded_inventory.has("slots"):
			return false
		var raw_size = encoded_inventory["size"]
		var encoded_slots = encoded_inventory["slots"]
		if (
			(typeof(raw_size) != TYPE_INT and typeof(raw_size) != TYPE_FLOAT)
			or not is_finite(float(raw_size))
			or float(raw_size) != float(int(raw_size))
			or int(raw_size) != PERSISTED_CHEST_SLOT_COUNT
			or not encoded_slots is Array
			or (encoded_slots as Array).size() != PERSISTED_CHEST_SLOT_COUNT
		):
			return false
		indexed_positions[position] = true
		encoded_chests[encoded_position] = (encoded_slots as Array).duplicate(true)
	data.erase("chest_inventories")
	data["chests"] = encoded_chests
	return true

static func _synthesize_missing_chest_storage(data: Dictionary) -> bool:
	var encoded_chests = data.get("chests", null)
	if not encoded_chests is Dictionary:
		return false
	var placed_blocks = data.get("placed_blocks", {})
	if not placed_blocks is Dictionary:
		return false
	for encoded_position in placed_blocks:
		if not encoded_position is String:
			return false
		var position = _try_parse_vector3i(encoded_position)
		var raw_block_id = placed_blocks[encoded_position]
		if (
			position == null
			or _encode_vector3i(position) != encoded_position
			or not _is_integer_number(raw_block_id)
		):
			return false
		var block_id := int(raw_block_id)
		if not BlockId.is_valid(block_id) or block_id == BlockId.Type.AIR:
			return false
		if block_id != BlockId.Type.CHEST or encoded_chests.has(encoded_position):
			continue
		var slots: Array = []
		slots.resize(PERSISTED_CHEST_SLOT_COUNT)
		slots.fill(null)
		encoded_chests[encoded_position] = slots
	return true

static func _migrate_equipment_variant_data(data: Dictionary) -> bool:
	var inventory = data.get("inventory", null)
	if inventory != null:
		if not inventory is Dictionary:
			return false
		var regions = (inventory as Dictionary).get("regions", null)
		if not regions is Dictionary:
			return false
		for region_name in ["hotbar", "backpack", "equipment"]:
			var encoded_region = (regions as Dictionary).get(region_name, null)
			if not encoded_region is Array:
				return false
			if not _add_empty_equipment_variant_ids(encoded_region as Array):
				return false
	var chests = data.get("chests", null)
	if not chests is Dictionary:
		return false
	for encoded_slots in chests.values():
		if not encoded_slots is Array:
			return false
		if not _add_empty_equipment_variant_ids(encoded_slots as Array):
			return false
	return true

static func _add_empty_equipment_variant_ids(encoded_stacks: Array) -> bool:
	for raw_stack in encoded_stacks:
		if raw_stack == null:
			continue
		if not raw_stack is Dictionary:
			return false
		var encoded_stack := raw_stack as Dictionary
		if (
			encoded_stack.size() != 3
			or not encoded_stack.has("item_id")
			or not encoded_stack.has("count")
			or not encoded_stack.has("socketed_rune_ids")
			or encoded_stack.has("equipment_variant_id")
		):
			return false
		encoded_stack["equipment_variant_id"] = ""
	return true

static func _migrate_equipment_instance_data(data: Dictionary, item_catalog: ItemCatalog) -> bool:
	if data.has("next_equipment_instance_id"):
		return false
	var allocation := {"next_instance_id": 1}
	var inventory = data.get("inventory", null)
	if inventory != null:
		if not inventory is Dictionary:
			return false
		var regions = (inventory as Dictionary).get("regions", null)
		if not regions is Dictionary:
			return false
		for region_name in ["hotbar", "backpack", "equipment"]:
			var encoded_region = (regions as Dictionary).get(region_name, null)
			if not encoded_region is Array:
				return false
			if not _migrate_equipment_instance_stacks(encoded_region as Array, item_catalog, allocation):
				return false
	var chests = data.get("chests", null)
	if not chests is Dictionary:
		return false
	var encoded_slots_by_position = _index_chest_slots(chests)
	if encoded_slots_by_position == null:
		return false
	var positions: Array[Vector3i] = []
	positions.assign(encoded_slots_by_position.keys())
	positions.sort_custom(_is_position_before)
	for position in positions:
		if not _migrate_equipment_instance_stacks(encoded_slots_by_position[position], item_catalog, allocation):
			return false
	data["next_equipment_instance_id"] = int(allocation["next_instance_id"])
	return true

static func _migrate_equipment_instance_stacks(
	encoded_stacks: Array,
	item_catalog: ItemCatalog,
	allocation: Dictionary,
) -> bool:
	for raw_stack in encoded_stacks:
		if raw_stack == null:
			continue
		if not raw_stack is Dictionary:
			return false
		var encoded_stack := raw_stack as Dictionary
		if (
			encoded_stack.size() != 4
			or not encoded_stack.has("item_id")
			or not encoded_stack.has("count")
			or not encoded_stack.has("socketed_rune_ids")
			or not encoded_stack.has("equipment_variant_id")
			or (typeof(encoded_stack["item_id"]) != TYPE_STRING and typeof(encoded_stack["item_id"]) != TYPE_STRING_NAME)
			or (typeof(encoded_stack["count"]) != TYPE_INT and typeof(encoded_stack["count"]) != TYPE_FLOAT)
			or not encoded_stack["socketed_rune_ids"] is Array
			or (typeof(encoded_stack["equipment_variant_id"]) != TYPE_STRING and typeof(encoded_stack["equipment_variant_id"]) != TYPE_STRING_NAME)
		):
			return false
		var item_id := StringName(encoded_stack["item_id"])
		if item_id.is_empty() or not item_catalog.has_definition(item_id):
			return false
		var count := int(encoded_stack["count"])
		if not is_finite(float(encoded_stack["count"])) or float(encoded_stack["count"]) != float(count) or count < 1:
			return false
		var definition := item_catalog.get_definition(item_id)
		var rune_ids: Array[StringName] = []
		for raw_rune_id in encoded_stack["socketed_rune_ids"] as Array:
			if typeof(raw_rune_id) != TYPE_STRING and typeof(raw_rune_id) != TYPE_STRING_NAME:
				return false
			rune_ids.append(StringName(raw_rune_id))
		var affix_id := StringName(encoded_stack["equipment_variant_id"])
		if definition.equipment_type == null:
			if not rune_ids.is_empty() or not affix_id.is_empty():
				return false
			encoded_stack["equipment_instance"] = null
		else:
			if count != 1 or not item_catalog.is_valid_persisted_socket_loadout(rune_ids):
				return false
			var encoded_affixes: Array = []
			if not affix_id.is_empty():
				if not item_catalog.has_equipment_affix(affix_id):
					return false
				if not VERSION_TEN_AFFIX_ROLLS.has(affix_id):
					return false
				var encoded_rolls: Array = (VERSION_TEN_AFFIX_ROLLS[affix_id] as Array).duplicate(true)
				encoded_affixes.append({
					"affix_id": String(affix_id),
					"stat_rolls": encoded_rolls,
				})
			var encoded_rune_ids: Array[String] = []
			for rune_id in rune_ids:
				encoded_rune_ids.append(String(rune_id))
			encoded_stack["equipment_instance"] = {
				"instance_id": int(allocation["next_instance_id"]),
				"affixes": encoded_affixes,
				"socketed_rune_ids": encoded_rune_ids,
			}
			allocation["next_instance_id"] = int(allocation["next_instance_id"]) + 1
		encoded_stack.erase("socketed_rune_ids")
		encoded_stack.erase("equipment_variant_id")
	return true

static func _migrate_version_eleven_equipment_instances(data: Dictionary) -> bool:
	var inventory = data.get("inventory", null)
	if inventory != null:
		if not inventory is Dictionary:
			return false
		var regions = (inventory as Dictionary).get("regions", null)
		if not regions is Dictionary:
			return false
		for region_name in ["hotbar", "backpack", "equipment"]:
			var encoded_region = (regions as Dictionary).get(region_name, null)
			if not encoded_region is Array or not _migrate_version_eleven_equipment_instance_stacks(encoded_region):
				return false
	var chests = data.get("chests", null)
	if not chests is Dictionary:
		return false
	for encoded_slots in chests.values():
		if not encoded_slots is Array or not _migrate_version_eleven_equipment_instance_stacks(encoded_slots):
			return false
	return true

static func _migrate_version_eleven_equipment_instance_stacks(encoded_stacks: Array) -> bool:
	for raw_stack in encoded_stacks:
		if raw_stack == null:
			continue
		if not raw_stack is Dictionary or (raw_stack as Dictionary).size() != 3:
			return false
		var encoded_stack := raw_stack as Dictionary
		if not encoded_stack.has("item_id") or not encoded_stack.has("count") or not encoded_stack.has("equipment_instance"):
			return false
		var raw_instance = encoded_stack["equipment_instance"]
		if raw_instance == null:
			continue
		if not raw_instance is Dictionary:
			return false
		var encoded_instance := raw_instance as Dictionary
		if (
			(encoded_instance.size() != 3 and encoded_instance.size() != 5)
			or not encoded_instance.has("instance_id")
			or not encoded_instance.has("affixes")
			or not encoded_instance.has("socketed_rune_ids")
		):
			return false
		if encoded_instance.size() == 5:
			if (
				not encoded_instance.has("current_durability")
				or not encoded_instance.has("maximum_durability")
				or not _is_integer_number(encoded_instance["current_durability"])
				or not _is_integer_number(encoded_instance["maximum_durability"])
			):
				return false
			var current_durability := int(encoded_instance["current_durability"])
			var maximum_durability := int(encoded_instance["maximum_durability"])
			if (
				maximum_durability < 1
				or maximum_durability > VERSION_ELEVEN_MAXIMUM_DURABILITY
				or current_durability < 0
				or current_durability > maximum_durability
			):
				return false
		encoded_stack["equipment_instance"] = {
			"instance_id": encoded_instance["instance_id"],
			"affixes": encoded_instance["affixes"],
			"socketed_rune_ids": encoded_instance["socketed_rune_ids"],
		}
	return true

static func _validate_equipment_instance_identity(data: Dictionary, item_catalog: ItemCatalog) -> bool:
	if data.has("chest_inventories"):
		return false
	var raw_next_instance_id = data.get("next_equipment_instance_id", null)
	if (
		(typeof(raw_next_instance_id) != TYPE_INT and typeof(raw_next_instance_id) != TYPE_FLOAT)
		or not is_finite(float(raw_next_instance_id))
		or float(raw_next_instance_id) != float(int(raw_next_instance_id))
	):
		return false
	var next_instance_id := int(raw_next_instance_id)
	if next_instance_id < 1 or next_instance_id > EquipmentInstanceFactory.MAXIMUM_NEXT_INSTANCE_ID:
		return false
	var factory := EquipmentInstanceFactory.new(item_catalog, next_instance_id)
	var instance_ids: Array[int] = []
	var inventory = data.get("inventory", null)
	if inventory != null:
		if not inventory is Dictionary:
			return false
		var regions = (inventory as Dictionary).get("regions", null)
		if not regions is Dictionary:
			return false
		for region_name in ["hotbar", "backpack", "equipment"]:
			var encoded_region = (regions as Dictionary).get(region_name, null)
			if not encoded_region is Array or not _validate_encoded_instance_stacks(encoded_region, factory, instance_ids):
				return false
	var chests = data.get("chests", null)
	if not chests is Dictionary:
		return false
	var encoded_slots_by_position = _index_chest_slots(chests)
	if encoded_slots_by_position == null:
		return false
	for encoded_slots in encoded_slots_by_position.values():
		if not encoded_slots is Array or not _validate_encoded_instance_stacks(encoded_slots, factory, instance_ids):
			return false
	var reserved_instance_ids: Dictionary = {}
	for instance_id in instance_ids:
		if reserved_instance_ids.has(instance_id):
			return false
		reserved_instance_ids[instance_id] = true
	var encoded_world_loot = data.get("world_loot", null)
	if not encoded_world_loot is Dictionary:
		return false
	var world_loot_state := WorldLootState.new(item_catalog, factory)
	if not world_loot_state.restore(encoded_world_loot, reserved_instance_ids):
		return false
	instance_ids.append_array(world_loot_state.get_equipment_instance_ids())
	return factory.can_restore_state(next_instance_id, instance_ids)

static func _validate_encoded_instance_stacks(
	encoded_stacks: Array,
	factory: EquipmentInstanceFactory,
	instance_ids: Array[int],
) -> bool:
	for raw_stack in encoded_stacks:
		if raw_stack == null:
			continue
		if not raw_stack is Dictionary or (raw_stack as Dictionary).size() != 3:
			return false
		var stack := InventoryStack.from_dict(raw_stack)
		if stack == null:
			return false
		if not factory.item_catalog.has_definition(stack.item_id):
			if stack.equipment_instance != null:
				instance_ids.append(stack.equipment_instance.instance_id)
			continue
		var definition := factory.item_catalog.get_definition(stack.item_id)
		if stack.count < 1 or stack.count > definition.max_stack:
			return false
		if definition.equipment_type == null:
			if stack.equipment_instance != null:
				return false
		elif stack.count != 1 or not factory.is_valid_instance(stack.item_id, stack.equipment_instance):
			return false
		else:
			instance_ids.append(stack.equipment_instance.instance_id)
	return true

static func _is_position_before(left: Vector3i, right: Vector3i) -> bool:
	if left.x != right.x:
		return left.x < right.x
	if left.y != right.y:
		return left.y < right.y
	return left.z < right.z

static func save_world_state(
	slot_id: int,
	current_data: Dictionary,
	voxel_model: VoxelWorld,
	persisted_player_position: Vector3,
	player_stats: ActorStats,
	inventory: InventoryModel,
	equipment_instance_factory: EquipmentInstanceFactory,
	player_perks: PlayerPerks,
	item_proficiency: ItemProficiency,
	chest_storage: ChestStorage,
	world_loot_state: WorldLootState,
	dungeon_progress: DungeonProgressState,
	pumpkin_patch: Dictionary,
	apple_trees: Dictionary,
	extra_seconds: float,
	time_of_day: float,
) -> bool:
	assert(player_perks != null)
	assert(item_proficiency != null)
	assert(equipment_instance_factory != null)
	assert(inventory.equipment_instance_factory == equipment_instance_factory)
	assert(chest_storage != null)
	assert(world_loot_state != null)
	assert(dungeon_progress != null)
	assert(world_loot_state.item_catalog == equipment_instance_factory.item_catalog)
	assert(world_loot_state.equipment_instance_factory == equipment_instance_factory)
	if not chest_storage._uses_configuration(
		equipment_instance_factory.item_catalog,
		equipment_instance_factory,
		PERSISTED_CHEST_SLOT_COUNT,
	):
		return false
	var block_edits := voxel_model.snapshot_block_edits()
	var chest_snapshot := chest_storage.snapshot()
	if not _is_chest_state_consistent(block_edits["placed"], chest_snapshot):
		return false
	var equipment_instance_ids := inventory.get_equipment_instance_ids()
	equipment_instance_ids.append_array(chest_storage.get_equipment_instance_ids())
	equipment_instance_ids.append_array(world_loot_state.get_equipment_instance_ids())
	if not equipment_instance_factory.can_restore_state(
		equipment_instance_factory.get_next_instance_id(),
		equipment_instance_ids,
	):
		return false
	var updated = current_data.duplicate()
	updated["last_played"] = _now_str()
	updated["version"] = CURRENT_SAVE_VERSION
	updated["playtime_seconds"] = float(updated.get("playtime_seconds", 0)) + extra_seconds

	updated["placed_blocks"] = serialize_vector3i_dict(block_edits["placed"])
	updated["removed_blocks"] = serialize_vector3i_dict(block_edits["removed"])
	updated["torch_attachments"] = serialize_vector3i_dict(voxel_model.torch_attachments)
	updated["emplacements"] = serialize_vector3i_dict(voxel_model.snapshot_emplacements())
	updated["chests"] = serialize_vector3i_dict(chest_snapshot)
	updated.erase("chest_inventories")
	updated.erase("copper_blocks")
	updated.erase("generated_copper_chunks")
	var p = persisted_player_position
	updated["player_position"] = [p.x, p.y, p.z]
	updated["player_stats"] = player_stats.snapshot_progression()
	updated["player_perks"] = player_perks.snapshot()
	updated["inventory"] = inventory.to_dict()
	updated["next_equipment_instance_id"] = equipment_instance_factory.get_next_instance_id()
	updated["world_loot"] = world_loot_state.snapshot()
	updated["dungeon_progress"] = dungeon_progress.snapshot()
	updated["item_proficiency"] = item_proficiency.snapshot()
	updated["pumpkin_patch"] = pumpkin_patch.duplicate(true)
	updated["apple_trees"] = apple_trees.duplicate(true)
	updated["time_of_day"] = fmod(time_of_day, GameClock.HOURS_PER_DAY)

	if not _save_dict_to_file(slot_id, updated):
		return false
	current_data.clear()
	current_data.merge(updated, true)
	return true

static func _is_chest_state_consistent(placed_blocks: Dictionary, chest_snapshot: Dictionary) -> bool:
	for position in chest_snapshot:
		if int(placed_blocks.get(position, BlockId.Type.AIR)) != BlockId.Type.CHEST:
			return false
	for position in placed_blocks:
		if int(placed_blocks[position]) == BlockId.Type.CHEST and not chest_snapshot.has(position):
			return false
	return true

static func update_last_played(slot_id: int, data: Dictionary) -> bool:
	var updated = data.duplicate()
	updated["last_played"] = _now_str()
	if not _save_dict_to_file(slot_id, updated):
		return false
	data.clear()
	data.merge(updated, true)
	return true
