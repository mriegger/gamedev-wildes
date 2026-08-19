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
const MIXED_NIGHT_STEPS: int = 120
const MIXED_NIGHT_DELTA: float = 0.05
const STREAM_RETIRE_SECONDS: float = 0.4
const EXPECTED_STONE_GOLEM_COUNT: int = 2
const ZOMBIE_OFFSETS: Array[Vector2i] = [
	Vector2i(-8, -4),
	Vector2i(0, -10),
	Vector2i(8, -4),
	Vector2i(-4, -16),
	Vector2i(4, -16),
]
const SKELETON_OFFSETS: Array[Vector2i] = [Vector2i(-10, -8), Vector2i(0, -12), Vector2i(10, -8)]
const STONE_GOLEM_OFFSETS: Array[Vector2i] = [Vector2i(-16, 0), Vector2i(16, 0)]
const SHEEP_OFFSETS: Array[Vector2i] = [Vector2i(-14, 8), Vector2i(-7, 14), Vector2i(7, 14), Vector2i(14, 8), Vector2i(-14, -14), Vector2i(14, -14)]
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
var _stone_golem_radial_contacts: Dictionary = {}
var _melee_contact_count: int = 0
var _radial_contact_count: int = 0
var _max_navigation_searches: int = 0
var _frames_with_navigation_search: int = 0
var _full_combat_regions: int = 0
var _mid_action_stream_loss_regions: int = 0
var _path_acquisition_by_runtime_id: Dictionary = {}
var _full_path_acquisition_count: int = 0
var _full_path_acquisitions_by_species: Dictionary = {
	&"zombie": 0,
	&"skeleton": 0,
	&"stone_golem": 0,
	&"sheep": 0,
}

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[soak_entity_streaming] FAIL: %s" % message)

func _consume_melee_contact(_source_runtime_id: int, _profile: MeleeAttackProfile) -> void:
	_melee_contact_count += 1

func _consume_radial_contact(source_runtime_id: int, profile: MeleeAttackProfile) -> void:
	_radial_contact_count += 1
	if profile.id != &"stone_golem_slam":
		return
	_stone_golem_radial_contacts[source_runtime_id] = int(_stone_golem_radial_contacts.get(source_runtime_id, 0)) + 1

func _observation(player_position: Vector3) -> EntityTargetObservation:
	var observation := EntityTargetObservation.create(
		player_position,
		player_position + Vector3(12.0, 16.0, 12.0),
		Vector3(-0.5, -0.5, -0.5),
		Vector3(1.0, 0.0, -1.0),
	)
	assert(observation != null)
	return observation

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

func _prepare_full_night_population(coordinator: WorldEntityCoordinator, catalog: EntityCatalog, player_position: Vector3, region_index: int) -> void:
	var runtime := coordinator.get_runtime()
	var bird_count := runtime.get_definition_count(&"bird")
	var expected_bird_count := catalog.get_definition(&"bird").ambient_max_active
	_expect(bird_count == expected_bird_count, "region %d did not reach the Bird cap before its final night transition" % region_index)
	coordinator._spawn_elapsed = 0.0
	coordinator.tick(0.0, _observation(player_position), NIGHT_TIME)
	var transition_context := "region %d final night transition" % region_index
	_assert_population(coordinator, catalog, player_position, NIGHT_TIME, transition_context)
	_expect(runtime.get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE - bird_count, "%s did not retire every Bird" % transition_context)
	for replacement_index in range(bird_count):
		var count_before := runtime.get_active_count()
		coordinator._spawn_elapsed = WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS
		coordinator.tick(0.0, _observation(player_position), NIGHT_TIME)
		var replacement_context := "region %d night replacement %d" % [region_index, replacement_index]
		_assert_population(coordinator, catalog, player_position, NIGHT_TIME, replacement_context)
		_expect(runtime.get_active_count() == count_before + 1, "%s did not add exactly one night actor" % replacement_context)
	_expect(
		runtime.get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE,
		"region %d night replacements did not restore the total population cap" % region_index,
	)
	_assert_mixed_night_population(coordinator, catalog, "region %d prepared night workload" % region_index)

func _workload_offsets(definition_id: StringName) -> Array[Vector2i]:
	match definition_id:
		&"zombie":
			return ZOMBIE_OFFSETS
		&"skeleton":
			return SKELETON_OFFSETS
		&"stone_golem":
			return STONE_GOLEM_OFFSETS
		&"sheep":
			return SHEEP_OFFSETS
	var empty: Array[Vector2i] = []
	return empty

func _arrange_active_population(coordinator: WorldEntityCoordinator, player_position: Vector3) -> Dictionary:
	var actors := coordinator.get_runtime().get_active_actors()
	actors.sort_custom(func(left: EntityActor, right: EntityActor) -> bool: return left.runtime_id < right.runtime_id)
	var next_index: Dictionary = {
		&"zombie": 0,
		&"skeleton": 0,
		&"stone_golem": 0,
		&"sheep": 0,
	}
	var activity: Dictionary = {}
	for actor in actors:
		var definition_id := actor.definition.id
		var offsets := _workload_offsets(definition_id)
		var index := int(next_index.get(definition_id, 0))
		_expect(index < offsets.size(), "active workload had an unexpected %s actor" % definition_id)
		if index >= offsets.size():
			continue
		next_index[definition_id] = index + 1
		var offset := offsets[index]
		actor.global_position = player_position + Vector3(float(offset.x), 0.0, float(offset.y))
		actor.velocity = Vector3.ZERO
		actor.on_ground = true
		_path_acquisition_by_runtime_id[actor.runtime_id] = {
			"definition_id": definition_id,
			"path_seen": false,
		}
		match definition_id:
			&"zombie":
				var zombie := actor as ZombieActor
				_expect(zombie != null, "active workload Zombie used the wrong actor type")
				if zombie != null:
					zombie._path_follower.request_repath()
			&"skeleton":
				var skeleton := actor as SkeletonActor
				_expect(skeleton != null, "active workload Skeleton used the wrong actor type")
				if skeleton != null:
					skeleton._path_follower.request_repath()
			&"stone_golem":
				var stone_golem := actor as StoneGolemActorType
				_expect(stone_golem != null, "active workload Stone Golem used the wrong actor type")
				if stone_golem != null:
					stone_golem._path_follower.request_repath()
					_stone_golem_radial_contacts[actor.runtime_id] = 0
					activity[actor.runtime_id] = {
						"initial_position": actor.global_position,
						"chase_seen": false,
						"path_seen": false,
						"airborne_seen": false,
						"recovery_seen": false,
						"max_displacement": 0.0,
					}
			&"sheep":
				var sheep := actor as SheepActor
				_expect(sheep != null, "active workload Sheep used the wrong actor type")
				if sheep != null:
					sheep._path_follower.request_repath()
		coordinator.get_runtime()._spatial_index.upsert(actor.runtime_id, actor.global_position, actor.get_world_bounds())
	_expect(int(next_index[&"zombie"]) == ZOMBIE_OFFSETS.size(), "active workload did not arrange %d Zombies" % ZOMBIE_OFFSETS.size())
	_expect(int(next_index[&"skeleton"]) == SKELETON_OFFSETS.size(), "active workload did not arrange three Skeletons")
	_expect(int(next_index[&"stone_golem"]) == STONE_GOLEM_OFFSETS.size(), "active workload did not arrange two Stone Golems")
	_expect(int(next_index[&"sheep"]) == SHEEP_OFFSETS.size(), "active workload did not arrange six Sheep")
	return activity

func _record_stone_golem_activity(coordinator: WorldEntityCoordinator, activity: Dictionary) -> void:
	for actor in coordinator.get_runtime().get_active_actors():
		if not activity.has(actor.runtime_id):
			continue
		var stone_golem := actor as StoneGolemActorType
		var record := activity[actor.runtime_id] as Dictionary
		if stone_golem.brain.state == StoneGolemBrainType.State.CHASE:
			record["chase_seen"] = true
			if not stone_golem._path_follower._path.is_empty():
				record["path_seen"] = true
		elif stone_golem.brain.state == StoneGolemBrainType.State.SLAM_AIRBORNE:
			record["airborne_seen"] = true
		elif stone_golem.brain.state == StoneGolemBrainType.State.SLAM_RECOVERY:
			record["recovery_seen"] = true
		var initial_position: Vector3 = record["initial_position"]
		var offset := actor.global_position - initial_position
		offset.y = 0.0
		record["max_displacement"] = maxf(float(record["max_displacement"]), offset.length())

func _record_navigation_budget(coordinator: WorldEntityCoordinator, context: String) -> void:
	var search_count := WorldEntityCoordinator.MAX_NAVIGATION_SEARCHES_PER_TICK - coordinator.get_runtime()._navigation_search_budget._remaining_searches
	_expect(search_count >= 0 and search_count <= WorldEntityCoordinator.MAX_NAVIGATION_SEARCHES_PER_TICK, "%s exceeded the navigation search budget" % context)
	_max_navigation_searches = maxi(_max_navigation_searches, search_count)
	if search_count > 0:
		_frames_with_navigation_search += 1

func _actor_has_navigation_path(actor: EntityActor) -> bool:
	match actor.definition.id:
		&"zombie":
			return not (actor as ZombieActor)._path_follower._path.is_empty()
		&"skeleton":
			return not (actor as SkeletonActor)._path_follower._path.is_empty()
		&"stone_golem":
			return not (actor as StoneGolemActorType)._path_follower._path.is_empty()
		&"sheep":
			return not (actor as SheepActor)._path_follower._path.is_empty()
	return false

func _record_path_acquisition(coordinator: WorldEntityCoordinator) -> void:
	for actor in coordinator.get_runtime().get_active_actors():
		if not _path_acquisition_by_runtime_id.has(actor.runtime_id):
			continue
		if _actor_has_navigation_path(actor):
			var record := _path_acquisition_by_runtime_id[actor.runtime_id] as Dictionary
			record["path_seen"] = true

func _assert_full_region_path_acquisition(coordinator: WorldEntityCoordinator, context: String) -> void:
	var actors := coordinator.get_runtime().get_active_actors()
	_expect(actors.size() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "%s did not retain the full population for path evidence" % context)
	for actor in actors:
		var record_value: Variant = _path_acquisition_by_runtime_id.get(actor.runtime_id)
		_expect(record_value is Dictionary, "%s runtime ID %d had no path record" % [context, actor.runtime_id])
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var acquired := bool(record["path_seen"])
		_expect(acquired, "%s %s runtime ID %d never acquired a path" % [context, actor.definition.id, actor.runtime_id])
		if acquired:
			_full_path_acquisition_count += 1
			var definition_id: StringName = record["definition_id"]
			_full_path_acquisitions_by_species[definition_id] = int(_full_path_acquisitions_by_species[definition_id]) + 1

func _active_slam_count(coordinator: WorldEntityCoordinator) -> int:
	var count := 0
	for actor in coordinator.get_runtime().get_active_actors():
		if actor.definition.id != &"stone_golem":
			continue
		var stone_golem := actor as StoneGolemActorType
		if stone_golem.brain.state == StoneGolemBrainType.State.SLAM_WINDUP or stone_golem.brain.state == StoneGolemBrainType.State.SLAM_AIRBORNE:
			count += 1
	return count

func _assert_stone_golem_activity(activity: Dictionary, require_completed_slam: bool, context: String) -> void:
	_expect(activity.size() == EXPECTED_STONE_GOLEM_COUNT, "%s did not track two Stone Golems" % context)
	var minimum_displacement := 3.0 if require_completed_slam else 0.5
	for runtime_id in activity:
		var record := activity[runtime_id] as Dictionary
		_expect(bool(record["chase_seen"]), "%s Stone Golem %d never chased" % [context, runtime_id])
		_expect(bool(record["path_seen"]), "%s Stone Golem %d never acquired a path" % [context, runtime_id])
		_expect(float(record["max_displacement"]) >= minimum_displacement, "%s Stone Golem %d did not move before its slam" % [context, runtime_id])
		if require_completed_slam:
			_expect(bool(record["airborne_seen"]), "%s Stone Golem %d never became airborne" % [context, runtime_id])
			_expect(bool(record["recovery_seen"]), "%s Stone Golem %d never entered recovery" % [context, runtime_id])
			_expect(int(_stone_golem_radial_contacts.get(runtime_id, 0)) > 0, "%s Stone Golem %d emitted no radial contact" % [context, runtime_id])

func _run() -> void:
	var catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	_expect(catalog != null and catalog.validate(), "entity catalog failed validation")
	var world := _make_flat_world()
	var coordinator := WorldEntityCoordinator.new()
	get_root().add_child(coordinator)
	coordinator.setup(catalog, world, 730241, _is_position_streamed)
	coordinator.get_runtime().entity_melee_contact_reached.connect(_consume_melee_contact)
	coordinator.get_runtime().entity_radial_contact_reached.connect(_consume_radial_contact)

	for region_index in range(STREAM_REGIONS.size()):
		_ready_region = STREAM_REGIONS[region_index]
		var player_position := _player_position(_ready_region)
		coordinator.tick(0.0, _observation(player_position), DAY_TIME)
		_assert_population(coordinator, catalog, player_position, DAY_TIME, "region %d entry" % region_index)
		_expect(coordinator.get_runtime().get_active_count() == 0, "region %d entry did not clear the previous population" % region_index)
		_expect(coordinator.get_runtime().get_definition_count(&"stone_golem") == 0, "region %d entry retained a Stone Golem" % region_index)
		await process_frame
		for cycle in range(CYCLES_PER_REGION):
			var time_of_day := DAY_TIME if cycle < 10 or cycle >= 16 else NIGHT_TIME
			coordinator._spawn_elapsed = WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS
			coordinator.tick(0.0, _observation(player_position), time_of_day)
			var context := "region %d cycle %d" % [region_index, cycle]
			_assert_population(coordinator, catalog, player_position, time_of_day, context)
			_assert_path_budget(world, catalog, _ready_region, time_of_day, cycle, context)
		for refill_cycle in range(CYCLES_PER_REGION):
			if coordinator.get_runtime().get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE:
				break
			var cycle := CYCLES_PER_REGION + refill_cycle
			var time_of_day := DAY_TIME if cycle % 2 == 0 else NIGHT_TIME
			coordinator._spawn_elapsed = WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS
			coordinator.tick(0.0, _observation(player_position), time_of_day)
			var context := "region %d refill cycle %d" % [region_index, refill_cycle]
			_assert_population(coordinator, catalog, player_position, time_of_day, context)
			_assert_path_budget(world, catalog, _ready_region, time_of_day, cycle, context)
		_expect(coordinator.get_runtime().get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "region %d did not reach the total population cap" % region_index)
		_prepare_full_night_population(coordinator, catalog, player_position, region_index)
		var stone_golem_activity := _arrange_active_population(coordinator, player_position)
		var stream_mid_action := region_index % 2 == 1
		var reached_mid_action := false
		for step in range(MIXED_NIGHT_STEPS):
			coordinator.tick(MIXED_NIGHT_DELTA, _observation(player_position), NIGHT_TIME)
			var context := "region %d mixed night step %d" % [region_index, step]
			_record_navigation_budget(coordinator, context)
			_record_path_acquisition(coordinator)
			_record_stone_golem_activity(coordinator, stone_golem_activity)
			_assert_population(coordinator, catalog, player_position, NIGHT_TIME, context)
			_assert_mixed_night_population(coordinator, catalog, context)
			if stream_mid_action and _active_slam_count(coordinator) == EXPECTED_STONE_GOLEM_COUNT:
				reached_mid_action = true
				break
		var activity_context := "region %d active workload" % region_index
		if stream_mid_action:
			_expect(reached_mid_action, "%s never reached simultaneous active slams" % activity_context)
			_assert_stone_golem_activity(stone_golem_activity, false, activity_context)
			var contacts_before_stream_loss := _melee_contact_count + _radial_contact_count
			_streaming_enabled = false
			coordinator.tick(0.0, _observation(player_position), NIGHT_TIME)
			_assert_population(coordinator, catalog, player_position, NIGHT_TIME, "region %d streaming loss" % region_index)
			_expect(coordinator.get_runtime().get_active_count() == 0, "region %d streaming loss retained actors" % region_index)
			_expect(coordinator.get_runtime().get_definition_count(&"stone_golem") == 0, "region %d streaming loss retained a Stone Golem" % region_index)
			coordinator.tick(STREAM_RETIRE_SECONDS, _observation(player_position), NIGHT_TIME)
			_expect(_melee_contact_count + _radial_contact_count == contacts_before_stream_loss, "region %d streaming loss emitted a delayed contact" % region_index)
			_expect(coordinator.get_runtime()._retiring.is_empty(), "region %d streaming loss retained fading actors" % region_index)
			_expect(coordinator.get_runtime()._spatial_index.get_entry_count() == 0, "region %d streaming loss retained spatial entries" % region_index)
			_expect(coordinator.get_runtime()._spatial_index.get_cell_count() == 0, "region %d streaming loss retained spatial cells" % region_index)
			_streaming_enabled = true
			_mid_action_stream_loss_regions += 1
			await process_frame
		else:
			_assert_stone_golem_activity(stone_golem_activity, true, activity_context)
			_assert_full_region_path_acquisition(coordinator, activity_context)
			_full_combat_regions += 1

	_streaming_enabled = false
	var final_position := _player_position(_ready_region)
	coordinator.tick(0.0, _observation(final_position), NIGHT_TIME)
	_assert_population(coordinator, catalog, final_position, NIGHT_TIME, "final streaming loss")
	_expect(coordinator.get_runtime().get_definition_count(&"stone_golem") == 0, "final streaming loss retained a Stone Golem")
	var expected_runtime_ids_per_region := CYCLES_PER_REGION + catalog.get_definition(&"bird").ambient_max_active
	var expected_runtime_ids := STREAM_REGIONS.size() * expected_runtime_ids_per_region
	_expect(_instance_by_runtime_id.size() == expected_runtime_ids, "soak observed %d unique runtime IDs instead of %d" % [_instance_by_runtime_id.size(), expected_runtime_ids])
	_expect(_max_navigation_searches == WorldEntityCoordinator.MAX_NAVIGATION_SEARCHES_PER_TICK, "active workload never consumed both navigation searches")
	_expect(_frames_with_navigation_search > 0, "active workload performed no navigation searches")
	_expect(_full_combat_regions == STREAM_REGIONS.size() / 2, "soak completed %d full-combat regions instead of four" % _full_combat_regions)
	_expect(_mid_action_stream_loss_regions == STREAM_REGIONS.size() / 2, "soak completed %d mid-action stream losses instead of four" % _mid_action_stream_loss_regions)
	var expected_full_regions := STREAM_REGIONS.size() / 2
	var expected_full_path_acquisitions := expected_full_regions * WorldEntityCoordinator.MAX_TOTAL_ACTIVE
	_expect(_full_path_acquisition_count == expected_full_path_acquisitions, "full workloads recorded %d path acquisitions instead of %d" % [_full_path_acquisition_count, expected_full_path_acquisitions])
	_expect(int(_full_path_acquisitions_by_species[&"zombie"]) == expected_full_regions * ZOMBIE_OFFSETS.size(), "full workloads did not record every Zombie path acquisition")
	_expect(int(_full_path_acquisitions_by_species[&"skeleton"]) == expected_full_regions * SKELETON_OFFSETS.size(), "full workloads did not record every Skeleton path acquisition")
	_expect(int(_full_path_acquisitions_by_species[&"stone_golem"]) == expected_full_regions * STONE_GOLEM_OFFSETS.size(), "full workloads did not record every Stone Golem path acquisition")
	_expect(int(_full_path_acquisitions_by_species[&"sheep"]) == expected_full_regions * SHEEP_OFFSETS.size(), "full workloads did not record every Sheep path acquisition")
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
		print(
			"SOAK_ENTITY_STREAMING PASS regions=%d cycles=%d runtime_ids=%d searches=%d full_combat=%d stream_loss=%d path_actors=%d/%d path_species=zombie:%d,skeleton:%d,stone_golem:%d,sheep:%d contacts=%d orphan=%d" % [
				STREAM_REGIONS.size(),
				STREAM_REGIONS.size() * CYCLES_PER_REGION,
				_instance_by_runtime_id.size(),
				_max_navigation_searches,
				_full_combat_regions,
				_mid_action_stream_loss_regions,
				_full_path_acquisition_count,
				expected_full_path_acquisitions,
				int(_full_path_acquisitions_by_species[&"zombie"]),
				int(_full_path_acquisitions_by_species[&"skeleton"]),
				int(_full_path_acquisitions_by_species[&"stone_golem"]),
				int(_full_path_acquisitions_by_species[&"sheep"]),
				_melee_contact_count + _radial_contact_count,
				orphan_count,
			]
		)
		quit(0)
	else:
		print("SOAK_ENTITY_STREAMING FAIL failures=%d" % _failures)
		quit(1)
