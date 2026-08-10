extends Resource
class_name EntityCatalog

@export var definitions: Array[EntityDefinition]:
	set(value):
		definitions = value
		_rebuild_lookup()

var _definitions_by_id: Dictionary = {}
var _is_valid: bool = false

func _rebuild_lookup():
	_definitions_by_id.clear()
	_is_valid = true
	for definition in definitions:
		if definition == null:
			push_error("[EntityCatalog] Null entity definition")
			_is_valid = false
			continue
		var source := definition.resource_path
		if definition.id.is_empty():
			push_error("[EntityCatalog] Empty entity ID at %s" % source)
			_is_valid = false
			continue
		if _definitions_by_id.has(definition.id):
			push_error("[EntityCatalog] Duplicate entity ID %s at %s" % [definition.id, source])
			_is_valid = false
			continue
		_definitions_by_id[definition.id] = definition
		_is_valid = definition.validate(source) and _is_valid

func _ensure_lookup():
	if _definitions_by_id.size() != definitions.size():
		_rebuild_lookup()

func validate() -> bool:
	_ensure_lookup()
	return _is_valid

func has_definition(id: StringName) -> bool:
	_ensure_lookup()
	return _definitions_by_id.has(id)

func get_definition(id: StringName) -> EntityDefinition:
	_ensure_lookup()
	assert(_definitions_by_id.has(id))
	return _definitions_by_id[id] as EntityDefinition
