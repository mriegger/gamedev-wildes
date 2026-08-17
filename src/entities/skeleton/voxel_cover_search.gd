extends RefCounted
class_name VoxelCoverSearch

enum Status {
	SEARCHING,
	FOUND,
	EXHAUSTED,
}

const SEARCH_RADIUS: int = 30
const CANDIDATES_PER_TICK: int = 32

var status: Status:
	get:
		return _status

var _voxel_space: VoxelSpace
var _body_width: float
var _body_height: float
var _navigation_limits: EntityNavigationLimits
var _candidate_offsets: Array[Vector2i]
var _status: Status = Status.EXHAUSTED
var _origin: Vector3
var _origin_feet: Vector3i
var _observation: EntityTargetObservation
var _candidate_index: int = 0
var _target: Vector3 = Vector3.ZERO

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
	_candidate_offsets = _build_candidate_offsets()

func begin(origin: Vector3, observation: EntityTargetObservation) -> void:
	assert(origin.is_finite())
	assert(observation != null and observation.validate())
	_origin = origin
	_origin_feet = Vector3i(floori(origin.x), roundi(origin.y), floori(origin.z))
	_observation = EntityTargetObservation.new(
		observation.player_position,
		observation.camera_origin,
		observation.camera_forward,
		observation.camera_right,
	)
	_candidate_index = 0
	_target = Vector3.ZERO
	_status = Status.SEARCHING

func advance(search_budget: NavigationSearchBudget) -> Status:
	assert(search_budget != null)
	if _status != Status.SEARCHING:
		return _status
	var processed_columns := 0
	while processed_columns < CANDIDATES_PER_TICK and _candidate_index < _candidate_offsets.size():
		var offset := _candidate_offsets[_candidate_index]
		var candidate := _resolve_candidate(offset)
		processed_columns += 1
		if is_equal_approx(candidate.y, VoxelSpace.NO_SURFACE_Y):
			_candidate_index += 1
			continue
		if not VoxelCameraOcclusion.is_hidden(_voxel_space, _observation, candidate, _body_width, _body_height):
			_candidate_index += 1
			continue
		if not search_budget.try_acquire():
			return _status
		var result := VoxelPathfinder.find_path(
			_voxel_space,
			_origin_feet,
			Vector3i(floori(candidate.x), roundi(candidate.y), floori(candidate.z)),
			_body_width,
			_body_height,
			_navigation_limits.get_max_search_radius(),
			_navigation_limits.get_max_search_nodes(),
		)
		_candidate_index += 1
		if result.is_success():
			_target = candidate
			_status = Status.FOUND
			return _status
	if _candidate_index >= _candidate_offsets.size():
		_status = Status.EXHAUSTED
	return _status

func get_target() -> Vector3:
	assert(_status == Status.FOUND)
	return _target

func _resolve_candidate(offset: Vector2i) -> Vector3:
	var x := floori(_origin.x) + offset.x
	var z := floori(_origin.z) + offset.y
	var probe := Vector3(float(x) + 0.5, _origin.y + 0.08, float(z) + 0.5)
	var ground_y := VoxelBodySolver.get_ground_y(_voxel_space, probe, _body_width)
	return Vector3(probe.x, ground_y, probe.z)

func _build_candidate_offsets() -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	for x in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
		for z in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
			var offset := Vector2i(x, z)
			if offset.length_squared() <= SEARCH_RADIUS * SEARCH_RADIUS:
				offsets.append(offset)
	offsets.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		var left_distance := left.length_squared()
		var right_distance := right.length_squared()
		if left_distance != right_distance:
			return left_distance < right_distance
		if left.x != right.x:
			return left.x < right.x
		return left.y < right.y
	)
	return offsets
