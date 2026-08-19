extends SceneTree

const PerformanceSampleStats = preload("res://tests/performance_sample_stats.gd")

const WORLD_SEED: int = 1337
const FLAT_HEIGHT: int = 6
const FEET_Y: float = float(FLAT_HEIGHT + 1)
const WORLD_RADIUS: int = 64
const FRAME_DELTA: float = 1.0 / 60.0
const WARMUP_FRAMES: int = 300
const SAMPLE_FRAMES: int = 1800
const PATH_WARMUP_SAMPLES: int = 20
const PATH_SAMPLES: int = 200
const DAY_TIME: float = 12.0
const NIGHT_TIME: float = 20.0

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[entity_efficiency] FAIL: %s" % message)

func _make_flat_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
		for z in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLAT_HEIGHT
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _position_ready(_position: Vector3) -> bool:
	return true

func _consume_melee_contact(_source_runtime_id: int, _profile: MeleeAttackProfile) -> void:
	pass

func _spawn_population(coordinator: WorldEntityCoordinator, player_position: Vector3) -> Dictionary:
	var spawn_samples: Array[int] = []
	var preparation_samples: Array[int] = []
	for cycle in range(WorldEntityCoordinator.MAX_TOTAL_ACTIVE):
		var time_of_day := DAY_TIME if cycle % 2 == 0 else NIGHT_TIME
		var before_count := coordinator.get_runtime().get_active_count()
		coordinator._spawn_elapsed = WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS - FRAME_DELTA
		var spawn_started := Time.get_ticks_usec()
		coordinator.tick(FRAME_DELTA, player_position, time_of_day)
		spawn_samples.append(Time.get_ticks_usec() - spawn_started)
		_expect(coordinator.get_runtime().get_active_count() == before_count + 1, "spawn cycle %d did not add one actor" % cycle)
		var prepared_before := coordinator.get_runtime()._prepared_actor_count()
		var preparation_started := Time.get_ticks_usec()
		coordinator.tick(FRAME_DELTA, player_position, time_of_day)
		var preparation_usec := Time.get_ticks_usec() - preparation_started
		if coordinator.get_runtime()._prepared_actor_count() > prepared_before:
			preparation_samples.append(preparation_usec)
	_expect(spawn_samples.size() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "spawn benchmark did not collect twelve samples")
	_expect(preparation_samples.size() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "spawn benchmark did not collect twelve preparation samples")
	return {
		"spawn_frame": PerformanceSampleStats.summarize(spawn_samples),
		"preparation_frame": PerformanceSampleStats.summarize(preparation_samples),
	}

func _sorted_actors(coordinator: WorldEntityCoordinator) -> Array[EntityActor]:
	var actors := coordinator.get_runtime().get_active_actors()
	actors.sort_custom(func(left: EntityActor, right: EntityActor) -> bool: return left.runtime_id < right.runtime_id)
	return actors

func _arrange_population(coordinator: WorldEntityCoordinator, actors: Array[EntityActor]) -> void:
	var zombie_index := 0
	var sheep_index := 0
	for actor in actors:
		var angle: float
		var radius: float
		if actor.definition.id == &"zombie":
			angle = TAU * float(zombie_index) / 6.0
			radius = 8.0
			zombie_index += 1
			(actor as ZombieActor)._path_follower.request_repath()
		else:
			angle = TAU * float(sheep_index) / 6.0 + PI / 6.0
			radius = 14.0
			sheep_index += 1
			(actor as SheepActor)._path_follower.request_repath()
		actor.global_position = Vector3(0.5 + cos(angle) * radius, FEET_Y, 0.5 + sin(angle) * radius)
		actor.velocity = Vector3.ZERO
		actor.on_ground = true
		coordinator.get_runtime()._spatial_index.upsert(actor.runtime_id, actor.global_position, actor.get_world_bounds())
	_expect(zombie_index == 6, "benchmark population had %d zombies" % zombie_index)
	_expect(sheep_index == 6, "benchmark population had %d sheep" % sheep_index)

func _player_position(frame_index: int) -> Vector3:
	var angle := float(frame_index) * 0.015
	return Vector3(0.5 + cos(angle) * 3.0, FEET_Y, 0.5 + sin(angle) * 3.0)

func _advance_entity_frame(coordinator: WorldEntityCoordinator, actors: Array[EntityActor], frame_index: int) -> int:
	coordinator.tick(FRAME_DELTA, _player_position(frame_index), NIGHT_TIME)
	for actor in actors:
		actor.animation_driver.advance(FRAME_DELTA)
	return WorldEntityCoordinator.MAX_NAVIGATION_SEARCHES_PER_TICK - coordinator.get_runtime()._navigation_search_budget._remaining_searches

func _benchmark_entity_frames(coordinator: WorldEntityCoordinator, actors: Array[EntityActor]) -> Dictionary:
	var max_navigation_searches := 0
	var frames_with_navigation_search := 0
	for frame_index in range(WARMUP_FRAMES):
		var search_count := _advance_entity_frame(coordinator, actors, frame_index)
		max_navigation_searches = maxi(max_navigation_searches, search_count)
	var samples: Array[int] = []
	for frame_offset in range(SAMPLE_FRAMES):
		var frame_index := WARMUP_FRAMES + frame_offset
		var started := Time.get_ticks_usec()
		var search_count := _advance_entity_frame(coordinator, actors, frame_index)
		samples.append(Time.get_ticks_usec() - started)
		max_navigation_searches = maxi(max_navigation_searches, search_count)
		if search_count > 0:
			frames_with_navigation_search += 1
	_expect(max_navigation_searches <= WorldEntityCoordinator.MAX_NAVIGATION_SEARCHES_PER_TICK, "entity frame exceeded its navigation search budget")
	_expect(frames_with_navigation_search > 0, "timed entity frames performed no navigation searches")
	_expect(coordinator.get_runtime().get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "entity frame benchmark did not retain twelve actors")
	var result := PerformanceSampleStats.summarize(samples)
	result["max_navigation_searches_per_frame"] = max_navigation_searches
	result["frames_with_navigation_search"] = frames_with_navigation_search
	return result

func _make_bounded_path_world() -> VoxelWorld:
	var world := _make_flat_world()
	var wall: Dictionary = {}
	for z in range(-32, 33):
		wall[Vector3i(0, int(FEET_Y), z)] = BlockId.Type.STONE
		wall[Vector3i(0, int(FEET_Y) + 1, z)] = BlockId.Type.STONE
	world.restore_block_edits(wall, {})
	return world

func _run_path_search(world: VoxelWorld) -> VoxelPathResult:
	return VoxelPathfinder.find_path(
		world,
		Vector3i(-12, int(FEET_Y), 0),
		Vector3i(12, int(FEET_Y), 0),
		0.6,
		1.8,
		WorldEntityCoordinator.MAX_NAVIGATION_SEARCH_RADIUS,
		WorldEntityCoordinator.MAX_NAVIGATION_SEARCH_NODES
	)

func _benchmark_bounded_pathfinding() -> Dictionary:
	var world := _make_bounded_path_world()
	for _sample in range(PATH_WARMUP_SAMPLES):
		_run_path_search(world)
	var samples: Array[int] = []
	var bounded := true
	var exhausted_budget := true
	for _sample in range(PATH_SAMPLES):
		var started := Time.get_ticks_usec()
		var result := _run_path_search(world)
		samples.append(Time.get_ticks_usec() - started)
		bounded = bounded and result.status == VoxelPathResult.Status.LIMIT_REACHED and result.visited_nodes <= WorldEntityCoordinator.MAX_NAVIGATION_SEARCH_NODES
		exhausted_budget = exhausted_budget and result.visited_nodes == WorldEntityCoordinator.MAX_NAVIGATION_SEARCH_NODES
	_expect(bounded, "bounded path benchmark exceeded its deterministic search contract")
	_expect(exhausted_budget, "bounded path benchmark did not exercise the full node budget")
	var summary := PerformanceSampleStats.summarize(samples)
	summary["max_search_nodes"] = WorldEntityCoordinator.MAX_NAVIGATION_SEARCH_NODES
	return summary

func _output_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			return argument.trim_prefix("--output=")
	return ""

func _write_report(report_json: String) -> void:
	var path := _output_path()
	if path.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "could not write benchmark report to %s" % path)
	if file != null:
		file.store_line(report_json)

func _run() -> void:
	var orphan_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	_expect(catalog != null and catalog.validate(), "entity catalog failed validation")
	var world := _make_flat_world()
	var coordinator := WorldEntityCoordinator.new()
	get_root().add_child(coordinator)
	coordinator.setup(catalog, world, WORLD_SEED, _position_ready)
	coordinator.get_runtime().entity_melee_contact_reached.connect(_consume_melee_contact)
	var origin := Vector3(0.5, FEET_Y, 0.5)
	var spawn_metrics := _spawn_population(coordinator, origin)
	var actors := _sorted_actors(coordinator)
	_expect(actors.size() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "benchmark did not create twelve actors")
	_arrange_population(coordinator, actors)
	var frame_metrics := _benchmark_entity_frames(coordinator, actors)
	var path_metrics := _benchmark_bounded_pathfinding()
	var spatial_index := coordinator.get_runtime()._spatial_index as EntitySpatialIndex
	_expect(spatial_index.get_entry_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "spatial index lost an active actor")
	_expect(spatial_index.get_cell_count() <= WorldEntityCoordinator.MAX_TOTAL_ACTIVE * 8, "spatial index exceeded its population bound")
	coordinator.shutdown()
	coordinator.queue_free()
	actors.clear()
	await process_frame
	await process_frame
	await process_frame
	var orphan_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_after == orphan_before, "benchmark changed orphan count from %d to %d" % [orphan_before, orphan_after])
	var report := {
		"schema_version": 2,
		"benchmark_id": "entity_efficiency",
		"environment": {
			"godot": str(Engine.get_version_info().get("string", "unknown")),
			"os": OS.get_name(),
			"processor_count": OS.get_processor_count(),
		},
		"workload": {
			"seed": WORLD_SEED,
			"active_entities": WorldEntityCoordinator.MAX_TOTAL_ACTIVE,
			"warmup_frames": WARMUP_FRAMES,
			"sample_frames": SAMPLE_FRAMES,
			"path_warmup_samples": PATH_WARMUP_SAMPLES,
			"path_samples": PATH_SAMPLES,
		},
		"metrics": {
			"entity_frame": frame_metrics,
			"bounded_path_search": path_metrics,
			"spawn_frame": spawn_metrics["spawn_frame"],
			"preparation_frame": spawn_metrics["preparation_frame"],
		},
		"orphan_before": orphan_before,
		"orphan_after": orphan_after,
	}
	var report_json := JSON.stringify(report)
	print("ENTITY_EFFICIENCY RESULT %s" % report_json)
	_write_report(report_json)
	if _failures == 0:
		print("ENTITY_EFFICIENCY PASS")
		quit(0)
	else:
		print("ENTITY_EFFICIENCY FAIL failures=%d" % _failures)
		quit(1)
