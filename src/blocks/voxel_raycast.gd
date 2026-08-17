extends RefCounted
class_name VoxelRaycast

const UNREACHABLE_DISTANCE: float = 999999.0

static func cast(voxel_space: VoxelSpace, origin: Vector3, direction: Vector3, max_distance: float) -> VoxelRaycastHit:
	direction = direction.normalized()
	if direction.length_squared() < 0.0001:
		return null
	var current := Vector3i(floor(origin.x), floor(origin.y), floor(origin.z))
	var can_hit := not voxel_space.is_raycast_solid(current)

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
	var last_position := current

	for _index in range(int(max_distance * 2 + 10)):
		var current_is_solid := voxel_space.is_raycast_solid(current)
		if current_is_solid and can_hit:
			var face_normal: Vector3i
			if last_position.x != current.x:
				face_normal = Vector3i(-step_x, 0, 0)
			elif last_position.y != current.y:
				face_normal = Vector3i(0, -step_y, 0)
			else:
				face_normal = Vector3i(0, 0, -step_z)
			if voxel_space.is_face_targetable(current, face_normal):
				var placement_cell := last_position
				if voxel_space.is_raycast_solid(placement_cell):
					placement_cell = current + face_normal
				return VoxelRaycastHit.new(current, placement_cell, face_normal, traveled)
		elif not current_is_solid:
			can_hit = true

		if t_max_x < t_max_y:
			if t_max_x < t_max_z:
				last_position = current
				current.x += step_x
				traveled = t_max_x
				t_max_x += t_delta_x
			else:
				last_position = current
				current.z += step_z
				traveled = t_max_z
				t_max_z += t_delta_z
		else:
			if t_max_y < t_max_z:
				last_position = current
				current.y += step_y
				traveled = t_max_y
				t_max_y += t_delta_y
			else:
				last_position = current
				current.z += step_z
				traveled = t_max_z
				t_max_z += t_delta_z

		if traveled > max_distance:
			break
	return null
