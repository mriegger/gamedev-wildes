extends SceneTree

const FLAT_HEIGHT: int = 6
const FEET_Y: float = float(FLAT_HEIGHT + 1)
const TEST_RADIUS: int = 64
const MAX_CELLS_PER_ACTOR: int = 8

var _failures: int = 0
var _ready_calls: int = 0
var _streaming_ready: bool = false

func _init() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[entity_population_integration] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-TEST_RADIUS, TEST_RADIUS + 1):
		for z in range(-TEST_RADIUS, TEST_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLAT_HEIGHT
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _position_ready(_position: Vector3) -> bool:
	_ready_calls += 1
	return _streaming_ready

func _sorted_actors(coordinator: EntityCoordinator) -> Array[EntityActor]:
	var actors := coordinator.get_active_actors()
	actors.sort_custom(func(left: EntityActor, right: EntityActor) -> bool: return left.runtime_id < right.runtime_id)
	return actors

func _expect_index_bounded(coordinator: EntityCoordinator, context: String) -> void:
	var active_count := coordinator.get_active_count()
	var index := coordinator._spatial_index as EntitySpatialIndex
	_expect(index.get_entry_count() == active_count, "%s spatial entry count diverged from active population" % context)
	_expect(index.get_cell_count() <= active_count * MAX_CELLS_PER_ACTOR, "%s spatial cell count exceeded the active-population bound" % context)
	if active_count == 0:
		_expect(index.get_cell_count() == 0, "%s retained cells for an empty population" % context)

func _run() -> void:
	var catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	var world := _make_world()
	var coordinator := EntityCoordinator.new()
	get_root().add_child(coordinator)
	coordinator.setup(catalog, world, 1337, _position_ready)
	var player_position := Vector3(0.5, FEET_Y, 0.5)

	_ready_calls = 0
	coordinator.tick(1.0, player_position, 20.0)
	_expect(coordinator.get_active_count() == 0, "spawn occurred before the two-second interval")
	_expect(_ready_calls == 0, "spawn candidates were checked before the interval")
	coordinator.tick(1.0, player_position, 20.0)
	_expect(coordinator.get_active_count() == 0, "rejected spawn cycle created an actor")
	_expect(_ready_calls == EntityCoordinator.SPAWN_ATTEMPTS, "rejected cycle did not stop after four attempts")
	_expect_index_bounded(coordinator, "rejected cycle")

	_streaming_ready = true
	var spawned_ids: Array[int] = []
	var spawn_positions: Array[Vector3] = []
	coordinator.tick(1.0, player_position, 20.0)
	_expect(coordinator.get_active_count() == 0, "spawn interval carried time across a completed cycle")
	for cycle in range(6):
		var delta := 1.0 if cycle == 0 else EntityCoordinator.SPAWN_INTERVAL_SECONDS
		var before_count := coordinator.get_active_count()
		coordinator.tick(delta, player_position, 20.0)
		var after_count := coordinator.get_active_count()
		_expect(after_count == before_count + 1, "cycle %d did not add exactly one zombie" % cycle)
		for actor in _sorted_actors(coordinator):
			if not spawned_ids.has(actor.runtime_id):
				spawned_ids.append(actor.runtime_id)
				spawn_positions.append(actor.global_position)
		_expect_index_bounded(coordinator, "spawn cycle %d" % cycle)

	coordinator.tick(EntityCoordinator.SPAWN_INTERVAL_SECONDS, player_position, 20.0)
	_expect(coordinator.get_active_count() == 6, "seventh spawn cycle exceeded the six-zombie cap")
	var actors_with_paths := 0
	for actor in _sorted_actors(coordinator):
		if not (actor as ZombieActor)._path_follower._path.is_empty():
			actors_with_paths += 1
	_expect(actors_with_paths >= 4, "shared navigation budget reached only %d due actors" % actors_with_paths)
	_expect(spawned_ids == [1, 2, 3, 4, 5, 6], "runtime IDs were not unique and increasing")
	_expect(spawn_positions.size() == 6, "did not capture all six spawn positions")
	for index in range(spawn_positions.size()):
		var position := spawn_positions[index]
		var horizontal_distance := Vector2(position.x - player_position.x, position.z - player_position.z).length()
		_expect(horizontal_distance >= EntityCoordinator.MIN_SPAWN_DISTANCE, "spawn %d was inside the minimum annulus at %.3f" % [index, horizontal_distance])
		_expect(horizontal_distance <= EntityCoordinator.MAX_SPAWN_DISTANCE, "spawn %d exceeded the maximum annulus at %.3f" % [index, horizontal_distance])
	_expect_index_bounded(coordinator, "population cap")

	var actors := _sorted_actors(coordinator)
	if actors.size() == 6:
		var overlap_position := Vector3(0.5, FEET_Y, 0.5)
		actors[0].global_position = overlap_position
		actors[1].global_position = overlap_position
		actors[2].global_position = Vector3(10.5, FEET_Y, 10.5)
		actors[3].global_position = Vector3(18.5, FEET_Y, 18.5)
		actors[4].global_position = Vector3(-10.5, FEET_Y, 10.5)
		actors[5].global_position = Vector3(10.5, FEET_Y, -10.5)
		coordinator._refresh_spatial_index()
		var first_separation := coordinator._get_separation_velocity(actors[0])
		var second_separation := coordinator._get_separation_velocity(actors[1])
		_expect(first_separation.length() > 0.0 and second_separation.length() > 0.0, "overlapping zombies received no separation")
		_expect(first_separation.is_equal_approx(-second_separation), "overlapping zombies did not receive opposite separation")
		coordinator.tick(0.1, overlap_position, 20.0)
		_expect(actors[0].global_position.distance_to(actors[1].global_position) > 0.0, "overlapping zombies did not move apart")
		_expect_index_bounded(coordinator, "separation update")

		var distance_id := actors[5].runtime_id
		actors[5].global_position = player_position + Vector3(EntityCoordinator.DESPAWN_DISTANCE + 1.0, 0.0, 0.0)
		coordinator.tick(0.0, player_position, 20.0)
		_expect(coordinator.get_actor(distance_id) == null, "distance despawn retained the actor")
		_expect(coordinator.get_active_count() == 5, "distance despawn changed the wrong population count")
		_expect_index_bounded(coordinator, "distance despawn")

		_streaming_ready = false
		coordinator.tick(0.0, player_position, 20.0)
		_expect(coordinator.get_active_count() == 0, "streaming despawn retained active actors")
		_expect_index_bounded(coordinator, "streaming despawn")

	coordinator.shutdown()
	coordinator.queue_free()
	await process_frame
	await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "shutdown ended with %d orphan nodes" % orphan_count)
	if _failures == 0:
		print("ENTITY_POPULATION_INTEGRATION PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("ENTITY_POPULATION_INTEGRATION FAIL failures=%d" % _failures)
		quit(1)
