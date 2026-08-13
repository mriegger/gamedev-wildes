extends Resource
class_name ActorStatsDefinition

@export_range(1, 999, 1, "or_greater") var starting_level: int = 1
@export_range(0, 999999999, 1, "or_greater") var starting_experience: int = 0
@export_range(1, 999999999, 1, "or_greater") var base_experience_to_level: int = 100
@export_range(0, 999999999, 1, "or_greater") var experience_increase_per_level: int = 25
@export_range(0, 999, 1, "or_greater") var maximum_level: int = 0

func validate() -> bool:
	var valid := starting_level >= 1 and starting_experience >= 0
	valid = valid and base_experience_to_level > 0 and experience_increase_per_level >= 0
	valid = valid and (maximum_level == 0 or starting_level <= maximum_level)
	if maximum_level > 0 and starting_level == maximum_level:
		valid = valid and starting_experience == 0
	else:
		valid = valid and starting_experience < get_experience_requirement(starting_level)
	var base_stats := get_base_stats()
	if not valid or base_stats.is_empty():
		return false
	for stat_id in base_stats:
		if typeof(stat_id) != TYPE_STRING_NAME or StringName(stat_id).is_empty():
			return false
		var value = base_stats[stat_id]
		if (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) or not is_finite(float(value)) or float(value) < 0.0:
			return false
	return true

func get_experience_requirement(for_level: int) -> int:
	assert(for_level >= 1)
	return maxi(1, base_experience_to_level + experience_increase_per_level * (for_level - 1))

func has_stat(stat_id: StringName) -> bool:
	return get_base_stats().has(stat_id)

func get_base_stats() -> Dictionary:
	return {}
