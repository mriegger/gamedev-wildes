extends Node3D
class_name WorldController

signal generation_progress(stage: String, percent: float, details: String)

@export var config: WorldConfig
@export var water_profile: WaterProfile
@export var block_catalog: BlockCatalog
@export var campfire_audio_profile: CampfireAudioProfile
@export var foliage_catalog: FoliageCatalog
@export var terrain_shader: Shader
@export var foliage_shader: Shader
@export var water_shader: Shader

@onready var chunk_renderer: ChunkRenderer = $ChunkRenderer
@onready var chunk_scheduler: ChunkBuildScheduler = $ChunkBuildScheduler
@onready var torch_renderer: TorchRenderer = $Torches
@onready var anvil_renderer: AnvilRenderer = $Anvils
@onready var chest_renderer: ChestRenderer = $Chests
@onready var cauldron_renderer: CauldronRenderer = $Cauldrons
@onready var campfire_renderer: CampfireRenderer = $Campfires

var terrain_material: ShaderMaterial
var water_block_material: ShaderMaterial
var foliage_material: ShaderMaterial
var terrain_generator: TerrainGenerator
var voxel_model: VoxelWorld
var block_texture_set: BlockTextureSet
var foliage_texture_set: FoliageTextureSet
var chunk_mesher: ChunkMesher
var foliage_mesher: FoliageMesher
var chunk_manager: ChunkManager
var _settings: GameSettings
var _water_ripples := WaterRipplePresentation.new()

var _start_state: WorldState
var _player_ref: Node3D
var _suspended: bool = false

func _ready():
	set_process(false)

func configure_start_state(state: WorldState):
	_start_state = state

func configure_settings(settings: GameSettings):
	_settings = settings

func initialize_world_async() -> void:
	config = config.runtime_copy_for_seed(_start_state.seed)
	var config_valid := config.validate()
	var block_catalog_valid := block_catalog.validate()
	var foliage_catalog_valid := foliage_catalog.validate(block_catalog)
	assert(config_valid)
	assert(block_catalog_valid)
	assert(foliage_catalog_valid)

	generation_progress.emit("config", 0.05, "Preparing config (seed %d)" % config.seed_value)
	await get_tree().process_frame
	generation_progress.emit("terrain", 0.1, "Generating terrain")
	var foliage_generator := FoliageGenerator.new(foliage_catalog, config.seed_value)
	terrain_generator = TerrainGenerator.new(config, foliage_generator)
	var generation := terrain_generator.generate_all()
	generation_progress.emit("terrain", 0.3, "Terrain prepared")
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

func _create_world_model(generation: Dictionary):
	voxel_model = VoxelWorld.new(config.chunk_size, config.max_build_y, config.water_level, config.meadow_radius, block_catalog)
	voxel_model.set_generator_ref(terrain_generator)
	voxel_model.apply_chunk_gen(generation)
	voxel_model.apply_tree_chunk(generation)
	voxel_model.restore_block_edits(_start_state.placed_blocks, _start_state.removed_blocks)
	voxel_model.torch_attachments = _start_state.torch_attachments.duplicate()
	assert(voxel_model.restore_emplacements(_start_state.emplacements))
	for pos in _start_state.removed_blocks:
		voxel_model.tree_block_fast.erase(pos)
	voxel_model.block_edit_committed.connect(_on_block_edit_committed)
	voxel_model.foliage_visibility_changed.connect(_on_foliage_visibility_changed)

func _setup_systems():
	chunk_mesher = ChunkMesher.new(config.chunk_size, config.max_build_y, config.seed_value, config.enable_ao, block_texture_set)
	foliage_mesher = FoliageMesher.new(foliage_texture_set, config.seed_value)
	chunk_scheduler.setup(chunk_mesher, foliage_mesher, terrain_generator, voxel_model, config.chunk_size, config.max_build_y)
	chunk_renderer.setup(chunk_mesher, foliage_mesher, terrain_material, water_block_material, foliage_material, voxel_model, _settings.get_shadow_chunk_radius())
	torch_renderer.setup(block_catalog, _settings.torch_shadow_count, 0.0)
	anvil_renderer.setup()
	chest_renderer.setup(block_catalog)
	cauldron_renderer.setup()
	campfire_renderer.setup(block_catalog, campfire_audio_profile)
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
	block_texture_set = BlockTextureSet.new(block_catalog)
	foliage_texture_set = FoliageTextureSet.new(foliage_catalog)
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = terrain_shader
	terrain_material.set_shader_parameter("terrain_textures", block_texture_set.texture_array)
	foliage_material = ShaderMaterial.new()
	foliage_material.shader = foliage_shader
	foliage_material.set_shader_parameter("foliage_textures", foliage_texture_set.texture_array)

	water_block_material = ShaderMaterial.new()
	water_block_material.shader = water_shader
	water_profile.apply_to_material(water_block_material)
	_water_ripples.setup(water_block_material, water_profile.ripple_duration)
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
	if _suspended:
		return
	_water_ripples.tick(delta)
	chunk_manager.tick(_player_ref.global_position)
	chunk_manager.poll_completed()
	voxel_model.prune_terrain_cache(2)
	torch_renderer.update_shadow_culling(delta)
	campfire_renderer.update_shadow_culling(delta)

func _on_chunk_loaded(coord: Vector2i):
	torch_renderer.load_torches_for_chunk(coord.x, coord.y, config.chunk_size, voxel_model.torch_attachments)
	anvil_renderer.load_anvils_for_chunk(coord.x, coord.y, config.chunk_size, voxel_model)
	chest_renderer.load_chests_for_chunk(coord.x, coord.y, config.chunk_size, voxel_model)
	cauldron_renderer.load_cauldrons_for_chunk(coord.x, coord.y, config.chunk_size, voxel_model)
	campfire_renderer.load_campfires_for_chunk(coord.x, coord.y, voxel_model)

func _on_chunk_unloaded(coord: Vector2i):
	torch_renderer.unload_torches_in_chunk(coord.x, coord.y, config.chunk_size)
	anvil_renderer.unload_anvils_in_chunk(coord.x, coord.y, config.chunk_size)
	chest_renderer.unload_chests_in_chunk(coord.x, coord.y, config.chunk_size)
	cauldron_renderer.unload_cauldrons_in_chunk(coord.x, coord.y, config.chunk_size)
	campfire_renderer.unload_campfires_in_chunk(coord.x, coord.y, config.chunk_size)

func _on_block_edit_committed(edit: BlockEdit):
	var edit_chunk := ChunkCoord.world_to_chunk_vec3i(edit.pos, config.chunk_size)
	if edit.is_mine() and edit.old_id == BlockId.Type.TORCH:
		torch_renderer.remove_torch(edit.pos)
	elif edit.new_id == BlockId.Type.TORCH:
		if chunk_manager.visible_chunks.has(edit_chunk):
			torch_renderer.spawn_torch(edit.pos, edit.attach_dir)
	elif edit.is_mine() and edit.old_id == BlockId.Type.ANVIL:
		anvil_renderer.remove_anvil(edit.pos)
		chunk_manager.queue_rebuild_for_world_pos(edit.pos)
	elif edit.new_id == BlockId.Type.ANVIL:
		if chunk_manager.visible_chunks.has(edit_chunk):
			anvil_renderer.spawn_anvil(edit.pos)
	elif edit.is_mine() and edit.old_id == BlockId.Type.CHEST:
		chest_renderer.remove_chest(edit.pos)
		chunk_manager.queue_rebuild_for_world_pos(edit.pos)
	elif edit.new_id == BlockId.Type.CHEST:
		if chunk_manager.visible_chunks.has(edit_chunk):
			chest_renderer.spawn_chest(edit.pos)
		chunk_manager.queue_rebuild_for_world_pos(edit.pos)
	elif edit.is_mine() and edit.old_id == BlockId.Type.CAULDRON:
		cauldron_renderer.remove_cauldron(edit.pos)
		chunk_manager.queue_rebuild_for_world_pos(edit.pos)
	elif edit.new_id == BlockId.Type.CAULDRON:
		if chunk_manager.visible_chunks.has(edit_chunk):
			cauldron_renderer.spawn_cauldron(edit.pos)
		chunk_manager.queue_rebuild_for_world_pos(edit.pos)
	elif edit.is_mine() and edit.old_id == BlockId.Type.CAMPFIRE:
		campfire_renderer.remove_campfire(edit.pos)
		_refresh_emplacement_foliage(edit.pos, edit.old_id)
	elif edit.new_id == BlockId.Type.CAMPFIRE:
		if chunk_manager.visible_chunks.has(edit_chunk):
			campfire_renderer.spawn_campfire(edit.pos)
		_refresh_emplacement_foliage(edit.pos, edit.new_id)
	elif _is_foliage_only_edit(edit):
		chunk_manager.refresh_foliage(edit_chunk, voxel_model.get_visible_foliage_cells_for_chunk(edit_chunk))
	else:
		chunk_manager.queue_rebuild_for_world_pos(edit.pos)
	if BlockId.is_foliage(edit.old_id) and edit.new_id != BlockId.Type.AIR and not BlockId.is_foliage(edit.new_id) and edit.new_id != BlockId.Type.CAMPFIRE:
		chunk_manager.refresh_foliage(edit_chunk, voxel_model.get_visible_foliage_cells_for_chunk(edit_chunk))

func _refresh_emplacement_foliage(anchor: Vector3i, block_id: int) -> void:
	var definition := block_catalog.get_definition(block_id)
	var cells: Array[Vector3i] = []
	for offset in definition.emplacement.occupied_offsets:
		cells.append(anchor + offset)
	_on_foliage_visibility_changed(cells)

func _on_foliage_visibility_changed(cells: Array[Vector3i]) -> void:
	var changed_chunks: Dictionary = {}
	for position in cells:
		changed_chunks[ChunkCoord.world_to_chunk_vec3i(position, config.chunk_size)] = true
	for coord in changed_chunks:
		chunk_manager.refresh_foliage(coord, voxel_model.get_visible_foliage_cells_for_chunk(coord))

func _is_foliage_only_edit(edit: BlockEdit) -> bool:
	var old_is_foliage := BlockId.is_foliage(edit.old_id)
	var new_is_foliage := BlockId.is_foliage(edit.new_id)
	return (old_is_foliage or new_is_foliage) and (old_is_foliage or edit.old_id == BlockId.Type.AIR) and (new_is_foliage or edit.new_id == BlockId.Type.AIR)

func set_player_ref(player: Node3D):
	assert(player != null and chunk_manager != null)
	_player_ref = player
	torch_renderer.set_player_ref(player)
	campfire_renderer.set_player_ref(player)
	set_process(true)

func is_position_streamed(position: Vector3) -> bool:
	if chunk_manager == null:
		return false
	var cell := Vector3i(floori(position.x), floori(position.y), floori(position.z))
	var coord := ChunkCoord.world_to_chunk_vec3i(cell, config.chunk_size)
	return chunk_manager.visible_chunks.has(coord)

func apply_settings(settings: GameSettings):
	_settings = settings
	if _suspended:
		return
	_apply_renderer_settings()

func _apply_renderer_settings():
	chunk_renderer.set_shadow_render_distance(_settings.get_shadow_chunk_radius())
	torch_renderer.set_max_shadow_torches(_settings.torch_shadow_count)

func update_water_tint(sky_color: Color):
	var sky_luminance: float = (sky_color.r + sky_color.g + sky_color.b) / 3.0
	var night_factor: float = clamp(1.0 - sky_luminance * 1.8, 0.0, 1.0)
	var tint: Vector4 = water_profile.tint_color * lerp(1.0, 0.6, night_factor)
	tint.x = maxf(tint.x, 0.03)
	tint.y = maxf(tint.y, 0.12)
	tint.z = maxf(tint.z, 0.25)
	water_block_material.set_shader_parameter("tint_color", tint)

func play_water_ripple(position: Vector3, planar_velocity: Vector2) -> void:
	_water_ripples.play(position, planar_velocity)

func try_set_water_ripple_strength(strength: float) -> bool:
	return _water_ripples.try_set_strength(strength)

func suspend():
	if _suspended:
		return
	_suspended = true
	chunk_manager.suspend()
	visible = false

func resume():
	if not _suspended:
		return
	chunk_manager.resume()
	_apply_renderer_settings()
	visible = true
	_suspended = false

func is_suspended() -> bool:
	return _suspended

func shutdown():
	set_process(false)
	_water_ripples.clear()
	campfire_renderer.clear()
	chunk_manager.shutdown()
