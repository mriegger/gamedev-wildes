extends SceneTree

const FLOOR_Y: int = 3
const FEET_Y: float = float(FLOOR_Y + 1)
const WORLD_RADIUS: int = 72
const DAY_TIME: float = 12.0
const NIGHT_TIME: float = 20.0
const WEIGHT_SAMPLE_COUNT: int = 3100
const SPAWN_CYCLE_LIMIT: int = 96

var _failures: int = 0
var _streaming_ready: bool = true

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[watcher_ambient_integration] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
		for z in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLOOR_Y
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _make_watcher_catalog() -> EntityCatalog:
	var catalog := EntityCatalog.new()
	catalog.definitions = [
		load("res://entities/definitions/watcher.tres") as EntityDefinition,
	]
	return catalog

func _make_weighted_catalog() -> EntityCatalog:
	var catalog := EntityCatalog.new()
	catalog.definitions = [
		load("res://entities/definitions/zombie.tres") as EntityDefinition,
		load("res://entities/definitions/skeleton.tres") as EntityDefinition,
		load("res://entities/definitions/slime_large.tres") as EntityDefinition,
		load("res://entities/definitions/slime_medium.tres") as EntityDefinition,
		load("res://entities/definitions/slime_small.tres") as EntityDefinition,
		load("res://entities/definitions/watcher.tres") as EntityDefinition,
	]
	return catalog

func _position_ready(_position: Vector3) -> bool:
	return _streaming_ready

func _observation(player_position: Vector3) -> EntityTargetObservation:
	return EntityTargetObservation.create(
		player_position,
		player_position,
		Vector3.FORWARD,
		Vector3.RIGHT,
	)

func _test_weighted_selection_and_floors() -> void:
	var catalog := _make_weighted_catalog()
	_expect(catalog.validate(), "watcher and slime lineage catalog did not validate")
	var main_catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	_expect(main_catalog != null and main_catalog.validate(), "main entity catalog did not validate")
	if main_catalog != null:
		_expect(main_catalog.has_definition(&"watcher"), "main catalog omitted Watcher")
		_expect(main_catalog.has_definition(&"slime_large") and main_catalog.has_definition(&"slime_medium") and main_catalog.has_definition(&"slime_small"), "main catalog lost slime lineage definitions")
	var watcher := catalog.get_definition(&"watcher")
	_expect(watcher.ambient_spawn_phase == EntityDefinition.SpawnPhase.NIGHT, "Watcher is not night-only ambient content")
	_expect(is_equal_approx(watcher.ambient_spawn_weight, 10.0), "Watcher ambient weight is not ten")
	_expect(watcher.ambient_max_active == 0, "Watcher retained a species-specific ambient quota")
	for common_id in [&"zombie", &"skeleton", &"slime_large"]:
		_expect(is_equal_approx(catalog.get_definition(common_id).ambient_spawn_weight, 100.0), "%s ambient weight is not one hundred" % common_id)
	var first := WorldEntityCoordinator.new()
	var second := WorldEntityCoordinator.new()
	first._catalog = catalog
	second._catalog = catalog
	first._rng.seed = 849221
	second._rng.seed = 849221
	var counts: Dictionary = {
		&"zombie": 0,
		&"skeleton": 0,
		&"slime_large": 0,
		&"watcher": 0,
	}
	for _sample in WEIGHT_SAMPLE_COUNT:
		var first_choice := first._select_ambient_definition(NIGHT_TIME)
		var second_choice := second._select_ambient_definition(NIGHT_TIME)
		_expect(first_choice != null and second_choice != null, "night selection returned no ambient definition")
		if first_choice == null or second_choice == null:
			continue
		_expect(first_choice.id == second_choice.id, "identical world seeds produced different weighted selections")
		counts[first_choice.id] = int(counts.get(first_choice.id, 0)) + 1
	_expect(int(counts[&"watcher"]) > 0, "seeded weighted selection never selected Watcher")
	for common_id in [&"zombie", &"skeleton", &"slime_large"]:
		_expect(int(counts[common_id]) > int(counts[&"watcher"]) * 4, "Watcher was not materially less common than %s" % common_id)
	_expect(first._select_ambient_definition(DAY_TIME) == null, "night-only catalog selected an ambient entity during the day")
	first.free()
	second.free()
	var allowed_floors: Array[int] = [
		BlockId.Type.GRASS,
		BlockId.Type.DIRT,
		BlockId.Type.SAND,
		BlockId.Type.STONE,
	]
	_expect(watcher.ambient_spawn_floor_ids == allowed_floors, "Watcher ambient floors changed")
	var world := _make_world()
	var floor_coordinator := WorldEntityCoordinator.new()
	floor_coordinator._voxel_world = world
	var floor_rng := RandomNumberGenerator.new()
	floor_rng.seed = 1
	for index in allowed_floors.size():
		var x := index
		world.type_map_dict[Vector2i(x, 0)] = allowed_floors[index]
		var candidate: Variant = floor_coordinator._find_spawn_position(watcher, x, 0, floor_rng)
		_expect(candidate is Vector3, "Watcher rejected allowed floor %d" % allowed_floors[index])
	world.type_map_dict[Vector2i(allowed_floors.size(), 0)] = BlockId.Type.LOG
	_expect(floor_coordinator._find_spawn_position(watcher, allowed_floors.size(), 0, floor_rng) == null, "Watcher accepted a non-configured floor")
	floor_coordinator.free()

func _test_population_lifecycle() -> void:
	var catalog := _make_watcher_catalog()
	_expect(catalog.validate(), "Watcher-only catalog did not validate")
	var coordinator := WorldEntityCoordinator.new()
	root.add_child(coordinator)
	_streaming_ready = true
	coordinator.setup(catalog, _make_world(), 780123, _position_ready)
	var runtime := coordinator.get_runtime()
	var player_position := Vector3(0.5, FEET_Y, 0.5)
	coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, _observation(player_position), DAY_TIME)
	_expect(runtime.get_active_count() == 0, "Watcher spawned during the day")
	var cycles := 0
	while runtime.get_active_count() < WorldEntityCoordinator.MAX_TOTAL_ACTIVE and cycles < SPAWN_CYCLE_LIMIT:
		coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, _observation(player_position), NIGHT_TIME)
		cycles += 1
	_expect(runtime.get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "Watcher population did not reach the global active bound")
	_expect(runtime.get_definition_count(&"watcher") == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "non-Watcher entity appeared in Watcher-only population")
	_expect(runtime.get_active_lineage_count(&"watcher") == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "Watcher-specific quota limited independent ambient lineages")
	_expect(runtime.get_population_cost() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "Watcher population cost did not match its independent lineages")
	coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, _observation(player_position), NIGHT_TIME)
	_expect(runtime.get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "Watcher spawning exceeded the global active bound")
	var replacement_id := runtime.get_active_actors()[0].runtime_id
	_expect(runtime.try_despawn(replacement_id), "Watcher selected for replacement did not despawn")
	_expect(runtime.get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE - 1, "Watcher despawn removed the wrong population amount")
	var replacement_cycles := 0
	while runtime.get_active_count() < WorldEntityCoordinator.MAX_TOTAL_ACTIVE and replacement_cycles < SPAWN_CYCLE_LIMIT:
		coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, _observation(player_position), NIGHT_TIME)
		replacement_cycles += 1
	_expect(runtime.get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "same-night replacement did not restore the global population bound")
	coordinator.tick(0.0, _observation(player_position), DAY_TIME)
	_expect(runtime.get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "Watchers despawned at dawn")
	var hostile := runtime.get_active_actors()[0] as WatcherActor
	hostile.record_player_attack()
	var hostile_id := hostile.runtime_id
	hostile.global_position = player_position + Vector3(WorldEntityCoordinator.DESPAWN_DISTANCE + 4.0, 0.0, 0.0)
	coordinator.tick(0.0, _observation(player_position), DAY_TIME)
	_expect(runtime.get_actor(hostile_id) == hostile, "hostile Watcher was removed by ordinary distance despawning")
	_streaming_ready = false
	coordinator.tick(0.0, _observation(player_position), DAY_TIME)
	_expect(runtime.get_actor(hostile_id) == null, "unstreamed hostile Watcher resisted mandatory cleanup")
	_expect(runtime.get_active_count() == 0, "unstreamed cleanup retained ambient actors")
	coordinator.shutdown()
	coordinator.queue_free()

func _test_slime_lineage_coexistence() -> void:
	var catalog := _make_weighted_catalog()
	var runtime := EntityRuntime.new()
	root.add_child(runtime)
	runtime.setup(
		catalog,
		_make_world(),
		WorldEntityCoordinator.MAX_TOTAL_POPULATION_COST,
		WorldEntityCoordinator.MAX_RETIRING_VISUALS,
		EntityNavigationLimits.new(24, 256, 1),
	)
	var requests: Array[EntitySpawnRequest] = [
		EntitySpawnRequest.new(&"watcher", Vector3(-8.5, FEET_Y, 0.5), 171),
		EntitySpawnRequest.new(&"slime_large", Vector3(8.5, FEET_Y, 0.5), 221),
	]
	var runtime_ids := runtime.try_spawn_batch(requests)
	_expect(runtime_ids.size() == 2, "Watcher and large slime could not coexist in one spawn transaction")
	if runtime_ids.size() == 2:
		var watcher_id := runtime_ids[0]
		var result := runtime.try_apply_damage(runtime_ids[1], 1000.0)
		_expect(result != null and result.defeated, "coexisting large slime did not complete its defeat lineage")
		_expect(runtime.get_actor(watcher_id) is WatcherActor, "slime lineage transition removed the coexisting Watcher")
		_expect(runtime.get_active_lineage_count(&"watcher") == 1, "slime split changed Watcher lineage ownership")
		_expect(runtime.get_active_lineage_count(&"slime_large") == 1, "slime descendants lost their root lineage")
		_expect(runtime.get_definition_count(&"slime_medium") >= 2, "large slime did not produce medium descendants beside Watcher")
	runtime.shutdown()
	runtime.queue_free()

func _run() -> void:
	var orphan_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_test_weighted_selection_and_floors()
	_test_population_lifecycle()
	_test_slime_lineage_coexistence()
	await process_frame
	await process_frame
	var orphan_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_after == orphan_before, "ambient integration changed orphan count from %d to %d" % [orphan_before, orphan_after])
	if _failures == 0:
		print("WATCHER_AMBIENT_INTEGRATION PASS")
		quit(0)
	else:
		print("WATCHER_AMBIENT_INTEGRATION FAIL failures=%d" % _failures)
		quit(1)
