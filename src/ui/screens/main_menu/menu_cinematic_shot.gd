extends Resource
class_name MenuCinematicShot

@export var id: StringName
@export var duration_seconds: float = 10.0
@export_range(0.0, 24.0) var time_of_day: float = 12.0
@export var anchor: Vector2i
@export var yaw_degrees: float = 225.0
@export var pitch_degrees: float = -42.0
@export var orthographic_size: float = 40.0
@export var drift: Vector2
@export var spawns: Array[MenuCinematicSpawn] = []

func validate(entity_catalog: EntityCatalog, maximum_anchor_radius: float) -> bool:
	if (
		id.is_empty()
		or not is_finite(duration_seconds)
		or duration_seconds <= 0.0
		or not is_finite(time_of_day)
		or time_of_day < 0.0
		or time_of_day >= 24.0
		or Vector2(anchor).length() > maximum_anchor_radius
		or not is_finite(yaw_degrees)
		or not is_finite(pitch_degrees)
		or pitch_degrees < -70.0
		or pitch_degrees > -20.0
		or not is_finite(orthographic_size)
		or orthographic_size < 24.0
		or orthographic_size > 60.0
		or not drift.is_finite()
		or drift.length() > 12.0
	):
		return false
	for spawn in spawns:
		if spawn == null or not spawn.validate(entity_catalog):
			return false
	return true
