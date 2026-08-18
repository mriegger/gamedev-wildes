extends EntityActor
class_name BirdActor

const LANDING_SEARCH_ATTEMPTS: int = 8
const FLIGHT_GOAL_DISTANCE: float = 0.8

var brain: BirdBrain

var _behavior: BirdBehaviorDefinition
var _path_follower: VoxelPathFollower
var _landing_target: Vector3 = Vector3.ZERO
var _cruise_target: Vector3 = Vector3.ZERO
var _takeoff_target_y: float = 0.0
var _has_landing_target: bool = false
var _landing_retry_remaining: float = 0.0

func supports_behavior(behavior: EntityBehaviorDefinition) -> bool:
	return behavior is BirdBehaviorDefinition

func setup(
	p_runtime_id: int,
	p_definition: EntityDefinition,
	p_voxel_space: VoxelSpace,
	behavior_seed: int,
	navigation_limits: EntityNavigationLimits,
):
	super.setup(p_runtime_id, p_definition, p_voxel_space, behavior_seed, navigation_limits)
	_behavior = p_definition.behavior as BirdBehaviorDefinition
	assert(_behavior != null)
	brain = BirdBrain.new(_behavior, behavior_seed)
	_path_follower = VoxelPathFollower.new(voxel_space, definition.body_width, definition.body_height, _behavior.repath_seconds, navigation_limits)
	assert(animation_driver is BirdAnimationDriver)
	on_ground = false
	max_speed = _behavior.flight_speed
	_try_select_landing_target()

func tick(delta: float, _player_position: Vector3, separation_velocity: Vector3, navigation_search_budget: NavigationSearchBudget):
	assert(brain != null and voxel_space != null)
	var previous_state := brain.state
	var phase_goal_reached := _is_phase_goal_reached()
	brain.advance(delta, global_position, on_ground, phase_goal_reached)
	_handle_state_transition(previous_state, brain.state)
	if brain.state in [BirdBrain.State.GROUNDED_IDLE, BirdBrain.State.GROUNDED_WALK]:
		_advance_grounded(delta, separation_velocity, navigation_search_budget)
	else:
		_advance_airborne(delta, separation_velocity)

func _advance_grounded(delta: float, separation_velocity: Vector3, navigation_search_budget: NavigationSearchBudget) -> void:
	max_speed = _behavior.grounded_walk_speed
	var desired_velocity := Vector3.ZERO
	if brain.state == BirdBrain.State.GROUNDED_WALK:
		var result := _path_follower.advance(delta, global_position, brain.get_movement_goal(), max_speed, on_ground, navigation_search_budget)
		if result.path_failed:
			brain.reject_movement_goal()
		else:
			desired_velocity = apply_path_follow_result(result, delta, _behavior.jump_velocity)
	desired_velocity = limit_planar_velocity(desired_velocity + separation_velocity, max_speed)
	advance_voxel_motion(delta, desired_velocity, _behavior.gravity)

func _advance_airborne(delta: float, separation_velocity: Vector3) -> void:
	if brain.state == BirdBrain.State.CRUISE and not _has_landing_target:
		_landing_retry_remaining = maxf(_landing_retry_remaining - delta, 0.0)
		if _landing_retry_remaining <= 0.0:
			_try_select_landing_target()
	var desired_velocity := _get_flight_velocity()
	var speed_limit := _behavior.flight_speed
	if brain.state == BirdBrain.State.DESCEND:
		speed_limit = _behavior.landing_speed
	elif brain.state == BirdBrain.State.TAKEOFF:
		speed_limit = _behavior.takeoff_speed
	desired_velocity += separation_velocity
	if desired_velocity.length() > speed_limit:
		desired_velocity = desired_velocity.normalized() * speed_limit
	max_speed = speed_limit
	velocity = velocity.move_toward(desired_velocity, _behavior.flight_acceleration * delta)
	_apply_flight_yaw(delta, velocity)
	var start_position := global_position
	var requested_motion := velocity * delta
	var result := VoxelBodySolver.sweep(voxel_space, global_position, velocity, requested_motion, definition.body_width, definition.body_height)
	global_position = result.position
	velocity = result.velocity
	var ground_y := VoxelBodySolver.get_ground_y(voxel_space, global_position, definition.body_width)
	on_ground = velocity.y <= 0.0 and ground_y != VoxelSpace.NO_SURFACE_Y and absf(ground_y - global_position.y) < 0.12
	if on_ground:
		velocity.y = 0.0
	var expected_position := start_position + requested_motion
	var blocked := global_position.distance_squared_to(expected_position) > 0.04
	if blocked and not on_ground:
		brain.reject_flight_goal()
		_has_landing_target = false
		_landing_retry_remaining = _behavior.landing_retry_seconds
		velocity.y = maxf(velocity.y, _behavior.takeoff_speed * 0.5)

func _get_flight_velocity() -> Vector3:
	var target := global_position
	var speed := _behavior.flight_speed
	match brain.state:
		BirdBrain.State.CRUISE:
			if _has_landing_target:
				target = _cruise_target
		BirdBrain.State.DESCEND:
			target = _landing_target
			speed = _behavior.landing_speed
		BirdBrain.State.TAKEOFF:
			target = Vector3(global_position.x, _takeoff_target_y, global_position.z)
			speed = _behavior.takeoff_speed
	var offset := target - global_position
	return offset.normalized() * speed if not offset.is_zero_approx() else Vector3.ZERO

func _is_phase_goal_reached() -> bool:
	match brain.state:
		BirdBrain.State.CRUISE:
			if not _has_landing_target:
				return false
			var planar_offset := Vector2(_cruise_target.x - global_position.x, _cruise_target.z - global_position.z)
			return planar_offset.length() <= _behavior.landing_approach_distance and absf(_cruise_target.y - global_position.y) <= FLIGHT_GOAL_DISTANCE
		BirdBrain.State.TAKEOFF:
			return global_position.y >= _takeoff_target_y - FLIGHT_GOAL_DISTANCE
	return false

func _handle_state_transition(previous_state: BirdBrain.State, current_state: BirdBrain.State) -> void:
	if previous_state == current_state:
		return
	if current_state == BirdBrain.State.GROUNDED_IDLE:
		velocity = Vector3.ZERO
	elif current_state == BirdBrain.State.GROUNDED_WALK:
		_path_follower.request_repath()
	elif current_state == BirdBrain.State.TAKEOFF:
		on_ground = false
		_takeoff_target_y = global_position.y + float(brain.sample_cruise_altitude())
	elif current_state == BirdBrain.State.CRUISE:
		_has_landing_target = false
		_try_select_landing_target()

func _try_select_landing_target() -> bool:
	for _attempt in LANDING_SEARCH_ATTEMPTS:
		var offset := brain.sample_landing_offset()
		var x := floori(global_position.x + offset.x)
		var z := floori(global_position.z + offset.y)
		var surface_top := voxel_space.get_highest_top(x, z)
		if surface_top == VoxelSpace.NO_SURFACE_Y:
			continue
		var floor_y := floori(surface_top - 0.001)
		if not definition.can_spawn_ambiently_on(voxel_space.get_block_id_at(Vector3i(x, floor_y, z))):
			continue
		var landing_candidate := Vector3(float(x) + 0.5, surface_top, float(z) + 0.5)
		if not EntitySpawnGeometry.can_spawn_grounded(voxel_space, definition, landing_candidate):
			continue
		_landing_target = landing_candidate
		_cruise_target = landing_candidate + Vector3.UP * float(brain.sample_cruise_altitude())
		_has_landing_target = true
		_landing_retry_remaining = 0.0
		return true
	_has_landing_target = false
	_landing_retry_remaining = _behavior.landing_retry_seconds
	return false

func _apply_flight_yaw(delta: float, flight_velocity: Vector3) -> void:
	var planar_velocity := Vector2(flight_velocity.x, flight_velocity.z)
	if planar_velocity.length_squared() <= 0.0001:
		return
	var target_yaw := atan2(flight_velocity.x, flight_velocity.z)
	model_root.rotation.y = lerp_angle(model_root.rotation.y, target_yaw, minf(delta * 8.0, 1.0))
