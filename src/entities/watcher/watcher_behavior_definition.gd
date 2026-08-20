extends EntityBehaviorDefinition
class_name WatcherBehaviorDefinition

@export_range(0.1, 12.0, 0.1) var wander_speed: float = 1.6
@export_range(0.1, 12.0, 0.1) var stalk_speed: float = 2.2
@export_range(0.1, 12.0, 0.1) var sprint_speed: float = 7.0
@export_range(0.0, 100.0, 0.1) var gravity: float = 30.0
@export_range(0.0, 20.0, 0.1) var jump_velocity: float = 7.0
@export_range(1.0, 64.0, 0.5) var detection_range: float = 16.0
@export_range(1.0, 96.0, 0.5) var forget_range: float = 24.0
@export_range(0.0, 15.0, 0.1) var target_memory_seconds: float = 3.0
@export_range(0.1, 12.0, 0.1) var stalk_inner_radius: float = 2.5
@export_range(0.1, 12.0, 0.1) var stalk_radius: float = 3.0
@export_range(0.1, 12.0, 0.1) var stalk_outer_radius: float = 3.5
@export_range(1.0, 180.0, 1.0) var stalk_step_degrees: float = 45.0
@export_range(0.1, 5.0, 0.1) var stalk_pause_seconds: float = 0.8
@export var melee_profile: MeleeAttackProfile
@export_range(1.0, 24.0, 0.5) var wander_radius: float = 8.0
@export_range(0.5, 15.0, 0.1) var wander_goal_seconds: float = 4.0
@export_range(0.1, 4.0, 0.05) var repath_seconds: float = 0.35

func validate(source: String) -> bool:
	var valid := true
	if (
		not is_finite(wander_speed)
		or wander_speed <= 0.0
		or not is_finite(stalk_speed)
		or stalk_speed < wander_speed
		or not is_finite(sprint_speed)
		or sprint_speed < stalk_speed
	):
		push_error("[WatcherBehaviorDefinition] Invalid movement speeds at %s" % source)
		valid = false
	if not is_finite(gravity) or gravity <= 0.0 or not is_finite(jump_velocity) or jump_velocity <= 0.0:
		push_error("[WatcherBehaviorDefinition] Invalid vertical movement at %s" % source)
		valid = false
	if melee_profile == null or not melee_profile.validate(source):
		push_error("[WatcherBehaviorDefinition] Invalid melee profile at %s" % source)
		valid = false
	elif (
		not is_finite(detection_range)
		or detection_range <= melee_profile.reach
		or not is_finite(forget_range)
		or forget_range < detection_range
		or not is_finite(target_memory_seconds)
		or target_memory_seconds < 0.0
	):
		push_error("[WatcherBehaviorDefinition] Invalid perception ranges at %s" % source)
		valid = false
	if (
		not is_finite(stalk_inner_radius)
		or stalk_inner_radius <= 0.0
		or not is_finite(stalk_radius)
		or stalk_inner_radius >= stalk_radius
		or not is_finite(stalk_outer_radius)
		or stalk_radius >= stalk_outer_radius
	):
		push_error("[WatcherBehaviorDefinition] Invalid stalking band at %s" % source)
		valid = false
	if (
		not is_finite(stalk_step_degrees)
		or stalk_step_degrees <= 0.0
		or stalk_step_degrees > 180.0
		or not is_finite(stalk_pause_seconds)
		or stalk_pause_seconds <= 0.0
	):
		push_error("[WatcherBehaviorDefinition] Invalid stalking cadence at %s" % source)
		valid = false
	if (
		not is_finite(wander_radius)
		or wander_radius <= 0.0
		or not is_finite(wander_goal_seconds)
		or wander_goal_seconds <= 0.0
		or not is_finite(repath_seconds)
		or repath_seconds <= 0.0
	):
		push_error("[WatcherBehaviorDefinition] Invalid navigation timing at %s" % source)
		valid = false
	return valid
