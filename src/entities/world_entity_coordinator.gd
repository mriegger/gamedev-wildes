extends Node3D
class_name WorldEntityCoordinator

const SPAWN_INTERVAL_SECONDS: float = 2.0
const SPAWN_ATTEMPTS: int = 4
const MIN_SPAWN_DISTANCE: float = 18.0
const MAX_SPAWN_DISTANCE: float = 36.0
const DESPAWN_DISTANCE: float = 56.0
const MAX_TOTAL_ACTIVE: int = 16
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
var _ambient_definition_cursor: int = 0
var _spawn_elapsed: float = 0.0
var _suspended: bool = false

func setup(p_catalog: EntityCatalog, p_voxel_world: VoxelWorld, world_seed: int, p_position_ready: Callable) -> void:
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
	_ambient_definition_cursor = 0
	_spawn_elapsed = 0.0
	_suspended = false
	visible = true
	_runtime.setup(
		p_catalog,
		p_voxel_world,
		MAX_TOTAL_ACTIVE,
		MAX_RETIRING_VISUALS,
		EntityNavigationLimits.new(
			MAX_NAVIGATION_SEARCH_RADIUS,
			MAX_NAVIGATION_SEARCH_NODES,
			MAX_NAVIGATION_SEARCHES_PER_TICK,
		),
	)

func tick(delta: float, observation: EntityTargetObservation, time_of_day: float) -> void:
	assert(_catalog != null and _voxel_world != null and _runtime != null)
	assert(not _suspended)
	assert(observation != null and observation.validate())
	var player_position := observation.player_position
	var is_day := DayNightProfile.is_day_time(time_of_day)
	_despawn_distant(player_position)
	_despawn_outside_phase(is_day)
	_runtime.tick(delta, observation)
	_spawn_elapsed += delta
	if _spawn_elapsed < SPAWN_INTERVAL_SECONDS:
		return
	_spawn_elapsed = fmod(_spawn_elapsed, SPAWN_INTERVAL_SECONDS)
	if _runtime.get_active_count() >= MAX_TOTAL_ACTIVE:
		return
	var definition_count := _catalog.definitions.size()
	for offset in range(definition_count):
		var definition_index := (_ambient_definition_cursor + offset) % definition_count
		var definition := _catalog.definitions[definition_index]
		if definition == null or _runtime.get_definition_count(definition.id) >= definition.ambient_max_active:
			continue
		if is_day != (definition.ambient_spawn_phase == EntityDefinition.SpawnPhase.DAY):
			continue
		if _try_spawn(definition, player_position):
			_ambient_definition_cursor = (definition_index + 1) % definition_count
			return

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
	var surface_y := _voxel_world.get_terrain_surface_y(x, z)
	if surface_y == VoxelSpace.NO_SURFACE_Y:
		return null
	var floor_y := int(surface_y)
	var floor_id := _voxel_world.get_block_id_at(Vector3i(x, floor_y, z))
	if not definition.can_spawn_ambiently_on(floor_id):
		return null
	var feet_y := floor_y + 1
	if definition.spawn_placement == EntityDefinition.SpawnPlacement.AERIAL:
		feet_y += rng.randi_range(definition.ambient_aerial_altitude_min_blocks, definition.ambient_aerial_altitude_max_blocks)
	var candidate := Vector3(float(x) + 0.5, float(feet_y), float(z) + 0.5)
	return candidate if EntitySpawnGeometry.can_spawn(_voxel_world, definition, candidate) else null

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
	if _runtime.get_active_count() + count > MAX_TOTAL_ACTIVE or not _catalog.has_definition(&"bird"):
		return false
	var requested_variant := -1 if variant_id.is_empty() else BirdActor.color_variant_index_for_id(variant_id)
	if not variant_id.is_empty() and requested_variant < 0:
		return false
	var definition := _catalog.get_definition(&"bird")
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
				var variant_index := requested_variant if requested_variant >= 0 else index % BirdActor.color_variant_count()
				var behavior_seed := BirdActor.behavior_seed_for_color_variant_index(variant_index, int(_debug_rng.randi()))
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

func _despawn_outside_phase(is_day: bool) -> void:
	var to_remove: Array[int] = []
	for actor in _runtime.get_active_actors():
		var definition := actor.definition
		if definition.ambient_despawn_outside_spawn_phase and is_day != (definition.ambient_spawn_phase == EntityDefinition.SpawnPhase.DAY):
			to_remove.append(actor.runtime_id)
	for runtime_id in to_remove:
		_runtime.try_despawn(runtime_id)

func _despawn_distant(player_position: Vector3) -> void:
	var max_distance_squared := DESPAWN_DISTANCE * DESPAWN_DISTANCE
	var to_remove: Array[int] = []
	for actor in _runtime.get_active_actors():
		if actor.global_position.distance_squared_to(player_position) > max_distance_squared or not bool(_position_ready.call(actor.global_position)):
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
	_ambient_definition_cursor = 0
	_spawn_elapsed = 0.0
	_suspended = false
