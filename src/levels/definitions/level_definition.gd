extends Resource
class_name LevelDefinition

const FORMAT_VERSION: int = 4
const HARD_MAX_EXPLORED_STATES: int = 10000
const HARD_MAX_MODULE_COUNT: int = 64

@export var format_version: int = 0
@export var level_id: StringName
@export var presentation: LevelPresentationDefinition
@export var start_module_id: StringName
@export var hallway_module_ids: Array[StringName] = []
@export var room_requirements: Array[LevelRoomRequirement] = []
@export var one_time_chest_reward: LevelOneTimeChestRewardDefinition
@export var maximum_extent: Vector3i = LevelGeometryLimits.HARD_MAX_EXTENT
@export_range(1, HARD_MAX_EXPLORED_STATES) var maximum_explored_states: int = HARD_MAX_EXPLORED_STATES

func validate() -> bool:
	var valid := true
	var source := resource_path
	if source.is_empty():
		source = String(level_id)
	if format_version != FORMAT_VERSION:
		push_error("[LevelDefinition] Unsupported format version %d for %s" % [format_version, source])
		valid = false
	if level_id.is_empty():
		push_error("[LevelDefinition] Empty level ID at %s" % source)
		valid = false
	if presentation == null or not presentation.validate(source):
		push_error("[LevelDefinition] Invalid presentation for %s" % source)
		valid = false
	if start_module_id.is_empty():
		push_error("[LevelDefinition] Empty start module ID for %s" % source)
		valid = false
	if room_requirements.is_empty():
		push_error("[LevelDefinition] Room requirements are required for %s" % source)
		valid = false
	if maximum_extent.x <= 0 or maximum_extent.y <= 0 or maximum_extent.z <= 0 or maximum_extent.x > LevelGeometryLimits.HARD_MAX_EXTENT.x or maximum_extent.y > LevelGeometryLimits.HARD_MAX_EXTENT.y or maximum_extent.z > LevelGeometryLimits.HARD_MAX_EXTENT.z:
		push_error("[LevelDefinition] Invalid maximum extent for %s" % source)
		valid = false
	if maximum_explored_states <= 0 or maximum_explored_states > HARD_MAX_EXPLORED_STATES:
		push_error("[LevelDefinition] Invalid search bound for %s" % source)
		valid = false
	var assigned_module_ids: Dictionary = {start_module_id: "start"}
	valid = _validate_module_pool(hallway_module_ids, "hallway", assigned_module_ids, source) and valid
	var room_type_ids: Dictionary = {}
	var has_chest_room := false
	for requirement in room_requirements:
		if requirement == null:
			push_error("[LevelDefinition] Null room requirement for %s" % source)
			valid = false
			continue
		valid = requirement.validate(source) and valid
		if room_type_ids.has(requirement.room_type_id):
			push_error("[LevelDefinition] Duplicate room type %s for %s" % [requirement.room_type_id, source])
			valid = false
		room_type_ids[requirement.room_type_id] = true
		has_chest_room = requirement.chest_loot_bundle != null or has_chest_room
		valid = _validate_module_pool(requirement.module_ids, "room", assigned_module_ids, source) and valid
	if one_time_chest_reward != null:
		valid = one_time_chest_reward.validate(source) and valid
		if not has_chest_room:
			push_error("[LevelDefinition] One-time chest reward requires a chest-bearing room for %s" % source)
			valid = false
	return valid

func get_room_count() -> int:
	var total := 0
	for requirement in room_requirements:
		if requirement != null:
			total += requirement.count
	return total

func get_hallway_count(start_socket_count: int) -> int:
	return get_room_count() - start_socket_count

func get_target_module_count(start_socket_count: int) -> int:
	return 1 + get_room_count() + get_hallway_count(start_socket_count)

func _validate_module_pool(module_ids: Array[StringName], label: String, assigned_module_ids: Dictionary, source: String) -> bool:
	var valid := true
	for module_id in module_ids:
		if module_id.is_empty() or assigned_module_ids.has(module_id):
			push_error("[LevelDefinition] Empty, duplicate, or conflicting %s module ID for %s" % [label, source])
			valid = false
		assigned_module_ids[module_id] = label
	return valid
