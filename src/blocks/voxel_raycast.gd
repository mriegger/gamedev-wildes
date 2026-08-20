extends RefCounted
class_name VoxelRaycast

const UNREACHABLE_DISTANCE: float = 999999.0

static func cast(voxel_space: VoxelSpace, origin: Vector3, direction: Vector3, max_distance: float) -> VoxelRaycastHit:
	direction = direction.normalized()
	if direction.length_squared() < 0.0001:
		return null
	var current := Vector3i(floor(origin.x), floor(origin.y), floor(origin.z))
	var can_hit := not voxel_space.is_raycast_solid(current)
	if not can_hit:
		can_hit = not voxel_space.get_interaction_bounds(current).has_point(origin)

	var step_x := 1 if direction.x >= 0 else -1
	var step_y := 1 if direction.y >= 0 else -1
	var step_z := 1 if direction.z >= 0 else -1

	var t_max_x: float
	var t_max_y: float
	var t_max_z: float
	var t_delta_x: float
	var t_delta_y: float
	var t_delta_z: float

	var frac_x = origin.x - floor(origin.x)
	var frac_y = origin.y - floor(origin.y)
	var frac_z = origin.z - floor(origin.z)

	if direction.x != 0:
		t_delta_x = abs(1.0 / direction.x)
		t_max_x = (1.0 - frac_x) * t_delta_x if step_x > 0 else frac_x * t_delta_x
	else:
		t_max_x = UNREACHABLE_DISTANCE
		t_delta_x = UNREACHABLE_DISTANCE

	if direction.y != 0:
		t_delta_y = abs(1.0 / direction.y)
		t_max_y = (1.0 - frac_y) * t_delta_y if step_y > 0 else frac_y * t_delta_y
	else:
		t_max_y = UNREACHABLE_DISTANCE
		t_delta_y = UNREACHABLE_DISTANCE

	if direction.z != 0:
		t_delta_z = abs(1.0 / direction.z)
		t_max_z = (1.0 - frac_z) * t_delta_z if step_z > 0 else frac_z * t_delta_z
	else:
		t_max_z = UNREACHABLE_DISTANCE
		t_delta_z = UNREACHABLE_DISTANCE

	var traveled := 0.0
	var entry_normal := Vector3i.ZERO

	for _index in range(int(max_distance * 2 + 10)):
		var current_is_solid := voxel_space.is_raycast_solid(current)
		if current_is_solid and can_hit:
			var bounds := voxel_space.get_interaction_bounds(current)
			var is_full_cell := bounds.position == Vector3(current) and bounds.size == Vector3.ONE
			var hit_distance := traveled
			var face_normal := entry_normal
			var bounds_hit := Vector4(-1.0, 0.0, 0.0, 0.0)
			if not is_full_cell:
				bounds_hit = _intersect_bounds(bounds, origin, direction, max_distance)
				if bounds_hit.x >= 0.0:
					hit_distance = bounds_hit.x
					face_normal = Vector3i(int(bounds_hit.y), int(bounds_hit.z), int(bounds_hit.w))
			if bounds_hit.x >= 0.0 or is_full_cell:
				if voxel_space.is_face_targetable(current, face_normal):
					return VoxelRaycastHit.new(current, current + face_normal, face_normal, hit_distance, bounds)
		elif not current_is_solid:
			can_hit = true

		if t_max_x < t_max_y:
			if t_max_x < t_max_z:
				current.x += step_x
				traveled = t_max_x
				entry_normal = Vector3i(-step_x, 0, 0)
				t_max_x += t_delta_x
			else:
				current.z += step_z
				traveled = t_max_z
				entry_normal = Vector3i(0, 0, -step_z)
				t_max_z += t_delta_z
		else:
			if t_max_y < t_max_z:
				current.y += step_y
				traveled = t_max_y
				entry_normal = Vector3i(0, -step_y, 0)
				t_max_y += t_delta_y
			else:
				current.z += step_z
				traveled = t_max_z
				entry_normal = Vector3i(0, 0, -step_z)
				t_max_z += t_delta_z

		if traveled > max_distance:
			break
	return null

static func _intersect_bounds(bounds: AABB, origin: Vector3, direction: Vector3, max_distance: float) -> Vector4:
	var near_distance := -INF
	var far_distance := max_distance
	var near_normal := Vector3.ZERO
	var bounds_end := bounds.position + bounds.size
	for axis in range(3):
		var axis_origin := origin[axis]
		var axis_direction := direction[axis]
		var axis_minimum := bounds.position[axis]
		var axis_maximum := bounds_end[axis]
		if is_zero_approx(axis_direction):
			if axis_origin < axis_minimum or axis_origin > axis_maximum:
				return Vector4(-1.0, 0.0, 0.0, 0.0)
			continue
		var axis_near := (axis_minimum - axis_origin) / axis_direction
		var axis_far := (axis_maximum - axis_origin) / axis_direction
		var axis_normal := Vector3.ZERO
		axis_normal[axis] = -1.0 if axis_direction > 0.0 else 1.0
		if axis_near > axis_far:
			var swap := axis_near
			axis_near = axis_far
			axis_far = swap
		if axis_near > near_distance:
			near_distance = axis_near
			near_normal = axis_normal
		far_distance = minf(far_distance, axis_far)
		if near_distance > far_distance:
			return Vector4(-1.0, 0.0, 0.0, 0.0)
	if far_distance < 0.0 or near_distance > max_distance:
		return Vector4(-1.0, 0.0, 0.0, 0.0)
	return Vector4(maxf(0.0, near_distance), near_normal.x, near_normal.y, near_normal.z)
