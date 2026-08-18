extends EntityActor
class_name StoneGolemActor

const VoxelPlayerVisibilitySensorType := preload("res://entities/awareness/voxel_player_visibility_sensor.gd")
const TimedMeleeContactType := preload("res://combat/timed_melee_contact.gd")

var brain: StoneGolemBrain

var _behavior: StoneGolemBehaviorDefinition
var _stone_golem_animation: StoneGolemAnimationDriver
var _visibility_sensor: VoxelPlayerVisibilitySensorType
var _path_follower: VoxelPathFollower
var _timed_melee_contact := TimedMeleeContactType.new()

func supports_behavior(behavior: EntityBehaviorDefinition) -> bool:
	return behavior is StoneGolemBehaviorDefinition

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
	var desired_velocity := Vector3.ZERO
	if brain.state == StoneGolemBrain.State.CHASE:
		var reach_squared := _behavior.punch_profile.reach * _behavior.punch_profile.reach
		if not player_visible or global_position.distance_squared_to(observation.player_position) > reach_squared:
			desired_velocity = _get_path_velocity(delta, navigation_search_budget)
		desired_velocity = limit_planar_velocity(desired_velocity + separation_velocity, _behavior.movement_speed)
	advance_voxel_motion(delta, desired_velocity, _behavior.gravity)

func _emit_melee_contact(profile: MeleeAttackProfile) -> void:
	if profile != null:
		melee_contact_reached.emit(runtime_id, profile)

func begin_despawn_fade() -> void:
	_timed_melee_contact.cancel()
	super.begin_despawn_fade()

func begin_death_retirement() -> void:
	_timed_melee_contact.cancel()
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
