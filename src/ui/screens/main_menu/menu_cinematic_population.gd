extends Node3D
class_name MenuCinematicPopulation

const MAX_RETIRING_VISUALS := 12
const MAX_NAVIGATION_SEARCH_RADIUS := 32
const MAX_NAVIGATION_SEARCH_NODES := 512
const MAX_NAVIGATION_SEARCHES_PER_TICK := 2
const MAX_POSITION_ATTEMPTS := 96

var _runtime: EntityRuntime

func _ready() -> void:
	set_physics_process(false)

func setup(
	catalog: EntityCatalog,
	voxel_world: VoxelWorld,
	profile: MenuCinematicProfile,
	water_ripple_callback: Callable,
) -> bool:
	assert(_runtime == null)
	assert(catalog != null and catalog.validate())
	assert(voxel_world != null)
	assert(profile != null and profile.validate(catalog))
	assert(water_ripple_callback.is_valid())
	_runtime = EntityRuntime.new()
	add_child(_runtime)
	_runtime.setup(
		catalog,
		voxel_world,
		MenuCinematicProfile.MAX_TOTAL_POPULATION_COST,
		MAX_RETIRING_VISUALS,
		EntityNavigationLimits.new(
			MAX_NAVIGATION_SEARCH_RADIUS,
			MAX_NAVIGATION_SEARCH_NODES,
			MAX_NAVIGATION_SEARCHES_PER_TICK,
		),
		EntityRuntime.Mode.PRESENTATION,
	)
	_runtime.water_surface_motion_committed.connect(water_ripple_callback)
	var requests := _build_spawn_requests(catalog, voxel_world, profile)
	if requests.is_empty():
		shutdown()
		return false
	if _runtime.try_spawn_batch(requests).size() != requests.size():
		shutdown()
		return false
	for actor in _runtime.get_active_actors():
		actor.advance_visual_fade(actor.visual_fader.fade_in_seconds)
	set_physics_process(false)
	return true

func start_simulation() -> void:
	assert(_runtime != null)
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	_runtime.tick_ambient(delta)

func shutdown() -> void:
	set_physics_process(false)
	if _runtime != null:
		_runtime.shutdown()
		_runtime.queue_free()
		_runtime = null

func get_runtime() -> EntityRuntime:
	return _runtime

func _build_spawn_requests(
	catalog: EntityCatalog,
	voxel_world: VoxelWorld,
	profile: MenuCinematicProfile,
) -> Array[EntitySpawnRequest]:
	var requests: Array[EntitySpawnRequest] = []
	var reserved_bounds: Array[AABB] = []
	for shot in profile.shots:
		for spawn in shot.spawns:
			var definition := catalog.get_definition(spawn.entity_id)
			for index in spawn.count:
				var position: Variant = _find_spawn_position(
					voxel_world,
					shot,
					spawn,
					definition,
					index,
					reserved_bounds,
				)
				if position == null:
					return []
				var feet_position := position as Vector3
				reserved_bounds.append(EntitySpawnGeometry.get_bounds(definition, feet_position))
				requests.append(EntitySpawnRequest.new(
					spawn.entity_id,
					feet_position,
					spawn.behavior_seed + index,
				))
	return requests

func _find_spawn_position(
	voxel_world: VoxelWorld,
	shot: MenuCinematicShot,
	spawn: MenuCinematicSpawn,
	definition: EntityDefinition,
	index: int,
	reserved_bounds: Array[AABB],
) -> Variant:
	var rng := RandomNumberGenerator.new()
	rng.seed = spawn.behavior_seed + index * 104729
	var origin := shot.anchor + spawn.column_offset
	var search_radius := maxi(spawn.spread_radius, 1) + 8
	for attempt in MAX_POSITION_ATTEMPTS:
		var column := origin
		if attempt > 0:
			column += Vector2i(
				rng.randi_range(-search_radius, search_radius),
				rng.randi_range(-search_radius, search_radius),
			)
		var position: Variant = _get_valid_spawn_position(
			voxel_world,
			definition,
			column,
			spawn.behavior_seed + index,
		)
		if position == null:
			continue
		var bounds := EntitySpawnGeometry.get_bounds(definition, position as Vector3)
		if not _overlaps_reserved(bounds, reserved_bounds):
			return position
	return null

func _get_valid_spawn_position(
	voxel_world: VoxelWorld,
	definition: EntityDefinition,
	column: Vector2i,
	behavior_seed: int,
) -> Variant:
	var surface_y := voxel_world.get_terrain_surface_y(column.x, column.y)
	if surface_y == VoxelSpace.NO_SURFACE_Y:
		return null
	var floor_y := int(surface_y)
	var floor_id := voxel_world.get_block_id_at(Vector3i(column.x, floor_y, column.y))
	if not definition.can_spawn_ambiently_on(floor_id):
		return null
	var feet_y := floor_y + 1
	if definition.spawn_placement == EntityDefinition.SpawnPlacement.AERIAL:
		var altitude_range := (
			definition.ambient_aerial_altitude_max_blocks
			- definition.ambient_aerial_altitude_min_blocks
			+ 1
		)
		feet_y += definition.ambient_aerial_altitude_min_blocks + absi(behavior_seed) % altitude_range
	var position := Vector3(float(column.x) + 0.5, float(feet_y), float(column.y) + 0.5)
	return position if EntitySpawnGeometry.can_spawn(voxel_world, definition, position) else null

func _overlaps_reserved(bounds: AABB, reserved_bounds: Array[AABB]) -> bool:
	for reserved in reserved_bounds:
		if bounds.intersects(reserved):
			return true
	return false
