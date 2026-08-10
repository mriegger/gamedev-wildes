extends Node
class_name MeleeCombatCoordinator

const PLAYER_RUNTIME_ID: int = 0
const PLAYER_DEFINITION_ID: StringName = &"player"

const MeleeAttackProfileType := preload("res://combat/melee_attack_profile.gd")
const MeleeContactType := preload("res://combat/melee_contact.gd")
const VoxelLineOfSightType := preload("res://combat/voxel_line_of_sight.gd")

signal melee_contact_committed(contact: MeleeContactType)

var _voxel_world: VoxelWorld
var _player: PlayerMotor
var _entity_coordinator: EntityCoordinator

func setup(
	p_voxel_world: VoxelWorld,
	p_player: PlayerMotor,
	p_entity_coordinator: EntityCoordinator,
) -> void:
	assert(p_voxel_world != null)
	assert(p_player != null)
	assert(p_entity_coordinator != null)
	_voxel_world = p_voxel_world
	_player = p_player
	_entity_coordinator = p_entity_coordinator

func acquire_player_target(ray_origin: Vector3, ray_direction: Vector3, profile: MeleeAttackProfileType) -> int:
	assert(_is_setup())
	assert(profile != null)
	if not ray_origin.is_finite() or not ray_direction.is_finite() or ray_direction.is_zero_approx():
		return -1
	var direction := ray_direction.normalized()
	var player_origin := _get_player_center()
	var nearest_runtime_id := -1
	var nearest_distance_squared := INF
	for actor in _entity_coordinator.get_active_actors():
		if not is_instance_valid(actor) or actor.definition == null:
			continue
		var hit: Variant = actor.get_world_bounds().intersects_ray(ray_origin, direction)
		if not hit is Vector3:
			continue
		var hit_position: Vector3 = hit
		if not _is_valid_player_geometry(player_origin, ray_origin, hit_position, profile):
			continue
		var distance_squared := ray_origin.distance_squared_to(hit_position)
		if distance_squared < nearest_distance_squared or (is_equal_approx(distance_squared, nearest_distance_squared) and actor.runtime_id < nearest_runtime_id):
			nearest_runtime_id = actor.runtime_id
			nearest_distance_squared = distance_squared
	return nearest_runtime_id

func try_commit_player_contact(
	target_runtime_id: int,
	locked_ray_origin: Vector3,
	locked_ray_direction: Vector3,
	profile: MeleeAttackProfileType,
) -> bool:
	assert(_is_setup())
	assert(profile != null)
	if target_runtime_id <= PLAYER_RUNTIME_ID:
		return false
	if not locked_ray_origin.is_finite() or not locked_ray_direction.is_finite() or locked_ray_direction.is_zero_approx():
		return false
	var actor: EntityActor = _entity_coordinator.get_actor(target_runtime_id)
	if not is_instance_valid(actor) or actor.definition == null:
		return false
	var hit: Variant = actor.get_world_bounds().intersects_ray(locked_ray_origin, locked_ray_direction.normalized())
	if not hit is Vector3:
		return false
	var hit_position: Vector3 = hit
	var player_origin := _get_player_center()
	if not _is_valid_player_geometry(player_origin, locked_ray_origin, hit_position, profile):
		return false
	var hit_direction := hit_position - player_origin
	if hit_direction.is_zero_approx():
		return false
	var contact := MeleeContactType.new(
		PLAYER_RUNTIME_ID,
		PLAYER_DEFINITION_ID,
		actor.runtime_id,
		actor.definition.id,
		profile.id,
		hit_position,
		hit_direction,
	)
	return _commit_contact(contact)

func try_commit_entity_contact(source_runtime_id: int, profile: MeleeAttackProfileType) -> bool:
	assert(_is_setup())
	assert(profile != null)
	if source_runtime_id <= PLAYER_RUNTIME_ID:
		return false
	var actor: EntityActor = _entity_coordinator.get_actor(source_runtime_id)
	if not is_instance_valid(actor) or actor.definition == null:
		return false
	var source_position := actor.global_position
	var target_position := _player.global_position
	if source_position.distance_squared_to(target_position) > profile.reach * profile.reach:
		return false
	var source_origin := _get_bounds_center(actor.get_world_bounds())
	var target_origin := _get_player_center()
	var hit_direction := target_origin - source_origin
	if hit_direction.is_zero_approx() or not VoxelLineOfSightType.has_clear_path(_voxel_world, source_origin, target_origin):
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
	return _commit_contact(contact)

func shutdown() -> void:
	_voxel_world = null
	_player = null
	_entity_coordinator = null

func _commit_contact(contact: MeleeContactType) -> bool:
	melee_contact_committed.emit(contact)
	return true

func _is_valid_player_geometry(
	player_origin: Vector3,
	ray_origin: Vector3,
	hit_position: Vector3,
	profile: MeleeAttackProfileType,
) -> bool:
	if player_origin.distance_squared_to(hit_position) > profile.reach * profile.reach:
		return false
	return VoxelLineOfSightType.has_clear_path(_voxel_world, ray_origin, hit_position) and VoxelLineOfSightType.has_clear_path(_voxel_world, player_origin, hit_position)

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
	return _voxel_world != null and _player != null and _entity_coordinator != null
