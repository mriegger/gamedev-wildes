extends EntityActor
class_name SkeletonActor

const VoxelCoverSearchType := preload("res://entities/skeleton/voxel_cover_search.gd")
const TimedMeleeContactType := preload("res://combat/timed_melee_contact.gd")

var brain: SkeletonBrain

var _behavior: SkeletonBehaviorDefinition
var _skeleton_animation: SkeletonAnimationDriver
var _path_follower: VoxelPathFollower
var _cover_search: VoxelCoverSearchType
var _timed_melee_contact := TimedMeleeContactType.new()

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
	_timed_melee_contact.cancel()
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
	_emit_melee_contact(_timed_melee_contact.advance(delta))
	var current_position_hidden := false
	if brain.needs_detection_occlusion_check(global_position, observation.player_position):
		current_position_hidden = _is_hidden(global_position, observation)
	var previous_state := brain.state
	brain.advance(delta, global_position, observation.player_position, current_position_hidden)
	_apply_state_change(previous_state)
	if brain.consume_attack_started():
		var melee_profile := _behavior.melee_profile
		play_attack(melee_profile.duration)
		_emit_melee_contact(_timed_melee_contact.arm(melee_profile))

	if brain.is_cover_revalidation_due():
		previous_state = brain.state
		var position_to_validate := global_position
		if brain.state == SkeletonBrain.State.MOVE_TO_COVER:
			position_to_validate = brain.get_movement_goal()
		brain.record_cover_revalidated(_is_hidden(position_to_validate, observation))
		_apply_state_change(previous_state)

	var cover_work_advanced := false
	if brain.state == SkeletonBrain.State.SEARCH_COVER:
		previous_state = brain.state
		_advance_cover_search(observation, navigation_search_budget)
		_apply_state_change(previous_state)
		cover_work_advanced = true

	var desired_velocity := Vector3.ZERO
	match brain.state:
		SkeletonBrain.State.ROAM:
			desired_velocity = _follow_movement_goal(
				delta,
				separation_velocity,
				navigation_search_budget,
				_behavior.roam_speed,
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
					_behavior.roam_speed,
					true,
				)
		SkeletonBrain.State.SPRINT:
			desired_velocity = _follow_movement_goal(
				delta,
				separation_velocity,
				navigation_search_budget,
				_behavior.sprint_speed,
				false,
			)
			if not cover_work_advanced and (brain.needs_cover_search() or brain.is_cover_search_in_progress()):
				previous_state = brain.state
				_advance_cover_search(observation, navigation_search_budget)
				_apply_state_change(previous_state)
				if brain.state != SkeletonBrain.State.SPRINT:
					desired_velocity = Vector3.ZERO
	advance_voxel_motion(delta, desired_velocity, _behavior.gravity)

	if brain.state == SkeletonBrain.State.MOVE_TO_COVER and _has_reached_movement_goal():
		previous_state = brain.state
		brain.record_cover_arrival(_is_hidden(global_position, observation))
		_apply_state_change(previous_state)


func _emit_melee_contact(profile: MeleeAttackProfile) -> void:
	if profile != null:
		melee_contact_reached.emit(runtime_id, profile)

func begin_despawn_fade():
	_timed_melee_contact.cancel()
	super.begin_despawn_fade()

func begin_death_retirement():
	_timed_melee_contact.cancel()
	super.begin_death_retirement()

func _advance_cover_search(
	observation: EntityTargetObservation,
	navigation_search_budget: NavigationSearchBudget,
):
	if brain.needs_cover_search():
		_cover_search.begin(global_position, observation, brain.get_minimum_cover_search_distance())
		brain.record_cover_search_started()
	if not brain.is_cover_search_in_progress():
		return
	var status := _cover_search.advance(navigation_search_budget)
	if status == VoxelCoverSearchType.Status.FOUND:
		var target := _cover_search.get_target()
		brain.record_cover_found(target)
		if not _is_hidden(target, observation):
			brain.reject_cover_goal()
	elif status == VoxelCoverSearchType.Status.EXHAUSTED:
		brain.record_cover_exhausted()

func _follow_movement_goal(
	delta: float,
	separation_velocity: Vector3,
	navigation_search_budget: NavigationSearchBudget,
	speed: float,
	is_cover_goal: bool,
) -> Vector3:
	var result := _path_follower.advance(
		delta,
		global_position,
		brain.get_movement_goal(),
		speed,
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
	if is_cover_goal and desired_velocity.is_zero_approx() and _is_inside_movement_goal_cell():
		var exact_offset := brain.get_movement_goal() - global_position
		exact_offset.y = 0.0
		if not exact_offset.is_zero_approx():
			desired_velocity = exact_offset.normalized() * speed
	return limit_planar_velocity(desired_velocity + separation_velocity, speed)

func _has_reached_movement_goal() -> bool:
	var goal := brain.get_movement_goal()
	var horizontal_offset := Vector2(goal.x - global_position.x, goal.z - global_position.z)
	return horizontal_offset.length_squared() < 0.09 and absf(goal.y - global_position.y) < 0.35

func _is_inside_movement_goal_cell() -> bool:
	var goal := brain.get_movement_goal()
	return (
		floori(global_position.x) == floori(goal.x)
		and floori(global_position.z) == floori(goal.z)
		and absf(goal.y - global_position.y) < 0.35
	)

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
	max_speed = _behavior.sprint_speed if brain.state == SkeletonBrain.State.SPRINT else _behavior.roam_speed
	_skeleton_animation.set_hiding(brain.state == SkeletonBrain.State.HIDE)
	_skeleton_animation.set_sprinting(brain.state == SkeletonBrain.State.SPRINT)
