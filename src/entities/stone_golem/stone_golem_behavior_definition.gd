extends EntityBehaviorDefinition
class_name StoneGolemBehaviorDefinition

@export_range(0.1, 100.0, 0.1) var gravity: float = 30.0
@export_range(1.0, 64.0, 0.5) var detection_range: float = 16.0
@export_range(1.0, 96.0, 0.5) var forget_range: float = 24.0
@export_range(0.1, 10.0, 0.1) var target_memory_seconds: float = 3.0

static func is_valid_gravity(value: float) -> bool:
	return is_finite(value) and value > 0.0

static func is_valid_awareness(detection: float, forget: float, memory_seconds: float) -> bool:
	return (
		is_finite(detection)
		and is_finite(forget)
		and is_finite(memory_seconds)
		and detection > 0.0
		and forget >= detection
		and memory_seconds > 0.0
	)

func validate(source: String) -> bool:
	var valid := true
	if not is_valid_gravity(gravity):
		push_error("[StoneGolemBehaviorDefinition] Invalid gravity at %s" % source)
		valid = false
	if not is_valid_awareness(detection_range, forget_range, target_memory_seconds):
		push_error("[StoneGolemBehaviorDefinition] Invalid awareness at %s" % source)
		valid = false
	return valid
