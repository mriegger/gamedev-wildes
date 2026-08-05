extends Resource
class_name BlockCatalog

@export var definitions: Array[BlockDefinition]:
	set(value):
		definitions = value
		_rebuild_lookup()

var _definitions_by_id: Array[BlockDefinition] = []

func _rebuild_lookup() -> void:
	_definitions_by_id.clear()
	_definitions_by_id.resize(BlockId.Type.COUNT)
	for definition in definitions:
		if definition == null:
			push_error("[BlockCatalog] Null block definition")
			continue
		var source := definition.resource_path
		if not BlockId.is_valid(definition.id):
			push_error("[BlockCatalog] Invalid BlockId %s at %s" % [definition.id, source])
			continue
		if _definitions_by_id[definition.id] != null:
			push_error("[BlockCatalog] Duplicate BlockId %s at %s" % [definition.id, source])
			continue
		_definitions_by_id[definition.id] = definition
	for id in range(BlockId.Type.COUNT):
		if _definitions_by_id[id] == null:
			push_error("[BlockCatalog] Missing block for BlockId %d" % id)

func _ensure_lookup() -> void:
	if _definitions_by_id.size() != BlockId.Type.COUNT:
		_rebuild_lookup()

func get_definition(id: int) -> BlockDefinition:
	_ensure_lookup()
	assert(BlockId.is_valid(id))
	assert(_definitions_by_id[id] != null)
	return _definitions_by_id[id]

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
