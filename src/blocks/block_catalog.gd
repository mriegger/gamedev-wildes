extends RefCounted
class_name BlockCatalog

var definitions: Dictionary = {}

func _init():
	definitions = BlockDefinition.create_all()

func get_definition(id: int) -> BlockDefinition:
	if definitions.has(id):
		return definitions[id] as BlockDefinition
	if BlockId.is_valid(id):
		var def = BlockDefinition.new(id as BlockId.Type)
		definitions[id] = def
		return def
	return definitions.get(BlockId.Type.AIR) as BlockDefinition

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
		elif y >= h - 2:
			return BlockId.Type.DIRT
		else:
			return BlockId.Type.STONE
	if top_t == BlockId.Type.DIRT:
		return BlockId.Type.DIRT
	return top_t

static var _shared: BlockCatalog = null
static func shared() -> BlockCatalog:
	if _shared == null:
		_shared = BlockCatalog.new()
	return _shared
