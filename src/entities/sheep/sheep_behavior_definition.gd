extends EntityBehaviorDefinition
class_name SheepBehaviorDefinition

@export_range(0.1, 12.0, 0.1) var wander_speed: float = 1.2
@export_range(0.1, 12.0, 0.1) var flee_speed: float = 3.6
@export_range(0.0, 100.0, 0.1) var gravity: float = 30.0
@export_range(0.0, 20.0, 0.1) var jump_velocity: float = 7.0
@export_range(1.0, 24.0, 0.5) var wander_radius: float = 6.0
@export_range(0.5, 15.0, 0.1) var wander_goal_seconds: float = 3.0
@export_range(0.1, 15.0, 0.1) var idle_seconds: float = 2.0
@export_range(0.1, 15.0, 0.1) var flee_seconds: float = 4.0
@export_range(1.0, 24.0, 0.5) var flee_goal_distance: float = 10.0
@export_range(0.1, 4.0, 0.05) var repath_seconds: float = 0.5

func validate(source: String) -> bool:
	var valid := true
	if wander_speed <= 0.0 or flee_speed < wander_speed:
		push_error("[SheepBehaviorDefinition] Invalid movement speeds at %s" % source)
		valid = false
	if gravity <= 0.0 or jump_velocity <= 0.0:
		push_error("[SheepBehaviorDefinition] Invalid vertical movement at %s" % source)
		valid = false
	if wander_radius <= 0.0 or wander_goal_seconds <= 0.0 or idle_seconds <= 0.0:
		push_error("[SheepBehaviorDefinition] Invalid idle or wander timing at %s" % source)
		valid = false
	if flee_seconds <= 0.0 or flee_goal_distance <= 0.0:
		push_error("[SheepBehaviorDefinition] Invalid flee behavior at %s" % source)
		valid = false
	if repath_seconds <= 0.0:
		push_error("[SheepBehaviorDefinition] Invalid navigation timing at %s" % source)
		valid = false
	return valid
