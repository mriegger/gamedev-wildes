extends RefCounted
class_name VoxelCoverSearch

enum Status {
	SEARCHING,
	FOUND,
	EXHAUSTED,
}

const SEARCH_RADIUS: int = 30
const NODES_PER_TICK: int = 16

class ReachableEntry:
	var position: Vector3i
	var path_cost: int

	func _init(p_position: Vector3i, p_path_cost: int) -> void:
		position = p_position
		path_cost = p_path_cost

var status: Status:
	get:
		return _status

var _voxel_space: VoxelSpace
var _body_width: float
var _body_height: float
var _navigation_limits: EntityNavigationLimits
var _search_radius: int
var _status: Status = Status.EXHAUSTED
var _origin_feet: Vector3i
var _candidate_exclusion_origin: Vector2
var _observation: EntityTargetObservation
var _frontier: NavigationPriorityQueue
var _path_costs: Dictionary = {}
var _came_from: Dictionary = {}
var _closed: Dictionary = {}
var _target: Vector3 = Vector3.ZERO
var _target_path: Array[Vector3i] = []
var _minimum_candidate_distance_squared: float = 0.0

func _init(
	p_voxel_space: VoxelSpace,
	p_body_width: float,
	p_body_height: float,
	p_navigation_limits: EntityNavigationLimits,
) -> void:
	assert(p_voxel_space != null)
	assert(is_finite(p_body_width) and p_body_width > 0.0)
	assert(is_finite(p_body_height) and p_body_height > 0.0)
	assert(p_navigation_limits != null)
	_voxel_space = p_voxel_space
	_body_width = p_body_width
	_body_height = p_body_height
	_navigation_limits = p_navigation_limits
	_search_radius = mini(SEARCH_RADIUS, _navigation_limits.get_max_search_radius())
	_frontier = NavigationPriorityQueue.new(_entry_precedes)

func begin(origin: Vector3, candidate_exclusion_origin: Vector3, observation: EntityTargetObservation, minimum_candidate_distance: float) -> void:
	assert(origin.is_finite())
	assert(candidate_exclusion_origin.is_finite())
	assert(observation != null and observation.validate())
	assert(is_finite(minimum_candidate_distance) and minimum_candidate_distance >= 0.0)
	_origin_feet = Vector3i(floori(origin.x), roundi(origin.y), floori(origin.z))
	_candidate_exclusion_origin = Vector2(candidate_exclusion_origin.x, candidate_exclusion_origin.z)
	_minimum_candidate_distance_squared = minimum_candidate_distance * minimum_candidate_distance
	_observation = EntityTargetObservation.new(
		observation.player_position,
		observation.camera_origin,
		observation.camera_forward,
		observation.camera_right,
	)
	_frontier.clear()
	_path_costs.clear()
	_came_from.clear()
	_closed.clear()
	_target = Vector3.ZERO
	_target_path.clear()
	if not VoxelPathfinder.is_walkable(_voxel_space, _origin_feet, _body_width, _body_height):
		_status = Status.EXHAUSTED
		return
	_path_costs[_origin_feet] = 0
	_frontier.push(ReachableEntry.new(_origin_feet, 0))
	_status = Status.SEARCHING

func advance(search_budget: NavigationSearchBudget) -> Status:
	assert(search_budget != null)
	if _status != Status.SEARCHING or not search_budget.try_acquire():
		return _status
	var walkability_cache: Dictionary = {}
	var body_clearance_cache: Dictionary = {}
	var processed_nodes := 0
	while processed_nodes < NODES_PER_TICK:
		if _frontier.is_empty():
			_status = Status.EXHAUSTED
			return _status
		var entry := _frontier.pop() as ReachableEntry
		processed_nodes += 1
		if _closed.has(entry.position):
			continue
		if entry.path_cost != int(_path_costs.get(entry.position, -1)):
			continue
		_closed[entry.position] = true
		if _is_cover(entry.position):
			_target = _cell_center(entry.position)
			_target_path = _reconstruct_path(entry.position)
			_status = Status.FOUND
			return _status
		for neighbor in VoxelPathfinder.get_walkable_neighbors(
			_voxel_space,
			_origin_feet,
			entry.position,
			_body_width,
			_body_height,
			_search_radius,
			walkability_cache,
			body_clearance_cache,
		):
			if _closed.has(neighbor):
				continue
			var next_cost := entry.path_cost + VoxelPathfinder.get_step_cost(entry.position, neighbor)
			var previous_cost := _path_costs.get(neighbor, -1) as int
			if previous_cost >= 0 and next_cost >= previous_cost:
				continue
			if previous_cost < 0 and _path_costs.size() >= _navigation_limits.get_max_search_nodes():
				continue
			_path_costs[neighbor] = next_cost
			_came_from[neighbor] = entry.position
			_frontier.push(ReachableEntry.new(neighbor, next_cost))
	if _frontier.is_empty():
		_status = Status.EXHAUSTED
	return _status

func get_target() -> Vector3:
	assert(_status == Status.FOUND)
	return _target

func get_target_path() -> Array[Vector3i]:
	assert(_status == Status.FOUND)
	return _target_path.duplicate()

func _is_cover(feet: Vector3i) -> bool:
	var candidate := _cell_center(feet)
	var horizontal_position := Vector2(candidate.x, candidate.z)
	if horizontal_position.distance_squared_to(_candidate_exclusion_origin) < _minimum_candidate_distance_squared:
		return false
	return VoxelCameraOcclusion.is_hidden(
		_voxel_space,
		_observation,
		candidate,
		_body_width,
		_body_height,
	)

func _cell_center(feet: Vector3i) -> Vector3:
	return Vector3(float(feet.x) + 0.5, float(feet.y), float(feet.z) + 0.5)

func _reconstruct_path(goal: Vector3i) -> Array[Vector3i]:
	var path: Array[Vector3i] = [goal]
	var cursor := goal
	while cursor != _origin_feet:
		cursor = _came_from[cursor] as Vector3i
		path.append(cursor)
	path.reverse()
	return path

static func _entry_precedes(left: ReachableEntry, right: ReachableEntry) -> bool:
	if left.path_cost != right.path_cost:
		return left.path_cost < right.path_cost
	if left.position.x != right.position.x:
		return left.position.x < right.position.x
	if left.position.z != right.position.z:
		return left.position.z < right.position.z
	if left.position.y != right.position.y:
		return left.position.y < right.position.y
	return false
