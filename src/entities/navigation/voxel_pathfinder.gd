extends RefCounted
class_name VoxelPathfinder

const CARDINAL_DIRECTIONS: Array[Vector3i] = [
	Vector3i(-1, 0, 0),
	Vector3i(0, 0, -1),
	Vector3i(0, 0, 1),
	Vector3i(1, 0, 0),
]
const STEP_HEIGHT_OFFSETS: Array[int] = [0, 1, -1]

class OpenEntry:
	var position: Vector3i
	var path_cost: int
	var estimated_cost: int
	var sequence: int

	func _init(p_position: Vector3i, p_path_cost: int, p_estimated_cost: int, p_sequence: int):
		position = p_position
		path_cost = p_path_cost
		estimated_cost = p_estimated_cost
		sequence = p_sequence

static func find_path(voxel_world: VoxelWorld, start_feet: Vector3i, goal_feet: Vector3i, body_width: float, body_height: float, max_radius: int = 24, max_nodes: int = 1024) -> VoxelPathResult:
	if max_nodes <= 0:
		return VoxelPathResult.new(VoxelPathResult.Status.LIMIT_REACHED, [], 0)
	if not _is_walkable(voxel_world, start_feet, body_width, body_height):
		return VoxelPathResult.new(VoxelPathResult.Status.INVALID_START, [], 0)
	if not _is_walkable(voxel_world, goal_feet, body_width, body_height):
		return VoxelPathResult.new(VoxelPathResult.Status.INVALID_GOAL, [], 0)
	if not _is_within_radius(start_feet, goal_feet, max_radius):
		return VoxelPathResult.new(VoxelPathResult.Status.NO_PATH, [], 0)

	var open_heap: Array[OpenEntry] = []
	var path_costs: Dictionary = {start_feet: 0}
	var came_from: Dictionary = {}
	var closed: Dictionary = {}
	var sequence := 0
	var start_estimate := _estimate_cost(start_feet, goal_feet)
	_heap_push(open_heap, OpenEntry.new(start_feet, 0, start_estimate, sequence))
	var limit_reached := false

	while not open_heap.is_empty():
		var current_entry := _heap_pop(open_heap)
		var current := current_entry.position
		if closed.has(current):
			continue
		var best_known_cost := path_costs.get(current, -1) as int
		if current_entry.path_cost != best_known_cost:
			continue
		closed[current] = true
		if current == goal_feet:
			return VoxelPathResult.new(VoxelPathResult.Status.FOUND, _reconstruct_path(came_from, start_feet, goal_feet), path_costs.size())

		for direction in CARDINAL_DIRECTIONS:
			var horizontal := current + direction
			for height_offset in STEP_HEIGHT_OFFSETS:
				var neighbor := Vector3i(horizontal.x, current.y + height_offset, horizontal.z)
				if not _is_within_radius(start_feet, neighbor, max_radius):
					continue
				if not _is_walkable(voxel_world, neighbor, body_width, body_height):
					continue
				if height_offset == 1:
					var raised_current := Vector3i(current.x, current.y + 1, current.z)
					if not _has_body_clearance(voxel_world, raised_current, body_width, body_height):
						continue
				var next_cost := best_known_cost + 1
				var previous_cost := path_costs.get(neighbor, -1) as int
				if previous_cost >= 0 and next_cost >= previous_cost:
					break
				if previous_cost < 0 and path_costs.size() >= max_nodes:
					limit_reached = true
					break
				path_costs[neighbor] = next_cost
				came_from[neighbor] = current
				sequence += 1
				var estimated_cost := next_cost + _estimate_cost(neighbor, goal_feet)
				_heap_push(open_heap, OpenEntry.new(neighbor, next_cost, estimated_cost, sequence))
				break

	var status := VoxelPathResult.Status.LIMIT_REACHED if limit_reached else VoxelPathResult.Status.NO_PATH
	return VoxelPathResult.new(status, [], path_costs.size())

static func _is_walkable(voxel_world: VoxelWorld, feet: Vector3i, body_width: float, body_height: float) -> bool:
	if not _has_body_clearance(voxel_world, feet, body_width, body_height):
		return false
	var body_position := _body_position(feet)
	return is_equal_approx(VoxelBodySolver.get_ground_y(voxel_world, body_position, body_width), float(feet.y))

static func _has_body_clearance(voxel_world: VoxelWorld, feet: Vector3i, body_width: float, body_height: float) -> bool:
	var body_position := _body_position(feet)
	if VoxelBodySolver.collides_at(voxel_world, body_position, body_width, body_height, false):
		return false
	var min_x := int(floor(body_position.x - body_width * 0.5))
	var max_x := int(floor(body_position.x + body_width * 0.5))
	var min_y := int(floor(body_position.y))
	var max_y := int(floor(body_position.y + body_height - 0.001))
	var min_z := int(floor(body_position.z - body_width * 0.5))
	var max_z := int(floor(body_position.z + body_width * 0.5))
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			for z in range(min_z, max_z + 1):
				if voxel_world.get_block_id_at(Vector3i(x, y, z)) == BlockId.Type.WATER:
					return false
	return true

static func _body_position(feet: Vector3i) -> Vector3:
	return Vector3(float(feet.x) + 0.5, float(feet.y), float(feet.z) + 0.5)

static func _is_within_radius(origin: Vector3i, position: Vector3i, max_radius: int) -> bool:
	var delta_x := position.x - origin.x
	var delta_z := position.z - origin.z
	return delta_x * delta_x + delta_z * delta_z <= max_radius * max_radius

static func _estimate_cost(from: Vector3i, to: Vector3i) -> int:
	return abs(from.x - to.x) + abs(from.z - to.z)

static func _reconstruct_path(came_from: Dictionary, start_feet: Vector3i, goal_feet: Vector3i) -> Array[Vector3i]:
	var path: Array[Vector3i] = [goal_feet]
	var cursor := goal_feet
	while cursor != start_feet:
		cursor = came_from[cursor] as Vector3i
		path.append(cursor)
	path.reverse()
	return path

static func _heap_push(heap: Array[OpenEntry], entry: OpenEntry) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if not _entry_precedes(heap[index], heap[parent]):
			break
		var parent_entry := heap[parent]
		heap[parent] = heap[index]
		heap[index] = parent_entry
		index = parent

static func _heap_pop(heap: Array[OpenEntry]) -> OpenEntry:
	var first := heap[0]
	var last := heap.pop_back() as OpenEntry
	if not heap.is_empty():
		heap[0] = last
		var index := 0
		while true:
			var left := index * 2 + 1
			var right := left + 1
			var smallest := index
			if left < heap.size() and _entry_precedes(heap[left], heap[smallest]):
				smallest = left
			if right < heap.size() and _entry_precedes(heap[right], heap[smallest]):
				smallest = right
			if smallest == index:
				break
			var smallest_entry := heap[smallest]
			heap[smallest] = heap[index]
			heap[index] = smallest_entry
			index = smallest
	return first

static func _entry_precedes(left: OpenEntry, right: OpenEntry) -> bool:
	if left.estimated_cost != right.estimated_cost:
		return left.estimated_cost < right.estimated_cost
	var left_remaining := left.estimated_cost - left.path_cost
	var right_remaining := right.estimated_cost - right.path_cost
	if left_remaining != right_remaining:
		return left_remaining < right_remaining
	return left.sequence < right.sequence
