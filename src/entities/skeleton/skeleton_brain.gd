extends RefCounted
class_name SkeletonBrain

enum State {
	ROAM,
	SEARCH_COVER,
	MOVE_TO_COVER,
	HIDE,
}

var state: State = State.ROAM

var _definition: SkeletonBehaviorDefinition
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _movement_goal: Vector3 = Vector3.ZERO
var _roam_goal_remaining: float = 0.0
var _cover_search_pending: bool = false

func _init(definition: SkeletonBehaviorDefinition, seed_value: int):
	assert(definition != null)
	_definition = definition
	_rng.seed = seed_value

func advance(delta: float, self_position: Vector3, player_position: Vector3, current_position_hidden: bool):
	if is_player_in_detection_range(self_position, player_position):
		match state:
			State.ROAM:
				if current_position_hidden:
					state = State.HIDE
				else:
					_request_cover_search()
			State.SEARCH_COVER:
				if current_position_hidden:
					state = State.HIDE
					_cover_search_pending = false
			State.HIDE:
				if not current_position_hidden:
					_request_cover_search()
		return
	if state != State.ROAM:
		state = State.ROAM
		_cover_search_pending = false
		_select_roam_goal(self_position)
		return
	_roam_goal_remaining = maxf(_roam_goal_remaining - delta, 0.0)
	if _roam_goal_remaining <= 0.0:
		_select_roam_goal(self_position)

func get_movement_goal() -> Vector3:
	return _movement_goal

func is_player_in_detection_range(self_position: Vector3, player_position: Vector3) -> bool:
	var horizontal_offset := Vector2(player_position.x - self_position.x, player_position.z - self_position.z)
	return horizontal_offset.length_squared() <= _definition.detection_range * _definition.detection_range

func needs_cover_search() -> bool:
	return state == State.SEARCH_COVER and _cover_search_pending

func record_cover_search_started():
	assert(state == State.SEARCH_COVER and _cover_search_pending)
	_cover_search_pending = false

func record_cover_found(target: Vector3):
	assert(state == State.SEARCH_COVER and not _cover_search_pending)
	assert(target.is_finite())
	_movement_goal = target
	state = State.MOVE_TO_COVER

func record_cover_exhausted():
	assert(state == State.SEARCH_COVER and not _cover_search_pending)
	_cover_search_pending = true

func record_cover_arrival(current_position_hidden: bool):
	assert(state == State.MOVE_TO_COVER)
	if current_position_hidden:
		state = State.HIDE
	else:
		_request_cover_search()

func reject_cover_goal():
	assert(state == State.MOVE_TO_COVER)
	_request_cover_search()

func reject_movement_goal(self_position: Vector3):
	if state == State.ROAM:
		_select_roam_goal(self_position)

func _request_cover_search():
	state = State.SEARCH_COVER
	_cover_search_pending = true

func _select_roam_goal(self_position: Vector3):
	var angle := _rng.randf_range(0.0, TAU)
	var distance := _rng.randf_range(_definition.roam_radius * 0.35, _definition.roam_radius)
	_movement_goal = self_position + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
	_roam_goal_remaining = _definition.roam_goal_seconds
