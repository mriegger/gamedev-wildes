extends RefCounted
class_name SheepBrain

enum State {
	IDLE,
	WANDER,
	FLEE,
}

var state: State = State.IDLE

var _definition: SheepBehaviorDefinition
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _movement_goal: Vector3 = Vector3.ZERO
var _state_remaining: float = 0.0
var _flee_remaining: float = 0.0
var _flee_direction: Vector3 = Vector3.FORWARD

func _init(definition: SheepBehaviorDefinition, seed_value: int):
	assert(definition != null)
	_definition = definition
	_rng.seed = seed_value
	_state_remaining = _definition.idle_seconds

func advance(delta: float, self_position: Vector3):
	if _flee_remaining > 0.0:
		_flee_remaining = maxf(_flee_remaining - delta, 0.0)
		state = State.FLEE
		var flat_offset := Vector2(_movement_goal.x - self_position.x, _movement_goal.z - self_position.z)
		if flat_offset.length_squared() < 1.0:
			_movement_goal = self_position + _flee_direction * _definition.flee_goal_distance
		return

	if state == State.FLEE:
		state = State.IDLE
		_state_remaining = _definition.idle_seconds

	_state_remaining = maxf(_state_remaining - delta, 0.0)
	if state == State.IDLE:
		if _state_remaining <= 0.0:
			state = State.WANDER
			_state_remaining = _definition.wander_goal_seconds
			_movement_goal = _create_wander_goal(self_position)
		return

	if _state_remaining <= 0.0:
		state = State.IDLE
		_state_remaining = _definition.idle_seconds

func record_melee_contact(self_position: Vector3, world_hit_direction: Vector3):
	assert(world_hit_direction.is_finite() and not world_hit_direction.is_zero_approx())
	_flee_direction = Vector3(world_hit_direction.x, 0.0, world_hit_direction.z)
	if _flee_direction.is_zero_approx():
		var angle := _rng.randf_range(0.0, TAU)
		_flee_direction = Vector3(cos(angle), 0.0, sin(angle))
	else:
		_flee_direction = _flee_direction.normalized()
	_movement_goal = self_position + _flee_direction * _definition.flee_goal_distance
	_flee_remaining = _definition.flee_seconds
	_state_remaining = 0.0
	state = State.FLEE

func get_movement_goal() -> Vector3:
	assert(state != State.IDLE)
	return _movement_goal

func reject_movement_goal(self_position: Vector3):
	if state == State.FLEE:
		var turn := PI * 0.5 if _rng.randi_range(0, 1) == 0 else -PI * 0.5
		_flee_direction = _flee_direction.rotated(Vector3.UP, turn)
		_movement_goal = self_position + _flee_direction * _definition.flee_goal_distance
	else:
		state = State.IDLE
		_state_remaining = _definition.idle_seconds

func _create_wander_goal(self_position: Vector3) -> Vector3:
	var angle := _rng.randf_range(0.0, TAU)
	var distance := _rng.randf_range(_definition.wander_radius * 0.35, _definition.wander_radius)
	return self_position + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
