extends Node3D
class_name WorldEntityCoordinator

const SPAWN_INTERVAL_SECONDS: float = 2.0
const SPAWN_ATTEMPTS: int = 4
const MIN_SPAWN_DISTANCE: float = 18.0
const MAX_SPAWN_DISTANCE: float = 36.0
const DESPAWN_DISTANCE: float = 56.0
const MAX_TOTAL_ACTIVE: int = 16
const MAX_TOTAL_POPULATION_COST: int = 32
const MAX_RETIRING_VISUALS: int = 12
const MAX_NAVIGATION_SEARCH_RADIUS: int = 32
const MAX_NAVIGATION_SEARCH_NODES: int = 512
const MAX_NAVIGATION_SEARCHES_PER_TICK: int = 2
const DEBUG_SPAWN_BATCH_ATTEMPTS: int = 8
const DEBUG_SPAWN_POSITION_ATTEMPTS: int = 16
const DEBUG_SPAWN_MIN_DISTANCE: float = 4.0
const DEBUG_SPAWN_MAX_DISTANCE: float = 14.0

var _catalog: EntityCatalog
var _voxel_world: VoxelWorld
var _position_ready: Callable
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _debug_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _runtime: EntityRuntime
var _spawn_elapsed: float = 0.0
var _suspended: bool = false

func setup(
	p_catalog: EntityCatalog,
	p_voxel_world: VoxelWorld,
	world_seed: int,
	p_position_ready: Callable,
) -> void:
	assert(p_catalog != null and p_catalog.validate())
	assert(p_voxel_world != null)
	assert(p_position_ready.is_valid())
	if _runtime == null:
		_runtime = EntityRuntime.new()
		add_child(_runtime)
	_catalog = p_catalog
	_voxel_world = p_voxel_world
	_position_ready = p_position_ready
	_rng.seed = world_seed
	_debug_rng.seed = world_seed ^ 0x2b7e1516
	_spawn_elapsed = 0.0
	_suspended = false
	visible = true
	_runtime.setup(
		p_catalog,
		p_voxel_world,
		MAX_TOTAL_POPULATION_COST,
		MAX_RETIRING_VISUALS,
		EntityNavigationLimits.new(
			MAX_NAVIGATION_SEARCH_RADIUS,
			MAX_NAVIGATION_SEARCH_NODES,
			MAX_NAVIGATION_SEARCHES_PER_TICK,
		),
		EntityRuntime.Mode.GAMEPLAY,
	)

func tick(delta: float, observation: EntityTargetObservation, time_of_day: float) -> void:
	assert(_catalog != null and _voxel_world != null and _runtime != null)
	assert(not _suspended)
	assert(observation != null and observation.validate())
	assert(is_finite(delta) and delta >= 0.0)
	assert(is_finite(time_of_day))
	var player_position := observation.player_position
	_despawn_distant(player_position)
	_despawn_outside_spawn_window(time_of_day)
	_runtime.tick_gameplay(delta, observation)
	_spawn_elapsed += delta
	if _spawn_elapsed < SPAWN_INTERVAL_SECONDS:
		return
	_spawn_elapsed = fmod(_spawn_elapsed, SPAWN_INTERVAL_SECONDS)
	if _runtime.get_active_count() >= MAX_TOTAL_ACTIVE:
		return
	var definition := _select_ambient_definition(time_of_day)
	if definition == null:
		return
	if definition.ambient_max_active > 0 and _runtime.get_active_lineage_count(definition.id) >= definition.ambient_max_active:
		return
	_try_spawn(definition, player_position)

func _select_ambient_definition(time_of_day: float) -> EntityDefinition:
	var candidates: Array[EntityDefinition] = []
	var total_weight := 0.0
	for definition in _catalog.definitions:
		if definition == null or not definition.ambient_spawn_enabled:
			continue
		if not _is_in_ambient_spawn_window(definition, time_of_day):
			continue
		candidates.append(definition)
		total_weight += definition.ambient_spawn_weight
	if candidates.is_empty():
		return null
	var selection := _rng.randf() * total_weight
	for definition in candidates:
		selection -= definition.ambient_spawn_weight
		if selection < 0.0:
			return definition
	return candidates.back()

func _is_in_ambient_spawn_window(definition: EntityDefinition, time_of_day: float) -> bool:
	var start_hour := DayNightProfile.DAY_START_HOUR if definition.ambient_spawn_phase == EntityDefinition.SpawnPhase.DAY else DayNightProfile.NIGHT_START_HOUR
	var default_end_hour := DayNightProfile.NIGHT_START_HOUR if definition.ambient_spawn_phase == EntityDefinition.SpawnPhase.DAY else DayNightProfile.DAY_START_HOUR
	var end_hour := definition.ambient_spawn_end_hour if definition.ambient_spawn_end_hour >= 0.0 else default_end_hour
	var normalized_time := fposmod(time_of_day, GameClock.HOURS_PER_DAY)
	if start_hour < end_hour:
		return normalized_time >= start_hour and normalized_time < end_hour
	return normalized_time >= start_hour or normalized_time < end_hour

func _try_spawn(definition: EntityDefinition, player_position: Vector3) -> bool:
	for _attempt in range(SPAWN_ATTEMPTS):
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(MIN_SPAWN_DISTANCE, MAX_SPAWN_DISTANCE)
		var x := int(floor(player_position.x + cos(angle) * distance))
		var z := int(floor(player_position.z + sin(angle) * distance))
		var candidate_position := Vector3(float(x) + 0.5, player_position.y, float(z) + 0.5)
		if not bool(_position_ready.call(candidate_position)):
			continue
		var spawn_candidate: Variant = _find_spawn_position(definition, x, z, _rng)
		if not spawn_candidate is Vector3:
			continue
		var spawn_position := spawn_candidate as Vector3
		var horizontal_offset := Vector2(spawn_position.x - player_position.x, spawn_position.z - player_position.z)
		var horizontal_distance_squared := horizontal_offset.length_squared()
		if horizontal_distance_squared < MIN_SPAWN_DISTANCE * MIN_SPAWN_DISTANCE or horizontal_distance_squared > MAX_SPAWN_DISTANCE * MAX_SPAWN_DISTANCE:
			continue
		var requests: Array[EntitySpawnRequest] = [
			EntitySpawnRequest.new(definition.id, spawn_position, int(_rng.randi())),
		]
		return not _runtime.try_spawn_batch(requests).is_empty()
	return false

func _find_spawn_position(definition: EntityDefinition, x: int, z: int, rng: RandomNumberGenerator) -> Variant:
	var floor_y := _find_spawn_floor_y(definition, x, z)
	if floor_y < 0:
		return null
	var feet_y := floor_y + 1
	if definition.spawn_placement == EntityDefinition.SpawnPlacement.AERIAL:
		feet_y += rng.randi_range(definition.ambient_aerial_altitude_min_blocks, definition.ambient_aerial_altitude_max_blocks)
	var candidate := Vector3(float(x) + 0.5, float(feet_y), float(z) + 0.5)
	return candidate if EntitySpawnGeometry.can_spawn(_voxel_world, definition, candidate) else null

func _find_spawn_floor_y(definition: EntityDefinition, x: int, z: int) -> int:
	var highest_top := _voxel_world.get_highest_top(x, z)
	if highest_top != VoxelSpace.NO_SURFACE_Y:
		var highest_y := floori(highest_top - 0.001)
		if definition.can_spawn_ambiently_on(_voxel_world.get_block_id_at(Vector3i(x, highest_y, z))):
			return highest_y
	var terrain_y := _voxel_world.get_terrain_surface_y(x, z)
	if terrain_y == VoxelSpace.NO_SURFACE_Y:
		return -1
	var floor_y := int(terrain_y)
	return floor_y if definition.can_spawn_ambiently_on(_voxel_world.get_block_id_at(Vector3i(x, floor_y, z))) else -1

func try_spawn_debug_birds(player_position: Vector3, variant_id: StringName, count: int) -> bool:
	if (
		_runtime == null
		or _catalog == null
		or _voxel_world == null
		or not _position_ready.is_valid()
		or _suspended
		or not player_position.is_finite()
		or count < 1
		or count > MAX_TOTAL_ACTIVE
	):
		return false
	var requested_variant := -1 if variant_id.is_empty() else BirdActor.color_variant_index_for_id(variant_id)
	if not variant_id.is_empty() and requested_variant < 0:
		return false
	var definition_id := &"owl" if requested_variant == BirdAnimationDriver.ColorVariant.OWL else &"bird"
	if _runtime.get_active_count() + count > MAX_TOTAL_ACTIVE or not _catalog.has_definition(definition_id):
		return false
	var definition := _catalog.get_definition(definition_id)
	for _batch_attempt in DEBUG_SPAWN_BATCH_ATTEMPTS:
		var requests: Array[EntitySpawnRequest] = []
		var reserved_columns: Dictionary = {}
		for index in count:
			var request: EntitySpawnRequest = null
			for _position_attempt in DEBUG_SPAWN_POSITION_ATTEMPTS:
				var angle := _debug_rng.randf_range(0.0, TAU)
				var distance := _debug_rng.randf_range(DEBUG_SPAWN_MIN_DISTANCE, DEBUG_SPAWN_MAX_DISTANCE)
				var x := floori(player_position.x + cos(angle) * distance)
				var z := floori(player_position.z + sin(angle) * distance)
				var column := Vector2i(x, z)
				if reserved_columns.has(column):
					continue
				var streamed_position := Vector3(float(x) + 0.5, player_position.y, float(z) + 0.5)
				if not bool(_position_ready.call(streamed_position)):
					continue
				var spawn_candidate: Variant = _find_spawn_position(definition, x, z, _debug_rng)
				if not spawn_candidate is Vector3:
					continue
				var behavior_seed := int(_debug_rng.randi())
				if definition_id == &"bird":
					var variant_index := requested_variant if requested_variant >= 0 else index % BirdActor.color_variant_count()
					behavior_seed = BirdActor.behavior_seed_for_color_variant_index(variant_index, behavior_seed)
				request = EntitySpawnRequest.new(definition.id, spawn_candidate as Vector3, behavior_seed)
				reserved_columns[column] = true
				break
			if request == null:
				break
			requests.append(request)
		if requests.size() != count:
			continue
		if _runtime.try_spawn_batch(requests).size() == count:
			return true
	return false

func _despawn_outside_spawn_window(time_of_day: float) -> void:
	var to_remove: Array[int] = []
	for actor in _runtime.get_active_actors():
		var definition := actor.definition
		if actor.can_despawn_ambiently() and definition.ambient_despawn_outside_spawn_phase and not _is_in_ambient_spawn_window(definition, time_of_day):
			to_remove.append(actor.runtime_id)
	for runtime_id in to_remove:
		_runtime.try_despawn(runtime_id)

func _despawn_distant(player_position: Vector3) -> void:
	var max_distance_squared := DESPAWN_DISTANCE * DESPAWN_DISTANCE
	var to_remove: Array[int] = []
	for actor in _runtime.get_active_actors():
		if not bool(_position_ready.call(actor.global_position)):
			to_remove.append(actor.runtime_id)
		elif actor.can_despawn_ambiently() and actor.global_position.distance_squared_to(player_position) > max_distance_squared:
			to_remove.append(actor.runtime_id)
	for runtime_id in to_remove:
		_runtime.try_despawn(runtime_id)

func get_runtime() -> EntityRuntime:
	return _runtime

func suspend() -> void:
	if _suspended:
		return
	_suspended = true
	visible = false
	_runtime.suspend()

func resume() -> void:
	if not _suspended:
		return
	_runtime.resume()
	visible = true
	_suspended = false

func is_suspended() -> bool:
	return _suspended

func shutdown() -> void:
	if _runtime != null:
		_runtime.shutdown()
	_catalog = null
	_voxel_world = null
	_position_ready = Callable()
	_spawn_elapsed = 0.0
	_suspended = false
