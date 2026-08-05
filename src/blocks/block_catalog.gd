extends Resource
class_name BlockCatalog

const DEFS_PATH: String = "res://blocks/defs"

var _definitions: Array[BlockDefinition] = []

func _init():
	_definitions.resize(BlockId.Type.COUNT)
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
				elif _definitions[def.id] != null:
					push_error(
						"[BlockCatalog] Duplicate BlockId %s at %s" % [def.id, full_path]
					)
				else:
					_definitions[def.id] = def
		fname = dir.get_next()
	dir.list_dir_end()
	_ensure_air_fallback()
	for i in range(BlockId.Type.COUNT):
		if _definitions[i] == null:
			push_error(
				"[BlockCatalog] Missing block for BlockId %d, falling back to AIR" % i
			)
			var air_def = _definitions[BlockId.Type.AIR]
			if air_def != null:
				_definitions[i] = air_def

func _ensure_air_fallback() -> void:
	if _definitions[BlockId.Type.AIR] != null:
		return
	push_error("[BlockCatalog] Missing AIR definition, creating fallback")
	var fallback = BlockDefinition.new()
	fallback.id = BlockId.Type.AIR
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
	_definitions[BlockId.Type.AIR] = fallback

func get_definition(id: int) -> BlockDefinition:
	if BlockId.is_valid(id):
		return _definitions[id]
	return _definitions[BlockId.Type.AIR]

func get_side_color(id: int) -> Color:
	return get_definition(id).side_color

func is_solid(id: int) -> bool:
	return id != BlockId.Type.AIR and get_definition(id).is_solid

func is_opaque(id: int) -> bool:
	return id != BlockId.Type.AIR and get_definition(id).is_opaque

func is_raycast_solid(id: int) -> bool:
	return id != BlockId.Type.AIR and get_definition(id).is_raycast_solid

func is_breakable(id: int) -> bool:
	return id != BlockId.Type.AIR and get_definition(id).is_breakable

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
