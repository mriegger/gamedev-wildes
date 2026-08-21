extends EntityActor
class_name WatcherActor

const TimedMeleeContactType := preload("res://combat/timed_melee_contact.gd")

const VISION_SAMPLE_INTERVAL_SECONDS: float = 0.125
const VISION_PHASE_COUNT: int = 8

var brain: WatcherBrain

var _behavior: WatcherBehaviorDefinition
var _watcher_animation: WatcherAnimationDriver
var _path_follower: VoxelPathFollower
var _timed_melee_contact := TimedMeleeContactType.new()
var _player_visible: bool = false
var _vision_sample_remaining: float = 0.0
var _teleport_sequence: int = 0
var _teleport_departure: CPUParticles3D
var _teleport_arrival: CPUParticles3D

func supports_behavior(behavior: EntityBehaviorDefinition) -> bool:
	return behavior is WatcherBehaviorDefinition

func setup(
	p_runtime_id: int,
	p_definition: EntityDefinition,
	p_voxel_space: VoxelSpace,
	p_behavior_seed: int,
	navigation_limits: EntityNavigationLimits,
) -> void:
	super.setup(p_runtime_id, p_definition, p_voxel_space, p_behavior_seed, navigation_limits)
	_behavior = p_definition.behavior as WatcherBehaviorDefinition
	assert(_behavior != null)
	brain = WatcherBrain.new(_behavior, p_behavior_seed)
	_path_follower = VoxelPathFollower.new(
		voxel_space,
		definition.body_width,
		definition.body_height,
		_behavior.repath_seconds,
		navigation_limits,
	)
	_watcher_animation = animation_driver as WatcherAnimationDriver
	assert(_watcher_animation != null)
	_teleport_departure = get_node(^"TeleportDeparture") as CPUParticles3D
	_teleport_arrival = get_node(^"TeleportArrival") as CPUParticles3D
	assert(_teleport_departure != null and _teleport_arrival != null)
	max_speed = _behavior.wander_speed
	_player_visible = false
	_vision_sample_remaining = VISION_SAMPLE_INTERVAL_SECONDS * float(runtime_id % VISION_PHASE_COUNT) / float(VISION_PHASE_COUNT)
	_teleport_sequence = 0

func tick(
	delta: float,
	observation: EntityTargetObservation,
	separation_velocity: Vector3,
	navigation_search_budget: NavigationSearchBudget,
) -> void:
	assert(brain != null and voxel_space != null)
	assert(observation != null and observation.validate())
	_emit_melee_contact(_timed_melee_contact.advance(delta))
	var player_position := observation.player_position
	var visible := false
	if not brain.is_aggressive():
		visible = _sample_player_visibility(delta, player_position)
	var previous_state := brain.state
	brain.advance(delta, global_position, player_position, visible)
	if brain.state != previous_state and brain.state not in [WatcherBrain.State.ATTACK, WatcherBrain.State.STARE]:
		_path_follower.request_repath()
	var aggressive := brain.is_aggressive()
	var stalking := brain.state in [WatcherBrain.State.STALK, WatcherBrain.State.STARE]
	_watcher_animation.set_aggressive(aggressive)
	_watcher_animation.set_stalking(stalking)
	if brain.consume_attack_started():
		play_attack(_behavior.melee_profile.duration)
		_emit_melee_contact(_timed_melee_contact.arm(_behavior.melee_profile))
	var desired_velocity := Vector3.ZERO
	var speed := _behavior.wander_speed
	if brain.state == WatcherBrain.State.STALK:
		speed = _behavior.stalk_speed
		desired_velocity = _get_path_velocity(delta, brain.get_movement_goal(), speed, navigation_search_budget)
	elif brain.state == WatcherBrain.State.CHASE:
		speed = _behavior.sprint_speed
		desired_velocity = _get_path_velocity(delta, brain.get_movement_goal(), speed, navigation_search_budget)
	elif brain.state == WatcherBrain.State.WANDER:
		desired_velocity = _get_path_velocity(delta, brain.get_movement_goal(), speed, navigation_search_budget)
	elif brain.state in [WatcherBrain.State.STARE, WatcherBrain.State.ATTACK]:
		_face_player(player_position, delta)
	max_speed = speed
	desired_velocity = limit_planar_velocity(desired_velocity + separation_velocity, max_speed)
	advance_voxel_motion(delta, desired_velocity, _behavior.gravity)

func record_player_attack() -> void:
	_apply_player_attack_response(true)

func _apply_player_attack_response(advance_teleport_sequence: bool) -> void:
	assert(brain != null and _path_follower != null and _watcher_animation != null)
	brain.record_player_attack()
	if advance_teleport_sequence:
		_teleport_sequence += 1
	_timed_melee_contact.cancel()
	_watcher_animation.cancel_attack()
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	_path_follower.request_repath()

func reset_after_player_defeat() -> void:
	assert(brain != null and _path_follower != null and _watcher_animation != null)
	brain.reset_after_player_defeat()
	_timed_melee_contact.cancel()
	_watcher_animation.cancel_attack()
	_watcher_animation.set_aggressive(false)
	_watcher_animation.set_stalking(false)
	_player_visible = false
	_vision_sample_remaining = 0.0
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	_path_follower.request_repath()

func is_aggressive() -> bool:
	return brain != null and brain.is_aggressive()

func is_aggroed() -> bool:
	return is_aggressive()

func try_begin_player_hit_response(_player_position: Vector3) -> bool:
	if brain == null or brain.is_aggressive():
		return false
	_apply_player_attack_response(false)
	return true

func supports_player_hit_response() -> bool:
	return true

func get_teleport_sequence() -> int:
	return _teleport_sequence

func record_teleport_committed(previous_position: Vector3) -> void:
	assert(previous_position.is_finite())
	assert(brain != null and brain.is_aggressive())
	brain.record_teleport_committed()
	_timed_melee_contact.cancel()
	_watcher_animation.cancel_attack()
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	on_ground = true
	_path_follower.request_repath()
	_play_teleport_particles(_teleport_departure, previous_position)
	_play_teleport_particles(_teleport_arrival, global_position)

func can_despawn_ambiently() -> bool:
	return not is_aggressive()

func begin_despawn_fade() -> void:
	_cancel_combat_and_particles()
	super.begin_despawn_fade()

func begin_death_retirement() -> void:
	_cancel_combat_and_particles()
	super.begin_death_retirement()

func _cancel_combat_and_particles() -> void:
	_timed_melee_contact.cancel()
	if _watcher_animation != null:
		_watcher_animation.cancel_attack()
	if _teleport_departure != null:
		_teleport_departure.emitting = false
	if _teleport_arrival != null:
		_teleport_arrival.emitting = false

func _emit_melee_contact(profile: MeleeAttackProfile) -> void:
	if profile != null:
		melee_contact_reached.emit(runtime_id, profile)

func _get_path_velocity(
	delta: float,
	goal: Vector3,
	speed: float,
	navigation_search_budget: NavigationSearchBudget,
) -> Vector3:
	var result := _path_follower.advance(
		delta,
		global_position,
		goal,
		speed,
		on_ground,
		navigation_search_budget,
	)
	if result.path_failed:
		brain.reject_movement_goal(global_position)
	return apply_path_follow_result(result, delta, _behavior.jump_velocity)

func _sample_player_visibility(delta: float, player_position: Vector3) -> bool:
	_vision_sample_remaining -= delta
	var sample_due := _vision_sample_remaining <= 0.0
	if sample_due:
		_vision_sample_remaining = fposmod(_vision_sample_remaining, VISION_SAMPLE_INTERVAL_SECONDS)
		if is_zero_approx(_vision_sample_remaining):
			_vision_sample_remaining = VISION_SAMPLE_INTERVAL_SECONDS
	if global_position.distance_squared_to(player_position) > _behavior.detection_range * _behavior.detection_range:
		_player_visible = false
		return false
	if not sample_due:
		return _player_visible
	var origin := global_position + Vector3.UP * definition.body_height * 0.85
	var target := player_position + Vector3.UP * 0.9
	_player_visible = VoxelLineOfSight.has_clear_path(voxel_space, origin, target)
	return _player_visible

func _face_player(player_position: Vector3, delta: float) -> void:
	var direction := player_position - global_position
	direction.y = 0.0
	if direction.is_zero_approx():
		return
	var target_yaw := atan2(direction.x, direction.z)
	model_root.rotation.y = lerp_angle(model_root.rotation.y, target_yaw, minf(delta * 10.0, 1.0))

func _play_teleport_particles(particles: CPUParticles3D, feet_position: Vector3) -> void:
	particles.global_position = feet_position + Vector3.UP * definition.body_height * 0.5
	particles.restart()
	particles.emitting = true
