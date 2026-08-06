extends Resource
class_name ItemCatalog

@export var definitions: Array[ItemDefinition]:
	set(value):
		definitions = value
		_rebuild_lookup()

var _definitions_by_id: Dictionary = {}
var _definitions_by_block: Array[ItemDefinition] = []
var _is_valid: bool = false

func _rebuild_lookup() -> void:
	_definitions_by_id.clear()
	_definitions_by_block.clear()
	_definitions_by_block.resize(BlockId.Type.COUNT)
	_is_valid = true
	for definition in definitions:
		if definition == null:
			push_error("[ItemCatalog] Null item definition")
			_is_valid = false
			continue
		var source := definition.resource_path
		if definition.id.is_empty():
			push_error("[ItemCatalog] Empty item ID at %s" % source)
			_is_valid = false
			continue
		if _definitions_by_id.has(definition.id):
			push_error("[ItemCatalog] Duplicate item ID %s at %s" % [definition.id, source])
			_is_valid = false
			continue
		if definition.icon == null:
			push_error("[ItemCatalog] Missing icon for %s at %s" % [definition.id, source])
			_is_valid = false
		if definition.max_stack < 1:
			push_error("[ItemCatalog] Invalid max stack for %s at %s" % [definition.id, source])
			_is_valid = false
		_definitions_by_id[definition.id] = definition
		if definition.placed_block == null:
			continue
		var block_id := int(definition.placed_block.id)
		if not BlockId.is_valid(block_id) or block_id == BlockId.Type.AIR:
			push_error("[ItemCatalog] Invalid placed block for %s at %s" % [definition.id, source])
			_is_valid = false
			continue
		if _definitions_by_block[block_id] != null:
			push_error("[ItemCatalog] Duplicate block mapping for %s at %s" % [BlockId.get_display_name(block_id), source])
			_is_valid = false
			continue
		_definitions_by_block[block_id] = definition

func _ensure_lookup() -> void:
	if _definitions_by_block.size() != BlockId.Type.COUNT:
		_rebuild_lookup()

func validate(block_catalog: BlockCatalog) -> bool:
	_ensure_lookup()
	var valid := _is_valid
	for definition in definitions:
		if definition == null or definition.placed_block == null:
			continue
		var block_id := int(definition.placed_block.id)
		if not BlockId.is_valid(block_id):
			continue
		if block_catalog.get_definition(block_id) != definition.placed_block:
			push_error("[ItemCatalog] Non-canonical block resource for %s" % definition.id)
			valid = false
	return valid

func has_definition(id: StringName) -> bool:
	_ensure_lookup()
	return _definitions_by_id.has(id)

func get_definition(id: StringName) -> ItemDefinition:
	_ensure_lookup()
	assert(_definitions_by_id.has(id))
	return _definitions_by_id[id] as ItemDefinition

func get_item_for_block(block_id: int) -> ItemDefinition:
	_ensure_lookup()
	assert(BlockId.is_valid(block_id))
	assert(_definitions_by_block[block_id] != null)
	return _definitions_by_block[block_id]
