extends Resource
class_name LevelRoomRequirement

@export var room_type_id: StringName
@export_range(1, 64, 1) var count: int = 1
@export var module_ids: Array[StringName] = []
@export var encounter: LevelRoomEncounterDefinition

func validate(source: String) -> bool:
	var valid := true
	if room_type_id.is_empty():
		push_error("[LevelRoomRequirement] Empty room type ID for %s" % source)
		valid = false
	if count <= 0 or count > 64:
		push_error("[LevelRoomRequirement] Invalid room count for %s in %s" % [room_type_id, source])
		valid = false
	if module_ids.is_empty():
		push_error("[LevelRoomRequirement] Empty module pool for %s in %s" % [room_type_id, source])
		valid = false
	if encounter == null or not encounter.validate("%s room type %s" % [source, room_type_id]):
		push_error("[LevelRoomRequirement] Invalid encounter for %s in %s" % [room_type_id, source])
		valid = false
	var seen: Dictionary = {}
	for module_id in module_ids:
		if module_id.is_empty() or seen.has(module_id):
			push_error("[LevelRoomRequirement] Empty or duplicate module ID for %s in %s" % [room_type_id, source])
			valid = false
		seen[module_id] = true
	return valid
