extends EntityActor
class_name ZombieActor

const VISION_SAMPLE_INTERVAL_SECONDS: float = 0.125
const VISION_PHASE_COUNT: int = 8

@export_node_path("AudioStreamPlayer3D") var vocalizations_path: NodePath

var brain: ZombieBrain

var _behavior: ZombieBehaviorDefinition
var _zombie_animation: ZombieAnimationDriver
var _vocalizations: ZombieVocalizations
var _path_follower: VoxelPathFollower
var _melee_profile: MeleeAttackProfile
var _melee_elapsed: float = 0.0
var _melee_contact_pending: bool = false
var _player_visible: bool = false
var _vision_sample_remaining: float = 0.0

func supports_behavior(behavior: EntityBehaviorDefinition) -> bool:
	return behavior is ZombieBehaviorDefinition


func has_valid_presentation() -> bool:
	return (
		super.has_valid_presentation()
		and not vocalizations_path.is_empty()
		and get_node_or_null(vocalizations_path) is ZombieVocalizations
	)


func setup(p_runtime_id: int, p_definition: EntityDefinition, p_voxel_world: VoxelWorld, behavior_seed: int):
	super.setup(p_runtime_id, p_definition, p_voxel_world, behavior_seed)
	_behavior = p_definition.behavior as ZombieBehaviorDefinition
	assert(_behavior != null)
	brain = ZombieBrain.new(_behavior, behavior_seed)
	_path_follower = VoxelPathFollower.new(voxel_world, definition.body_width, definition.body_height, _behavior.repath_seconds)
	max_speed = _behavior.wander_speed
	_zombie_animation = animation_driver as ZombieAnimationDriver
	assert(_zombie_animation != null)
	_vocalizations = get_node(vocalizations_path) as ZombieVocalizations
	assert(_vocalizations != null)
	_vocalizations.setup(behavior_seed)
	_player_visible = false
	_vision_sample_remaining = VISION_SAMPLE_INTERVAL_SECONDS * float(runtime_id % VISION_PHASE_COUNT) / float(VISION_PHASE_COUNT)


func begin_despawn_fade():
	_vocalizations.stop_vocalizations()
	super.begin_despawn_fade()

func tick(delta: float, player_position: Vector3, separation_velocity: Vector3, navigation_search_budget: NavigationSearchBudget):
	assert(brain != null and voxel_world != null)
	_advance_melee_contact(delta)
	var visible := _sample_player_visibility(delta, player_position)
	var previous_state := brain.state
	brain.advance(delta, global_position, player_position, visible)
	if brain.state != previous_state and brain.state != ZombieBrain.State.ATTACK:
		_path_follower.request_repath()
	var attacking := brain.state == ZombieBrain.State.ATTACK
	var chasing := brain.state == ZombieBrain.State.CHASE
	_zombie_animation.set_chasing(chasing)
	if brain.consume_attack_started():
		var melee_profile := _behavior.melee_profile
		play_attack(melee_profile.duration)
		_arm_melee_contact(melee_profile)
	var desired_velocity := Vector3.ZERO
	if not attacking:
		var goal := brain.get_movement_goal()
		var reach_squared := _behavior.melee_profile.reach * _behavior.melee_profile.reach
		if not (chasing and global_position.distance_squared_to(player_position) <= reach_squared):
			desired_velocity = _get_path_velocity(delta, goal, _behavior.chase_speed if chasing else _behavior.wander_speed, navigation_search_budget)
	max_speed = _behavior.chase_speed if chasing else _behavior.wander_speed
	desired_velocity = limit_planar_velocity(desired_velocity + separation_velocity, max_speed)
	advance_voxel_motion(delta, desired_velocity, _behavior.gravity)

func _arm_melee_contact(profile: MeleeAttackProfile):
	assert(profile != null)
	_melee_profile = profile
	_melee_elapsed = 0.0
	_melee_contact_pending = true
	if is_zero_approx(profile.contact_time):
		_emit_melee_contact()

func _advance_melee_contact(delta: float):
	if not _melee_contact_pending:
		return
	var previous_elapsed := _melee_elapsed
	_melee_elapsed = minf(_melee_elapsed + delta, _melee_profile.duration)
	if previous_elapsed < _melee_profile.contact_time and _melee_elapsed >= _melee_profile.contact_time:
		_emit_melee_contact()

func _emit_melee_contact():
	var profile := _melee_profile
	_melee_contact_pending = false
	_melee_profile = null
	melee_contact_reached.emit(runtime_id, profile)

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
	_player_visible = VoxelLineOfSight.has_clear_path(voxel_world, origin, target)
	return _player_visible
