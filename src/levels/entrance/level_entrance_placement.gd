extends RefCounted
class_name LevelEntrancePlacement

const MIN_RADIUS: int = 6
const MAX_RADIUS: int = 12

static func find_position(voxel_world: VoxelWorld, spawn_position: Vector3, seed: int) -> Variant:
	var center := Vector2i(floori(spawn_position.x), floori(spawn_position.z))
	var candidates: Array[Vector2i] = []
	for x in range(-MAX_RADIUS, MAX_RADIUS + 1):
		for z in range(-MAX_RADIUS, MAX_RADIUS + 1):
			var distance_squared := x * x + z * z
			if distance_squared < MIN_RADIUS * MIN_RADIUS or distance_squared > MAX_RADIUS * MAX_RADIUS:
				continue
			candidates.append(center + Vector2i(x, z))
	if candidates.is_empty():
		return null
	var start_index := posmod(seed, candidates.size())
	for offset in range(candidates.size()):
		var candidate: Vector2i = candidates[(start_index + offset) % candidates.size()]
		var position: Variant = _try_flat_patch(voxel_world, candidate)
		if position != null:
			return position
	return null

static func get_protected_cells(position: Vector3) -> Array[Vector3i]:
	var center := Vector3i(floori(position.x), floori(position.y), floori(position.z))
	var cells: Array[Vector3i] = []
	for x in range(center.x - 1, center.x + 2):
		for z in range(center.z - 1, center.z + 2):
			for y in range(center.y - 1, center.y + 4):
				cells.append(Vector3i(x, y, z))
	return cells

static func has_edit_conflict(voxel_world: VoxelWorld, position: Vector3) -> bool:
	for cell in get_protected_cells(position):
		if voxel_world.has_persisted_edit(cell):
			return true
	return false

static func _try_flat_patch(voxel_world: VoxelWorld, center: Vector2i) -> Variant:
	var surface_y := int(voxel_world.get_terrain_surface_top(center.x, center.y))
	if surface_y == int(VoxelSpace.NO_SURFACE_Y):
		return null
	for x in range(center.x - 1, center.x + 2):
		for z in range(center.y - 1, center.y + 2):
			if int(voxel_world.get_terrain_surface_top(x, z)) != surface_y:
				return null
			if voxel_world.get_terrain_surface_block_id(x, z) != BlockId.Type.GRASS:
				return null
	return Vector3(center.x + 0.5, surface_y, center.y + 0.5)
