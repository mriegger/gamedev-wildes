extends EntityActor
class_name ZombieActor

const TimedMeleeContactType := preload("res://combat/timed_melee_contact.gd")

const VISION_SAMPLE_INTERVAL_SECONDS: float = 0.125
const VISION_PHASE_COUNT: int = 8

var brain: GroundMeleeEnemyBrain

var _behavior: GroundMeleeEnemyBehaviorDefinition
var _zombie_animation: ZombieAnimationDriver
var _path_follower: VoxelPathFollower
var _timed_melee_contact := TimedMeleeContactType.new()
var _player_visible: bool = false
var _vision_sample_remaining: float = 0.0

func supports_behavior(behavior: EntityBehaviorDefinition) -> bool:
	return behavior is GroundMeleeEnemyBehaviorDefinition


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
	_player_visible = false
	_vision_sample_remaining = VISION_SAMPLE_INTERVAL_SECONDS * float(runtime_id % VISION_PHASE_COUNT) / float(VISION_PHASE_COUNT)


func tick(delta: float, observation: EntityTargetObservation, separation_velocity: Vector3, navigation_search_budget: NavigationSearchBudget):
	assert(brain != null and voxel_space != null)
	assert(observation != null and observation.validate())
	var player_position := observation.player_position
	_emit_melee_contact(_timed_melee_contact.advance(delta))
	var visible := _sample_player_visibility(delta, player_position)
	var previous_state := brain.state
	brain.advance(delta, global_position, player_position, visible)
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

func _emit_melee_contact(profile: MeleeAttackProfile) -> void:
	if profile != null:
		melee_contact_reached.emit(runtime_id, profile)

func begin_death_retirement():
	_timed_melee_contact.cancel()
	super.begin_death_retirement()

func _get_path_velocity(delta: float, goal: Vector3, speed: float, navigation_search_budget: NavigationSearchBudget) -> Vector3:
	var result := _path_follower.advance(delta, global_position, goal, speed, on_ground, navigation_search_budget)
	if result.path_failed:
		brain.reject_wander_goal()
	return apply_path_follow_result(result, delta, _behavior.jump_velocity)

func _sample_player_visibility(delta: float, player_position: Vector3) -> bool:
	_vision_sample_remaining -= delta
	var sample_due := _vision_sample_remaining <= 0.0
	if sample_due:
		_vision_sample_remaining = fposmod(_vision_sample_remaining, VISION_SAMPLE_INTERVAL_SECONDS)
		if is_zero_approx(_vision_sample_remaining):
			_vision_sample_remaining = VISION_SAMPLE_INTERVAL_SECONDS
	if global_position.distance_squared_to(player_position) > _behavior.detection_range * _behavior.detection_range:
		_player_visible = false
		return false
	if not sample_due:
		return _player_visible
	var origin := global_position + Vector3.UP * minf(definition.body_height * 0.8, 1.4)
	var target := player_position + Vector3.UP * 0.9
	_player_visible = VoxelLineOfSight.has_clear_path(voxel_space, origin, target)
	return _player_visible
