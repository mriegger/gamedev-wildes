extends EntityBehaviorDefinition
class_name StoneGolemBehaviorDefinition

@export_range(0.1, 100.0, 0.1) var gravity: float = 30.0

static func is_valid_gravity(value: float) -> bool:
	return is_finite(value) and value > 0.0

func validate(source: String) -> bool:
	var valid := true
	if not is_valid_gravity(gravity):
		push_error("[StoneGolemBehaviorDefinition] Invalid gravity at %s" % source)
		valid = false
	return valid
