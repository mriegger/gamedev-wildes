extends EntityActor
class_name BirdActor

const LANDING_SEARCH_ATTEMPTS: int = 8
const FLIGHT_GOAL_DISTANCE: float = 0.8
const WATER_SURFACE_SEARCH_HEIGHT: int = 32
const WATER_RIPPLE_MINIMUM_SPEED: float = 0.15
const AMBIENT_DEPARTURE_SECONDS: float = 1.5
const TAKEOFF_ESCAPE_DISTANCES: Array[float] = [2.0, 4.0]
const TAKEOFF_ESCAPE_DIRECTIONS: Array[Vector3] = [
	Vector3.RIGHT,
	Vector3.LEFT,
	Vector3.FORWARD,
	Vector3.BACK,
	Vector3(0.70710678, 0.0, 0.70710678),
	Vector3(-0.70710678, 0.0, 0.70710678),
	Vector3(0.70710678, 0.0, -0.70710678),
	Vector3(-0.70710678, 0.0, -0.70710678),
]

@export var vocalization_profiles: Array[EntityVocalizationProfile] = []
@export var vocalization_profile_override: EntityVocalizationProfile
@export_range(-1, 4, 1) var color_variant_override: int = -1

var brain: BirdBrain
var color_variant: BirdAnimationDriver.ColorVariant

var _behavior: BirdBehaviorDefinition
var _path_follower: VoxelPathFollower
var _landing_target: Vector3 = Vector3.ZERO
var _cruise_target: Vector3 = Vector3.ZERO
var _takeoff_target: Vector3 = Vector3.ZERO
var _has_landing_target: bool = false
var _landing_on_water: bool = false
var _landing_retry_remaining: float = 0.0
var _water_ripple_remaining: float = 0.0
var _ambient_departure_remaining: float = 0.0

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
	color_variant = color_variant_for_seed(behavior_seed) if color_variant_override < 0 else color_variant_override as BirdAnimationDriver.ColorVariant
	_configure_vocalizations(behavior_seed)
	(animation_driver as BirdAnimationDriver).apply_color_variant(color_variant)
	on_ground = false
	max_speed = _behavior.flight_speed
	_water_ripple_remaining = 0.0
	_try_select_landing_target()
	_update_vocalizations()

static func color_variant_for_seed(seed_value: int) -> BirdAnimationDriver.ColorVariant:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x4b1d5eed
	return rng.randi_range(BirdAnimationDriver.ColorVariant.CROW, BirdAnimationDriver.ColorVariant.BLUEBIRD) as BirdAnimationDriver.ColorVariant

static func color_variant_index_for_id(variant_id: StringName) -> int:
	match variant_id:
		&"crow":
			return BirdAnimationDriver.ColorVariant.CROW
		&"redbird":
			return BirdAnimationDriver.ColorVariant.REDBIRD
		&"duck":
			return BirdAnimationDriver.ColorVariant.DUCK
		&"bluebird":
			return BirdAnimationDriver.ColorVariant.BLUEBIRD
		&"owl":
			return BirdAnimationDriver.ColorVariant.OWL
	return -1

static func color_variant_count() -> int:
	return BirdAnimationDriver.ColorVariant.BLUEBIRD + 1

static func behavior_seed_for_color_variant_index(variant_index: int, seed_start: int) -> int:
	assert(variant_index >= BirdAnimationDriver.ColorVariant.CROW and variant_index <= BirdAnimationDriver.ColorVariant.BLUEBIRD)
	var variant := variant_index as BirdAnimationDriver.ColorVariant
	var candidate := seed_start
	for _attempt in 256:
		if color_variant_for_seed(candidate) == variant:
			return candidate
		candidate += 1
	assert(false)
	return seed_start

func tick(delta: float, _observation: EntityTargetObservation, separation_velocity: Vector3, navigation_search_budget: NavigationSearchBudget):
	assert(brain != null and voxel_space != null)
	var previous_state := brain.state
	var rejected_ground_contact := on_ground and not _has_approved_ground_contact() and brain.state != BirdBrain.State.CRUISE
	if rejected_ground_contact:
		brain.reject_ground_contact()
	else:
		var phase_goal_reached := _is_phase_goal_reached()
		brain.advance(delta, global_position, on_ground, phase_goal_reached)
	_handle_state_transition(previous_state, brain.state)
	if brain.state in [BirdBrain.State.GROUNDED_IDLE, BirdBrain.State.GROUNDED_WALK]:
		_advance_grounded(delta, separation_velocity, navigation_search_budget)
	else:
		_advance_airborne(delta, separation_velocity)
	_update_vocalizations()

func begin_despawn_fade() -> void:
	if definition.id != &"owl":
		super.begin_despawn_fade()
		return
	if vocalizations != null:
		vocalizations.stop_vocalizations()
	set_process(false)
	_has_landing_target = false
	_landing_on_water = false
	brain.state = BirdBrain.State.TAKEOFF
	if not _try_select_takeoff_target():
		_takeoff_target = global_position + Vector3.UP * float(_behavior.cruise_altitude_min_blocks)
	on_ground = false
	velocity = Vector3.ZERO
	_ambient_departure_remaining = AMBIENT_DEPARTURE_SECONDS

func advance_retirement(delta: float) -> bool:
	if _ambient_departure_remaining > 0.0:
		var flight_delta := minf(delta, _ambient_departure_remaining)
		_advance_airborne(flight_delta, Vector3.ZERO)
		animation_driver.advance(flight_delta)
		_ambient_departure_remaining -= flight_delta
		delta -= flight_delta
		if _ambient_departure_remaining > 0.0:
			return false
		(animation_driver as BirdAnimationDriver).stop_flight_audio()
		super.begin_despawn_fade()
		if is_zero_approx(delta):
			return false
	return super.advance_retirement(delta)

func _update_vocalizations() -> void:
	if vocalizations == null:
		return
	var planar_speed_squared := Vector2(velocity.x, velocity.z).length_squared()
	var can_call := brain.state == BirdBrain.State.GROUNDED_IDLE and on_ground and planar_speed_squared <= 0.0001
	vocalizations.set_vocalizations_enabled(can_call)

func _has_approved_ground_contact() -> bool:
	var water_surface_y := _get_water_surface_y(floori(global_position.x), floori(global_position.z))
	if water_surface_y != VoxelSpace.NO_SURFACE_Y:
		if absf(water_surface_y - global_position.y) < 0.12:
			return _can_land_on_water()
		var feet_cell := Vector3i(floori(global_position.x), floori(global_position.y + 0.05), floori(global_position.z))
		if voxel_space.get_block_id_at(feet_cell) == BlockId.Type.WATER:
			return false
	var ground_y := VoxelBodySolver.get_ground_y(voxel_space, global_position, definition.body_width)
	var supporting_block_id := VoxelBodySolver.get_supporting_block_id(voxel_space, global_position, definition.body_width, ground_y)
	return definition.can_spawn_ambiently_on(supporting_block_id)

func _configure_vocalizations(behavior_seed: int) -> void:
	if vocalizations == null:
		return
	var selected_profile := vocalization_profile_override
	if selected_profile == null:
		assert(vocalization_profiles.size() == color_variant_count())
		selected_profile = vocalization_profiles[color_variant]
	if vocalizations.profile == selected_profile:
		return
	vocalizations.profile = selected_profile
	vocalizations.setup(behavior_seed)

func _advance_grounded(delta: float, separation_velocity: Vector3, navigation_search_budget: NavigationSearchBudget) -> void:
	if _can_land_on_water() and _is_on_water_surface(global_position):
		_advance_waterborne(delta, separation_velocity)
		return
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

func _advance_waterborne(delta: float, separation_velocity: Vector3) -> void:
	_water_ripple_remaining = maxf(_water_ripple_remaining - delta, 0.0)
	max_speed = _behavior.grounded_walk_speed
	var desired_velocity := separation_velocity
	if brain.state == BirdBrain.State.GROUNDED_WALK:
		var offset := brain.get_movement_goal() - global_position
		offset.y = 0.0
		if not offset.is_zero_approx():
			desired_velocity += offset.normalized() * max_speed
	desired_velocity = limit_planar_velocity(desired_velocity, max_speed)
	var requested_position := global_position + desired_velocity * delta
	if not _is_on_water_surface(requested_position):
		desired_velocity = Vector3.ZERO
	var result := VoxelBodySolver.sweep(voxel_space, global_position, desired_velocity, desired_velocity * delta, definition.body_width, definition.body_height)
	if _is_on_water_surface(result.position):
		global_position = result.position
		global_position.y = _get_water_surface_y(floori(global_position.x), floori(global_position.z))
		velocity = result.velocity
	else:
		velocity = Vector3.ZERO
	velocity.y = 0.0
	on_ground = true
	_apply_flight_yaw(delta, velocity)
	var planar_velocity := Vector2(velocity.x, velocity.z)
	if planar_velocity.length() >= WATER_RIPPLE_MINIMUM_SPEED and _water_ripple_remaining <= 0.0:
		water_surface_motion_committed.emit(global_position, planar_velocity)
		_water_ripple_remaining = _behavior.water_ripple_interval_seconds

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
	if brain.state == BirdBrain.State.DESCEND and _landing_on_water and global_position.distance_to(_landing_target) <= requested_motion.length() + 0.05:
		global_position = _landing_target
		velocity = Vector3.ZERO
		on_ground = true
		water_surface_motion_committed.emit(global_position, Vector2.ZERO)
		_water_ripple_remaining = _behavior.water_ripple_interval_seconds
		return
	var result := VoxelBodySolver.sweep(voxel_space, global_position, velocity, requested_motion, definition.body_width, definition.body_height)
	global_position = result.position
	velocity = result.velocity
	var ground_y := VoxelBodySolver.get_ground_y(voxel_space, global_position, definition.body_width)
	on_ground = velocity.y <= 0.0 and ground_y != VoxelSpace.NO_SURFACE_Y and absf(ground_y - global_position.y) < 0.12
	if on_ground:
		velocity.y = 0.0
	var expected_position := start_position + requested_motion
	var blocked := global_position.distance_squared_to(expected_position) > 0.04
	if blocked and brain.state == BirdBrain.State.TAKEOFF:
		_has_landing_target = false
		_landing_on_water = false
		if _try_select_takeoff_target():
			on_ground = false
		else:
			brain.reject_takeoff()
			velocity = Vector3.ZERO
	elif blocked and not on_ground:
		brain.reject_flight_goal()
		_has_landing_target = false
		_landing_on_water = false
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
			target = _takeoff_target
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
			return global_position.distance_to(_takeoff_target) <= FLIGHT_GOAL_DISTANCE
	return false

func _handle_state_transition(previous_state: BirdBrain.State, current_state: BirdBrain.State) -> void:
	if previous_state == current_state:
		return
	if current_state == BirdBrain.State.GROUNDED_IDLE:
		velocity = Vector3.ZERO
	elif current_state == BirdBrain.State.GROUNDED_WALK:
		_path_follower.request_repath()
	elif current_state == BirdBrain.State.TAKEOFF:
		if not _try_select_takeoff_target():
			brain.reject_takeoff()
			velocity = Vector3.ZERO
			return
		on_ground = false
	elif current_state == BirdBrain.State.CRUISE:
		_has_landing_target = false
		_landing_on_water = false
		_try_select_landing_target()

func _try_select_takeoff_target() -> bool:
	var altitude := float(brain.sample_cruise_altitude())
	if _takeoff_route_is_clear(global_position + Vector3.UP * altitude):
		return true
	for distance in TAKEOFF_ESCAPE_DISTANCES:
		for direction in TAKEOFF_ESCAPE_DIRECTIONS:
			if _takeoff_route_is_clear(global_position + direction * distance + Vector3.UP * altitude):
				return true
	return false

func _takeoff_route_is_clear(candidate: Vector3) -> bool:
	var motion := candidate - global_position
	var result := VoxelBodySolver.sweep(voxel_space, global_position, motion.normalized(), motion, definition.body_width, definition.body_height)
	if not result.position.is_equal_approx(candidate):
		return false
	_takeoff_target = candidate
	return true

func _try_select_landing_target() -> bool:
	for _attempt in LANDING_SEARCH_ATTEMPTS:
		var offset := brain.sample_landing_offset()
		var x := floori(global_position.x + offset.x)
		var z := floori(global_position.z + offset.y)
		var surface_top := voxel_space.get_highest_top(x, z)
		if surface_top == VoxelSpace.NO_SURFACE_Y:
			continue
		var water_surface_y := _get_water_surface_y(x, z)
		if water_surface_y != VoxelSpace.NO_SURFACE_Y:
			if not _can_land_on_water():
				continue
			var water_candidate := Vector3(float(x) + 0.5, water_surface_y, float(z) + 0.5)
			if VoxelBodySolver.collides_at(voxel_space, water_candidate, definition.body_width, definition.body_height, false):
				continue
			_landing_target = water_candidate
			_cruise_target = water_candidate + Vector3.UP * float(brain.sample_cruise_altitude())
			_has_landing_target = true
			_landing_on_water = true
			_landing_retry_remaining = 0.0
			return true
		var floor_y := floori(surface_top - 0.001)
		if not definition.can_spawn_ambiently_on(voxel_space.get_block_id_at(Vector3i(x, floor_y, z))):
			continue
		var landing_candidate := Vector3(float(x) + 0.5, surface_top, float(z) + 0.5)
		if not EntitySpawnGeometry.can_spawn_grounded(voxel_space, definition, landing_candidate):
			continue
		_landing_target = landing_candidate
		_cruise_target = landing_candidate + Vector3.UP * float(brain.sample_cruise_altitude())
		_has_landing_target = true
		_landing_on_water = false
		_landing_retry_remaining = 0.0
		return true
	_has_landing_target = false
	_landing_on_water = false
	_landing_retry_remaining = _behavior.landing_retry_seconds
	return false

func _can_land_on_water() -> bool:
	return color_variant == BirdAnimationDriver.ColorVariant.DUCK

func _is_on_water_surface(position: Vector3) -> bool:
	var water_surface_y := _get_water_surface_y(floori(position.x), floori(position.z))
	return water_surface_y != VoxelSpace.NO_SURFACE_Y and absf(water_surface_y - position.y) < 0.12

func _get_water_surface_y(x: int, z: int) -> float:
	var solid_top := voxel_space.get_highest_top(x, z)
	if solid_top == VoxelSpace.NO_SURFACE_Y:
		return VoxelSpace.NO_SURFACE_Y
	var water_y := floori(solid_top)
	if voxel_space.get_block_id_at(Vector3i(x, water_y, z)) != BlockId.Type.WATER:
		return VoxelSpace.NO_SURFACE_Y
	for _step in WATER_SURFACE_SEARCH_HEIGHT:
		if voxel_space.get_block_id_at(Vector3i(x, water_y + 1, z)) != BlockId.Type.WATER:
			return float(water_y) + VoxelSpace.WATER_SURFACE_HEIGHT
		water_y += 1
	return VoxelSpace.NO_SURFACE_Y

func _apply_flight_yaw(delta: float, flight_velocity: Vector3) -> void:
	var planar_velocity := Vector2(flight_velocity.x, flight_velocity.z)
	if planar_velocity.length_squared() <= 0.0001:
		return
	var target_yaw := atan2(flight_velocity.x, flight_velocity.z)
	model_root.rotation.y = lerp_angle(model_root.rotation.y, target_yaw, minf(delta * 8.0, 1.0))
