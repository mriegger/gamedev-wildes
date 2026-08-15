extends Resource
class_name LevelRoomEncounterDefinition

const MAX_ENEMY_COUNT: int = 64

@export var enemy_groups: Array[LevelEnemyGroupDefinition] = []

func validate(source: String) -> bool:
	var valid := true
	if enemy_groups.is_empty():
		push_error("[LevelRoomEncounterDefinition] Enemy groups are required for %s" % source)
		valid = false
	var entity_ids: Dictionary = {}
	var total_count := 0
	for group in enemy_groups:
		if group == null:
			push_error("[LevelRoomEncounterDefinition] Null enemy group for %s" % source)
			valid = false
			continue
		valid = group.validate(source) and valid
		if entity_ids.has(group.entity_id):
			push_error("[LevelRoomEncounterDefinition] Duplicate entity ID %s for %s" % [group.entity_id, source])
			valid = false
		entity_ids[group.entity_id] = true
		total_count += group.count
	if total_count > MAX_ENEMY_COUNT:
		push_error("[LevelRoomEncounterDefinition] Enemy count exceeds %d for %s" % [MAX_ENEMY_COUNT, source])
		valid = false
	return valid
