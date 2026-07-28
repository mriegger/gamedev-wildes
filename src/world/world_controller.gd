extends Node3D
class_name WorldController

## WorldController - coordinates generation, model, rendering
## Supports sync (direct launch) and async (loading screen with progress bar)

signal generation_progress(stage: String, percent: float, details: String)

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

var _has_generated: bool = false


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
	print("[Wildes] Generating %dx%d world (seed %d) ..." % [world_size, world_size, seed_value])
	terrain_generator = TerrainGenerator.new(config)
	var gen = terrain_generator.generate_all()

	voxel_model = VoxelWorld.new(world_size, chunk_size, max_build_y)
	voxel_model.setup(world_size, chunk_size, max_build_y, gen["height_map"], gen["type_map"], gen["tree_block_fast"], gen["tree_blocks"])

	if not pending_save_data.is_empty():
		_apply_save_data_to_model(pending_save_data)

	voxel_model.block_edit_committed.connect(_on_block_edit_committed)

	_prepare_materials()
	_setup_rendering_systems()
	chunk_renderer.generate_all_chunks()
	_create_water_plane()

	print("[Wildes] World ready: %d chunks gen=%s model=%s" % [chunk_renderer.chunk_instances.size(), terrain_generator.get_stats(), voxel_model.get_stats()])


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

	print("[Wildes] Async generating %dx%d world (seed %d)" % [world_size, world_size, seed_value])
	generation_progress.emit("terrain", 0.1, "Generating heightmap...")

	terrain_generator = TerrainGenerator.new(config)
	var gen = terrain_generator.generate_all()

	generation_progress.emit("terrain", 0.3, "Terrain: %d trees" % gen["tree_blocks"].size())
	await get_tree().process_frame

	generation_progress.emit("model", 0.4, "Building voxel model...")
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
	await _generate_chunks_async()

	generation_progress.emit("water", 0.95, "Creating water plane...")
	_create_water_plane()
	await get_tree().process_frame

	generation_progress.emit("done", 1.0, "%d chunks ready" % chunk_renderer.chunk_instances.size())
	print("[Wildes] World ready async: %d chunks gen=%s model=%s" % [chunk_renderer.chunk_instances.size(), terrain_generator.get_stats(), voxel_model.get_stats()])
	_has_generated = true


func _generate_chunks_async() -> void:
	if chunk_renderer == null:
		return
	chunk_renderer.clear()
	var chunks_x = int(ceil(float(world_size) / float(chunk_size)))
	var chunks_z = int(ceil(float(world_size) / float(chunk_size)))
	var total = chunks_x * chunks_z
	var done = 0
	for cx in range(chunks_x):
		for cz in range(chunks_z):
			chunk_renderer.rebuild_immediate(cx, cz)
			done += 1
			var prog = 0.55 + (float(done) / float(total)) * 0.4 # 0.55->0.95
			if done % 3 == 0 or done == total:
				generation_progress.emit("chunks", prog, "Chunks %d/%d" % [done, total])
				await get_tree().process_frame
			# Also yield every chunk for smoother bar on low-end
			if done % 10 == 0:
				await get_tree().process_frame


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


func _on_block_edit_committed(edit: BlockEdit):
	if edit.is_mine():
		chunk_renderer.queue_rebuild_for_world_pos(edit.pos)
		if edit.old_id == BlockId.Type.TORCH:
			torch_renderer.remove_torch(edit.pos)
	else:
		if edit.new_id == BlockId.Type.TORCH:
			torch_renderer.spawn_torch(edit.pos, edit.attach_dir)
		else:
			chunk_renderer.queue_rebuild_for_world_pos(edit.pos)

func _get_chunk_container() -> Node3D:
	return $Chunks as Node3D
func _get_water_container() -> Node3D:
	return $Water as Node3D
func _get_torch_container() -> Node3D:
	return $SpecialBlocks/TorchContainer as Node3D

func _setup_rendering_systems():
	chunk_mesher = ChunkMesher.new(world_size, chunk_size, max_build_y, seed_value, enable_ao)
	chunk_mesher.configure_from_config(config)
	var c_container = _get_chunk_container()
	chunk_renderer = ChunkRenderSystem.new()
	chunk_renderer.setup(c_container, chunk_mesher, terrain_material, world_size, chunk_size, max_build_y, seed_value, voxel_model)
	var t_container = _get_torch_container()
	torch_renderer = TorchRenderSystem.new(t_container)

func _prepare_materials():
	var terrain_shader = load("res://shaders/terrain.gdshader")
	terrain_material = ShaderMaterial.new()
	if terrain_shader:
		terrain_material.shader = terrain_shader
		terrain_material.set_shader_parameter("world_size", float(world_size))
		terrain_material.set_shader_parameter("terrain_saturation", 1.1)
		terrain_material.set_shader_parameter("terrain_contrast", 1.3)
		terrain_material.set_shader_parameter("haze_color", Vector3(0.75, 0.87, 0.94))

func _process(delta):
	if chunk_renderer:
		chunk_renderer.flush_dirty(chunk_renderer.max_per_frame)
	if torch_renderer:
		torch_renderer.update_shadow_culling(delta)

func _create_water_plane():
	if not show_water:
		return
	var water_mesh = PlaneMesh.new()
	water_mesh.size = Vector2(world_size, world_size)
	var mi = MeshInstance3D.new()
	mi.mesh = water_mesh
	mi.name = "WaterPlane"
	mi.position = Vector3(world_size * 0.5, float(water_level) + 0.45, world_size * 0.5)
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
		"config_path": config.resource_path if config else "",
	}
