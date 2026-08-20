extends ItemActionDefinition
class_name BowDrawActionDefinition

@export_range(0.05, 1.0, 0.01) var raise_seconds: float = 0.18
@export_range(0.1, 10.0, 0.1) var draw_seconds: float = 1.5
@export_range(0.1, 1.0, 0.01) var full_draw_distance: float = 0.48
@export_range(0.1, 100.0, 0.1, "or_greater") var minimum_launch_speed: float = 12.0
@export_range(0.1, 100.0, 0.1, "or_greater") var maximum_launch_speed: float = 48.0
@export_range(0.01, 1.0, 0.01) var minimum_damage_multiplier: float = 0.4
@export_range(0.0, 3.0, 0.001, "or_greater") var projectile_launch_height: float = 1.0485
@export_range(-2.0, 2.0, 0.001) var projectile_launch_right_offset: float = 0.1066
@export_range(0.0, 3.0, 0.001, "or_greater") var projectile_launch_forward_offset: float = 0.8006
@export_range(0.0, 90.0, 0.1) var maximum_launch_angle_degrees: float = 45.0
@export var ammunition: Array[ArrowItemDefinition]

func validate(source: String) -> bool:
	var valid := true
	if not is_finite(raise_seconds) or raise_seconds <= 0.0:
		push_error("[BowDrawActionDefinition] Invalid raise duration at %s" % source)
		return false
	if not is_finite(draw_seconds) or draw_seconds <= 0.0:
		push_error("[BowDrawActionDefinition] Invalid draw duration at %s" % source)
		return false
	if not is_finite(full_draw_distance) or full_draw_distance <= 0.0 or full_draw_distance > 1.0:
		push_error("[BowDrawActionDefinition] Invalid full-draw distance at %s" % source)
		return false
	if not is_finite(minimum_launch_speed) or minimum_launch_speed <= 0.0:
		push_error("[BowDrawActionDefinition] Invalid minimum launch speed at %s" % source)
		valid = false
	if not is_finite(maximum_launch_speed) or maximum_launch_speed < minimum_launch_speed:
		push_error("[BowDrawActionDefinition] Invalid maximum launch speed at %s" % source)
		valid = false
	if not is_finite(minimum_damage_multiplier) or minimum_damage_multiplier <= 0.0 or minimum_damage_multiplier > 1.0:
		push_error("[BowDrawActionDefinition] Invalid minimum damage multiplier at %s" % source)
		valid = false
	if not is_finite(projectile_launch_height) or projectile_launch_height < 0.0:
		push_error("[BowDrawActionDefinition] Invalid projectile launch height at %s" % source)
		valid = false
	if not is_finite(projectile_launch_right_offset):
		push_error("[BowDrawActionDefinition] Invalid projectile right offset at %s" % source)
		valid = false
	if not is_finite(projectile_launch_forward_offset) or projectile_launch_forward_offset < full_draw_distance:
		push_error("[BowDrawActionDefinition] Invalid projectile forward offset at %s" % source)
		valid = false
	if not is_finite(maximum_launch_angle_degrees) or maximum_launch_angle_degrees <= 0.0 or maximum_launch_angle_degrees > 45.0:
		push_error("[BowDrawActionDefinition] Invalid maximum launch angle at %s" % source)
		valid = false
	if ammunition.is_empty():
		push_error("[BowDrawActionDefinition] Missing ammunition at %s" % source)
		valid = false
	var item_ids: Dictionary = {}
	for arrow in ammunition:
		if arrow == null or not arrow.validate(source):
			valid = false
			continue
		if item_ids.has(arrow.id):
			push_error("[BowDrawActionDefinition] Duplicate ammunition %s at %s" % [arrow.id, source])
			valid = false
		item_ids[arrow.id] = true
	return valid

func get_launch_speed(draw_progress: float) -> float:
	assert(is_finite(draw_progress))
	return lerpf(minimum_launch_speed, maximum_launch_speed, clampf(draw_progress, 0.0, 1.0))

func get_damage_multiplier(draw_progress: float) -> float:
	assert(is_finite(draw_progress))
	return lerpf(minimum_damage_multiplier, 1.0, clampf(draw_progress, 0.0, 1.0))

func get_projectile_release_transform(actor_position: Vector3, actor_forward: Vector3, aim_target: Vector3, draw_progress: float, gravity: float) -> Transform3D:
	assert(actor_position.is_finite() and actor_forward.is_finite() and aim_target.is_finite() and is_finite(draw_progress))
	assert(is_finite(gravity) and gravity > 0.0)
	var facing_forward := Vector3(actor_forward.x, 0.0, actor_forward.z).normalized()
	assert(not facing_forward.is_zero_approx())
	var facing_right := Vector3.UP.cross(facing_forward).normalized()
	var draw_weight := smoothstep(0.0, 1.0, clampf(draw_progress, 0.0, 1.0))
	var origin := actor_position + Vector3.UP * projectile_launch_height
	origin += facing_right * projectile_launch_right_offset
	origin += facing_forward * (projectile_launch_forward_offset - full_draw_distance * draw_weight)
	var target_offset := Vector3(aim_target.x - origin.x, 0.0, aim_target.z - origin.z)
	var forward := target_offset.normalized()
	if forward.is_zero_approx() or forward.dot(facing_forward) <= 0.0:
		forward = facing_forward
	var launch_angle := _get_projectile_launch_angle(origin, aim_target, draw_progress, gravity)
	var launch_direction := (forward * cos(launch_angle) + Vector3.UP * sin(launch_angle)).normalized()
	var right := Vector3.UP.cross(forward).normalized()
	var arrow_down := launch_direction.cross(-right).normalized()
	return Transform3D(Basis(arrow_down, launch_direction, -right), origin)

func _get_projectile_launch_angle(origin: Vector3, target: Vector3, draw_progress: float, gravity: float) -> float:
	var horizontal_distance := Vector2(target.x - origin.x, target.z - origin.z).length()
	var maximum_angle := deg_to_rad(maximum_launch_angle_degrees)
	var charge_angle := maximum_angle * smoothstep(0.0, 1.0, clampf(draw_progress, 0.0, 1.0))
	if horizontal_distance <= 0.000001:
		return charge_angle
	var speed := get_launch_speed(draw_progress)
	var speed_squared := speed * speed
	var height_delta := target.y - origin.y
	var discriminant := speed_squared * speed_squared - gravity * (gravity * horizontal_distance * horizontal_distance + 2.0 * height_delta * speed_squared)
	if discriminant < 0.0:
		return charge_angle
	var target_angle := atan((speed_squared - sqrt(discriminant)) / (gravity * horizontal_distance))
	if target_angle > maximum_angle:
		return charge_angle
	if target_angle < 0.0:
		return maxf(target_angle, -maximum_angle)
	return minf(target_angle, charge_angle)
