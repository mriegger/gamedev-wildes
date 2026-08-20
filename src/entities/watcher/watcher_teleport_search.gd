extends RefCounted

const EntitySpawnGeometryType := preload("res://entities/entity_spawn_geometry.gd")
const VoxelLineOfSightType := preload("res://combat/voxel_line_of_sight.gd")

const RADII: Array[float] = [7.0, 8.5, 10.0]
const SECTOR_COUNT: int = 16
const VERTICAL_OFFSETS: Array[int] = [0, 1, -1, 2, -2, 3, -3, 4, -4]
const BEARING_EPSILON: float = 0.000001

static func find_candidates(
	voxel_space: VoxelSpace,
	definition: EntityDefinition,
	behavior_seed: int,
	teleport_sequence: int,
	player_feet_position: Vector3,
	player_bounds: AABB,
	previous_actor_position: Vector3,
	position_ready: Callable,
) -> Array[Vector3]:
	assert(voxel_space != null)
	assert(definition != null)
	assert(teleport_sequence >= 0)
	assert(player_feet_position.is_finite())
	assert(player_bounds.position.is_finite() and player_bounds.size.is_finite())
	assert(previous_actor_position.is_finite())
	assert(position_ready.is_valid())
	var clear_candidates: Array[Vector3] = []
	var occluded_candidates: Array[Vector3] = []
	var visited_cells: Dictionary = {}
	var previous_bearing := _planar_direction(previous_actor_position - player_feet_position)
	var player_center := player_bounds.get_center()
	var base_y := roundf(player_feet_position.y)
	for radius in RADII:
		for sector_index in _get_sector_order(behavior_seed + teleport_sequence):
			var angle := TAU * float(sector_index) / float(SECTOR_COUNT)
			var direction := Vector3(cos(angle), 0.0, sin(angle))
			var unsnapped_position := player_feet_position + direction * radius
			var centered_x := floorf(unsnapped_position.x) + 0.5
			var centered_z := floorf(unsnapped_position.z) + 0.5
			for vertical_offset in VERTICAL_OFFSETS:
				var candidate := Vector3(
					centered_x,
					base_y + float(vertical_offset),
					centered_z,
				)
				var cell := Vector3i(floori(candidate.x), roundi(candidate.y), floori(candidate.z))
				if visited_cells.has(cell):
					continue
				visited_cells[cell] = true
				var candidate_bearing := _planar_direction(candidate - player_feet_position)
				if (
					not previous_bearing.is_zero_approx()
					and previous_bearing.dot(candidate_bearing) > BEARING_EPSILON
				):
					continue
				if not bool(position_ready.call(candidate)):
					continue
				if not EntitySpawnGeometryType.can_spawn_grounded(voxel_space, definition, candidate):
					continue
				var candidate_bounds := EntitySpawnGeometryType.get_bounds(definition, candidate)
				if player_bounds.intersects(candidate_bounds):
					continue
				if VoxelLineOfSightType.has_clear_path(
					voxel_space,
					player_center,
					candidate_bounds.get_center(),
				):
					clear_candidates.append(candidate)
				else:
					occluded_candidates.append(candidate)
	clear_candidates.append_array(occluded_candidates)
	return clear_candidates

static func _get_sector_order(seed: int) -> Array[int]:
	var order: Array[int] = []
	for sector_index in SECTOR_COUNT:
		order.append(sector_index)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for index in range(SECTOR_COUNT - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var value := order[index]
		order[index] = order[swap_index]
		order[swap_index] = value
	return order

static func _planar_direction(offset: Vector3) -> Vector2:
	var planar := Vector2(offset.x, offset.z)
	return planar.normalized() if not planar.is_zero_approx() else Vector2.ZERO
