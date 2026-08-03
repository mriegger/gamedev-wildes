extends RefCounted
class_name ChunkManager

signal chunk_loaded(coord: Vector2i)
signal chunk_unloaded(coord: Vector2i)

var config: WorldConfig
var voxel_model: VoxelWorld
var chunk_renderer: ChunkRenderSystem
var terrain_generator: TerrainGenerator

var player_ref: Node3D = null

var data_chunks: Dictionary = {}
var visible_chunks: Dictionary = {}

var data_load_queue: Array[Vector2i] = []
var mesh_load_queue: Array[Vector2i] = []
var data_unload_queue: Array[Vector2i] = []

var render_distance: int = 4
var unload_distance: int = 6
var max_loads_per_frame: int = 1
var max_unloads_per_frame: int = 4

var last_player_chunk: Vector2i = Vector2i(-99999, -99999)

var _last_visible_set: Dictionary = {}
var _last_keep_set: Dictionary = {}

var _initialized: bool = false

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
	data_chunks.clear()
	visible_chunks.clear()
	data_load_queue.clear()
	mesh_load_queue.clear()
	data_unload_queue.clear()
	last_player_chunk = Vector2i(-99999, -99999)
	_initialized = true
	if voxel_model:
		voxel_model.configure_terrain_cache(render_distance, config.unload_padding if config else 2)
		if voxel_model.has_signal("terrain_chunk_evicted"):
			if not voxel_model.terrain_chunk_evicted.is_connected(_on_terrain_evicted):
				voxel_model.terrain_chunk_evicted.connect(_on_terrain_evicted)
	if chunk_renderer and terrain_generator:
		chunk_renderer.set_terrain_generator(terrain_generator)

func _on_terrain_evicted(coord: Vector2i):
	if _last_keep_set.has(coord):
		data_chunks.erase(coord)
		var was_visible = visible_chunks.has(coord)
		visible_chunks.erase(coord)
		if chunk_renderer:
			chunk_renderer.unload_render_only(coord.x, coord.y)
		var already_data = false
		for q in data_load_queue:
			if q == coord:
				already_data = true
				break
		if not already_data:
			data_load_queue.append(coord)
		if _last_visible_set.has(coord) or was_visible:
			var already_mesh = false
			for q in mesh_load_queue:
				if q == coord:
					already_mesh = true
					break
			if not already_mesh:
				mesh_load_queue.append(coord)
		return
	if data_chunks.has(coord):
		data_chunks.erase(coord)
		visible_chunks.erase(coord)
		if chunk_renderer:
			chunk_renderer.unload_render_only(coord.x, coord.y)

func set_player_ref(p_player: Node3D):
	player_ref = p_player

func ensure_terrain_for_chunk(coord: Vector2i):
	if not config:
		return
	if not terrain_generator or not voxel_model:
		return
	var origin_x = coord.x * config.chunk_size
	var origin_z = coord.y * config.chunk_size
	if data_chunks.has(coord) or voxel_model.is_chunk_data_available(coord.x, coord.y):
		data_chunks[coord] = true
		if not voxel_model.has_trees_in_chunk(coord.x, coord.y):
			var snap = voxel_model.snapshot_edits_for_chunk(origin_x, origin_z, config.chunk_size)
			var payload = terrain_generator.build_cache_with_generation(origin_x, origin_z, config.chunk_size, config.max_build_y, snap["placed"], snap["removed"], snap["trees"])
			var h = payload.get("height", {})
			var t = payload.get("type", {})
			if not h.is_empty():
				voxel_model.apply_chunk_gen({"height": h, "type": t})
			var tf = payload.get("tree_block_fast", {})
			voxel_model.apply_tree_chunk_for_coord(coord, {"tree_block_fast": tf})
			data_chunks[coord] = true
		return
	var payload = terrain_generator.generate_chunk_payload_for_terrain(origin_x, origin_z, config.chunk_size)
	voxel_model.apply_chunk_gen(payload)
	if payload.has("tree_block_fast"):
		voxel_model.apply_tree_chunk_for_coord(coord, {"tree_block_fast": payload["tree_block_fast"]})
	data_chunks[coord] = true

func world_to_chunk(pos: Vector3) -> Vector2i:
	if config == null:
		return ChunkCoord.world_to_chunk(pos, 20)
	return ChunkCoord.world_to_chunk(pos, config.chunk_size)

func compute_desired_chunks(center_chunk: Vector2i) -> Array[Vector2i]:
	return ChunkCoord.get_chunks_in_radius_infinite(center_chunk, render_distance)

func compute_unload_keep_chunks(center_chunk: Vector2i) -> Array[Vector2i]:
	return ChunkCoord.get_chunks_in_radius_infinite(center_chunk, unload_distance)

func tick(_delta: float, player_pos: Vector3 = Vector3.INF) -> bool:
	return update(player_pos, false)

func update(player_pos: Vector3, force: bool = false) -> bool:
	if not _initialized:
		return false
	if config == null or voxel_model == null or chunk_renderer == null:
		return false

	var current_chunk = world_to_chunk(player_pos)
	var moved = current_chunk != last_player_chunk or force

	if moved or force or _last_visible_set.is_empty():
		var desired_visible = compute_desired_chunks(current_chunk)
		var desired_keep = compute_unload_keep_chunks(current_chunk)

		var visible_set: Dictionary = {}
		for c in desired_visible:
			visible_set[c] = true
		var keep_set: Dictionary = {}
		for c in desired_keep:
			keep_set[c] = true

		_last_visible_set = visible_set
		_last_keep_set = keep_set

		last_player_chunk = current_chunk

		if voxel_model:
			for c in desired_keep:
				if not data_chunks.has(c) and voxel_model.is_chunk_data_available(c.x, c.y):
					data_chunks[c] = true

		if chunk_renderer:
			for k in chunk_renderer.chunk_instances.keys():
				var coord = ChunkCoord.key_to_chunk(k)
				if coord == Vector2i(-9999, -9999):
					continue
				if not visible_chunks.has(coord):
					visible_chunks[coord] = true
				if not data_chunks.has(coord):
					data_chunks[coord] = true

		var prune_queue = func(queue: Array[Vector2i], keep_dict: Dictionary) -> Array[Vector2i]:
			var out: Array[Vector2i] = []
			for c in queue:
				if keep_dict.has(c):
					out.append(c)
				else:
					if chunk_renderer:
						chunk_renderer.unload_chunk(c.x, c.y)
			return out

		data_load_queue = prune_queue.call(data_load_queue, keep_set) as Array[Vector2i]
		var filtered_data_load: Array[Vector2i] = []
		for c in data_load_queue:
			if not visible_chunks.has(c):
				filtered_data_load.append(c)
		data_load_queue = filtered_data_load
		var filtered_data_unload: Array[Vector2i] = []
		for c in data_unload_queue:
			if not keep_set.has(c):
				filtered_data_unload.append(c)
		data_unload_queue = filtered_data_unload

		var filtered_mesh_load: Array[Vector2i] = []
		for c in mesh_load_queue:
			if visible_set.has(c):
				filtered_mesh_load.append(c)
			else:
				if chunk_renderer:
					chunk_renderer.unload_chunk(c.x, c.y)
		mesh_load_queue = filtered_mesh_load

		var data_load_set: Dictionary = {}
		for q in data_load_queue:
			data_load_set[q] = true
		var new_data_loads: Array[Vector2i] = []
		for c in desired_keep:
			if visible_set.has(c):
				continue
			if not data_chunks.has(c) and not visible_chunks.has(c):
				if data_load_set.has(c):
					continue
				new_data_loads.append(c)
		new_data_loads = ChunkCoord.sort_by_distance(new_data_loads, current_chunk)
		data_load_queue.append_array(new_data_loads)

		var mesh_load_set: Dictionary = {}
		for q in mesh_load_queue:
			mesh_load_set[q] = true
		var new_mesh_loads: Array[Vector2i] = []
		for c in desired_visible:
			if not visible_chunks.has(c):
				if mesh_load_set.has(c):
					continue
				new_mesh_loads.append(c)
		new_mesh_loads = ChunkCoord.sort_by_distance(new_mesh_loads, current_chunk)
		mesh_load_queue.append_array(new_mesh_loads)

		var unload_set: Dictionary = {}
		for q in data_unload_queue:
			unload_set[q] = true
		var new_data_unloads: Array[Vector2i] = []
		for c in data_chunks.keys():
			if not keep_set.has(c):
				if unload_set.has(c):
					continue
				new_data_unloads.append(c)
		data_unload_queue.append_array(new_data_unloads)

		for c in visible_chunks.keys():
			if not visible_set.has(c):
				if chunk_renderer:
					chunk_renderer.unload_render_only(c.x, c.y)
				visible_chunks.erase(c)
				chunk_unloaded.emit(c)

	var visible_set = _last_visible_set
	var keep_set = _last_keep_set

	var processed_data = 0
	var loads_done = 0
	while loads_done < max_loads_per_frame and processed_data < data_load_queue.size():
		var coord = data_load_queue[processed_data]
		processed_data += 1
		if not keep_set.is_empty() and not keep_set.has(coord):
			continue
		ensure_terrain_for_chunk(coord)
		data_chunks[coord] = true
		loads_done += 1
	if processed_data > 0:
		data_load_queue = data_load_queue.slice(processed_data) as Array[Vector2i]

	var processed_mesh = 0
	loads_done = 0
	while loads_done < max_loads_per_frame and processed_mesh < mesh_load_queue.size():
		var coord = mesh_load_queue[processed_mesh]
		processed_mesh += 1
		if not visible_set.is_empty() and not visible_set.has(coord):
			continue
		if chunk_renderer:
			var ok = chunk_renderer.rebuild_async_combined(coord.x, coord.y)
			if ok:
				visible_chunks[coord] = true
				data_chunks[coord] = true
				chunk_loaded.emit(coord)
				loads_done += 1
			else:
				if chunk_renderer.is_chunk_loaded(coord.x, coord.y):
					visible_chunks[coord] = true
					chunk_loaded.emit(coord)
	if processed_mesh > 0:
		mesh_load_queue = mesh_load_queue.slice(processed_mesh) as Array[Vector2i]

	var processed_unload = 0
	var unloads_done = 0
	while unloads_done < max_unloads_per_frame and processed_unload < data_unload_queue.size():
		var coord = data_unload_queue[processed_unload]
		processed_unload += 1
		if not keep_set.is_empty() and keep_set.has(coord):
			continue
		if data_chunks.has(coord):
			data_chunks.erase(coord)
			visible_chunks.erase(coord)
			if chunk_renderer:
				chunk_renderer.unload_chunk(coord.x, coord.y)
			unloads_done += 1
			chunk_unloaded.emit(coord)
	if processed_unload > 0:
		data_unload_queue = data_unload_queue.slice(processed_unload) as Array[Vector2i]

	return moved or force

func ensure_chunks_around(pos: Vector3, immediate: bool = false) -> int:
	if not _initialized:
		return 0
	var center = world_to_chunk(pos)
	var desired_visible = compute_desired_chunks(center)
	var desired_keep = compute_unload_keep_chunks(center)
	var count = 0
	var visible_set: Dictionary = {}
	for c in desired_visible:
		visible_set[c] = true
	if immediate and chunk_renderer:
		for c in desired_visible:
			if not visible_chunks.has(c):
				chunk_renderer.rebuild_immediate(c.x, c.y)
				visible_chunks[c] = true
				data_chunks[c] = true
				count += 1
	for c in desired_keep:
		if visible_set.has(c):
			continue
		if not data_chunks.has(c):
			ensure_terrain_for_chunk(c)
			data_chunks[c] = true
			count += 1
	return count

func is_chunk_loaded(coord: Vector2i) -> bool:
	return visible_chunks.has(coord) or data_chunks.has(coord)

func clear():
	data_chunks.clear()
	visible_chunks.clear()
	data_load_queue.clear()
	mesh_load_queue.clear()
	data_unload_queue.clear()
	last_player_chunk = Vector2i(-99999, -99999)
	if chunk_renderer:
		chunk_renderer.clear()
