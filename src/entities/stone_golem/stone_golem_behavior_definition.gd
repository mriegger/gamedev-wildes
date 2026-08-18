extends EntityBehaviorDefinition
class_name StoneGolemBehaviorDefinition

const DEFAULT_PUNCH_PROFILE: MeleeAttackProfile = preload("res://combat/profiles/stone_golem_punch.tres")

@export_range(0.1, 12.0, 0.1) var movement_speed: float = 1.2
@export_range(0.1, 100.0, 0.1) var gravity: float = 30.0
@export_range(0.1, 20.0, 0.1) var jump_velocity: float = 7.0
@export_range(1.0, 64.0, 0.5) var detection_range: float = 16.0
@export_range(1.0, 96.0, 0.5) var forget_range: float = 24.0
@export_range(0.1, 10.0, 0.1) var target_memory_seconds: float = 3.0
@export_range(0.1, 4.0, 0.05) var repath_seconds: float = 0.5
@export var punch_profile: MeleeAttackProfile = DEFAULT_PUNCH_PROFILE

static func is_valid_movement(speed: float, jump: float, repath: float) -> bool:
	return is_finite(speed) and is_finite(jump) and is_finite(repath) and speed > 0.0 and jump > 0.0 and repath > 0.0

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
	if not is_valid_movement(movement_speed, jump_velocity, repath_seconds):
		push_error("[StoneGolemBehaviorDefinition] Invalid movement at %s" % source)
		valid = false
	if not is_valid_gravity(gravity):
		push_error("[StoneGolemBehaviorDefinition] Invalid gravity at %s" % source)
		valid = false
	if not is_valid_awareness(detection_range, forget_range, target_memory_seconds):
		push_error("[StoneGolemBehaviorDefinition] Invalid awareness at %s" % source)
		valid = false
	if punch_profile == null or not punch_profile.validate(source):
		push_error("[StoneGolemBehaviorDefinition] Invalid punch profile at %s" % source)
		valid = false
	return valid
