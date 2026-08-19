extends SceneTree

const PerformanceSampleStats = preload("res://tests/performance_sample_stats.gd")
const PerformanceEntityTarget = preload("res://tests/performance_entity_target.gd")

const WORLD_SEED: int = 1337
const TARGET_FPS: int = 120
const FRAME_DELTA: float = 1.0 / 60.0
const DAY_TIME: float = 12.0
const NIGHT_TIME: float = 20.0
const STEADY_WARMUP_FRAMES: int = 300
const STEADY_SAMPLE_FRAMES: int = 1200
const STREAMING_WARMUP_FRAMES: int = 300
const STREAMING_SAMPLE_FRAMES: int = 1200
const CHUNK_BUILD_SAMPLES: int = 64
const CHUNK_APPLY_SAMPLES: int = 128
const SESSION_TIMEOUT_FRAMES: int = 1200
const QUEUE_DRAIN_TIMEOUT_FRAMES: int = 3600
const POPULATION_ATTEMPT_LIMIT: int = 96

class FrameRecorder:
	extends RefCounted

	var enabled: bool = false
	var samples_usec: Array[int] = []
	var _process_started_usec: int = 0
	var _physics_started_usec: int = 0
	var _pending_physics_usec: int = 0

	func start_capture() -> void:
		samples_usec.clear()
		_process_started_usec = 0
		_physics_started_usec = 0
		_pending_physics_usec = 0
		enabled = true

	func stop_capture() -> void:
		enabled = false
		_process_started_usec = 0
		_physics_started_usec = 0
		_pending_physics_usec = 0

	func begin_process() -> void:
		if enabled:
			_process_started_usec = Time.get_ticks_usec()

	func end_process() -> void:
		if not enabled or _process_started_usec == 0:
			return
		var process_usec := Time.get_ticks_usec() - _process_started_usec
		samples_usec.append(process_usec + _pending_physics_usec)
		_process_started_usec = 0
		_pending_physics_usec = 0

	func begin_physics() -> void:
		if enabled:
			_physics_started_usec = Time.get_ticks_usec()

	func end_physics() -> void:
		if not enabled or _physics_started_usec == 0:
			return
		_pending_physics_usec += Time.get_ticks_usec() - _physics_started_usec
		_physics_started_usec = 0

class FrameStartProbe:
	extends Node

	const PRIORITY: int = -1000000

	var recorder: FrameRecorder

	func _init(p_recorder: FrameRecorder) -> void:
		recorder = p_recorder
		process_priority = PRIORITY
		process_physics_priority = PRIORITY

	func _process(_delta: float) -> void:
		recorder.begin_process()

	func _physics_process(_delta: float) -> void:
		recorder.begin_physics()

class FrameEndProbe:
	extends Node

	const PRIORITY: int = 1000000

	var recorder: FrameRecorder

	func _init(p_recorder: FrameRecorder) -> void:
		recorder = p_recorder
		process_priority = PRIORITY
		process_physics_priority = PRIORITY

	func _process(_delta: float) -> void:
		recorder.end_process()

	func _physics_process(_delta: float) -> void:
		recorder.end_physics()

var _failures: int = 0
var _session_ready: bool = false

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[game_performance] FAIL: %s" % message)

func _make_saved_world() -> Dictionary:
	return {
		"version": SaveManager.CURRENT_SAVE_VERSION,
		"world_name": "Performance Benchmark",
		"playtime_seconds": 0.0,
		"seed": WORLD_SEED,
		"time_of_day": DAY_TIME,
		"player_position": null,
		"player_perks": {"allocations": {}},
		"item_proficiency": {},
		"inventory": null,
		"next_equipment_instance_id": 1,
		"chests": {},
		"world_loot": {"next_entry_id": 1, "entries": []},
		"placed_blocks": {},
		"removed_blocks": {},
		"torch_attachments": {},
	}

func _streaming_queue_depth(world: WorldController) -> int:
	var manager := world.chunk_manager
	return (
		world.chunk_scheduler.pending_count()
		+ manager._data_load_queue.size()
		+ manager._mesh_load_queue.size()
		+ manager._data_unload_queue.size()
		+ manager._dirty_chunks.size()
		+ manager._requested_meshes.size()
		+ manager._requested_terrain.size()
		+ manager._rebuilding_meshes.size()
	)

func _streaming_queues_are_drained(world: WorldController) -> bool:
	var manager := world.chunk_manager
	return _streaming_queue_depth(world) == 0 and manager._initial_load_queue.is_empty()

func _wait_for_streaming_drain(world: WorldController, max_frames: int) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var frames := 0
	while not _streaming_queues_are_drained(world) and frames < max_frames:
		frames += 1
		await process_frame
	return {
		"drained": _streaming_queues_are_drained(world),
		"frames": frames,
		"elapsed_usec": Time.get_ticks_usec() - started_usec,
	}

func _advance_frames(frame_count: int) -> void:
	for _frame in range(frame_count):
		await process_frame

func _force_steady_population(game: Game, player_position: Vector3) -> int:
	var coordinator := game.world_entity_coordinator
	var attempts := 0
	while coordinator.get_runtime().get_active_count() < WorldEntityCoordinator.MAX_TOTAL_ACTIVE and attempts < POPULATION_ATTEMPT_LIMIT:
		var time_of_day := DAY_TIME if attempts % 2 == 0 else NIGHT_TIME
		coordinator._spawn_elapsed = WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS - FRAME_DELTA
		coordinator.tick(FRAME_DELTA, PerformanceEntityTarget.create(player_position), time_of_day)
		coordinator.tick(FRAME_DELTA, PerformanceEntityTarget.create(player_position), time_of_day)
		attempts += 1
	return attempts

func _capture_steady_frames(game: Game, recorder: FrameRecorder) -> Array[int]:
	await _advance_frames(STEADY_WARMUP_FRAMES)
	_expect(game.world_entity_coordinator.get_runtime().get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "steady warmup did not retain twelve actors")
	recorder.start_capture()
	await _advance_frames(STEADY_SAMPLE_FRAMES)
	recorder.stop_capture()
	_expect(game.world_entity_coordinator.get_runtime().get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "steady sample did not retain twelve actors")
	return recorder.samples_usec.duplicate()

func _streaming_position(world: WorldController, origin: Vector3, frame_index: int) -> Vector3:
	var span := float(world.config.chunk_size * (world.config.render_distance + world.config.unload_padding + 4))
	var distance := fmod(float(frame_index) * 1.25, span * 4.0)
	var offset: Vector2
	if distance < span:
		offset = Vector2(distance, 0.0)
	elif distance < span * 2.0:
		offset = Vector2(span, distance - span)
	elif distance < span * 3.0:
		offset = Vector2(span * 3.0 - distance, span)
	else:
		offset = Vector2(0.0, span * 4.0 - distance)
	return Vector3(origin.x + offset.x, maxf(origin.y + 10.0, 24.0), origin.z + offset.y)

func _place_player(player: PlayerMotor, position: Vector3) -> void:
	player.global_position = position
	player.velocity = Vector3.ZERO
	player.ground_y = position.y
	player.on_ground = true

func _run_streaming_route(game: Game, frame_offset: int, frame_count: int, origin: Vector3) -> Dictionary:
	var world := game.world
	var player := game.player
	var previous_chunk := ChunkCoord.world_to_chunk(player.global_position, world.config.chunk_size)
	var chunk_transitions := 0
	var queue_activity_frames := 0
	var max_queue_depth := 0
	var max_data_chunks := world.chunk_manager.data_chunks.size()
	var max_visible_chunks := world.chunk_manager.visible_chunks.size()
	for frame_index in range(frame_offset, frame_offset + frame_count):
		_place_player(player, _streaming_position(world, origin, frame_index))
		await process_frame
		var current_chunk := ChunkCoord.world_to_chunk(player.global_position, world.config.chunk_size)
		if current_chunk != previous_chunk:
			chunk_transitions += 1
			previous_chunk = current_chunk
		var queue_depth := _streaming_queue_depth(world)
		max_queue_depth = maxi(max_queue_depth, queue_depth)
		max_data_chunks = maxi(max_data_chunks, world.chunk_manager.data_chunks.size())
		max_visible_chunks = maxi(max_visible_chunks, world.chunk_manager.visible_chunks.size())
		if queue_depth > 0:
			queue_activity_frames += 1
	return {
		"chunk_transitions": chunk_transitions,
		"queue_activity_frames": queue_activity_frames,
		"max_queue_depth": max_queue_depth,
		"max_data_chunks": max_data_chunks,
		"max_visible_chunks": max_visible_chunks,
	}

func _capture_streaming_frames(game: Game, recorder: FrameRecorder, origin: Vector3) -> Dictionary:
	await _run_streaming_route(game, 0, STREAMING_WARMUP_FRAMES, origin)
	recorder.start_capture()
	var activity := await _run_streaming_route(game, STREAMING_WARMUP_FRAMES, STREAMING_SAMPLE_FRAMES, origin)
	recorder.stop_capture()
	activity["samples_usec"] = recorder.samples_usec.duplicate()
	return activity

func _validate_streaming_activity(world: WorldController, activity: Dictionary) -> void:
	var keep_distance := world.config.render_distance + world.config.unload_padding
	var keep_area := (keep_distance * 2 + 1) * (keep_distance * 2 + 1)
	var visible_area := (world.config.render_distance * 2 + 1) * (world.config.render_distance * 2 + 1)
	var queue_limit := (keep_area + visible_area) * 4
	_expect(int(activity["chunk_transitions"]) > 0, "streaming route crossed no chunk boundaries")
	_expect(int(activity["queue_activity_frames"]) > 0, "streaming route produced no queue activity")
	_expect(int(activity["max_queue_depth"]) > 0, "streaming route did not exercise the scheduler")
	_expect(int(activity["max_queue_depth"]) <= queue_limit, "streaming queue depth exceeded %d" % queue_limit)
	_expect(int(activity["max_data_chunks"]) <= keep_area + 40, "streaming data chunks exceeded their bound")
	_expect(int(activity["max_visible_chunks"]) <= visible_area + 10, "streaming visible chunks exceeded their bound")

func _chunk_coordinates(world: WorldController) -> Array[Vector2i]:
	var coordinates: Array[Vector2i] = []
	var center := world.chunk_manager._last_player_chunk + Vector2i(32, -32)
	for index in range(CHUNK_BUILD_SAMPLES):
		coordinates.append(center + Vector2i(index % 8, floori(float(index) / 8.0)))
	return coordinates

func _benchmark_chunk_work(world: WorldController) -> Dictionary:
	world.chunk_scheduler.shutdown()
	_expect(world.chunk_scheduler._workers.is_empty() and not world.chunk_scheduler._workers_started, "chunk workers did not stop before synchronous sampling")
	var coordinates := _chunk_coordinates(world)
	var build_samples: Array[int] = []
	var results: Array[ChunkBuildResult] = []
	for coord in coordinates:
		var started_usec := Time.get_ticks_usec()
		var result := world.chunk_scheduler.build_now(coord)
		build_samples.append(Time.get_ticks_usec() - started_usec)
		_expect(result != null and not result.terrain_only, "synchronous chunk build failed for %s" % str(coord))
		if result != null:
			results.append(result)
	_expect(build_samples.size() == CHUNK_BUILD_SAMPLES, "chunk build benchmark collected %d samples" % build_samples.size())
	_expect(results.size() == CHUNK_BUILD_SAMPLES, "chunk build benchmark produced %d results" % results.size())
	_expect(world.chunk_scheduler.pending_count() == 0, "synchronous chunk build left scheduler work pending")
	var apply_samples: Array[int] = []
	if not results.is_empty():
		for index in range(CHUNK_APPLY_SAMPLES):
			var started_usec := Time.get_ticks_usec()
			world.chunk_renderer.apply_result(results[index % results.size()])
			apply_samples.append(Time.get_ticks_usec() - started_usec)
	_expect(apply_samples.size() == CHUNK_APPLY_SAMPLES, "chunk apply benchmark collected %d samples" % apply_samples.size())
	for coord in coordinates:
		world.chunk_renderer.unload(coord)
		world.chunk_renderer.invalidate_cache(coord)
		_expect(not world.chunk_renderer._terrain_instances.has(coord), "chunk apply cleanup retained terrain at %s" % str(coord))
		_expect(not world.chunk_renderer._water_instances.has(coord), "chunk apply cleanup retained water at %s" % str(coord))
	results.clear()
	_expect(_streaming_queues_are_drained(world), "chunk benchmark changed streaming queue state")
	return {
		"build_samples": build_samples,
		"apply_samples": apply_samples,
	}

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

func _teardown(game: Game, start_probe: FrameStartProbe = null, end_probe: FrameEndProbe = null, recorder: FrameRecorder = null) -> void:
	if recorder != null:
		recorder.stop_capture()
	if is_instance_valid(start_probe):
		start_probe.queue_free()
	if is_instance_valid(end_probe):
		end_probe.queue_free()
	if is_instance_valid(game):
		game._notification(game.NOTIFICATION_WM_CLOSE_REQUEST)
		game.queue_free()
	await create_timer(0.25).timeout
	await process_frame
	await process_frame

func _on_session_ready() -> void:
	_session_ready = true

func _run() -> void:
	var orphan_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var packed := load("res://game/game.tscn") as PackedScene
	_expect(packed != null, "game scene did not load")
	if packed == null:
		quit(1)
		return
	var game := packed.instantiate() as Game
	_expect(game != null, "game scene did not instantiate")
	if game == null:
		quit(1)
		return
	var settings := GameSettings.new()
	settings.frame_rate_limit = TARGET_FPS
	settings.ambient_volume = 0.0
	settings.birds_enabled = false
	settings.torch_shadow_count = 0
	game.configure_session(-1, _make_saved_world(), settings)
	game.session_ready.connect(_on_session_ready)
	var startup_started_usec := Time.get_ticks_usec()
	root.add_child(game)
	var startup_frames := 0
	while not _session_ready and startup_frames < SESSION_TIMEOUT_FRAMES:
		startup_frames += 1
		await process_frame
	var startup_usec := Time.get_ticks_usec() - startup_started_usec
	_expect(_session_ready, "game session did not become ready within %d frames" % SESSION_TIMEOUT_FRAMES)
	if not _session_ready:
		await _teardown(game)
		quit(1)
		return
	var world := game.world
	var player := game.player
	_expect(world != null and player != null, "game did not expose its world and player")
	_expect(world.voxel_model != null and world.chunk_manager != null, "world streaming systems were not initialized")
	var initial_drain := await _wait_for_streaming_drain(world, QUEUE_DRAIN_TIMEOUT_FRAMES)
	_expect(bool(initial_drain["drained"]), "initial streaming queues did not drain")
	if not bool(initial_drain["drained"]):
		await _teardown(game)
		quit(1)
		return
	var spawn := world.voxel_model.get_spawn_position()
	_place_player(player, spawn + Vector3(0.0, 1.0, 0.0))
	var population_attempts := _force_steady_population(game, player.global_position)
	_expect(game.world_entity_coordinator.get_runtime().get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "steady fixture did not create twelve actors")
	var recorder := FrameRecorder.new()
	var start_probe := FrameStartProbe.new(recorder)
	var end_probe := FrameEndProbe.new(recorder)
	root.add_child(start_probe)
	root.add_child(end_probe)
	var steady_samples := await _capture_steady_frames(game, recorder)
	_expect(steady_samples.size() == STEADY_SAMPLE_FRAMES, "steady frame benchmark collected %d samples" % steady_samples.size())
	var streaming := await _capture_streaming_frames(game, recorder, spawn)
	var streaming_samples := streaming["samples_usec"] as Array[int]
	_expect(streaming_samples.size() == STREAMING_SAMPLE_FRAMES, "streaming frame benchmark collected %d samples" % streaming_samples.size())
	_validate_streaming_activity(world, streaming)
	var final_drain := await _wait_for_streaming_drain(world, QUEUE_DRAIN_TIMEOUT_FRAMES)
	_expect(bool(final_drain["drained"]), "streaming queues did not drain after the route")
	_expect(not world.chunk_manager.visible_chunks.is_empty(), "streaming left no visible chunks")
	_expect(not world.chunk_manager.data_chunks.is_empty(), "streaming left no data chunks")
	var chunk_work := _benchmark_chunk_work(world) if bool(final_drain["drained"]) else {"build_samples": [], "apply_samples": []}
	var chunk_build_samples := chunk_work["build_samples"] as Array[int]
	var chunk_apply_samples := chunk_work["apply_samples"] as Array[int]
	await _teardown(game, start_probe, end_probe, recorder)
	var orphan_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_after == orphan_before, "benchmark changed orphan count from %d to %d" % [orphan_before, orphan_after])
	if steady_samples.is_empty() or streaming_samples.is_empty() or chunk_build_samples.is_empty() or chunk_apply_samples.is_empty():
		print("GAME_PERFORMANCE FAIL failures=%d" % maxi(_failures, 1))
		quit(1)
		return
	var startup_samples: Array[int] = [startup_usec]
	var drain_samples: Array[int] = [int(final_drain["elapsed_usec"])]
	var report := {
		"schema_version": 2,
		"benchmark_id": "game_performance",
		"environment": {
			"godot": str(Engine.get_version_info().get("string", "unknown")),
			"os": OS.get_name(),
			"processor_count": OS.get_processor_count(),
			"headless": DisplayServer.get_name() == "headless",
		},
		"workload": {
			"seed": WORLD_SEED,
			"target_fps": TARGET_FPS,
			"active_entities": WorldEntityCoordinator.MAX_TOTAL_ACTIVE,
			"steady_warmup_frames": STEADY_WARMUP_FRAMES,
			"steady_sample_frames": STEADY_SAMPLE_FRAMES,
			"streaming_warmup_frames": STREAMING_WARMUP_FRAMES,
			"streaming_sample_frames": STREAMING_SAMPLE_FRAMES,
			"streaming_route_step_world_units": 1.25,
			"chunk_build_samples": CHUNK_BUILD_SAMPLES,
			"chunk_apply_samples": CHUNK_APPLY_SAMPLES,
		},
		"observations": {
			"startup_frames": startup_frames,
			"steady_population_attempts": population_attempts,
			"steady_active_entities": WorldEntityCoordinator.MAX_TOTAL_ACTIVE,
			"streaming_chunk_transitions": int(streaming["chunk_transitions"]),
			"streaming_queue_activity_frames": int(streaming["queue_activity_frames"]),
			"streaming_max_queue_depth": int(streaming["max_queue_depth"]),
			"streaming_max_data_chunks": int(streaming["max_data_chunks"]),
			"streaming_max_visible_chunks": int(streaming["max_visible_chunks"]),
			"initial_queue_drain_frames": int(initial_drain["frames"]),
			"final_queue_drain_frames": int(final_drain["frames"]),
		},
		"metrics": {
			"steady_game_frame": PerformanceSampleStats.summarize(steady_samples),
			"streaming_game_frame": PerformanceSampleStats.summarize(streaming_samples),
			"chunk_build": PerformanceSampleStats.summarize(chunk_build_samples),
			"chunk_apply": PerformanceSampleStats.summarize(chunk_apply_samples),
			"startup": PerformanceSampleStats.summarize(startup_samples),
			"streaming_queue_drain": PerformanceSampleStats.summarize(drain_samples),
		},
		"orphan_before": orphan_before,
		"orphan_after": orphan_after,
	}
	var report_json := JSON.stringify(report)
	print("GAME_PERFORMANCE RESULT %s" % report_json)
	_write_report(report_json)
	if _failures == 0:
		print("GAME_PERFORMANCE PASS")
		quit(0)
	else:
		print("GAME_PERFORMANCE FAIL failures=%d" % _failures)
		quit(1)
