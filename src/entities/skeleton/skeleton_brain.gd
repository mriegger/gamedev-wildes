extends RefCounted
class_name SkeletonBrain

enum State {
	ROAM,
	SEARCH_COVER,
	MOVE_TO_COVER,
	HIDE,
	SPRINT,
	ATTACK,
}

var state: State = State.ROAM

var _definition: SkeletonBehaviorDefinition
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _movement_goal: Vector3 = Vector3.ZERO
var _last_player_position: Vector3 = Vector3.ZERO
var _roam_goal_remaining: float = 0.0
var _cover_retry_remaining: float = 0.0
var _cover_revalidation_remaining: float = 0.0
var _cover_search_pending: bool = false
var _cover_search_in_progress: bool = false
var _attack_remaining: float = 0.0
var _attack_cooldown_remaining: float = 0.0
var _attack_started: bool = false
var _post_attack_retreat_required: bool = false

func _init(definition: SkeletonBehaviorDefinition, seed_value: int):
	assert(definition != null and definition.melee_profile != null)
	_definition = definition
	_rng.seed = seed_value

func advance(delta: float, self_position: Vector3, player_position: Vector3, current_position_hidden: bool):
	assert(is_finite(delta) and delta >= 0.0)
	assert(self_position.is_finite() and player_position.is_finite())
	_attack_started = false
	_attack_cooldown_remaining = maxf(_attack_cooldown_remaining - delta, 0.0)
	_last_player_position = player_position
	if _attack_remaining > 0.0:
		_attack_remaining = maxf(_attack_remaining - delta, 0.0)
		if is_zero_approx(_attack_remaining):
			_attack_remaining = 0.0
			_post_attack_retreat_required = true
		state = State.ATTACK
		return
	if not is_player_in_detection_range(self_position, player_position):
		if state != State.ROAM:
			_enter_roam(self_position)
		else:
			_advance_roam(delta, self_position)
		return
	if state == State.ATTACK:
		if _post_attack_retreat_required:
			_request_cover_search()
		else:
			_enter_sprint()
	var within_ambush_range := _is_player_in_ambush_range(self_position, player_position)
	if within_ambush_range and not _post_attack_retreat_required and state != State.SPRINT:
		_enter_sprint()
	match state:
		State.ROAM:
			if current_position_hidden:
				_enter_hide()
			else:
				_request_cover_search()
		State.MOVE_TO_COVER, State.HIDE:
			_cover_revalidation_remaining = maxf(_cover_revalidation_remaining - delta, 0.0)
		State.SPRINT:
			_movement_goal = player_position
			if within_ambush_range:
				_cancel_cover_search()
				_cover_retry_remaining = _definition.cover_retry_seconds
			else:
				_advance_cover_retry(delta)
			var profile := _definition.melee_profile
			if self_position.distance_squared_to(player_position) <= profile.reach * profile.reach and is_zero_approx(_attack_cooldown_remaining):
				_start_attack()

func get_movement_goal() -> Vector3:
	return _movement_goal

func is_player_in_detection_range(self_position: Vector3, player_position: Vector3) -> bool:
	var horizontal_offset := Vector2(player_position.x - self_position.x, player_position.z - self_position.z)
	return horizontal_offset.length_squared() <= _definition.detection_range * _definition.detection_range

func _is_player_in_ambush_range(self_position: Vector3, player_position: Vector3) -> bool:
	var horizontal_offset := Vector2(player_position.x - self_position.x, player_position.z - self_position.z)
	return horizontal_offset.length_squared() <= _definition.ambush_range * _definition.ambush_range

func needs_detection_occlusion_check(self_position: Vector3, player_position: Vector3) -> bool:
	return state == State.ROAM and is_player_in_detection_range(self_position, player_position) and not _is_player_in_ambush_range(self_position, player_position)

func needs_cover_search() -> bool:
	return _is_cover_search_state() and _cover_search_pending

func is_cover_search_in_progress() -> bool:
	return _is_cover_search_state() and _cover_search_in_progress

func record_cover_search_started():
	assert(needs_cover_search())
	_cover_search_pending = false
	_cover_search_in_progress = true

func record_cover_found(target: Vector3):
	assert(_is_cover_search_state() and _cover_search_in_progress)
	assert(target.is_finite())
	_cover_search_pending = false
	_cover_search_in_progress = false
	_movement_goal = target
	state = State.MOVE_TO_COVER
	_cover_retry_remaining = 0.0
	_reset_cover_revalidation()

func record_cover_exhausted():
	assert(_is_cover_search_state() and _cover_search_in_progress)
	_cover_search_pending = false
	_cover_search_in_progress = false
	_post_attack_retreat_required = false
	_enter_sprint()

func record_cover_arrival(current_position_hidden: bool):
	assert(state == State.MOVE_TO_COVER)
	if current_position_hidden:
		_post_attack_retreat_required = false
		_enter_hide()
	else:
		_request_cover_search()

func reject_cover_goal():
	assert(state == State.MOVE_TO_COVER)
	_request_cover_search()

func is_cover_revalidation_due() -> bool:
	return (state == State.MOVE_TO_COVER or state == State.HIDE) and is_zero_approx(_cover_revalidation_remaining)

func record_cover_revalidated(is_hidden: bool):
	assert(is_cover_revalidation_due())
	if is_hidden:
		_reset_cover_revalidation()
	else:
		_request_cover_search()

func consume_attack_started() -> bool:
	var started := _attack_started
	_attack_started = false
	return started

func reject_movement_goal(self_position: Vector3):
	if state == State.ROAM:
		_select_roam_goal(self_position)

func _advance_roam(delta: float, self_position: Vector3):
	_roam_goal_remaining = maxf(_roam_goal_remaining - delta, 0.0)
	if _roam_goal_remaining <= 0.0:
		_select_roam_goal(self_position)

func _advance_cover_retry(delta: float):
	if _cover_search_pending or _cover_search_in_progress:
		return
	_cover_retry_remaining = maxf(_cover_retry_remaining - delta, 0.0)
	if is_zero_approx(_cover_retry_remaining):
		_cover_search_pending = true

func _request_cover_search():
	state = State.SEARCH_COVER
	_cover_search_pending = true
	_cover_search_in_progress = false
	_cover_retry_remaining = 0.0
	_cover_revalidation_remaining = 0.0

func _enter_sprint():
	state = State.SPRINT
	_cancel_cover_search()
	_movement_goal = _last_player_position
	_cover_retry_remaining = _definition.cover_retry_seconds
	_cover_revalidation_remaining = 0.0

func _enter_hide():
	state = State.HIDE
	_cancel_cover_search()
	_cover_retry_remaining = 0.0
	_reset_cover_revalidation()

func _enter_roam(self_position: Vector3):
	state = State.ROAM
	_cancel_cover_search()
	_post_attack_retreat_required = false
	_cover_retry_remaining = 0.0
	_cover_revalidation_remaining = 0.0
	_select_roam_goal(self_position)

func _start_attack():
	var profile := _definition.melee_profile
	state = State.ATTACK
	_attack_started = true
	_attack_remaining = profile.duration
	_attack_cooldown_remaining = profile.cooldown
	_cancel_cover_search()
	_cover_retry_remaining = 0.0
	_cover_revalidation_remaining = 0.0

func _cancel_cover_search():
	_cover_search_pending = false
	_cover_search_in_progress = false

func _reset_cover_revalidation():
	_cover_revalidation_remaining = _definition.cover_revalidation_seconds

func _is_cover_search_state() -> bool:
	return state == State.SEARCH_COVER or state == State.SPRINT

func _select_roam_goal(self_position: Vector3):
	var angle := _rng.randf_range(0.0, TAU)
	var distance := _rng.randf_range(_definition.roam_radius * 0.35, _definition.roam_radius)
	_movement_goal = self_position + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
	_roam_goal_remaining = _definition.roam_goal_seconds
