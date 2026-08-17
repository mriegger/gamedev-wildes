extends RefCounted
class_name VoxelCameraOcclusion

const EntityTargetObservationType := preload("res://entities/entity_target_observation.gd")

static func is_hidden(
	voxel_space: VoxelSpace,
	observation: EntityTargetObservationType,
	feet_position: Vector3,
	body_width: float,
	body_height: float,
) -> bool:
	assert(voxel_space != null)
	assert(observation != null and observation.validate())
	assert(feet_position.is_finite())
	assert(is_finite(body_width) and body_width > 0.0)
	assert(is_finite(body_height) and body_height > 0.0)

	var camera_forward := observation.camera_forward.normalized()
	var camera_right := observation.camera_right - camera_forward * observation.camera_right.dot(camera_forward)
	assert(not camera_right.is_zero_approx())
	camera_right = camera_right.normalized()

	for height_index in range(3):
		var height_fraction := 0.1 + float(height_index) * 0.4
		for side_index in range(-1, 2):
			var sample := (
				feet_position
				+ Vector3.UP * body_height * height_fraction
				+ camera_right * body_width * 0.5 * float(side_index)
			)
			var distance_from_plane := (sample - observation.camera_origin).dot(camera_forward)
			if distance_from_plane <= 0.0:
				return false
			var ray_origin := sample - camera_forward * distance_from_plane
			if VoxelLineOfSight.has_clear_path(voxel_space, ray_origin, sample):
				return false
	return true
