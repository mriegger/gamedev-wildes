extends RefCounted
class_name StoneGolemBrain

const StoneGolemBehaviorDefinitionType := preload("res://entities/stone_golem/stone_golem_behavior_definition.gd")
const EntityTargetObservationType := preload("res://entities/entity_target_observation.gd")

enum State {
	DORMANT,
	CHASE,
	PUNCH,
}

var state: State = State.DORMANT

var _definition: StoneGolemBehaviorDefinitionType
var _target_memory_remaining: float = 0.0
var _movement_goal: Vector3 = Vector3.ZERO
var _punch_remaining: float = 0.0
var _punch_cooldown_remaining: float = 0.0
var _punch_started: bool = false

func _init(definition: StoneGolemBehaviorDefinitionType) -> void:
	assert(definition != null)
	assert(StoneGolemBehaviorDefinitionType.is_valid_movement(definition.movement_speed, definition.jump_velocity, definition.repath_seconds))
	assert(StoneGolemBehaviorDefinitionType.is_valid_gravity(definition.gravity))
	assert(StoneGolemBehaviorDefinitionType.is_valid_awareness(definition.detection_range, definition.forget_range, definition.target_memory_seconds))
	assert(definition.punch_profile != null)
	_definition = definition

func advance(
	delta: float,
	self_position: Vector3,
	observation: EntityTargetObservationType,
	player_visible: bool,
	visibility_sample_fresh: bool,
) -> void:
	assert(is_finite(delta) and delta >= 0.0)
	assert(self_position.is_finite())
	assert(observation != null and observation.validate())
	_punch_started = false
	_punch_cooldown_remaining = maxf(_punch_cooldown_remaining - delta, 0.0)
	var distance_squared := self_position.distance_squared_to(observation.player_position)
	var detected := player_visible and distance_squared <= _definition.detection_range * _definition.detection_range
	if detected:
		if visibility_sample_fresh:
			_movement_goal = observation.player_position
		_target_memory_remaining = _definition.target_memory_seconds
	elif distance_squared > _definition.forget_range * _definition.forget_range:
		_target_memory_remaining = 0.0
		_movement_goal = Vector3.ZERO
	else:
		_target_memory_remaining = maxf(_target_memory_remaining - delta, 0.0)
	if _punch_remaining > 0.0:
		_punch_remaining = maxf(_punch_remaining - delta, 0.0)
		if is_zero_approx(_punch_remaining):
			_punch_remaining = 0.0
		state = State.PUNCH
		return
	if detected and distance_squared <= _definition.punch_profile.reach * _definition.punch_profile.reach and is_zero_approx(_punch_cooldown_remaining):
		_start_punch()
		return
	if detected or _target_memory_remaining > 0.0:
		state = State.CHASE
		return
	_movement_goal = Vector3.ZERO
	state = State.DORMANT

func consume_punch_started() -> bool:
	var started := _punch_started
	_punch_started = false
	return started

func _start_punch() -> void:
	state = State.PUNCH
	_punch_started = true
	_punch_remaining = _definition.punch_profile.duration
	_punch_cooldown_remaining = _definition.punch_profile.cooldown

func get_movement_goal() -> Vector3:
	assert(state == State.CHASE)
	return _movement_goal

func is_alerted() -> bool:
	return state == State.CHASE or state == State.PUNCH
