extends RefCounted
class_name GroundMeleeEnemyBrain

enum State {
	WANDER,
	CHASE,
	ATTACK,
}

var state: State = State.WANDER

var _definition: GroundMeleeEnemyBehaviorDefinition
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_seen_position: Vector3 = Vector3.ZERO
var _wander_goal: Vector3 = Vector3.ZERO
var _target_memory_remaining: float = 0.0
var _wander_goal_remaining: float = 0.0
var _attack_remaining: float = 0.0
var _attack_cooldown_remaining: float = 0.0
var _attack_started: bool = false

func _init(definition: GroundMeleeEnemyBehaviorDefinition, seed_value: int):
	assert(definition != null)
	_definition = definition
	_rng.seed = seed_value

func advance(
	delta: float,
	self_position: Vector3,
	player_position: Vector3,
	player_visible: bool,
	visibility_sample_fresh: bool,
):
	_attack_started = false
	_attack_cooldown_remaining = maxf(_attack_cooldown_remaining - delta, 0.0)

	var distance_squared := self_position.distance_squared_to(player_position)
	var detected := player_visible and distance_squared <= _definition.detection_range * _definition.detection_range
	if detected:
		if visibility_sample_fresh:
			_last_seen_position = player_position
		_target_memory_remaining = _definition.target_memory_seconds
	else:
		_target_memory_remaining = maxf(_target_memory_remaining - delta, 0.0)
	if distance_squared > _definition.forget_range * _definition.forget_range:
		_target_memory_remaining = 0.0

	if _attack_remaining > 0.0:
		_attack_remaining = maxf(_attack_remaining - delta, 0.0)
		state = State.ATTACK
		return
	var melee_profile := _definition.melee_profile
	if detected and distance_squared <= melee_profile.reach * melee_profile.reach and _attack_cooldown_remaining <= 0.0:
		state = State.ATTACK
		_attack_started = true
		_attack_remaining = melee_profile.duration
		_attack_cooldown_remaining = melee_profile.cooldown
		return

	if detected or _target_memory_remaining > 0.0:
		state = State.CHASE
		return

	_advance_wander(delta, self_position)

func advance_ambient(delta: float, self_position: Vector3) -> void:
	assert(is_finite(delta) and delta >= 0.0)
	assert(self_position.is_finite())
	_attack_started = false
	_attack_remaining = 0.0
	_target_memory_remaining = 0.0
	_advance_wander(delta, self_position)

func _advance_wander(delta: float, self_position: Vector3) -> void:
	state = State.WANDER
	_wander_goal_remaining -= delta
	if _wander_goal_remaining <= 0.0:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(_definition.wander_radius * 0.35, _definition.wander_radius)
		_wander_goal = self_position + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		_wander_goal_remaining = _definition.wander_goal_seconds

func get_movement_goal() -> Vector3:
	if state == State.CHASE:
		return _last_seen_position
	return _wander_goal

func consume_attack_started() -> bool:
	var started := _attack_started
	_attack_started = false
	return started

func is_alerted() -> bool:
	return state != State.WANDER

func alert_to_player(player_position: Vector3) -> void:
	assert(player_position.is_finite())
	if is_alerted():
		return
	_last_seen_position = player_position
	_target_memory_remaining = _definition.target_memory_seconds
	state = State.CHASE

func reject_wander_goal():
	if state == State.WANDER:
		_wander_goal_remaining = 0.0
