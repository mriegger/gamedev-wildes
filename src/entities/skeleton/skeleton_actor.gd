extends EntityActor
class_name SkeletonActor

var brain: SkeletonBrain

var _behavior: SkeletonBehaviorDefinition
var _skeleton_animation: SkeletonAnimationDriver
var _path_follower: VoxelPathFollower

func supports_behavior(behavior: EntityBehaviorDefinition) -> bool:
	return behavior is SkeletonBehaviorDefinition

func setup(
	p_runtime_id: int,
	p_definition: EntityDefinition,
	p_voxel_space: VoxelSpace,
	behavior_seed: int,
	navigation_limits: EntityNavigationLimits,
):
	super.setup(p_runtime_id, p_definition, p_voxel_space, behavior_seed, navigation_limits)
	_behavior = p_definition.behavior as SkeletonBehaviorDefinition
	assert(_behavior != null)
	brain = SkeletonBrain.new(_behavior, behavior_seed)
	_path_follower = VoxelPathFollower.new(
		voxel_space,
		definition.body_width,
		definition.body_height,
		_behavior.repath_seconds,
		navigation_limits,
	)
	max_speed = _behavior.roam_speed
	_skeleton_animation = animation_driver as SkeletonAnimationDriver
	assert(_skeleton_animation != null)

func tick(
	delta: float,
	observation: EntityTargetObservation,
	separation_velocity: Vector3,
	navigation_search_budget: NavigationSearchBudget,
):
	assert(brain != null and voxel_space != null and observation != null)
	var current_position_hidden := false
	if brain.is_player_in_detection_range(global_position, observation.player_position):
		current_position_hidden = VoxelCameraOcclusion.is_hidden(
			voxel_space,
			observation,
			global_position,
			definition.body_width,
			definition.body_height,
		)
	var previous_state := brain.state
	brain.advance(delta, global_position, observation.player_position, current_position_hidden)
	if brain.state != previous_state:
		_path_follower.request_repath()
	_skeleton_animation.set_hiding(brain.state == SkeletonBrain.State.HIDE)
	var desired_velocity := Vector3.ZERO
	if brain.state == SkeletonBrain.State.ROAM:
		var result := _path_follower.advance(
			delta,
			global_position,
			brain.get_movement_goal(),
			_behavior.roam_speed,
			on_ground,
			navigation_search_budget,
		)
		if result.path_failed:
			brain.reject_movement_goal(global_position)
		desired_velocity = apply_path_follow_result(result, delta, _behavior.jump_velocity)
		desired_velocity = limit_planar_velocity(desired_velocity + separation_velocity, _behavior.roam_speed)
	advance_voxel_motion(delta, desired_velocity, _behavior.gravity)
