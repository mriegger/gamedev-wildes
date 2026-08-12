extends Resource
class_name ProficiencyDefinition

@export var experience_requirements: PackedFloat64Array
@export var slot_unlock_levels: PackedInt32Array

var maximum_level: int:
	get:
		return experience_requirements.size()

func validate() -> bool:
	if experience_requirements.is_empty() or slot_unlock_levels.is_empty():
		return false
	for requirement in experience_requirements:
		if not is_finite(requirement) or requirement <= 0.0:
			return false
	var previous_unlock_level := -1
	for unlock_level in slot_unlock_levels:
		if unlock_level < 0 or unlock_level < previous_unlock_level or unlock_level > maximum_level:
			return false
		previous_unlock_level = unlock_level
	return true

func get_experience_requirement(level: int) -> float:
	assert(level >= 0 and level < maximum_level)
	return experience_requirements[level]

func get_unlocked_slot_count(level: int) -> int:
	assert(level >= 0 and level <= maximum_level)
	var unlocked := 0
	for unlock_level in slot_unlock_levels:
		if unlock_level > level:
			break
		unlocked += 1
	return unlocked
