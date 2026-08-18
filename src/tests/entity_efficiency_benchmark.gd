extends SceneTree

const PerformanceSampleStats = preload("res://tests/performance_sample_stats.gd")
const PerformanceEntityTarget = preload("res://tests/performance_entity_target.gd")

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
const EXPECTED_SHEEP_COUNT: int = 6
const EXPECTED_ZOMBIE_COUNT: int = 2
const EXPECTED_SKELETON_COUNT: int = 2
const EXPECTED_BIRD_COUNT: int = 4
const EXPECTED_STONE_GOLEM_COUNT: int = 2

const FIXED_TARGET_FRAMES: int = 360
const ENTITY_FRAME_P95_LIMIT_MS: float = 75.0
const ENTITY_FRAME_P99_LIMIT_MS: float = 125.0

var _stone_golem_runtime_ids: Array[int] = []
var _stone_golem_initial_positions: Dictionary = {}
var _stone_golem_chase_seen: Dictionary = {}
var _stone_golem_path_seen: Dictionary = {}
var _stone_golem_airborne_seen: Dictionary = {}
var _stone_golem_recovery_seen: Dictionary = {}
var _stone_golem_max_displacement: Dictionary = {}
var _stone_golem_radial_contacts: Dictionary = {}
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

func _consume_radial_contact(source_runtime_id: int, profile: MeleeAttackProfile) -> void:
	if profile.id != &"stone_golem_slam" or not _stone_golem_radial_contacts.has(source_runtime_id):
		return
	_stone_golem_radial_contacts[source_runtime_id] = int(_stone_golem_radial_contacts[source_runtime_id]) + 1

func _spawn_population(coordinator: WorldEntityCoordinator, player_position: Vector3) -> Dictionary:
	var spawn_samples: Array[int] = []
	var preparation_samples: Array[int] = []
	for cycle in range(WorldEntityCoordinator.MAX_TOTAL_ACTIVE):
		var time_of_day := NIGHT_TIME if cycle < 6 else DAY_TIME
		var before_count := coordinator.get_runtime().get_active_count()
		coordinator._spawn_elapsed = WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS - FRAME_DELTA
		var spawn_started := Time.get_ticks_usec()
		coordinator.tick(FRAME_DELTA, PerformanceEntityTarget.create(player_position), time_of_day)
		spawn_samples.append(Time.get_ticks_usec() - spawn_started)
		_expect(coordinator.get_runtime().get_active_count() == before_count + 1, "spawn cycle %d did not add one actor" % cycle)
		var prepared_before := coordinator.get_runtime()._prepared_actor_count()
		var preparation_started := Time.get_ticks_usec()
		coordinator.tick(FRAME_DELTA, PerformanceEntityTarget.create(player_position), time_of_day)
		var preparation_usec := Time.get_ticks_usec() - preparation_started
		if coordinator.get_runtime()._prepared_actor_count() > prepared_before:
			preparation_samples.append(preparation_usec)
	_expect(spawn_samples.size() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "spawn benchmark did not collect one sample per active slot")
	_expect(not preparation_samples.is_empty(), "spawn benchmark did not observe actor preparation")
	return {
		"spawn_frame": PerformanceSampleStats.summarize(spawn_samples),
		"preparation_frame": PerformanceSampleStats.summarize(preparation_samples),
	}

func _sorted_actors(coordinator: WorldEntityCoordinator) -> Array[EntityActor]:
	var actors := coordinator.get_runtime().get_active_actors()
	actors.sort_custom(func(left: EntityActor, right: EntityActor) -> bool: return left.runtime_id < right.runtime_id)
	return actors

func _arrange_population(coordinator: WorldEntityCoordinator, actors: Array[EntityActor]) -> Dictionary:
	var zombie_index := 0
	var sheep_index := 0
	var skeleton_index := 0
	var bird_index := 0
	var stone_golem_index := 0
	for actor in actors:
		var angle: float
		var radius: float
		var height := FEET_Y
		match actor.definition.id:
			&"zombie":
				angle = TAU * float(zombie_index) / float(EXPECTED_ZOMBIE_COUNT)
				radius = 8.0
				zombie_index += 1
				var zombie := actor as ZombieActor
				_expect(zombie != null, "zombie definition did not instantiate a ZombieActor")
				if zombie != null:
					zombie._path_follower.request_repath()
			&"skeleton":
				angle = TAU * float(skeleton_index) / float(EXPECTED_SKELETON_COUNT) + PI / 3.0
				radius = 11.0
				skeleton_index += 1
				var skeleton := actor as SkeletonActor
				_expect(skeleton != null, "skeleton definition did not instantiate a SkeletonActor")
				if skeleton != null:
					skeleton._path_follower.request_repath()
			&"stone_golem":
				angle = TAU * float(stone_golem_index) / float(EXPECTED_STONE_GOLEM_COUNT) + PI / 2.0
				radius = 8.0
				stone_golem_index += 1
				var stone_golem := actor as StoneGolemActor
				_expect(stone_golem != null, "stone_golem definition did not instantiate a StoneGolemActor")
				if stone_golem != null:
					stone_golem._path_follower.request_repath()
			&"sheep":
				angle = TAU * float(sheep_index) / float(EXPECTED_SHEEP_COUNT) + PI / 6.0
				radius = 17.0
				sheep_index += 1
				var sheep := actor as SheepActor
				_expect(sheep != null, "sheep definition did not instantiate a SheepActor")
				if sheep != null:
					sheep._path_follower.request_repath()
			&"bird":
				angle = TAU * float(bird_index) / float(EXPECTED_BIRD_COUNT) + PI / 4.0
				radius = 20.0
				height += 10.0
				bird_index += 1
				_expect(actor is BirdActor, "bird definition did not instantiate a BirdActor")
			_:
				_expect(false, "benchmark population contained unsupported entity %s" % actor.definition.id)
				continue
		actor.global_position = Vector3(0.5 + cos(angle) * radius, height, 0.5 + sin(angle) * radius)
		actor.velocity = Vector3.ZERO
		actor.on_ground = actor.definition.id != &"bird"
		coordinator.get_runtime()._spatial_index.upsert(actor.runtime_id, actor.global_position, actor.get_world_bounds())
		if actor is StoneGolemActor:
			_register_stone_golem(actor as StoneGolemActor)
	_expect(zombie_index == EXPECTED_ZOMBIE_COUNT, "benchmark population had %d zombies" % zombie_index)
	_expect(sheep_index == EXPECTED_SHEEP_COUNT, "benchmark population had %d sheep" % sheep_index)
	_expect(skeleton_index == EXPECTED_SKELETON_COUNT, "benchmark population had %d skeletons" % skeleton_index)
	_expect(bird_index == EXPECTED_BIRD_COUNT, "benchmark population had %d birds" % bird_index)
	_expect(stone_golem_index == EXPECTED_STONE_GOLEM_COUNT, "benchmark population had %d Stone Golems" % stone_golem_index)
	return {
		"sheep": sheep_index,
		"zombie": zombie_index,
		"skeleton": skeleton_index,
		"bird": bird_index,
		"stone_golem": stone_golem_index,
	}

func _register_stone_golem(actor: StoneGolemActor) -> void:
	var runtime_id := actor.runtime_id
	_stone_golem_runtime_ids.append(runtime_id)
	_stone_golem_initial_positions[runtime_id] = actor.global_position
	_stone_golem_chase_seen[runtime_id] = false
	_stone_golem_path_seen[runtime_id] = false
	_stone_golem_airborne_seen[runtime_id] = false
	_stone_golem_recovery_seen[runtime_id] = false
	_stone_golem_max_displacement[runtime_id] = 0.0
	_stone_golem_radial_contacts[runtime_id] = 0

func _record_stone_golem_activity(actors: Array[EntityActor]) -> void:
	for actor in actors:
		if not _stone_golem_initial_positions.has(actor.runtime_id):
			continue
		var stone_golem := actor as StoneGolemActor
		var runtime_id := actor.runtime_id
		if stone_golem.brain.state == StoneGolemBrain.State.CHASE:
			_stone_golem_chase_seen[runtime_id] = true
			if not stone_golem._path_follower._path.is_empty():
				_stone_golem_path_seen[runtime_id] = true
		elif stone_golem.brain.state == StoneGolemBrain.State.SLAM_AIRBORNE:
			_stone_golem_airborne_seen[runtime_id] = true
		elif stone_golem.brain.state == StoneGolemBrain.State.SLAM_RECOVERY:
			_stone_golem_recovery_seen[runtime_id] = true
		var offset := actor.global_position - (_stone_golem_initial_positions[runtime_id] as Vector3)
		offset.y = 0.0
		var maximum := float(_stone_golem_max_displacement[runtime_id])
		_stone_golem_max_displacement[runtime_id] = maxf(maximum, offset.length())

func _assert_stone_golem_workload() -> Dictionary:
	_expect(_stone_golem_runtime_ids.size() == EXPECTED_STONE_GOLEM_COUNT, "active workload did not register two Stone Golems")
	var actors_with_paths := 0
	var radial_contacts := 0
	for runtime_id in _stone_golem_runtime_ids:
		_expect(bool(_stone_golem_chase_seen[runtime_id]), "Stone Golem %d never entered pursuit" % runtime_id)
		_expect(bool(_stone_golem_path_seen[runtime_id]), "Stone Golem %d never acquired a path" % runtime_id)
		_expect(bool(_stone_golem_airborne_seen[runtime_id]), "Stone Golem %d never became airborne" % runtime_id)
		_expect(bool(_stone_golem_recovery_seen[runtime_id]), "Stone Golem %d never entered slam recovery" % runtime_id)
		_expect(float(_stone_golem_max_displacement[runtime_id]) >= 1.0, "Stone Golem %d moved less than one block" % runtime_id)
		var contact_count := int(_stone_golem_radial_contacts[runtime_id])
		_expect(contact_count > 0, "Stone Golem %d emitted no radial contact" % runtime_id)
		actors_with_paths += int(bool(_stone_golem_path_seen[runtime_id]))
		radial_contacts += contact_count
	return {
		"actor_count": _stone_golem_runtime_ids.size(),
		"actors_with_paths": actors_with_paths,
		"radial_contacts": radial_contacts,
	}

func _player_position(frame_index: int) -> Vector3:
	if frame_index < FIXED_TARGET_FRAMES:
		return Vector3(0.5, FEET_Y, 0.5)
	var angle := float(frame_index - FIXED_TARGET_FRAMES) * 0.015
	return Vector3(0.5 + cos(angle) * 3.0, FEET_Y, 0.5 + sin(angle) * 3.0)

func _advance_entity_frame(coordinator: WorldEntityCoordinator, actors: Array[EntityActor], frame_index: int) -> int:
	var player_position := _player_position(frame_index)
	coordinator.tick(FRAME_DELTA, PerformanceEntityTarget.create(player_position), DAY_TIME)
	for actor in actors:
		actor.animation_driver.advance(FRAME_DELTA)
	_record_stone_golem_activity(actors)
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
	_expect(coordinator.get_runtime().get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "entity frame benchmark did not retain the full population")
	var result := PerformanceSampleStats.summarize(samples)
	result["max_navigation_searches_per_frame"] = max_navigation_searches
	result["frames_with_navigation_search"] = frames_with_navigation_search
	_expect(float(result["p95_ms"]) <= ENTITY_FRAME_P95_LIMIT_MS, "entity frame p95 %.3f ms exceeded %.1f ms" % [float(result["p95_ms"]), ENTITY_FRAME_P95_LIMIT_MS])
	_expect(float(result["p99_ms"]) <= ENTITY_FRAME_P99_LIMIT_MS, "entity frame p99 %.3f ms exceeded %.1f ms" % [float(result["p99_ms"]), ENTITY_FRAME_P99_LIMIT_MS])
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
	coordinator.get_runtime().entity_radial_contact_reached.connect(_consume_radial_contact)
	var origin := Vector3(0.5, FEET_Y, 0.5)
	var spawn_metrics := _spawn_population(coordinator, origin)
	var actors := _sorted_actors(coordinator)
	_expect(actors.size() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "benchmark did not create the full population")
	var species_counts := _arrange_population(coordinator, actors)
	var frame_metrics := _benchmark_entity_frames(coordinator, actors)
	var stone_golem_metrics := _assert_stone_golem_workload()
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
			"species_counts": species_counts,
			"warmup_frames": WARMUP_FRAMES,
			"sample_frames": SAMPLE_FRAMES,
			"fixed_target_frames": FIXED_TARGET_FRAMES,
			"path_warmup_samples": PATH_WARMUP_SAMPLES,
			"path_samples": PATH_SAMPLES,
		},
		"metrics": {
			"entity_frame": frame_metrics,
			"stone_golem": stone_golem_metrics,
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
