extends RefCounted
class_name ChunkRenderSystem

## ChunkRenderSystem - manages chunk meshes, now with seamless async threading
## - Sync rebuild_immediate for edits (1 per frame, quick)
## - Async rebuild_async for streaming (background thread, no stall)

var chunk_container: Node3D
var mesher: ChunkMesher
var terrain_material: Material
var voxel_model: VoxelWorld

var world_size: int = 200
var chunk_size: int = 20
var max_build_y: int = 36
var seed_value: int = 1337
var infinite_world: bool = false

var chunk_instances: Dictionary = {}
var dirty_chunks: Dictionary = {}
var max_per_frame: int = 1

var total_rebuilds: int = 0
var last_flush_ms: int = 0

# --- Async threading ---
var _threads: Dictionary = {} # key String -> Thread
var _thread_results: Dictionary = {} # key String -> Variant mesh_data or null
var _mutex: Mutex = Mutex.new()
var _async_pending: Dictionary = {} # key -> bool (queued)
var _cancelled: Dictionary = {} # key String -> bool (unloaded while thread building, skip creation)
var _total_async: int = 0
var _total_async_completed: int = 0

# --- Mesh cache for fast reload (no lag when revisiting) ---
var _mesh_cache: Dictionary = {} # key String -> ArrayMesh (or null for empty)
var _mesh_cache_order: Array[String] = [] # LRU order, oldest first
const MAX_MESH_CACHE: int = 80 # keeps ~80 recently unloaded chunks for instant reload
var _cache_hits: int = 0


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
	if infinite_world:
		# For infinite, allow negative chunk coords, world_size is effectively infinite
		pass
	_mutex = Mutex.new()
	_threads.clear()
	_thread_results.clear()
	_async_pending.clear()

func clear():
	# Cancel async threads
	for key in _threads.keys():
		var th = _threads[key] as Thread
		if th and th.is_started():
			th.wait_to_finish()
	_threads.clear()
	_thread_results.clear()
	_async_pending.clear()
	_cancelled.clear()
	_mesh_cache.clear()
	_mesh_cache_order.clear()
	_cache_hits = 0
	for key in chunk_instances.keys():
		var mi = chunk_instances[key]
		if mi and is_instance_valid(mi):
			mi.queue_free()
	chunk_instances.clear()
	dirty_chunks.clear()
	total_rebuilds = 0
	_total_async = 0
	_total_async_completed = 0

func _cache_mesh(key: String, mesh: ArrayMesh):
	# LRU cache for instant reload, no CPU cost when revisiting
	if _mesh_cache.has(key):
		_mesh_cache_order.erase(key)
	_mesh_cache[key] = mesh
	_mesh_cache_order.append(key)
	if _mesh_cache_order.size() > MAX_MESH_CACHE:
		var oldest = _mesh_cache_order[0]
		_mesh_cache_order.remove_at(0)
		_mesh_cache.erase(oldest)

func _pop_cached_mesh(key: String) -> Variant:
	if not _mesh_cache.has(key):
		return null
	# Check existence: cached value might be null meaning empty chunk
	var cached = _mesh_cache.get(key, null)
	# Even if null mesh, we have entry – treat as hit for empty placeholder
	if _mesh_cache.has(key):
		_cache_hits += 1
		_mesh_cache_order.erase(key)
		_mesh_cache.erase(key)
		return cached
	return null

func _has_cached_mesh(key: String) -> bool:
	return _mesh_cache.has(key)

func unload_chunk(cx: int, cz: int) -> bool:
	var key = "%d_%d" % [cx, cz]
	# If async build pending for this chunk, cancel it – thread will finish but result ignored
	if _threads.has(key) or _async_pending.has(key):
		_cancelled[key] = true
		_async_pending.erase(key)
		_mutex.lock()
		_thread_results.erase(key)
		_mutex.unlock()
	if not chunk_instances.has(key):
		dirty_chunks.erase(key)
		# If pending thread cancelled, keep thread entry for poll to wait_to_finish, but mark cancelled
		if not _threads.has(key):
			_cancelled.erase(key)
		return false
	var mi = chunk_instances[key] as MeshInstance3D
	if mi and is_instance_valid(mi):
		# Cache mesh for fast reload – no regeneration lag when coming back
		var m = mi.mesh as ArrayMesh
		_cache_mesh(key, m)
		mi.queue_free()
	chunk_instances.erase(key)
	dirty_chunks.erase(key)
	_cancelled.erase(key)
	return true

func is_chunk_loaded(cx: int, cz: int) -> bool:
	var key = "%d_%d" % [cx, cz]
	if _cancelled.has(key):
		return false
	if _threads.has(key) or _async_pending.has(key):
		# Consider pending async as not yet loaded but in progress
		return false
	if not chunk_instances.has(key):
		return false
	var mi = chunk_instances[key]
	return mi != null and is_instance_valid(mi)

func is_chunk_pending(cx: int, cz: int) -> bool:
	var key = "%d_%d" % [cx, cz]
	if _cancelled.has(key):
		return true # treat cancelled as pending until poll cleans
	return _threads.has(key) or _async_pending.has(key)

func get_loaded_chunk_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k in chunk_instances.keys():
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
	# Invalidate cached mesh if chunk edited – must rebuild
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
	# Synchronous, used for edits and initial loads during loading screen
	if not infinite_world:
		var chunks_x = int(ceil(float(world_size) / float(chunk_size)))
		var chunks_z = int(ceil(float(world_size) / float(chunk_size)))
		if cx < 0 or cz < 0 or cx >= chunks_x or cz >= chunks_z:
			return
	var key = "%d_%d" % [cx, cz]

	# Fast path: if we have cached mesh from recent unload, reuse instantly (no lag)
	if _mesh_cache.has(key):
		var has_entry = _mesh_cache.has(key)
		var cached_mesh = null
		if has_entry:
			cached_mesh = _mesh_cache.get(key, null)
			# Only use cache if chunk is not dirty? Dirty already invalidated in queue_rebuild
			# Pop from cache (LRU remove)
			_mesh_cache_order.erase(key)
			# Keep entry for this use then erase? We pop via _pop_cached_mesh logic but we already have
			# For immediate, reuse and keep cached? We erase to avoid double use – will be re-cached on next unload
			_mesh_cache.erase(key)
			_cache_hits += 1
		var mi: MeshInstance3D
		if chunk_instances.has(key):
			mi = chunk_instances[key] as MeshInstance3D
			if is_instance_valid(mi):
				mi.mesh = cached_mesh
			else:
				mi = _create_mesh_instance(cached_mesh, cx, cz)
				chunk_instances[key] = mi
		else:
			if cached_mesh == null:
				# Empty chunk cached
				var empty_mi = MeshInstance3D.new()
				empty_mi.name = "Chunk_%d_%d_empty_cached" % [cx, cz]
				empty_mi.mesh = null
				if chunk_container and is_instance_valid(chunk_container):
					chunk_container.add_child(empty_mi)
				chunk_instances[key] = empty_mi
			else:
				mi = _create_mesh_instance(cached_mesh, cx, cz)
				chunk_instances[key] = mi
		return

	var origin_x = cx * chunk_size
	var origin_z = cz * chunk_size

	var lookup = func(pos: Vector3i): return voxel_model.get_block_at(pos)
	var mesh = mesher.build_mesh(origin_x, origin_z, lookup, voxel_model.height_map)

	# Cancel any pending async for same chunk
	if _threads.has(key):
		# let thread finish but we'll overwrite result below; clear pending
		_async_pending.erase(key)
		_mutex.lock()
		_thread_results.erase(key)
		_mutex.unlock()
		# Don't wait here to avoid stall, poll will clean thread later

	if chunk_instances.has(key):
		var mi: MeshInstance3D = chunk_instances[key] as MeshInstance3D
		if not is_instance_valid(mi):
			mi = _create_mesh_instance(mesh, cx, cz)
			chunk_instances[key] = mi
		else:
			mi.mesh = mesh
	else:
		var mi = _create_mesh_instance(mesh, cx, cz)
		chunk_instances[key] = mi

# ------------------------------------------------------------------
# Async seamless path
# ------------------------------------------------------------------
func rebuild_async(cx: int, cz: int) -> bool:
	# Returns true if queued
	if not infinite_world:
		var chunks_x = int(ceil(float(world_size) / float(chunk_size)))
		var chunks_z = int(ceil(float(world_size) / float(chunk_size)))
		if cx < 0 or cz < 0 or cx >= chunks_x or cz >= chunks_z:
			return false
	var key = "%d_%d" % [cx, cz]
	if _threads.has(key) or _async_pending.has(key):
		return false # already pending
	if chunk_instances.has(key):
		return false # already loaded

	# Fast path: cached mesh from recent unload → instant, no thread, no lag
	if _mesh_cache.has(key):
		var cached_mesh = _mesh_cache.get(key, null)
		_mesh_cache_order.erase(key)
		_mesh_cache.erase(key)
		_cache_hits += 1
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
		return true # treated as loaded instantly

	var origin_x = cx * chunk_size
	var origin_z = cz * chunk_size
	# Fast snapshot using VoxelWorld optimized method (no Callable overhead)
	var cache_dict: Dictionary
	if voxel_model and voxel_model.has_method("build_cache_for_chunk"):
		cache_dict = voxel_model.build_cache_for_chunk(origin_x, origin_z, chunk_size, max_build_y)
	else:
		# Fallback old path
		var lookup = func(pos: Vector3i): return voxel_model.get_block_at(pos)
		cache_dict = mesher.build_cache(origin_x, origin_z, lookup)

	_async_pending[key] = true
	var thread = Thread.new()
	var data = {
		"cache_dict": cache_dict,
		"key": key,
		"cx": cx,
		"cz": cz,
		"mesher": mesher,
	}
	# Stat
	_total_async += 1
	# Start thread with bound data
	var err = thread.start(_thread_build_mesh.bind(data))
	if err != OK:
		_async_pending.erase(key)
		return false
	_threads[key] = thread
	return true

func _thread_build_mesh(data: Dictionary):
	# Runs in background thread - heavy geometry
	var cache_dict = data.get("cache_dict", {})
	var m = data.get("mesher") as ChunkMesher
	var mesh_data = null
	if m:
		mesh_data = m.build_mesh_data_from_cache(cache_dict)
	_mutex.lock()
	_thread_results[data["key"]] = mesh_data
	_mutex.unlock()
	# No return

func poll_async(max_to_apply: int = 4) -> int:
	# Call from main thread _process, applies completed meshes without stalling
	if _threads.is_empty():
		return 0
	var applied = 0
	var keys = _threads.keys()
	# Copy to avoid modification during iter
	var to_remove: Array[String] = []
	for k in keys:
		if applied >= max_to_apply:
			break
		var th = _threads[k] as Thread
		if th == null:
			to_remove.append(k)
			continue
		if not th.is_alive():
			# Thread finished
			th.wait_to_finish()
			to_remove.append(k)
			_mutex.lock()
			var mesh_data = _thread_results.get(k, null)
			_thread_results.erase(k)
			_mutex.unlock()
			_async_pending.erase(k)

			# If chunk was cancelled (unloaded while building), skip creation entirely
			if _cancelled.has(k):
				_cancelled.erase(k)
				continue

			if mesh_data == null:
				# Empty chunk - create placeholder to mark loaded (only if not cancelled)
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
						chunk_instances[k] = mi
			else:
				var mesh = mesher.create_mesh_from_data(mesh_data)
				var parts = k.split("_")
				var cx = int(parts[0])
				var cz = int(parts[1])
				var key = k
				# If container gone, skip
				if not chunk_container or not is_instance_valid(chunk_container):
					continue
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
			applied += 1
			_total_async_completed += 1

	for k in to_remove:
		_threads.erase(k)

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

func get_dirty_count() -> int:
	return dirty_chunks.size()

func get_pending_async_count() -> int:
	return _threads.size()

func get_stats() -> Dictionary:
	return {
		"chunks": chunk_instances.size(),
		"dirty": dirty_chunks.size(),
		"pending_async": _threads.size(),
		"async_pending_flag": _async_pending.size(),
		"total_async": _total_async,
		"total_async_completed": _total_async_completed,
		"total_rebuilds": total_rebuilds,
		"last_flush_ms": last_flush_ms,
		"max_per_frame": max_per_frame,
		"mesh_cache": _mesh_cache.size(),
		"cache_hits": _cache_hits,
	}
