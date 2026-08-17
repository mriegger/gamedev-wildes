extends Node3D
class_name LevelRuntime

const DUNGEON_TORCH_SHADOW_FADE_SECONDS: float = 0.45
const MAX_RETIRING_ENTITIES: int = LevelRoomEncounterDefinition.MAX_ENEMY_COUNT
const MAX_NAVIGATION_SEARCH_RADIUS: int = 48
const MAX_NAVIGATION_SEARCH_NODES: int = 2048
const MAX_NAVIGATION_SEARCHES_PER_TICK: int = 2

@onready var _geometry_renderer: LevelGeometryRenderer = $Geometry as LevelGeometryRenderer
@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _torch_renderer: TorchRenderer = $Torches
@onready var _return_point: Marker3D = $ReturnPoint
@onready var _return_door: MeshInstance3D = $ReturnDoor
@onready var _encounter_hud: LevelEncounterHUD = $EncounterHUD as LevelEncounterHUD

var _state: LevelState
var _topology: LevelEncounterTopology
var _encounter_state: LevelEncounterState
var _entity_runtime: EntityRuntime
var _encounter_coordinator: LevelEncounterCoordinator
var _player: PlayerMotor
var _level_environment: Environment

func _ready() -> void:
	visible = false
	set_process(false)
	set_physics_process(false)

func setup(
	layout: LevelLayout,
	definition: LevelDefinition,
	block_catalog: BlockCatalog,
	texture_set: BlockTextureSet,
	settings: GameSettings,
	entity_catalog: EntityCatalog,
) -> void:
	assert(is_node_ready())
	assert(_state == null)
	assert(layout != null)
	assert(definition != null and definition.presentation != null)
	assert(entity_catalog != null and entity_catalog.validate())
	var presentation := definition.presentation
	_state = LevelState.from_layout(layout, block_catalog)
	_topology = LevelEncounterTopology.create(layout, definition)
	assert(_topology != null)
	_encounter_state = LevelEncounterState.create(_topology, layout.seed_value)
	assert(_encounter_state != null)
	_entity_runtime = EntityRuntime.new()
	_entity_runtime.name = "Entities"
	add_child(_entity_runtime)
	_entity_runtime.setup(
		entity_catalog,
		_state,
		_topology.get_maximum_simultaneous_encounter_enemy_count(),
		MAX_RETIRING_ENTITIES,
		EntityNavigationLimits.new(
			MAX_NAVIGATION_SEARCH_RADIUS,
			MAX_NAVIGATION_SEARCH_NODES,
			MAX_NAVIGATION_SEARCHES_PER_TICK,
		),
	)
	_encounter_coordinator = LevelEncounterCoordinator.new()
	_encounter_coordinator.name = "EncounterCoordinator"
	add_child(_encounter_coordinator)
	assert(_encounter_coordinator.setup(
		_topology,
		_encounter_state,
		_state,
		_entity_runtime,
		entity_catalog,
		layout.seed_value,
	))
	_encounter_coordinator.seals_opened.connect(_on_seals_opened)
	_encounter_coordinator.encounter_summary_changed.connect(_encounter_hud.show_summary)
	_encounter_coordinator.room_cleared.connect(_on_room_cleared)
	_level_environment = _create_environment(presentation)
	_torch_renderer.setup(block_catalog, settings.dungeon_torch_shadow_count, DUNGEON_TORCH_SHADOW_FADE_SECONDS)
	var torch_attachments: Dictionary = {}
	for torch in layout.torches:
		torch_attachments[torch.cell] = LevelSocketDefinition.vector_for(torch.wall_direction)
	_torch_renderer.spawn_torches(torch_attachments)
	assert(_geometry_renderer.setup(
		layout,
		_state,
		_topology,
		_encounter_state.get_sealed_door_ids(),
		_encounter_state.get_discovered_room_ids(),
		texture_set,
		presentation.terrain_shader,
		_torch_renderer,
	))
	_return_point.position = _state.get_return_door_position()
	_setup_return_door(block_catalog, presentation.return_door_block_id)
	suspend_simulation()

func _process(delta: float) -> void:
	_torch_renderer.update_shadow_culling(delta)

func _physics_process(delta: float) -> void:
	if _player == null:
		return
	_encounter_coordinator.tick()
	_entity_runtime.tick(delta, _player.global_position)

func activate() -> void:
	assert(_state != null)
	_world_environment.environment = _level_environment
	_encounter_hud.visible = true
	visible = true
	_resume_simulation()

func deactivate() -> void:
	suspend_simulation()
	_encounter_hud.visible = false
	visible = false
	_world_environment.environment = null

func suspend_simulation() -> void:
	assert(_state != null)
	set_process(false)
	set_physics_process(false)
	_entity_runtime.suspend()
	_geometry_renderer.process_mode = Node.PROCESS_MODE_DISABLED
	_encounter_hud.process_mode = Node.PROCESS_MODE_DISABLED

func _resume_simulation() -> void:
	assert(_state != null)
	_geometry_renderer.process_mode = Node.PROCESS_MODE_INHERIT
	_encounter_hud.process_mode = Node.PROCESS_MODE_INHERIT
	_entity_runtime.resume()
	set_process(true)
	set_physics_process(true)

func get_voxel_space() -> VoxelSpace:
	return _state

func get_spawn_position() -> Vector3:
	assert(_state != null)
	return to_global(_state.get_spawn_position())

func get_return_door_position() -> Vector3:
	assert(_state != null)
	return _return_point.global_position

func get_entity_runtime() -> EntityRuntime:
	return _entity_runtime

func set_player_ref(player: Node3D) -> void:
	_torch_renderer.set_player_ref(player)
	if player is PlayerMotor:
		_player = player as PlayerMotor
		_encounter_coordinator.set_player(_player)

func apply_settings(settings: GameSettings) -> void:
	_torch_renderer.set_max_shadow_torches(settings.dungeon_torch_shadow_count)

func _on_seals_opened(seal_ids: Array[int]) -> void:
	_geometry_renderer.open_seals(seal_ids)

func _on_room_cleared(room_id: int) -> void:
	var room := _topology.get_room(room_id)
	assert(room != null)
	_geometry_renderer.discover_rooms(room.child_room_ids)
	if _encounter_state.get_summary().active_wave_count == 0:
		_encounter_hud.show_cleared()

func _setup_return_door(block_catalog: BlockCatalog, door_block_id: int) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.35, 2.4, 0.15)
	_return_door.mesh = mesh
	var direction := LevelSocketDefinition.vector_for(_state.get_return_door_facing())
	_return_door.position = _state.get_return_door_position() + Vector3(0, 1.2, 0) + Vector3(direction) * 0.42
	if direction.x != 0:
		_return_door.rotation.y = PI * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_texture = block_catalog.get_definition(door_block_id).side_texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.9
	_return_door.material_override = material

func _create_environment(presentation: LevelPresentationDefinition) -> Environment:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = presentation.background_color
	environment.background_energy_multiplier = presentation.background_energy_multiplier
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = presentation.ambient_light_color
	environment.ambient_light_energy = presentation.ambient_light_energy
	environment.ambient_light_sky_contribution = 0.0
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.glow_enabled = false
	environment.ssao_enabled = false
	environment.sdfgi_enabled = false
	environment.fog_enabled = false
	environment.volumetric_fog_enabled = false
	return environment
