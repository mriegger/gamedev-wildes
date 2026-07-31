extends RefCounted
class_name ChunkRenderSystem

## ChunkRenderSystem - manages chunk meshes with bounded worker pool
## Now supports water blocks as separate translucent mesh with water shader

var chunk_container: Node3D
var mesher: ChunkMesher
var terrain_material: Material
var water_material: Material
var voxel_model: VoxelWorld
var terrain_generator: TerrainGenerator

var world_size: int = 200
var chunk_size: int = 20
var max_build_y: int = 36
var seed_value: int = 1337
var infinite_world: bool = false

var chunk_instances: Dictionary = {} # terrain
var water_chunk_instances: Dictionary = {} # water
var dirty_chunks: Dictionary = {}
var max_per_frame: int = 1

var total_rebuilds: int = 0
var last_flush_ms: int = 0

# --- Legacy async ---
var _threads: Dictionary = {}
var _thread_results: Dictionary = {}
var _mutex: Mutex = Mutex.new()
var _async_pending: Dictionary = {}
var _job_gens: Dictionary = {}
var _cancelled: Dictionary = {}
var _total_async: int = 0
var _total_async_completed: int = 0
var _total_cancelled_ack: int = 0

# --- Mesh cache ---
var _mesh_cache: Dictionary = {}
var _mesh_cache_order: Array[String] = []
var _water_mesh_cache: Dictionary = {}
var _water_mesh_cache_order: Array[String] = []
const MAX_MESH_CACHE: int = 80
var _cache_hits: int = 0

# --- Bounded worker pool ---
const MAX_WORKERS: int = 2
var _workers: Array[Thread] = []
var _job_queue: Array[Dictionary] = []
var _job_mutex: Mutex = Mutex.new()
var _result_queue: Array[Dictionary] = []
var _result_mutex: Mutex = Mutex.new()
var _stop_workers: bool = false
var _workers_started: bool = false


func setup(p_container: Node3D, p_mesher: ChunkMesher, p_material: Material, p_world_size: int, p_chunk_size: int, p_max_y: int, p_seed: int, p_voxel_model: VoxelWorld):
	chunk_container = p_container
	mesher = p_mesher
	terrain_material = p_material
	world_size = p_world_size
	chunk_size = p_chunk_size
	max_build_y = p_max_y
	seed_value = p_seed
	voxel_model = p_voxel_model
	if mesher == null:
		mesher = ChunkMesher.new(world_size, chunk_size, max_build_y, seed_value, true)
	infinite_world = voxel_model.infinite_world if voxel_model else false
	_mutex = Mutex.new()
	_job_mutex = Mutex.new()
	_result_mutex = Mutex.new()
	_threads.clear()
	_thread_results.clear()
	_async_pending.clear()
	_job_gens.clear()
	_cancelled.clear()
	_job_queue.clear()
	_result_queue.clear()
	_workers.clear()
	_stop_workers = false
	_workers_started = false

func set_terrain_generator(gen: TerrainGenerator):
	terrain_generator = gen

func set_water_material(mat: Material):
	water_material = mat
	# Update existing water instances
	for key in water_chunk_instances.keys():
		var mi = water_chunk_instances[key] as MeshInstance3D
		if mi and is_instance_valid(mi):
			mi.material_override = water_material

func clear():
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

	for key in _threads.keys():
		var th = _threads[key] as Thread
		if th and th.is_started():
			th.wait_to_finish()
	_threads.clear()
	_thread_results.clear()
	_async_pending.clear()
	_job_gens.clear()
	_cancelled.clear()
	_result_queue.clear()
	_mesh_cache.clear()
	_mesh_cache_order.clear()
	_water_mesh_cache.clear()
	_water_mesh_cache_order.clear()
	_cache_hits = 0
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
	dirty_chunks.clear()
	total_rebuilds = 0
	_total_async = 0
	_total_async_completed = 0

func _ensure_workers():
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
			_mutex.lock()
			if _async_pending.get(key, -1) == job_gen:
				_async_pending.erase(key)
			_cancelled.erase(key)
			_total_cancelled_ack += 1
			_mutex.unlock()
			continue

		var result = _do_combined_job(job)
		if result.is_empty():
			_mutex.lock()
			if _async_pending.get(key, -1) == job_gen:
				_async_pending.erase(key)
			_mutex.unlock()
			continue

		_mutex.lock()
		cur_gen = _job_gens.get(key, job_gen)
		is_stale = cur_gen != job_gen
		if not is_stale and _cancelled.has(key):
			is_stale = true
		if is_stale:
			if _async_pending.get(key, -1) == job_gen:
				_async_pending.erase(key)
			_cancelled.erase(key)
			_total_cancelled_ack += 1
			_mutex.unlock()
			continue
		_mutex.unlock()

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
	var cache_dict: Variant = job.get("cache_dict", null)

	var mesh_data = null
	var water_mesh_data = null
	var gen_payload: Dictionary = {}

	var is_data_only = job.get("data_only", false)
	if cache_dict == null and gen != null:
		if gen.has_method("build_cache_with_generation"):
			gen_payload = gen.build_cache_with_generation(origin_x, origin_z, cs, max_y, placed_snap, removed_snap, tree_snap)
			cache_dict = gen_payload.get("cache_dict", null)

	if not is_data_only and m != null and cache_dict != null:
		# Combined terrain + water
		if m.has_method("build_combined_mesh_data"):
			var combined = m.build_combined_mesh_data(cache_dict)
			mesh_data = combined.get("terrain", null)
			water_mesh_data = combined.get("water", null)
		else:
			mesh_data = m.build_mesh_data_from_cache(cache_dict)
			if m.has_method("build_water_mesh_data_from_cache"):
				water_mesh_data = m.build_water_mesh_data_from_cache(cache_dict)

	return {
		"key": key,
		"cx": cx,
		"cz": cz,
		"mesh_data": mesh_data,
		"water_mesh_data": water_mesh_data,
		"cache_dict": cache_dict,
		"gen_payload": gen_payload,
		"origin_x": origin_x,
		"origin_z": origin_z,
		"data_only": is_data_only,
		"gen": job.get("gen", 0),
	}

func _cache_mesh(key: String, mesh: ArrayMesh):
	if _mesh_cache.has(key):
		_mesh_cache_order.erase(key)
	_mesh_cache[key] = mesh
	_mesh_cache_order.append(key)
	if _mesh_cache_order.size() > MAX_MESH_CACHE:
		var oldest = _mesh_cache_order[0]
		_mesh_cache_order.remove_at(0)
		_mesh_cache.erase(oldest)

func _cache_water_mesh(key: String, mesh: ArrayMesh):
	if _water_mesh_cache.has(key):
		_water_mesh_cache_order.erase(key)
	_water_mesh_cache[key] = mesh
	_water_mesh_cache_order.append(key)
	if _water_mesh_cache_order.size() > MAX_MESH_CACHE:
		var oldest = _water_mesh_cache_order[0]
		_water_mesh_cache_order.remove_at(0)
		_water_mesh_cache.erase(oldest)

func _pop_cached_mesh(key: String) -> Variant:
	if not _mesh_cache.has(key):
		return null
	var cached = _mesh_cache.get(key, null)
	if _mesh_cache.has(key):
		_cache_hits += 1
		_mesh_cache_order.erase(key)
		_mesh_cache.erase(key)
		return cached
	return null

func _pop_cached_water_mesh(key: String) -> Variant:
	if not _water_mesh_cache.has(key):
		return null
	var cached = _water_mesh_cache.get(key, null)
	_cache_hits += 1
	_water_mesh_cache_order.erase(key)
	_water_mesh_cache.erase(key)
	return cached

func unload_chunk(cx: int, cz: int) -> bool:
	var key = "%d_%d" % [cx, cz]

	var was_in_queue = false
	_job_mutex.lock()
	for j in _job_queue:
		if j.get("key", "") == key:
			was_in_queue = true
			break
	_job_mutex.unlock()

	var was_in_result = false
	_result_mutex.lock()
	for r in _result_queue:
		if r.get("key", "") == key:
			was_in_result = true
			break
	_result_mutex.unlock()

	_mutex.lock()
	var was_pending = _async_pending.has(key)
	var cur = _job_gens.get(key, 0)
	var should_inc_gen = was_in_queue or was_pending or was_in_result
	var new_gen = cur
	if should_inc_gen:
		new_gen = cur + 1
		_job_gens[key] = new_gen
	_async_pending.erase(key)
	_thread_results.erase(key)
	if was_pending and not was_in_queue:
		_cancelled[key] = true
	else:
		_cancelled.erase(key)
		if was_in_queue or was_in_result:
			_total_cancelled_ack += 1
	_mutex.unlock()

	_job_mutex.lock()
	var new_jobs: Array[Dictionary] = []
	for j in _job_queue:
		if j.get("key", "") != key:
			new_jobs.append(j)
	_job_queue = new_jobs
	_job_mutex.unlock()

	_result_mutex.lock()
	var new_results: Array[Dictionary] = []
	for r in _result_queue:
		if r.get("key", "") != key:
			new_results.append(r)
	_result_queue = new_results
	_result_mutex.unlock()

	var had_terrain = chunk_instances.has(key)
	var had_water = water_chunk_instances.has(key)

	if had_terrain:
		var mi = chunk_instances[key] as MeshInstance3D
		if mi and is_instance_valid(mi):
			var m = mi.mesh as ArrayMesh
			if m:
				_cache_mesh(key, m)
			mi.queue_free()
		chunk_instances.erase(key)
	if had_water:
		var miw = water_chunk_instances[key] as MeshInstance3D
		if miw and is_instance_valid(miw):
			var mw = miw.mesh as ArrayMesh
			if mw:
				_cache_water_mesh(key, mw)
			miw.queue_free()
		water_chunk_instances.erase(key)

	dirty_chunks.erase(key)
	return had_terrain or had_water

func unload_render_only(cx: int, cz: int) -> bool:
	var key = "%d_%d" % [cx, cz]
	if not chunk_instances.has(key) and not water_chunk_instances.has(key):
		return false
	if chunk_instances.has(key):
		var mi = chunk_instances[key] as MeshInstance3D
		if mi and is_instance_valid(mi):
			var m = mi.mesh as ArrayMesh
			if m:
				_cache_mesh(key, m)
			mi.queue_free()
		chunk_instances.erase(key)
	if water_chunk_instances.has(key):
		var miw = water_chunk_instances[key] as MeshInstance3D
		if miw and is_instance_valid(miw):
			var mw = miw.mesh as ArrayMesh
			if mw:
				_cache_water_mesh(key, mw)
			miw.queue_free()
		water_chunk_instances.erase(key)
	return true

func is_chunk_loaded(cx: int, cz: int) -> bool:
	var key = "%d_%d" % [cx, cz]
	_mutex.lock()
	var cancelled = _cancelled.has(key)
	_mutex.unlock()
	if cancelled:
		return false
	if _threads.has(key) or _async_pending.has(key):
		return false
	_job_mutex.lock()
	for j in _job_queue:
		if j.get("key", "") == key:
			_job_mutex.unlock()
			return false
	_job_mutex.unlock()
	_result_mutex.lock()
	for r in _result_queue:
		if r.get("key", "") == key:
			_result_mutex.unlock()
			return false
	_result_mutex.unlock()
	if not chunk_instances.has(key) and not water_chunk_instances.has(key):
		return false
	var mi = chunk_instances.get(key, null)
	var miw = water_chunk_instances.get(key, null)
	var valid_terrain = mi != null and is_instance_valid(mi)
	var valid_water = miw != null and is_instance_valid(miw)
	return valid_terrain or valid_water or chunk_instances.has(key)

func is_chunk_pending(cx: int, cz: int) -> bool:
	var key = "%d_%d" % [cx, cz]
	_mutex.lock()
	var cancelled = _cancelled.has(key)
	_mutex.unlock()
	if cancelled:
		return true
	if _threads.has(key) or _async_pending.has(key):
		return true
	_job_mutex.lock()
	for j in _job_queue:
		if j.get("key", "") == key:
			_job_mutex.unlock()
			return true
	_job_mutex.unlock()
	_result_mutex.lock()
	for r in _result_queue:
		if r.get("key", "") == key:
			_result_mutex.unlock()
			return true
	_result_mutex.unlock()
	return false

func get_loaded_chunk_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k in chunk_instances.keys():
		var parts = k.split("_")
		if parts.size() != 2:
			continue
		var cx = int(parts[0])
		var cz = int(parts[1])
		out.append(Vector2i(cx, cz))
	for k in water_chunk_instances.keys():
		if chunk_instances.has(k):
			continue
		var parts = k.split("_")
		if parts.size() != 2:
			continue
		var cx = int(parts[0])
		var cz = int(parts[1])
		out.append(Vector2i(cx, cz))
	return out

func generate_chunks(chunks: Array[Vector2i]):
	for coord in chunks:
		rebuild_immediate(coord.x, coord.y)

func ensure_visibility_around(cx: int, cz: int, radius: int = 1) -> int:
	var count = 0
	var chunks_x = int(ceil(float(world_size) / float(chunk_size)))
	var chunks_z = int(ceil(float(world_size) / float(chunk_size)))
	for dx in range(-radius, radius+1):
		for dz in range(-radius, radius+1):
			var ncx = cx + dx
			var ncz = cz + dz
			if ncx <0 or ncz<0 or ncx>=chunks_x or ncz>=chunks_z:
				continue
			if is_chunk_loaded(ncx, ncz):
				count += 1
	return count

func queue_rebuild(cx: int, cz: int):
	if not infinite_world:
		var chunks_x = int(ceil(float(world_size) / float(chunk_size)))
		var chunks_z = int(ceil(float(world_size) / float(chunk_size)))
		if cx < 0 or cz < 0 or cx >= chunks_x or cz >= chunks_z:
			return
	var key = "%d_%d" % [cx, cz]
	if _mesh_cache.has(key):
		_mesh_cache.erase(key)
		_mesh_cache_order.erase(key)
	if _water_mesh_cache.has(key):
		_water_mesh_cache.erase(key)
		_water_mesh_cache_order.erase(key)
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
	var start = Time.get_ticks_msec()
	for k in keys:
		if rebuilt >= max_per_call:
			break
		var v = dirty_chunks[k] as Vector2i
		dirty_chunks.erase(k)
		rebuild_immediate(v.x, v.y)
		rebuilt += 1
	last_flush_ms = Time.get_ticks_msec() - start
	if rebuilt > 0:
		total_rebuilds += rebuilt
	return rebuilt

func generate_all_chunks():
	clear()
	var chunks_x = int(ceil(float(world_size) / float(chunk_size)))
	var chunks_z = int(ceil(float(world_size) / float(chunk_size)))
	for cx in range(chunks_x):
		for cz in range(chunks_z):
			rebuild_immediate(cx, cz)

func rebuild_immediate(cx: int, cz: int):
	if not infinite_world:
		var chunks_x = int(ceil(float(world_size) / float(chunk_size)))
		var chunks_z = int(ceil(float(world_size) / float(chunk_size)))
		if cx < 0 or cz < 0 or cx >= chunks_x or cz >= chunks_z:
			return
	var key = "%d_%d" % [cx, cz]

	# Try cache
	if _mesh_cache.has(key) or _water_mesh_cache.has(key):
		var cached_mesh = null
		var cached_water = null
		if _mesh_cache.has(key):
			cached_mesh = _mesh_cache.get(key, null)
			_mesh_cache_order.erase(key)
			_mesh_cache.erase(key)
			_cache_hits += 1
		if _water_mesh_cache.has(key):
			cached_water = _water_mesh_cache.get(key, null)
			_water_mesh_cache_order.erase(key)
			_water_mesh_cache.erase(key)
		# Create instances
		if cached_mesh != null or _mesh_cache.has(key) == false:
			if not chunk_instances.has(key):
				if cached_mesh == null:
					var empty_mi = MeshInstance3D.new()
					empty_mi.name = "Chunk_%d_%d_empty_cached" % [cx, cz]
					empty_mi.mesh = null
					if chunk_container and is_instance_valid(chunk_container):
						chunk_container.add_child(empty_mi)
					chunk_instances[key] = empty_mi
				else:
					var mi = _create_mesh_instance(cached_mesh, cx, cz)
					chunk_instances[key] = mi
			else:
				var mi = chunk_instances[key] as MeshInstance3D
				if is_instance_valid(mi):
					mi.mesh = cached_mesh
		if cached_water != null:
			if not water_chunk_instances.has(key):
				var miw = _create_water_mesh_instance(cached_water, cx, cz)
				water_chunk_instances[key] = miw
			else:
				var miw = water_chunk_instances[key] as MeshInstance3D
				if is_instance_valid(miw):
					miw.mesh = cached_water
		else:
			# If no water cached but we had terrain cached, ensure no stale water remains
			if _water_mesh_cache.has(key) == false and water_chunk_instances.has(key):
				# leave as is? For cache hit terrain only, water may be null, remove old water
				var miw_old = water_chunk_instances[key] as MeshInstance3D
				if miw_old and is_instance_valid(miw_old):
					miw_old.queue_free()
				water_chunk_instances.erase(key)
		# If at least one cached, return (we popped)
		if cached_mesh != null or cached_water != null:
			return

	var origin_x = cx * chunk_size
	var origin_z = cz * chunk_size

	var lookup = func(pos: Vector3i): return voxel_model.get_block_at(pos)
	var cache_dict = mesher.build_cache(origin_x, origin_z, lookup)
	var terrain_data = mesher.build_mesh_data_from_cache(cache_dict)
	var water_data = mesher.build_water_mesh_data_from_cache(cache_dict)

	var terrain_mesh = mesher.create_mesh_from_data(terrain_data)
	var water_mesh = mesher.create_water_mesh_from_data(water_data)

	if _threads.has(key):
		_async_pending.erase(key)
		_mutex.lock()
		_thread_results.erase(key)
		_mutex.unlock()

	# Terrain instance
	if chunk_instances.has(key):
		var mi: MeshInstance3D = chunk_instances[key] as MeshInstance3D
		if not is_instance_valid(mi):
			mi = _create_mesh_instance(terrain_mesh, cx, cz)
			chunk_instances[key] = mi
		else:
			mi.mesh = terrain_mesh
	else:
		var mi = _create_mesh_instance(terrain_mesh, cx, cz)
		chunk_instances[key] = mi

	# Water instance
	if water_mesh != null:
		if water_chunk_instances.has(key):
			var miw: MeshInstance3D = water_chunk_instances[key] as MeshInstance3D
			if not is_instance_valid(miw):
				miw = _create_water_mesh_instance(water_mesh, cx, cz)
				water_chunk_instances[key] = miw
			else:
				miw.mesh = water_mesh
		else:
			var miw = _create_water_mesh_instance(water_mesh, cx, cz)
			water_chunk_instances[key] = miw
	else:
		# No water in chunk - remove existing water mesh if any
		if water_chunk_instances.has(key):
			var miw = water_chunk_instances[key] as MeshInstance3D
			if miw and is_instance_valid(miw):
				miw.queue_free()
			water_chunk_instances.erase(key)

# Async combined path
func rebuild_async(cx: int, cz: int) -> bool:
	if not infinite_world:
		var chunks_x = int(ceil(float(world_size) / float(chunk_size)))
		var chunks_z = int(ceil(float(world_size) / float(chunk_size)))
		if cx < 0 or cz < 0 or cx >= chunks_x or cz >= chunks_z:
			return false
	var key = "%d_%d" % [cx, cz]
	if _threads.has(key) or _async_pending.has(key):
		return false
	_job_mutex.lock()
	for j in _job_queue:
		if j.get("key", "") == key:
			_job_mutex.unlock()
			return false
	_job_mutex.unlock()
	_result_mutex.lock()
	for r in _result_queue:
		if r.get("key", "") == key:
			_result_mutex.unlock()
			return false
	_result_mutex.unlock()
	if chunk_instances.has(key):
		return false

	if _mesh_cache.has(key):
		var cached_mesh = _mesh_cache.get(key, null)
		_mesh_cache_order.erase(key)
		_mesh_cache.erase(key)
		_cache_hits += 1
		var cached_water = null
		if _water_mesh_cache.has(key):
			cached_water = _water_mesh_cache.get(key, null)
			_water_mesh_cache_order.erase(key)
			_water_mesh_cache.erase(key)
		if cached_mesh == null:
			var empty_mi = MeshInstance3D.new()
			empty_mi.name = "Chunk_%d_%d_empty_cached" % [cx, cz]
			empty_mi.mesh = null
			if chunk_container and is_instance_valid(chunk_container):
				chunk_container.add_child(empty_mi)
			chunk_instances[key] = empty_mi
		else:
			var mi = _create_mesh_instance(cached_mesh, cx, cz)
			chunk_instances[key] = mi
		if cached_water != null:
			var miw = _create_water_mesh_instance(cached_water, cx, cz)
			water_chunk_instances[key] = miw
		return true

	if terrain_generator != null and voxel_model != null and voxel_model.has_method("snapshot_edits_for_chunk") and terrain_generator.has_method("build_cache_with_generation"):
		return rebuild_async_combined(cx, cz)

	var origin_x = cx * chunk_size
	var origin_z = cz * chunk_size
	var cache_dict: Dictionary
	if voxel_model and voxel_model.has_method("build_cache_for_chunk"):
		cache_dict = voxel_model.build_cache_for_chunk(origin_x, origin_z, chunk_size, max_build_y)
	else:
		var lookup = func(pos: Vector3i): return voxel_model.get_block_at(pos)
		cache_dict = mesher.build_cache(origin_x, origin_z, lookup)

	_mutex.lock()
	var new_gen = _job_gens.get(key, 0) + 1
	_job_gens[key] = new_gen
	_async_pending[key] = new_gen
	_cancelled.erase(key)
	_mutex.unlock()
	var thread = Thread.new()
	var data = {
		"cache_dict": cache_dict,
		"key": key,
		"cx": cx,
		"cz": cz,
		"mesher": mesher,
		"gen": new_gen,
	}
	_total_async += 1
	var err = thread.start(_thread_build_mesh.bind(data))
	if err != OK:
		_mutex.lock()
		_async_pending.erase(key)
		_mutex.unlock()
		return false
	_threads[key] = thread
	return true

func rebuild_async_combined(cx: int, cz: int) -> bool:
	var key = "%d_%d" % [cx, cz]
	_mutex.lock()
	if _async_pending.has(key):
		_mutex.unlock()
		return false
	_mutex.unlock()
	_job_mutex.lock()
	for j in _job_queue:
		if j.get("key", "") == key:
			_job_mutex.unlock()
			return false
	_job_mutex.unlock()
	if chunk_instances.has(key):
		return false

	if _mesh_cache.has(key):
		var cached_mesh = _mesh_cache.get(key, null)
		_mesh_cache_order.erase(key)
		_mesh_cache.erase(key)
		_cache_hits += 1
		var cached_water = null
		if _water_mesh_cache.has(key):
			cached_water = _water_mesh_cache.get(key, null)
			_water_mesh_cache_order.erase(key)
			_water_mesh_cache.erase(key)
		if cached_mesh == null:
			var empty_mi = MeshInstance3D.new()
			empty_mi.name = "Chunk_%d_%d_empty_cached" % [cx, cz]
			empty_mi.mesh = null
			if chunk_container and is_instance_valid(chunk_container):
				chunk_container.add_child(empty_mi)
			chunk_instances[key] = empty_mi
		else:
			var mi = _create_mesh_instance(cached_mesh, cx, cz)
			chunk_instances[key] = mi
		if cached_water != null:
			var miw = _create_water_mesh_instance(cached_water, cx, cz)
			water_chunk_instances[key] = miw
		return true

	var origin_x = cx * chunk_size
	var origin_z = cz * chunk_size

	var placed_snap: Dictionary = {}
	var removed_snap: Dictionary = {}
	var tree_snap: Dictionary = {}
	if voxel_model and voxel_model.has_method("snapshot_edits_for_chunk"):
		var snap = voxel_model.snapshot_edits_for_chunk(origin_x, origin_z, chunk_size)
		placed_snap = snap.get("placed", {})
		removed_snap = snap.get("removed", {})
		tree_snap = snap.get("trees", {})

	_ensure_workers()
	_mutex.lock()
	var new_gen = _job_gens.get(key, 0) + 1
	_job_gens[key] = new_gen
	_async_pending[key] = new_gen
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
		"data_only": false,
		"gen": new_gen,
	}

	_job_mutex.lock()
	_job_queue.append(job)
	_job_mutex.unlock()
	_total_async += 1
	return true

func rebuild_async_data_only(cx: int, cz: int) -> bool:
	var key = "%d_%d" % [cx, cz]
	_mutex.lock()
	if _async_pending.has(key):
		_mutex.unlock()
		return false
	_mutex.unlock()
	_job_mutex.lock()
	for j in _job_queue:
		if j.get("key", "") == key:
			_job_mutex.unlock()
			return false
	_job_mutex.unlock()
	var origin_x = cx * chunk_size
	var origin_z = cz * chunk_size
	var placed_snap: Dictionary = {}
	var removed_snap: Dictionary = {}
	var tree_snap: Dictionary = {}
	if voxel_model and voxel_model.has_method("snapshot_edits_for_chunk"):
		var snap = voxel_model.snapshot_edits_for_chunk(origin_x, origin_z, chunk_size)
		placed_snap = snap.get("placed", {})
		removed_snap = snap.get("removed", {})
		tree_snap = snap.get("trees", {})

	_ensure_workers()
	_mutex.lock()
	var new_gen = _job_gens.get(key, 0) + 1
	_job_gens[key] = new_gen
	_async_pending[key] = new_gen
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
		"data_only": true,
		"gen": new_gen,
	}
	_job_mutex.lock()
	_job_queue.append(job)
	_job_mutex.unlock()
	_total_async += 1
	return true

func _thread_build_mesh(data: Dictionary):
	var cache_dict = data.get("cache_dict", {})
	var m = data.get("mesher") as ChunkMesher
	var mesh_data = null
	var water_mesh_data = null
	if m:
		if m.has_method("build_combined_mesh_data"):
			var combined = m.build_combined_mesh_data(cache_dict)
			mesh_data = combined.get("terrain", null)
			water_mesh_data = combined.get("water", null)
		else:
			mesh_data = m.build_mesh_data_from_cache(cache_dict)
			if m.has_method("build_water_mesh_data_from_cache"):
				water_mesh_data = m.build_water_mesh_data_from_cache(cache_dict)
	_mutex.lock()
	_thread_results[data["key"]] = {"mesh_data": mesh_data, "water_mesh_data": water_mesh_data, "gen": data.get("gen", 0)}
	_mutex.unlock()

func poll_async(max_to_apply: int = 1) -> int:
	if _threads.is_empty() and _job_queue.is_empty() and _result_queue.is_empty():
		return 0

	var applied = 0
	var time_start = Time.get_ticks_msec()
	var time_budget_ms = 8

	if not _threads.is_empty():
		var keys = _threads.keys()
		var to_remove: Array[String] = []
		for k in keys:
			if applied >= max_to_apply:
				break
			if Time.get_ticks_msec() - time_start > time_budget_ms:
				break
			var th = _threads[k] as Thread
			if th == null:
				to_remove.append(k)
				continue
			if not th.is_alive():
				th.wait_to_finish()
				to_remove.append(k)
				_mutex.lock()
				var res = _thread_results.get(k, null)
				_thread_results.erase(k)
				_mutex.unlock()
				_mutex.lock()
				var pending_gen = _async_pending.get(k, -1)
				_async_pending.erase(k)
				var was_cancelled = _cancelled.has(k)
				var cur_gen = _job_gens.get(k, pending_gen if pending_gen != -1 else 0)
				var mesh_data = null
				var water_mesh_data = null
				var res_gen = pending_gen
				if res is Dictionary:
					mesh_data = res.get("mesh_data", null)
					water_mesh_data = res.get("water_mesh_data", null)
					res_gen = res.get("gen", pending_gen)
				else:
					mesh_data = res
				if was_cancelled or (pending_gen != -1 and cur_gen != pending_gen) or (res_gen != -1 and cur_gen != res_gen and cur_gen != pending_gen):
					if was_cancelled:
						_cancelled.erase(k)
					_total_cancelled_ack += 1
					_mutex.unlock()
					continue
				_mutex.unlock()

				if mesh_data == null and water_mesh_data == null:
					var parts = k.split("_")
					if parts.size() == 2:
						var cx = int(parts[0])
						var cz = int(parts[1])
						if not chunk_instances.has(k):
							var mi = MeshInstance3D.new()
							mi.name = "Chunk_%d_%d_empty" % [cx, cz]
							mi.mesh = null
							if chunk_container and is_instance_valid(chunk_container):
								chunk_container.add_child(mi)
							if not chunk_instances.has(k):
								chunk_instances[k] = mi
				else:
					var parts = k.split("_")
					var cx = int(parts[0])
					var cz = int(parts[1])
					if mesh_data != null:
						var mesh = mesher.create_mesh_from_data(mesh_data)
						if chunk_container and is_instance_valid(chunk_container):
							if chunk_instances.has(k):
								var mi: MeshInstance3D = chunk_instances[k] as MeshInstance3D
								if is_instance_valid(mi):
									mi.mesh = mesh
								else:
									var mi2 = _create_mesh_instance(mesh, cx, cz)
									chunk_instances[k] = mi2
							else:
								var mi = _create_mesh_instance(mesh, cx, cz)
								chunk_instances[k] = mi
						else:
							if not chunk_instances.has(k):
								var mi = MeshInstance3D.new()
								mi.name = "Chunk_%d_%d" % [cx, cz]
								mi.mesh = mesh
								chunk_instances[k] = mi
					if water_mesh_data != null:
						var wmesh = mesher.create_water_mesh_from_data(water_mesh_data)
						if chunk_container and is_instance_valid(chunk_container):
							if water_chunk_instances.has(k):
								var miw: MeshInstance3D = water_chunk_instances[k] as MeshInstance3D
								if is_instance_valid(miw):
									miw.mesh = wmesh
								else:
									var miw2 = _create_water_mesh_instance(wmesh, cx, cz)
									water_chunk_instances[k] = miw2
							else:
								var miw = _create_water_mesh_instance(wmesh, cx, cz)
								water_chunk_instances[k] = miw
						else:
							if not water_chunk_instances.has(k):
								var miw = MeshInstance3D.new()
								miw.name = "Water_%d_%d" % [cx, cz]
								miw.mesh = wmesh
								water_chunk_instances[k] = miw
				applied += 1
				_total_async_completed += 1

		for k in to_remove:
			_threads.erase(k)

	while applied < max_to_apply and Time.get_ticks_msec() - time_start < time_budget_ms:
		var result: Variant = null
		_result_mutex.lock()
		if not _result_queue.is_empty():
			result = _result_queue[0]
			_result_queue.remove_at(0)
		_result_mutex.unlock()
		if result == null:
			break

		var key = result.get("key", "")
		var cx = result.get("cx", 0)
		var cz = result.get("cz", 0)
		var res_gen = result.get("gen", 0)

		_mutex.lock()
		var cur_gen = _job_gens.get(key, res_gen)
		var is_stale = cur_gen != res_gen
		var was_cancelled = _cancelled.has(key)
		if is_stale:
			if _async_pending.get(key, -1) == res_gen:
				_async_pending.erase(key)
			if was_cancelled:
				_cancelled.erase(key)
			_total_cancelled_ack += 1
			_mutex.unlock()
			continue
		if was_cancelled:
			_cancelled.erase(key)
			_async_pending.erase(key)
			_total_cancelled_ack += 1
			_mutex.unlock()
			continue
		_async_pending.erase(key)
		_mutex.unlock()

		var payload = result.get("gen_payload", {}) as Dictionary
		if not payload.is_empty() and voxel_model != null:
			var h = payload.get("height", {})
			var t = payload.get("type", {})
			var b = payload.get("biome", {})
			var coord = Vector2i(cx, cz)
			if not h.is_empty():
				if voxel_model.has_method("apply_chunk_gen_for_coord"):
					voxel_model.apply_chunk_gen_for_coord(coord, {"height": h, "type": t, "biome": b})
				else:
					voxel_model.apply_chunk_gen({"height": h, "type": t, "biome": b})
			var tree_fast = payload.get("tree_block_fast", {})
			var tree_blocks = payload.get("tree_blocks", [])
			if not tree_fast.is_empty() or not tree_blocks.is_empty():
				if voxel_model.has_method("apply_tree_chunk_for_coord"):
					voxel_model.apply_tree_chunk_for_coord(coord, {"tree_block_fast": tree_fast, "tree_blocks": tree_blocks})
				else:
					voxel_model.apply_tree_chunk({"tree_block_fast": tree_fast, "tree_blocks": tree_blocks})

		var is_data_only = result.get("data_only", false)
		if is_data_only:
			applied += 1
			_total_async_completed += 1
			continue

		var mesh_data = result.get("mesh_data", null)
		var water_mesh_data = result.get("water_mesh_data", null)

		if mesh_data == null and water_mesh_data == null:
			if not chunk_instances.has(key):
				var mi = MeshInstance3D.new()
				mi.name = "Chunk_%d_%d_empty" % [cx, cz]
				mi.mesh = null
				if chunk_container and is_instance_valid(chunk_container):
					chunk_container.add_child(mi)
				chunk_instances[key] = mi
		else:
			if mesh_data != null:
				var mesh = mesher.create_mesh_from_data(mesh_data)
				if chunk_container and is_instance_valid(chunk_container):
					if chunk_instances.has(key):
						var mi: MeshInstance3D = chunk_instances[key] as MeshInstance3D
						if is_instance_valid(mi):
							mi.mesh = mesh
						else:
							var mi2 = _create_mesh_instance(mesh, cx, cz)
							chunk_instances[key] = mi2
					else:
						var mi = _create_mesh_instance(mesh, cx, cz)
						chunk_instances[key] = mi
				else:
					if not chunk_instances.has(key):
						var mi = MeshInstance3D.new()
						mi.name = "Chunk_%d_%d" % [cx, cz]
						mi.mesh = mesh
						chunk_instances[key] = mi
			else:
				# No terrain mesh, but maybe empty placeholder
				if not chunk_instances.has(key):
					var mi = MeshInstance3D.new()
					mi.name = "Chunk_%d_%d_empty" % [cx, cz]
					mi.mesh = null
					if chunk_container and is_instance_valid(chunk_container):
						chunk_container.add_child(mi)
					chunk_instances[key] = mi

			if water_mesh_data != null:
				var wmesh = mesher.create_water_mesh_from_data(water_mesh_data)
				if chunk_container and is_instance_valid(chunk_container):
					if water_chunk_instances.has(key):
						var miw: MeshInstance3D = water_chunk_instances[key] as MeshInstance3D
						if is_instance_valid(miw):
							miw.mesh = wmesh
						else:
							var miw2 = _create_water_mesh_instance(wmesh, cx, cz)
							water_chunk_instances[key] = miw2
					else:
						var miw = _create_water_mesh_instance(wmesh, cx, cz)
						water_chunk_instances[key] = miw
				else:
					if not water_chunk_instances.has(key):
						var miw = MeshInstance3D.new()
						miw.name = "Water_%d_%d" % [cx, cz]
						miw.mesh = wmesh
						water_chunk_instances[key] = miw
			else:
				if water_chunk_instances.has(key):
					var miw = water_chunk_instances[key] as MeshInstance3D
					if miw and is_instance_valid(miw):
						miw.queue_free()
					water_chunk_instances.erase(key)

		applied += 1
		_total_async_completed += 1

	return applied

func _create_mesh_instance(mesh: ArrayMesh, cx: int, cz: int) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = terrain_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.name = "Chunk_%d_%d" % [cx, cz]
	if chunk_container and is_instance_valid(chunk_container):
		chunk_container.add_child(mi)
	return mi

func _create_water_mesh_instance(mesh: ArrayMesh, cx: int, cz: int) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = water_material if water_material else terrain_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Water_%d_%d" % [cx, cz]
	if chunk_container and is_instance_valid(chunk_container):
		chunk_container.add_child(mi)
	return mi

func get_dirty_count() -> int:
	return dirty_chunks.size()

func get_pending_async_count() -> int:
	_mutex.lock()
	var pending = _async_pending.size()
	_mutex.unlock()
	_job_mutex.lock()
	pending += _job_queue.size()
	_job_mutex.unlock()
	_result_mutex.lock()
	pending += _result_queue.size()
	_result_mutex.unlock()
	return pending + _threads.size()

func get_stats() -> Dictionary:
	_job_mutex.lock()
	var job_q = _job_queue.size()
	_job_mutex.unlock()
	_result_mutex.lock()
	var res_q = _result_queue.size()
	_result_mutex.unlock()
	return {
		"chunks": chunk_instances.size(),
		"water_chunks": water_chunk_instances.size(),
		"dirty": dirty_chunks.size(),
		"pending_async": _threads.size() + job_q + res_q,
		"async_pending_flag": _async_pending.size(),
		"job_queue": job_q,
		"result_queue": res_q,
		"workers": _workers.size(),
		"total_async": _total_async,
		"total_async_completed": _total_async_completed,
		"total_cancelled_ack": _total_cancelled_ack,
		"job_gens": _job_gens.size(),
		"total_rebuilds": total_rebuilds,
		"last_flush_ms": last_flush_ms,
		"max_per_frame": max_per_frame,
		"mesh_cache": _mesh_cache.size(),
		"water_mesh_cache": _water_mesh_cache.size(),
		"cache_hits": _cache_hits,
	}
