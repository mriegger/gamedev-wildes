extends Resource
class_name LevelDefinition

const HARD_MAX_EXTENT: Vector3i = Vector3i(96, 16, 96)
const HARD_MAX_EXPLORED_STATES: int = 10000
const HARD_MAX_MODULE_COUNT: int = 64

@export var level_id: StringName
@export var presentation: LevelPresentationDefinition
@export var start_module_id: StringName
@export var expansion_module_ids: Array[StringName] = []
@export var cap_module_ids: Array[StringName] = []
@export_range(1, 64) var minimum_module_count: int = 8
@export_range(1, 64) var maximum_module_count: int = 12
@export var maximum_extent: Vector3i = HARD_MAX_EXTENT
@export_range(1, HARD_MAX_EXPLORED_STATES) var maximum_explored_states: int = HARD_MAX_EXPLORED_STATES

func validate() -> bool:
	var valid := true
	var source := resource_path
	if source.is_empty():
		source = String(level_id)
	if level_id.is_empty():
		push_error("[LevelDefinition] Empty level ID at %s" % source)
		valid = false
	if presentation == null or not presentation.validate(source):
		push_error("[LevelDefinition] Invalid presentation for %s" % source)
		valid = false
	if start_module_id.is_empty():
		push_error("[LevelDefinition] Empty start module ID for %s" % source)
		valid = false
	if expansion_module_ids.is_empty() or cap_module_ids.is_empty():
		push_error("[LevelDefinition] Expansion and cap pools are required for %s" % source)
		valid = false
	if minimum_module_count < 1 or maximum_module_count < minimum_module_count or maximum_module_count > HARD_MAX_MODULE_COUNT:
		push_error("[LevelDefinition] Invalid module count range for %s" % source)
		valid = false
	if maximum_extent.x <= 0 or maximum_extent.y <= 0 or maximum_extent.z <= 0 or maximum_extent.x > HARD_MAX_EXTENT.x or maximum_extent.y > HARD_MAX_EXTENT.y or maximum_extent.z > HARD_MAX_EXTENT.z:
		push_error("[LevelDefinition] Invalid maximum extent for %s" % source)
		valid = false
	if maximum_explored_states <= 0 or maximum_explored_states > HARD_MAX_EXPLORED_STATES:
		push_error("[LevelDefinition] Invalid search bound for %s" % source)
		valid = false
	valid = _validate_pool(expansion_module_ids, "expansion", source) and valid
	valid = _validate_pool(cap_module_ids, "cap", source) and valid
	return valid

func _validate_pool(module_ids: Array[StringName], label: String, source: String) -> bool:
	var valid := true
	var seen: Dictionary = {}
	for module_id in module_ids:
		if module_id.is_empty() or seen.has(module_id):
			push_error("[LevelDefinition] Empty or duplicate %s module ID for %s" % [label, source])
			valid = false
		seen[module_id] = true
	return valid
