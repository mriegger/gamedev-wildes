extends Node3D
class_name EntityRuntime

const EntitySpawnGeometryType := preload("res://entities/entity_spawn_geometry.gd")

signal entity_melee_contact_reached(source_runtime_id: int, profile: MeleeAttackProfile)
signal entity_defeated(runtime_id: int, definition_id: StringName)

const SPATIAL_CELL_SIZE: float = 4.0
const SEPARATION_RADIUS: float = 1.2
const SEPARATION_SPEED: float = 1.25

class Retirement:
	var actor: EntityActor
	var sequence: int

	func _init(p_actor: EntityActor, p_sequence: int):
		actor = p_actor
		sequence = p_sequence

var _catalog: EntityCatalog
var _voxel_space: VoxelSpace
var _navigation_limits: EntityNavigationLimits
var _max_active: int = 0
var _max_retiring_visuals: int = 0
var _active: Dictionary = {}
var _stats_by_runtime_id: Dictionary = {}
var _retiring: Dictionary = {}
var _spatial_index: EntitySpatialIndex = EntitySpatialIndex.new(SPATIAL_CELL_SIZE)
var _prepared_actors: Dictionary = {}
var _next_runtime_id: int = 1
var _navigation_search_budget: NavigationSearchBudget
var _actor_tick_start_index: int = 0
var _prepared_definition_cursor: int = 0
var _preparation_needed: bool = false
var _next_retirement_sequence: int = 0
var _suspended: bool = false

func setup(
	p_catalog: EntityCatalog,
	p_voxel_space: VoxelSpace,
	p_max_active: int,
	p_max_retiring_visuals: int,
	p_navigation_limits: EntityNavigationLimits,
) -> void:
	assert(p_catalog != null and p_catalog.validate())
	assert(p_voxel_space != null)
	assert(p_max_active > 0)
	assert(p_max_retiring_visuals > 0)
	assert(p_navigation_limits != null)
	shutdown()
	_catalog = p_catalog
	_voxel_space = p_voxel_space
	_max_active = p_max_active
	_max_retiring_visuals = p_max_retiring_visuals
	_navigation_limits = p_navigation_limits
	_navigation_search_budget = NavigationSearchBudget.new(p_navigation_limits.get_max_searches_per_tick())
	_next_runtime_id = 1
	_actor_tick_start_index = 0
	_prepared_definition_cursor = 0
	_next_retirement_sequence = 0
	_prepare_initial_actors()
	_preparation_needed = false
	_suspended = false
	visible = true

func tick(delta: float, player_position: Vector3) -> void:
	assert(_catalog != null and _voxel_space != null)
	assert(not _suspended)
	assert(is_finite(delta) and delta >= 0.0)
	assert(player_position.is_finite())
	_prepare_one_actor()
	_advance_retiring(delta)
	_navigation_search_budget.reset()
	var runtime_ids: Array = _active.keys()
	runtime_ids.sort()
	var tick_runtime_ids := runtime_ids.duplicate()
	if not tick_runtime_ids.is_empty():
		var start_index := _actor_tick_start_index % tick_runtime_ids.size()
		tick_runtime_ids = tick_runtime_ids.slice(start_index) + tick_runtime_ids.slice(0, start_index)
		_actor_tick_start_index = (start_index + 1) % runtime_ids.size()
	var separation_velocities: Dictionary = {}
	for runtime_id in runtime_ids:
		var actor := get_actor(runtime_id)
		if actor != null:
			separation_velocities[runtime_id] = _get_separation_velocity(actor)
	for runtime_id in tick_runtime_ids:
		var actor := get_actor(runtime_id)
		if actor == null:
			continue
		actor.advance_visual_fade(delta)
		actor.tick(delta, player_position, separation_velocities[runtime_id] as Vector3, _navigation_search_budget)
		if get_actor(runtime_id) == actor:
			_spatial_index.upsert(actor.runtime_id, actor.global_position, actor.get_world_bounds())

func try_spawn_batch(requests: Array[EntitySpawnRequest]) -> Array[int]:
	var rejected: Array[int] = []
	if _catalog == null or _voxel_space == null or _suspended or requests.is_empty():
		return rejected
	if _active.size() + requests.size() > _max_active:
		return rejected
	var definitions: Array[EntityDefinition] = []
	var bounds: Array[AABB] = []
	var required_by_definition: Dictionary = {}
	for request in requests:
		if request == null or not _catalog.has_definition(request.definition_id):
			return rejected
		var definition := _catalog.get_definition(request.definition_id)
		if not EntitySpawnGeometryType.can_spawn(_voxel_space, definition, request.feet_position):
			return rejected
		var actor_bounds := EntitySpawnGeometryType.get_bounds(definition, request.feet_position)
		if not _spatial_index.query_overlapping(actor_bounds).is_empty():
			return rejected
		for existing_bounds in bounds:
			if existing_bounds.intersects(actor_bounds):
				return rejected
		definitions.append(definition)
		bounds.append(actor_bounds)
		required_by_definition[definition.id] = int(required_by_definition.get(definition.id, 0)) + 1
	for definition_id in required_by_definition:
		if not _prepare_count(definition_id, int(required_by_definition[definition_id])):
			return rejected
	var runtime_ids: Array[int] = []
	for index in requests.size():
		var request := requests[index]
		var definition := definitions[index]
		var actor := _take_prepared_actor(definition.id)
		assert(actor != null)
		var runtime_id := _next_runtime_id
		_next_runtime_id += 1
		_active[runtime_id] = actor
		var stats := ActorStats.new(definition.stats_definition)
		stats.health_depleted.connect(_retire_defeated.bind(runtime_id))
		_stats_by_runtime_id[runtime_id] = stats
		actor.visible = true
		actor.global_position = request.feet_position
		actor.bind_stats(stats, definition.body_height)
		actor.setup(runtime_id, definition, _voxel_space, request.behavior_seed, _navigation_limits)
		actor.melee_contact_reached.connect(_on_actor_melee_contact_reached)
		_spatial_index.upsert(runtime_id, actor.global_position, actor.get_world_bounds())
		runtime_ids.append(runtime_id)
	return runtime_ids

func try_despawn(runtime_id: int) -> bool:
	var actor := _remove_active_actor(runtime_id)
	if actor == null:
		return false
	_retain_retiring_actor(runtime_id, actor)
	actor.begin_despawn_fade()
	return true

func _retire_defeated(runtime_id: int) -> void:
	var actor := _remove_active_actor(runtime_id)
	if actor == null:
		return
	var definition_id := actor.definition.id
	_retain_retiring_actor(runtime_id, actor)
	actor.begin_death_retirement()
	entity_defeated.emit(runtime_id, definition_id)

func _prepare_initial_actors() -> void:
	for definition in _catalog.definitions:
		if _prepared_actor_count() >= _max_active:
			return
		_prepare_actor(definition)

func _prepare_one_actor() -> void:
	if not _preparation_needed:
		return
	if _prepared_actor_count() >= _max_active or _catalog.definitions.is_empty():
		_preparation_needed = false
		return
	for offset in range(_catalog.definitions.size()):
		var index := (_prepared_definition_cursor + offset) % _catalog.definitions.size()
		var definition := _catalog.definitions[index]
		if definition == null or _has_prepared_actor(definition.id):
			continue
		_prepare_actor(definition)
		_prepared_definition_cursor = (index + 1) % _catalog.definitions.size()
		return
	_preparation_needed = false

func _prepare_count(definition_id: StringName, required_count: int) -> bool:
	var actors := _prepared_actors.get(definition_id, []) as Array
	while actors.size() < required_count:
		var definition := _catalog.get_definition(definition_id)
		var actor := definition.actor_scene.instantiate() as EntityActor
		if actor == null:
			return false
		actor.visible = false
		add_child(actor)
		actors.append(actor)
	_prepared_actors[definition_id] = actors
	return true

func _prepare_actor(definition: EntityDefinition) -> void:
	var actor := definition.actor_scene.instantiate() as EntityActor
	assert(actor != null)
	actor.visible = false
	add_child(actor)
	if not _prepared_actors.has(definition.id):
		_prepared_actors[definition.id] = []
	var actors := _prepared_actors[definition.id] as Array
	actors.append(actor)

func _has_prepared_actor(definition_id: StringName) -> bool:
	return _prepared_actors.has(definition_id) and not (_prepared_actors[definition_id] as Array).is_empty()

func _take_prepared_actor(definition_id: StringName) -> EntityActor:
	if not _has_prepared_actor(definition_id):
		return null
	_preparation_needed = true
	return (_prepared_actors[definition_id] as Array).pop_back() as EntityActor

func _prepared_actor_count() -> int:
	var count := 0
	for actors in _prepared_actors.values():
		count += (actors as Array).size()
	return count

func _clear_prepared_actors() -> void:
	for actors in _prepared_actors.values():
		for actor in actors as Array:
			if is_instance_valid(actor):
				(actor as EntityActor).free()
	_prepared_actors.clear()

func _remove_active_actor(runtime_id: int) -> EntityActor:
	if not _active.has(runtime_id):
		return null
	var actor := _active[runtime_id] as EntityActor
	_active.erase(runtime_id)
	_stats_by_runtime_id.erase(runtime_id)
	_spatial_index.remove(runtime_id)
	_preparation_needed = true
	if is_instance_valid(actor):
		if actor.melee_contact_reached.is_connected(_on_actor_melee_contact_reached):
			actor.melee_contact_reached.disconnect(_on_actor_melee_contact_reached)
		return actor
	return null

func _retain_retiring_actor(runtime_id: int, actor: EntityActor) -> void:
	_make_retiring_capacity()
	_retiring[runtime_id] = Retirement.new(actor, _next_retirement_sequence)
	_next_retirement_sequence += 1

func _make_retiring_capacity() -> void:
	if _retiring.size() < _max_retiring_visuals:
		return
	var oldest_runtime_id: int = -1
	var oldest_sequence: int = -1
	for runtime_id in _retiring:
		var retirement := _retiring[runtime_id] as Retirement
		if oldest_runtime_id == -1 or retirement.sequence < oldest_sequence:
			oldest_runtime_id = runtime_id
			oldest_sequence = retirement.sequence
	assert(oldest_runtime_id >= 0)
	_finish_retiring(oldest_runtime_id)

func _advance_retiring(delta: float) -> void:
	var completed_ids: Array[int] = []
	var runtime_ids: Array = _retiring.keys()
	runtime_ids.sort()
	for runtime_id in runtime_ids:
		var retirement := _retiring[runtime_id] as Retirement
		var actor := retirement.actor
		if not is_instance_valid(actor) or actor.advance_retirement(delta):
			completed_ids.append(runtime_id)
	for runtime_id in completed_ids:
		_finish_retiring(runtime_id)

func _finish_retiring(runtime_id: int) -> void:
	var retirement := _retiring.get(runtime_id) as Retirement
	_retiring.erase(runtime_id)
	var actor := retirement.actor if retirement != null else null
	if is_instance_valid(actor):
		actor.queue_free()

func get_definition_count(definition_id: StringName) -> int:
	var count := 0
	for actor in _active.values():
		if is_instance_valid(actor) and (actor as EntityActor).definition.id == definition_id:
			count += 1
	return count

func _get_separation_velocity(actor: EntityActor) -> Vector3:
	var separation := Vector3.ZERO
	for nearby_id in _spatial_index.query_nearby(actor.global_position, SEPARATION_RADIUS):
		if nearby_id == actor.runtime_id:
			continue
		var other := get_actor(nearby_id)
		if other == null:
			continue
		var offset := actor.global_position - other.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance <= 0.001:
			offset = Vector3.RIGHT if actor.runtime_id < other.runtime_id else Vector3.LEFT
			distance = 0.0
		var strength := 1.0 - distance / SEPARATION_RADIUS
		if strength > 0.0:
			separation += offset.normalized() * strength
	if separation.length_squared() > 1.0:
		separation = separation.normalized()
	return separation * SEPARATION_SPEED

func get_active_count() -> int:
	return _active.size()

func get_active_actors() -> Array[EntityActor]:
	var actors: Array[EntityActor] = []
	if _suspended:
		return actors
	for actor in _active.values():
		if is_instance_valid(actor):
			actors.append(actor as EntityActor)
	return actors

func get_actor(runtime_id: int) -> EntityActor:
	if _suspended:
		return null
	var actor := _active.get(runtime_id) as EntityActor
	return actor if is_instance_valid(actor) else null

func get_current_hp(runtime_id: int) -> float:
	return _get_stats(runtime_id).current_hp

func get_stat_value(runtime_id: int, stat_id: StringName) -> float:
	return _get_stats(runtime_id).get_value(stat_id)

func try_apply_damage(runtime_id: int, amount: float) -> EntityDamageResult:
	assert(is_finite(amount) and amount > 0.0)
	var stats := _stats_by_runtime_id.get(runtime_id) as ActorStats
	if stats == null:
		return null
	var applied_damage := stats.damage(amount)
	return EntityDamageResult.new(applied_damage, stats.is_dead())

func try_apply_knockback(runtime_id: int, direction: Vector3, speed: float) -> bool:
	var actor := get_actor(runtime_id)
	return actor != null and actor.apply_knockback(direction, speed)

func _get_stats(runtime_id: int) -> ActorStats:
	var stats := _stats_by_runtime_id.get(runtime_id) as ActorStats
	assert(stats != null)
	return stats

func has_entity_overlap(bounds: AABB) -> bool:
	return not _spatial_index.query_overlapping(bounds).is_empty()

func get_active_runtime_ids_overlapping(bounds: AABB) -> Array[int]:
	assert(bounds.position.is_finite() and bounds.size.is_finite())
	assert(bounds.size.x > 0.0 and bounds.size.y > 0.0 and bounds.size.z > 0.0)
	return _spatial_index.query_overlapping(bounds)

func record_melee_outcome(outcome: MeleeOutcome) -> void:
	var target := get_actor(outcome.contact.target_runtime_id)
	if target != null:
		target.record_melee_contact(outcome.contact.hit_direction)

func _on_actor_melee_contact_reached(source_runtime_id: int, profile: MeleeAttackProfile) -> void:
	entity_melee_contact_reached.emit(source_runtime_id, profile)

func suspend() -> void:
	if _suspended:
		return
	_suspended = true
	visible = false

func resume() -> void:
	if not _suspended:
		return
	visible = true
	_suspended = false

func is_suspended() -> bool:
	return _suspended

func shutdown() -> void:
	for runtime_id in _active.keys():
		var actor := _active[runtime_id] as EntityActor
		if is_instance_valid(actor):
			actor.queue_free()
	for value in _retiring.values():
		var actor := (value as Retirement).actor
		if is_instance_valid(actor):
			actor.queue_free()
	_active.clear()
	_stats_by_runtime_id.clear()
	_retiring.clear()
	_spatial_index.clear()
	_clear_prepared_actors()
	_catalog = null
	_voxel_space = null
	_navigation_limits = null
	_navigation_search_budget = null
	_max_active = 0
	_max_retiring_visuals = 0
	_actor_tick_start_index = 0
	_prepared_definition_cursor = 0
	_preparation_needed = false
	_next_retirement_sequence = 0
	_suspended = false
