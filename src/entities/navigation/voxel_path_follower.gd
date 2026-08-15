extends RefCounted
class_name VoxelPathFollower

var _voxel_space: VoxelSpace
var _body_width: float
var _body_height: float
var _repath_seconds: float
var _navigation_limits: EntityNavigationLimits
var _path: Array[Vector3i] = []
var _path_index: int = 0
var _repath_remaining: float = 0.0

func _init(
	p_voxel_space: VoxelSpace,
	p_body_width: float,
	p_body_height: float,
	p_repath_seconds: float,
	p_navigation_limits: EntityNavigationLimits,
):
	assert(p_voxel_space != null)
	assert(p_body_width > 0.0 and p_body_height > 0.0 and p_repath_seconds > 0.0)
	assert(p_navigation_limits != null)
	_voxel_space = p_voxel_space
	_body_width = p_body_width
	_body_height = p_body_height
	_repath_seconds = p_repath_seconds
	_navigation_limits = p_navigation_limits

func advance(delta: float, position: Vector3, goal: Vector3, speed: float, on_ground: bool, search_budget: NavigationSearchBudget) -> VoxelPathFollowResult:
	assert(delta >= 0.0 and position.is_finite() and goal.is_finite() and speed >= 0.0)
	assert(search_budget != null)
	_repath_remaining = maxf(_repath_remaining - delta, 0.0)
	var goal_cell := _resolve_feet_cell(goal)
	var path_failed := false
	if _repath_remaining <= 0.0 and search_budget.try_acquire():
		path_failed = not _rebuild_path(position, goal_cell)
	if _path_index >= _path.size():
		return VoxelPathFollowResult.new(Vector3.ZERO, false, path_failed)
	var waypoint := _waypoint_position(_path[_path_index])
	var flat_offset := Vector3(waypoint.x - position.x, 0.0, waypoint.z - position.z)
	if flat_offset.length_squared() < 0.09 and absf(waypoint.y - position.y) < 0.35:
		_path_index += 1
		if _path_index >= _path.size():
			return VoxelPathFollowResult.new(Vector3.ZERO, false, path_failed)
		waypoint = _waypoint_position(_path[_path_index])
		flat_offset = Vector3(waypoint.x - position.x, 0.0, waypoint.z - position.z)
	var should_jump := waypoint.y > position.y + 0.25 and on_ground
	if flat_offset.length_squared() < 0.0001:
		return VoxelPathFollowResult.new(Vector3.ZERO, should_jump, path_failed)
	return VoxelPathFollowResult.new(flat_offset.normalized() * speed, should_jump, path_failed)

func request_repath():
	_path.clear()
	_path_index = 0
	_repath_remaining = 0.0

func _rebuild_path(position: Vector3, goal_cell: Vector3i) -> bool:
	_repath_remaining = _repath_seconds
	var start_cell := _resolve_feet_cell(position)
	var result := VoxelPathfinder.find_path(
		_voxel_space,
		start_cell,
		goal_cell,
		_body_width,
		_body_height,
		_navigation_limits.get_max_search_radius(),
		_navigation_limits.get_max_search_nodes(),
	)
	if result.is_success():
		_path = result.path
		_path_index = 1 if _path.size() > 1 else _path.size()
		return true
	_path.clear()
	_path_index = 0
	return false

func _resolve_feet_cell(position: Vector3) -> Vector3i:
	var x := floori(position.x)
	var z := floori(position.z)
	var probe := Vector3(float(x) + 0.5, position.y + 0.08, float(z) + 0.5)
	var ground_y := VoxelBodySolver.get_ground_y(_voxel_space, probe, _body_width)
	if ground_y == VoxelSpace.NO_SURFACE_Y:
		ground_y = roundf(position.y)
	return Vector3i(x, roundi(ground_y), z)

func _waypoint_position(cell: Vector3i) -> Vector3:
	return Vector3(float(cell.x) + 0.5, float(cell.y), float(cell.z) + 0.5)
