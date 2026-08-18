extends RefCounted
class_name BirdBrain

enum State {
	CRUISE,
	DESCEND,
	GROUNDED_IDLE,
	GROUNDED_WALK,
	TAKEOFF,
}

var state: State = State.CRUISE

var _definition: BirdBehaviorDefinition
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _movement_goal: Vector3 = Vector3.ZERO
var _state_remaining: float = 0.0
var _walks_done: int = 0

func _init(definition: BirdBehaviorDefinition, seed_value: int):
	assert(definition != null and definition.validate("bird brain"))
	_definition = definition
	_rng.seed = seed_value

func advance(delta: float, self_position: Vector3, on_ground: bool, phase_goal_reached: bool) -> void:
	assert(is_finite(delta) and delta >= 0.0 and self_position.is_finite())
	match state:
		State.CRUISE:
			if phase_goal_reached:
				state = State.DESCEND
		State.DESCEND:
			if on_ground:
				_enter_idle()
		State.GROUNDED_IDLE:
			_state_remaining = maxf(_state_remaining - delta, 0.0)
			if _state_remaining <= 0.0:
				state = State.GROUNDED_WALK
				_state_remaining = _definition.grounded_walk_seconds
				_movement_goal = self_position + _sample_planar_offset(_definition.grounded_wander_radius)
		State.GROUNDED_WALK:
			_state_remaining = maxf(_state_remaining - delta, 0.0)
			var flat_offset := Vector2(_movement_goal.x - self_position.x, _movement_goal.z - self_position.z)
			if _state_remaining <= 0.0 or flat_offset.length_squared() < 0.16:
				_finish_walk()
		State.TAKEOFF:
			if phase_goal_reached:
				_walks_done = 0
				state = State.CRUISE

func sample_landing_offset() -> Vector2:
	var offset := _sample_planar_offset(_definition.landing_search_radius)
	return Vector2(offset.x, offset.z)

func sample_cruise_altitude() -> int:
	return _rng.randi_range(_definition.cruise_altitude_min_blocks, _definition.cruise_altitude_max_blocks)

func get_movement_goal() -> Vector3:
	assert(state == State.GROUNDED_WALK)
	return _movement_goal

func reject_movement_goal() -> void:
	if state == State.GROUNDED_WALK:
		_enter_idle()

func reject_flight_goal() -> void:
	if state in [State.CRUISE, State.DESCEND, State.TAKEOFF]:
		state = State.CRUISE

func reject_takeoff() -> void:
	if state == State.TAKEOFF:
		_walks_done = 0
		_enter_idle()

func _finish_walk() -> void:
	_walks_done += 1
	if _walks_done >= _definition.walks_before_takeoff:
		state = State.TAKEOFF
		_state_remaining = 0.0
	else:
		_enter_idle()

func _enter_idle() -> void:
	state = State.GROUNDED_IDLE
	_state_remaining = _rng.randf_range(_definition.landed_idle_min_seconds, _definition.landed_idle_max_seconds)

func _sample_planar_offset(radius: float) -> Vector3:
	var angle := _rng.randf_range(0.0, TAU)
	var distance := _rng.randf_range(radius * 0.35, radius)
	return Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
