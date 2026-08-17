extends Resource
class_name LevelEnemyGroupDefinition

const MAX_COUNT: int = 64

@export var entity_id: StringName
@export_range(1, MAX_COUNT, 1) var count: int = 1

func validate(source: String) -> bool:
	var valid := true
	if entity_id.is_empty():
		push_error("[LevelEnemyGroupDefinition] Empty entity ID for %s" % source)
		valid = false
	if count <= 0 or count > MAX_COUNT:
		push_error("[LevelEnemyGroupDefinition] Invalid count for %s in %s" % [entity_id, source])
		valid = false
	return valid
