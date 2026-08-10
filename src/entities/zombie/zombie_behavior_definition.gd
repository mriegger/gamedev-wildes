extends EntityBehaviorDefinition
class_name ZombieBehaviorDefinition

@export_range(0.1, 12.0, 0.1) var wander_speed: float = 1.6
@export_range(0.1, 12.0, 0.1) var chase_speed: float = 3.2
@export_range(0.0, 100.0, 0.1) var gravity: float = 30.0
@export_range(0.0, 20.0, 0.1) var jump_velocity: float = 7.0
@export_range(1.0, 64.0, 0.5) var detection_range: float = 16.0
@export_range(1.0, 96.0, 0.5) var forget_range: float = 24.0
@export_range(0.0, 15.0, 0.1) var target_memory_seconds: float = 3.0
@export_range(0.5, 4.0, 0.05) var attack_range: float = 1.4
@export_range(0.1, 4.0, 0.05) var attack_duration: float = 0.65
@export_range(0.1, 8.0, 0.05) var attack_cooldown: float = 1.2
@export_range(1.0, 24.0, 0.5) var wander_radius: float = 8.0
@export_range(0.5, 15.0, 0.1) var wander_goal_seconds: float = 4.0
@export_range(0.1, 4.0, 0.05) var repath_seconds: float = 0.5

func validate(source: String) -> bool:
	var valid := true
	if wander_speed <= 0.0 or chase_speed < wander_speed:
		push_error("[ZombieBehaviorDefinition] Invalid movement speeds at %s" % source)
		valid = false
	if gravity <= 0.0 or jump_velocity <= 0.0:
		push_error("[ZombieBehaviorDefinition] Invalid vertical movement at %s" % source)
		valid = false
	if detection_range <= attack_range or forget_range < detection_range:
		push_error("[ZombieBehaviorDefinition] Invalid perception ranges at %s" % source)
		valid = false
	if attack_duration <= 0.0 or attack_cooldown < attack_duration:
		push_error("[ZombieBehaviorDefinition] Invalid attack timing at %s" % source)
		valid = false
	if wander_radius <= 0.0 or wander_goal_seconds <= 0.0 or repath_seconds <= 0.0:
		push_error("[ZombieBehaviorDefinition] Invalid navigation timing at %s" % source)
		valid = false
	return valid
