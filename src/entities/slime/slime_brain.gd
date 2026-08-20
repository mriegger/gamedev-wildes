extends RefCounted
class_name SlimeBrain

enum State {
	WANDER,
	CHASE,
	ATTACHED,
}

var state: State = State.WANDER

var _definition: SlimeBehaviorDefinition
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_seen_position: Vector3 = Vector3.ZERO
var _wander_goal: Vector3 = Vector3.ZERO
var _target_memory_remaining: float = 0.0
var _wander_goal_remaining: float = 0.0
var _hop_remaining: float
var _hop_started: bool = false

func _init(definition: SlimeBehaviorDefinition, seed_value: int) -> void:
	assert(definition != null)
	_definition = definition
	_rng.seed = seed_value
	_hop_remaining = definition.hop_interval_seconds

func advance(
	delta: float,
	self_position: Vector3,
	player_position: Vector3,
	player_visible: bool,
	attached: bool,
	on_ground: bool,
) -> void:
	assert(is_finite(delta) and delta >= 0.0)
	assert(self_position.is_finite() and player_position.is_finite())
	_hop_started = false
	if attached:
		if state != State.ATTACHED:
			_hop_remaining = _definition.hop_interval_seconds
		state = State.ATTACHED
		return

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
		state = State.CHASE
	else:
		state = State.WANDER
		_wander_goal_remaining -= delta
		if _wander_goal_remaining <= 0.0:
			_sample_wander_goal(self_position)

	if not on_ground:
		return
	_hop_remaining -= delta
	if _hop_remaining <= 0.0:
		_hop_started = true
		_hop_remaining = _definition.hop_interval_seconds

func get_movement_goal() -> Vector3:
	return _last_seen_position if state == State.CHASE else _wander_goal

func consume_hop_started() -> bool:
	var started := _hop_started
	_hop_started = false
	return started

func reject_movement_goal(self_position: Vector3) -> void:
	if state != State.WANDER:
		return
	_sample_wander_goal(self_position)

func _sample_wander_goal(self_position: Vector3) -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var distance := _rng.randf_range(_definition.wander_radius * 0.35, _definition.wander_radius)
	_wander_goal = self_position + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
	_wander_goal_remaining = _definition.wander_goal_seconds
