extends Node
class_name MeleeCombatCoordinator

const PLAYER_RUNTIME_ID: int = 0
const PLAYER_DEFINITION_ID: StringName = &"player"
const GEOMETRY_EPSILON: float = 0.000001

const MeleeAttackProfileType := preload("res://combat/melee_attack_profile.gd")
const MeleeContactType := preload("res://combat/melee_contact.gd")
const MeleeOutcomeType := preload("res://combat/melee_outcome.gd")
const VoxelLineOfSightType := preload("res://combat/voxel_line_of_sight.gd")

signal melee_outcome_committed(outcome: MeleeOutcomeType)

var _voxel_space: VoxelSpace
var _player: PlayerMotor
var _player_stats: ActorStats
var _entity_runtime: EntityRuntime

func setup(
	p_voxel_space: VoxelSpace,
	p_player: PlayerMotor,
	p_player_stats: ActorStats,
	p_entity_runtime: EntityRuntime,
) -> void:
	assert(p_voxel_space != null)
	assert(p_player != null)
	assert(p_player_stats != null)
	assert(p_player_stats.has_stat(&"hp"))
	assert(p_player_stats.has_stat(&"strength"))
	assert(p_player_stats.has_stat(&"defense"))
	assert(p_entity_runtime != null)
	_player = p_player
	_player_stats = p_player_stats
	bind_context(p_voxel_space, p_entity_runtime)

func bind_context(p_voxel_space: VoxelSpace, p_entity_runtime: EntityRuntime) -> void:
	assert(p_voxel_space != null)
	assert(p_entity_runtime != null)
	_voxel_space = p_voxel_space
	_entity_runtime = p_entity_runtime

func unbind_context() -> void:
	_voxel_space = null
	_entity_runtime = null

func acquire_player_targets(
	ray_origin: Vector3,
	ray_direction: Vector3,
	profile: MeleeAttackProfileType,
	impact_origin: Vector3 = Vector3.INF,
) -> Array[int]:
	assert(_is_setup())
	assert(profile != null)
	var result: Array[int] = []
	if not ray_origin.is_finite() or not ray_direction.is_finite() or ray_direction.is_zero_approx():
		return result
	var direction := ray_direction.normalized()
	var player_origin := _get_player_center()
	var attack_origin := player_origin if impact_origin == Vector3.INF else impact_origin
	assert(attack_origin.is_finite())
	var reach_extent := Vector3.ONE * (profile.reach + GEOMETRY_EPSILON)
	var candidate_ids := _entity_runtime.get_active_runtime_ids_overlapping(AABB(attack_origin - reach_extent, reach_extent * 2.0))
	if profile.sweep_degrees > 0.0:
		var planar_aim := Vector3.ZERO
		if profile.requires_planar_aim():
			planar_aim = _get_planar_aim(ray_origin, direction, player_origin)
			if planar_aim.is_zero_approx():
				return result
		for runtime_id in candidate_ids:
			var actor := _entity_runtime.get_actor(runtime_id)
			if actor != null and _get_valid_player_hit(actor, attack_origin, ray_origin, direction, planar_aim, profile) is Vector3:
				result.append(runtime_id)
		return result
	var nearest_runtime_id := -1
	var nearest_distance_squared := INF
	for runtime_id in candidate_ids:
		var actor := _entity_runtime.get_actor(runtime_id)
		if actor == null or actor.definition == null:
			continue
		var hit: Variant = _get_valid_player_hit(actor, attack_origin, ray_origin, direction, Vector3.ZERO, profile)
		if not hit is Vector3:
			continue
		var hit_position: Vector3 = hit
		var distance_squared := ray_origin.distance_squared_to(hit_position)
		if distance_squared < nearest_distance_squared or (is_equal_approx(distance_squared, nearest_distance_squared) and actor.runtime_id < nearest_runtime_id):
			nearest_runtime_id = actor.runtime_id
			nearest_distance_squared = distance_squared
	if nearest_runtime_id > PLAYER_RUNTIME_ID:
		result.append(nearest_runtime_id)
	return result

func try_commit_player_contacts(
	target_runtime_ids: Array[int],
	locked_ray_origin: Vector3,
	locked_ray_direction: Vector3,
	profile: MeleeAttackProfileType,
	source_item_id: StringName,
	impact_origin: Vector3 = Vector3.INF,
) -> bool:
	assert(_is_setup())
	assert(profile != null)
	if target_runtime_ids.is_empty() or source_item_id.is_empty():
		return false
	if not locked_ray_origin.is_finite() or not locked_ray_direction.is_finite() or locked_ray_direction.is_zero_approx():
		return false
	var direction := locked_ray_direction.normalized()
	var player_origin := _get_player_center()
	var attack_origin := player_origin if impact_origin == Vector3.INF else impact_origin
	assert(attack_origin.is_finite())
	var planar_aim := Vector3.ZERO
	if profile.requires_planar_aim():
		planar_aim = _get_planar_aim(locked_ray_origin, direction, player_origin)
		if planar_aim.is_zero_approx():
			return false
	var sorted_runtime_ids := target_runtime_ids.duplicate()
	sorted_runtime_ids.sort()
	var previous_runtime_id := -1
	var committed := false
	for target_runtime_id in sorted_runtime_ids:
		if target_runtime_id <= PLAYER_RUNTIME_ID or target_runtime_id == previous_runtime_id:
			continue
		previous_runtime_id = target_runtime_id
		var actor := _entity_runtime.get_actor(target_runtime_id)
		if actor == null or actor.definition == null:
			continue
		var hit: Variant = _get_valid_player_hit(actor, attack_origin, locked_ray_origin, direction, planar_aim, profile)
		if not hit is Vector3:
			continue
		var hit_position: Vector3 = hit
		var target_center := _get_bounds_center(actor.get_world_bounds())
		var radial_offset := target_center - attack_origin
		radial_offset.y = 0.0
		var hit_direction := radial_offset
		if hit_direction.is_zero_approx():
			hit_direction = attack_origin - player_origin
			hit_direction.y = 0.0
		if hit_direction.is_zero_approx():
			hit_direction = Vector3(direction.x, 0.0, direction.z)
		if hit_direction.is_zero_approx():
			continue
		var contact := MeleeContactType.new(
			PLAYER_RUNTIME_ID,
			PLAYER_DEFINITION_ID,
			actor.runtime_id,
			actor.definition.id,
			profile.id,
			hit_position,
			hit_direction,
		)
		if _commit_contact(contact, profile, source_item_id, radial_offset.length()):
			committed = true
	return committed

func try_commit_entity_contact(source_runtime_id: int, profile: MeleeAttackProfileType) -> bool:
	assert(_is_setup())
	assert(profile != null)
	if source_runtime_id <= PLAYER_RUNTIME_ID:
		return false
	var actor: EntityActor = _entity_runtime.get_actor(source_runtime_id)
	if not is_instance_valid(actor) or actor.definition == null:
		return false
	var source_position := actor.global_position
	var target_position := _player.global_position
	if source_position.distance_squared_to(target_position) > profile.reach * profile.reach:
		return false
	var source_origin := _get_bounds_center(actor.get_world_bounds())
	var target_origin := _get_player_center()
	var hit_direction := target_origin - source_origin
	if hit_direction.is_zero_approx() or not VoxelLineOfSightType.has_clear_path(_voxel_space, source_origin, target_origin):
		return false
	var hit: Variant = _get_player_bounds().intersects_ray(source_origin, hit_direction.normalized())
	if not hit is Vector3:
		return false
	var contact := MeleeContactType.new(
		actor.runtime_id,
		actor.definition.id,
		PLAYER_RUNTIME_ID,
		PLAYER_DEFINITION_ID,
		profile.id,
		hit as Vector3,
		hit_direction,
	)
	return _commit_contact(contact, profile, &"")

func shutdown() -> void:
	_voxel_space = null
	_player = null
	_player_stats = null
	_entity_runtime = null

func _commit_contact(contact: MeleeContactType, profile: MeleeAttackProfileType, source_item_id: StringName, distance_from_attack_center: float = 0.0) -> bool:
	assert(contact.attack_id == profile.id)
	assert(is_finite(distance_from_attack_center) and distance_from_attack_center >= 0.0)
	var applied_damage: float
	var target_defeated := false
	if contact.source_runtime_id == PLAYER_RUNTIME_ID:
		if _player_stats.is_dead():
			return false
		var target := _entity_runtime.get_actor(contact.target_runtime_id)
		if target == null or target.definition.id != contact.target_definition_id:
			return false
		var damage := profile.calculate_damage_at_distance(
			_player_stats.get_value(&"strength"),
			_entity_runtime.get_stat_value(contact.target_runtime_id, &"defense"),
			distance_from_attack_center,
		)
		var damage_result := _entity_runtime.try_apply_damage(contact.target_runtime_id, damage)
		if damage_result == null:
			return false
		applied_damage = damage_result.applied_damage
		target_defeated = damage_result.defeated
		if not target_defeated and profile.knockback_speed > 0.0:
			_entity_runtime.try_apply_knockback(contact.target_runtime_id, contact.hit_direction, profile.knockback_speed)
	else:
		if contact.target_runtime_id != PLAYER_RUNTIME_ID or contact.target_definition_id != PLAYER_DEFINITION_ID or _player_stats.is_dead():
			return false
		var source := _entity_runtime.get_actor(contact.source_runtime_id)
		if source == null or source.definition.id != contact.source_definition_id:
			return false
		var damage := profile.calculate_damage(
			_entity_runtime.get_stat_value(contact.source_runtime_id, &"strength"),
			_player_stats.get_value(&"defense"),
		)
		applied_damage = _player_stats.damage(damage)
		target_defeated = _player_stats.is_dead()
	melee_outcome_committed.emit(MeleeOutcomeType.new(contact, source_item_id, applied_damage, target_defeated))
	return true

func _is_valid_player_geometry(
	player_origin: Vector3,
	ray_origin: Vector3,
	hit_position: Vector3,
	profile: MeleeAttackProfileType,
) -> bool:
	if player_origin.distance_squared_to(hit_position) > profile.reach * profile.reach:
		return false
	return VoxelLineOfSightType.has_clear_path(_voxel_space, ray_origin, hit_position) and VoxelLineOfSightType.has_clear_path(_voxel_space, player_origin, hit_position)

func _get_valid_player_hit(
	actor: EntityActor,
	attack_origin: Vector3,
	ray_origin: Vector3,
	ray_direction: Vector3,
	planar_aim: Vector3,
	profile: MeleeAttackProfileType,
) -> Variant:
	var bounds := actor.get_world_bounds()
	var hit: Variant
	if profile.sweep_degrees > 0.0:
		var target_center := _get_bounds_center(bounds)
		var planar_target := target_center - attack_origin
		planar_target.y = 0.0
		if profile.requires_planar_aim():
			if planar_target.is_zero_approx():
				return null
			var minimum_dot := cos(deg_to_rad(profile.sweep_degrees * 0.5))
			if planar_aim.dot(planar_target.normalized()) + GEOMETRY_EPSILON < minimum_dot:
				return null
		var target_direction := target_center - attack_origin
		if target_direction.is_zero_approx():
			return null
		hit = target_center if bounds.has_point(attack_origin) else bounds.intersects_ray(attack_origin, target_direction.normalized())
	else:
		hit = bounds.intersects_ray(ray_origin, ray_direction)
	if not hit is Vector3:
		return null
	var hit_position: Vector3 = hit
	if profile.sweep_degrees > 0.0:
		if attack_origin.distance_squared_to(hit_position) > profile.reach * profile.reach:
			return null
		if not VoxelLineOfSightType.has_clear_path(_voxel_space, attack_origin, hit_position):
			return null
	elif not _is_valid_player_geometry(attack_origin, ray_origin, hit_position, profile):
		return null
	return hit_position

func _get_planar_aim(ray_origin: Vector3, ray_direction: Vector3, player_origin: Vector3) -> Vector3:
	var planar_aim: Vector3
	if absf(ray_direction.y) > GEOMETRY_EPSILON:
		var intersection_distance := (player_origin.y - ray_origin.y) / ray_direction.y
		if intersection_distance < 0.0:
			return Vector3.ZERO
		planar_aim = ray_origin + ray_direction * intersection_distance - player_origin
		planar_aim.y = 0.0
	else:
		planar_aim = Vector3(ray_direction.x, 0.0, ray_direction.z)
	if not planar_aim.is_finite() or planar_aim.is_zero_approx():
		return Vector3.ZERO
	return planar_aim.normalized()

func _get_player_bounds() -> AABB:
	var half_width := _player.player_width * 0.5
	return AABB(
		_player.global_position + Vector3(-half_width, 0.0, -half_width),
		Vector3(_player.player_width, _player.player_height, _player.player_width),
	)

func _get_player_center() -> Vector3:
	return _get_bounds_center(_get_player_bounds())

func _get_bounds_center(bounds: AABB) -> Vector3:
	return bounds.position + bounds.size * 0.5

func _is_setup() -> bool:
	return _voxel_space != null and _player != null and _player_stats != null and _entity_runtime != null
