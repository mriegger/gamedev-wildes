extends Node3D
class_name WorldController

signal generation_progress(stage: String, percent: float, details: String)

const ChunkCoord = preload("res://world/streaming/chunk_coord.gd")
const ChunkManager = preload("res://world/streaming/chunk_manager.gd")

@export var config: WorldConfig
@export var water_profile: WaterProfile

@export var auto_generate_on_ready: bool = true

var seed_override: int = -1
var pending_save_data: Dictionary = {}

var max_build_y: int:
	get: return config.max_build_y if config else 36
var chunk_size: int:
	get: return config.chunk_size if config else 20
var seed_value: int:
	get:
		if seed_override != -1:
			return seed_override
		return config.seed_value if config else 1337
var enable_ao: bool:
	get: return config.enable_ao if config else true

var terrain_material: ShaderMaterial
var water_block_material: ShaderMaterial
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
		_ensure_config_loaded()
		return

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
	if water_profile == null:
		var wp = "res://environment/water_profile.tres"
		if not ResourceLoader.exists(wp):
			push_error("Missing WaterProfile at %s - single source of truth, using fallback" % wp)
			water_profile = WaterProfile.new()
		else:
			var loaded_profile = load(wp) as WaterProfile
			if loaded_profile == null:
				push_error("Failed to load WaterProfile - check water_profile.tres, using fallback")
				water_profile = WaterProfile.new()
			else:
				water_profile = loaded_profile

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
					elif parsed.has("seed"):
						seed_override = int(parsed["seed"])
						pending_save_data = parsed

func _prepare_config():
	if config == null:
		return
	config = config.duplicate() as WorldConfig
	if seed_override != -1:
		config.seed_value = seed_override
	elif pending_save_data.is_empty():
		var rng = RandomNumberGenerator.new()
		rng.randomize()
		var random_seed = rng.randi_range(1, 2147483646)
		config.seed_value = random_seed
	else:
		if pending_save_data.has("seed") and seed_override == -1:
			seed_override = int(pending_save_data["seed"])
			config.seed_value = seed_override

	var jitter_rng = RandomNumberGenerator.new()
	jitter_rng.seed = config.seed_value
	config.base_height = 8.5 + jitter_rng.randf_range(-0.8, 1.5)
	config.meadow_radius = 22.0 + jitter_rng.randf_range(-2.0, 6.0)
	config.tree_density = 0.01 + jitter_rng.randf_range(-0.003, 0.008)
	# Jitter new parameter fields slightly per seed for variety, keep within valid ranges.
	config.continentalness_frequency = clamp(0.0018 + jitter_rng.randf_range(-0.0004, 0.0006), 0.0005, 0.01)
	config.erosion_frequency = clamp(0.0045 + jitter_rng.randf_range(-0.001, 0.0015), 0.001, 0.015)
	config.peaks_valleys_frequency = clamp(0.018 + jitter_rng.randf_range(-0.003, 0.004), 0.005, 0.04)

func _generate_world_sync():
	terrain_generator = TerrainGenerator.new(config)
	var gen = terrain_generator.generate_all()

	voxel_model = VoxelWorld.new(chunk_size, max_build_y)
	voxel_model.setup_infinite(chunk_size, max_build_y)
	voxel_model.water_level = config.water_level
	voxel_model.set_generator_ref(terrain_generator)
	voxel_model.apply_chunk_gen(gen)
	voxel_model.apply_tree_chunk(gen)

	if not pending_save_data.is_empty():
		_apply_save_data_to_model(pending_save_data)

	voxel_model.block_edit_committed.connect(_on_block_edit_committed)

	_prepare_materials()
	_setup_rendering_systems()

	var initial_pos = voxel_model.get_spawn_position()
	if not pending_save_data.is_empty() and pending_save_data.has("player_position"):
		var arr = pending_save_data["player_position"]
		if arr is Array and arr.size() == 3:
			var p = Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
			if p != Vector3.ZERO and p.length() > 1.0:
				initial_pos = p
	chunk_manager.ensure_chunks_around(initial_pos, true)
	if torch_renderer and voxel_model:
		for coord in chunk_manager.data_chunks.keys():
			torch_renderer.load_torches_for_chunk(coord.x, coord.y, chunk_size, voxel_model.torch_attachments)
	if _player_ref:
		chunk_manager.set_player_ref(_player_ref)

func initialize_world_async() -> void:
	if _has_generated:
		generation_progress.emit("done", 1.0, "Already generated")
		return

	_ensure_config_loaded()
	_prepare_config()
	if not config.validate():
		config = WorldConfig.new()

	generation_progress.emit("config", 0.05, "Preparing config (seed %d)" % seed_value)
	await get_tree().process_frame

	generation_progress.emit("terrain", 0.1, "Generating terrain (INFINITE)...")

	terrain_generator = TerrainGenerator.new(config)
	var gen = terrain_generator.generate_all()

	var tree_count = gen.get("positions", []).size()
	if tree_count == 0:
		tree_count = gen.get("tree_block_fast", {}).size()
	generation_progress.emit("terrain", 0.3, "Terrain: %d trees" % tree_count)
	await get_tree().process_frame

	generation_progress.emit("model", 0.4, "Building voxel model...")
	voxel_model = VoxelWorld.new(chunk_size, max_build_y)
	voxel_model.setup_infinite(chunk_size, max_build_y)
	voxel_model.water_level = config.water_level
	voxel_model.set_generator_ref(terrain_generator)
	voxel_model.apply_chunk_gen(gen)
	voxel_model.apply_tree_chunk(gen)

	if not pending_save_data.is_empty():
		_apply_save_data_to_model(pending_save_data)

	voxel_model.block_edit_committed.connect(_on_block_edit_committed)
	await get_tree().process_frame

	generation_progress.emit("materials", 0.5, "Preparing materials...")
	_prepare_materials()
	_setup_rendering_systems()
	await get_tree().process_frame

	generation_progress.emit("chunks", 0.55, "Generating chunks...")
	await _generate_chunks_async_streaming()

	generation_progress.emit("water", 0.95, "Water blocks (block-based)...")
	await get_tree().process_frame

	generation_progress.emit("done", 1.0, "%d chunks ready" % chunk_renderer.chunk_instances.size())
	_has_generated = true

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
	var center_chunk = ChunkCoord.world_to_chunk(initial_pos, chunk_size)
	var desired = ChunkCoord.get_chunks_in_radius_infinite(center_chunk, config.render_distance)
	desired = ChunkCoord.sort_by_distance(desired, center_chunk)
	var total = desired.size()
	var done = 0
	for coord in desired:
		chunk_renderer.rebuild_immediate(coord.x, coord.y)
		if chunk_manager:
			chunk_manager.data_chunks[coord] = true
			chunk_manager.visible_chunks[coord] = true
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

func _on_chunk_loaded(coord: Vector2i):
	if torch_renderer and voxel_model:
		torch_renderer.load_torches_for_chunk(coord.x, coord.y, chunk_size, voxel_model.torch_attachments)

func _on_chunk_unloaded(coord: Vector2i):
	if torch_renderer:
		torch_renderer.unload_torches_in_chunk(coord.x, coord.y, chunk_size)

func _on_block_edit_committed(edit: BlockEdit):
	if chunk_renderer == null:
		return
	var should_queue = true
	var edit_chunk = ChunkCoord.world_to_chunk_vec3i(edit.pos, chunk_size)
	if chunk_manager:
		if not chunk_manager.is_chunk_loaded(edit_chunk) and not chunk_renderer.is_chunk_loaded(edit_chunk.x, edit_chunk.y):
			should_queue = false

	if should_queue:
		if edit.is_mine():
			chunk_renderer.queue_rebuild_for_world_pos(edit.pos)
			if edit.old_id == BlockId.Type.TORCH:
				torch_renderer.remove_torch(edit.pos)
		else:
			if edit.new_id == BlockId.Type.TORCH:
				if chunk_manager.is_chunk_loaded(edit_chunk) or chunk_renderer.is_chunk_loaded(edit_chunk.x, edit_chunk.y):
					torch_renderer.spawn_torch(edit.pos, edit.attach_dir)
			else:
				chunk_renderer.queue_rebuild_for_world_pos(edit.pos)
	else:
		if edit.is_mine() and edit.old_id == BlockId.Type.TORCH:
			torch_renderer.remove_torch(edit.pos)

func _get_chunk_container() -> Node3D:
	return $Chunks as Node3D
func _get_torch_container() -> Node3D:
	return $SpecialBlocks/TorchContainer as Node3D

func set_player_ref(p: Node3D):
	_player_ref = p
	if chunk_manager:
		chunk_manager.set_player_ref(p)
	if torch_renderer:
		torch_renderer.set_player_ref(p)

func _setup_rendering_systems():
	chunk_mesher = ChunkMesher.new(chunk_size, max_build_y, seed_value, enable_ao)
	chunk_mesher.configure_from_config(config)
	var c_container = _get_chunk_container()
	chunk_renderer = ChunkRenderSystem.new()
	chunk_renderer.setup(c_container, chunk_mesher, terrain_material, chunk_size, max_build_y, seed_value, voxel_model)
	if water_block_material:
		chunk_renderer.set_water_material(water_block_material)
	if terrain_generator:
		chunk_renderer.set_terrain_generator(terrain_generator)
	var t_container = _get_torch_container()
	torch_renderer = TorchRenderSystem.new(t_container)
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
		if RenderingServer.get_rendering_device() == null:
			terrain_material.set_shader_parameter("terrain_saturation", 1.0)
			terrain_material.set_shader_parameter("terrain_contrast", 1.0)
		else:
			terrain_material.set_shader_parameter("terrain_saturation", 1.1)
			terrain_material.set_shader_parameter("terrain_contrast", 1.3)

	var water_shader = load("res://shaders/water.gdshader")
	water_block_material = ShaderMaterial.new()
	if water_shader:
		water_block_material.shader = water_shader
		if water_profile == null:
			push_error("water_profile must be loaded before _prepare_materials - using fallback")
			water_profile = WaterProfile.new()
		water_profile.apply_to_material(water_block_material)

		var normal_tex = NoiseTexture2D.new()
		normal_tex.width = 512
		normal_tex.height = 512
		normal_tex.seamless = true
		normal_tex.as_normal_map = true
		normal_tex.bump_strength = 1.0
		var norm_noise = FastNoiseLite.new()
		norm_noise.noise_type = FastNoiseLite.TYPE_PERLIN
		norm_noise.frequency = 0.008
		norm_noise.seed = seed_value + 7331
		norm_noise.fractal_octaves = 4
		normal_tex.noise = norm_noise

		water_block_material.set_shader_parameter("water_normal", normal_tex)

func _process(delta):
	if chunk_renderer:
		chunk_renderer.poll_async(2)
	if chunk_manager:
		var player_pos: Vector3 = Vector3.INF
		if _player_ref and is_instance_valid(_player_ref):
			player_pos = _player_ref.global_position
		elif voxel_model:
			player_pos = voxel_model.get_spawn_position()
		chunk_manager.tick(delta, player_pos if player_pos != Vector3.INF else voxel_model.get_spawn_position())
	if voxel_model:
		voxel_model.prune_terrain_cache(1)
	if chunk_renderer:
		chunk_renderer.flush_dirty(chunk_renderer.max_per_frame)
	if torch_renderer:
		torch_renderer.update_shadow_culling(delta)

func update_water_tint(sky_col: Color):
	if water_block_material == null:
		return
	if water_profile == null:
		push_error("WaterProfile must be loaded - check res://environment/water_profile.tres, using fallback")
		water_profile = WaterProfile.new()
	var sky_lum = (sky_col.r + sky_col.g + sky_col.b) / 3.0
	var night_factor = clamp(1.0 - sky_lum * 1.8, 0.0, 1.0)
	var base_tint: Vector4 = water_profile.tint_color
	var tint = base_tint * lerp(1.0, 0.6, night_factor)
	tint.x = maxf(tint.x, 0.03)
	tint.y = maxf(tint.y, 0.12)
	tint.z = maxf(tint.z, 0.25)
	water_block_material.set_shader_parameter("tint_color", tint)
