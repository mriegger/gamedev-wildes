extends RefCounted
class_name WatcherBrain

enum State {
	WANDER,
	STALK,
	STARE,
	CHASE,
	ATTACK,
}

const MOVEMENT_GOAL_REACHED_DISTANCE_SQUARED: float = 0.16

var state: State = State.WANDER

var _definition: WatcherBehaviorDefinition
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _aggressive: bool = false
var _movement_goal: Vector3 = Vector3.ZERO
var _last_seen_position: Vector3 = Vector3.ZERO
var _target_memory_remaining: float = 0.0
var _wander_goal_remaining: float = 0.0
var _stalk_angle: float = 0.0
var _stalk_step_direction: float = 1.0
var _stalk_pause_remaining: float = 0.0
var _has_stalk_angle: bool = false
var _attack_remaining: float = 0.0
var _attack_cooldown_remaining: float = 0.0
var _attack_started: bool = false

func _init(definition: WatcherBehaviorDefinition, seed_value: int):
	assert(definition != null)
	_definition = definition
	_rng.seed = seed_value

func advance(
	delta: float,
	self_position: Vector3,
	player_position: Vector3,
	player_visible: bool,
) -> void:
	assert(is_finite(delta) and delta >= 0.0)
	assert(self_position.is_finite() and player_position.is_finite())
	_attack_started = false
	_attack_cooldown_remaining = maxf(_attack_cooldown_remaining - delta, 0.0)
	if _aggressive:
		_advance_aggression(delta, self_position, player_position)
		return
	_advance_awareness(delta, self_position, player_position, player_visible)

func record_player_attack() -> void:
	_aggressive = true
	_attack_started = false
	_attack_remaining = 0.0
	_target_memory_remaining = 0.0
	state = State.CHASE

func record_teleport_committed() -> void:
	assert(_aggressive)
	_attack_started = false
	_attack_remaining = 0.0
	state = State.CHASE

func reset_after_player_defeat() -> void:
	_aggressive = false
	_attack_started = false
	_attack_remaining = 0.0
	_attack_cooldown_remaining = 0.0
	_target_memory_remaining = 0.0
	_wander_goal_remaining = 0.0
	_stalk_pause_remaining = 0.0
	_has_stalk_angle = false
	state = State.WANDER

func is_aggressive() -> bool:
	return _aggressive

func get_movement_goal() -> Vector3:
	assert(state in [State.WANDER, State.STALK, State.STARE, State.CHASE])
	return _movement_goal

func consume_attack_started() -> bool:
	var started := _attack_started
	_attack_started = false
	return started

func reject_movement_goal(self_position: Vector3) -> void:
	assert(self_position.is_finite())
	if state == State.WANDER:
		_wander_goal_remaining = 0.0
	elif state == State.STALK:
		_advance_stalk_step()
		_update_stalk_goal(_last_seen_position)
	elif state == State.CHASE:
		_movement_goal = self_position

func _advance_aggression(delta: float, self_position: Vector3, player_position: Vector3) -> void:
	if _attack_remaining > 0.0:
		_attack_remaining = maxf(_attack_remaining - delta, 0.0)
		state = State.ATTACK
		return
	var reach := _definition.melee_profile.reach
	if self_position.distance_squared_to(player_position) <= reach * reach and _attack_cooldown_remaining <= 0.0:
		state = State.ATTACK
		_attack_started = true
		_attack_remaining = _definition.melee_profile.duration
		_attack_cooldown_remaining = _definition.melee_profile.cooldown
		return
	state = State.CHASE
	_movement_goal = player_position

func _advance_awareness(
	delta: float,
	self_position: Vector3,
	player_position: Vector3,
	player_visible: bool,
) -> void:
	var distance_squared := self_position.distance_squared_to(player_position)
	var detected := player_visible and distance_squared <= _definition.detection_range * _definition.detection_range
	if detected:
		_last_seen_position = player_position
		_target_memory_remaining = _definition.target_memory_seconds
	else:
		_target_memory_remaining = maxf(_target_memory_remaining - delta, 0.0)
	if distance_squared > _definition.forget_range * _definition.forget_range:
		_target_memory_remaining = 0.0
	if detected or _target_memory_remaining > 0.0:
		_advance_stalking(delta, self_position, _last_seen_position)
		return
	_has_stalk_angle = false
	_stalk_pause_remaining = 0.0
	state = State.WANDER
	_advance_wander(delta, self_position)

func _advance_stalking(delta: float, self_position: Vector3, target_position: Vector3) -> void:
	if not _has_stalk_angle:
		_begin_stalking(self_position, target_position)
	var distance_squared := self_position.distance_squared_to(target_position)
	if distance_squared < _definition.stalk_inner_radius * _definition.stalk_inner_radius:
		state = State.STARE
		_stalk_pause_remaining = _definition.stalk_pause_seconds
		return
	if distance_squared > _definition.stalk_outer_radius * _definition.stalk_outer_radius:
		_update_stalk_goal(target_position)
		state = State.STALK
		return
	if state == State.STARE:
		_stalk_pause_remaining = maxf(_stalk_pause_remaining - delta, 0.0)
		if _stalk_pause_remaining > 0.0:
			return
		_advance_stalk_step()
		_update_stalk_goal(target_position)
		state = State.STALK
		return
	_update_stalk_goal(target_position)
	if self_position.distance_squared_to(_movement_goal) <= MOVEMENT_GOAL_REACHED_DISTANCE_SQUARED:
		state = State.STARE
		_stalk_pause_remaining = _definition.stalk_pause_seconds
		return
	state = State.STALK

func _begin_stalking(self_position: Vector3, target_position: Vector3) -> void:
	var offset := self_position - target_position
	var angle_step := deg_to_rad(_definition.stalk_step_degrees)
	if Vector2(offset.x, offset.z).is_zero_approx():
		_stalk_angle = float(_rng.randi_range(0, 7)) * angle_step
	else:
		_stalk_angle = roundf(atan2(offset.z, offset.x) / angle_step) * angle_step
	_stalk_step_direction = -1.0 if _rng.randi_range(0, 1) == 0 else 1.0
	_has_stalk_angle = true
	_stalk_pause_remaining = 0.0
	_update_stalk_goal(target_position)

func _advance_stalk_step() -> void:
	_stalk_angle = wrapf(
		_stalk_angle + _stalk_step_direction * deg_to_rad(_definition.stalk_step_degrees),
		-PI,
		PI,
	)

func _update_stalk_goal(target_position: Vector3) -> void:
	_movement_goal = target_position + Vector3(
		cos(_stalk_angle) * _definition.stalk_radius,
		0.0,
		sin(_stalk_angle) * _definition.stalk_radius,
	)

func _advance_wander(delta: float, self_position: Vector3) -> void:
	_wander_goal_remaining = maxf(_wander_goal_remaining - delta, 0.0)
	if _wander_goal_remaining > 0.0:
		return
	var angle := _rng.randf_range(0.0, TAU)
	var distance := _rng.randf_range(_definition.wander_radius * 0.35, _definition.wander_radius)
	_movement_goal = self_position + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
	_wander_goal_remaining = _definition.wander_goal_seconds
