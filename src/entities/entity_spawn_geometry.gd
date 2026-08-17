extends RefCounted
class_name EntitySpawnGeometry

static func can_spawn(voxel_space: VoxelSpace, definition: EntityDefinition, feet_position: Vector3) -> bool:
	if voxel_space == null or definition == null or not feet_position.is_finite():
		return false
	if not is_equal_approx(feet_position.x - floorf(feet_position.x), 0.5):
		return false
	if not is_equal_approx(feet_position.y, roundf(feet_position.y)):
		return false
	if not is_equal_approx(feet_position.z - floorf(feet_position.z), 0.5):
		return false
	if VoxelBodySolver.collides_at(voxel_space, feet_position, definition.body_width, definition.body_height, false):
		return false
	var ground_y := VoxelBodySolver.get_ground_y(voxel_space, feet_position, definition.body_width)
	return ground_y != VoxelSpace.NO_SURFACE_Y and is_equal_approx(ground_y, feet_position.y)

static func get_bounds(definition: EntityDefinition, feet_position: Vector3) -> AABB:
	assert(definition != null and feet_position.is_finite())
	var half_width := definition.body_width * 0.5
	return AABB(
		feet_position + Vector3(-half_width, 0.0, -half_width),
		Vector3(definition.body_width, definition.body_height, definition.body_width)
	)
