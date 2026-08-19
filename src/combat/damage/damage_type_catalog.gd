extends Resource
class_name DamageTypeCatalog

@export var definitions: Array[DamageTypeDefinition]:
	set(value):
		definitions = value
		_rebuild_lookup()

var _definitions_by_id: Dictionary[StringName, DamageTypeDefinition] = {}
var _is_valid: bool = false

func _rebuild_lookup() -> void:
	_definitions_by_id.clear()
	_is_valid = true
	for definition in definitions:
		if definition == null or not definition.validate(resource_path):
			_is_valid = false
			continue
		if _definitions_by_id.has(definition.id):
			push_error("[DamageTypeCatalog] Duplicate damage type %s" % definition.id)
			_is_valid = false
			continue
		_definitions_by_id[definition.id] = definition

func _ensure_lookup() -> void:
	if _definitions_by_id.size() != definitions.size():
		_rebuild_lookup()

func validate() -> bool:
	_ensure_lookup()
	return _is_valid and not definitions.is_empty()

func has_definition(definition: DamageTypeDefinition) -> bool:
	if definition == null:
		return false
	_ensure_lookup()
	return _definitions_by_id.get(definition.id) == definition
