extends SceneTree

const StoneGolemActorType := preload("res://entities/stone_golem/stone_golem_actor.gd")
const StoneGolemBrainType := preload("res://entities/stone_golem/stone_golem_brain.gd")

const FLAT_HEIGHT: int = 6
const FEET_Y: int = FLAT_HEIGHT + 1
const STREAM_REGION_SIZE: int = 128
const CYCLES_PER_REGION: int = 20
const DAY_TIME: float = 12.0
const NIGHT_TIME: float = 20.0
const MAX_CELLS_PER_ACTOR: int = 8
const PATH_RADIUS: int = 12
const PATH_NODE_BUDGET: int = 64
const MIXED_NIGHT_STEPS: int = 8
const MIXED_NIGHT_DELTA: float = 0.05
const STREAM_REGIONS: Array[Vector2i] = [
	Vector2i(-3, -2),
	Vector2i(-1, 1),
	Vector2i(2, -1),
	Vector2i(4, 2),
	Vector2i(1, 4),
	Vector2i(-2, 3),
	Vector2i(-4, 0),
	Vector2i(0, -4),
]

var _failures: int = 0
var _streaming_enabled: bool = true
var _ready_region: Vector2i = STREAM_REGIONS[0]
var _instance_by_runtime_id: Dictionary = {}

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[soak_entity_streaming] FAIL: %s" % message)

func _make_flat_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for region in STREAM_REGIONS:
		var origin := region * STREAM_REGION_SIZE
		for x in range(origin.x, origin.x + STREAM_REGION_SIZE):
			for z in range(origin.y, origin.y + STREAM_REGION_SIZE):
				world.height_map_dict[Vector2i(x, z)] = FLAT_HEIGHT
				world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _region_at(position: Vector3) -> Vector2i:
	return Vector2i(
		floori(position.x / float(STREAM_REGION_SIZE)),
		floori(position.z / float(STREAM_REGION_SIZE))
	)

func _is_position_streamed(position: Vector3) -> bool:
	return _streaming_enabled and _region_at(position) == _ready_region

func _player_position(region: Vector2i) -> Vector3:
	var origin := region * STREAM_REGION_SIZE
	var center := STREAM_REGION_SIZE / 2
	return Vector3(float(origin.x + center) + 0.5, float(FEET_Y), float(origin.y + center) + 0.5)

func _eligible_definitions(catalog: EntityCatalog, time_of_day: float) -> Array[EntityDefinition]:
	var eligible: Array[EntityDefinition] = []
	var is_day := DayNightProfile.is_day_time(time_of_day)
	for definition in catalog.definitions:
		if definition != null and is_day == (definition.ambient_spawn_phase == EntityDefinition.SpawnPhase.DAY):
			eligible.append(definition)
	return eligible

func _assert_path_budget(world: VoxelWorld, catalog: EntityCatalog, region: Vector2i, time_of_day: float, cycle: int, context: String) -> void:
	var definitions := _eligible_definitions(catalog, time_of_day)
	_expect(not definitions.is_empty(), "%s had no eligible ambient definitions" % context)
	if not DayNightProfile.is_day_time(time_of_day):
		_expect(definitions.size() == 3, "%s did not exercise all three night species" % context)
	var origin := region * STREAM_REGION_SIZE + Vector2i(STREAM_REGION_SIZE / 2, STREAM_REGION_SIZE / 2)
	for index in range(definitions.size()):
		var definition := definitions[index]
		var z_offset := (cycle + index) % 3 - 1
		var start := Vector3i(origin.x - 4, FEET_Y, origin.y + z_offset)
		var goal := Vector3i(origin.x + 4, FEET_Y, origin.y - z_offset)
		var result := VoxelPathfinder.find_path(world, start, goal, definition.body_width, definition.body_height, PATH_RADIUS, PATH_NODE_BUDGET)
		_expect(result.is_success(), "%s representative %s path failed with status %d" % [context, definition.id, result.status])
		_expect(result.visited_nodes > 0 and result.visited_nodes <= PATH_NODE_BUDGET, "%s %s path visited %d nodes with budget %d" % [context, definition.id, result.visited_nodes, PATH_NODE_BUDGET])
		if result.is_success():
			_expect(result.path.front() == start and result.path.back() == goal, "%s %s path endpoints changed" % [context, definition.id])

func _assert_runtime_ids(actors: Array[EntityActor], context: String) -> void:
	var active_ids: Dictionary = {}
	for actor in actors:
		var runtime_id := actor.runtime_id
		_expect(runtime_id > 0, "%s actor had invalid runtime ID %d" % [context, runtime_id])
		_expect(not active_ids.has(runtime_id), "%s duplicated active runtime ID %d" % [context, runtime_id])
		active_ids[runtime_id] = true
		var instance_id := actor.get_instance_id()
		if _instance_by_runtime_id.has(runtime_id):
			_expect(int(_instance_by_runtime_id[runtime_id]) == instance_id, "%s reused runtime ID %d for another actor" % [context, runtime_id])
		else:
			_instance_by_runtime_id[runtime_id] = instance_id

func _assert_population(coordinator: WorldEntityCoordinator, catalog: EntityCatalog, player_position: Vector3, time_of_day: float, context: String) -> void:
	var actors := coordinator.get_runtime().get_active_actors()
	var active_count := coordinator.get_runtime().get_active_count()
	var retiring_count := coordinator.get_runtime()._retiring.size()
	_expect(actors.size() == active_count, "%s active actor query returned %d of %d" % [context, actors.size(), active_count])
	_expect(active_count <= WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "%s exceeded the active entity cap" % context)
	_expect(retiring_count <= WorldEntityCoordinator.MAX_RETIRING_VISUALS, "%s exceeded the retiring-visual cap" % context)
	var species_counts: Dictionary = {}
	for definition in catalog.definitions:
		if definition != null:
			species_counts[definition.id] = 0
	for actor in actors:
		if actor.definition == null or not species_counts.has(actor.definition.id):
			_expect(false, "%s contained an unknown entity definition" % context)
			continue
		species_counts[actor.definition.id] = int(species_counts[actor.definition.id]) + 1
		_expect(actor.global_position.distance_squared_to(player_position) <= WorldEntityCoordinator.DESPAWN_DISTANCE * WorldEntityCoordinator.DESPAWN_DISTANCE, "%s retained runtime ID %d beyond despawn distance" % [context, actor.runtime_id])
		_expect(_is_position_streamed(actor.global_position), "%s retained runtime ID %d outside the streamed region" % [context, actor.runtime_id])
	for definition in catalog.definitions:
		if definition != null:
			_expect(int(species_counts[definition.id]) <= definition.ambient_max_active, "%s exceeded the %d-%s cap" % [context, definition.ambient_max_active, definition.id])
	if not DayNightProfile.is_day_time(time_of_day):
		_expect(int(species_counts[&"bird"]) == 0, "%s retained birds at night" % context)
	_assert_runtime_ids(actors, context)
	var spatial_index := coordinator.get_runtime()._spatial_index as EntitySpatialIndex
	var entry_count := spatial_index.get_entry_count()
	var cell_count := spatial_index.get_cell_count()
	_expect(entry_count == active_count, "%s spatial entries %d diverged from active count %d" % [context, entry_count, active_count])
	_expect(cell_count <= active_count * MAX_CELLS_PER_ACTOR, "%s spatial cells %d exceeded the active bound" % [context, cell_count])
	if active_count == 0:
		_expect(cell_count == 0, "%s retained spatial cells without active actors" % context)

func _assert_mixed_night_population(coordinator: WorldEntityCoordinator, catalog: EntityCatalog, context: String) -> void:
	var night_definitions := _eligible_definitions(catalog, NIGHT_TIME)
	_expect(night_definitions.size() == 3, "%s catalog did not contain exactly three night species" % context)
	var night_ids: Dictionary = {}
	for definition in night_definitions:
		night_ids[definition.id] = true
		_expect(coordinator.get_runtime().get_definition_count(definition.id) > 0, "%s did not retain night species %s" % [context, definition.id])
	_expect(night_ids.size() == 3 and night_ids.has(&"zombie") and night_ids.has(&"skeleton") and night_ids.has(&"stone_golem"), "%s night species IDs changed" % context)
	_expect(coordinator.get_runtime().get_definition_count(&"stone_golem") == 2, "%s did not contain exactly two Stone Golems" % context)

func _stone_golem_positions(coordinator: WorldEntityCoordinator, context: String) -> Dictionary:
	var positions: Dictionary = {}
	for actor in coordinator.get_runtime().get_active_actors():
		if actor.definition.id != &"stone_golem":
			continue
		_expect(actor is StoneGolemActorType, "%s Stone Golem used the wrong actor type" % context)
		if not actor is StoneGolemActorType:
			continue
		var stone_golem := actor as StoneGolemActorType
		_expect(stone_golem.brain != null and stone_golem.brain.state == StoneGolemBrainType.State.DORMANT, "%s Stone Golem %d was not dormant" % [context, actor.runtime_id])
		positions[actor.runtime_id] = actor.global_position
	_expect(positions.size() == 2, "%s observed %d Stone Golems instead of two" % [context, positions.size()])
	return positions

func _assert_stone_golems_stationary(coordinator: WorldEntityCoordinator, expected_positions: Dictionary, context: String) -> void:
	var current_positions := _stone_golem_positions(coordinator, context)
	_expect(current_positions.size() == expected_positions.size(), "%s changed the Stone Golem population" % context)
	for runtime_id in expected_positions:
		_expect(current_positions.has(runtime_id), "%s removed Stone Golem %d" % [context, runtime_id])
		if current_positions.has(runtime_id):
			var expected_position: Vector3 = expected_positions[runtime_id]
			var current_position: Vector3 = current_positions[runtime_id]
			_expect(current_position.is_equal_approx(expected_position), "%s moved dormant Stone Golem %d" % [context, runtime_id])

func _run() -> void:
	var catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	_expect(catalog != null and catalog.validate(), "entity catalog failed validation")
	var world := _make_flat_world()
	var coordinator := WorldEntityCoordinator.new()
	get_root().add_child(coordinator)
	coordinator.setup(catalog, world, 730241, _is_position_streamed)

	for region_index in range(STREAM_REGIONS.size()):
		_ready_region = STREAM_REGIONS[region_index]
		var player_position := _player_position(_ready_region)
		coordinator.tick(0.0, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), DAY_TIME)
		_assert_population(coordinator, catalog, player_position, DAY_TIME, "region %d entry" % region_index)
		_expect(coordinator.get_runtime().get_active_count() == 0, "region %d entry did not clear the previous population" % region_index)
		_expect(coordinator.get_runtime().get_definition_count(&"stone_golem") == 0, "region %d entry retained a Stone Golem" % region_index)
		await process_frame
		for cycle in range(CYCLES_PER_REGION):
			var time_of_day := DAY_TIME if cycle < 10 or cycle >= 16 else NIGHT_TIME
			coordinator._spawn_elapsed = WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS
			coordinator.tick(0.0, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), time_of_day)
			var context := "region %d cycle %d" % [region_index, cycle]
			_assert_population(coordinator, catalog, player_position, time_of_day, context)
			_assert_path_budget(world, catalog, _ready_region, time_of_day, cycle, context)
		for refill_cycle in range(CYCLES_PER_REGION):
			if coordinator.get_runtime().get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE:
				break
			var cycle := CYCLES_PER_REGION + refill_cycle
			var time_of_day := DAY_TIME if cycle % 2 == 0 else NIGHT_TIME
			coordinator._spawn_elapsed = WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS
			coordinator.tick(0.0, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), time_of_day)
			var context := "region %d refill cycle %d" % [region_index, refill_cycle]
			_assert_population(coordinator, catalog, player_position, time_of_day, context)
			_assert_path_budget(world, catalog, _ready_region, time_of_day, cycle, context)
		_expect(coordinator.get_runtime().get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "region %d did not reach the total population cap" % region_index)
		_assert_mixed_night_population(coordinator, catalog, "region %d mixed night" % region_index)
		var stone_golem_positions := _stone_golem_positions(coordinator, "region %d filled" % region_index)
		for step in range(MIXED_NIGHT_STEPS):
			coordinator.tick(MIXED_NIGHT_DELTA, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), NIGHT_TIME)
			var context := "region %d mixed night step %d" % [region_index, step]
			_assert_population(coordinator, catalog, player_position, NIGHT_TIME, context)
			_assert_mixed_night_population(coordinator, catalog, context)
			_assert_stone_golems_stationary(coordinator, stone_golem_positions, context)
		if region_index % 2 == 1:
			_streaming_enabled = false
			coordinator.tick(0.0, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), NIGHT_TIME)
			_assert_population(coordinator, catalog, player_position, NIGHT_TIME, "region %d streaming loss" % region_index)
			_expect(coordinator.get_runtime().get_active_count() == 0, "region %d streaming loss retained actors" % region_index)
			_expect(coordinator.get_runtime().get_definition_count(&"stone_golem") == 0, "region %d streaming loss retained a Stone Golem" % region_index)
			_streaming_enabled = true
			await process_frame

	_streaming_enabled = false
	var final_position := _player_position(_ready_region)
	coordinator.tick(0.0, EntityTargetObservation.create(final_position, final_position, Vector3.FORWARD, Vector3.RIGHT), NIGHT_TIME)
	_assert_population(coordinator, catalog, final_position, NIGHT_TIME, "final streaming loss")
	_expect(coordinator.get_runtime().get_definition_count(&"stone_golem") == 0, "final streaming loss retained a Stone Golem")
	_expect(_instance_by_runtime_id.size() == STREAM_REGIONS.size() * CYCLES_PER_REGION, "soak observed %d unique runtime IDs instead of %d" % [_instance_by_runtime_id.size(), STREAM_REGIONS.size() * CYCLES_PER_REGION])
	coordinator.shutdown()
	_expect(coordinator.get_runtime().get_definition_count(&"stone_golem") == 0, "shutdown retained an active Stone Golem")
	_expect(coordinator.get_runtime().get_active_count() == 0, "shutdown retained active actors")
	_expect(coordinator.get_runtime()._retiring.is_empty(), "shutdown retained fading actors")
	_expect(coordinator.get_runtime()._spatial_index.get_entry_count() == 0, "shutdown retained spatial entries")
	_expect(coordinator.get_runtime()._spatial_index.get_cell_count() == 0, "shutdown retained spatial cells")
	coordinator.queue_free()
	await process_frame
	await process_frame
	await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "shutdown ended with %d orphan nodes" % orphan_count)
	if _failures == 0:
		print("SOAK_ENTITY_STREAMING PASS regions=%d cycles=%d runtime_ids=%d orphan=%d" % [STREAM_REGIONS.size(), STREAM_REGIONS.size() * CYCLES_PER_REGION, _instance_by_runtime_id.size(), orphan_count])
		quit(0)
	else:
		print("SOAK_ENTITY_STREAMING FAIL failures=%d" % _failures)
		quit(1)
