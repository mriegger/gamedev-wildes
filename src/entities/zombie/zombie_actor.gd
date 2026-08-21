extends EntityActor
class_name ZombieActor

const TimedMeleeContactType := preload("res://combat/timed_melee_contact.gd")
const VoxelPlayerVisibilitySensorType := preload("res://entities/awareness/voxel_player_visibility_sensor.gd")

var brain: GroundMeleeEnemyBrain

var _behavior: GroundMeleeEnemyBehaviorDefinition
var _zombie_animation: ZombieAnimationDriver
var _path_follower: VoxelPathFollower
var _timed_melee_contact := TimedMeleeContactType.new()
var _visibility_sensor: VoxelPlayerVisibilitySensorType

func supports_behavior(behavior: EntityBehaviorDefinition) -> bool:
	return behavior is GroundMeleeEnemyBehaviorDefinition

func is_aggroed() -> bool:
	return brain != null and brain.state != GroundMeleeEnemyBrain.State.WANDER


func setup(
	p_runtime_id: int,
	p_definition: EntityDefinition,
	p_voxel_space: VoxelSpace,
	behavior_seed: int,
	navigation_limits: EntityNavigationLimits,
):
	super.setup(p_runtime_id, p_definition, p_voxel_space, behavior_seed, navigation_limits)
	_behavior = p_definition.behavior as GroundMeleeEnemyBehaviorDefinition
	assert(_behavior != null)
	brain = GroundMeleeEnemyBrain.new(_behavior, behavior_seed)
	_path_follower = VoxelPathFollower.new(voxel_space, definition.body_width, definition.body_height, _behavior.repath_seconds, navigation_limits)
	max_speed = _behavior.wander_speed
	_zombie_animation = animation_driver as ZombieAnimationDriver
	assert(_zombie_animation != null)
	_visibility_sensor = VoxelPlayerVisibilitySensorType.new(voxel_space, _behavior.detection_range, definition.body_height, runtime_id)


func tick_gameplay(
	delta: float,
	observation: EntityTargetObservation,
	separation_velocity: Vector3,
	navigation_search_budget: NavigationSearchBudget,
) -> void:
	assert(brain != null and voxel_space != null)
	assert(observation != null and observation.validate())
	var player_position := observation.player_position
	_emit_melee_contact(_timed_melee_contact.advance(delta))
	var visible := _visibility_sensor.advance(delta, global_position, player_position)
	var previous_state := brain.state
	brain.advance(
		delta,
		global_position,
		player_position,
		visible,
		_visibility_sensor.did_sample_line_of_sight(),
	)
	if brain.state != previous_state and brain.state != GroundMeleeEnemyBrain.State.ATTACK:
		_path_follower.request_repath()
	var attacking := brain.state == GroundMeleeEnemyBrain.State.ATTACK
	var chasing := brain.state == GroundMeleeEnemyBrain.State.CHASE
	_zombie_animation.set_chasing(chasing)
	if brain.consume_attack_started():
		var melee_profile := _behavior.melee_profile
		play_attack(melee_profile.duration)
		_emit_melee_contact(_timed_melee_contact.arm(melee_profile))
	var desired_velocity := Vector3.ZERO
	if not attacking:
		var goal := brain.get_movement_goal()
		var reach_squared := _behavior.melee_profile.reach * _behavior.melee_profile.reach
		if not (chasing and global_position.distance_squared_to(player_position) <= reach_squared):
			desired_velocity = _get_path_velocity(delta, goal, _behavior.chase_speed if chasing else _behavior.wander_speed, navigation_search_budget)
	max_speed = _behavior.chase_speed if chasing else _behavior.wander_speed
	desired_velocity = limit_planar_velocity(desired_velocity + separation_velocity, max_speed)
	advance_voxel_motion(delta, desired_velocity, _behavior.gravity)

func tick_ambient(
	delta: float,
	separation_velocity: Vector3,
	navigation_search_budget: NavigationSearchBudget,
) -> void:
	assert(brain != null and voxel_space != null)
	_timed_melee_contact.cancel()
	brain.advance_ambient(delta, global_position)
	_zombie_animation.set_chasing(false)
	max_speed = _behavior.wander_speed
	var desired_velocity := _get_path_velocity(
		delta,
		brain.get_movement_goal(),
		max_speed,
		navigation_search_budget,
	)
	desired_velocity = limit_planar_velocity(desired_velocity + separation_velocity, max_speed)
	advance_voxel_motion(delta, desired_velocity, _behavior.gravity)

func _emit_melee_contact(profile: MeleeAttackProfile) -> void:
	if profile != null:
		melee_contact_reached.emit(runtime_id, profile)

func begin_death_retirement():
	_timed_melee_contact.cancel()
	super.begin_death_retirement()

func try_begin_player_hit_response(player_position: Vector3) -> bool:
	if brain == null or brain.is_alerted():
		return false
	brain.alert_to_player(player_position)
	_path_follower.request_repath()
	max_speed = _behavior.chase_speed
	_zombie_animation.set_chasing(true)
	return true

func supports_player_hit_response() -> bool:
	return true

func _get_path_velocity(delta: float, goal: Vector3, speed: float, navigation_search_budget: NavigationSearchBudget) -> Vector3:
	var result := _path_follower.advance(delta, global_position, goal, speed, on_ground, navigation_search_budget)
	if result.path_failed:
		brain.reject_wander_goal()
	return apply_path_follow_result(result, delta, _behavior.jump_velocity)
