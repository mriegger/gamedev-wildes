extends EntityActor
class_name SheepActor

var brain: SheepBrain

var _behavior: SheepBehaviorDefinition
var _sheep_animation: SheepAnimationDriver
var _path_follower: VoxelPathFollower

func supports_behavior(behavior: EntityBehaviorDefinition) -> bool:
	return behavior is SheepBehaviorDefinition

func setup(
	p_runtime_id: int,
	p_definition: EntityDefinition,
	p_voxel_space: VoxelSpace,
	behavior_seed: int,
	navigation_limits: EntityNavigationLimits,
):
	super.setup(p_runtime_id, p_definition, p_voxel_space, behavior_seed, navigation_limits)
	_behavior = p_definition.behavior as SheepBehaviorDefinition
	assert(_behavior != null)
	brain = SheepBrain.new(_behavior, behavior_seed)
	_path_follower = VoxelPathFollower.new(voxel_space, definition.body_width, definition.body_height, _behavior.repath_seconds, navigation_limits)
	max_speed = _behavior.wander_speed
	_sheep_animation = animation_driver as SheepAnimationDriver
	assert(_sheep_animation != null)

func tick(delta: float, _observation: EntityTargetObservation, separation_velocity: Vector3, navigation_search_budget: NavigationSearchBudget):
	assert(brain != null and voxel_space != null)
	var previous_state := brain.state
	brain.advance(delta, global_position)
	if brain.state != previous_state and brain.state == SheepBrain.State.WANDER:
		_path_follower.request_repath()
	var fleeing := brain.state == SheepBrain.State.FLEE
	_sheep_animation.set_fleeing(fleeing)
	max_speed = _behavior.flee_speed if fleeing else _behavior.wander_speed
	var desired_velocity := Vector3.ZERO
	if brain.state != SheepBrain.State.IDLE:
		desired_velocity = _get_path_velocity(delta, brain.get_movement_goal(), max_speed, navigation_search_budget)
	desired_velocity = limit_planar_velocity(desired_velocity + separation_velocity, max_speed)
	advance_voxel_motion(delta, desired_velocity, _behavior.gravity)

func record_melee_contact(world_hit_direction: Vector3):
	assert(brain != null)
	brain.record_melee_contact(global_position, world_hit_direction)
	_path_follower.request_repath()
	super.record_melee_contact(world_hit_direction)

func try_begin_player_hit_response(player_position: Vector3) -> bool:
	if brain == null or brain.state == SheepBrain.State.FLEE:
		return false
	var flee_direction := global_position - player_position
	flee_direction.y = 0.0
	if flee_direction.is_zero_approx():
		flee_direction = Vector3.FORWARD
	brain.record_melee_contact(global_position, flee_direction)
	_path_follower.request_repath()
	max_speed = _behavior.flee_speed
	_sheep_animation.set_fleeing(true)
	return true

func supports_player_hit_response() -> bool:
	return true

func _get_path_velocity(delta: float, goal: Vector3, speed: float, navigation_search_budget: NavigationSearchBudget) -> Vector3:
	var result := _path_follower.advance(delta, global_position, goal, speed, on_ground, navigation_search_budget)
	if result.path_failed:
		brain.reject_movement_goal(global_position)
	return apply_path_follow_result(result, delta, _behavior.jump_velocity)
