extends Node3D
class_name LevelRuntime

const LEVEL_TERRAIN_SHADER := preload("res://levels/presentation/level_terrain.gdshader")

@onready var _geometry: MeshInstance3D = $Geometry
@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _torch_renderer: TorchRenderer = $Torches
@onready var _return_point: Marker3D = $ReturnPoint
@onready var _return_door: MeshInstance3D = $ReturnDoor

var _state: LevelState
var _level_environment: Environment
var _terrain_material: ShaderMaterial

func _ready() -> void:
	visible = false
	set_process(false)

func setup(
	layout: LevelLayout,
	block_catalog: BlockCatalog,
	texture_set: BlockTextureSet,
	settings: GameSettings
) -> void:
	assert(is_node_ready())
	assert(_state == null)
	assert(layout != null)
	_state = LevelState.from_layout(layout, block_catalog)
	_level_environment = _create_environment()
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = LEVEL_TERRAIN_SHADER
	_terrain_material.set_shader_parameter("terrain_textures", texture_set.texture_array)
	var mesher := LevelMesher.new(texture_set)
	_geometry.mesh = mesher.create_mesh(_state)
	assert(_geometry.mesh != null)
	_geometry.material_override = _terrain_material
	_geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_torch_renderer.setup(block_catalog, settings.torch_shadow_count)
	var torch_attachments: Dictionary = {}
	for torch in layout.torches:
		torch_attachments[torch.cell] = LevelSocketDefinition.vector_for(torch.wall_direction)
	_torch_renderer.spawn_torches(torch_attachments)
	_return_point.position = _state.get_return_door_position()
	_setup_return_door(block_catalog)

func _process(delta: float) -> void:
	_torch_renderer.update_shadow_culling(delta)

func activate() -> void:
	assert(_state != null)
	_world_environment.environment = _level_environment
	visible = true
	set_process(true)

func deactivate() -> void:
	set_process(false)
	visible = false
	_world_environment.environment = null

func get_voxel_space() -> VoxelSpace:
	return _state

func get_spawn_position() -> Vector3:
	assert(_state != null)
	return to_global(_state.get_spawn_position())

func get_return_door_position() -> Vector3:
	assert(_state != null)
	return _return_point.global_position

func set_player_ref(player: Node3D) -> void:
	_torch_renderer.set_player_ref(player)

func apply_settings(settings: GameSettings) -> void:
	_torch_renderer.set_max_shadow_torches(settings.torch_shadow_count)

func _setup_return_door(block_catalog: BlockCatalog) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.35, 2.4, 0.15)
	_return_door.mesh = mesh
	var direction := LevelSocketDefinition.vector_for(_state.get_return_door_facing())
	_return_door.position = _state.get_return_door_position() + Vector3(0, 1.2, 0) + Vector3(direction) * 0.42
	if direction.x != 0:
		_return_door.rotation.y = PI * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_texture = block_catalog.get_definition(BlockId.Type.LOG).side_texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.9
	_return_door.material_override = material

func _create_environment() -> Environment:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.002, 0.003, 0.005, 1.0)
	environment.background_energy_multiplier = 0.1
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.42, 0.44, 0.48, 1.0)
	environment.ambient_light_energy = 0.28
	environment.ambient_light_sky_contribution = 0.0
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.glow_enabled = false
	environment.ssao_enabled = false
	environment.sdfgi_enabled = false
	environment.fog_enabled = false
	environment.volumetric_fog_enabled = false
	return environment
