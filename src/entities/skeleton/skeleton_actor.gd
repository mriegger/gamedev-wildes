extends EntityActor
class_name SkeletonActor

const VoxelCoverSearchType := preload("res://entities/skeleton/voxel_cover_search.gd")

var brain: SkeletonBrain

var _behavior: SkeletonBehaviorDefinition
var _skeleton_animation: SkeletonAnimationDriver
var _path_follower: VoxelPathFollower
var _cover_search: VoxelCoverSearchType

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
	_cover_search = VoxelCoverSearchType.new(
		voxel_space,
		definition.body_width,
		definition.body_height,
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
		current_position_hidden = _is_hidden(global_position, observation)
	var previous_state := brain.state
	brain.advance(delta, global_position, observation.player_position, current_position_hidden)
	_apply_state_change(previous_state)

	if brain.state == SkeletonBrain.State.SEARCH_COVER:
		previous_state = brain.state
		_advance_cover_search(observation, navigation_search_budget)
		_apply_state_change(previous_state)

	var desired_velocity := Vector3.ZERO
	match brain.state:
		SkeletonBrain.State.ROAM:
			desired_velocity = _follow_movement_goal(
				delta,
				separation_velocity,
				navigation_search_budget,
				false,
			)
		SkeletonBrain.State.MOVE_TO_COVER:
			if _has_reached_movement_goal():
				previous_state = brain.state
				brain.record_cover_arrival(_is_hidden(global_position, observation))
				_apply_state_change(previous_state)
			else:
				desired_velocity = _follow_movement_goal(
					delta,
					separation_velocity,
					navigation_search_budget,
					true,
				)
	advance_voxel_motion(delta, desired_velocity, _behavior.gravity)

	if brain.state == SkeletonBrain.State.MOVE_TO_COVER and _has_reached_movement_goal():
		previous_state = brain.state
		brain.record_cover_arrival(_is_hidden(global_position, observation))
		_apply_state_change(previous_state)

func _advance_cover_search(
	observation: EntityTargetObservation,
	navigation_search_budget: NavigationSearchBudget,
):
	if brain.needs_cover_search():
		_cover_search.begin(global_position, observation)
		brain.record_cover_search_started()
	var status := _cover_search.advance(navigation_search_budget)
	if status == VoxelCoverSearchType.Status.FOUND:
		brain.record_cover_found(_cover_search.get_target())
	elif status == VoxelCoverSearchType.Status.EXHAUSTED:
		brain.record_cover_exhausted()

func _follow_movement_goal(
	delta: float,
	separation_velocity: Vector3,
	navigation_search_budget: NavigationSearchBudget,
	is_cover_goal: bool,
) -> Vector3:
	var result := _path_follower.advance(
		delta,
		global_position,
		brain.get_movement_goal(),
		_behavior.roam_speed,
		on_ground,
		navigation_search_budget,
	)
	if result.path_failed:
		if is_cover_goal:
			var previous_state := brain.state
			brain.reject_cover_goal()
			_apply_state_change(previous_state)
		else:
			brain.reject_movement_goal(global_position)
		return Vector3.ZERO
	var desired_velocity := apply_path_follow_result(result, delta, _behavior.jump_velocity)
	return limit_planar_velocity(desired_velocity + separation_velocity, _behavior.roam_speed)

func _has_reached_movement_goal() -> bool:
	var goal := brain.get_movement_goal()
	var horizontal_offset := Vector2(goal.x - global_position.x, goal.z - global_position.z)
	return horizontal_offset.length_squared() < 0.09 and absf(goal.y - global_position.y) < 0.35

func _is_hidden(position: Vector3, observation: EntityTargetObservation) -> bool:
	return VoxelCameraOcclusion.is_hidden(
		voxel_space,
		observation,
		position,
		definition.body_width,
		definition.body_height,
	)

func _apply_state_change(previous_state: SkeletonBrain.State):
	if brain.state == previous_state:
		return
	_path_follower.request_repath()
	_skeleton_animation.set_hiding(brain.state == SkeletonBrain.State.HIDE)
