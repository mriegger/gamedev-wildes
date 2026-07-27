extends RefCounted
class_name BlockCatalog

## BlockCatalog - cached block definitions, single source for appearance and physical rules
## Consolidates BlockId, BlockDefinition duplicates from mesher, torch renderer, hotbar, targeting view
## Avoids constructing BlockDefinition during visual updates

var definitions: Dictionary = {} # BlockId.Type -> BlockDefinition, cached

func _init():
	definitions = BlockDefinition.create_all()

func get_definition(id: int) -> BlockDefinition:
	if definitions.has(id):
		return definitions[id] as BlockDefinition
	if BlockId.is_valid(id):
		# fallback create if not cached (should not happen)
		var def = BlockDefinition.new(id as BlockId.Type)
		definitions[id] = def
		return def
	return definitions.get(BlockId.Type.AIR) as BlockDefinition

func get_side_color(id: int) -> Color:
	var def = get_definition(id)
	return def.side_color if def else Color(1, 0, 1)

func get_top_color(id: int) -> Color:
	var def = get_definition(id)
	return def.top_color if def else Color(1, 0, 1)

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

func is_occupying(id: int) -> bool:
	if id == BlockId.Type.AIR:
		return false
	var def = get_definition(id)
	return def.is_occupying if def else false

func is_occupied(id: int) -> bool:
	# Canonical: any occupying block is occupied (includes torch), AIR not
	return is_occupying(id)

func is_breakable(id: int) -> bool:
	if id == BlockId.Type.AIR:
		return false
	var def = get_definition(id)
	return def.is_breakable if def else false

func get_display_name(id: int) -> String:
	return BlockId.get_display_name(id as BlockId.Type)

static var _shared: BlockCatalog = null
static func shared() -> BlockCatalog:
	if _shared == null:
		_shared = BlockCatalog.new()
	return _shared
