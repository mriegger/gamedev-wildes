extends Resource
class_name ActorStatsDefinition

@export_range(1, 999, 1, "or_greater") var starting_level: int = 1
@export_range(0, 999999999, 1, "or_greater") var starting_experience: int = 0
@export_range(1, 999999999, 1, "or_greater") var base_experience_to_level: int = 100
@export_range(1.0, 10.0, 0.01, "or_greater") var experience_growth: float = 1.25
@export_range(0, 999, 1, "or_greater") var maximum_level: int = 0

func validate() -> bool:
	var valid := starting_level >= 1 and starting_experience >= 0
	valid = valid and base_experience_to_level > 0 and experience_growth >= 1.0
	valid = valid and (maximum_level == 0 or starting_level <= maximum_level)
	if maximum_level > 0 and starting_level == maximum_level:
		valid = valid and starting_experience == 0
	else:
		valid = valid and starting_experience < get_experience_requirement(starting_level)
	return valid and not get_base_stats().is_empty()

func get_experience_requirement(for_level: int) -> int:
	return maxi(1, int(round(float(base_experience_to_level) * pow(experience_growth, for_level - 1))))

func has_stat(stat_id: StringName) -> bool:
	return get_base_stats().has(stat_id)

func get_base_stats() -> Dictionary:
	return {}
