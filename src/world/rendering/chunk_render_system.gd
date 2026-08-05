extends RefCounted
class_name ChunkRenderSystem

var chunk_container: Node3D
var mesher: ChunkMesher
var terrain_material: Material
var water_material: Material
var voxel_model: VoxelWorld
var terrain_generator: TerrainGenerator

var chunk_size: int = 20
var max_build_y: int = 36
var seed_value: int = 1337

var chunk_instances: Dictionary = {}
var water_chunk_instances: Dictionary = {}
var dirty_chunks: Dictionary = {}
var max_per_frame: int = 1
var max_terrain_per_frame: int = 2

var _mutex: Mutex = Mutex.new()
var _async_pending: Dictionary = {}
var _job_gens: Dictionary = {}
var _cancelled: Dictionary = {}
var _queued_keys: Dictionary = {}
var _pending_terrain_only: Dictionary = {}
var _terrain_only_dirty: bool = false

var _mesh_cache: Dictionary = {}
var _mesh_cache_order: Array[String] = []
const MAX_MESH_CACHE: int = 200

const MAX_WORKERS: int = 4
var _workers: Array[Thread] = []
var _job_queue: Array[Dictionary] = []
var _job_mutex: Mutex = Mutex.new()
var _result_queue: Array[Dictionary] = []
var _result_mutex: Mutex = Mutex.new()
var _terrain_result_queue: Array[Dictionary] = []
var _terrain_result_mutex: Mutex = Mutex.new()
var _stop_workers: bool = false
var _workers_started: bool = false

var _terrain_pool: Array[MeshInstance3D] = []
var _water_pool: Array[MeshInstance3D] = []
var _pending_water: Dictionary = {}

func setup(p_container: Node3D, p_mesher: ChunkMesher, p_material: Material, p_chunk_size: int, p_max_y: int, p_seed: int, p_voxel_model: VoxelWorld):
	chunk_container = p_container
	mesher = p_mesher
	terrain_material = p_material
	chunk_size = p_chunk_size
	max_build_y = p_max_y
	seed_value = p_seed
	voxel_model = p_voxel_model
	if mesher == null:
		mesher = ChunkMesher.new(chunk_size, max_build_y, seed_value, true)
	_mutex = Mutex.new()
	_job_mutex = Mutex.new()
	_result_mutex = Mutex.new()
	_terrain_result_mutex = Mutex.new()
	_async_pending.clear()
	_job_gens.clear()
	_cancelled.clear()
	_queued_keys.clear()
	_pending_terrain_only.clear()
	_terrain_only_dirty = false
	_job_queue.clear()
	_result_queue.clear()
	_terrain_result_queue.clear()
	_workers.clear()
	_stop_workers = false
	_workers_started = false

func consume_terrain_dirty() -> bool:
	_mutex.lock()
	var v = _terrain_only_dirty
	_terrain_only_dirty = false
	_mutex.unlock()
	return v

func _clear_pending(key: String, gen: int = -1) -> void:
	_mutex.lock()
	if gen != -1:
		if _async_pending.get(key, -1) != gen:
			_mutex.unlock()
			return
		_async_pending.erase(key)
		_pending_terrain_only.erase(key)
	else:
		_async_pending.erase(key)
		_pending_terrain_only.erase(key)
	_queued_keys.erase(key)
	_cancelled.erase(key)
	_mutex.unlock()

func _should_skip_result(key: String, gen: int) -> bool:
	_mutex.lock()
	var cur_gen = _job_gens.get(key, gen)
	var is_stale = cur_gen != gen
	var was_cancelled = _cancelled.has(key)
	if is_stale:
		if _async_pending.get(key, -1) == gen:
			_async_pending.erase(key)
			_pending_terrain_only.erase(key)
			_queued_keys.erase(key)
			if was_cancelled:
				_cancelled.erase(key)
		_mutex.unlock()
		return true
	if was_cancelled:
		_cancelled.erase(key)
		_async_pending.erase(key)
		_pending_terrain_only.erase(key)
		_queued_keys.erase(key)
		_mutex.unlock()
		return true
	_async_pending.erase(key)
	_pending_terrain_only.erase(key)
	_queued_keys.erase(key)
	_mutex.unlock()
	return false

func set_terrain_generator(gen: TerrainGenerator):
	terrain_generator = gen

func set_water_material(mat: Material):
	water_material = mat
	for key in water_chunk_instances.keys():
		var mi = water_chunk_instances[key] as MeshInstance3D
		if mi and is_instance_valid(mi):
			mi.material_override = water_material

func clear():
	# restartable reset — not a final shutdown; _ensure_workers() will rearm workers on next rebuild, so caller must block stray ticks after clear during shutdown or rearm crashes on freed state
	_stop_workers = true
	_job_mutex.lock()
	_job_queue.clear()
	_job_mutex.unlock()
	for w in _workers:
		if w and w.is_started():
			w.wait_to_finish()
	_workers.clear()
	_workers_started = false
	_stop_workers = false

	_async_pending.clear()
	_job_gens.clear()
	_cancelled.clear()
	_queued_keys.clear()
	_pending_terrain_only.clear()
	_terrain_only_dirty = false
	_result_queue.clear()
	_terrain_result_queue.clear()
	_pending_water.clear()
	_mesh_cache.clear()
	_mesh_cache_order.clear()
	for key in chunk_instances.keys():
		var mi = chunk_instances[key]
		if mi and is_instance_valid(mi):
			mi.queue_free()
	chunk_instances.clear()
	for key in water_chunk_instances.keys():
		var mi2 = water_chunk_instances[key]
		if mi2 and is_instance_valid(mi2):
			mi2.queue_free()
	water_chunk_instances.clear()
	for mi in _terrain_pool:
		if mi and is_instance_valid(mi):
			mi.queue_free()
	_terrain_pool.clear()
	for miw in _water_pool:
		if miw and is_instance_valid(miw):
			miw.queue_free()
	_water_pool.clear()
	dirty_chunks.clear()

func shutdown():
	# real shutdown — leaves _stop_workers = true permanently so stray ticks cannot rearm workers and crash on freed state
	_stop_workers = true
	_job_mutex.lock()
	_job_queue.clear()
	_job_mutex.unlock()
	for w in _workers:
		if w and w.is_started():
			w.wait_to_finish()
	_workers.clear()
	_workers_started = false

	_async_pending.clear()
	_job_gens.clear()
	_cancelled.clear()
	_queued_keys.clear()
	_pending_terrain_only.clear()
	_terrain_only_dirty = false
	_result_queue.clear()
	_terrain_result_queue.clear()
	_pending_water.clear()
	_mesh_cache.clear()
	_mesh_cache_order.clear()
	for key in chunk_instances.keys():
		var mi = chunk_instances[key]
		if mi and is_instance_valid(mi):
			mi.queue_free()
	chunk_instances.clear()
	for key in water_chunk_instances.keys():
		var mi2 = water_chunk_instances[key]
		if mi2 and is_instance_valid(mi2):
			mi2.queue_free()
	water_chunk_instances.clear()
	for mi in _terrain_pool:
		if mi and is_instance_valid(mi):
			mi.queue_free()
	_terrain_pool.clear()
	for miw in _water_pool:
		if miw and is_instance_valid(miw):
			miw.queue_free()
	_water_pool.clear()
	dirty_chunks.clear()

func _ensure_workers():
	if _stop_workers:
		return
	if _workers_started:
		return
	_workers_started = true
	_stop_workers = false
	for i in range(MAX_WORKERS):
		var th = Thread.new()
		var err = th.start(_worker_loop)
		if err == OK:
			_workers.append(th)
		else:
			push_warning("[ChunkRenderSystem] Failed to start worker %d" % i)

func _worker_loop():
	while true:
		var job: Variant = null
		_job_mutex.lock()
		if _stop_workers:
			_job_mutex.unlock()
			if terrain_generator != null:
				terrain_generator.release_thread_caches(OS.get_thread_caller_id())
			break
		if not _job_queue.is_empty():
			job = _job_queue[0]
			_job_queue.remove_at(0)
		_job_mutex.unlock()

		if job == null:
			OS.delay_msec(2)
			continue

		var key = job.get("key", "")
		var job_gen = job.get("gen", 0)

		_mutex.lock()
		var cur_gen = _job_gens.get(key, job_gen)
		var is_stale = cur_gen != job_gen
		if not is_stale and _cancelled.has(key):
			is_stale = true
		_mutex.unlock()
		if is_stale:
			_clear_pending(key, job_gen)
			continue

		var result = _do_combined_job(job)
		if result.is_empty():
			_clear_pending(key, job_gen)
			continue

		_mutex.lock()
		cur_gen = _job_gens.get(key, job_gen)
		is_stale = cur_gen != job_gen
		if not is_stale and _cancelled.has(key):
			is_stale = true
		var should_clear = is_stale
		_mutex.unlock()
		if should_clear:
			_clear_pending(key, job_gen)
			continue

		if result.get("terrain_only", false):
			_terrain_result_mutex.lock()
			_terrain_result_queue.append(result)
			_terrain_result_mutex.unlock()
		else:
			_result_mutex.lock()
			_result_queue.append(result)
			_result_mutex.unlock()

func _do_combined_job(job: Dictionary) -> Dictionary:
	var key = job.get("key", "")
	var cx = job.get("cx", 0)
	var cz = job.get("cz", 0)
	var origin_x = job.get("origin_x", cx * chunk_size)
	var origin_z = job.get("origin_z", cz * chunk_size)
	var cs = job.get("chunk_size", chunk_size)
	var max_y = job.get("max_build_y", max_build_y)
	var m = job.get("mesher") as ChunkMesher
	var gen = job.get("terrain_generator") as TerrainGenerator
	var placed_snap = job.get("placed_snap", {})
	var removed_snap = job.get("removed_snap", {})
	var tree_snap = job.get("tree_snap", {})
	var terrain_only = job.get("terrain_only", false) as bool

	var mesh: ArrayMesh = null
	var water_mesh: ArrayMesh = null
	var mesh_data = null
	var water_mesh_data = null
	var gen_payload: Dictionary = {}
	var cache_dict: Variant = null

	if gen != null:
		gen_payload = gen.build_cache_with_generation(origin_x, origin_z, cs, max_y, placed_snap, removed_snap, tree_snap, terrain_only)
		if not terrain_only:
			cache_dict = gen_payload.get("cache_dict", null)

	if not terrain_only and m != null and cache_dict != null:
		var combined = m.build_combined_mesh_data(cache_dict)
		mesh_data = combined.get("terrain", null)
		water_mesh_data = combined.get("water", null)
		if mesh_data != null:
			mesh = m.create_mesh_from_data(mesh_data)
		if water_mesh_data != null:
			water_mesh = m.create_water_mesh_from_data(water_mesh_data)

	return {
		"key": key,
		"cx": cx,
		"cz": cz,
		"mesh": mesh,
		"water_mesh": water_mesh,
		"gen_payload": gen_payload,
		"gen": job.get("gen", 0),
		"terrain_only": terrain_only,
	}

func _touch_lru(key: String) -> void:
	_mesh_cache_order.erase(key)
	_mesh_cache_order.append(key)
	if _mesh_cache_order.size() > MAX_MESH_CACHE:
		var oldest = _mesh_cache_order[0]
		_mesh_cache_order.remove_at(0)
		_mesh_cache.erase(oldest)

func _cache_mesh(key: String, mesh: ArrayMesh):

	var entry = _mesh_cache.get(key, null)
	if entry == null:
		entry = {"terrain": mesh, "water": null}
	else:
		entry["terrain"] = mesh
	_mesh_cache[key] = entry
	_touch_lru(key)

func _cache_water_mesh(key: String, mesh: ArrayMesh):

	if not _mesh_cache.has(key):
		return
	var entry = _mesh_cache[key]
	entry["water"] = mesh
	_mesh_cache[key] = entry
	_touch_lru(key)

func _pop_cached_meshes(key: String) -> Dictionary:
	if not _mesh_cache.has(key):
		return {"mesh": null, "water": null}
	var entry = _mesh_cache[key]
	var terrain = entry.get("terrain", null)
	var water = entry.get("water", null)

	_mesh_cache_order.erase(key)
	_mesh_cache.erase(key)
	return {"mesh": terrain, "water": water}

func _pop_pooled_instance(pool: Array) -> MeshInstance3D:
	while not pool.is_empty():
		var mi = pool.pop_back() as MeshInstance3D
		if mi and is_instance_valid(mi):
			return mi
	return null

func _attach_to_container(mi: MeshInstance3D) -> void:
	if chunk_container and is_instance_valid(chunk_container) and mi.get_parent() == null:
		chunk_container.add_child(mi)

func _release_water(key: String, cache_mesh: bool = false) -> bool:
	if not water_chunk_instances.has(key):
		return false
	var miw = water_chunk_instances[key] as MeshInstance3D
	if miw and is_instance_valid(miw):
		if cache_mesh:
			var mw = miw.mesh as ArrayMesh
			if mw:
				_cache_water_mesh(key, mw)
		miw.mesh = null
		miw.visible = false
		_water_pool.append(miw)
	water_chunk_instances.erase(key)
	return true

func _release_terrain(key: String) -> bool:
	if not chunk_instances.has(key):
		return false
	var mi = chunk_instances[key] as MeshInstance3D
	if mi and is_instance_valid(mi):
		var m = mi.mesh as ArrayMesh
		if m:
			_cache_mesh(key, m)
		mi.mesh = null
		mi.visible = false
		_terrain_pool.append(mi)
	chunk_instances.erase(key)
	_pending_water.erase(key)
	return true

func _release_render_instances(key: String) -> bool:
	var had_terrain = _release_terrain(key)
	var had_water = _release_water(key, true)
	return had_terrain or had_water

func _drop_jobs_for_key(key: String) -> Dictionary:
	var was_in_jobs = false
	var was_in_results = false
	_job_mutex.lock()
	var new_jobs: Array[Dictionary] = []
	for j in _job_queue:
		if j.get("key", "") == key:
			was_in_jobs = true
		else:
			new_jobs.append(j)
	_job_queue = new_jobs
	_job_mutex.unlock()

	_result_mutex.lock()
	var new_results: Array[Dictionary] = []
	for r in _result_queue:
		if r.get("key", "") == key:
			was_in_results = true
		else:
			new_results.append(r)
	_result_queue = new_results
	_result_mutex.unlock()
	_terrain_result_mutex.lock()
	var new_terrain: Array[Dictionary] = []
	for r in _terrain_result_queue:
		if r.get("key", "") == key:
			was_in_results = true
		else:
			new_terrain.append(r)
	_terrain_result_queue = new_terrain
	_terrain_result_mutex.unlock()

	return {"jobs": was_in_jobs, "results": was_in_results}

func unload_chunk(cx: int, cz: int) -> bool:
	var key = "%d_%d" % [cx, cz]
	var drop_info = _drop_jobs_for_key(key)
	var was_in_queue = drop_info.get("jobs", false)
	var was_in_result = drop_info.get("results", false)
	_mutex.lock()
	var was_pending = _async_pending.has(key)
	var cur = _job_gens.get(key, 0)
	var should_inc_gen = was_in_queue or was_pending or was_in_result
	if should_inc_gen:
		_job_gens[key] = cur + 1
	_mutex.unlock()
	_clear_pending(key)
	_mutex.lock()
	if was_pending and not was_in_queue:
		_cancelled[key] = true
	else:
		_cancelled.erase(key)
	_mutex.unlock()
	var had = _release_render_instances(key)
	dirty_chunks.erase(key)
	return had

func unload_render_only(cx: int, cz: int) -> bool:
	var key = "%d_%d" % [cx, cz]
	var drop_info = _drop_jobs_for_key(key)
	var was_in_queue = drop_info.get("jobs", false)
	var was_in_result = drop_info.get("results", false)
	_mutex.lock()
	var was_pending = _async_pending.has(key)
	var cur = _job_gens.get(key, 0)
	var should_inc_gen = was_in_queue or was_pending or was_in_result
	if should_inc_gen:
		_job_gens[key] = cur + 1
	_mutex.unlock()
	_clear_pending(key)
	_mutex.lock()
	if was_pending and not was_in_queue:
		_cancelled[key] = true
	else:
		_cancelled.erase(key)
	_mutex.unlock()

	var had = _release_render_instances(key)
	return had or was_in_queue or was_pending or was_in_result

func is_chunk_loaded(cx: int, cz: int) -> bool:
	var key = "%d_%d" % [cx, cz]
	_mutex.lock()
	var cancelled = _cancelled.has(key)
	var queued = _queued_keys.has(key) or _async_pending.has(key)
	_mutex.unlock()
	if cancelled:
		return false
	if queued:
		return false
	if not chunk_instances.has(key) and not water_chunk_instances.has(key):
		return false
	var mi = chunk_instances.get(key, null)
	var miw = water_chunk_instances.get(key, null)
	var valid_terrain = mi != null and is_instance_valid(mi)
	var valid_water = miw != null and is_instance_valid(miw)
	return valid_terrain or valid_water or chunk_instances.has(key)

func queue_rebuild(cx: int, cz: int):
	var key = "%d_%d" % [cx, cz]
	if _mesh_cache.has(key):
		_mesh_cache.erase(key)
		_mesh_cache_order.erase(key)
	dirty_chunks[key] = Vector2i(cx, cz)

func queue_rebuild_for_world_pos(pos: Vector3i):
	var cx = int(floor(float(pos.x) / float(chunk_size)))
	var cz = int(floor(float(pos.z) / float(chunk_size)))
	queue_rebuild(cx, cz)
	if pos.x % chunk_size == 0:
		queue_rebuild(cx - 1, cz)
	if (pos.x + 1) % chunk_size == 0:
		queue_rebuild(cx + 1, cz)
	if pos.z % chunk_size == 0:
		queue_rebuild(cx, cz - 1)
	if (pos.z + 1) % chunk_size == 0:
		queue_rebuild(cx, cz + 1)

func flush_dirty(max_per_call: int = -1) -> int:
	if max_per_call == -1:
		max_per_call = max_per_frame
	if dirty_chunks.is_empty():
		return 0
	var rebuilt = 0
	var keys = dirty_chunks.keys()
	for k in keys:
		if rebuilt >= max_per_call:
			break
		var v = dirty_chunks[k] as Vector2i
		dirty_chunks.erase(k)
		rebuild_async_combined(v.x, v.y, true)
		rebuilt += 1
	return rebuilt

func rebuild_immediate(cx: int, cz: int):
	var key = "%d_%d" % [cx, cz]

	if _mesh_cache.has(key):
		var cached = _pop_cached_meshes(key)
		var cached_mesh = cached.get("mesh")
		var cached_water = cached.get("water")
		if not chunk_instances.has(key):
			chunk_instances[key] = _create_mesh_instance(cached_mesh, cx, cz)
		else:
			var mi = chunk_instances[key] as MeshInstance3D
			if is_instance_valid(mi):
				mi.mesh = cached_mesh
		if cached_water != null:
			_set_or_create_water(key, cx, cz, cached_water)
		else:
			_release_water(key)
		return

	var origin_x = cx * chunk_size
	var origin_z = cz * chunk_size

	if terrain_generator == null:
		push_warning("[ChunkRenderSystem] rebuild_immediate requires terrain_generator - WorldController always sets it")
		return
	var snap = voxel_model.snapshot_edits_for_chunk(origin_x, origin_z, chunk_size)
	var placed_snap: Dictionary = snap.get("placed", {})
	var removed_snap: Dictionary = snap.get("removed", {})
	var tree_snap: Dictionary = snap.get("trees", {})
	var gen_payload = terrain_generator.build_cache_with_generation(origin_x, origin_z, chunk_size, max_build_y, placed_snap, removed_snap, tree_snap)
	var cache_dict = gen_payload.get("cache_dict", null)
	if voxel_model != null:
		var h = gen_payload.get("height", {})
		var t = gen_payload.get("type", {})
		var coord = Vector2i(cx, cz)
		if not h.is_empty():
			voxel_model.apply_chunk_gen_for_coord(coord, {"height": h, "type": t})
		var tree_fast = gen_payload.get("tree_block_fast", {})
		voxel_model.apply_tree_chunk_for_coord(coord, {"tree_block_fast": tree_fast})
	var terrain_mesh: ArrayMesh = null
	var water_mesh: ArrayMesh = null
	if cache_dict != null and mesher != null:
		var combined = mesher.build_combined_mesh_data(cache_dict)
		var terrain_data = combined.get("terrain", null)
		var water_data = combined.get("water", null)
		if terrain_data != null:
			terrain_mesh = mesher.create_mesh_from_data(terrain_data)
		if water_data != null:
			water_mesh = mesher.create_water_mesh_from_data(water_data)

	_clear_pending(key)

	_set_or_create_terrain(key, cx, cz, terrain_mesh)
	if water_mesh != null:
		_set_or_create_water(key, cx, cz, water_mesh)
	else:
		_release_water(key)
func rebuild_async_combined(cx: int, cz: int, force: bool = false) -> bool:
	var key = "%d_%d" % [cx, cz]
	if not force:
		_mutex.lock()
		var already_queued = _queued_keys.has(key) or _async_pending.has(key)
		var is_terrain_only = _pending_terrain_only.has(key)
		_mutex.unlock()
		if already_queued:
			if is_terrain_only:
				_drop_jobs_for_key(key)
				_mutex.lock()
				var cur = _job_gens.get(key, 0)
				_job_gens[key] = cur + 1
				_mutex.unlock()
				_clear_pending(key)
			else:
				return false
		elif chunk_instances.has(key):
			return false
	else:

		_drop_jobs_for_key(key)
	if _mesh_cache.has(key):
		var cached = _pop_cached_meshes(key)
		var cached_mesh = cached.get("mesh")
		var cached_water = cached.get("water")
		if force:
			_set_or_create_terrain(key, cx, cz, cached_mesh)
			if cached_water != null:
				_set_or_create_water(key, cx, cz, cached_water)
			else:
				_release_water(key)
			return true
		else:
			chunk_instances[key] = _create_mesh_instance(cached_mesh, cx, cz)
			if cached_water != null:
				water_chunk_instances[key] = _create_water_mesh_instance(cached_water, cx, cz)
			return true

	var origin_x = cx * chunk_size
	var origin_z = cz * chunk_size

	var snap = voxel_model.snapshot_edits_for_chunk(origin_x, origin_z, chunk_size)
	var placed_snap: Dictionary = snap.get("placed", {})
	var removed_snap: Dictionary = snap.get("removed", {})
	var tree_snap: Dictionary = snap.get("trees", {})

	_ensure_workers()
	_mutex.lock()
	var new_gen = _job_gens.get(key, 0) + 1
	_job_gens[key] = new_gen
	_async_pending[key] = new_gen
	_queued_keys[key] = true
	_pending_terrain_only.erase(key)
	_cancelled.erase(key)
	_mutex.unlock()

	var job = {
		"key": key,
		"cx": cx,
		"cz": cz,
		"origin_x": origin_x,
		"origin_z": origin_z,
		"chunk_size": chunk_size,
		"max_build_y": max_build_y,
		"mesher": mesher,
		"terrain_generator": terrain_generator,
		"placed_snap": placed_snap,
		"removed_snap": removed_snap,
		"tree_snap": tree_snap,
		"gen": new_gen,
	}

	_job_mutex.lock()
	_job_queue.append(job)
	_job_mutex.unlock()
	return true

func ensure_terrain_async(cx: int, cz: int) -> bool:
	var key = "%d_%d" % [cx, cz]
	_mutex.lock()
	var already_queued = _queued_keys.has(key) or _async_pending.has(key)
	_mutex.unlock()
	if already_queued:
		return false
	if chunk_instances.has(key) or water_chunk_instances.has(key):
		return false
	if voxel_model and voxel_model.is_chunk_data_available(cx, cz):
		return false
	if _mesh_cache.has(key):
		return false
	if terrain_generator == null or voxel_model == null:
		return false
	var origin_x = cx * chunk_size
	var origin_z = cz * chunk_size
	var snap = voxel_model.snapshot_edits_for_chunk(origin_x, origin_z, chunk_size)
	var placed_snap: Dictionary = snap.get("placed", {})
	var removed_snap: Dictionary = snap.get("removed", {})
	var tree_snap: Dictionary = snap.get("trees", {})

	_ensure_workers()
	_mutex.lock()
	var new_gen = _job_gens.get(key, 0) + 1
	_job_gens[key] = new_gen
	_async_pending[key] = new_gen
	_queued_keys[key] = true
	_pending_terrain_only[key] = true
	_cancelled.erase(key)
	_mutex.unlock()

	var job = {
		"key": key,
		"cx": cx,
		"cz": cz,
		"origin_x": origin_x,
		"origin_z": origin_z,
		"chunk_size": chunk_size,
		"max_build_y": max_build_y,
		"mesher": null,
		"terrain_generator": terrain_generator,
		"placed_snap": placed_snap,
		"removed_snap": removed_snap,
		"tree_snap": tree_snap,
		"gen": new_gen,
		"terrain_only": true,
	}

	_job_mutex.lock()
	_job_queue.append(job)
	_job_mutex.unlock()
	return true

func poll_async(max_to_apply: int = 4) -> int:
	_job_mutex.lock()
	var job_empty = _job_queue.is_empty()
	_job_mutex.unlock()
	_result_mutex.lock()
	var result_empty = _result_queue.is_empty()
	_result_mutex.unlock()
	_terrain_result_mutex.lock()
	var terrain_empty = _terrain_result_queue.is_empty()
	_terrain_result_mutex.unlock()
	if job_empty and result_empty and terrain_empty and _pending_water.is_empty():
		return 0
	var time_start = Time.get_ticks_msec()
	var time_budget_ms = 8
	while not _pending_water.is_empty() and Time.get_ticks_msec() - time_start < time_budget_ms:
		var p_keys = _pending_water.keys()
		if p_keys.is_empty():
			break
		var p_key = p_keys[0] as String
		var p_data = _pending_water[p_key] as Dictionary
		_pending_water.erase(p_key)
		var p_cx = p_data.get("cx", 0)
		var p_cz = p_data.get("cz", 0)
		var p_wmesh = p_data.get("water_mesh", null) as ArrayMesh
		if p_wmesh != null:
			_set_or_create_water(p_key, p_cx, p_cz, p_wmesh)
		else:
			_release_water(p_key)
	var applied_mesh = 0
	while applied_mesh < max_to_apply and Time.get_ticks_msec() - time_start < time_budget_ms:
		_result_mutex.lock()
		if _result_queue.is_empty():
			_result_mutex.unlock()
			break
		var result = _result_queue[0]
		_result_queue.remove_at(0)
		_result_mutex.unlock()
		var key = result.get("key", "")
		var cx = result.get("cx", 0)
		var cz = result.get("cz", 0)
		var res_gen = result.get("gen", 0)
		if _should_skip_result(key, res_gen):
			continue
		var payload = result.get("gen_payload", {}) as Dictionary
		if not payload.is_empty() and voxel_model != null:
			var h = payload.get("height", {})
			var t = payload.get("type", {})
			var coord = Vector2i(cx, cz)
			if not h.is_empty():
				voxel_model.apply_chunk_gen_for_coord(coord, {"height": h, "type": t})
			var tree_fast = payload.get("tree_block_fast", {})
			voxel_model.apply_tree_chunk_for_coord(coord, {"tree_block_fast": tree_fast})
		var mesh = result.get("mesh", null) as ArrayMesh
		var water_mesh = result.get("water_mesh", null) as ArrayMesh
		if mesh == null and water_mesh == null:
			_ensure_empty_terrain(key, cx, cz, false)
		else:
			if mesh != null:
				_set_or_create_terrain(key, cx, cz, mesh)
			else:
				_ensure_empty_terrain(key, cx, cz, false)
			if water_mesh != null:
				if Time.get_ticks_msec() - time_start < time_budget_ms:
					_set_or_create_water(key, cx, cz, water_mesh)
				else:
					_pending_water[key] = {"cx": cx, "cz": cz, "water_mesh": water_mesh}
			else:
				_release_water(key)
		applied_mesh += 1
	var applied_terrain = 0
	while applied_terrain < max_terrain_per_frame and Time.get_ticks_msec() - time_start < time_budget_ms:
		_terrain_result_mutex.lock()
		if _terrain_result_queue.is_empty():
			_terrain_result_mutex.unlock()
			break
		var result = _terrain_result_queue[0]
		_terrain_result_queue.remove_at(0)
		_terrain_result_mutex.unlock()
		var key = result.get("key", "")
		var cx = result.get("cx", 0)
		var cz = result.get("cz", 0)
		var res_gen = result.get("gen", 0)
		if _should_skip_result(key, res_gen):
			continue
		var payload = result.get("gen_payload", {}) as Dictionary
		if not payload.is_empty() and voxel_model != null:
			var h = payload.get("height", {})
			var t = payload.get("type", {})
			var coord = Vector2i(cx, cz)
			if not h.is_empty():
				voxel_model.apply_chunk_gen_for_coord(coord, {"height": h, "type": t})
			var tree_fast = payload.get("tree_block_fast", {})
			voxel_model.apply_tree_chunk_for_coord(coord, {"tree_block_fast": tree_fast})
		applied_terrain += 1
	if applied_terrain > 0:
		_mutex.lock()
		_terrain_only_dirty = true
		_mutex.unlock()
	while not _pending_water.is_empty() and Time.get_ticks_msec() - time_start < time_budget_ms:
		var pk2 = _pending_water.keys()[0] as String
		var pd2 = _pending_water[pk2] as Dictionary
		_pending_water.erase(pk2)
		var pcx2 = pd2.get("cx", 0)
		var pcz2 = pd2.get("cz", 0)
		var pwm2 = pd2.get("water_mesh", null) as ArrayMesh
		if pwm2 != null:
			_set_or_create_water(pk2, pcx2, pcz2, pwm2)
		else:
			_release_water(pk2)
	return applied_mesh + applied_terrain

func _create_mesh_instance(mesh: ArrayMesh, cx: int, cz: int) -> MeshInstance3D:
	var mi = _pop_pooled_instance(_terrain_pool)
	if mi != null:
		mi.mesh = mesh
		mi.material_override = terrain_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visible = true
		mi.name = "Chunk_%d_%d" % [cx, cz]
		_attach_to_container(mi)
		return mi
	mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = terrain_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.name = "Chunk_%d_%d" % [cx, cz]
	_attach_to_container(mi)
	return mi

func _create_water_mesh_instance(mesh: ArrayMesh, cx: int, cz: int) -> MeshInstance3D:
	var mi = _pop_pooled_instance(_water_pool)
	if mi != null:
		mi.mesh = mesh
		mi.visible = true
		mi.name = "Water_%d_%d" % [cx, cz]
		mi.material_override = water_material if water_material else terrain_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_attach_to_container(mi)
		return mi
	mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = water_material if water_material else terrain_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Water_%d_%d" % [cx, cz]
	_attach_to_container(mi)
	return mi

func _create_empty_terrain_instance(cx: int, cz: int, cached: bool = false) -> MeshInstance3D:
	var mi = _pop_pooled_instance(_terrain_pool)
	if mi != null:
		mi.mesh = null
		mi.visible = true
		mi.name = "Chunk_%d_%d_empty%s" % [cx, cz, "_cached" if cached else ""]
		_attach_to_container(mi)
		return mi
	mi = MeshInstance3D.new()
	mi.mesh = null
	mi.name = "Chunk_%d_%d_empty%s" % [cx, cz, "_cached" if cached else ""]
	_attach_to_container(mi)
	return mi

func _set_or_create_terrain(key: String, cx: int, cz: int, mesh: ArrayMesh) -> void:
	if chunk_instances.has(key):
		var existing = chunk_instances[key] as MeshInstance3D
		if is_instance_valid(existing):
			existing.mesh = mesh
			return
	chunk_instances[key] = _create_mesh_instance(mesh, cx, cz)

func _set_or_create_water(key: String, cx: int, cz: int, mesh: ArrayMesh) -> void:
	if water_chunk_instances.has(key):
		var existing = water_chunk_instances[key] as MeshInstance3D
		if is_instance_valid(existing):
			existing.mesh = mesh
			return
	water_chunk_instances[key] = _create_water_mesh_instance(mesh, cx, cz)

func _ensure_empty_terrain(key: String, cx: int, cz: int, cached: bool = false) -> void:
	if chunk_instances.has(key):
		return
	chunk_instances[key] = _create_empty_terrain_instance(cx, cz, cached)
