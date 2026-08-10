extends RefCounted
class_name VoxelBodySolver

static func sweep(voxel_world: VoxelWorld, position: Vector3, velocity: Vector3, motion: Vector3, body_width: float, body_height: float) -> VoxelBodyMotionResult:
	var resolved_position := position
	var resolved_velocity := velocity

	if motion.x != 0.0:
		var steps_x := int(ceil(abs(motion.x) / 0.4)) + 1
		var step_x := motion.x / float(steps_x)
		for _step in range(steps_x):
			var test_position := resolved_position + Vector3(step_x, 0.0, 0.0)
			if collides_at(voxel_world, test_position, body_width, body_height, true):
				resolved_velocity.x = 0.0
				break
			resolved_position.x = test_position.x

	if motion.z != 0.0:
		var steps_z := int(ceil(abs(motion.z) / 0.4)) + 1
		var step_z := motion.z / float(steps_z)
		for _step in range(steps_z):
			var test_position := resolved_position + Vector3(0.0, 0.0, step_z)
			if collides_at(voxel_world, test_position, body_width, body_height, true):
				resolved_velocity.z = 0.0
				break
			resolved_position.z = test_position.z

	if motion.y < 0.0:
		var steps_y := int(ceil(abs(motion.y) / 0.25)) + 1
		var step_y := motion.y / float(steps_y)
		for _step in range(steps_y):
			var test_position := resolved_position + Vector3(0.0, step_y, 0.0)
			var ground_y := get_ground_y(voxel_world, test_position, body_width)
			if ground_y != VoxelWorld.NO_SURFACE_Y and test_position.y <= ground_y + 0.03 and test_position.y >= ground_y - 0.4:
				resolved_position.y = ground_y
				resolved_velocity.y = 0.0
				break
			if collides_at(voxel_world, test_position, body_width, body_height, false):
				var collision_ground_y := get_ground_y(voxel_world, test_position, body_width)
				if collision_ground_y != VoxelWorld.NO_SURFACE_Y and abs(collision_ground_y - test_position.y) < 0.15:
					resolved_position.y = collision_ground_y
				resolved_velocity.y = 0.0
				break
			resolved_position.y = test_position.y
	elif motion.y > 0.0:
		var steps_y := int(ceil(abs(motion.y) / 0.25)) + 1
		var step_y := motion.y / float(steps_y)
		for _step in range(steps_y):
			var test_position := resolved_position + Vector3(0.0, step_y, 0.0)
			if collides_at(voxel_world, test_position, body_width, body_height, false):
				resolved_velocity.y = 0.0
				break
			resolved_position.y = test_position.y

	return VoxelBodyMotionResult.new(resolved_position, resolved_velocity)

static func collides_at(voxel_world: VoxelWorld, position: Vector3, body_width: float, body_height: float, ignore_ground: bool) -> bool:
	var min_x := int(floor(position.x - body_width * 0.5))
	var max_x := int(floor(position.x + body_width * 0.5))
	var min_y := int(floor(position.y))
	var max_y := int(floor(position.y + body_height - 0.001))
	var min_z := int(floor(position.z - body_width * 0.5))
	var max_z := int(floor(position.z + body_width * 0.5))
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			for z in range(min_z, max_z + 1):
				if voxel_world.is_solid(Vector3i(x, y, z)):
					if ignore_ground:
						var block_top := float(y) + 1.0
						if block_top <= position.y + 0.05:
							continue
					return true
	return false

static func get_ground_y(voxel_world: VoxelWorld, position: Vector3, body_width: float) -> float:
	var min_x := int(floor(position.x - body_width * 0.5 + 0.04))
	var max_x := int(floor(position.x + body_width * 0.5 - 0.04))
	var min_z := int(floor(position.z - body_width * 0.5 + 0.04))
	var max_z := int(floor(position.z + body_width * 0.5 - 0.04))
	var best := VoxelWorld.NO_SURFACE_Y
	var feet_y := int(floor(position.y + 0.08))
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			var highest_top := voxel_world.get_highest_top(x, z)
			if highest_top != VoxelWorld.NO_SURFACE_Y and highest_top <= position.y + 0.08 and highest_top >= position.y - 1.2:
				if highest_top > best:
					best = highest_top
				continue
			for depth in range(6):
				var y := feet_y - depth
				if voxel_world.is_solid(Vector3i(x, y, z)):
					var block_top := float(y) + 1.0
					if block_top <= position.y + 0.08 and block_top > best:
						best = block_top
					break
	return best
