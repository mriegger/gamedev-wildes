extends EntityBehaviorDefinition
class_name BirdBehaviorDefinition

@export_range(0.1, 12.0, 0.1) var flight_speed: float = 5.0
@export_range(0.1, 40.0, 0.1) var flight_acceleration: float = 12.0
@export_range(0.1, 12.0, 0.1) var landing_speed: float = 3.0
@export_range(0.1, 12.0, 0.1) var takeoff_speed: float = 6.5
@export_range(0.1, 12.0, 0.1) var grounded_walk_speed: float = 1.0
@export_range(0.1, 100.0, 0.1) var gravity: float = 25.0
@export_range(0.1, 20.0, 0.1) var jump_velocity: float = 5.0
@export_range(0.1, 4.0, 0.05) var repath_seconds: float = 0.5
@export_range(1.0, 24.0, 0.5) var grounded_wander_radius: float = 4.0
@export_range(4.0, 64.0, 0.5) var landing_search_radius: float = 28.0
@export_range(1, 32, 1) var cruise_altitude_min_blocks: int = 9
@export_range(1, 32, 1) var cruise_altitude_max_blocks: int = 14
@export_range(0.5, 8.0, 0.1) var landing_approach_distance: float = 3.0
@export_range(0.1, 15.0, 0.1) var landed_idle_min_seconds: float = 1.5
@export_range(0.1, 15.0, 0.1) var landed_idle_max_seconds: float = 3.0
@export_range(0.1, 15.0, 0.1) var grounded_walk_seconds: float = 2.5
@export_range(1, 8, 1) var walks_before_takeoff: int = 2
@export_range(0.1, 10.0, 0.1) var landing_retry_seconds: float = 1.0
@export_range(0.1, 3.0, 0.05) var water_ripple_interval_seconds: float = 0.55
@export_range(0.5, 16.0, 0.5) var player_flee_distance: float = 5.0

func validate(source: String) -> bool:
	var valid := true
	if not is_finite(flight_speed) or not is_finite(grounded_walk_speed) or flight_speed < grounded_walk_speed or grounded_walk_speed <= 0.0:
		push_error("[BirdBehaviorDefinition] Invalid movement speeds at %s" % source)
		valid = false
	if not is_finite(flight_acceleration) or not is_finite(landing_speed) or not is_finite(takeoff_speed) or flight_acceleration <= 0.0 or landing_speed <= 0.0 or takeoff_speed <= 0.0:
		push_error("[BirdBehaviorDefinition] Invalid flight tuning at %s" % source)
		valid = false
	if not is_finite(gravity) or not is_finite(jump_velocity) or gravity <= 0.0 or jump_velocity <= 0.0:
		push_error("[BirdBehaviorDefinition] Invalid grounded vertical movement at %s" % source)
		valid = false
	if not is_finite(repath_seconds) or not is_finite(grounded_wander_radius) or not is_finite(landing_search_radius) or repath_seconds <= 0.0 or grounded_wander_radius <= 0.0 or landing_search_radius <= 0.0:
		push_error("[BirdBehaviorDefinition] Invalid navigation tuning at %s" % source)
		valid = false
	if cruise_altitude_min_blocks < 1 or cruise_altitude_min_blocks > cruise_altitude_max_blocks:
		push_error("[BirdBehaviorDefinition] Invalid cruise altitude range at %s" % source)
		valid = false
	if not is_finite(landing_approach_distance) or landing_approach_distance <= 0.0:
		push_error("[BirdBehaviorDefinition] Invalid landing approach at %s" % source)
		valid = false
	if not is_finite(landed_idle_min_seconds) or not is_finite(landed_idle_max_seconds) or landed_idle_min_seconds <= 0.0 or landed_idle_min_seconds > landed_idle_max_seconds:
		push_error("[BirdBehaviorDefinition] Invalid idle range at %s" % source)
		valid = false
	if not is_finite(grounded_walk_seconds) or not is_finite(landing_retry_seconds) or not is_finite(water_ripple_interval_seconds) or not is_finite(player_flee_distance) or grounded_walk_seconds <= 0.0 or landing_retry_seconds <= 0.0 or water_ripple_interval_seconds <= 0.0 or player_flee_distance <= 0.0 or walks_before_takeoff < 1:
		push_error("[BirdBehaviorDefinition] Invalid cycle timing at %s" % source)
		valid = false
	return valid
