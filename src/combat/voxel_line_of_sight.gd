extends RefCounted
class_name VoxelLineOfSight

const SAMPLE_INTERVAL: float = 0.25

static func has_clear_path(
	voxel_space: VoxelSpace,
	origin: Vector3,
	target: Vector3,
	ignored_block_predicate: Callable = Callable(),
) -> bool:
	var offset := target - origin
	var distance := offset.length()
	if distance <= 0.001:
		return true
	var direction := offset / distance
	var step_count := ceili(distance / SAMPLE_INTERVAL)
	for step in range(1, step_count):
		var point := origin + direction * (float(step) * distance / float(step_count))
		var voxel := Vector3i(floori(point.x), floori(point.y), floori(point.z))
		if (
			voxel_space.is_raycast_solid(voxel)
			and (
				not ignored_block_predicate.is_valid()
				or not bool(ignored_block_predicate.call(voxel_space.get_block_id_at(voxel)))
			)
		):
			return false
	return true
