extends RefCounted
class_name VoxelLineOfSight

const SAMPLE_INTERVAL: float = 0.25

static func has_clear_path(voxel_world: VoxelWorld, origin: Vector3, target: Vector3) -> bool:
	var offset := target - origin
	var distance := offset.length()
	if distance <= 0.001:
		return true
	var direction := offset / distance
	var step_count := ceili(distance / SAMPLE_INTERVAL)
	for step in range(1, step_count):
		var point := origin + direction * (float(step) * distance / float(step_count))
		var voxel := Vector3i(floori(point.x), floori(point.y), floori(point.z))
		if voxel_world.is_raycast_solid(voxel):
			return false
	return true
