extends Node3D
class_name ArrowProjectileRuntime

const MAXIMUM_ACTIVE_PROJECTILES: int = 64
const TRAJECTORY_STEP_SECONDS: float = 1.0 / 60.0

class ActiveProjectile:
	var view: NockableArrowView
	var trail: ArrowTrailView
	var ammunition: ArrowItemDefinition
	var source_item_id: StringName
	var launch_position: Vector3
	var launch_velocity: Vector3
	var velocity: Vector3
	var damage_multiplier: float = 1.0
	var flight_elapsed: float = 0.0
	var flight_step_accumulator: float = 0.0
	var embedded_elapsed: float = -1.0

var _inventory: InventoryModel
var _inventory_loadout: InventoryLoadoutCoordinator
var _combat: MeleeCombatCoordinator
var _voxel_space: VoxelSpace
var _entity_runtime: EntityRuntime
var _projectiles: Array[ActiveProjectile] = []

func _ready() -> void:
	set_physics_process(false)

func setup(
	inventory: InventoryModel,
	inventory_loadout: InventoryLoadoutCoordinator,
	combat: MeleeCombatCoordinator,
) -> void:
	assert(inventory != null)
	assert(inventory_loadout != null and inventory_loadout.inventory_model == inventory)
	assert(combat != null)
	assert(_inventory == null and _inventory_loadout == null and _combat == null)
	_inventory = inventory
	_inventory_loadout = inventory_loadout
	_combat = combat

func bind_context(voxel_space: VoxelSpace, entity_runtime: EntityRuntime) -> void:
	assert(voxel_space != null and entity_runtime != null)
	clear()
	_voxel_space = voxel_space
	_entity_runtime = entity_runtime

func unbind_context() -> void:
	clear()
	_voxel_space = null
	_entity_runtime = null

func get_available_ammunition(action: BowDrawActionDefinition) -> ArrowItemDefinition:
	if action == null or _inventory == null:
		return null
	for index in range(mini(_inventory.get_size(), InventoryModel.FILLABLE_SIZE)):
		var stack := _inventory.get_slot(index)
		if stack == null:
			continue
		var ammunition := _inventory.item_catalog.get_definition(stack.item_id) as ArrowItemDefinition
		if ammunition != null and ammunition in action.ammunition:
			return ammunition
	return null

func predict_trajectory(
	action: BowDrawActionDefinition,
	ammunition: ArrowItemDefinition,
	draw_progress: float,
	release_transform: Transform3D,
) -> PackedVector3Array:
	var points := PackedVector3Array()
	if (
		_voxel_space == null
		or _entity_runtime == null
		or action == null
		or ammunition == null
		or ammunition.projectile_profile == null
		or ammunition not in action.ammunition
		or not is_finite(draw_progress)
		or draw_progress < 0.0
		or draw_progress > 1.0
		or not release_transform.is_finite()
	):
		return points
	var launch_velocity := _get_launch_velocity(action, draw_progress, release_transform)
	if launch_velocity.is_zero_approx():
		return points
	var profile := ammunition.projectile_profile
	var launch_position := release_transform.origin
	var previous_position := launch_position
	var elapsed := 0.0
	points.append(launch_position)
	while elapsed < profile.maximum_flight_seconds:
		var next_elapsed := elapsed + _get_trajectory_step_duration(profile, elapsed)
		var destination := _calculate_trajectory_position(launch_position, launch_velocity, profile.gravity, next_elapsed)
		var hit := _get_first_hit(previous_position, destination, profile.collision_radius)
		if not hit.is_empty():
			points.append(hit["position"] as Vector3)
			break
		points.append(destination)
		previous_position = destination
		elapsed = next_elapsed
	return points

func try_fire(
	bow_source: SelectedItemSource,
	action: BowDrawActionDefinition,
	ammunition: ArrowItemDefinition,
	draw_progress: float,
	release_transform: Transform3D,
) -> bool:
	if (
		_voxel_space == null
		or _entity_runtime == null
		or bow_source == null
		or action == null
		or ammunition == null
		or not is_finite(draw_progress)
		or draw_progress < 0.0
		or draw_progress > 1.0
		or not release_transform.is_finite()
		or not _inventory.is_selected_item_source_current(bow_source)
		or ammunition not in action.ammunition
	):
		return false
	var selected_item := _inventory.item_catalog.get_definition(bow_source.get_item_id())
	if selected_item.primary_action != action:
		return false
	var ammunition_index := _find_ammunition_index(ammunition.id)
	if ammunition_index < 0:
		return false
	var inventory_change := _inventory.prepare_remove_stack(ammunition_index, 1)
	var loadout_change := _inventory_loadout.prepare_inventory_change(inventory_change)
	if loadout_change == null:
		return false
	var view := ammunition.held_scene.instantiate() as NockableArrowView
	if view == null:
		return false
	var trail := ArrowTrailView.new()
	var launch_velocity := _get_launch_velocity(action, draw_progress, release_transform)
	if launch_velocity.is_zero_approx():
		view.free()
		trail.free()
		return false
	if not _inventory_loadout.commit_prepared_change(loadout_change):
		view.free()
		trail.free()
		return false
	if _projectiles.size() >= MAXIMUM_ACTIVE_PROJECTILES:
		_remove_projectile(0)
	add_child(view)
	add_child(trail)
	view.global_transform = release_transform
	trail.start(release_transform.origin)
	var projectile := ActiveProjectile.new()
	projectile.view = view
	projectile.trail = trail
	projectile.ammunition = ammunition
	projectile.source_item_id = bow_source.get_item_id()
	projectile.launch_position = release_transform.origin
	projectile.launch_velocity = launch_velocity
	projectile.velocity = launch_velocity
	projectile.damage_multiplier = action.get_damage_multiplier(draw_progress)
	_projectiles.append(projectile)
	_orient_projectile(projectile)
	set_physics_process(true)
	return true

func clear() -> void:
	for projectile in _projectiles:
		if is_instance_valid(projectile.view):
			projectile.view.free()
		if is_instance_valid(projectile.trail):
			projectile.trail.free()
	_projectiles.clear()
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	advance_projectiles(delta)

func advance_projectiles(delta: float) -> void:
	assert(is_finite(delta) and delta >= 0.0)
	for index in range(_projectiles.size() - 1, -1, -1):
		var projectile := _projectiles[index]
		if projectile.embedded_elapsed >= 0.0:
			_advance_embedded_projectile(index, projectile, delta)
		else:
			_advance_flying_projectile(index, projectile, delta)
	if _projectiles.is_empty():
		set_physics_process(false)

func _advance_flying_projectile(index: int, projectile: ActiveProjectile, delta: float) -> void:
	var profile := projectile.ammunition.projectile_profile
	projectile.flight_step_accumulator += delta
	while projectile.flight_elapsed < profile.maximum_flight_seconds:
		var step_duration := _get_trajectory_step_duration(profile, projectile.flight_elapsed)
		if projectile.flight_step_accumulator + 0.000001 < step_duration:
			break
		projectile.flight_step_accumulator = maxf(0.0, projectile.flight_step_accumulator - step_duration)
		var next_elapsed := projectile.flight_elapsed + step_duration
		var start := projectile.view.global_position
		var destination := _calculate_trajectory_position(projectile.launch_position, projectile.launch_velocity, profile.gravity, next_elapsed)
		var hit := _get_first_hit(start, destination, profile.collision_radius)
		if not hit.is_empty():
			var segment_length := start.distance_to(destination)
			var hit_ratio := 1.0 if segment_length <= 0.000001 else clampf(start.distance_to(hit["position"] as Vector3) / segment_length, 0.0, 1.0)
			var hit_elapsed := lerpf(projectile.flight_elapsed, next_elapsed, hit_ratio)
			projectile.view.global_position = hit["position"] as Vector3
			projectile.velocity = _calculate_trajectory_velocity(projectile.launch_velocity, profile.gravity, hit_elapsed)
			_orient_projectile(projectile)
			projectile.flight_elapsed = hit_elapsed
			projectile.trail.record_position(projectile.view.global_position, hit_elapsed)
			projectile.trail.finish()
			projectile.embedded_elapsed = 0.0
			var target_runtime_id := int(hit.get("target_runtime_id", -1))
			if target_runtime_id > 0:
				_combat.try_commit_player_projectile_hit(
					target_runtime_id,
					profile,
					projectile.source_item_id,
					projectile.view.global_position,
					projectile.velocity,
					projectile.damage_multiplier,
				)
			return
		projectile.flight_elapsed = next_elapsed
		projectile.view.global_position = destination
		projectile.velocity = _calculate_trajectory_velocity(projectile.launch_velocity, profile.gravity, next_elapsed)
		_orient_projectile(projectile)
		projectile.trail.record_position(destination, next_elapsed)
	if projectile.flight_elapsed >= profile.maximum_flight_seconds:
		_remove_projectile(index)

func _advance_embedded_projectile(index: int, projectile: ActiveProjectile, delta: float) -> void:
	projectile.embedded_elapsed += delta
	var profile := projectile.ammunition.projectile_profile
	if projectile.embedded_elapsed <= profile.embedded_seconds:
		return
	var fade_progress := (projectile.embedded_elapsed - profile.embedded_seconds) / profile.fade_seconds
	projectile.view.set_fade_progress(fade_progress)
	if fade_progress >= 1.0:
		_remove_projectile(index)

func _get_first_hit(start: Vector3, destination: Vector3, radius: float) -> Dictionary:
	var displacement := destination - start
	var distance := displacement.length()
	if distance <= 0.000001:
		return {}
	var direction := displacement / distance
	var nearest_distance := INF
	var nearest_runtime_id := -1
	var bounds := AABB(
		Vector3(
			minf(start.x, destination.x),
			minf(start.y, destination.y),
			minf(start.z, destination.z)
		) - Vector3.ONE * radius,
		Vector3(
			absf(displacement.x),
			absf(displacement.y),
			absf(displacement.z)
		) + Vector3.ONE * radius * 2.0,
	)
	for runtime_id in _entity_runtime.get_active_runtime_ids_overlapping(bounds):
		var actor := _entity_runtime.get_actor(runtime_id)
		if actor == null or actor.definition == null or not actor.definition.combat_targetable:
			continue
		var entity_hit: Variant = actor.get_world_bounds().grow(radius).intersects_segment(start, destination)
		if not entity_hit is Vector3:
			continue
		var entity_distance := start.distance_to(entity_hit as Vector3)
		if entity_distance < nearest_distance:
			nearest_distance = entity_distance
			nearest_runtime_id = runtime_id
	var voxel_hit := VoxelRaycast.cast(_voxel_space, start, direction, distance, _is_foliage)
	if voxel_hit != null and voxel_hit.ray_distance <= distance + 0.000001 and voxel_hit.ray_distance <= nearest_distance:
		return {"position": start + direction * voxel_hit.ray_distance}
	if nearest_runtime_id > 0:
		return {
			"position": start + direction * nearest_distance,
			"target_runtime_id": nearest_runtime_id,
		}
	return {}

func _is_foliage(block_id: int) -> bool:
	return BlockId.is_foliage(block_id)

func _orient_projectile(projectile: ActiveProjectile) -> void:
	if projectile.velocity.is_zero_approx():
		return
	projectile.view.global_basis = Basis(Quaternion(Vector3.UP, projectile.velocity.normalized()))

func _get_launch_velocity(action: BowDrawActionDefinition, draw_progress: float, release_transform: Transform3D) -> Vector3:
	var forward := release_transform.basis.y.normalized()
	if not forward.is_finite() or forward.is_zero_approx():
		return Vector3.ZERO
	return forward * action.get_launch_speed(draw_progress)

func _calculate_trajectory_position(origin: Vector3, launch_velocity: Vector3, gravity: float, elapsed: float) -> Vector3:
	return origin + launch_velocity * elapsed + Vector3.DOWN * (0.5 * gravity * elapsed * elapsed)

func _calculate_trajectory_velocity(launch_velocity: Vector3, gravity: float, elapsed: float) -> Vector3:
	return launch_velocity + Vector3.DOWN * gravity * elapsed

func _get_trajectory_step_duration(profile: ProjectileAttackProfile, elapsed: float) -> float:
	return minf(TRAJECTORY_STEP_SECONDS, profile.maximum_flight_seconds - elapsed)

func _find_ammunition_index(item_id: StringName) -> int:
	for index in range(mini(_inventory.get_size(), InventoryModel.FILLABLE_SIZE)):
		var stack := _inventory.get_slot(index)
		if stack != null and stack.item_id == item_id:
			return index
	return -1

func _remove_projectile(index: int) -> void:
	var projectile := _projectiles[index]
	if is_instance_valid(projectile.view):
		projectile.view.free()
	if is_instance_valid(projectile.trail):
		projectile.trail.free()
	_projectiles.remove_at(index)
