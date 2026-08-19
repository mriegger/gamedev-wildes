extends Node
class_name ChunkBuildScheduler

const WORKER_COUNT: int = 2

var _mesher: ChunkMesher
var _foliage_mesher: FoliageMesher
var _terrain_generator: TerrainGenerator
var _voxel_model: VoxelWorld
var _chunk_size: int
var _max_build_y: int

var _state_mutex := Mutex.new()
var _pending_generations: Dictionary = {}
var _pending_terrain_only: Dictionary = {}
var _next_generation: int = 0

var _job_mutex := Mutex.new()
var _job_available := Semaphore.new()
var _job_queue: Array[ChunkBuildJob] = []
var _mesh_result_mutex := Mutex.new()
var _mesh_results: Array[ChunkBuildResult] = []
var _terrain_result_mutex := Mutex.new()
var _terrain_results: Array[ChunkBuildResult] = []

var _workers: Array[Thread] = []
var _workers_started: bool = false
var _stopped: bool = false
var _suspend_mutex := Mutex.new()
var _resume_available := Semaphore.new()
var _suspended: bool = false
var _resume_waiter_count: int = 0

func setup(p_mesher: ChunkMesher, p_foliage_mesher: FoliageMesher, p_terrain_generator: TerrainGenerator, p_voxel_model: VoxelWorld, p_chunk_size: int, p_max_build_y: int):
	_mesher = p_mesher
	_foliage_mesher = p_foliage_mesher
	_terrain_generator = p_terrain_generator
	_voxel_model = p_voxel_model
	_chunk_size = p_chunk_size
	_max_build_y = p_max_build_y
	_reset_queues()
	_stopped = false
	_suspend_mutex.lock()
	_suspended = false
	_resume_waiter_count = 0
	_suspend_mutex.unlock()

func _exit_tree():
	shutdown()

func queue_mesh(coord: Vector2i) -> bool:
	return _queue_build(coord, false, false)

func replace_mesh(coord: Vector2i) -> bool:
	return _queue_build(coord, false, true)

func queue_terrain(coord: Vector2i) -> bool:
	return _queue_build(coord, true, false)

func build_now(coord: Vector2i) -> ChunkBuildResult:
	cancel(coord)
	return _build(_create_job(coord, 0, false))

func take_completed(max_mesh_results: int, max_terrain_results: int) -> Array[ChunkBuildResult]:
	var completed: Array[ChunkBuildResult] = []
	var mesh_count := 0
	while mesh_count < max_mesh_results:
		var result := _pop_mesh_result()
		if result == null:
			break
		if _consume_if_current(result):
			completed.append(result)
			mesh_count += 1
	var terrain_count := 0
	while terrain_count < max_terrain_results:
		var result := _pop_terrain_result()
		if result == null:
			break
		if _consume_if_current(result):
			completed.append(result)
			terrain_count += 1
	return completed

func pending_count() -> int:
	_state_mutex.lock()
	var count := _pending_generations.size()
	_state_mutex.unlock()
	return count

func suspend():
	_suspend_mutex.lock()
	_suspended = true
	_suspend_mutex.unlock()

func resume():
	_suspend_mutex.lock()
	if not _suspended:
		_suspend_mutex.unlock()
		return
	_suspended = false
	var waiter_count := _resume_waiter_count
	_suspend_mutex.unlock()
	for _index in waiter_count:
		_resume_available.post()

func cancel(coord: Vector2i):
	_state_mutex.lock()
	_pending_generations.erase(coord)
	_pending_terrain_only.erase(coord)
	_state_mutex.unlock()
	_job_mutex.lock()
	var retained: Array[ChunkBuildJob] = []
	for job in _job_queue:
		if job.coord != coord:
			retained.append(job)
	_job_queue = retained
	_job_mutex.unlock()

func shutdown():
	_stop_workers()
	_reset_queues()

func _queue_build(coord: Vector2i, terrain_only: bool, replace_existing: bool) -> bool:
	if _stopped:
		return false
	_state_mutex.lock()
	var already_pending := _pending_generations.has(coord)
	var pending_terrain := _pending_terrain_only.has(coord)
	if already_pending and not replace_existing and (terrain_only or not pending_terrain):
		_state_mutex.unlock()
		return false
	_next_generation += 1
	var generation := _next_generation
	_pending_generations[coord] = generation
	if terrain_only:
		_pending_terrain_only[coord] = true
	else:
		_pending_terrain_only.erase(coord)
	_state_mutex.unlock()
	if already_pending:
		_drop_queued_jobs(coord)
	var job := _create_job(coord, generation, terrain_only)
	_ensure_workers()
	if _workers.is_empty():
		_push_result(_build(job))
		return true
	_job_mutex.lock()
	_job_queue.append(job)
	_job_mutex.unlock()
	_job_available.post()
	return true

func _create_job(coord: Vector2i, generation: int, terrain_only: bool) -> ChunkBuildJob:
	var origin_x := coord.x * _chunk_size
	var origin_z := coord.y * _chunk_size
	var edits := _voxel_model.snapshot_edits_for_chunk(origin_x, origin_z)
	return ChunkBuildJob.new(
		coord,
		generation,
		terrain_only,
		edits.get("placed", {}) as Dictionary,
		edits.get("removed", {}) as Dictionary,
		edits.get("foliage_clearance", {}) as Dictionary,
		edits.get("trees", {}) as Dictionary,
		edits.get("copper", {}) as Dictionary,
		not terrain_only and not _voxel_model.generated_copper_chunks.has(coord)
	)

func _ensure_workers():
	if _workers_started or _stopped:
		return
	_workers_started = true
	for index in range(WORKER_COUNT):
		var worker := Thread.new()
		var error := worker.start(_worker_loop, Thread.PRIORITY_LOW)
		if error == OK:
			_workers.append(worker)
		else:
			push_warning("[ChunkBuildScheduler] Failed to start worker %d" % index)

func _worker_loop():
	while true:
		_job_available.wait()
		if not _wait_until_resumed():
			_terrain_generator.release_thread_caches(OS.get_thread_caller_id())
			return
		var job := _pop_job()
		if job == null:
			continue
		if not _is_current(job.coord, job.generation):
			continue
		var result := _build(job)
		if result == null:
			continue
		if not _is_current(job.coord, job.generation):
			continue
		_push_result(result)

func _wait_until_resumed() -> bool:
	while true:
		_suspend_mutex.lock()
		if _stopped:
			_suspend_mutex.unlock()
			return false
		if not _suspended:
			_suspend_mutex.unlock()
			return true
		_resume_waiter_count += 1
		_suspend_mutex.unlock()
		_resume_available.wait()
		_suspend_mutex.lock()
		_resume_waiter_count -= 1
		_suspend_mutex.unlock()
	return false

func _push_result(result: ChunkBuildResult):
	if result.terrain_only:
		_terrain_result_mutex.lock()
		_terrain_results.append(result)
		_terrain_result_mutex.unlock()
	else:
		_mesh_result_mutex.lock()
		_mesh_results.append(result)
		_mesh_result_mutex.unlock()

func _pop_job() -> ChunkBuildJob:
	_job_mutex.lock()
	var job: ChunkBuildJob = null
	if not _job_queue.is_empty():
		job = _job_queue.pop_front()
	_job_mutex.unlock()
	return job

func _build(job: ChunkBuildJob) -> ChunkBuildResult:
	var origin_x := job.coord.x * _chunk_size
	var origin_z := job.coord.y * _chunk_size
	var payload := _terrain_generator.build_cache_with_generation(
		origin_x,
		origin_z,
		_chunk_size,
		_max_build_y,
		job.placed_blocks,
		job.removed_blocks,
		job.tree_blocks,
		job.terrain_only,
		job.copper_blocks,
		job.generate_copper,
		job.foliage_clearance
	)
	if job.generation != 0 and not _is_current(job.coord, job.generation):
		return null
	var terrain_data: Variant = null
	var water_data: Variant = null
	var foliage_data: Variant = null
	if not job.terrain_only:
		var cache := payload["cache_dict"] as Dictionary
		foliage_data = _foliage_mesher.build_mesh_data(cache["foliage_cells"] as PackedInt32Array)
		payload.erase("cache_dict")
		var mesh_data := _mesher.build_combined_mesh_data(cache)
		terrain_data = mesh_data["terrain"]
		water_data = mesh_data["water"]
	return ChunkBuildResult.new(job.coord, job.generation, job.terrain_only, payload, terrain_data, water_data, foliage_data)

func _is_current(coord: Vector2i, generation: int) -> bool:
	_state_mutex.lock()
	var current: bool = _pending_generations.get(coord, -1) == generation
	_state_mutex.unlock()
	return current

func _consume_if_current(result: ChunkBuildResult) -> bool:
	_state_mutex.lock()
	var current: bool = _pending_generations.get(result.coord, -1) == result.generation
	if current:
		_pending_generations.erase(result.coord)
		_pending_terrain_only.erase(result.coord)
	_state_mutex.unlock()
	return current

func _pop_mesh_result() -> ChunkBuildResult:
	_mesh_result_mutex.lock()
	var result: ChunkBuildResult = null
	if not _mesh_results.is_empty():
		result = _mesh_results.pop_front()
	_mesh_result_mutex.unlock()
	return result

func _pop_terrain_result() -> ChunkBuildResult:
	_terrain_result_mutex.lock()
	var result: ChunkBuildResult = null
	if not _terrain_results.is_empty():
		result = _terrain_results.pop_front()
	_terrain_result_mutex.unlock()
	return result

func _drop_queued_jobs(coord: Vector2i):
	_job_mutex.lock()
	var retained: Array[ChunkBuildJob] = []
	for job in _job_queue:
		if job.coord != coord:
			retained.append(job)
	_job_queue = retained
	_job_mutex.unlock()

func _stop_workers():
	_suspend_mutex.lock()
	_stopped = true
	_suspended = false
	var resume_waiter_count := _resume_waiter_count
	_suspend_mutex.unlock()
	_job_mutex.lock()
	_job_queue.clear()
	_job_mutex.unlock()
	for _worker in _workers:
		_job_available.post()
	for _index in resume_waiter_count:
		_resume_available.post()
	for worker in _workers:
		if worker.is_started():
			worker.wait_to_finish()
	_workers.clear()
	_workers_started = false

func _reset_queues():
	_state_mutex.lock()
	_pending_generations.clear()
	_pending_terrain_only.clear()
	_state_mutex.unlock()
	_job_mutex.lock()
	_job_queue.clear()
	_job_mutex.unlock()
	_mesh_result_mutex.lock()
	_mesh_results.clear()
	_mesh_result_mutex.unlock()
	_terrain_result_mutex.lock()
	_terrain_results.clear()
	_terrain_result_mutex.unlock()
