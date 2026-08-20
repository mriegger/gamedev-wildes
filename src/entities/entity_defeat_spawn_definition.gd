extends Resource
class_name EntityDefeatSpawnDefinition

const MAXIMUM_COUNT: int = 64

@export var child_definition_id: StringName
@export_range(1, 64, 1) var minimum_count: int = 1
@export_range(1, 64, 1) var maximum_count: int = 1
@export_range(0.0, 8.0, 0.01, "or_greater") var child_spawn_clearance: float = 0.0
@export_range(0.0, 8.0, 0.01, "or_greater") var child_damage_immunity_seconds: float = 0.0
@export_range(0.0, 32.0, 0.1, "or_greater") var child_launch_planar_speed: float = 0.0
@export_range(0.0, 32.0, 0.1, "or_greater") var child_launch_vertical_speed: float = 0.0

static func _are_child_launch_speeds_valid(planar_speed: float, vertical_speed: float) -> bool:
	return (
		is_finite(planar_speed)
		and planar_speed >= 0.0
		and is_finite(vertical_speed)
		and vertical_speed >= 0.0
		and ((planar_speed > 0.0) == (vertical_speed > 0.0))
	)

func validate(source: String) -> bool:
	var valid := true
	if child_definition_id.is_empty():
		push_error("[EntityDefeatSpawnDefinition] Empty child definition ID at %s" % source)
		valid = false
	if minimum_count < 1 or maximum_count < minimum_count or maximum_count > MAXIMUM_COUNT:
		push_error("[EntityDefeatSpawnDefinition] Invalid child count range at %s" % source)
		valid = false
	if not is_finite(child_spawn_clearance) or child_spawn_clearance < 0.0:
		push_error("[EntityDefeatSpawnDefinition] Invalid child spawn clearance at %s" % source)
		valid = false
	if not is_finite(child_damage_immunity_seconds) or child_damage_immunity_seconds < 0.0:
		push_error("[EntityDefeatSpawnDefinition] Invalid child damage immunity at %s" % source)
		valid = false
	if not _are_child_launch_speeds_valid(child_launch_planar_speed, child_launch_vertical_speed):
		push_error("[EntityDefeatSpawnDefinition] Invalid child launch speeds at %s" % source)
		valid = false
	return valid
