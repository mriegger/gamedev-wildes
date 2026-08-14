extends Resource
class_name CraftingRecipeCatalog

@export var definitions: Array[CraftingRecipeDefinition]:
	set(value):
		definitions = value
		_rebuild_lookup()

var _definitions_by_id: Dictionary = {}
var _is_valid: bool = false

func _rebuild_lookup() -> void:
	_definitions_by_id.clear()
	_is_valid = true
	for definition in definitions:
		if definition == null:
			push_error("[CraftingRecipeCatalog] Null recipe definition")
			_is_valid = false
			continue
		if definition.id.is_empty() or _definitions_by_id.has(definition.id):
			push_error("[CraftingRecipeCatalog] Empty or duplicate recipe ID %s" % definition.id)
			_is_valid = false
			continue
		_definitions_by_id[definition.id] = definition

func validate(item_catalog: ItemCatalog) -> bool:
	_rebuild_lookup()
	var valid := _is_valid
	for definition in definitions:
		if definition != null:
			valid = definition.validate(item_catalog, definition.resource_path) and valid
	return valid

func has_definition(id: StringName) -> bool:
	return _definitions_by_id.has(id)

func get_definition(id: StringName) -> CraftingRecipeDefinition:
	assert(_definitions_by_id.has(id))
	return _definitions_by_id[id] as CraftingRecipeDefinition
