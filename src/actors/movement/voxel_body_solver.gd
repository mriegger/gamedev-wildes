extends RefCounted
class_name VoxelBodySolver

static func sweep(voxel_space: VoxelSpace, position: Vector3, velocity: Vector3, motion: Vector3, body_width: float, body_height: float) -> VoxelBodyMotionResult:
	var resolved_position := position
	var resolved_velocity := velocity

	if motion.x != 0.0:
		var steps_x := int(ceil(abs(motion.x) / 0.4)) + 1
		var step_x := motion.x / float(steps_x)
		for _step in range(steps_x):
			var test_position := resolved_position + Vector3(step_x, 0.0, 0.0)
			if collides_at(voxel_space, test_position, body_width, body_height, true):
				resolved_velocity.x = 0.0
				break
			resolved_position.x = test_position.x

	if motion.z != 0.0:
		var steps_z := int(ceil(abs(motion.z) / 0.4)) + 1
		var step_z := motion.z / float(steps_z)
		for _step in range(steps_z):
			var test_position := resolved_position + Vector3(0.0, 0.0, step_z)
			if collides_at(voxel_space, test_position, body_width, body_height, true):
				resolved_velocity.z = 0.0
				break
			resolved_position.z = test_position.z

	if motion.y < 0.0:
		var steps_y := int(ceil(abs(motion.y) / 0.25)) + 1
		var step_y := motion.y / float(steps_y)
		for _step in range(steps_y):
			var test_position := resolved_position + Vector3(0.0, step_y, 0.0)
			var ground_y := get_ground_y(voxel_space, test_position, body_width)
			if ground_y != VoxelSpace.NO_SURFACE_Y and test_position.y <= ground_y + 0.03 and test_position.y >= ground_y - 0.4:
				resolved_position.y = ground_y
				resolved_velocity.y = 0.0
				break
			if collides_at(voxel_space, test_position, body_width, body_height, false):
				var collision_ground_y := get_ground_y(voxel_space, test_position, body_width)
				if collision_ground_y != VoxelSpace.NO_SURFACE_Y and abs(collision_ground_y - test_position.y) < 0.15:
					resolved_position.y = collision_ground_y
				resolved_velocity.y = 0.0
				break
			resolved_position.y = test_position.y
	elif motion.y > 0.0:
		var steps_y := int(ceil(abs(motion.y) / 0.25)) + 1
		var step_y := motion.y / float(steps_y)
		for _step in range(steps_y):
			var test_position := resolved_position + Vector3(0.0, step_y, 0.0)
			if collides_at(voxel_space, test_position, body_width, body_height, false):
				resolved_velocity.y = 0.0
				break
			resolved_position.y = test_position.y

	return VoxelBodyMotionResult.new(resolved_position, resolved_velocity)

static func collides_at(voxel_space: VoxelSpace, position: Vector3, body_width: float, body_height: float, ignore_ground: bool) -> bool:
	var min_x := int(floor(position.x - body_width * 0.5))
	var max_x := int(floor(position.x + body_width * 0.5))
	var min_y := int(floor(position.y))
	var max_y := int(floor(position.y + body_height - 0.001))
	var min_z := int(floor(position.z - body_width * 0.5))
	var max_z := int(floor(position.z + body_width * 0.5))
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			for z in range(min_z, max_z + 1):
				if voxel_space.is_solid(Vector3i(x, y, z)):
					if ignore_ground:
						var block_top := float(y) + 1.0
						if block_top <= position.y + 0.05:
							continue
					return true
	return false

static func get_ground_y(voxel_space: VoxelSpace, position: Vector3, body_width: float) -> float:
	var footprint := _get_footprint(position, body_width)
	var best := VoxelSpace.NO_SURFACE_Y
	var feet_y := int(floor(position.y + 0.08))
	for x in range(footprint.position.x, footprint.end.x):
		for z in range(footprint.position.y, footprint.end.y):
			var highest_top := voxel_space.get_highest_top(x, z)
			if highest_top != VoxelSpace.NO_SURFACE_Y and highest_top <= position.y + 0.08 and highest_top >= position.y - 1.2:
				if highest_top > best:
					best = highest_top
				continue
			for depth in range(6):
				var y := feet_y - depth
				if voxel_space.is_solid(Vector3i(x, y, z)):
					var block_top := float(y) + 1.0
					if block_top <= position.y + 0.08 and block_top > best:
						best = block_top
					break
	return best

static func has_solid_support(voxel_space: VoxelSpace, position: Vector3, body_width: float) -> bool:
	var footprint := _get_footprint(position, body_width)
	var support_y := floori(position.y - 0.001)
	for x in range(footprint.position.x, footprint.end.x):
		for z in range(footprint.position.y, footprint.end.y):
			if voxel_space.is_solid(Vector3i(x, support_y, z)):
				return true
	return false

static func get_supporting_block_id(voxel_space: VoxelSpace, position: Vector3, body_width: float, ground_y: float) -> int:
	if ground_y == VoxelSpace.NO_SURFACE_Y:
		return BlockId.Type.AIR
	var footprint := _get_footprint(position, body_width)
	var block_y := floori(ground_y - 0.001)
	var nearest_distance := INF
	var nearest_block_id := BlockId.Type.AIR
	for x in range(footprint.position.x, footprint.end.x):
		for z in range(footprint.position.y, footprint.end.y):
			var cell := Vector3i(x, block_y, z)
			if not voxel_space.is_solid(cell):
				continue
			var distance := Vector2(
				position.x - (float(x) + 0.5),
				position.z - (float(z) + 0.5),
			).length_squared()
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_block_id = voxel_space.get_block_id_at(cell)
	return nearest_block_id

static func _get_footprint(position: Vector3, body_width: float) -> Rect2i:
	var min_x := floori(position.x - body_width * 0.5 + 0.04)
	var max_x := floori(position.x + body_width * 0.5 - 0.04)
	var min_z := floori(position.z - body_width * 0.5 + 0.04)
	var max_z := floori(position.z + body_width * 0.5 - 0.04)
	return Rect2i(min_x, min_z, max_x - min_x + 1, max_z - min_z + 1)
