extends Node3D
class_name WorldController

## WorldController - coordinates generation, model, rendering
## Supports sync (direct launch) and async (loading screen with progress bar)
## Now with chunk streaming: only nearby chunks loaded, far chunks deloaded

signal generation_progress(stage: String, percent: float, details: String)

const ChunkCoord = preload("res://world/streaming/chunk_coord.gd")
const ChunkManager = preload("res://world/streaming/chunk_manager.gd")

@export var config: WorldConfig

@export var auto_generate_on_ready: bool = true

var seed_override: int = -1
var pending_save_data: Dictionary = {}

var max_build_y: int:
	get: return config.max_build_y if config else 36
var world_size: int:
	get: return config.world_size if config else 200
var chunk_size: int:
	get: return config.chunk_size if config else 20
var water_level: int:
	get: return config.water_level if config else 5
var show_water: bool:
	get: return config.show_water if config else true
var seed_value: int:
	get:
		if seed_override != -1:
			return seed_override
		return config.seed_value if config else 1337
var enable_ao: bool:
	get: return config.enable_ao if config else true
var ao_darkness: float:
	get: return config.ao_darkness if config else 0.22
var enable_shadows: bool:
	get: return config.enable_shadows if config else true

var terrain_material: ShaderMaterial
var terrain_generator: TerrainGenerator
var voxel_model: VoxelWorld
var chunk_mesher: ChunkMesher
var chunk_renderer: ChunkRenderSystem
var torch_renderer: TorchRenderSystem
var chunk_manager: ChunkManager

var _has_generated: bool = false
var _player_ref: Node3D = null


func _ready():
	if not auto_generate_on_ready:
		# Defer generation to LoadingScreen -> initialize_world_async()
		print("[WorldController] auto_generate_on_ready=false, deferring. Waiting for async init.")
		# Still load config so seed_value is valid, but don't generate chunks yet
		_ensure_config_loaded()
		return

	# Normal sync path for direct launch (game.tscn)
	_ensure_config_loaded()
	_prepare_config()
	if not config.validate():
		push_error("[WorldController] Invalid config, using fallback")
		config = WorldConfig.new()

	_generate_world_sync()
	_has_generated = true


func _ensure_config_loaded():
	if config == null:
		var p = "res://world/generation/world_config.tres"
		if ResourceLoader.exists(p):
			config = load(p) as WorldConfig
		if config == null:
			config = WorldConfig.new()

	# Auto-load session fallback
	if pending_save_data.is_empty() and seed_override == -1:
		var session_path = "user://current_session.json"
		if FileAccess.file_exists(session_path):
			var f = FileAccess.open(session_path, FileAccess.READ)
			if f:
				var txt = f.get_as_text()
				f.close()
				var parsed = JSON.parse_string(txt)
				if parsed is Dictionary and not parsed.is_empty():
					var sid = int(parsed.get("slot_id", -1))
					if sid != -1 and SaveManager.slot_exists(sid):
						var full = SaveManager.load_slot(sid)
						if full.get("exists", false):
							pending_save_data = full
							seed_override = int(full.get("seed", seed_override))
							print("[WorldController] Auto-loaded slot %d seed %d" % [sid, seed_override])
					elif parsed.has("seed"):
						seed_override = int(parsed["seed"])
						pending_save_data = parsed
						print("[WorldController] Auto-loaded session seed %d" % seed_override)

func _prepare_config():
	if config == null:
		return
	config = config.duplicate() as WorldConfig
	if seed_override != -1:
		config.seed_value = seed_override
		print("[WorldController] Using override seed %d" % seed_override)
	elif pending_save_data.is_empty():
		var rng = RandomNumberGenerator.new()
		rng.randomize()
		var random_seed = rng.randi_range(1, 2147483646)
		config.seed_value = random_seed
		print("[WorldController] Random seed %d for fresh world" % random_seed)
	else:
		if pending_save_data.has("seed") and seed_override == -1:
			seed_override = int(pending_save_data["seed"])
			config.seed_value = seed_override
			print("[WorldController] Using pending save seed %d" % seed_override)

	var is_fresh = pending_save_data.is_empty() or (pending_save_data.get("placed_blocks", {}).is_empty() and pending_save_data.get("removed_blocks", {}).is_empty())
	if is_fresh:
		var jitter_rng = RandomNumberGenerator.new()
		jitter_rng.seed = config.seed_value
		config.base_height = 8.5 + jitter_rng.randf_range(-0.8, 1.5)
		config.meadow_radius = 22.0 + jitter_rng.randf_range(-2.0, 6.0)
		config.tree_density = 0.01 + jitter_rng.randf_range(-0.003, 0.008)
		config.hills_frequency = 0.012 + jitter_rng.randf_range(-0.002, 0.004)
		print("[WorldController] Jitter: base_h=%.2f meadow_r=%.1f tree_d=%.4f hills_f=%.4f" % [config.base_height, config.meadow_radius, config.tree_density, config.hills_frequency])


func _generate_world_sync():
	var effective_ws = config.get_effective_world_size() if config else world_size
	var infinite_str = "INFINITE" if config and config.infinite_world else "%dx%d" % [world_size, world_size]
	print("[Wildes] Generating %s world (seed %d) streaming=%s render_dist=%d ..." % [infinite_str, seed_value, config.chunk_streaming_enabled if config else true, config.render_distance if config else 4])
	terrain_generator = TerrainGenerator.new(config)
	var gen = terrain_generator.generate_all()

	if config and config.infinite_world:
		# Infinite: setup infinite voxel model, apply initial gen dicts
		voxel_model = VoxelWorld.new(effective_ws, chunk_size, max_build_y)
		voxel_model.setup_infinite(chunk_size, max_build_y)
		voxel_model.set_generator_ref(terrain_generator)
		voxel_model.apply_chunk_gen(gen)
		voxel_model.apply_tree_chunk(gen)
	else:
		voxel_model = VoxelWorld.new(world_size, chunk_size, max_build_y)
		voxel_model.setup(world_size, chunk_size, max_build_y, gen["height_map"], gen["type_map"], gen["tree_block_fast"], gen["tree_blocks"])

	if not pending_save_data.is_empty():
		_apply_save_data_to_model(pending_save_data)

	voxel_model.block_edit_committed.connect(_on_block_edit_committed)

	_prepare_materials()
	_setup_rendering_systems()

	if config and config.chunk_streaming_enabled:
		var initial_pos = voxel_model.get_spawn_position()
		if not pending_save_data.is_empty() and pending_save_data.has("player_position"):
			var arr = pending_save_data["player_position"]
			if arr is Array and arr.size() == 3:
				var p = Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
				if p != Vector3.ZERO and p.length() > 1.0:
					initial_pos = p
					print("[WorldController] Using saved player pos %s for initial streaming load" % initial_pos)
		var loaded = chunk_manager.ensure_chunks_around(initial_pos)
		print("[Wildes] Streaming initial load around %s -> %d chunks" % [initial_pos, loaded])
		# Load torches for initial chunks
		if torch_renderer and voxel_model:
			for coord in chunk_manager.loaded_chunks.keys():
				torch_renderer.load_torches_for_chunk(coord.x, coord.y, chunk_size, voxel_model.torch_attachments)
		if _player_ref:
			chunk_manager.set_player_ref(_player_ref)
	else:
		chunk_renderer.generate_all_chunks()
		# Load all torches when not streaming
		if torch_renderer and voxel_model:
			for torch_pos in voxel_model.torch_attachments.keys():
				var dir = voxel_model.torch_attachments[torch_pos] as Vector3i
				torch_renderer.spawn_torch(torch_pos, dir)
		print("[Wildes] Non-streaming fallback generated all chunks")

	_create_water_plane()

	print("[Wildes] World ready: %d chunks gen=%s model=%s streaming=%s infinite=%s" % [chunk_renderer.chunk_instances.size(), terrain_generator.get_stats(), voxel_model.get_stats(), chunk_manager.get_stats() if chunk_manager else {}, config.infinite_world if config else false])


func initialize_world_async() -> void:
	# Async version used by LoadingScreen with progress bar
	if _has_generated:
		print("[WorldController] Already generated, skipping async")
		generation_progress.emit("done", 1.0, "Already generated")
		return

	_ensure_config_loaded()
	_prepare_config()
	if not config.validate():
		config = WorldConfig.new()

	generation_progress.emit("config", 0.05, "Preparing config (seed %d)" % seed_value)
	await get_tree().process_frame

	var infinite_str = "INFINITE" if config and config.infinite_world else "%dx%d" % [world_size, world_size]
	print("[Wildes] Async generating %s world (seed %d) infinite=%s" % [infinite_str, seed_value, config.infinite_world if config else false])
	generation_progress.emit("terrain", 0.1, "Generating terrain (%s)..." % infinite_str)

	terrain_generator = TerrainGenerator.new(config)
	var gen = terrain_generator.generate_all()

	generation_progress.emit("terrain", 0.3, "Terrain: %d trees" % gen["tree_blocks"].size())
	await get_tree().process_frame

	generation_progress.emit("model", 0.4, "Building voxel model...")
	if config and config.infinite_world:
		var effective_ws = config.get_effective_world_size()
		voxel_model = VoxelWorld.new(effective_ws, chunk_size, max_build_y)
		voxel_model.setup_infinite(chunk_size, max_build_y)
		voxel_model.set_generator_ref(terrain_generator)
		voxel_model.apply_chunk_gen(gen)
		voxel_model.apply_tree_chunk(gen)
	else:
		voxel_model = VoxelWorld.new(world_size, chunk_size, max_build_y)
		voxel_model.setup(world_size, chunk_size, max_build_y, gen["height_map"], gen["type_map"], gen["tree_block_fast"], gen["tree_blocks"])

	if not pending_save_data.is_empty():
		_apply_save_data_to_model(pending_save_data)

	voxel_model.block_edit_committed.connect(_on_block_edit_committed)
	await get_tree().process_frame

	generation_progress.emit("materials", 0.5, "Preparing materials...")
	_prepare_materials()
	_setup_rendering_systems()
	await get_tree().process_frame

	# Chunk generation with progress 0.55 -> 0.95
	generation_progress.emit("chunks", 0.55, "Generating chunks...")
	if config and config.chunk_streaming_enabled:
		await _generate_chunks_async_streaming()
	else:
		await _generate_chunks_async()

	generation_progress.emit("water", 0.95, "Creating water plane...")
	_create_water_plane()
	await get_tree().process_frame

	generation_progress.emit("done", 1.0, "%d chunks ready" % chunk_renderer.chunk_instances.size())
	print("[Wildes] World ready async: %d chunks gen=%s model=%s streaming=%s" % [chunk_renderer.chunk_instances.size(), terrain_generator.get_stats(), voxel_model.get_stats(), chunk_manager.get_stats() if chunk_manager else {}])
	_has_generated = true


func _generate_chunks_async() -> void:
	# Full world generation (fallback when streaming disabled)
	if chunk_renderer == null:
		return
	chunk_renderer.clear()
	if chunk_manager:
		chunk_manager.clear()
	if config and config.infinite_world:
		# For infinite non-streaming doesn't make sense, but generate around spawn only
		await _generate_chunks_async_streaming()
		return
	var chunks_x = int(ceil(float(world_size) / float(chunk_size)))
	var chunks_z = int(ceil(float(world_size) / float(chunk_size)))
	var total = chunks_x * chunks_z
	var done = 0
	for cx in range(chunks_x):
		for cz in range(chunks_z):
			chunk_renderer.rebuild_immediate(cx, cz)
			done += 1
			var prog = 0.55 + (float(done) / float(total)) * 0.4
			if done % 3 == 0 or done == total:
				generation_progress.emit("chunks", prog, "Chunks %d/%d" % [done, total])
				await get_tree().process_frame
			if done % 10 == 0:
				await get_tree().process_frame

func _generate_chunks_async_streaming() -> void:
	if chunk_renderer == null:
		return
	chunk_renderer.clear()
	if chunk_manager:
		chunk_manager.clear()
	var initial_pos = voxel_model.get_spawn_position() if voxel_model else Vector3(0,10,0)
	if not pending_save_data.is_empty() and pending_save_data.has("player_position"):
		var arr = pending_save_data["player_position"]
		if arr is Array and arr.size() == 3:
			var p = Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
			if p != Vector3.ZERO and p.length() > 1.0:
				initial_pos = p
				print("[WorldController] Async streaming using saved player pos %s" % initial_pos)
	var center_chunk = ChunkCoord.world_to_chunk(initial_pos, chunk_size)
	var desired: Array[Vector2i]
	if config and config.infinite_world:
		desired = ChunkCoord.get_chunks_in_radius_infinite(center_chunk, config.render_distance)
	else:
		desired = ChunkCoord.get_chunks_in_radius(center_chunk, config.render_distance, world_size, chunk_size)
	desired = ChunkCoord.sort_by_distance(desired, center_chunk)
	var total = desired.size()
	var done = 0
	print("[WorldController] Streaming async gen around %s center chunk %s desired %d infinite=%s" % [initial_pos, center_chunk, total, config.infinite_world if config else false])
	for coord in desired:
		# Ensure terrain data exists before meshing (critical for infinite)
		if config and config.infinite_world and chunk_manager:
			chunk_manager.ensure_terrain_for_chunk(coord)
		elif config and config.infinite_world and terrain_generator and voxel_model:
			# Fallback if manager not ready
			var ox = coord.x * chunk_size
			var oz = coord.y * chunk_size
			var cd = terrain_generator.generate_chunk_region(ox-1, oz-1, chunk_size+2, chunk_size+2)
			voxel_model.apply_chunk_gen(cd)
			var td = terrain_generator.generate_trees_for_chunk(ox, oz, chunk_size, chunk_size)
			voxel_model.apply_tree_chunk(td)

		chunk_renderer.rebuild_immediate(coord.x, coord.y)
		if chunk_manager:
			chunk_manager.loaded_chunks[coord] = true
			chunk_manager.total_loads += 1
		# Load torches for this chunk
		if torch_renderer and voxel_model:
			torch_renderer.load_torches_for_chunk(coord.x, coord.y, chunk_size, voxel_model.torch_attachments)
		done += 1
		var prog = 0.55 + (float(done) / float(max(total,1))) * 0.4
		if done % 2 == 0 or done == total:
			generation_progress.emit("chunks", prog, "Chunks %d/%d (streaming radius %d)" % [done, total, config.render_distance])
			await get_tree().process_frame
		if done % 5 == 0:
			await get_tree().process_frame
	if chunk_manager:
		chunk_manager.last_player_chunk = center_chunk


func set_seed_override(s: int):
	seed_override = s
	if config:
		config = config.duplicate() as WorldConfig
		config.seed_value = s

func set_pending_save_data(data: Dictionary):
	pending_save_data = data
	if data.has("seed"):
		seed_override = int(data["seed"])
		if config:
			config.seed_value = seed_override

func _apply_save_data_to_model(save_dict: Dictionary):
	if voxel_model == null:
		return
	var placed_raw = save_dict.get("placed_blocks", {})
	var removed_raw = save_dict.get("removed_blocks", {})
	var torch_raw = save_dict.get("torch_attachments", {})

	var placed = SaveManager.deserialize_vector3i_dict_to_placed(placed_raw) if placed_raw is Dictionary else {}
	var removed = SaveManager.deserialize_vector3i_dict_to_removed(removed_raw) if removed_raw is Dictionary else {}
	var torches = SaveManager.deserialize_torch_dict(torch_raw) if torch_raw is Dictionary else {}

	voxel_model.placed_blocks = placed
	voxel_model.removed_blocks = removed
	voxel_model.torch_attachments = torches
	for p in removed.keys():
		if voxel_model.tree_block_fast.has(p):
			voxel_model.tree_block_fast.erase(p)

	print("[WorldController] Applied save: %d placed, %d removed, %d torches" % [placed.size(), removed.size(), torches.size()])


func _on_chunk_loaded(coord: Vector2i):
	if torch_renderer and voxel_model:
		torch_renderer.load_torches_for_chunk(coord.x, coord.y, chunk_size, voxel_model.torch_attachments)

func _on_chunk_unloaded(coord: Vector2i):
	if torch_renderer:
		torch_renderer.unload_torches_in_chunk(coord.x, coord.y, chunk_size)

func _on_block_edit_committed(edit: BlockEdit):
	if chunk_renderer == null:
		return
	# Only queue rebuild if chunk is currently loaded (or if streaming disabled)
	var should_queue = true
	var edit_chunk = ChunkCoord.world_to_chunk_vec3i(edit.pos, chunk_size)
	if config and config.chunk_streaming_enabled and chunk_manager:
		if not chunk_manager.is_chunk_loaded(edit_chunk) and not chunk_renderer.is_chunk_loaded(edit_chunk.x, edit_chunk.y):
			should_queue = false

	if should_queue:
		if edit.is_mine():
			chunk_renderer.queue_rebuild_for_world_pos(edit.pos)
			if edit.old_id == BlockId.Type.TORCH:
				torch_renderer.remove_torch(edit.pos)
		else:
			if edit.new_id == BlockId.Type.TORCH:
				# Only spawn torch visually if its chunk is currently loaded
				if (not config or not config.chunk_streaming_enabled) or chunk_manager.is_chunk_loaded(edit_chunk) or chunk_renderer.is_chunk_loaded(edit_chunk.x, edit_chunk.y):
					torch_renderer.spawn_torch(edit.pos, edit.attach_dir)
			else:
				chunk_renderer.queue_rebuild_for_world_pos(edit.pos)
	else:
		# Chunk not loaded: don't spawn torch mesh now, it will appear when chunk loads via _on_chunk_loaded
		# For removal, if torch instance exists (shouldn't when chunk unloaded) remove it
		if edit.is_mine() and edit.old_id == BlockId.Type.TORCH:
			torch_renderer.remove_torch(edit.pos)

func _get_chunk_container() -> Node3D:
	return $Chunks as Node3D
func _get_water_container() -> Node3D:
	return $Water as Node3D
func _get_torch_container() -> Node3D:
	return $SpecialBlocks/TorchContainer as Node3D

func set_player_ref(p: Node3D):
	_player_ref = p
	if chunk_manager:
		chunk_manager.set_player_ref(p)
	if torch_renderer:
		torch_renderer.set_player_ref(p)
	print("[WorldController] Player ref set %s" % (p.global_position if p else "null"))

func get_chunk_manager() -> ChunkManager:
	return chunk_manager

func _setup_rendering_systems():
	chunk_mesher = ChunkMesher.new(world_size, chunk_size, max_build_y, seed_value, enable_ao)
	chunk_mesher.configure_from_config(config)
	var c_container = _get_chunk_container()
	chunk_renderer = ChunkRenderSystem.new()
	# For infinite, world_size is huge, but renderer needs effective size for clamping check - pass large if infinite
	var effective_ws = config.get_effective_world_size() if config else world_size
	chunk_renderer.setup(c_container, chunk_mesher, terrain_material, effective_ws, chunk_size, max_build_y, seed_value, voxel_model)
	var t_container = _get_torch_container()
	torch_renderer = TorchRenderSystem.new(t_container)
	# Chunk streaming manager with terrain generator ref for infinite on-demand gen
	chunk_manager = ChunkManager.new()
	chunk_manager.setup(config, voxel_model, chunk_renderer, terrain_generator)
	if not chunk_manager.chunk_loaded.is_connected(_on_chunk_loaded):
		chunk_manager.chunk_loaded.connect(_on_chunk_loaded)
	if not chunk_manager.chunk_unloaded.is_connected(_on_chunk_unloaded):
		chunk_manager.chunk_unloaded.connect(_on_chunk_unloaded)
	if _player_ref:
		chunk_manager.set_player_ref(_player_ref)

func _prepare_materials():
	var terrain_shader = load("res://shaders/terrain.gdshader")
	terrain_material = ShaderMaterial.new()
	if terrain_shader:
		terrain_material.shader = terrain_shader
		terrain_material.set_shader_parameter("terrain_saturation", 1.1)
		terrain_material.set_shader_parameter("terrain_contrast", 1.3)

func _process(delta):
	# Handle chunk streaming - continuous, seamless async
	if chunk_manager and config and config.chunk_streaming_enabled:
		var player_pos: Vector3 = Vector3.INF
		if _player_ref and is_instance_valid(_player_ref):
			player_pos = _player_ref.global_position
		elif voxel_model:
			player_pos = voxel_model.get_spawn_position()
		chunk_manager.tick(delta, player_pos if player_pos != Vector3.INF else voxel_model.get_spawn_position())

	if chunk_renderer:
		chunk_renderer.poll_async(4)
		chunk_renderer.flush_dirty(chunk_renderer.max_per_frame)
	if torch_renderer:
		torch_renderer.update_shadow_culling(delta)

	# Infinite water plane follows player
	if config and config.infinite_world and config.show_water:
		var water_cont = _get_water_container()
		if water_cont and water_cont.get_child_count() > 0 and _player_ref and is_instance_valid(_player_ref):
			var wp = water_cont.get_child(0) as Node3D
			if wp:
				wp.global_position.x = _player_ref.global_position.x
				wp.global_position.z = _player_ref.global_position.z

func _create_water_plane():
	if not show_water:
		return
	var water_mesh = PlaneMesh.new()
	var plane_size: float
	var plane_pos: Vector3
	if config and config.infinite_world:
		plane_size = float(config.infinite_water_size)
		plane_pos = Vector3(0, float(water_level) + 0.45, 0)
		if _player_ref and is_instance_valid(_player_ref):
			plane_pos.x = _player_ref.global_position.x
			plane_pos.z = _player_ref.global_position.z
	else:
		plane_size = float(world_size)
		plane_pos = Vector3(world_size * 0.5, float(water_level) + 0.45, world_size * 0.5)
	water_mesh.size = Vector2(plane_size, plane_size)
	var mi = MeshInstance3D.new()
	mi.mesh = water_mesh
	mi.name = "WaterPlane"
	mi.position = plane_pos
	var water_shader = load("res://shaders/water.gdshader")
	var mat: Material
	if water_shader:
		var sm = ShaderMaterial.new()
		sm.shader = water_shader
		mat = sm
	else:
		var stdm = StandardMaterial3D.new()
		stdm.albedo_color = Color(0.43, 0.68, 0.78, 0.42)
		stdm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat = stdm
	if mat is StandardMaterial3D:
		mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.43, 0.68, 0.78, 0.44)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_get_water_container().add_child(mi)

func get_world_stats() -> Dictionary:
	return {
		"world_size": world_size,
		"chunk_size": chunk_size,
		"chunks": chunk_renderer.chunk_instances.size() if chunk_renderer else 0,
		"dirty": chunk_renderer.dirty_chunks.size() if chunk_renderer else 0,
		"placed": voxel_model.placed_blocks.size() if voxel_model else 0,
		"removed": voxel_model.removed_blocks.size() if voxel_model else 0,
		"torches": voxel_model.torch_attachments.size() if voxel_model else 0,
		"max_build_y": max_build_y,
		"render": chunk_renderer.get_stats() if chunk_renderer else {},
		"torch_render": torch_renderer.get_stats() if torch_renderer else {},
		"model": voxel_model.get_stats() if voxel_model else {},
		"generation": terrain_generator.get_stats() if terrain_generator else {},
		"streaming": chunk_manager.get_stats() if chunk_manager else {},
		"config_path": config.resource_path if config else "",
		"streaming_enabled": config.chunk_streaming_enabled if config else false,
		"render_distance": config.render_distance if config else 0,
	}
