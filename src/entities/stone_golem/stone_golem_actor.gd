extends EntityActor
class_name StoneGolemActor

const VoxelPlayerVisibilitySensorType := preload("res://entities/awareness/voxel_player_visibility_sensor.gd")
const TimedMeleeContactType := preload("res://combat/timed_melee_contact.gd")
const StoneGolemLandingDustType := preload("res://entities/stone_golem/stone_golem_landing_dust.gd")
const StoneGolemAudioType := preload("res://entities/stone_golem/stone_golem_audio.gd")

@export_node_path("CPUParticles3D") var landing_dust_path: NodePath
@export_node_path("Node3D") var action_audio_path: NodePath

var brain: StoneGolemBrain

var _behavior: StoneGolemBehaviorDefinition
var _stone_golem_animation: StoneGolemAnimationDriver
var _visibility_sensor: VoxelPlayerVisibilitySensorType
var _path_follower: VoxelPathFollower
var _timed_melee_contact := TimedMeleeContactType.new()
var _landing_dust: StoneGolemLandingDustType
var _action_audio: StoneGolemAudioType
var _slam_airborne_elapsed: float = 0.0
var _slam_contact_pending: bool = false

func supports_behavior(behavior: EntityBehaviorDefinition) -> bool:
	return behavior is StoneGolemBehaviorDefinition

func has_valid_presentation() -> bool:
	if landing_dust_path.is_empty() or action_audio_path.is_empty():
		return false
	var dust_candidate := get_node_or_null(landing_dust_path)
	var audio_candidate := get_node_or_null(action_audio_path)
	return (
		super.has_valid_presentation()
		and dust_candidate is StoneGolemLandingDustType
		and audio_candidate is StoneGolemAudioType
		and audio_candidate.has_valid_presentation()
	)

func setup(
	p_runtime_id: int,
	p_definition: EntityDefinition,
	p_voxel_space: VoxelSpace,
	behavior_seed: int,
	navigation_limits: EntityNavigationLimits,
) -> void:
	super.setup(p_runtime_id, p_definition, p_voxel_space, behavior_seed, navigation_limits)
	_behavior = p_definition.behavior as StoneGolemBehaviorDefinition
	assert(_behavior != null)
	_timed_melee_contact.cancel()
	_landing_dust = get_node(landing_dust_path) as StoneGolemLandingDustType
	assert(_landing_dust != null)
	_action_audio = get_node(action_audio_path) as StoneGolemAudioType
	assert(_action_audio != null)
	_slam_airborne_elapsed = 0.0
	_slam_contact_pending = false
	brain = StoneGolemBrain.new(_behavior)
	_path_follower = VoxelPathFollower.new(
		voxel_space,
		definition.body_width,
		definition.body_height,
		_behavior.repath_seconds,
		navigation_limits,
	)
	max_speed = _behavior.movement_speed
	_stone_golem_animation = animation_driver as StoneGolemAnimationDriver
	assert(_stone_golem_animation != null)
	_action_audio.setup(behavior_seed, _stone_golem_animation.animator.profile.walk_cycle_seconds)
	_visibility_sensor = VoxelPlayerVisibilitySensorType.new(voxel_space, _behavior.detection_range, definition.body_height, runtime_id)

func tick(
	delta: float,
	observation: EntityTargetObservation,
	separation_velocity: Vector3,
	navigation_search_budget: NavigationSearchBudget,
) -> void:
	assert(brain != null and voxel_space != null)
	assert(observation != null and observation.validate())
	_emit_melee_contact(_timed_melee_contact.advance(delta))
	var player_visible := _visibility_sensor.advance(delta, global_position, observation.player_position)
	var previous_state := brain.state
	brain.advance(
		delta,
		global_position,
		observation,
		player_visible,
		_visibility_sensor.did_sample_line_of_sight(),
	)
	if brain.state != previous_state:
		_path_follower.request_repath()
	_stone_golem_animation.set_alerted(brain.is_alerted())
	if brain.consume_punch_started():
		var punch_profile := _behavior.punch_profile
		play_attack(punch_profile.duration)
		_emit_melee_contact(_timed_melee_contact.arm(punch_profile))
	var launched_this_tick := false
	if brain.consume_slam_started():
		_begin_slam_windup()
	if brain.consume_slam_launch_requested():
		launched_this_tick = _try_launch_slam()
	if brain.state == StoneGolemBrain.State.SLAM_AIRBORNE:
		if not launched_this_tick:
			_advance_slam_motion(delta)
		_advance_walking_audio(delta)
		return
	var desired_velocity := Vector3.ZERO
	if brain.state == StoneGolemBrain.State.CHASE:
		var planar_offset := observation.player_position - global_position
		planar_offset.y = 0.0
		var reach_squared := _behavior.punch_profile.reach * _behavior.punch_profile.reach
		if not player_visible or planar_offset.length_squared() > reach_squared:
			desired_velocity = _get_path_velocity(delta, navigation_search_budget)
		desired_velocity = limit_planar_velocity(desired_velocity + separation_velocity, _behavior.movement_speed)
	advance_voxel_motion(delta, desired_velocity, _behavior.gravity)
	_advance_walking_audio(delta)

func _begin_slam_windup() -> void:
	var target := brain.get_locked_slam_target()
	_face_planar(target)
	_stone_golem_animation.play_slam_windup(_behavior.slam_windup_seconds)
	velocity.x = 0.0
	velocity.z = 0.0

func _try_launch_slam() -> bool:
	var target := brain.get_locked_slam_target()
	if not _has_slam_launch_clearance(target):
		brain.abort_slam_launch()
		_stone_golem_animation.cancel_slam()
		velocity.x = 0.0
		velocity.z = 0.0
		return false
	velocity = _get_slam_launch_velocity(target)
	on_ground = false
	_slam_airborne_elapsed = 0.0
	_slam_contact_pending = true
	brain.record_slam_launch_started()
	_stone_golem_animation.play_slam_airborne(_behavior.get_slam_airborne_seconds())
	return true

func _get_slam_launch_velocity(target: Vector3) -> Vector3:
	var duration := _behavior.get_slam_airborne_seconds()
	var displacement := target - global_position
	return Vector3(
		displacement.x / duration,
		(displacement.y + 0.5 * _behavior.gravity * duration * duration) / duration,
		displacement.z / duration,
	)

func _has_slam_launch_clearance(target: Vector3) -> bool:
	var launch_velocity := _get_slam_launch_velocity(target)
	if launch_velocity.y <= 0.0:
		return false
	var apex_height := launch_velocity.y * launch_velocity.y / (2.0 * _behavior.gravity)
	var result := VoxelBodySolver.sweep(
		voxel_space,
		global_position,
		launch_velocity,
		Vector3.UP * apex_height,
		definition.body_width,
		definition.body_height,
	)
	return result.velocity.y > 0.0 and result.position.y >= global_position.y + apex_height - 0.001

func _advance_slam_motion(delta: float) -> void:
	var airborne_duration := _behavior.get_slam_airborne_seconds()
	var powered_remaining := maxf(airborne_duration - _slam_airborne_elapsed, 0.0)
	var powered_delta := minf(delta, powered_remaining)
	if powered_delta > 0.0:
		_advance_slam_step(powered_delta)
		_slam_airborne_elapsed += powered_delta
		if _finish_slam_if_landed():
			return
	var fall_delta := delta - powered_delta
	if fall_delta <= 0.0:
		return
	velocity.x = 0.0
	velocity.z = 0.0
	_advance_slam_step(fall_delta)
	_finish_slam_if_landed()

func _advance_slam_step(delta: float) -> void:
	var next_velocity := velocity
	next_velocity.y -= _behavior.gravity * delta
	var motion := next_velocity * delta
	motion.y = (velocity.y + next_velocity.y) * 0.5 * delta
	var result := VoxelBodySolver.sweep(voxel_space, global_position, next_velocity, motion, definition.body_width, definition.body_height)
	global_position = result.position
	velocity = result.velocity
	var ground_y := VoxelBodySolver.get_ground_y(voxel_space, global_position, definition.body_width)
	on_ground = (
		is_zero_approx(velocity.y)
		and ground_y != VoxelSpace.NO_SURFACE_Y
		and absf(ground_y - global_position.y) < 0.031
	)
	if on_ground:
		global_position.y = ground_y
		velocity.y = 0.0

func _finish_slam_if_landed() -> bool:
	if not on_ground:
		return false
	brain.record_slam_landed()
	_stone_golem_animation.play_slam_recovery(_behavior.get_slam_recovery_seconds())
	if _slam_contact_pending:
		_slam_contact_pending = false
		_landing_dust.play_at(global_position)
		radial_contact_reached.emit(runtime_id, _behavior.slam_profile)
	return true

func _face_planar(target: Vector3) -> void:
	var direction := target - global_position
	direction.y = 0.0
	if direction.is_zero_approx():
		return
	model_root.rotation.y = atan2(direction.x, direction.z)

func _cancel_slam() -> void:
	_slam_contact_pending = false
	_slam_airborne_elapsed = 0.0
	if is_instance_valid(_stone_golem_animation):
		_stone_golem_animation.cancel_slam()

func _emit_melee_contact(profile: MeleeAttackProfile) -> void:
	if profile != null:
		melee_contact_reached.emit(runtime_id, profile)

func _advance_walking_audio(delta: float) -> void:
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	var speed_ratio := planar_speed / maxf(max_speed, 0.001)
	_action_audio.advance(delta, speed_ratio, on_ground)

func record_melee_contact(world_hit_direction: Vector3) -> void:
	super.record_melee_contact(world_hit_direction)
	_action_audio.play_impact()

func begin_despawn_fade() -> void:
	_timed_melee_contact.cancel()
	_cancel_slam()
	_action_audio.stop_audio()
	super.begin_despawn_fade()

func begin_death_retirement() -> void:
	_timed_melee_contact.cancel()
	_cancel_slam()
	_action_audio.play_death()
	super.begin_death_retirement()

func _get_path_velocity(delta: float, navigation_search_budget: NavigationSearchBudget) -> Vector3:
	var result := _path_follower.advance(
		delta,
		global_position,
		brain.get_movement_goal(),
		_behavior.movement_speed,
		on_ground,
		navigation_search_budget,
	)
	return apply_path_follow_result(result, delta, _behavior.jump_velocity)
