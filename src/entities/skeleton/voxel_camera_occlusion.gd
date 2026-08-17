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

	var camera_forward := observation.camera_forward
	var half_width := body_width * 0.5
	var lower_height := body_height * 0.1
	var upper_height := body_height * 0.9

	for height in [lower_height, upper_height]:
		for x_offset in [-half_width, half_width]:
			for z_offset in [-half_width, half_width]:
				var corner := feet_position + Vector3(x_offset, height, z_offset)
				if _sample_is_visible(voxel_space, observation, camera_forward, corner):
					return false
	var torso_center := feet_position + Vector3.UP * body_height * 0.5
	if _sample_is_visible(voxel_space, observation, camera_forward, torso_center):
		return false
	return true

static func _sample_is_visible(
	voxel_space: VoxelSpace,
	observation: EntityTargetObservationType,
	camera_forward: Vector3,
	sample: Vector3,
) -> bool:
	var distance_from_plane := (sample - observation.camera_origin).dot(camera_forward)
	if distance_from_plane <= 0.0:
		return true
	var ray_origin := sample - camera_forward * distance_from_plane
	return VoxelLineOfSight.has_clear_path(voxel_space, ray_origin, sample)
