extends EntityActor
class_name SlimeActor

const VISION_SAMPLE_INTERVAL_SECONDS: float = 0.125
const VISION_PHASE_COUNT: int = 8

var brain: SlimeBrain

var _behavior: SlimeBehaviorDefinition
var _path_follower: VoxelPathFollower
var _player_visible: bool = false
var _vision_sample_remaining: float = 0.0
var _hop_active: bool = false
var _attachment_slot_index: int = -1
var _attachment_damage_remaining: float = 0.0
var _initial_attachment_contact_pending: bool = false
var _reattach_cooldown_remaining: float = 0.0
var _defeat_spawn_launch_active: bool = false

func supports_behavior(behavior: EntityBehaviorDefinition) -> bool:
	return behavior is SlimeBehaviorDefinition

func is_aggroed() -> bool:
	return brain != null and brain.state != SlimeBrain.State.WANDER

func setup(
	p_runtime_id: int,
	p_definition: EntityDefinition,
	p_voxel_space: VoxelSpace,
	behavior_seed: int,
	navigation_limits: EntityNavigationLimits,
) -> void:
	super.setup(p_runtime_id, p_definition, p_voxel_space, behavior_seed, navigation_limits)
	_behavior = p_definition.behavior as SlimeBehaviorDefinition
	assert(_behavior != null)
	brain = SlimeBrain.new(_behavior, behavior_seed)
	_path_follower = VoxelPathFollower.new(
		voxel_space,
		definition.body_width,
		definition.body_height,
		_behavior.repath_seconds,
		navigation_limits,
	)
	var slime_animation := animation_driver as SlimeAnimationDriver
	assert(slime_animation != null)
	slime_animation.configure_dimensions(definition.body_width, definition.body_height)
	death_poof.position.y = definition.body_height * 0.5
	max_speed = _behavior.wander_speed
	_player_visible = false
	_vision_sample_remaining = VISION_SAMPLE_INTERVAL_SECONDS * float(runtime_id % VISION_PHASE_COUNT) / float(VISION_PHASE_COUNT)
	_hop_active = false
	_attachment_slot_index = -1
	_attachment_damage_remaining = _behavior.attachment_damage_profile.cooldown
	_initial_attachment_contact_pending = false
	_reattach_cooldown_remaining = 0.0
	_defeat_spawn_launch_active = false

func tick(
	delta: float,
	observation: EntityTargetObservation,
	separation_velocity: Vector3,
	navigation_search_budget: NavigationSearchBudget,
) -> void:
	assert(brain != null and voxel_space != null)
	assert(observation != null and observation.validate())
	_reattach_cooldown_remaining = maxf(_reattach_cooldown_remaining - delta, 0.0)
	if _defeat_spawn_launch_active:
		advance_voxel_motion(delta, Vector3.ZERO, _behavior.gravity)
		if on_ground:
			_defeat_spawn_launch_active = false
			velocity = Vector3.ZERO
			knockback_velocity = Vector3.ZERO
		return
	var player_position := observation.player_position
	if is_attached():
		brain.advance(delta, global_position, player_position, true, true, false)
		velocity = Vector3.ZERO
		knockback_velocity = Vector3.ZERO
		_advance_attachment_damage(delta)
		return

	var visible := _sample_player_visibility(delta, player_position)
	brain.advance(delta, global_position, player_position, visible, false, on_ground)
	if brain.consume_hop_started():
		_hop_active = true
		velocity.y = _behavior.jump_velocity
		_path_follower.request_repath()

	var chasing := brain.state == SlimeBrain.State.CHASE
	max_speed = _behavior.chase_speed if chasing else _behavior.wander_speed
	var desired_velocity := Vector3.ZERO
	if _hop_active:
		desired_velocity = _get_path_velocity(delta, brain.get_movement_goal(), max_speed, navigation_search_budget)
		desired_velocity = limit_planar_velocity(desired_velocity + separation_velocity, max_speed)
	advance_voxel_motion(delta, desired_velocity, _behavior.gravity)
	if _hop_active and on_ground and is_zero_approx(velocity.y):
		_hop_active = false

func is_attached() -> bool:
	return _attachment_slot_index >= 0

func can_attach() -> bool:
	return (
		_behavior != null
		and not is_attached()
		and not _defeat_spawn_launch_active
		and is_zero_approx(_reattach_cooldown_remaining)
	)

func begin_defeat_spawn_launch(direction: Vector3, planar_speed: float, vertical_speed: float) -> bool:
	if is_attached() or _defeat_spawn_launch_active:
		return false
	if not super.begin_defeat_spawn_launch(direction, planar_speed, vertical_speed):
		return false
	_defeat_spawn_launch_active = true
	_hop_active = false
	return true

func attach(slot_index: int) -> bool:
	if slot_index < 0 or not can_attach():
		return false
	_attachment_slot_index = slot_index
	_attachment_damage_remaining = _behavior.attachment_damage_profile.cooldown
	_initial_attachment_contact_pending = true
	_hop_active = false
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	on_ground = false
	return true

func commit_initial_attachment_contact() -> bool:
	if not is_attached() or not _initial_attachment_contact_pending:
		return false
	_initial_attachment_contact_pending = false
	melee_contact_reached.emit(runtime_id, _behavior.attachment_damage_profile)
	return true

func detach(direction: Vector3, knockback_speed: float, reattach_cooldown_seconds: float) -> bool:
	if not is_attached() or not direction.is_finite() or direction.is_zero_approx():
		return false
	if not is_finite(knockback_speed) or knockback_speed < 0.0:
		return false
	if not is_finite(reattach_cooldown_seconds) or reattach_cooldown_seconds < 0.0:
		return false
	var planar_direction := Vector3(direction.x, 0.0, direction.z)
	if knockback_speed > 0.0 and planar_direction.is_zero_approx():
		return false
	_attachment_slot_index = -1
	_attachment_damage_remaining = _behavior.attachment_damage_profile.cooldown
	_initial_attachment_contact_pending = false
	_reattach_cooldown_remaining = reattach_cooldown_seconds
	_hop_active = false
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	if knockback_speed > 0.0:
		var applied := apply_knockback(planar_direction, knockback_speed)
		assert(applied)
		return applied
	return true

func get_attachment_slow_fraction() -> float:
	assert(_behavior != null)
	return _behavior.attachment_slow_fraction

func begin_despawn_fade() -> void:
	_defeat_spawn_launch_active = false
	_clear_attachment()
	super.begin_despawn_fade()

func begin_death_retirement() -> void:
	_defeat_spawn_launch_active = false
	_clear_attachment()
	super.begin_death_retirement()

func try_begin_player_hit_response(player_position: Vector3) -> bool:
	if brain == null or brain.state != SlimeBrain.State.WANDER:
		return false
	brain.alert_to_player(player_position)
	_path_follower.request_repath()
	max_speed = _behavior.chase_speed
	return true

func supports_player_hit_response() -> bool:
	return true

func _advance_attachment_damage(delta: float) -> void:
	_attachment_damage_remaining -= delta
	while _attachment_damage_remaining < 0.0 or is_zero_approx(_attachment_damage_remaining):
		melee_contact_reached.emit(runtime_id, _behavior.attachment_damage_profile)
		_attachment_damage_remaining += _behavior.attachment_damage_profile.cooldown

func _clear_attachment() -> void:
	_attachment_slot_index = -1
	_attachment_damage_remaining = _behavior.attachment_damage_profile.cooldown if _behavior != null else 0.0
	_initial_attachment_contact_pending = false

func _get_path_velocity(
	delta: float,
	goal: Vector3,
	speed: float,
	navigation_search_budget: NavigationSearchBudget,
) -> Vector3:
	var result := _path_follower.advance(
		delta,
		global_position,
		goal,
		speed,
		on_ground,
		navigation_search_budget,
	)
	if result.path_failed:
		brain.reject_movement_goal(global_position)
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
	var origin := global_position + Vector3.UP * minf(definition.body_height * 0.7, 1.0)
	var target := player_position + Vector3.UP * 0.9
	_player_visible = VoxelLineOfSight.has_clear_path(voxel_space, origin, target)
	return _player_visible
