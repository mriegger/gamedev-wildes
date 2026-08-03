extends RefCounted
class_name BlockCatalog

const DEFS_PATH: String = "res://blocks/defs"

static var _shared: BlockCatalog = null

var definitions: Dictionary = {}
var _by_string_id: Dictionary = {}

func _init():
	definitions = {}
	_by_string_id = {}
	_scan_definitions()

func _scan_definitions() -> void:
	var dir = DirAccess.open(DEFS_PATH)
	if dir == null:
		push_error("[BlockCatalog] Failed to open block defs directory: %s" % DEFS_PATH)
		_ensure_air_fallback()
		return
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var full_path = DEFS_PATH.path_join(fname)
			var res = ResourceLoader.load(full_path)
			if res == null:
				push_error("[BlockCatalog] Failed to load block definition: %s" % full_path)
			elif not (res is BlockDefinition):
				push_error("[BlockCatalog] Resource at %s is not a BlockDefinition" % full_path)
			else:
				var def = res as BlockDefinition
				if not BlockId.is_valid(def.id):
					push_error(
						"[BlockCatalog] Malformed at %s: invalid BlockId %s" % [full_path, def.id]
					)
				elif def.string_id == "":
					push_error(
						"[BlockCatalog] Malformed at %s: empty string_id" % full_path
					)
				elif definitions.has(def.id):
					push_error(
						"[BlockCatalog] Duplicate BlockId %s at %s" % [def.id, full_path]
					)
				elif _by_string_id.has(def.string_id):
					push_error(
						"[BlockCatalog] Duplicate string_id '%s' at %s"
						% [def.string_id, full_path]
					)
				else:
					definitions[def.id] = def
					_by_string_id[def.string_id] = def
		fname = dir.get_next()
	dir.list_dir_end()
	_ensure_air_fallback()
	for i in range(BlockId.Type.COUNT):
		if not definitions.has(i):
			push_error(
				"[BlockCatalog] Missing block for BlockId %d, falling back to AIR" % i
			)
			var air_def = definitions.get(BlockId.Type.AIR) as BlockDefinition
			if air_def != null:
				definitions[i] = air_def

func _ensure_air_fallback() -> void:
	if definitions.has(BlockId.Type.AIR):
		return
	push_error("[BlockCatalog] Missing AIR definition, creating fallback")
	var fallback = BlockDefinition.new()
	fallback.id = BlockId.Type.AIR
	fallback.string_id = "air"
	fallback.is_solid = false
	fallback.is_opaque = false
	fallback.is_raycast_solid = false
	fallback.is_breakable = false
	fallback.is_replaceable = true
	fallback.top_color = Color(0, 0, 0, 0)
	fallback.side_color = Color(0, 0, 0, 0)
	fallback.emissive_enabled = false
	fallback.emissive_color = Color(0, 0, 0, 0)
	fallback.emissive_energy = 0.0
	fallback.light_range = 0.0
	fallback.light_color = Color(1, 1, 1)
	definitions[BlockId.Type.AIR] = fallback
	_by_string_id["air"] = fallback

func get_definition(id: int) -> BlockDefinition:
	var def = definitions.get(id, null)
	if def != null:
		return def as BlockDefinition
	return definitions.get(BlockId.Type.AIR) as BlockDefinition

func get_definition_by_string_id(sid: String) -> BlockDefinition:
	var def = _by_string_id.get(sid, null)
	if def != null:
		return def as BlockDefinition
	return definitions.get(BlockId.Type.AIR) as BlockDefinition

func get_by_string_id(sid: String) -> BlockDefinition:
	return get_definition_by_string_id(sid)

func get_string_id(id: int) -> String:
	var def = definitions.get(id, null) as BlockDefinition
	if def != null:
		return def.string_id
	return ""

func get_block_id_for_string_id(sid: String) -> int:
	var def = _by_string_id.get(sid, null) as BlockDefinition
	if def != null:
		return def.id
	return BlockId.Type.AIR

func has_string_id(sid: String) -> bool:
	return _by_string_id.has(sid)

func get_side_color(id: int) -> Color:
	var def = get_definition(id)
	return def.side_color if def else Color(1, 0, 1)

func is_solid(id: int) -> bool:
	if id == BlockId.Type.AIR:
		return false
	var def = get_definition(id)
	return def.is_solid if def else false

func is_opaque(id: int) -> bool:
	if id == BlockId.Type.AIR:
		return false
	var def = get_definition(id)
	return def.is_opaque if def else false

func is_raycast_solid(id: int) -> bool:
	if id == BlockId.Type.AIR:
		return false
	var def = get_definition(id)
	return def.is_raycast_solid if def else false

func is_breakable(id: int) -> bool:
	if id == BlockId.Type.AIR:
		return false
	var def = get_definition(id)
	return def.is_breakable if def else false

static func column_block_at(top_t: int, h: int, y: int) -> int:
	if top_t == BlockId.Type.SAND:
		return BlockId.Type.SAND
	if top_t == BlockId.Type.STONE:
		return BlockId.Type.STONE
	if top_t == BlockId.Type.GRASS:
		if y == h:
			return BlockId.Type.GRASS
		if y >= h - 2:
			return BlockId.Type.DIRT
		return BlockId.Type.STONE
	if top_t == BlockId.Type.DIRT:
		return BlockId.Type.DIRT
	return top_t

static func shared() -> BlockCatalog:
	if _shared == null:
		_shared = BlockCatalog.new()
	return _shared
