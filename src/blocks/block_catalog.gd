extends Resource
class_name BlockCatalog

@export var definitions: Array[BlockDefinition]:
	set(value):
		definitions = value
		_rebuild_lookup()

var _definitions_by_id: Array[BlockDefinition] = []
var _is_valid: bool = false

func _rebuild_lookup() -> void:
	_definitions_by_id.clear()
	_definitions_by_id.resize(BlockId.Type.COUNT)
	_is_valid = true
	for definition in definitions:
		if definition == null:
			push_error("[BlockCatalog] Null block definition")
			_is_valid = false
			continue
		var source := definition.resource_path
		if not BlockId.is_valid(definition.id):
			push_error("[BlockCatalog] Invalid BlockId %s at %s" % [definition.id, source])
			_is_valid = false
			continue
		if _definitions_by_id[definition.id] != null:
			push_error("[BlockCatalog] Duplicate BlockId %s at %s" % [definition.id, source])
			_is_valid = false
			continue
		_definitions_by_id[definition.id] = definition
		if definition.is_breakable and definition.mine_duration <= 0.0:
			push_error("[BlockCatalog] Invalid mine duration for %s" % BlockId.get_display_name(definition.id))
			_is_valid = false
		if definition.minimum_mining_power < 0:
			push_error("[BlockCatalog] Negative mining power for %s" % BlockId.get_display_name(definition.id))
			_is_valid = false
		if definition.minimum_mining_power > 0 and definition.mining_tool_tag.is_empty():
			push_error("[BlockCatalog] Missing mining tool tag for %s" % BlockId.get_display_name(definition.id))
			_is_valid = false
		if definition.crafting_station != null:
			_is_valid = definition.crafting_station.validate(source) and _is_valid
			if not definition.is_raycast_solid:
				push_error("[BlockCatalog] Crafting station must be targetable at %s" % source)
				_is_valid = false
		if definition.container != null:
			_is_valid = definition.container.validate(source) and _is_valid
			if not definition.is_raycast_solid or definition.is_breakable:
				push_error("[BlockCatalog] Container must be targetable and non-breakable at %s" % source)
				_is_valid = false
	for id in range(BlockId.Type.COUNT):
		var definition := _definitions_by_id[id]
		if definition == null:
			push_error("[BlockCatalog] Missing block for BlockId %d" % id)
			_is_valid = false
		elif BlockId.is_chunk_cube(id) or id == BlockId.Type.ANVIL or id == BlockId.Type.CHEST or id == BlockId.Type.CAULDRON:
			_validate_face_texture(definition.top_texture, "top", definition)
			_validate_face_texture(definition.side_texture, "side", definition)
			_validate_face_texture(definition.bottom_texture, "bottom", definition)

func _validate_face_texture(texture: Texture2D, face: String, definition: BlockDefinition) -> void:
	if texture == null:
		push_error("[BlockCatalog] Missing %s texture for %s" % [face, BlockId.get_display_name(definition.id)])
		_is_valid = false
		return
	if texture.get_width() != 16 or texture.get_height() != 16:
		push_error("[BlockCatalog] %s texture for %s must be 16x16" % [face, BlockId.get_display_name(definition.id)])
		_is_valid = false

func _ensure_lookup() -> void:
	if _definitions_by_id.size() != BlockId.Type.COUNT:
		_rebuild_lookup()

func validate() -> bool:
	_ensure_lookup()
	return _is_valid

func get_definition(id: int) -> BlockDefinition:
	_ensure_lookup()
	assert(BlockId.is_valid(id))
	assert(_definitions_by_id[id] != null)
	return _definitions_by_id[id]

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
