extends Node3D
class_name WorldController

signal generation_progress(stage: String, percent: float, details: String)

@export var config: WorldConfig
@export var water_profile: WaterProfile
@export var block_catalog: BlockCatalog
@export var terrain_shader: Shader
@export var water_shader: Shader

@onready var chunk_renderer: ChunkRenderer = $ChunkRenderer
@onready var chunk_scheduler: ChunkBuildScheduler = $ChunkBuildScheduler
@onready var torch_renderer: TorchRenderer = $Torches

var terrain_material: ShaderMaterial
var water_block_material: ShaderMaterial
var terrain_generator: TerrainGenerator
var voxel_model: VoxelWorld
var chunk_mesher: ChunkMesher
var chunk_manager: ChunkManager

var _start_state: WorldState
var _player_ref: Node3D

func _ready():
	set_process(false)

func configure_start_state(state: WorldState):
	_start_state = state

func initialize_world_async() -> void:
	config = config.runtime_copy_for_seed(_start_state.seed)
	assert(config.validate())

	generation_progress.emit("config", 0.05, "Preparing config (seed %d)" % config.seed_value)
	await get_tree().process_frame
	generation_progress.emit("terrain", 0.1, "Generating terrain")
	terrain_generator = TerrainGenerator.new(config)
	var generation := terrain_generator.generate_all()
	var tree_count := (generation.get("tree_block_fast", {}) as Dictionary).size()
	generation_progress.emit("terrain", 0.3, "Terrain: %d tree blocks" % tree_count)
	await get_tree().process_frame

	generation_progress.emit("model", 0.4, "Building voxel model")
	_create_world_model(generation)
	await get_tree().process_frame

	generation_progress.emit("materials", 0.5, "Preparing materials")
	_prepare_materials()
	_setup_systems()
	await get_tree().process_frame

	generation_progress.emit("chunks", 0.55, "Generating chunks")
	await _generate_initial_chunks()
	generation_progress.emit("done", 1.0, "%d chunks ready" % chunk_manager.visible_chunks.size())
	set_process(true)

func _create_world_model(generation: Dictionary):
	voxel_model = VoxelWorld.new(config.chunk_size, config.max_build_y, config.water_level, config.meadow_radius, block_catalog)
	voxel_model.set_generator_ref(terrain_generator)
	voxel_model.apply_chunk_gen(generation)
	voxel_model.apply_tree_chunk(generation)
	voxel_model.placed_blocks = _start_state.placed_blocks.duplicate()
	voxel_model.removed_blocks = _start_state.removed_blocks.duplicate()
	voxel_model.torch_attachments = _start_state.torch_attachments.duplicate()
	for pos in voxel_model.removed_blocks:
		voxel_model.tree_block_fast.erase(pos)
	voxel_model.block_edit_committed.connect(_on_block_edit_committed)

func _setup_systems():
	chunk_mesher = ChunkMesher.new(config.chunk_size, config.max_build_y, config.seed_value, config.enable_ao, block_catalog)
	chunk_scheduler.setup(chunk_mesher, terrain_generator, voxel_model, config.chunk_size, config.max_build_y)
	chunk_renderer.setup(chunk_mesher, terrain_material, water_block_material, voxel_model)
	torch_renderer.setup(block_catalog)
	chunk_manager = ChunkManager.new()
	chunk_manager.setup(config, voxel_model, chunk_scheduler, chunk_renderer)
	chunk_manager.chunk_loaded.connect(_on_chunk_loaded)
	chunk_manager.chunk_unloaded.connect(_on_chunk_unloaded)

func _generate_initial_chunks() -> void:
	var total := chunk_manager.begin_initial_load(_get_initial_position())
	for index in range(total):
		chunk_manager.step_initial_load()
		var completed := index + 1
		if completed % 2 == 0 or completed == total:
			var percent := 0.55 + float(completed) / float(max(total, 1)) * 0.4
			generation_progress.emit("chunks", percent, "Chunks %d/%d" % [completed, total])
			await get_tree().process_frame

func _get_initial_position() -> Vector3:
	if _start_state.player_position != Vector3.ZERO:
		return _start_state.player_position
	return voxel_model.get_spawn_position()

func _prepare_materials():
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = terrain_shader
	if RenderingServer.get_rendering_device() == null:
		terrain_material.set_shader_parameter("terrain_saturation", 1.0)
		terrain_material.set_shader_parameter("terrain_contrast", 1.0)
	else:
		terrain_material.set_shader_parameter("terrain_saturation", 1.1)
		terrain_material.set_shader_parameter("terrain_contrast", 1.3)

	water_block_material = ShaderMaterial.new()
	water_block_material.shader = water_shader
	water_profile.apply_to_material(water_block_material)
	var normal_texture := NoiseTexture2D.new()
	normal_texture.width = 512
	normal_texture.height = 512
	normal_texture.seamless = true
	normal_texture.as_normal_map = true
	normal_texture.bump_strength = 1.0
	var normal_noise := FastNoiseLite.new()
	normal_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	normal_noise.frequency = 0.008
	normal_noise.seed = config.seed_value + 7331
	normal_noise.fractal_octaves = 4
	normal_texture.noise = normal_noise
	water_block_material.set_shader_parameter("water_normal", normal_texture)

func _process(delta: float):
	chunk_manager.tick(_player_ref.global_position)
	chunk_manager.poll_completed()
	voxel_model.prune_terrain_cache(1)
	torch_renderer.update_shadow_culling(delta)

func _on_chunk_loaded(coord: Vector2i):
	torch_renderer.load_torches_for_chunk(coord.x, coord.y, config.chunk_size, voxel_model.torch_attachments)

func _on_chunk_unloaded(coord: Vector2i):
	torch_renderer.unload_torches_in_chunk(coord.x, coord.y, config.chunk_size)

func _on_block_edit_committed(edit: BlockEdit):
	var edit_chunk := ChunkCoord.world_to_chunk_vec3i(edit.pos, config.chunk_size)
	if edit.is_mine() and edit.old_id == BlockId.Type.TORCH:
		torch_renderer.remove_torch(edit.pos)
	elif edit.new_id == BlockId.Type.TORCH:
		if chunk_manager.visible_chunks.has(edit_chunk):
			torch_renderer.spawn_torch(edit.pos, edit.attach_dir)
	else:
		chunk_manager.queue_rebuild_for_world_pos(edit.pos)

func set_player_ref(player: Node3D):
	_player_ref = player
	torch_renderer.set_player_ref(player)

func update_water_tint(sky_color: Color):
	var sky_luminance: float = (sky_color.r + sky_color.g + sky_color.b) / 3.0
	var night_factor: float = clamp(1.0 - sky_luminance * 1.8, 0.0, 1.0)
	var tint: Vector4 = water_profile.tint_color * lerp(1.0, 0.6, night_factor)
	tint.x = maxf(tint.x, 0.03)
	tint.y = maxf(tint.y, 0.12)
	tint.z = maxf(tint.z, 0.25)
	water_block_material.set_shader_parameter("tint_color", tint)

func shutdown():
	set_process(false)
	chunk_manager.shutdown()
