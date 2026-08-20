extends SceneTree

const FLOOR_Y: int = 3
const WORLD_RADIUS: int = 64
const DAY_TIME: float = 12.0
const NIGHT_TIME: float = 20.0

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[slime_ambient_integration] FAIL: %s" % message)

func _make_catalog() -> EntityCatalog:
	var catalog := EntityCatalog.new()
	catalog.definitions = [
		load("res://entities/definitions/slime_large.tres") as EntityDefinition,
		load("res://entities/definitions/slime_medium.tres") as EntityDefinition,
		load("res://entities/definitions/slime_small.tres") as EntityDefinition,
	]
	return catalog

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
		for z in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLOOR_Y
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _position_ready(_position: Vector3) -> bool:
	return true

func _observation(player_position: Vector3) -> EntityTargetObservation:
	return EntityTargetObservation.create(
		player_position,
		player_position,
		Vector3.FORWARD,
		Vector3.RIGHT,
	)

func _run() -> void:
	var orphan_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var catalog := _make_catalog()
	_expect(catalog.validate(), "slime-only catalog did not validate")
	var coordinator := WorldEntityCoordinator.new()
	root.add_child(coordinator)
	coordinator.setup(catalog, _make_world(), 88119, _position_ready)
	var runtime := coordinator.get_runtime()
	var player_position := Vector3(0.5, float(FLOOR_Y + 1), 0.5)
	coordinator.tick(
		WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS,
		_observation(player_position),
		DAY_TIME,
	)
	_expect(runtime.get_active_count() == 0, "slime spawned during the day")
	coordinator.tick(
		WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS,
		_observation(player_position),
		NIGHT_TIME,
	)
	_expect(runtime.get_definition_count(&"slime_large") == 1, "night did not spawn one ambient large slime")
	_expect(runtime.get_definition_count(&"slime_medium") == 0 and runtime.get_definition_count(&"slime_small") == 0, "split-only slime spawned ambiently")
	_expect(runtime.get_active_lineage_count(&"slime_large") == 1, "ambient large slime did not register one lineage")
	_expect(runtime.get_population_cost() == 16, "ambient large slime did not reserve sixteen population units")
	_expect(runtime._max_population_cost == WorldEntityCoordinator.MAX_TOTAL_POPULATION_COST, "world runtime did not use the bounded population capacity")
	var large := runtime.get_active_actors()[0]
	var result := runtime.try_apply_damage(large.runtime_id, 1000.0)
	_expect(result != null and result.defeated, "ambient large slime did not split on lethal damage")
	var descendant_count := runtime.get_active_count()
	_expect(descendant_count >= 2 and descendant_count <= 4, "large slime did not create two to four descendants")
	_expect(runtime.get_definition_count(&"slime_large") == 0 and runtime.get_definition_count(&"slime_medium") == descendant_count, "large slime descendants were not all medium")
	coordinator.tick(0.0, _observation(player_position), DAY_TIME)
	_expect(runtime.get_active_count() == descendant_count, "slime descendants despawned at dawn")
	coordinator.tick(
		WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS,
		_observation(player_position),
		NIGHT_TIME,
	)
	_expect(runtime.get_active_count() == descendant_count, "descendants did not block another ambient lineage")
	_expect(runtime.get_definition_count(&"slime_large") == 0, "another large slime spawned while descendants remained")
	var descendant_ids: Array[int] = []
	for actor in runtime.get_active_actors():
		descendant_ids.append(actor.runtime_id)
	for runtime_id in descendant_ids:
		_expect(runtime.try_despawn(runtime_id), "descendant despawn was rejected")
	_expect(runtime.get_active_lineage_count(&"slime_large") == 0, "final descendant did not release the ambient lineage")
	coordinator.tick(
		WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS,
		_observation(player_position),
		NIGHT_TIME,
	)
	_expect(runtime.get_definition_count(&"slime_large") == 1, "released lineage did not permit a later ambient large slime")
	coordinator.shutdown()
	coordinator.queue_free()
	await process_frame
	await process_frame
	var orphan_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_after == orphan_before, "ambient integration changed orphan count from %d to %d" % [orphan_before, orphan_after])
	if _failures == 0:
		print("SLIME_AMBIENT_INTEGRATION PASS orphan=%d" % orphan_after)
		quit(0)
	else:
		print("SLIME_AMBIENT_INTEGRATION FAIL failures=%d" % _failures)
		quit(1)
