extends EntityBehaviorDefinition
class_name SkeletonBehaviorDefinition

@export_range(0.1, 12.0, 0.1) var roam_speed: float = 2.4
@export_range(0.1, 12.0, 0.1) var sprint_speed: float = 5.5
@export_range(0.0, 100.0, 0.1) var gravity: float = 30.0
@export_range(0.0, 20.0, 0.1) var jump_velocity: float = 7.0
@export_range(1.0, 64.0, 0.5) var detection_range: float = 30.0
@export_range(1.0, 64.0, 0.5) var roam_radius: float = 30.0
@export_range(0.5, 15.0, 0.1) var roam_goal_seconds: float = 4.0
@export_range(0.1, 4.0, 0.05) var repath_seconds: float = 0.5
@export_range(0.1, 4.0, 0.05) var cover_retry_seconds: float = 1.0
@export_range(0.025, 1.0, 0.025) var cover_revalidation_seconds: float = 0.125

func validate(source: String) -> bool:
	var valid := true
	if not is_finite(roam_speed) or roam_speed <= 0.0:
		push_error("[SkeletonBehaviorDefinition] Invalid roam speed at %s" % source)
		valid = false
	if not is_finite(sprint_speed) or sprint_speed <= roam_speed:
		push_error("[SkeletonBehaviorDefinition] Invalid sprint speed at %s" % source)
		valid = false
	if not is_finite(gravity) or gravity <= 0.0 or not is_finite(jump_velocity) or jump_velocity <= 0.0:
		push_error("[SkeletonBehaviorDefinition] Invalid vertical movement at %s" % source)
		valid = false
	if not is_finite(detection_range) or detection_range <= 0.0:
		push_error("[SkeletonBehaviorDefinition] Invalid detection range at %s" % source)
		valid = false
	if not is_finite(roam_radius) or roam_radius <= 0.0:
		push_error("[SkeletonBehaviorDefinition] Invalid roam radius at %s" % source)
		valid = false
	if not is_finite(roam_goal_seconds) or roam_goal_seconds <= 0.0 or not is_finite(repath_seconds) or repath_seconds <= 0.0:
		push_error("[SkeletonBehaviorDefinition] Invalid navigation timing at %s" % source)
		valid = false
	if not is_finite(cover_retry_seconds) or cover_retry_seconds <= 0.0:
		push_error("[SkeletonBehaviorDefinition] Invalid cover retry timing at %s" % source)
		valid = false
	if not is_finite(cover_revalidation_seconds) or cover_revalidation_seconds <= 0.0:
		push_error("[SkeletonBehaviorDefinition] Invalid cover revalidation timing at %s" % source)
		valid = false
	return valid
