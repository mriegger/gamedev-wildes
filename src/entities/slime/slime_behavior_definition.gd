extends EntityBehaviorDefinition
class_name SlimeBehaviorDefinition

@export_range(0.1, 12.0, 0.1) var wander_speed: float = 1.3
@export_range(0.1, 12.0, 0.1) var chase_speed: float = 2.6
@export_range(0.0, 100.0, 0.1) var gravity: float = 30.0
@export_range(0.0, 20.0, 0.1) var jump_velocity: float = 7.0
@export_range(1.0, 64.0, 0.5) var detection_range: float = 16.0
@export_range(1.0, 96.0, 0.5) var forget_range: float = 24.0
@export_range(0.0, 15.0, 0.1) var target_memory_seconds: float = 3.0
@export_range(1.0, 24.0, 0.5) var wander_radius: float = 8.0
@export_range(0.5, 15.0, 0.1) var wander_goal_seconds: float = 4.0
@export_range(0.1, 4.0, 0.05) var repath_seconds: float = 0.5
@export_range(0.1, 4.0, 0.05) var hop_interval_seconds: float = 0.9
@export_range(0.0, 0.95, 0.01) var attachment_slow_fraction: float = 0.4
@export var attachment_damage_profile: MeleeAttackProfile

func validate(source: String) -> bool:
	var valid := true
	if not is_finite(wander_speed) or wander_speed <= 0.0 or not is_finite(chase_speed) or chase_speed <= wander_speed:
		push_error("[SlimeBehaviorDefinition] Invalid movement speeds at %s" % source)
		valid = false
	if not is_finite(gravity) or gravity <= 0.0 or not is_finite(jump_velocity) or jump_velocity <= 0.0 or not is_finite(hop_interval_seconds) or hop_interval_seconds <= 0.0:
		push_error("[SlimeBehaviorDefinition] Invalid hop movement at %s" % source)
		valid = false
	if not is_finite(detection_range) or detection_range <= 0.0 or not is_finite(forget_range) or forget_range < detection_range or not is_finite(target_memory_seconds) or target_memory_seconds < 0.0:
		push_error("[SlimeBehaviorDefinition] Invalid perception at %s" % source)
		valid = false
	if not is_finite(wander_radius) or wander_radius <= 0.0 or not is_finite(wander_goal_seconds) or wander_goal_seconds <= 0.0 or not is_finite(repath_seconds) or repath_seconds <= 0.0:
		push_error("[SlimeBehaviorDefinition] Invalid wandering at %s" % source)
		valid = false
	if not is_finite(attachment_slow_fraction) or attachment_slow_fraction <= 0.0 or attachment_slow_fraction >= 1.0:
		push_error("[SlimeBehaviorDefinition] Invalid attachment slow fraction at %s" % source)
		valid = false
	if attachment_damage_profile == null or not attachment_damage_profile.validate(source):
		push_error("[SlimeBehaviorDefinition] Invalid attachment damage profile at %s" % source)
		valid = false
	return valid
