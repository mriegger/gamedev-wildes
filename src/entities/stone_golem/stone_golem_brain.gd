extends RefCounted
class_name StoneGolemBrain

const StoneGolemBehaviorDefinitionType := preload("res://entities/stone_golem/stone_golem_behavior_definition.gd")
const EntityTargetObservationType := preload("res://entities/entity_target_observation.gd")

enum State {
	DORMANT,
	CHASE,
	PUNCH,
	SLAM_WINDUP,
	SLAM_AIRBORNE,
	SLAM_RECOVERY,
}

var state: State = State.DORMANT

var _definition: StoneGolemBehaviorDefinitionType
var _target_memory_remaining: float = 0.0
var _movement_goal: Vector3 = Vector3.ZERO
var _punch_remaining: float = 0.0
var _punch_cooldown_remaining: float = 0.0
var _punch_started: bool = false
var _slam_cooldown_remaining: float = 0.0
var _slam_phase_remaining: float = 0.0
var _locked_slam_target: Vector3 = Vector3.ZERO
var _slam_started: bool = false
var _slam_launch_requested: bool = false

func _init(definition: StoneGolemBehaviorDefinitionType) -> void:
	assert(definition != null)
	assert(StoneGolemBehaviorDefinitionType.is_valid_movement(definition.movement_speed, definition.jump_velocity, definition.repath_seconds))
	assert(StoneGolemBehaviorDefinitionType.is_valid_gravity(definition.gravity))
	assert(StoneGolemBehaviorDefinitionType.is_valid_awareness(definition.detection_range, definition.forget_range, definition.target_memory_seconds))
	assert(definition.punch_profile != null)
	assert(definition.slam_profile != null)
	assert(StoneGolemBehaviorDefinitionType.is_valid_slam(definition.slam_trigger_range, definition.slam_windup_seconds, definition.slam_profile))
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
	_slam_started = false
	_slam_launch_requested = false
	_punch_cooldown_remaining = maxf(_punch_cooldown_remaining - delta, 0.0)
	_slam_cooldown_remaining = maxf(_slam_cooldown_remaining - delta, 0.0)
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
	if _advance_active_action(delta):
		return
	var planar_offset := observation.player_position - self_position
	planar_offset.y = 0.0
	var planar_distance_squared := planar_offset.length_squared()
	var fresh_visible := detected and visibility_sample_fresh
	if (
		fresh_visible
		and planar_distance_squared <= _definition.slam_trigger_range * _definition.slam_trigger_range
		and is_zero_approx(_slam_cooldown_remaining)
	):
		_start_slam(observation.player_position)
		return
	if (
		fresh_visible
		and _slam_cooldown_remaining > 0.0
		and planar_distance_squared <= _definition.punch_profile.reach * _definition.punch_profile.reach
		and is_zero_approx(_punch_cooldown_remaining)
	):
		_start_punch()
		return
	if detected or _target_memory_remaining > 0.0:
		state = State.CHASE
		return
	_movement_goal = Vector3.ZERO
	state = State.DORMANT

func _advance_active_action(delta: float) -> bool:
	if _punch_remaining > 0.0:
		_punch_remaining = maxf(_punch_remaining - delta, 0.0)
		if is_zero_approx(_punch_remaining):
			_punch_remaining = 0.0
		state = State.PUNCH
		return true
	if state == State.SLAM_WINDUP:
		if _slam_phase_remaining > 0.0:
			_slam_phase_remaining = maxf(_slam_phase_remaining - delta, 0.0)
		if is_zero_approx(_slam_phase_remaining):
			_slam_launch_requested = true
		return true
	if state == State.SLAM_AIRBORNE:
		return true
	if state == State.SLAM_RECOVERY and _slam_phase_remaining > 0.0:
		_slam_phase_remaining = maxf(_slam_phase_remaining - delta, 0.0)
		if is_zero_approx(_slam_phase_remaining):
			_slam_phase_remaining = 0.0
		return true
	return false

func consume_punch_started() -> bool:
	var started := _punch_started
	_punch_started = false
	return started

func consume_slam_started() -> bool:
	var started := _slam_started
	_slam_started = false
	return started

func consume_slam_launch_requested() -> bool:
	var requested := _slam_launch_requested
	_slam_launch_requested = false
	return requested

func get_locked_slam_target() -> Vector3:
	assert(state == State.SLAM_WINDUP or state == State.SLAM_AIRBORNE)
	return _locked_slam_target

func record_slam_launch_started() -> void:
	assert(state == State.SLAM_WINDUP)
	state = State.SLAM_AIRBORNE
	_slam_phase_remaining = 0.0

func abort_slam_launch() -> void:
	assert(state == State.SLAM_WINDUP)
	state = State.CHASE if _target_memory_remaining > 0.0 else State.DORMANT
	_slam_phase_remaining = 0.0
	_locked_slam_target = Vector3.ZERO

func record_slam_landed() -> void:
	assert(state == State.SLAM_AIRBORNE)
	state = State.SLAM_RECOVERY
	_slam_phase_remaining = _definition.get_slam_recovery_seconds()
	_locked_slam_target = Vector3.ZERO

func _start_punch() -> void:
	state = State.PUNCH
	_punch_started = true
	_punch_remaining = _definition.punch_profile.duration
	_punch_cooldown_remaining = _definition.punch_profile.cooldown

func _start_slam(target_position: Vector3) -> void:
	state = State.SLAM_WINDUP
	_slam_started = true
	_slam_phase_remaining = _definition.slam_windup_seconds
	_slam_cooldown_remaining = _definition.slam_profile.cooldown
	_locked_slam_target = target_position

func get_movement_goal() -> Vector3:
	assert(state == State.CHASE)
	return _movement_goal

func is_alerted() -> bool:
	return state != State.DORMANT
