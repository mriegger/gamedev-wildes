extends RefCounted
class_name StoneGolemBrain

const StoneGolemBehaviorDefinitionType := preload("res://entities/stone_golem/stone_golem_behavior_definition.gd")
const EntityTargetObservationType := preload("res://entities/entity_target_observation.gd")

enum State {
	DORMANT,
	CHASE,
}

var state: State = State.DORMANT

var _definition: StoneGolemBehaviorDefinitionType
var _target_memory_remaining: float = 0.0
var _movement_goal: Vector3 = Vector3.ZERO

func _init(definition: StoneGolemBehaviorDefinitionType) -> void:
	assert(definition != null)
	assert(StoneGolemBehaviorDefinitionType.is_valid_movement(definition.movement_speed, definition.jump_velocity, definition.repath_seconds))
	assert(StoneGolemBehaviorDefinitionType.is_valid_gravity(definition.gravity))
	assert(StoneGolemBehaviorDefinitionType.is_valid_awareness(definition.detection_range, definition.forget_range, definition.target_memory_seconds))
	_definition = definition

func advance(delta: float, self_position: Vector3, observation: EntityTargetObservationType, player_visible: bool) -> void:
	assert(is_finite(delta) and delta >= 0.0)
	assert(self_position.is_finite())
	assert(observation != null and observation.validate())
	var distance_squared := self_position.distance_squared_to(observation.player_position)
	if distance_squared > _definition.forget_range * _definition.forget_range:
		_target_memory_remaining = 0.0
		_movement_goal = Vector3.ZERO
		state = State.DORMANT
		return
	if player_visible and distance_squared <= _definition.detection_range * _definition.detection_range:
		_movement_goal = observation.player_position
		_target_memory_remaining = _definition.target_memory_seconds
		state = State.CHASE
		return
	_target_memory_remaining = maxf(_target_memory_remaining - delta, 0.0)
	if _target_memory_remaining > 0.0:
		state = State.CHASE
		return
	_movement_goal = Vector3.ZERO
	state = State.DORMANT

func get_movement_goal() -> Vector3:
	assert(state == State.CHASE)
	return _movement_goal

func is_alerted() -> bool:
	return state == State.CHASE
