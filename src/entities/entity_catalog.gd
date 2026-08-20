extends Resource
class_name EntityCatalog

@export var definitions: Array[EntityDefinition]:
	set(value):
		definitions = value
		_rebuild_lookup()

var _definitions_by_id: Dictionary = {}
var _maximum_lineage_capacity_by_id: Dictionary = {}
var _is_valid: bool = false

func _rebuild_lookup():
	_definitions_by_id.clear()
	_maximum_lineage_capacity_by_id.clear()
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
	_is_valid = _validate_defeat_spawns() and _is_valid
	if _is_valid:
		for definition in definitions:
			_maximum_lineage_capacity_by_id[definition.id] = _calculate_maximum_lineage_capacity(definition.id)

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

func get_maximum_lineage_capacity(id: StringName) -> int:
	_ensure_lookup()
	assert(_is_valid and _maximum_lineage_capacity_by_id.has(id))
	return int(_maximum_lineage_capacity_by_id[id])

func _validate_defeat_spawns() -> bool:
	var issue := _get_defeat_spawn_validation_issue(definitions)
	if issue.is_empty():
		return true
	push_error(issue)
	return false

static func _get_defeat_spawn_validation_issue(candidates: Array[EntityDefinition]) -> String:
	var definitions_by_id: Dictionary = {}
	for definition in candidates:
		if definition != null and not definition.id.is_empty() and not definitions_by_id.has(definition.id):
			definitions_by_id[definition.id] = definition
	for definition in candidates:
		if definition == null or definition.defeat_spawn == null:
			continue
		var child_id := definition.defeat_spawn.child_definition_id
		if not definitions_by_id.has(child_id):
			return "[EntityCatalog] Missing defeat-spawn child %s for %s" % [child_id, definition.id]
		var child := definitions_by_id[child_id] as EntityDefinition
		if child.body_width > definition.body_width or child.body_height > definition.body_height:
			return "[EntityCatalog] Defeat-spawn child %s is larger than %s" % [child_id, definition.id]
	var visit_states: Dictionary = {}
	for definition in candidates:
		if definition == null:
			continue
		var cycle_id := _find_defeat_spawn_cycle(definition.id, definitions_by_id, visit_states)
		if not cycle_id.is_empty():
			return "[EntityCatalog] Defeat-spawn cycle contains %s" % cycle_id
	return ""

static func _find_defeat_spawn_cycle(
	definition_id: StringName,
	definitions_by_id: Dictionary,
	visit_states: Dictionary,
) -> StringName:
	var state := int(visit_states.get(definition_id, 0))
	if state == 2:
		return &""
	if state == 1:
		return definition_id
	visit_states[definition_id] = 1
	var definition := definitions_by_id.get(definition_id) as EntityDefinition
	if definition != null and definition.defeat_spawn != null:
		var child_id := definition.defeat_spawn.child_definition_id
		if definitions_by_id.has(child_id):
			var cycle_id := _find_defeat_spawn_cycle(child_id, definitions_by_id, visit_states)
			if not cycle_id.is_empty():
				return cycle_id
	visit_states[definition_id] = 2
	return &""

func _calculate_maximum_lineage_capacity(definition_id: StringName) -> int:
	if _maximum_lineage_capacity_by_id.has(definition_id):
		return int(_maximum_lineage_capacity_by_id[definition_id])
	var definition := _definitions_by_id[definition_id] as EntityDefinition
	if definition.defeat_spawn == null:
		return 1
	var child_capacity := _calculate_maximum_lineage_capacity(definition.defeat_spawn.child_definition_id)
	var capacity := definition.defeat_spawn.maximum_count * child_capacity
	_maximum_lineage_capacity_by_id[definition_id] = capacity
	return capacity
