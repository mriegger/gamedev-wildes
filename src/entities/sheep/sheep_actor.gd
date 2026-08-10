extends EntityActor
class_name SheepActor

var brain: SheepBrain

var _behavior: SheepBehaviorDefinition
var _sheep_animation: SheepAnimationDriver
var _path_follower: VoxelPathFollower

func supports_behavior(behavior: EntityBehaviorDefinition) -> bool:
	return behavior is SheepBehaviorDefinition

func setup(p_runtime_id: int, p_definition: EntityDefinition, p_voxel_world: VoxelWorld, behavior_seed: int):
	super.setup(p_runtime_id, p_definition, p_voxel_world, behavior_seed)
	_behavior = p_definition.behavior as SheepBehaviorDefinition
	assert(_behavior != null)
	brain = SheepBrain.new(_behavior, behavior_seed)
	_path_follower = VoxelPathFollower.new(voxel_world, definition.body_width, definition.body_height, _behavior.repath_seconds)
	max_speed = _behavior.wander_speed
	_sheep_animation = animation_driver as SheepAnimationDriver
	assert(_sheep_animation != null)

func tick(delta: float, _player_position: Vector3, separation_velocity: Vector3, navigation_search_budget: NavigationSearchBudget):
	assert(brain != null and voxel_world != null)
	brain.advance(delta, global_position)
	var fleeing := brain.state == SheepBrain.State.FLEE
	_sheep_animation.set_fleeing(fleeing)
	max_speed = _behavior.flee_speed if fleeing else _behavior.wander_speed
	var desired_velocity := Vector3.ZERO
	if brain.state != SheepBrain.State.IDLE:
		desired_velocity = _get_path_velocity(delta, brain.get_movement_goal(), max_speed, navigation_search_budget)
	desired_velocity += separation_velocity
	var planar_velocity := Vector2(desired_velocity.x, desired_velocity.z)
	if planar_velocity.length() > max_speed:
		planar_velocity = planar_velocity.normalized() * max_speed
		desired_velocity.x = planar_velocity.x
		desired_velocity.z = planar_velocity.y
	_advance_motion(delta, desired_velocity)

func record_melee_contact(world_hit_direction: Vector3):
	assert(brain != null)
	brain.record_melee_contact(global_position, world_hit_direction)
	super.record_melee_contact(world_hit_direction)

func _get_path_velocity(delta: float, goal: Vector3, speed: float, navigation_search_budget: NavigationSearchBudget) -> Vector3:
	var result := _path_follower.advance(delta, global_position, goal, speed, on_ground, navigation_search_budget)
	if result.path_failed:
		brain.reject_movement_goal(global_position)
	if result.should_jump:
		velocity.y = _behavior.jump_velocity
	if result.desired_velocity.is_zero_approx():
		return Vector3.ZERO
	var direction := result.desired_velocity.normalized()
	var target_yaw := atan2(direction.x, direction.z)
	model_root.rotation.y = lerp_angle(model_root.rotation.y, target_yaw, minf(delta * 8.0, 1.0))
	return result.desired_velocity

func _advance_motion(delta: float, desired_velocity: Vector3):
	velocity.x = desired_velocity.x
	velocity.z = desired_velocity.z
	if not on_ground:
		velocity.y -= _behavior.gravity * delta
	var intended_horizontal := Vector2(velocity.x, velocity.z)
	var result := VoxelBodySolver.sweep(voxel_world, global_position, velocity, velocity * delta, definition.body_width, definition.body_height)
	global_position = result.position
	velocity = result.velocity
	var ground_y := VoxelBodySolver.get_ground_y(voxel_world, global_position, definition.body_width)
	on_ground = velocity.y <= 0.0 and ground_y != VoxelWorld.NO_SURFACE_Y and absf(ground_y - global_position.y) < 0.12
	if on_ground:
		velocity.y = 0.0
	if intended_horizontal.length_squared() > 0.01 and Vector2(velocity.x, velocity.z).length_squared() < 0.0001:
		_path_follower.invalidate_path()
