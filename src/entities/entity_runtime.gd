extends Node3D
class_name EntityRuntime

const EntitySpawnGeometryType := preload("res://entities/entity_spawn_geometry.gd")

signal entity_melee_contact_reached(source_runtime_id: int, profile: MeleeAttackProfile)
signal entity_radial_contact_reached(source_runtime_id: int, profile: MeleeAttackProfile)
signal entity_defeated(defeat: EntityDefeat)
signal entity_removed(runtime_id: int)
signal water_surface_motion_committed(position: Vector3, planar_velocity: Vector2)
signal aggro_changed(active: bool)

const SPATIAL_CELL_SIZE: float = 4.0
const SEPARATION_RADIUS: float = 1.2
const SEPARATION_SPEED: float = 1.25
const DEFEAT_SPAWN_RADIAL_STEPS: int = 7
const DEFEAT_SPAWN_ANGLE_OFFSETS: Array[float] = [
	0.0,
	PI / 12.0,
	-PI / 12.0,
	PI / 6.0,
	-PI / 6.0,
	PI / 4.0,
	-PI / 4.0,
	PI / 2.0,
	-PI / 2.0,
	PI,
]
const DEFEAT_SPAWN_VERTICAL_OFFSETS: Array[float] = [0.0, 0.5, -0.5, 1.0, -1.0]

enum Mode {
	GAMEPLAY,
	PRESENTATION,
}

class Retirement:
	var actor: EntityActor
	var sequence: int

	func _init(p_actor: EntityActor, p_sequence: int):
		actor = p_actor
		sequence = p_sequence

class DefeatSpawnPlan:
	var child_definition: EntityDefinition
	var child_seeds: Array[int]
	var child_positions: Array[Vector3]
	var origin_position: Vector3
	var lineage_id: int
	var root_definition_id: StringName
	var child_damage_immunity_seconds: float
	var child_launch_planar_speed: float
	var child_launch_vertical_speed: float

	func _init(
		p_child_definition: EntityDefinition,
		p_child_seeds: Array[int],
		p_child_positions: Array[Vector3],
		p_origin_position: Vector3,
		p_lineage_id: int,
		p_root_definition_id: StringName,
		p_child_damage_immunity_seconds: float,
		p_child_launch_planar_speed: float,
		p_child_launch_vertical_speed: float,
	) -> void:
		assert(p_child_seeds.size() == p_child_positions.size())
		child_definition = p_child_definition
		child_seeds = p_child_seeds
		child_positions = p_child_positions
		origin_position = p_origin_position
		lineage_id = p_lineage_id
		root_definition_id = p_root_definition_id
		child_damage_immunity_seconds = p_child_damage_immunity_seconds
		child_launch_planar_speed = p_child_launch_planar_speed
		child_launch_vertical_speed = p_child_launch_vertical_speed

var _catalog: EntityCatalog
var _voxel_space: VoxelSpace
var _navigation_limits: EntityNavigationLimits
var _max_population_cost: int = 0
var _max_retiring_visuals: int = 0
var _active: Dictionary = {}
var _stats_by_runtime_id: Dictionary = {}
var _retiring: Dictionary = {}
var _spatial_index: EntitySpatialIndex = EntitySpatialIndex.new(SPATIAL_CELL_SIZE)
var _prepared_actors: Dictionary = {}
var _damage_immunity_remaining_by_runtime_id: Dictionary = {}
var _lineage_id_by_runtime_id: Dictionary = {}
var _lineage_member_count_by_id: Dictionary = {}
var _lineage_root_definition_by_id: Dictionary = {}
var _active_lineage_count_by_root_definition: Dictionary = {}
var _next_runtime_id: int = 1
var _next_lineage_id: int = 1
var _population_cost: int = 0
var _navigation_search_budget: NavigationSearchBudget
var _actor_tick_start_index: int = 0
var _prepared_definition_cursor: int = 0
var _preparation_needed: bool = false
var _next_retirement_sequence: int = 0
var _suspended: bool = false
var _aggro_active: bool = false
var _aggroed_runtime_ids: Dictionary = {}
var _mode: Mode = Mode.GAMEPLAY

func setup(
	p_catalog: EntityCatalog,
	p_voxel_space: VoxelSpace,
	p_max_population_cost: int,
	p_max_retiring_visuals: int,
	p_navigation_limits: EntityNavigationLimits,
	p_mode: Mode,
) -> void:
	assert(p_catalog != null and p_catalog.validate())
	assert(p_voxel_space != null)
	assert(p_max_population_cost > 0)
	assert(p_max_retiring_visuals > 0)
	assert(p_navigation_limits != null)
	assert(p_mode == Mode.GAMEPLAY or p_mode == Mode.PRESENTATION)
	shutdown()
	_catalog = p_catalog
	_voxel_space = p_voxel_space
	_max_population_cost = p_max_population_cost
	_max_retiring_visuals = p_max_retiring_visuals
	_navigation_limits = p_navigation_limits
	_mode = p_mode
	_navigation_search_budget = NavigationSearchBudget.new(p_navigation_limits.get_max_searches_per_tick())
	_next_runtime_id = 1
	_next_lineage_id = 1
	_population_cost = 0
	_actor_tick_start_index = 0
	_prepared_definition_cursor = 0
	_next_retirement_sequence = 0
	_aggro_active = false
	_aggroed_runtime_ids.clear()
	if _mode == Mode.GAMEPLAY:
		_prepare_initial_actors()
	_preparation_needed = false
	_suspended = false
	visible = true

func tick_gameplay(delta: float, observation: EntityTargetObservation) -> void:
	assert(_catalog != null and _voxel_space != null)
	assert(not _suspended)
	assert(_mode == Mode.GAMEPLAY)
	assert(is_finite(delta) and delta >= 0.0)
	assert(observation != null and observation.validate())
	_advance_entities(delta, observation)

func tick_ambient(delta: float) -> void:
	assert(_catalog != null and _voxel_space != null)
	assert(not _suspended)
	assert(_mode == Mode.PRESENTATION)
	assert(is_finite(delta) and delta >= 0.0)
	_advance_entities(delta, null)

func _advance_entities(delta: float, observation: EntityTargetObservation) -> void:
	if _preparation_needed:
		_prepare_one_actor()
	if not _retiring.is_empty():
		_advance_retiring(delta)
	if not _damage_immunity_remaining_by_runtime_id.is_empty():
		_advance_damage_immunity(delta)
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
		if observation == null:
			actor.tick_ambient(delta, separation_velocities[runtime_id] as Vector3, _navigation_search_budget)
		else:
			actor.tick_gameplay(delta, observation, separation_velocities[runtime_id] as Vector3, _navigation_search_budget)
		if get_actor(runtime_id) == actor:
			_spatial_index.upsert(actor.runtime_id, actor.global_position, actor.get_world_bounds())
			if _mode == Mode.GAMEPLAY:
				_set_actor_aggro(runtime_id, actor.is_aggroed())

func try_spawn_batch(requests: Array[EntitySpawnRequest]) -> Array[int]:
	var rejected: Array[int] = []
	if _catalog == null or _voxel_space == null or _suspended or requests.is_empty():
		return rejected
	var definitions: Array[EntityDefinition] = []
	var bounds: Array[AABB] = []
	var required_by_definition: Dictionary = {}
	var requested_population_cost := 0
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
		requested_population_cost += _catalog.get_maximum_lineage_capacity(definition.id)
	if _population_cost + requested_population_cost > _max_population_cost:
		return rejected
	for definition_id in required_by_definition:
		if not _prepare_count(definition_id, int(required_by_definition[definition_id])):
			return rejected
	var runtime_ids: Array[int] = []
	for index in requests.size():
		var request := requests[index]
		var definition := definitions[index]
		var lineage_id := _next_lineage_id
		_next_lineage_id += 1
		var actor := _activate_prepared_actor(
			definition,
			request.feet_position,
			request.behavior_seed,
			lineage_id,
			definition.id,
		)
		runtime_ids.append(actor.runtime_id)
	return runtime_ids

func _activate_prepared_actor(
	definition: EntityDefinition,
	feet_position: Vector3,
	behavior_seed: int,
	lineage_id: int,
	root_definition_id: StringName,
) -> EntityActor:
	var actor := _take_prepared_actor(definition.id)
	assert(actor != null)
	var runtime_id := _next_runtime_id
	_next_runtime_id += 1
	_active[runtime_id] = actor
	actor.visible = true
	actor.global_position = feet_position
	if _mode == Mode.GAMEPLAY:
		var stats := ActorStats.new(definition.stats_definition)
		_stats_by_runtime_id[runtime_id] = stats
		actor.bind_stats(stats, definition.body_height)
	actor.setup(runtime_id, definition, _voxel_space, behavior_seed, _navigation_limits)
	actor.melee_contact_reached.connect(_on_actor_melee_contact_reached)
	actor.water_surface_motion_committed.connect(_on_actor_water_surface_motion_committed)
	actor.radial_contact_reached.connect(_on_actor_radial_contact_reached)
	_register_lineage_member(runtime_id, definition.id, lineage_id, root_definition_id)
	_spatial_index.upsert(runtime_id, actor.global_position, actor.get_world_bounds())
	return actor

func try_despawn(runtime_id: int) -> bool:
	var actor := _remove_active_actor(runtime_id)
	if actor == null:
		return false
	_retain_retiring_actor(runtime_id, actor)
	actor.begin_despawn_fade()
	return true

func defeat_all_active() -> int:
	var runtime_ids: Array = _active.keys()
	runtime_ids.sort()
	for runtime_id in runtime_ids:
		_retire_defeated(runtime_id, null)
	return runtime_ids.size()

func _retire_defeated(runtime_id: int, spawn_plan: DefeatSpawnPlan) -> void:
	var actor := _remove_active_actor(runtime_id)
	if actor == null:
		return
	var defeat := EntityDefeat.new(
		runtime_id,
		actor.definition.id,
		actor.global_position,
		actor.behavior_seed,
	)
	_retain_retiring_actor(runtime_id, actor)
	actor.begin_death_retirement()
	if spawn_plan != null:
		_commit_defeat_spawn(spawn_plan)
	entity_defeated.emit(defeat)

func _commit_defeat_spawn(plan: DefeatSpawnPlan) -> void:
	var child_count := plan.child_seeds.size()
	for child_index in child_count:
		var child := _activate_prepared_actor(
			plan.child_definition,
			plan.child_positions[child_index],
			plan.child_seeds[child_index],
			plan.lineage_id,
			plan.root_definition_id,
		)
		var ground_y := VoxelBodySolver.get_ground_y(
			_voxel_space,
			child.global_position,
			child.definition.body_width,
		)
		child.on_ground = (
			ground_y != VoxelSpace.NO_SURFACE_Y
			and absf(ground_y - child.global_position.y) < 0.12
		)
		var direction := plan.child_positions[child_index] - plan.origin_position
		direction.y = 0.0
		if plan.child_launch_planar_speed > 0.0:
			var launched := child.begin_defeat_spawn_launch(
				direction,
				plan.child_launch_planar_speed,
				plan.child_launch_vertical_speed,
			)
			assert(launched)
		if plan.child_damage_immunity_seconds > 0.0:
			_damage_immunity_remaining_by_runtime_id[child.runtime_id] = plan.child_damage_immunity_seconds

func _prepare_initial_actors() -> void:
	for definition in _catalog.definitions:
		if _prepared_actor_count() >= _max_population_cost:
			return
		_prepare_actor(definition)

func _prepare_one_actor() -> void:
	if _prepared_actor_count() >= _max_population_cost or _catalog.definitions.is_empty():
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
		actor.configure_audio(_mode == Mode.GAMEPLAY)
		add_child(actor)
		actors.append(actor)
	_prepared_actors[definition_id] = actors
	return true

func _prepare_actor(definition: EntityDefinition) -> void:
	var actor := definition.actor_scene.instantiate() as EntityActor
	assert(actor != null)
	actor.visible = false
	actor.configure_audio(_mode == Mode.GAMEPLAY)
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
	_preparation_needed = _mode == Mode.GAMEPLAY
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
	_unregister_lineage_member(runtime_id, actor.definition.id)
	_active.erase(runtime_id)
	_stats_by_runtime_id.erase(runtime_id)
	_damage_immunity_remaining_by_runtime_id.erase(runtime_id)
	_spatial_index.remove(runtime_id)
	_aggroed_runtime_ids.erase(runtime_id)
	_sync_aggro_state()
	_preparation_needed = _mode == Mode.GAMEPLAY
	entity_removed.emit(runtime_id)
	if is_instance_valid(actor):
		if actor.melee_contact_reached.is_connected(_on_actor_melee_contact_reached):
			actor.melee_contact_reached.disconnect(_on_actor_melee_contact_reached)
		if actor.water_surface_motion_committed.is_connected(_on_actor_water_surface_motion_committed):
			actor.water_surface_motion_committed.disconnect(_on_actor_water_surface_motion_committed)
		if actor.radial_contact_reached.is_connected(_on_actor_radial_contact_reached):
			actor.radial_contact_reached.disconnect(_on_actor_radial_contact_reached)
		return actor
	return null

func _register_lineage_member(
	runtime_id: int,
	definition_id: StringName,
	lineage_id: int,
	root_definition_id: StringName,
) -> void:
	assert(runtime_id > 0 and lineage_id > 0 and not root_definition_id.is_empty())
	assert(not _lineage_id_by_runtime_id.has(runtime_id))
	var member_count := int(_lineage_member_count_by_id.get(lineage_id, 0))
	if member_count == 0:
		assert(not _lineage_root_definition_by_id.has(lineage_id))
		_lineage_root_definition_by_id[lineage_id] = root_definition_id
		_active_lineage_count_by_root_definition[root_definition_id] = int(
			_active_lineage_count_by_root_definition.get(root_definition_id, 0)
		) + 1
	else:
		assert(_lineage_root_definition_by_id[lineage_id] == root_definition_id)
	_lineage_id_by_runtime_id[runtime_id] = lineage_id
	_lineage_member_count_by_id[lineage_id] = member_count + 1
	_population_cost += _catalog.get_maximum_lineage_capacity(definition_id)

func _unregister_lineage_member(runtime_id: int, definition_id: StringName) -> void:
	assert(_lineage_id_by_runtime_id.has(runtime_id))
	var lineage_id := int(_lineage_id_by_runtime_id[runtime_id])
	var member_count := int(_lineage_member_count_by_id[lineage_id])
	assert(member_count > 0)
	_population_cost -= _catalog.get_maximum_lineage_capacity(definition_id)
	assert(_population_cost >= 0)
	_lineage_id_by_runtime_id.erase(runtime_id)
	if member_count > 1:
		_lineage_member_count_by_id[lineage_id] = member_count - 1
		return
	var root_definition_id := _lineage_root_definition_by_id[lineage_id] as StringName
	var root_count := int(_active_lineage_count_by_root_definition[root_definition_id])
	if root_count > 1:
		_active_lineage_count_by_root_definition[root_definition_id] = root_count - 1
	else:
		_active_lineage_count_by_root_definition.erase(root_definition_id)
	_lineage_member_count_by_id.erase(lineage_id)
	_lineage_root_definition_by_id.erase(lineage_id)

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

func _advance_damage_immunity(delta: float) -> void:
	var runtime_ids: Array = _damage_immunity_remaining_by_runtime_id.keys()
	runtime_ids.sort()
	for runtime_id in runtime_ids:
		var remaining := float(_damage_immunity_remaining_by_runtime_id[runtime_id])
		if delta >= remaining or is_equal_approx(delta, remaining):
			_damage_immunity_remaining_by_runtime_id.erase(runtime_id)
		else:
			_damage_immunity_remaining_by_runtime_id[runtime_id] = remaining - delta

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

func get_population_snapshot() -> Dictionary:
	var rows: Array[Dictionary] = []
	for definition in _catalog.definitions:
		rows.append({
			"id": definition.id,
			"active": get_definition_count(definition.id),
			"ambient_enabled": definition.ambient_spawn_enabled,
			"ambient_cap": definition.ambient_max_active,
		})
	return {
		"active": _active.size(),
		"population_cost": _population_cost,
		"population_capacity": _max_population_cost,
		"rows": rows,
	}

func get_population_cost() -> int:
	return _population_cost

func get_active_lineage_count(root_definition_id: StringName) -> int:
	assert(_catalog != null and _catalog.has_definition(root_definition_id))
	return int(_active_lineage_count_by_root_definition.get(root_definition_id, 0))

func get_active_runtime_ids_for_definition(definition_id: StringName) -> Array[int]:
	assert(_catalog != null and _catalog.has_definition(definition_id))
	var runtime_ids: Array[int] = []
	for runtime_id in _active:
		var actor := _active[runtime_id] as EntityActor
		if is_instance_valid(actor) and actor.definition.id == definition_id:
			runtime_ids.append(runtime_id)
	runtime_ids.sort()
	return runtime_ids

func is_aggro_active() -> bool:
	return _aggro_active

func get_active_actors() -> Array[EntityActor]:
	var actors: Array[EntityActor] = []
	if _suspended:
		return actors
	for actor in _active.values():
		if is_instance_valid(actor):
			actors.append(actor as EntityActor)
	return actors

func get_hostile_positions_near(position: Vector3, radius: float) -> PackedVector3Array:
	assert(position.is_finite())
	assert(is_finite(radius) and radius >= 0.0)
	var positions := PackedVector3Array()
	if _suspended:
		return positions
	for runtime_id in _spatial_index.query_nearby(position, radius):
		var actor := get_actor(runtime_id)
		if actor != null and actor.definition.hostile_to_player:
			positions.append(actor.global_position)
	return positions

func get_actor(runtime_id: int) -> EntityActor:
	if _suspended:
		return null
	var actor := _active.get(runtime_id) as EntityActor
	return actor if is_instance_valid(actor) else null

func try_relocate_actor(runtime_id: int, position: Vector3) -> bool:
	if not position.is_finite():
		return false
	var actor := get_actor(runtime_id)
	if actor == null:
		return false
	actor.global_position = position
	_spatial_index.upsert(runtime_id, position, actor.get_world_bounds())
	return true

func try_teleport_actor(runtime_id: int, position: Vector3) -> bool:
	if not position.is_finite():
		return false
	var actor := get_actor(runtime_id)
	if actor == null or actor.definition == null:
		return false
	if not EntitySpawnGeometryType.can_spawn(_voxel_space, actor.definition, position):
		return false
	var bounds := EntitySpawnGeometryType.get_bounds(actor.definition, position)
	for overlapping_runtime_id in _spatial_index.query_overlapping(bounds):
		if overlapping_runtime_id != runtime_id:
			return false
	return try_relocate_actor(runtime_id, position)

func get_presented_actor(runtime_id: int) -> EntityActor:
	var active_actor := _active.get(runtime_id) as EntityActor
	if is_instance_valid(active_actor):
		return active_actor
	var retirement := _retiring.get(runtime_id) as Retirement
	if retirement != null and is_instance_valid(retirement.actor):
		return retirement.actor
	return null

func get_current_hp(runtime_id: int) -> float:
	return _get_stats(runtime_id).current_hp

func get_stat_value(runtime_id: int, stat_id: StringName) -> float:
	return _get_stats(runtime_id).get_value(stat_id)

func try_apply_damage(runtime_id: int, amount: float) -> EntityDamageResult:
	assert(is_finite(amount) and amount > 0.0)
	if _mode != Mode.GAMEPLAY:
		return null
	var actor := get_actor(runtime_id)
	if actor == null or actor.definition == null or not actor.definition.combat_targetable:
		return null
	if _damage_immunity_remaining_by_runtime_id.has(runtime_id):
		return null
	var stats := _stats_by_runtime_id.get(runtime_id) as ActorStats
	if stats == null:
		return null
	var spawn_plan: DefeatSpawnPlan = null
	if amount >= stats.current_hp and actor.definition.defeat_spawn != null:
		spawn_plan = _prepare_defeat_spawn(actor)
		if spawn_plan == null:
			return null
	var applied_damage := stats.damage(amount)
	var defeated := stats.is_dead()
	if defeated:
		_retire_defeated(runtime_id, spawn_plan)
	return EntityDamageResult.new(applied_damage, defeated)

func _prepare_defeat_spawn(actor: EntityActor) -> DefeatSpawnPlan:
	assert(actor != null and actor.definition != null and actor.definition.defeat_spawn != null)
	var spawn := actor.definition.defeat_spawn
	var child_definition := _catalog.get_definition(spawn.child_definition_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = actor.behavior_seed
	var child_count := rng.randi_range(spawn.minimum_count, spawn.maximum_count)
	var child_seeds: Array[int] = []
	for _child_index in child_count:
		child_seeds.append(int(rng.randi()))
	var initial_rotation := rng.randf_range(0.0, TAU)
	var child_positions := _find_defeat_spawn_positions(
		actor,
		child_definition,
		child_count,
		initial_rotation,
		spawn.child_spawn_clearance,
	)
	if child_positions.size() != child_count:
		return null
	var parent_cost := _catalog.get_maximum_lineage_capacity(actor.definition.id)
	var child_cost := _catalog.get_maximum_lineage_capacity(child_definition.id)
	if _population_cost - parent_cost + child_count * child_cost > _max_population_cost:
		return null
	if not _prepare_count(child_definition.id, child_count):
		return null
	var lineage_id := int(_lineage_id_by_runtime_id[actor.runtime_id])
	var root_definition_id := _lineage_root_definition_by_id[lineage_id] as StringName
	return DefeatSpawnPlan.new(
		child_definition,
		child_seeds,
		child_positions,
		actor.global_position,
		lineage_id,
		root_definition_id,
		spawn.child_damage_immunity_seconds,
		spawn.child_launch_planar_speed,
		spawn.child_launch_vertical_speed,
	)

func _find_defeat_spawn_positions(
	parent: EntityActor,
	child_definition: EntityDefinition,
	child_count: int,
	initial_rotation: float,
	clearance: float,
) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var planned_bounds: Array[AABB] = []
	var parent_clearance_radius := (
		(parent.definition.body_width + child_definition.body_width) * 0.5 + clearance
	)
	var sibling_clearance_radius := 0.0
	if child_count > 1:
		sibling_clearance_radius = (
			(child_definition.body_width + clearance)
			/ (sqrt(2.0) * sin(PI / float(child_count)))
		)
	var base_radius := maxf(parent_clearance_radius, sibling_clearance_radius)
	var radial_step_distance := maxf(0.5, child_definition.body_width * 0.5)
	for child_index in child_count:
		var preferred_angle := initial_rotation + TAU * float(child_index) / float(child_count)
		var selected: Variant = null
		for radial_step in DEFEAT_SPAWN_RADIAL_STEPS:
			if selected is Vector3:
				break
			var radius := base_radius + float(radial_step) * radial_step_distance
			for angle_offset in DEFEAT_SPAWN_ANGLE_OFFSETS:
				if selected is Vector3:
					break
				var angle := preferred_angle + angle_offset
				var direction := Vector3(cos(angle), 0.0, sin(angle))
				for vertical_offset in DEFEAT_SPAWN_VERTICAL_OFFSETS:
					var candidate := parent.global_position + direction * radius + Vector3.UP * vertical_offset
					if _can_use_defeat_spawn_position(
						parent.runtime_id,
						child_definition,
						candidate,
						planned_bounds,
					):
						selected = candidate
						break
		if not selected is Vector3:
			return []
		var position := selected as Vector3
		positions.append(position)
		planned_bounds.append(EntitySpawnGeometryType.get_bounds(child_definition, position))
	return positions

func _can_use_defeat_spawn_position(
	parent_runtime_id: int,
	child_definition: EntityDefinition,
	position: Vector3,
	planned_bounds: Array[AABB],
) -> bool:
	if VoxelBodySolver.collides_at(
		_voxel_space,
		position,
		child_definition.body_width,
		child_definition.body_height,
		false,
	):
		return false
	var bounds := EntitySpawnGeometryType.get_bounds(child_definition, position)
	for planned_bound in planned_bounds:
		if planned_bound.intersects(bounds):
			return false
	for runtime_id in _spatial_index.query_overlapping(bounds):
		if runtime_id != parent_runtime_id:
			return false
	return true

func try_apply_knockback(runtime_id: int, direction: Vector3, speed: float) -> bool:
	if _mode != Mode.GAMEPLAY:
		return false
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

func get_nearest_combat_target_ray_hit(ray_origin: Vector3, ray_direction: Vector3, maximum_distance: float) -> Variant:
	assert(ray_origin.is_finite() and ray_direction.is_finite() and not ray_direction.is_zero_approx())
	assert(is_finite(maximum_distance) and maximum_distance > 0.0)
	if _suspended:
		return null
	var direction := ray_direction.normalized()
	var nearest_hit: Variant = null
	var nearest_distance := maximum_distance + 1.0
	var nearest_runtime_id := 0
	for runtime_id in _spatial_index.query_ray(ray_origin, direction, maximum_distance):
		var actor := get_actor(runtime_id)
		if actor == null or actor.definition == null or not actor.definition.combat_targetable:
			continue
		var hit: Variant = actor.get_world_bounds().intersects_ray(ray_origin, direction)
		if not hit is Vector3:
			continue
		var distance := ((hit as Vector3) - ray_origin).dot(direction)
		if distance < 0.0 or distance > maximum_distance:
			continue
		if distance < nearest_distance or (is_equal_approx(distance, nearest_distance) and runtime_id < nearest_runtime_id):
			nearest_hit = hit
			nearest_distance = distance
			nearest_runtime_id = runtime_id
	return nearest_hit

func record_melee_outcome(outcome: MeleeOutcome) -> void:
	if _mode != Mode.GAMEPLAY:
		return
	var target := get_actor(outcome.contact.target_runtime_id)
	if target != null:
		target.record_melee_contact(outcome.contact.hit_direction)

func record_projectile_outcome(outcome: ProjectileOutcome) -> void:
	if _mode != Mode.GAMEPLAY:
		return
	var target := get_actor(outcome.contact.target_runtime_id)
	if target != null:
		target.record_melee_contact(outcome.contact.hit_direction)

func _on_actor_melee_contact_reached(source_runtime_id: int, profile: MeleeAttackProfile) -> void:
	if _mode == Mode.GAMEPLAY:
		entity_melee_contact_reached.emit(source_runtime_id, profile)

func _on_actor_water_surface_motion_committed(position: Vector3, planar_velocity: Vector2) -> void:
	water_surface_motion_committed.emit(position, planar_velocity)

func _on_actor_radial_contact_reached(source_runtime_id: int, profile: MeleeAttackProfile) -> void:
	if _mode == Mode.GAMEPLAY:
		entity_radial_contact_reached.emit(source_runtime_id, profile)

func _set_actor_aggro(runtime_id: int, active: bool) -> void:
	if active:
		_aggroed_runtime_ids[runtime_id] = true
	else:
		_aggroed_runtime_ids.erase(runtime_id)
	_sync_aggro_state()

func _sync_aggro_state() -> void:
	var active := not _suspended and not _aggroed_runtime_ids.is_empty()
	if active == _aggro_active:
		return
	_aggro_active = active
	aggro_changed.emit(active)

func suspend() -> void:
	if _suspended:
		return
	_suspended = true
	visible = false
	_set_active_actors_suspended(true)
	_sync_aggro_state()

func resume() -> void:
	if not _suspended:
		return
	visible = true
	_suspended = false
	_set_active_actors_suspended(false)
	_sync_aggro_state()

func _set_active_actors_suspended(suspended: bool) -> void:
	for value in _active.values():
		var actor := value as EntityActor
		if is_instance_valid(actor):
			actor.set_runtime_suspended(suspended)

func is_suspended() -> bool:
	return _suspended

func shutdown() -> void:
	_aggroed_runtime_ids.clear()
	_sync_aggro_state()
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
	_damage_immunity_remaining_by_runtime_id.clear()
	_retiring.clear()
	_lineage_id_by_runtime_id.clear()
	_lineage_member_count_by_id.clear()
	_lineage_root_definition_by_id.clear()
	_active_lineage_count_by_root_definition.clear()
	_spatial_index.clear()
	_clear_prepared_actors()
	_catalog = null
	_voxel_space = null
	_navigation_limits = null
	_navigation_search_budget = null
	_max_population_cost = 0
	_max_retiring_visuals = 0
	_next_runtime_id = 1
	_next_lineage_id = 1
	_population_cost = 0
	_actor_tick_start_index = 0
	_prepared_definition_cursor = 0
	_preparation_needed = false
	_next_retirement_sequence = 0
	_aggro_active = false
	_aggroed_runtime_ids.clear()
	_suspended = false
	_mode = Mode.GAMEPLAY
