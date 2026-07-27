extends Node3D
class_name WorldController

## WorldController - coordinates generation, model, rendering
## Single truth: config .tres, typed DI, no forwarders, no second caches, no duplicate timers

@export var config: WorldConfig

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
	get: return config.seed_value if config else 1337
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


func _ready():
	if config == null:
		var p = "res://world/generation/world_config.tres"
		if ResourceLoader.exists(p):
			config = load(p) as WorldConfig
		if config == null:
			config = WorldConfig.new()
	# Config validation - single source of truth, called here (was never called at line 88)
	if not config.validate():
		push_error("[WorldController] Invalid config, using fallback defaults")
		config = WorldConfig.new()
	print("[Wildes] Generating %dx%d world (seed %d) from %s ..." % [world_size, world_size, seed_value, config.resource_path if config.resource_path != "" else "config"])

	terrain_generator = TerrainGenerator.new(config)
	var gen = terrain_generator.generate_all()

	voxel_model = VoxelWorld.new(world_size, chunk_size, max_build_y)
	voxel_model.setup(world_size, chunk_size, max_build_y, gen["height_map"], gen["type_map"], gen["tree_block_fast"], gen["tree_blocks"])
	voxel_model.block_edit_committed.connect(_on_block_edit_committed)

	_prepare_materials()
	_setup_rendering_systems()
	chunk_renderer.generate_all_chunks()
	_create_water_plane()

	print("[Wildes] World ready: %d chunks gen=%s model=%s" % [chunk_renderer.chunk_instances.size(), terrain_generator.get_stats(), voxel_model.get_stats()])


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
		# Only set uniforms that exist in terrain.gdshader: world_size, haze_color, terrain_saturation, terrain_contrast
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
