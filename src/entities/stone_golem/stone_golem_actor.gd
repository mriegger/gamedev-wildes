extends EntityActor
class_name StoneGolemActor

const VoxelPlayerVisibilitySensorType := preload("res://entities/awareness/voxel_player_visibility_sensor.gd")

var brain: StoneGolemBrain

var _behavior: StoneGolemBehaviorDefinition
var _stone_golem_animation: StoneGolemAnimationDriver
var _visibility_sensor: VoxelPlayerVisibilitySensorType
var _path_follower: VoxelPathFollower

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
	var player_visible := _visibility_sensor.advance(delta, global_position, observation.player_position)
	var previous_state := brain.state
	brain.advance(delta, global_position, observation, player_visible)
	if brain.state != previous_state:
		_path_follower.request_repath()
	_stone_golem_animation.set_alerted(brain.is_alerted())
	var desired_velocity := Vector3.ZERO
	if brain.state == StoneGolemBrain.State.CHASE:
		desired_velocity = _get_path_velocity(delta, navigation_search_budget)
		desired_velocity = limit_planar_velocity(desired_velocity + separation_velocity, _behavior.movement_speed)
	advance_voxel_motion(delta, desired_velocity, _behavior.gravity)

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
