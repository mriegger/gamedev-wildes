extends RefCounted
class_name ChunkManager

## ChunkManager - continuous chunk streaming with separated visible vs cached
## - Visible: render_distance -> mesh rendered
## - Cached: unload_distance (render + padding) -> terrain data kept, mesh may be cached
## - Bounded worker pool (2) with cancellation for obsolete chunks
## - One mesh upload per frame budget via renderer poll_async(1)
## - Uses combined terrain+trees payload generation reusing height/type for trees

signal chunk_loaded(coord: Vector2i)
signal chunk_unloaded(coord: Vector2i)
signal streaming_updated(stats: Dictionary)

const _ChunkCoord = preload("res://world/streaming/chunk_coord.gd")

var config: WorldConfig
var voxel_model: VoxelWorld
var chunk_renderer: ChunkRenderSystem
var terrain_generator: TerrainGenerator

var player_ref: Node3D = null

# Tracking
var loaded_chunks: Dictionary = {} # legacy - now tracks data chunks (terrain cached) for backwards compat
var data_chunks: Dictionary = {} # Vector2i -> true : terrain data (height/type/tree) is cached
var visible_chunks: Dictionary = {} # Vector2i -> true : mesh is rendered (subset of data)

var load_queue: Array[Vector2i] = [] # legacy visible queue
var data_load_queue: Array[Vector2i] = [] # keep radius, need terrain data
var mesh_load_queue: Array[Vector2i] = [] # visible radius, need mesh (data already present)
var mesh_unload_queue: Array[Vector2i] = [] # was visible, now outside visible but inside keep -> unrender only
var unload_queue: Array[Vector2i] = [] # legacy, now used for data unload (outside keep)
var data_unload_queue: Array[Vector2i] = [] # outside keep -> remove data + mesh cache

var render_distance: int = 4
var unload_distance: int = 6
var max_loads_per_frame: int = 1
var max_unloads_per_frame: int = 4
var update_interval: float = 0.15

var last_player_chunk: Vector2i = Vector2i(-99999, -99999)
var last_update_time: float = 0.0
var _time_accum: float = 0.0

var total_loads: int = 0
var total_unloads: int = 0
var _initialized: bool = false
var use_async: bool = true

func setup(p_config: WorldConfig, p_voxel_model: VoxelWorld, p_renderer: ChunkRenderSystem, p_terrain_gen: TerrainGenerator = null):
	config = p_config
	voxel_model = p_voxel_model
	chunk_renderer = p_renderer
	terrain_generator = p_terrain_gen
	if config:
		render_distance = config.render_distance
		unload_distance = config.render_distance + config.unload_padding
		max_loads_per_frame = config.max_chunk_loads_per_frame
		max_unloads_per_frame = config.max_chunk_unloads_per_frame
		update_interval = config.chunk_update_interval
	loaded_chunks.clear()
	data_chunks.clear()
	visible_chunks.clear()
	load_queue.clear()
	data_load_queue.clear()
	mesh_load_queue.clear()
	mesh_unload_queue.clear()
	unload_queue.clear()
	data_unload_queue.clear()
	last_player_chunk = Vector2i(-99999, -99999)
	_time_accum = 0.0
	_initialized = true
	if voxel_model:
		if voxel_model.has_method("configure_terrain_cache"):
			voxel_model.configure_terrain_cache(render_distance, config.unload_padding if config else 2)
		# Connect eviction signal so VoxelWorld LRU does not disagree with manager's data_chunks
		if voxel_model.has_signal("terrain_chunk_evicted"):
			if not voxel_model.terrain_chunk_evicted.is_connected(_on_terrain_evicted):
				voxel_model.terrain_chunk_evicted.connect(_on_terrain_evicted)
	if chunk_renderer and terrain_generator:
		chunk_renderer.set_terrain_generator(terrain_generator)
	print("[ChunkManager] Setup visible=%d keep=%d max_load=%d max_unload=%d interval=%.2f cache_max=%d" % [
		render_distance, unload_distance, max_loads_per_frame, max_unloads_per_frame, update_interval,
		voxel_model.max_terrain_cache_chunks if voxel_model and voxel_model.has_method("get_stats") else 0
	])

func _on_terrain_evicted(coord: Vector2i):
	# VoxelWorld evicted data independently - remove manager tracking to avoid disagreement
	# ChunkManager is sole eviction owner, but safety: if World does evict, clear our entries
	if data_chunks.has(coord):
		data_chunks.erase(coord)
		loaded_chunks.erase(coord)
		visible_chunks.erase(coord)
		# Also ensure renderer cache cleared
		if chunk_renderer and chunk_renderer.has_method("unload_render_only"):
			chunk_renderer.unload_render_only(coord.x, coord.y)

func set_player_ref(p_player: Node3D):
	player_ref = p_player
	if player_ref:
		print("[ChunkManager] Player ref set at %s" % player_ref.global_position)

func set_render_distance(d: int):
	render_distance = clamp(d, 1, 16)
	if config:
		unload_distance = render_distance + config.unload_padding
	else:
		unload_distance = render_distance + 2
	print("[ChunkManager] Render distance set visible=%d keep=%d" % [render_distance, unload_distance])
	if voxel_model and voxel_model.has_method("configure_terrain_cache"):
		voxel_model.configure_terrain_cache(render_distance, config.unload_padding if config else 2)

func ensure_terrain_for_chunk(coord: Vector2i):
	if not config or not config.infinite_world:
		return
	if not terrain_generator or not voxel_model:
		return
	var origin_x = coord.x * config.chunk_size
	var origin_z = coord.y * config.chunk_size

	# Fast path: check data presence via direct tracking (O(1)) - no scanning
	if data_chunks.has(coord) or voxel_model.is_chunk_data_available(coord.x, coord.y):
		data_chunks[coord] = true
		loaded_chunks[coord] = true # legacy compat
		# Ensure trees via direct tracking, not scanning all blocks
		if voxel_model.has_method("has_trees_in_chunk"):
			if not voxel_model.has_trees_in_chunk(coord.x, coord.y):
				# Need trees for this chunk - generate using combined payload reusing heights
				if terrain_generator.has_method("generate_chunk_payload_for_terrain") or terrain_generator.has_method("build_cache_with_generation"):
					# Use combined payload method if available
					var payload = {}
					if terrain_generator.has_method("build_cache_with_generation"):
						var snap = voxel_model.snapshot_edits_for_chunk(origin_x, origin_z, config.chunk_size) if voxel_model.has_method("snapshot_edits_for_chunk") else {"placed": {}, "removed": {}, "trees": {}}
						payload = terrain_generator.build_cache_with_generation(origin_x, origin_z, config.chunk_size, config.max_build_y, snap["placed"], snap["removed"], snap["trees"])
						var h = payload.get("height", {})
						var t = payload.get("type", {})
						if not h.is_empty():
							voxel_model.apply_chunk_gen({"height": h, "type": t})
						var tf = payload.get("tree_block_fast", {})
						var tb = payload.get("tree_blocks", [])
						if not tf.is_empty():
							voxel_model.apply_tree_chunk_for_coord(coord, {"tree_block_fast": tf, "tree_blocks": tb})
							data_chunks[coord] = true
							loaded_chunks[coord] = true
							return
				# Fallback tree gen
				if terrain_generator.has_method("generate_trees_for_chunk"):
					var tree_data = terrain_generator.generate_trees_for_chunk(origin_x, origin_z, config.chunk_size, config.chunk_size)
					voxel_model.apply_tree_chunk_for_coord(coord, tree_data)
					data_chunks[coord] = true
					loaded_chunks[coord] = true
		return

	# Data not available - generate full terrain + trees in one go reusing payload
	var size = config.chunk_size + 2
	# Use new combined generator if available to avoid double height computation
	if terrain_generator.has_method("generate_chunk_payload_for_terrain"):
		var payload = terrain_generator.generate_chunk_payload_for_terrain(origin_x -1, origin_z -1, config.chunk_size)
		voxel_model.apply_chunk_gen(payload)
		if payload.has("tree_block_fast"):
			voxel_model.apply_tree_chunk_for_coord(coord, {"tree_block_fast": payload["tree_block_fast"], "tree_blocks": payload["tree_blocks"]})
		data_chunks[coord] = true
		loaded_chunks[coord] = true
		return
	if terrain_generator.has_method("build_cache_with_generation"):
		var snap = voxel_model.snapshot_edits_for_chunk(origin_x, origin_z, config.chunk_size) if voxel_model.has_method("snapshot_edits_for_chunk") else {"placed": {}, "removed": {}, "trees": {}}
		var payload = terrain_generator.build_cache_with_generation(origin_x, origin_z, config.chunk_size, config.max_build_y, snap["placed"], snap["removed"], snap["trees"])
		var h = payload.get("height", {})
		var t = payload.get("type", {})
		if not h.is_empty():
			voxel_model.apply_chunk_gen({"height": h, "type": t})
		var tf = payload.get("tree_block_fast", {})
		var tb = payload.get("tree_blocks", [])
		if not tf.is_empty():
			voxel_model.apply_tree_chunk_for_coord(coord, {"tree_block_fast": tf, "tree_blocks": tb})
		data_chunks[coord] = true
		loaded_chunks[coord] = true
		return

	# Fallback old path
	var chunk_data = terrain_generator.generate_chunk_region(origin_x -1, origin_z -1, size, size)
	voxel_model.apply_chunk_gen(chunk_data)
	var tree_data = terrain_generator.generate_trees_for_chunk(origin_x, origin_z, config.chunk_size, config.chunk_size)
	voxel_model.apply_tree_chunk_for_coord(coord, tree_data)
	data_chunks[coord] = true
	loaded_chunks[coord] = true

func world_to_chunk(pos: Vector3) -> Vector2i:
	if config == null:
		return _ChunkCoord.world_to_chunk(pos, 20)
	return _ChunkCoord.world_to_chunk(pos, config.chunk_size)

func compute_desired_chunks(center_chunk: Vector2i) -> Array[Vector2i]:
	if config and config.infinite_world:
		return _ChunkCoord.get_chunks_in_radius_infinite(center_chunk, render_distance)
	if config == null:
		return _ChunkCoord.get_chunks_in_radius(center_chunk, render_distance, 200, 20)
	return _ChunkCoord.get_chunks_in_radius(center_chunk, render_distance, config.world_size, config.chunk_size)

func compute_unload_keep_chunks(center_chunk: Vector2i) -> Array[Vector2i]:
	if config and config.infinite_world:
		return _ChunkCoord.get_chunks_in_radius_infinite(center_chunk, unload_distance)
	if config == null:
		return _ChunkCoord.get_chunks_in_radius(center_chunk, unload_distance, 200, 20)
	return _ChunkCoord.get_chunks_in_radius(center_chunk, unload_distance, config.world_size, config.chunk_size)

func update(player_pos: Vector3, force: bool = false) -> bool:
	if not _initialized:
		return false
	var now = Time.get_ticks_msec() / 1000.0
	var center = world_to_chunk(player_pos)

	var moved = center != last_player_chunk
	var time_elapsed = now - last_update_time

	if not force and not moved:
		if not data_load_queue.is_empty() or not mesh_load_queue.is_empty() or not mesh_unload_queue.is_empty() or not data_unload_queue.is_empty() or not load_queue.is_empty() or not unload_queue.is_empty():
			return false
		if time_elapsed < update_interval and _time_accum < update_interval:
			return false
	if not moved and not force:
		if time_elapsed < update_interval:
			return false

	last_player_chunk = center
	last_update_time = now
	_time_accum = 0.0

	var desired_visible = compute_desired_chunks(center)
	var desired_keep = compute_unload_keep_chunks(center)

	var visible_set: Dictionary = {}
	for c in desired_visible:
		visible_set[c] = true
	var keep_set: Dictionary = {}
	for c in desired_keep:
		keep_set[c] = true

	# Sync data_chunks with voxel_model reality (O(visible) not O(all))
	if voxel_model and voxel_model.has_method("is_chunk_data_available"):
		# Instead of scanning all data, just ensure our data_chunks contains at least visible+keep that are already available
		for c in desired_keep:
			if not data_chunks.has(c) and voxel_model.is_chunk_data_available(c.x, c.y):
				data_chunks[c] = true
				loaded_chunks[c] = true

	# Sync visible with renderer
	if chunk_renderer:
		for k in chunk_renderer.chunk_instances.keys():
			var coord = _ChunkCoord.key_to_chunk(k)
			if coord == Vector2i(-9999, -9999):
				continue
			if not visible_chunks.has(coord):
				visible_chunks[coord] = true
			if not data_chunks.has(coord):
				data_chunks[coord] = true
				loaded_chunks[coord] = true

	# Prune obsolete from queues - cancellation for obsolete chunks
	var prune_queue = func(queue: Array[Vector2i], keep_dict: Dictionary) -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for c in queue:
			if keep_dict.has(c):
				out.append(c)
			else:
				# Cancel pending job in renderer
				if chunk_renderer:
					chunk_renderer.unload_chunk(c.x, c.y)
		return out

	# Data queues: keep = keep_set
	data_load_queue = prune_queue.call(data_load_queue, keep_set) as Array[Vector2i]
	var filtered_data_unload: Array[Vector2i] = []
	for c in data_unload_queue:
		if not keep_set.has(c):
			filtered_data_unload.append(c)
	data_unload_queue = filtered_data_unload

	# Mesh queues: visible = visible_set, but mesh unload only if outside visible (keep still)
	var filtered_mesh_load: Array[Vector2i] = []
	for c in mesh_load_queue:
		if visible_set.has(c):
			filtered_mesh_load.append(c)
		else:
			if chunk_renderer:
				chunk_renderer.unload_chunk(c.x, c.y)
	mesh_load_queue = filtered_mesh_load

	var filtered_mesh_unload: Array[Vector2i] = []
	for c in mesh_unload_queue:
		if not visible_set.has(c) and keep_set.has(c):
			filtered_mesh_unload.append(c)
	mesh_unload_queue = filtered_mesh_unload

	# Legacy queues prune
	load_queue = prune_queue.call(load_queue, visible_set) as Array[Vector2i]
	var filtered_unload: Array[Vector2i] = []
	for c in unload_queue:
		if not keep_set.has(c):
			filtered_unload.append(c)
	unload_queue = filtered_unload

	# Build data loads: keep \ data_chunks
	var new_data_loads: Array[Vector2i] = []
	for c in desired_keep:
		if data_chunks.has(c):
			continue
		if data_load_queue.has(c):
			continue
		if chunk_renderer and chunk_renderer.is_chunk_pending(c.x, c.y):
			continue
		new_data_loads.append(c)
	new_data_loads = _ChunkCoord.sort_by_distance(new_data_loads, center)
	for c in new_data_loads:
		data_load_queue.append(c)
	data_load_queue = _ChunkCoord.sort_by_distance(data_load_queue, center)

	# Build mesh loads: visible \ visible (renderer)
	var new_mesh_loads: Array[Vector2i] = []
	for c in desired_visible:
		if visible_chunks.has(c) and chunk_renderer and chunk_renderer.is_chunk_loaded(c.x, c.y):
			continue
		if mesh_load_queue.has(c):
			continue
		if data_load_queue.has(c):
			# Will be handled as combined job via data queue (gen+mesh) - skip separate mesh queue
			continue
		if chunk_renderer and chunk_renderer.is_chunk_pending(c.x, c.y):
			continue
		# Only queue mesh load if data already present (fast mesh-only)
		if data_chunks.has(c):
			new_mesh_loads.append(c)
		else:
			# Data not yet present, it will be loaded via data_load_queue as combined job
			pass
	new_mesh_loads = _ChunkCoord.sort_by_distance(new_mesh_loads, center)
	for c in new_mesh_loads:
		mesh_load_queue.append(c)

	# Mesh unload: rendered but outside visible and inside keep -> unrender only
	var new_mesh_unloads: Array[Vector2i] = []
	for k in visible_chunks.keys():
		var coord = k as Vector2i
		if not visible_set.has(coord) and keep_set.has(coord):
			if not mesh_unload_queue.has(coord):
				new_mesh_unloads.append(coord)
	for c in new_mesh_unloads:
		mesh_unload_queue.append(c)

	# Data unload: data present but outside keep -> remove data + cached mesh
	var new_data_unloads: Array[Vector2i] = []
	for k in data_chunks.keys():
		var coord = k as Vector2i
		if not keep_set.has(coord):
			if not data_unload_queue.has(coord):
				new_data_unloads.append(coord)
	# Also renderer instances outside keep
	if chunk_renderer:
		for k in chunk_renderer.chunk_instances.keys():
			var coord = _ChunkCoord.key_to_chunk(k)
			if coord == Vector2i(-9999, -9999):
				continue
			if not keep_set.has(coord) and not data_unload_queue.has(coord) and data_chunks.has(coord):
				new_data_unloads.append(coord)
	for c in new_data_unloads:
		if not data_unload_queue.has(c):
			data_unload_queue.append(c)
	data_unload_queue.sort_custom(func(a,b): return _ChunkCoord.euclidean_distance(a, center) > _ChunkCoord.euclidean_distance(b, center))

	# Legacy load queue for visible (for backwards compat with old world_controller)
	var new_loads: Array[Vector2i] = []
	for c in desired_visible:
		if data_chunks.has(c) and visible_chunks.has(c):
			continue
		if load_queue.has(c):
			continue
		if data_load_queue.has(c) or mesh_load_queue.has(c):
			continue
		if chunk_renderer and (chunk_renderer.is_chunk_loaded(c.x, c.y) or chunk_renderer.is_chunk_pending(c.x, c.y)):
			continue
		if desired_visible.has(c) and not data_chunks.has(c):
			# Will be loaded via data queue as combined, not legacy
			continue
		new_loads.append(c)
	new_loads = _ChunkCoord.sort_by_distance(new_loads, center)
	for c in new_loads:
		load_queue.append(c)

	if new_data_loads.size() > 0 or new_mesh_loads.size() > 0 or new_mesh_unloads.size() > 0 or new_data_unloads.size() > 0 or moved:
		print("[ChunkManager] Visible %d Keep %d | data_load +%d (%d) mesh_load +%d (%d) mesh_unload %d data_unload %d | data %d visible %d" % [
			desired_visible.size(), desired_keep.size(), new_data_loads.size(), data_load_queue.size(), new_mesh_loads.size(), mesh_load_queue.size(), new_mesh_unloads.size(), new_data_unloads.size(), data_chunks.size(), visible_chunks.size()
		])
		streaming_updated.emit(get_stats())

	return true

func process_queues(p_max_loads: int = -1, p_max_unloads: int = -1) -> Dictionary:
	if not _initialized or chunk_renderer == null:
		return {"loaded":0, "unloaded":0}
	if p_max_loads == -1:
		p_max_loads = max_loads_per_frame
	if p_max_unloads == -1:
		p_max_unloads = max_unloads_per_frame

	var loaded_now = 0
	var unloaded_now = 0

	# 1) Mesh unload for padding ring - unrender only, keep data (separate visible vs cached)
	var to_mesh_unload = min(p_max_unloads, mesh_unload_queue.size())
	for i in range(to_mesh_unload):
		if mesh_unload_queue.is_empty():
			break
		var coord = mesh_unload_queue[0]
		mesh_unload_queue.remove_at(0)
		if chunk_renderer.has_method("unload_render_only"):
			chunk_renderer.unload_render_only(coord.x, coord.y)
		else:
			chunk_renderer.unload_chunk(coord.x, coord.y)
		visible_chunks.erase(coord)
		unloaded_now += 1
		chunk_unloaded.emit(coord)

	# 2) Data load - one per frame (bounded), combined gen+trees+snapshot+mesh in one background pool
	# Visible chunks: combined job (data+mesh), keep padding: data-only job (no mesh) to keep visible vs cached separate
	var to_data_load = min(p_max_loads, data_load_queue.size())
	for i in range(to_data_load):
		if data_load_queue.is_empty():
			break
		var coord = data_load_queue[0]
		data_load_queue.remove_at(0)
		if data_chunks.has(coord) and voxel_model.is_chunk_data_available(coord.x, coord.y):
			continue
		if chunk_renderer.is_chunk_pending(coord.x, coord.y):
			continue

		# Determine if this chunk should be visible (rendered) or just cached
		var is_visible = _ChunkCoord.euclidean_distance(coord, last_player_chunk) <= float(render_distance) + 0.5

		if use_async:
			var queued = false
			if is_visible:
				if chunk_renderer.has_method("rebuild_async_combined"):
					queued = chunk_renderer.rebuild_async_combined(coord.x, coord.y)
					if not queued:
						queued = chunk_renderer.rebuild_async(coord.x, coord.y)
				else:
					queued = chunk_renderer.rebuild_async(coord.x, coord.y)
			else:
				# Keep padding: data-only (terrain+trees) no mesh to separate visible vs cached
				if chunk_renderer.has_method("rebuild_async_data_only"):
					queued = chunk_renderer.rebuild_async_data_only(coord.x, coord.y)
				else:
					# Fallback to combined if data-only not available (will be unrendered via cache)
					if chunk_renderer.has_method("rebuild_async_combined"):
						queued = chunk_renderer.rebuild_async_combined(coord.x, coord.y)
			if queued:
				total_loads += 1
				loaded_now += 1
				chunk_loaded.emit(coord)
			else:
				ensure_terrain_for_chunk(coord)
				if is_visible:
					chunk_renderer.rebuild_immediate(coord.x, coord.y)
					visible_chunks[coord] = true
				data_chunks[coord] = true
				loaded_chunks[coord] = true
				total_loads += 1
				loaded_now += 1
				chunk_loaded.emit(coord)
		else:
			ensure_terrain_for_chunk(coord)
			if is_visible:
				chunk_renderer.rebuild_immediate(coord.x, coord.y)
				visible_chunks[coord] = true
			data_chunks[coord] = true
			loaded_chunks[coord] = true
			total_loads += 1
			loaded_now += 1
			chunk_loaded.emit(coord)

	# 3) Mesh load for visible chunks whose data already exists (mesh-only, fast)
	var to_mesh_load = min(p_max_loads, mesh_load_queue.size())
	for i in range(to_mesh_load):
		if mesh_load_queue.is_empty():
			break
		var coord = mesh_load_queue[0]
		mesh_load_queue.remove_at(0)
		if chunk_renderer.is_chunk_loaded(coord.x, coord.y):
			visible_chunks[coord] = true
			continue
		if chunk_renderer.is_chunk_pending(coord.x, coord.y):
			continue
		if use_async:
			var queued = chunk_renderer.rebuild_async(coord.x, coord.y)
			if queued:
				total_loads += 1
				loaded_now += 1
				chunk_loaded.emit(coord)
			else:
				chunk_renderer.rebuild_immediate(coord.x, coord.y)
				visible_chunks[coord] = true
				total_loads += 1
				loaded_now += 1
				chunk_loaded.emit(coord)
		else:
			chunk_renderer.rebuild_immediate(coord.x, coord.y)
			visible_chunks[coord] = true
			total_loads += 1
			loaded_now += 1
			chunk_loaded.emit(coord)

	# 4) Data unload for outside keep - remove terrain data + cached mesh, chunk-level LRU
	var to_data_unload = min(p_max_unloads, data_unload_queue.size())
	for i in range(to_data_unload):
		if data_unload_queue.is_empty():
			break
		var coord = data_unload_queue[0]
		data_unload_queue.remove_at(0)
		# Cancel any pending jobs
		if chunk_renderer.is_chunk_pending(coord.x, coord.y):
			chunk_renderer.unload_chunk(coord.x, coord.y)
		if chunk_renderer.has_method("unload_chunk"):
			chunk_renderer.unload_chunk(coord.x, coord.y)
		voxel_model.unload_chunk_data(coord.x, coord.y)
		data_chunks.erase(coord)
		loaded_chunks.erase(coord)
		visible_chunks.erase(coord)
		total_unloads += 1
		unloaded_now += 1
		chunk_unloaded.emit(coord)

	# Legacy queues for backward compat
	var to_load = min(p_max_loads, load_queue.size())
	for i in range(to_load):
		if load_queue.is_empty():
			break
		var coord = load_queue[0]
		load_queue.remove_at(0)
		if chunk_renderer.is_chunk_loaded(coord.x, coord.y):
			visible_chunks[coord] = true
			data_chunks[coord] = true
			loaded_chunks[coord] = true
			continue
		if chunk_renderer.is_chunk_pending(coord.x, coord.y):
			continue
		# For legacy visible loads without data, use combined
		if not data_chunks.has(coord):
			ensure_terrain_for_chunk(coord)
		if use_async:
			var queued = chunk_renderer.rebuild_async(coord.x, coord.y)
			if queued:
				total_loads += 1
				loaded_now += 1
				chunk_loaded.emit(coord)
		else:
			chunk_renderer.rebuild_immediate(coord.x, coord.y)
			data_chunks[coord] = true
			loaded_chunks[coord] = true
			visible_chunks[coord] = true
			total_loads += 1
			loaded_now += 1
			chunk_loaded.emit(coord)

	var to_unload = min(p_max_unloads, unload_queue.size())
	for i in range(to_unload):
		if unload_queue.is_empty():
			break
		var coord = unload_queue[0]
		unload_queue.remove_at(0)
		if not chunk_renderer.is_chunk_loaded(coord.x, coord.y):
			data_chunks.erase(coord)
			loaded_chunks.erase(coord)
			visible_chunks.erase(coord)
			voxel_model.unload_chunk_data(coord.x, coord.y)
			continue
		chunk_renderer.unload_chunk(coord.x, coord.y)
		voxel_model.unload_chunk_data(coord.x, coord.y)
		data_chunks.erase(coord)
		loaded_chunks.erase(coord)
		visible_chunks.erase(coord)
		total_unloads += 1
		unloaded_now += 1
		chunk_unloaded.emit(coord)

	return {"loaded": loaded_now, "unloaded": unloaded_now}

func ensure_chunks_around(pos: Vector3) -> int:
	if not _initialized:
		return 0
	var center = world_to_chunk(pos)
	var desired_keep = compute_unload_keep_chunks(center)
	var desired_visible = compute_desired_chunks(center)
	desired_keep = _ChunkCoord.sort_by_distance(desired_keep, center)
	desired_visible = _ChunkCoord.sort_by_distance(desired_visible, center)
	var count = 0

	# First ensure data for keep area (no mesh yet)
	for coord in desired_keep:
		if data_chunks.has(coord) and voxel_model.is_chunk_data_available(coord.x, coord.y):
			continue
		ensure_terrain_for_chunk(coord)
		data_chunks[coord] = true
		loaded_chunks[coord] = true
	# Then ensure visible meshes immediate
	for coord in desired_visible:
		if chunk_renderer.is_chunk_loaded(coord.x, coord.y):
			visible_chunks[coord] = true
			continue
		chunk_renderer.rebuild_immediate(coord.x, coord.y)
		visible_chunks[coord] = true
		data_chunks[coord] = true
		loaded_chunks[coord] = true
		total_loads += 1
		count += 1
	last_player_chunk = center
	last_update_time = Time.get_ticks_msec() / 1000.0
	_time_accum = 0.0
	data_load_queue.clear()
	mesh_load_queue.clear()
	mesh_unload_queue.clear()
	data_unload_queue.clear()
	load_queue.clear()
	unload_queue.clear()
	print("[ChunkManager] ensure_chunks_around visible %d keep %d immediate %d total data %d visible %d" % [desired_visible.size(), desired_keep.size(), count, data_chunks.size(), visible_chunks.size()])
	return count

func tick(delta: float, player_pos: Vector3 = Vector3.INF) -> Dictionary:
	_time_accum += delta
	var pos = player_pos
	if pos == Vector3.INF:
		if player_ref and is_instance_valid(player_ref):
			pos = player_ref.global_position
		else:
			return process_queues()
	update(pos)
	return process_queues()

func clear():
	data_chunks.clear()
	visible_chunks.clear()
	loaded_chunks.clear()
	data_load_queue.clear()
	mesh_load_queue.clear()
	mesh_unload_queue.clear()
	data_unload_queue.clear()
	load_queue.clear()
	unload_queue.clear()
	last_player_chunk = Vector2i(-99999, -99999)
	_time_accum = 0.0
	last_update_time = 0.0
	if chunk_renderer:
		chunk_renderer.clear()
	total_loads = 0
	total_unloads = 0
	print("[ChunkManager] Cleared all")

func force_unload_all():
	for coord in data_chunks.keys():
		if chunk_renderer.is_chunk_loaded(coord.x, coord.y):
			chunk_renderer.unload_chunk(coord.x, coord.y)
		voxel_model.unload_chunk_data(coord.x, coord.y)
	data_chunks.clear()
	visible_chunks.clear()
	loaded_chunks.clear()
	data_load_queue.clear()
	mesh_load_queue.clear()
	mesh_unload_queue.clear()
	data_unload_queue.clear()
	load_queue.clear()
	unload_queue.clear()

func get_loaded_count() -> int:
	return data_chunks.size()

func is_chunk_loaded(coord: Vector2i) -> bool:
	return data_chunks.has(coord)

func is_visible_loaded(coord: Vector2i) -> bool:
	return visible_chunks.has(coord)

func get_stats() -> Dictionary:
	return {
		"render_distance": render_distance,
		"unload_distance": unload_distance,
		"loaded": data_chunks.size(),
		"visible": visible_chunks.size(),
		"load_queue": load_queue.size(),
		"data_load_queue": data_load_queue.size(),
		"mesh_load_queue": mesh_load_queue.size(),
		"mesh_unload_queue": mesh_unload_queue.size(),
		"data_unload_queue": data_unload_queue.size(),
		"unload_queue": unload_queue.size(),
		"total_loads": total_loads,
		"total_unloads": total_unloads,
		"last_player_chunk": last_player_chunk,
		"max_loads_per_frame": max_loads_per_frame,
		"max_unloads_per_frame": max_unloads_per_frame,
		"interval": update_interval,
	}
