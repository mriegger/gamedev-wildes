extends RefCounted
class_name ChunkManager

signal chunk_loaded(coord: Vector2i)
signal chunk_unloaded(coord: Vector2i)

var data_chunks: Dictionary = {}
var visible_chunks: Dictionary = {}
var _last_player_chunk: Vector2i

var _config: WorldConfig
var _voxel_model: VoxelWorld
var _scheduler: ChunkBuildScheduler
var _renderer: ChunkRenderer

var _data_load_queue: Array[Vector2i] = []
var _mesh_load_queue: Array[Vector2i] = []
var _data_unload_queue: Array[Vector2i] = []
var _dirty_chunks: Dictionary = {}
var _initial_load_queue: Array[Vector2i] = []
var _requested_meshes: Dictionary = {}
var _requested_terrain: Dictionary = {}
var _rebuilding_meshes: Dictionary = {}

var _render_distance: int
var _unload_distance: int
var _max_loads_per_frame: int
var _max_unloads_per_frame: int
var _visible_set: Dictionary = {}
var _keep_set: Dictionary = {}

func setup(p_config: WorldConfig, p_voxel_model: VoxelWorld, p_scheduler: ChunkBuildScheduler, p_renderer: ChunkRenderer):
	_config = p_config
	_voxel_model = p_voxel_model
	_scheduler = p_scheduler
	_renderer = p_renderer
	_render_distance = _config.render_distance
	_unload_distance = _config.render_distance + _config.unload_padding
	_max_loads_per_frame = _config.max_chunk_loads_per_frame
	_max_unloads_per_frame = _config.max_chunk_unloads_per_frame
	_clear_tracking()
	_voxel_model.configure_terrain_cache(_render_distance, _config.unload_padding)
	_voxel_model.terrain_chunk_evicted.connect(_on_terrain_evicted)

func tick(player_pos: Vector3):
	var current_chunk := ChunkCoord.world_to_chunk(player_pos, _config.chunk_size)
	if current_chunk != _last_player_chunk:
		_recompute_streaming(current_chunk)
	_promote_generated_terrain()
	_process_data_loads()
	_process_mesh_loads()
	_process_unloads()
	_flush_dirty()

func poll_completed():
	var results := _scheduler.take_completed(_max_loads_per_frame, _max_loads_per_frame)
	for result in results:
		if result.terrain_only:
			_requested_terrain.erase(result.coord)
			if not _keep_set.has(result.coord):
				continue
		else:
			_requested_terrain.erase(result.coord)
			_rebuilding_meshes.erase(result.coord)
		_renderer.apply_result(result)
		data_chunks[result.coord] = true
		if not result.terrain_only and _requested_meshes.has(result.coord):
			_requested_meshes.erase(result.coord)
			if _visible_set.has(result.coord):
				_mark_visible_ready(result.coord)

func begin_initial_load(pos: Vector3) -> int:
	var center := ChunkCoord.world_to_chunk(pos, _config.chunk_size)
	var desired_visible := ChunkCoord.get_chunks_in_radius_infinite(center, _render_distance)
	var desired_keep := ChunkCoord.get_chunks_in_radius_infinite(center, _unload_distance)
	_visible_set = _to_set(desired_visible)
	_keep_set = _to_set(desired_keep)
	_last_player_chunk = center
	_initial_load_queue.clear()
	for coord in ChunkCoord.sort_by_distance(desired_visible, center):
		_initial_load_queue.append(coord)
	_data_load_queue.clear()
	for coord in ChunkCoord.sort_by_distance(desired_keep, center):
		if _visible_set.has(coord):
			continue
		_data_load_queue.append(coord)
	return _initial_load_queue.size()

func step_initial_load():
	var coord := _initial_load_queue.pop_front() as Vector2i
	_renderer.apply_result(_scheduler.build_now(coord))
	_mark_visible_ready(coord)

func queue_rebuild_for_world_pos(pos: Vector3i):
	var coord := ChunkCoord.world_to_chunk_vec3i(pos, _config.chunk_size)
	_queue_rebuild(coord)
	if pos.x % _config.chunk_size == 0:
		_queue_rebuild(coord + Vector2i.LEFT)
	if (pos.x + 1) % _config.chunk_size == 0:
		_queue_rebuild(coord + Vector2i.RIGHT)
	if pos.z % _config.chunk_size == 0:
		_queue_rebuild(coord + Vector2i(0, -1))
	if (pos.z + 1) % _config.chunk_size == 0:
		_queue_rebuild(coord + Vector2i(0, 1))

func shutdown():
	_voxel_model.terrain_chunk_evicted.disconnect(_on_terrain_evicted)
	_clear_tracking()
	_scheduler.shutdown()
	_renderer.clear()

func _recompute_streaming(current_chunk: Vector2i):
	var desired_visible := ChunkCoord.get_chunks_in_radius_infinite(current_chunk, _render_distance)
	var desired_keep := ChunkCoord.get_chunks_in_radius_infinite(current_chunk, _unload_distance)
	_visible_set = _to_set(desired_visible)
	_keep_set = _to_set(desired_keep)
	_last_player_chunk = current_chunk

	for coord in _requested_meshes.keys():
		if not _visible_set.has(coord):
			_cancel_and_unload(coord)
	for coord in _requested_terrain.keys():
		if not _keep_set.has(coord):
			_requested_terrain.erase(coord)
			_scheduler.cancel(coord)

	_data_load_queue = _prune_load_queue(_data_load_queue, _keep_set)
	var retained_data_loads: Array[Vector2i] = []
	for coord in _data_load_queue:
		if not visible_chunks.has(coord):
			retained_data_loads.append(coord)
	_data_load_queue = retained_data_loads

	var retained_unloads: Array[Vector2i] = []
	for coord in _data_unload_queue:
		if not _keep_set.has(coord):
			retained_unloads.append(coord)
	_data_unload_queue = retained_unloads

	var retained_mesh_loads: Array[Vector2i] = []
	for coord in _mesh_load_queue:
		if _visible_set.has(coord):
			retained_mesh_loads.append(coord)
		else:
			_cancel_and_unload(coord)
	_mesh_load_queue = retained_mesh_loads

	var queued_data := _to_set(_data_load_queue)
	var new_data_loads: Array[Vector2i] = []
	for coord in desired_keep:
		if _visible_set.has(coord) or data_chunks.has(coord) or queued_data.has(coord) or _requested_terrain.has(coord):
			continue
		new_data_loads.append(coord)
	_data_load_queue.append_array(ChunkCoord.sort_by_distance(new_data_loads, current_chunk))

	var queued_meshes := _to_set(_mesh_load_queue)
	var new_mesh_loads: Array[Vector2i] = []
	for coord in desired_visible:
		if visible_chunks.has(coord) or _requested_meshes.has(coord) or queued_meshes.has(coord):
			continue
		new_mesh_loads.append(coord)
	_mesh_load_queue.append_array(ChunkCoord.sort_by_distance(new_mesh_loads, current_chunk))

	var queued_unloads := _to_set(_data_unload_queue)
	for coord in data_chunks.keys():
		if not _keep_set.has(coord) and not queued_unloads.has(coord):
			_data_unload_queue.append(coord)

	for coord in visible_chunks.keys():
		if _visible_set.has(coord):
			continue
		_cancel_and_unload(coord)
		visible_chunks.erase(coord)
		chunk_unloaded.emit(coord)

func _promote_generated_terrain():
	for coord in _keep_set.keys():
		if not data_chunks.has(coord) and _voxel_model.is_chunk_data_available(coord.x, coord.y):
			data_chunks[coord] = true

func _process_data_loads():
	var processed := 0
	var loads := 0
	while loads < _max_loads_per_frame and processed < _data_load_queue.size():
		var coord := _data_load_queue[processed]
		processed += 1
		if not _keep_set.has(coord):
			continue
		if _voxel_model.is_chunk_data_available(coord.x, coord.y):
			data_chunks[coord] = true
			loads += 1
			continue
		if _scheduler.queue_terrain(coord):
			_requested_terrain[coord] = true
		loads += 1
	if processed > 0:
		_data_load_queue = _data_load_queue.slice(processed) as Array[Vector2i]

func _process_mesh_loads():
	var processed := 0
	var loads := 0
	while loads < _max_loads_per_frame and processed < _mesh_load_queue.size():
		var coord := _mesh_load_queue[processed]
		processed += 1
		if not _visible_set.has(coord):
			continue
		var data_available := _voxel_model.is_chunk_data_available(coord.x, coord.y)
		if data_available and _renderer.restore_cached(coord):
			_mark_visible_ready(coord)
		else:
			_requested_meshes[coord] = true
			if _scheduler.queue_mesh(coord):
				_requested_terrain.erase(coord)
		loads += 1
	if processed > 0:
		_mesh_load_queue = _mesh_load_queue.slice(processed) as Array[Vector2i]

func _process_unloads():
	var processed := 0
	var unloads := 0
	while unloads < _max_unloads_per_frame and processed < _data_unload_queue.size():
		var coord := _data_unload_queue[processed]
		processed += 1
		if _keep_set.has(coord):
			continue
		if data_chunks.has(coord):
			var was_visible := visible_chunks.has(coord)
			data_chunks.erase(coord)
			visible_chunks.erase(coord)
			_cancel_and_unload(coord)
			unloads += 1
			if was_visible:
				chunk_unloaded.emit(coord)
	if processed > 0:
		_data_unload_queue = _data_unload_queue.slice(processed) as Array[Vector2i]

func _flush_dirty():
	if _dirty_chunks.is_empty():
		return
	var coord := _dirty_chunks.keys()[0] as Vector2i
	if _scheduler.replace_mesh(coord):
		_dirty_chunks.erase(coord)
		_rebuilding_meshes[coord] = true

func _queue_rebuild(coord: Vector2i):
	_renderer.invalidate_cache(coord)
	if visible_chunks.has(coord) or _requested_meshes.has(coord):
		_dirty_chunks[coord] = true

func _on_terrain_evicted(coord: Vector2i):
	var was_visible := visible_chunks.has(coord)
	data_chunks.erase(coord)
	visible_chunks.erase(coord)
	_cancel_and_unload(coord)
	_renderer.invalidate_cache(coord)
	if was_visible:
		chunk_unloaded.emit(coord)
	if _keep_set.has(coord):
		if _visible_set.has(coord) or was_visible:
			_append_unique(_mesh_load_queue, coord)
		else:
			_append_unique(_data_load_queue, coord)

func _prune_load_queue(queue: Array[Vector2i], keep: Dictionary) -> Array[Vector2i]:
	var retained: Array[Vector2i] = []
	for coord in queue:
		if keep.has(coord):
			retained.append(coord)
		else:
			_cancel_and_unload(coord)
	return retained

func _cancel_and_unload(coord: Vector2i):
	var discard_cached_mesh := _dirty_chunks.has(coord) or _rebuilding_meshes.has(coord)
	_requested_meshes.erase(coord)
	_requested_terrain.erase(coord)
	_dirty_chunks.erase(coord)
	_rebuilding_meshes.erase(coord)
	_scheduler.cancel(coord)
	_renderer.unload(coord)
	if discard_cached_mesh:
		_renderer.invalidate_cache(coord)

func _mark_visible_ready(coord: Vector2i):
	data_chunks[coord] = true
	if visible_chunks.has(coord):
		return
	visible_chunks[coord] = true
	chunk_loaded.emit(coord)

func _append_unique(queue: Array[Vector2i], coord: Vector2i):
	if not queue.has(coord):
		queue.append(coord)

func _to_set(coords: Array) -> Dictionary:
	var result: Dictionary = {}
	for coord in coords:
		result[coord] = true
	return result

func _clear_tracking():
	data_chunks.clear()
	visible_chunks.clear()
	_data_load_queue.clear()
	_mesh_load_queue.clear()
	_data_unload_queue.clear()
	_dirty_chunks.clear()
	_initial_load_queue.clear()
	_requested_meshes.clear()
	_requested_terrain.clear()
	_rebuilding_meshes.clear()
	_visible_set.clear()
	_keep_set.clear()
