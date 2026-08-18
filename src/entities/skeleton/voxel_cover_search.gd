extends RefCounted
class_name VoxelCoverSearch

enum Status {
	SEARCHING,
	FOUND,
	EXHAUSTED,
}

const SEARCH_RADIUS: int = 30
const CANDIDATES_PER_TICK: int = 32
const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i(-1, 0),
	Vector2i(0, -1),
	Vector2i(0, 1),
	Vector2i(1, 0),
]

class CandidateEntry:
	var column: Vector2i
	var distance_squared: float

	func _init(p_column: Vector2i, p_distance_squared: float) -> void:
		column = p_column
		distance_squared = p_distance_squared

var status: Status:
	get:
		return _status

var _voxel_space: VoxelSpace
var _body_width: float
var _body_height: float
var _navigation_limits: EntityNavigationLimits
var _status: Status = Status.EXHAUSTED
var _elevation_offsets: Array[int] = []
var _origin: Vector3
var _origin_feet: Vector3i
var _candidate_exclusion_origin: Vector2
var _observation: EntityTargetObservation
var _candidate_frontier: Array[CandidateEntry] = []
var _queued_columns: Dictionary = {}
var _current_column: Vector2i
var _has_current_column: bool = false
var _current_elevations: Array[int] = []
var _elevation_index: int = 0
var _target: Vector3 = Vector3.ZERO
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
	_elevation_offsets = _build_elevation_offsets()

func begin(origin: Vector3, candidate_exclusion_origin: Vector3, observation: EntityTargetObservation, minimum_candidate_distance: float) -> void:
	assert(origin.is_finite())
	assert(candidate_exclusion_origin.is_finite())
	assert(observation != null and observation.validate())
	assert(is_finite(minimum_candidate_distance) and minimum_candidate_distance >= 0.0)
	_origin = origin
	_origin_feet = Vector3i(floori(origin.x), roundi(origin.y), floori(origin.z))
	_candidate_exclusion_origin = Vector2(candidate_exclusion_origin.x, candidate_exclusion_origin.z)
	_minimum_candidate_distance_squared = minimum_candidate_distance * minimum_candidate_distance
	_observation = EntityTargetObservation.new(
		observation.player_position,
		observation.camera_origin,
		observation.camera_forward,
		observation.camera_right,
	)
	_candidate_frontier.clear()
	_queued_columns.clear()
	_queue_nearest_columns()
	_has_current_column = false
	_current_elevations.clear()
	_elevation_index = 0
	_target = Vector3.ZERO
	_status = Status.SEARCHING

func advance(search_budget: NavigationSearchBudget) -> Status:
	assert(search_budget != null)
	if _status != Status.SEARCHING:
		return _status
	var processed_columns := 0
	while processed_columns < CANDIDATES_PER_TICK:
		if not _has_current_column:
			var entry := _take_next_entry()
			if entry == null:
				_status = Status.EXHAUSTED
				return _status
			var candidate_center := Vector2(float(entry.column.x) + 0.5, float(entry.column.y) + 0.5)
			if candidate_center.distance_squared_to(_candidate_exclusion_origin) < _minimum_candidate_distance_squared:
				processed_columns += 1
				continue
			_current_column = entry.column
			_has_current_column = true
			_current_elevations = _resolve_candidate_elevations(_current_column)
			_elevation_index = 0
		processed_columns += 1
		while _elevation_index < _current_elevations.size():
			var candidate_feet := Vector3i(
				_current_column.x,
				_current_elevations[_elevation_index],
				_current_column.y,
			)
			var candidate := Vector3(
				float(candidate_feet.x) + 0.5,
				float(candidate_feet.y),
				float(candidate_feet.z) + 0.5,
			)
			if not VoxelCameraOcclusion.is_hidden(_voxel_space, _observation, candidate, _body_width, _body_height):
				_elevation_index += 1
				continue
			if not search_budget.try_acquire():
				return _status
			var result := VoxelPathfinder.find_path(
				_voxel_space,
				_origin_feet,
				candidate_feet,
				_body_width,
				_body_height,
				_navigation_limits.get_max_search_radius(),
				_navigation_limits.get_max_search_nodes(),
			)
			_elevation_index += 1
			if result.is_success():
				_target = candidate
				_status = Status.FOUND
				return _status
			return _status
		_has_current_column = false
	return _status

func get_target() -> Vector3:
	assert(_status == Status.FOUND)
	return _target

func _resolve_candidate_elevations(column: Vector2i) -> Array[int]:
	var elevations: Array[int] = []
	for offset in _elevation_offsets:
		_append_walkable_elevation(elevations, column, _origin_feet.y + offset)
	return elevations

func _append_walkable_elevation(elevations: Array[int], column: Vector2i, elevation: int) -> void:
	var feet := Vector3i(column.x, elevation, column.y)
	var body_position := Vector3(float(column.x) + 0.5, float(elevation), float(column.y) + 0.5)
	if not VoxelBodySolver.has_solid_support(_voxel_space, body_position, _body_width):
		return
	if VoxelPathfinder.is_walkable(_voxel_space, feet, _body_width, _body_height):
		elevations.append(elevation)

func _build_elevation_offsets() -> Array[int]:
	var offsets: Array[int] = [0]
	for delta in range(1, _navigation_limits.get_max_search_radius() + 1):
		offsets.append(-delta)
		offsets.append(delta)
	return offsets

func _queue_nearest_columns() -> void:
	var floor_x := floori(_origin.x)
	var floor_z := floori(_origin.z)
	var x_columns: Array[int] = [floor_x]
	var z_columns: Array[int] = [floor_z]
	if _origin.x == float(floor_x):
		x_columns.push_front(floor_x - 1)
	if _origin.z == float(floor_z):
		z_columns.push_front(floor_z - 1)
	for x in x_columns:
		for z in z_columns:
			_queue_column(Vector2i(x, z))

func _queue_column(column: Vector2i) -> void:
	if _queued_columns.has(column):
		return
	_queued_columns[column] = true
	var center := Vector2(float(column.x) + 0.5, float(column.y) + 0.5)
	var distance_squared := center.distance_squared_to(Vector2(_origin.x, _origin.z))
	_heap_push(CandidateEntry.new(column, distance_squared))

func _take_next_entry() -> CandidateEntry:
	if _candidate_frontier.is_empty():
		return null
	var entry := _heap_pop()
	if entry.distance_squared > float(SEARCH_RADIUS * SEARCH_RADIUS):
		return null
	for direction in CARDINAL_DIRECTIONS:
		_queue_column(entry.column + direction)
	return entry

func _heap_push(entry: CandidateEntry) -> void:
	_candidate_frontier.append(entry)
	var index := _candidate_frontier.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if not _entry_precedes(_candidate_frontier[index], _candidate_frontier[parent]):
			break
		var parent_entry := _candidate_frontier[parent]
		_candidate_frontier[parent] = _candidate_frontier[index]
		_candidate_frontier[index] = parent_entry
		index = parent

func _heap_pop() -> CandidateEntry:
	var first := _candidate_frontier[0]
	var last := _candidate_frontier.pop_back() as CandidateEntry
	if not _candidate_frontier.is_empty():
		_candidate_frontier[0] = last
		var index := 0
		while true:
			var left := index * 2 + 1
			var right := left + 1
			var smallest := index
			if left < _candidate_frontier.size() and _entry_precedes(_candidate_frontier[left], _candidate_frontier[smallest]):
				smallest = left
			if right < _candidate_frontier.size() and _entry_precedes(_candidate_frontier[right], _candidate_frontier[smallest]):
				smallest = right
			if smallest == index:
				break
			var smallest_entry := _candidate_frontier[smallest]
			_candidate_frontier[smallest] = _candidate_frontier[index]
			_candidate_frontier[index] = smallest_entry
			index = smallest
	return first

func _entry_precedes(left: CandidateEntry, right: CandidateEntry) -> bool:
	if left.distance_squared != right.distance_squared:
		return left.distance_squared < right.distance_squared
	if left.column.x != right.column.x:
		return left.column.x < right.column.x
	return left.column.y < right.column.y
