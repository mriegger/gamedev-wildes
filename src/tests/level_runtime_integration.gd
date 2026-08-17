extends SceneTree

const LEVEL_RUNTIME_SCENE: String = "res://levels/runtime/level_runtime.tscn"
const STRUCTURE_RUNTIME_SCENE: String = "res://structures/runtime/structure_designer_runtime.tscn"
const STRUCTURE_DIALOGS_SCENE: String = "res://structures/presentation/structure_designer_dialogs.tscn"
const STRUCTURE_TERRAIN_SHADER: String = "res://levels/presentation/level_terrain.gdshader"
const STRUCTURE_RUNTIME_TEST = preload("res://structures/tests/structure_designer_runtime.gd")
const WORLD_SCENE: String = "res://world/world.tscn"
const CATALOG_PATH: String = "res://levels/content/dungeons/stone/level_catalog.tres"
const BLOCK_CATALOG_PATH: String = "res://blocks/block_catalog.tres"
const LIFECYCLE_ITERATIONS: int = 12
const GAME_TRANSITION_CYCLES: int = 3

class TransitionGame:
	extends Game

	var level_was_suspended_at_fade_start: bool = false

	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_input(false)

	func _fade_to(alpha: float) -> void:
		if alpha > 0.0 and _level_runtime != null:
			level_was_suspended_at_fade_start = not _level_runtime.is_processing() \
				and not _level_runtime.is_physics_processing() \
				and _level_runtime.get_entity_runtime().is_suspended() \
				and _level_runtime._geometry_renderer.process_mode == Node.PROCESS_MODE_DISABLED \
				and _level_runtime._encounter_hud.process_mode == Node.PROCESS_MODE_DISABLED
		_fade.visible = not is_zero_approx(alpha)
		_fade.color = Color(0.0, 0.0, 0.0, alpha)
		await get_tree().process_frame

var _failures: int = 0
var _assertions: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var catalog := load(CATALOG_PATH) as LevelCatalog
	var block_catalog := load(BLOCK_CATALOG_PATH) as BlockCatalog
	var runtime_scene := load(LEVEL_RUNTIME_SCENE) as PackedScene
	var world_scene := load(WORLD_SCENE) as PackedScene
	_expect(catalog != null and catalog.validate(), "level catalog did not load or validate")
	_expect(block_catalog != null and block_catalog.validate(), "block catalog did not load or validate")
	_expect(runtime_scene != null, "level runtime scene did not load")
	_expect(world_scene != null, "world scene did not load")
	if catalog == null or block_catalog == null or runtime_scene == null or world_scene == null:
		call_deferred("_finish", 0)
		return
	var generation := LevelGenerator.new().generate(catalog, &"stone_dungeon", 1337, &"runtime_test", Vector3i(7, 0, -9))
	_expect(generation.succeeded, "runtime fixture generation failed: %s" % generation.failure_reason)
	if not generation.succeeded:
		call_deferred("_finish", 0)
		return
	var texture_set := BlockTextureSet.new(block_catalog)
	var definition := catalog.get_level(&"stone_dungeon")
	var settings := GameSettings.new()
	settings.dungeon_torch_shadow_count = 0
	var root_child_baseline := root.get_child_count()
	var orphan_baseline := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for iteration in range(LIFECYCLE_ITERATIONS):
		await _run_runtime_lifecycle(runtime_scene, generation.layout, definition, block_catalog, texture_set, settings, iteration)
	_expect(root.get_child_count() == root_child_baseline, "runtime lifecycle left children attached to SceneTree root")
	await _test_world_suspension(world_scene)
	await _test_game_transitions(catalog, block_catalog, runtime_scene)
	var structure_runtime_test := STRUCTURE_RUNTIME_TEST.new()
	var structure_runtime_failures: Array[String] = await structure_runtime_test.run(self)
	for failure in structure_runtime_failures:
		_expect(false, "structure runtime: %s" % failure)
	await process_frame
	await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == orphan_baseline, "level/world lifecycle changed orphan count from %d to %d" % [orphan_baseline, orphan_count])
	call_deferred("_finish", orphan_count)

func _run_runtime_lifecycle(
	runtime_scene: PackedScene,
	layout: LevelLayout,
	definition: LevelDefinition,
	block_catalog: BlockCatalog,
	texture_set: BlockTextureSet,
	settings: GameSettings,
	iteration: int
) -> void:
	var runtime := runtime_scene.instantiate() as LevelRuntime
	_expect(runtime != null, "runtime scene root is not LevelRuntime at iteration %d" % iteration)
	if runtime == null:
		return
	runtime.position = Vector3(float(iteration), 0.0, float(-iteration))
	root.add_child(runtime)
	await process_frame
	_expect(runtime.is_node_ready(), "runtime was not ready before setup at iteration %d" % iteration)
	_expect(not runtime.visible and not runtime.is_processing(), "runtime starts active at iteration %d" % iteration)
	runtime.setup(layout, definition, block_catalog, texture_set, settings, load("res://entities/entity_catalog.tres") as EntityCatalog)
	_expect(not runtime.is_processing() and not runtime.is_physics_processing() and runtime.get_entity_runtime().is_suspended(), "setup left dungeon simulation active at iteration %d" % iteration)
	_expect(runtime._geometry_renderer.process_mode == Node.PROCESS_MODE_DISABLED and runtime._encounter_hud.process_mode == Node.PROCESS_MODE_DISABLED, "setup left dungeon presentation timers active at iteration %d" % iteration)
	var state := runtime.get_voxel_space() as LevelState
	_expect(state != null, "runtime did not expose LevelState at iteration %d" % iteration)
	if state != null:
		_expect(state.get_spawn_facing() == layout.spawn_facing, "runtime spawn facing changed at iteration %d" % iteration)
		_expect(state.get_return_door_facing() == layout.return_door_facing, "runtime return facing changed at iteration %d" % iteration)
		_expect(state.get_bounds_min() == layout.bounds_min and state.get_bounds_max() == layout.bounds_max, "runtime state bounds changed at iteration %d" % iteration)
		_expect(state.snapshot_cells() == layout.cells, "runtime state cells differ from generated layout at iteration %d" % iteration)
	var expected_spawn := runtime.to_global(Vector3(layout.spawn_cell) + Vector3(0.5, 0.0, 0.5))
	var expected_return := runtime.to_global(Vector3(layout.return_door_cell) + Vector3(0.5, 0.0, 0.5))
	_expect(runtime.get_spawn_position().is_equal_approx(expected_spawn), "runtime spawn position changed at iteration %d" % iteration)
	_expect(runtime.get_return_door_position().is_equal_approx(expected_return), "runtime return position changed at iteration %d" % iteration)
	var geometry := runtime.get_node("Geometry") as LevelGeometryRenderer
	var environment_node := runtime.get_node("WorldEnvironment") as WorldEnvironment
	var torch_renderer := runtime.get_node("Torches") as TorchRenderer
	var return_door := runtime.get_node("ReturnDoor") as MeshInstance3D
	_expect(geometry != null and geometry.get_node_or_null("EntryGeometry") is MeshInstance3D, "runtime entry geometry was not built at iteration %d" % iteration)
	_expect(geometry != null and geometry._room_meshes.size() == runtime._topology.get_room_ids().size(), "runtime omitted room branch geometry at iteration %d" % iteration)
	_expect(geometry != null and geometry._seal_meshes.size() == runtime._topology.get_doorways().size(), "runtime omitted authored doorway seals at iteration %d" % iteration)
	_expect(runtime.get_entity_runtime()._max_active == runtime._topology.get_maximum_simultaneous_encounter_enemy_count(), "runtime ignored topology-derived encounter capacity at iteration %d" % iteration)
	var entry_mesh := geometry.get_node("EntryGeometry") as MeshInstance3D
	var terrain_material := entry_mesh.material_override as ShaderMaterial
	_expect(terrain_material != null and terrain_material.shader.resource_path == "res://levels/presentation/level_terrain.gdshader", "runtime terrain shader changed at iteration %d" % iteration)
	_expect(terrain_material != null and terrain_material.get_shader_parameter("terrain_textures") == texture_set.texture_array, "runtime terrain texture array changed at iteration %d" % iteration)
	for room_id in runtime._topology.get_room_ids():
		var progress := runtime._encounter_state._rooms[room_id] as LevelEncounterState.RoomProgress
		var discovered := progress.status != LevelEncounterState.RoomStatus.LOCKED
		var room_mesh := geometry._room_meshes[room_id] as MeshInstance3D
		_expect(room_mesh.material_override == terrain_material, "runtime room branch did not share the terrain material at iteration %d room %d" % [iteration, room_id])
		_expect(room_mesh.visible == discovered, "runtime room branch visibility changed at iteration %d room %d" % [iteration, room_id])
		_expect(is_equal_approx(room_mesh.transparency, 0.0 if discovered else 1.0), "runtime room branch transparency changed at iteration %d room %d" % [iteration, room_id])
		_expect(
			room_mesh.cast_shadow == (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if discovered else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF),
			"runtime room branch shadow state changed at iteration %d room %d" % [iteration, room_id],
		)
		for torch_cell in geometry._room_torch_cells[room_id] as Array[Vector3i]:
			_expect_runtime_torch_discovery_state(torch_renderer, torch_cell, discovered, iteration, room_id)
	var sealed_door_ids := runtime._encounter_state.get_sealed_door_ids()
	for doorway in runtime._topology.get_doorways():
		var owner_progress := runtime._encounter_state._rooms[doorway.room_id] as LevelEncounterState.RoomProgress
		var owner_discovered := owner_progress.status != LevelEncounterState.RoomStatus.LOCKED
		var expected_visible := sealed_door_ids.has(doorway.door_id) and owner_discovered
		var seal_mesh := geometry._seal_meshes[doorway.door_id] as MeshInstance3D
		_expect(seal_mesh.material_override == terrain_material, "runtime seal did not share the authored terrain material at iteration %d door %d" % [iteration, doorway.door_id])
		_expect(seal_mesh.visible == expected_visible, "runtime seal visibility changed at iteration %d door %d" % [iteration, doorway.door_id])
		_expect(is_equal_approx(seal_mesh.transparency, 0.0 if expected_visible else 1.0), "runtime seal transparency changed at iteration %d door %d" % [iteration, doorway.door_id])
		_expect(
			seal_mesh.cast_shadow == (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if expected_visible else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF),
			"runtime seal shadow state changed at iteration %d door %d" % [iteration, doorway.door_id],
		)
	_expect(runtime.get_node_or_null("Doors") == null, "runtime retained the removed sliding-door presentation at iteration %d" % iteration)
	_expect(torch_renderer.torch_instances.size() == layout.torches.size(), "runtime spawned %d/%d authored torches at iteration %d" % [torch_renderer.torch_instances.size(), layout.torches.size(), iteration])
	_expect((return_door.material_override as StandardMaterial3D).albedo_texture == block_catalog.get_definition(definition.presentation.return_door_block_id).side_texture, "runtime ignored the authored return-door block at iteration %d" % iteration)
	for torch in layout.torches:
		_expect(torch_renderer.has_torch(torch.cell), "runtime omitted authored torch %s at iteration %d" % [torch.cell, iteration])
	for cycle in range(3):
		runtime.activate()
		_expect(runtime.visible and runtime.is_processing(), "activate failed at iteration %d cycle %d" % [iteration, cycle])
		_expect(runtime.is_physics_processing() and not runtime.get_entity_runtime().is_suspended(), "activate did not resume dungeon simulation at iteration %d cycle %d" % [iteration, cycle])
		_expect(runtime._geometry_renderer.process_mode == Node.PROCESS_MODE_INHERIT and runtime._encounter_hud.process_mode == Node.PROCESS_MODE_INHERIT, "activate did not resume dungeon presentation timers at iteration %d cycle %d" % [iteration, cycle])
		_expect(environment_node.environment != null, "activate did not install the level environment at iteration %d cycle %d" % [iteration, cycle])
		_expect(environment_node.environment.background_color == definition.presentation.background_color, "runtime ignored the authored background color at iteration %d cycle %d" % [iteration, cycle])
		_expect(environment_node.environment.ambient_light_color == definition.presentation.ambient_light_color, "runtime ignored the authored ambient light at iteration %d cycle %d" % [iteration, cycle])
		runtime.apply_settings(settings)
		for light in torch_renderer.torch_light_nodes.values():
			_expect(not (light as OmniLight3D).shadow_enabled, "zero-shadow setting left a torch shadow enabled at iteration %d cycle %d" % [iteration, cycle])
		runtime.deactivate()
		_expect(not runtime.visible and not runtime.is_processing(), "deactivate failed at iteration %d cycle %d" % [iteration, cycle])
		_expect(not runtime.is_processing() and not runtime.is_physics_processing() and runtime.get_entity_runtime().is_suspended(), "deactivate left dungeon simulation active at iteration %d cycle %d" % [iteration, cycle])
		_expect(runtime._geometry_renderer.process_mode == Node.PROCESS_MODE_DISABLED and runtime._encounter_hud.process_mode == Node.PROCESS_MODE_DISABLED, "deactivate left dungeon presentation timers active at iteration %d cycle %d" % [iteration, cycle])
		_expect(environment_node.environment == null, "deactivate retained the level environment at iteration %d cycle %d" % [iteration, cycle])
	runtime.queue_free()
	await process_frame
	await process_frame
	_expect(not is_instance_valid(runtime), "queued runtime survived teardown at iteration %d" % iteration)

func _test_world_suspension(world_scene: PackedScene) -> void:
	var world := world_scene.instantiate() as WorldController
	_expect(world != null, "world scene root is not WorldController")
	if world == null:
		return
	root.add_child(world)
	await process_frame
	var voxel_world := VoxelWorld.new(
		world.config.chunk_size,
		world.config.max_build_y,
		world.config.water_level,
		world.config.meadow_radius,
		world.block_catalog
	)
	var manager := ChunkManager.new()
	manager.setup(world.config, voxel_world, world.chunk_scheduler, world.chunk_renderer)
	world.voxel_model = voxel_world
	world.chunk_manager = manager
	var settings := GameSettings.new()
	settings.shadow_range = GameSettings.SHADOW_RANGE_HIGH
	settings.torch_shadow_count = 4
	world.configure_settings(settings)
	world.visible = true
	_expect(not world.is_suspended(), "world starts suspended")
	world.suspend()
	_expect(world.is_suspended(), "world suspend state was not recorded")
	_expect(manager._suspended, "world suspend did not reach ChunkManager")
	_expect(world.chunk_scheduler._suspended, "world suspend did not reach ChunkBuildScheduler")
	_expect(not world.visible, "suspended world remained visible")
	world.apply_settings(settings)
	_expect(world.chunk_renderer._shadow_render_distance != settings.get_shadow_chunk_radius(), "suspended world applied renderer settings immediately")
	_expect(world.torch_renderer._max_shadow_torches != settings.torch_shadow_count, "suspended world updated torch culling immediately")
	world.suspend()
	_expect(world.is_suspended() and manager._suspended and world.chunk_scheduler._suspended, "repeated suspend was not idempotent")
	world.resume()
	_expect(not world.is_suspended(), "world resume state was not recorded")
	_expect(not manager._suspended, "world resume did not reach ChunkManager")
	_expect(not world.chunk_scheduler._suspended, "world resume did not reach ChunkBuildScheduler")
	_expect(world.visible, "resumed world remained hidden")
	_expect(world.chunk_renderer._shadow_render_distance == settings.get_shadow_chunk_radius(), "world resume did not apply deferred shadow range")
	_expect(world.torch_renderer._max_shadow_torches == settings.torch_shadow_count, "world resume did not apply deferred torch culling")
	world.resume()
	_expect(not world.is_suspended() and not manager._suspended and not world.chunk_scheduler._suspended, "repeated resume was not idempotent")
	world.shutdown()
	world.queue_free()
	await process_frame
	await process_frame
	_expect(not is_instance_valid(world), "queued world survived teardown")

func _test_game_transitions(catalog: LevelCatalog, block_catalog: BlockCatalog, runtime_scene: PackedScene) -> void:
	var root_child_baseline := root.get_child_count()
	var game := TransitionGame.new()
	game.name = "TransitionGame"
	game.block_catalog = block_catalog
	game.item_catalog = load("res://items/item_catalog.tres") as ItemCatalog
	game.entity_catalog = load("res://entities/entity_catalog.tres") as EntityCatalog
	game.player_stats_definition = load("res://player/player_stats.tres") as CombatStatsDefinition
	game.level_catalog = catalog
	game.level_entrance_definition = load("res://levels/content/dungeons/stone/entrance.tres") as LevelEntranceDefinition
	game.level_runtime_scene = runtime_scene
	game.player_death_screen_scene = load("res://ui/screens/death/player_death_screen.tscn") as PackedScene
	game.structure_designer_runtime_scene = load(STRUCTURE_RUNTIME_SCENE) as PackedScene
	game.structure_terrain_shader = load(STRUCTURE_TERRAIN_SHADER) as Shader
	var world := (load(WORLD_SCENE) as PackedScene).instantiate() as WorldController
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as PlayerMotor
	var camera_rig := (load("res://player/camera/camera_rig.tscn") as PackedScene).instantiate() as CameraRig
	var environment := (load("res://environment/environment.tscn") as PackedScene).instantiate() as GameEnvironment
	var hud := (load("res://ui/hud/hud.tscn") as PackedScene).instantiate() as HUD
	var dev_console := (load("res://dev_console/presentation/dev_console.tscn") as PackedScene).instantiate() as DevConsole
	var structure_workflow := StructureDesignerWorkflow.new()
	var structure_dialogs := (load(STRUCTURE_DIALOGS_SCENE) as PackedScene).instantiate() as StructureDesignerDialogs
	var session := GameSession.new()
	var coordinator := LevelInteractionCoordinator.new()
	var entities := WorldEntityCoordinator.new()
	var combat := MeleeCombatCoordinator.new()
	var combat_hit_particles := (load("res://combat/particles/combat_hit_particles.tscn") as PackedScene).instantiate() as CombatHitParticles
	var mining_break_particles := (load("res://mining/presentation/mining_break_particles.tscn") as PackedScene).instantiate()
	var mining_hit_particles := (load("res://mining/presentation/mining_hit_particles.tscn") as PackedScene).instantiate()
	var pumpkin_patch := (load("res://farming/pumpkin/pumpkin_patch_coordinator.tscn") as PackedScene).instantiate() as PumpkinPatchCoordinator
	world.name = "World"
	player.name = "Player"
	player.process_mode = Node.PROCESS_MODE_INHERIT
	camera_rig.name = "CameraRig"
	environment.name = "Environment"
	hud.name = "HUD"
	dev_console.name = "DevConsole"
	structure_workflow.name = "StructureDesignerWorkflow"
	structure_dialogs.name = "StructureDesignerDialogs"
	session.name = "GameSession"
	coordinator.name = "LevelInteractionCoordinator"
	entities.name = "WorldEntities"
	combat.name = "MeleeCombat"
	combat_hit_particles.name = "CombatHitParticles"
	mining_break_particles.name = "MiningBreakParticles"
	mining_hit_particles.name = "MiningHitParticles"
	pumpkin_patch.name = "PumpkinPatch"
	game.add_child(world)
	game.add_child(player)
	game.add_child(camera_rig)
	game.add_child(environment)
	game.add_child(entities)
	game.add_child(combat)
	game.add_child(combat_hit_particles)
	game.add_child(hud)
	game.add_child(dev_console)
	game.add_child(structure_workflow)
	game.add_child(structure_dialogs)
	game.add_child(session)
	game.add_child(coordinator)
	game.add_child(mining_break_particles)
	game.add_child(mining_hit_particles)
	game.add_child(pumpkin_patch)
	var save_layer := CanvasLayer.new()
	save_layer.name = "SaveStatusLayer"
	var save_label := Label.new()
	save_label.name = "SaveStatusLabel"
	save_layer.add_child(save_label)
	game.add_child(save_layer)
	var transition_layer := CanvasLayer.new()
	transition_layer.name = "TransitionLayer"
	var fade := ColorRect.new()
	fade.name = "Fade"
	transition_layer.add_child(fade)
	game.add_child(transition_layer)
	var voxel_world := _make_flat_world(block_catalog)
	world.voxel_model = voxel_world
	world.block_texture_set = BlockTextureSet.new(block_catalog)
	world.config = world.config.runtime_copy_for_seed(1337)
	root.add_child(game)
	await process_frame
	_expect(game.world == world and game.player == player and game.camera_rig == camera_rig, "Game onready dependencies were not wired")
	_expect(game.game_environment == environment and game.level_interaction == coordinator and game.dev_console == dev_console and game.pumpkin_patch == pumpkin_patch, "Game transition dependencies were not wired")
	_expect(game.structure_designer_workflow == structure_workflow and game.structure_designer_dialogs == structure_dialogs, "Game structure designer dependencies were not wired")
	_expect(game.structure_designer_runtime_scene != null and game.structure_terrain_shader != null, "Game structure designer resources were not wired")
	var manager := ChunkManager.new()
	manager.setup(world.config, voxel_world, world.chunk_scheduler, world.chunk_renderer)
	world.chunk_manager = manager
	var settings := GameSettings.new()
	settings.dungeon_torch_shadow_count = 0
	settings.birds_enabled = false
	game.settings = settings
	world.configure_settings(settings)
	environment.setup(6.0, settings.get_shadow_distance())
	environment.apply_settings(settings)
	environment.start_clock()
	game.inventory_model = InventoryModel.new(game.item_catalog)
	game.inventory_model.setup_starter()
	dev_console.setup(
		game.inventory_model,
		pumpkin_patch,
		Callable(game, "_request_new_structure"),
		Callable(game, "_request_import_structure"),
		Callable(game, "_request_export_structure"),
		Callable(game, "_request_exit_structure")
	)
	dev_console.open_state_changed.connect(game._on_dev_console_open_state_changed)
	structure_dialogs.open_state_changed.connect(game._on_structure_dialog_open_state_changed)
	game.player_stats = ActorStats.new(game.player_stats_definition)
	camera_rig.setup(player, game.input_buffer)
	entities.setup(game.entity_catalog, voxel_world, 1337, _position_ready)
	combat.setup(voxel_world, player, game.player_stats, entities.get_runtime())
	player.setup(camera_rig, game.inventory_model, game.input_buffer, game.player_stats, combat, entities.get_runtime())
	game._bind_entity_context(voxel_world, entities.get_runtime())
	var world_entity_runtime := entities.get_runtime()
	var world_spawn := voxel_world.get_spawn_position()
	var doorway_anchor := world_spawn
	player.global_position = doorway_anchor
	player.bind_space(voxel_world, world, world_spawn, voxel_world)
	game._location_state = GameplayLocationState.new(doorway_anchor)
	structure_workflow.setup(structure_dialogs, StructureFileStore.new(ProjectSettings.globalize_path("res://../").simplify_path()))
	var prompt_coordinator := InteractionPromptCoordinator.new()
	prompt_coordinator.setup(hud, Callable(game, "_is_gameplay_ui_blocked"))
	coordinator.setup(player, prompt_coordinator)
	coordinator.interaction_requested.connect(game._on_level_interaction_requested)
	var entrance := LevelEntrance.new()
	entrance.name = "TestLevelEntrance"
	entrance.interaction_position = doorway_anchor + Vector3(1.0, 0.0, 0.0)
	game.add_child(entrance)
	game._level_entrance = entrance
	game._entrance_coordinate = Vector3i(floori(entrance.interaction_position.x), floori(entrance.interaction_position.y), floori(entrance.interaction_position.z))
	game._show_world_level_interaction()
	var inventory_identity := game.inventory_model
	var stats_identity := game.player_stats
	var preserved_yaw := 315.0
	var preserved_zoom := 31.5
	camera_rig.target_yaw_deg = preserved_yaw
	camera_rig.current_yaw_deg = preserved_yaw
	camera_rig.rotation_degrees.y = preserved_yaw
	camera_rig.camera.size = preserved_zoom
	var prompt_connections := coordinator.interaction_requested.get_connections()
	_expect(prompt_connections.size() == 1, "interaction coordinator does not have exactly one Game consumer")
	if prompt_connections.size() == 1:
		_expect(prompt_connections[0]["callable"] == Callable(game, "_on_level_interaction_requested"), "interaction coordinator is connected to the wrong consumer")
	for cycle in range(GAME_TRANSITION_CYCLES):
		doorway_anchor = Vector3(0.5 + float(cycle), world_spawn.y, 0.5)
		player.global_position = doorway_anchor
		game._location_state.update_world_position(doorway_anchor)
		await _run_structure_designer_cycle(game, false, cycle)
		player.interactor.melee_attack_timer = 1.0
		player.interactor.melee_attack_queue = 1
		player.interactor._melee_contact_pending = true
		player.interactor._melee_target_runtime_ids.assign([999999])
		await game._enter_level()
		var runtime := game._level_runtime
		var dungeon_entity_runtime := runtime.get_entity_runtime()
		_expect(runtime != null and is_instance_valid(runtime), "Game did not retain an active runtime in cycle %d" % cycle)
		_expect(game._location_state.is_in_level(), "Game location did not enter level in cycle %d" % cycle)
		_expect(game._get_persisted_position().is_equal_approx(doorway_anchor), "indoor persisted position differs from doorway anchor in cycle %d" % cycle)
		_expect(world.is_suspended() and manager._suspended and world.chunk_scheduler._suspended, "Game did not suspend world streaming in cycle %d" % cycle)
		_expect(entities.is_suspended() and not entities.visible, "Game did not suspend overworld entities in cycle %d" % cycle)
		_expect(not world.visible and not entrance.visible, "overworld presentation remained visible in cycle %d" % cycle)
		_expect(environment._world_environment.environment == null and not environment._sun.visible and not environment._sun_fill.visible, "outdoor environment remained active in cycle %d" % cycle)
		_expect(not environment._ambient_soundscape._running, "outdoor ambient audio remained active in cycle %d" % cycle)
		_expect(runtime.visible and runtime.is_processing(), "level runtime is inactive in cycle %d" % cycle)
		_expect(dungeon_entity_runtime != world_entity_runtime and not dungeon_entity_runtime.is_suspended(), "level entry did not activate a dedicated entity runtime in cycle %d" % cycle)
		_expect(game._active_entity_runtime == dungeon_entity_runtime and player.interactor.entity_runtime == dungeon_entity_runtime, "level entry did not rebind player entity queries in cycle %d" % cycle)
		_expect(combat._entity_runtime == dungeon_entity_runtime and combat._voxel_space == runtime.get_voxel_space(), "level entry did not rebind combat in cycle %d" % cycle)
		_expect(player.interactor.melee_attack_timer == 0.0 and player.interactor.melee_attack_queue == 0 and not player.interactor._melee_contact_pending and player.interactor._melee_target_runtime_ids.is_empty(), "level entry retained a pending overworld attack in cycle %d" % cycle)
		_expect(player.voxel_space == runtime.get_voxel_space(), "player is not bound to LevelState in cycle %d" % cycle)
		_expect(player.interactor.voxel_space == runtime.get_voxel_space(), "interactor is not bound to LevelState in cycle %d" % cycle)
		_expect(not player.interactor.is_editing_enabled() and player.interactor.editable_voxel_world == null, "level binding retained edit authority in cycle %d" % cycle)
		_expect(player.targeting_view.voxel_space == runtime.get_voxel_space(), "targeting view is not bound to LevelState in cycle %d" % cycle)
		_expect(player.targeting_view.selection_box.get_parent() == runtime, "level targeting visuals were not reparented in cycle %d" % cycle)
		_expect(game.inventory_model == inventory_identity, "level entry replaced inventory identity in cycle %d" % cycle)
		_expect(game.player_stats == stats_identity and player.stats == stats_identity, "level entry replaced player stats identity in cycle %d" % cycle)
		_expect(is_equal_approx(camera_rig.target_yaw_deg, preserved_yaw) and is_equal_approx(camera_rig.current_yaw_deg, preserved_yaw), "level entry changed camera yaw in cycle %d" % cycle)
		_expect(is_equal_approx(camera_rig.camera.size, preserved_zoom), "level entry changed camera zoom in cycle %d" % cycle)
		_expect(coordinator._has_target and coordinator._prompt == "F  Return to Wildes", "return prompt was not installed in cycle %d" % cycle)
		_expect(coordinator._target_position.is_equal_approx(runtime.get_return_door_position()), "return prompt target changed in cycle %d" % cycle)
		await _run_structure_designer_cycle(game, true, cycle)
		player.global_position += Vector3(2.0, 0.0, 1.0)
		_expect(game._get_persisted_position().is_equal_approx(doorway_anchor), "level-local movement changed persisted anchor in cycle %d" % cycle)
		game.level_was_suspended_at_fade_start = false
		await game._exit_level()
		_expect(game.level_was_suspended_at_fade_start, "level exit began fading before dungeon simulation suspended in cycle %d" % cycle)
		_expect(not game._location_state.is_in_level(), "Game location remained in level after cycle %d" % cycle)
		_expect(player.global_position.is_equal_approx(doorway_anchor), "Game restored %s instead of exact anchor %s in cycle %d" % [player.global_position, doorway_anchor, cycle])
		_expect(player.voxel_space == voxel_world and player.interactor.voxel_space == voxel_world, "player world binding was not restored in cycle %d" % cycle)
		_expect(player.interactor.is_editing_enabled() and player.interactor.editable_voxel_world == voxel_world, "world edit authority was not restored in cycle %d" % cycle)
		_expect(player.targeting_view.voxel_space == voxel_world and player.targeting_view.selection_box.get_parent() == world, "world targeting presentation was not restored in cycle %d" % cycle)
		_expect(not world.is_suspended() and not manager._suspended and not world.chunk_scheduler._suspended, "Game did not resume world streaming in cycle %d" % cycle)
		_expect(not entities.is_suspended() and entities.visible, "Game did not resume overworld entities in cycle %d" % cycle)
		_expect(game._active_entity_runtime == world_entity_runtime and player.interactor.entity_runtime == world_entity_runtime, "level exit did not restore player entity queries in cycle %d" % cycle)
		_expect(combat._entity_runtime == world_entity_runtime and combat._voxel_space == voxel_world, "level exit did not restore overworld combat in cycle %d" % cycle)
		_expect(world.visible and entrance.visible, "overworld presentation remained hidden after cycle %d" % cycle)
		_expect(environment._world_environment.environment != null and environment._sun.visible and environment._sun_fill.visible, "outdoor environment was not restored after cycle %d" % cycle)
		_expect(game._level_runtime == null and not is_instance_valid(runtime), "level runtime survived cycle %d teardown" % cycle)
		_expect(game.inventory_model == inventory_identity, "level exit replaced inventory identity in cycle %d" % cycle)
		_expect(game.player_stats == stats_identity and player.stats == stats_identity, "level exit replaced player stats identity in cycle %d" % cycle)
		_expect(is_equal_approx(camera_rig.target_yaw_deg, preserved_yaw) and is_equal_approx(camera_rig.current_yaw_deg, preserved_yaw), "level exit changed camera yaw in cycle %d" % cycle)
		_expect(is_equal_approx(camera_rig.camera.size, preserved_zoom), "level exit changed camera zoom in cycle %d" % cycle)
		_expect(coordinator._has_target and coordinator._prompt == "F  Enter Dungeon", "entry prompt was not restored in cycle %d" % cycle)
		_expect(coordinator._target_position.is_equal_approx(entrance.interaction_position), "entry prompt target changed in cycle %d" % cycle)
		_expect(coordinator.interaction_requested.get_connections().size() == 1, "transition duplicated interaction signal consumers in cycle %d" % cycle)
	var defeat_anchor := Vector3(9.5, world_spawn.y, 4.5)
	player.global_position = defeat_anchor
	game._location_state.update_world_position(defeat_anchor)
	await game._enter_level()
	var defeated_runtime := game._level_runtime
	var first_attempt_state := defeated_runtime._encounter_state
	game.player_stats.damage(game.player_stats.current_hp)
	game._on_player_defeated()
	_expect(defeated_runtime.get_entity_runtime().is_suspended() and not defeated_runtime.is_processing() and not defeated_runtime.is_physics_processing(), "dungeon defeat left encounter simulation active")
	_expect(defeated_runtime._geometry_renderer.process_mode == Node.PROCESS_MODE_DISABLED and defeated_runtime._encounter_hud.process_mode == Node.PROCESS_MODE_DISABLED, "dungeon defeat left encounter presentation timers active")
	var completed_screen := game._death_screen
	game._death_screen = null
	completed_screen.queue_free()
	await game._exit_level(true)
	_expect(not player.is_defeated() and not game.player_stats.is_dead(), "dungeon defeat did not restore player health")
	_expect(player.global_position.is_equal_approx(defeat_anchor), "dungeon defeat did not restore the exact overworld position")
	_expect(game.inventory_model == inventory_identity and game.player_stats == stats_identity, "dungeon defeat replaced player-owned state")
	_expect(game._active_entity_runtime == world_entity_runtime and player.interactor.entity_runtime == world_entity_runtime, "dungeon defeat did not restore the overworld entity runtime")
	_expect(not world.is_suspended() and not entities.is_suspended() and world.visible and entities.visible, "dungeon defeat did not restore overworld systems")
	_expect(environment._world_environment.environment != null and environment._sun.visible and environment._sun_fill.visible, "dungeon defeat did not restore the outdoor environment")
	_expect(not game.game_session.is_saving_suspended(), "dungeon defeat did not restore saving")
	_expect(game._level_runtime == null and not is_instance_valid(defeated_runtime), "dungeon defeat retained the failed runtime")
	await game._enter_level()
	var fresh_runtime := game._level_runtime
	_expect(fresh_runtime._encounter_state != first_attempt_state and fresh_runtime._encounter_state.get_active_room_ids().is_empty(), "dungeon re-entry did not create a fresh encounter attempt")
	await game._exit_level()
	player.unbind_space()
	game._unbind_entity_context()
	combat.shutdown()
	entities.shutdown()
	world.shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	await process_frame
	_expect(not is_instance_valid(game), "Game transition fixture survived teardown")
	_expect(root.get_child_count() == root_child_baseline, "Game transition fixture left root children behind")

func _run_structure_designer_cycle(game: TransitionGame, in_level: bool, cycle: int) -> void:
	var label := "%s cycle %d" % ["dungeon" if in_level else "overworld", cycle]
	var world := game.world
	var entities := game.world_entity_coordinator
	var player := game.player
	var camera_rig := game.camera_rig
	var hud := game.hud
	var level_interaction := game.level_interaction
	var environment := game.game_environment
	var level_runtime := game._level_runtime
	var location_state := game._location_state
	var persisted_position := location_state.get_persisted_position()
	var inventory_identity := game.inventory_model
	var player_position := player.global_position
	var player_voxel_space := player.voxel_space
	var player_process_mode := player.process_mode
	var player_physics_processing := player.is_physics_processing()
	var player_visible := player.visible
	var camera_process_mode := camera_rig.process_mode
	var camera_visible := camera_rig.visible
	var camera_current := camera_rig.camera.current
	var camera_input_enabled := camera_rig._gameplay_input_enabled
	var camera_yaw := camera_rig.current_yaw_deg
	var camera_target_yaw := camera_rig.target_yaw_deg
	var camera_size := camera_rig.camera.size
	var hud_process_mode := hud.process_mode
	var hud_visible := hud.visible
	var hotbar_input_enabled := hud.hotbar._selection_input_enabled
	var level_interaction_process_mode := level_interaction.process_mode
	var world_suspended := world.is_suspended()
	var world_visible := world.visible
	var entities_suspended := entities.is_suspended()
	var entities_visible := entities.visible
	var entrance_visible := game._level_entrance.visible
	var outdoor_environment := environment._world_environment.environment
	var outdoor_sun_visible := environment._sun.visible
	var outdoor_fill_visible := environment._sun_fill.visible
	var outdoor_audio_running := environment._ambient_soundscape._running
	var level_visible := level_runtime.visible if level_runtime != null else false
	var level_processing := level_runtime.is_processing() if level_runtime != null else false
	var level_environment := (level_runtime.get_node("WorldEnvironment") as WorldEnvironment).environment if level_runtime != null else null
	var clock_was_paused := cycle % 2 == 1
	var debug_panel_input_was_enabled := cycle % 2 == 0
	environment.set_clock_paused(clock_was_paused)
	if debug_panel_input_was_enabled:
		environment.restore_debug_panel_input()
	else:
		environment.close_debug_panel()
	var clock_time_before_designer := environment.get_time_of_day()
	var saving_was_suspended := cycle % 2 == 1
	if saving_was_suspended:
		game.game_session.suspend_saving()
	else:
		game.game_session.resume_saving()
	var orphan_baseline := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var draft := StructureDraft.create_generic(Vector3i(5, 4, 5))
	_expect(draft != null, "structure draft creation failed for %s" % label)
	if draft == null:
		return
	game.structure_designer_workflow._draft = draft
	if in_level:
		game.level_was_suspended_at_fade_start = false
	await game._enter_structure_designer(draft)
	if in_level:
		_expect(game.level_was_suspended_at_fade_start, "designer entry began fading before dungeon simulation suspended for %s" % label)
	var designer_runtime := game._structure_designer_runtime
	_expect(designer_runtime != null and is_instance_valid(designer_runtime), "designer runtime was not retained for %s" % label)
	_expect(game._location_state == location_state and game._location_state.is_in_level() == in_level, "designer entry changed GameplayLocationState for %s" % label)
	_expect(game._location_state.get_persisted_position().is_equal_approx(persisted_position), "designer entry changed the persisted position for %s" % label)
	_expect(game.inventory_model == inventory_identity and game.structure_designer_workflow._draft == draft, "designer entry replaced owned state for %s" % label)
	_expect(game.game_session.is_saving_suspended(), "designer entry did not suspend saving for %s" % label)
	_expect(environment.is_clock_paused(), "designer entry did not suspend the world clock for %s" % label)
	_expect(not environment.is_debug_panel_input_enabled(), "designer entry left environment debug input active for %s" % label)
	_expect(is_equal_approx(environment.get_time_of_day(), clock_time_before_designer), "world clock advanced during designer entry for %s" % label)
	_expect(player.process_mode == Node.PROCESS_MODE_DISABLED and not player.visible, "designer entry left the normal player active for %s" % label)
	_expect(camera_rig.process_mode == Node.PROCESS_MODE_DISABLED and not camera_rig.visible and not camera_rig.camera.current, "designer entry left the gameplay camera active for %s" % label)
	_expect(hud.process_mode == Node.PROCESS_MODE_DISABLED and not hud.visible, "designer entry left the gameplay HUD active for %s" % label)
	_expect(level_interaction.process_mode == Node.PROCESS_MODE_DISABLED, "designer entry left gameplay interaction active for %s" % label)
	if designer_runtime != null:
		var designer_controller := designer_runtime.get_node("StructureDesignerController") as StructureDesignerController
		_expect(designer_runtime.visible and designer_runtime.is_processing(), "designer runtime was inactive for %s" % label)
		_expect(designer_controller.camera.current and designer_controller._input_enabled and designer_controller.is_physics_processing(), "designer input and camera were inactive for %s" % label)
		game.dev_console.open()
		_expect(game.dev_console.is_open() and not designer_controller._input_enabled, "open console did not block designer input for %s" % label)
		_expect(game._request_export_structure(), "export command did not open its dialog for %s" % label)
		game.dev_console.close()
		_expect(game.structure_designer_workflow.is_dialog_open() and not designer_controller._input_enabled, "closing the console bypassed the open export dialog for %s" % label)
		game.structure_designer_dialogs.close_active()
		_expect(designer_controller._input_enabled, "closing the export dialog did not restore designer input for %s" % label)
	if in_level:
		_expect(world.is_suspended() == world_suspended and entities.is_suspended() == entities_suspended, "designer entry changed suspended overworld systems for %s" % label)
		_expect(level_runtime != null and not level_runtime.visible and not level_runtime.is_processing(), "designer entry did not suspend the level runtime for %s" % label)
		_expect(level_runtime.get_entity_runtime().is_suspended(), "designer entry left dungeon entities active for %s" % label)
		_expect((level_runtime.get_node("WorldEnvironment") as WorldEnvironment).environment == null, "designer entry retained the level environment for %s" % label)
	else:
		_expect(world.is_suspended() and entities.is_suspended() and not world.visible and not entities.visible, "designer entry did not suspend overworld systems for %s" % label)
		_expect(environment._world_environment.environment == null and not environment._sun.visible and not environment._sun_fill.visible, "designer entry retained the outdoor environment for %s" % label)
	await game._exit_structure_designer()
	await process_frame
	_expect(game._structure_designer_runtime == null and not is_instance_valid(designer_runtime), "designer runtime survived exit for %s" % label)
	_expect(game._location_state == location_state and game._location_state.is_in_level() == in_level, "designer exit changed GameplayLocationState for %s" % label)
	_expect(game._location_state.get_persisted_position().is_equal_approx(persisted_position), "designer exit changed the persisted position for %s" % label)
	_expect(game.inventory_model == inventory_identity and not game.structure_designer_workflow.has_active_draft(), "designer exit replaced inventory or retained the draft for %s" % label)
	_expect(game.game_session.is_saving_suspended() == saving_was_suspended, "designer exit changed the prior saving state for %s" % label)
	_expect(environment.is_clock_paused() == clock_was_paused, "designer exit changed the prior world clock state for %s" % label)
	_expect(environment.is_debug_panel_input_enabled() == debug_panel_input_was_enabled, "designer exit changed the prior environment debug input state for %s" % label)
	_expect(player.process_mode == player_process_mode and player.visible == player_visible and player.global_position.is_equal_approx(player_position), "designer exit did not restore the player for %s" % label)
	_expect(player.is_physics_processing() == player_physics_processing, "designer exit changed player input processing for %s" % label)
	_expect(player.voxel_space == player_voxel_space, "designer exit changed the player voxel binding for %s" % label)
	_expect(camera_rig.process_mode == camera_process_mode and camera_rig.visible == camera_visible and camera_rig.camera.current == camera_current, "designer exit did not restore the gameplay camera for %s" % label)
	_expect(camera_rig._gameplay_input_enabled == camera_input_enabled, "designer exit changed gameplay camera input for %s" % label)
	_expect(is_equal_approx(camera_rig.current_yaw_deg, camera_yaw) and is_equal_approx(camera_rig.target_yaw_deg, camera_target_yaw) and is_equal_approx(camera_rig.camera.size, camera_size), "designer exit changed the gameplay camera transform for %s" % label)
	_expect(hud.process_mode == hud_process_mode and hud.visible == hud_visible and hud.hotbar._selection_input_enabled == hotbar_input_enabled, "designer exit did not restore the HUD and hotbar input for %s" % label)
	_expect(level_interaction.process_mode == level_interaction_process_mode, "designer exit did not restore gameplay interaction for %s" % label)
	_expect(world.is_suspended() == world_suspended and world.visible == world_visible, "designer exit did not restore the world for %s" % label)
	_expect(entities.is_suspended() == entities_suspended and entities.visible == entities_visible, "designer exit did not restore entities for %s" % label)
	_expect(game._level_entrance.visible == entrance_visible, "designer exit did not restore the entrance for %s" % label)
	_expect(environment._world_environment.environment == outdoor_environment and environment._sun.visible == outdoor_sun_visible and environment._sun_fill.visible == outdoor_fill_visible and environment._ambient_soundscape._running == outdoor_audio_running, "designer exit did not restore the outdoor environment for %s" % label)
	if in_level:
		_expect(level_runtime.visible == level_visible and level_runtime.is_processing() == level_processing, "designer exit did not reactivate the level runtime for %s" % label)
		_expect(not level_runtime.get_entity_runtime().is_suspended(), "designer exit did not reactivate dungeon entities for %s" % label)
		_expect((level_runtime.get_node("WorldEnvironment") as WorldEnvironment).environment == level_environment, "designer exit did not restore the level environment for %s" % label)
	_expect(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == orphan_baseline, "designer cycle changed orphan count for %s" % label)
	if saving_was_suspended:
		game.game_session.resume_saving()

func _expect_runtime_torch_discovery_state(
	torch_renderer: TorchRenderer,
	cell: Vector3i,
	discovered: bool,
	iteration: int,
	room_id: int,
) -> void:
	var torch_root := torch_renderer.torch_instances.get(cell) as Node3D
	_expect(torch_root != null, "runtime omitted torch %s at iteration %d room %d" % [cell, iteration, room_id])
	if torch_root == null:
		return
	var stem := torch_root.get_node("Stem") as MeshInstance3D
	var flame := torch_root.get_node("Flame") as MeshInstance3D
	var light := torch_renderer.torch_light_nodes.get(cell) as OmniLight3D
	_expect(stem.visible == discovered, "runtime torch stem visibility changed at iteration %d room %d" % [iteration, room_id])
	_expect(flame.visible == discovered, "runtime torch flame visibility changed at iteration %d room %d" % [iteration, room_id])
	_expect(is_equal_approx(stem.transparency, 0.0 if discovered else 1.0), "runtime torch stem transparency changed at iteration %d room %d" % [iteration, room_id])
	_expect(is_equal_approx(flame.transparency, 0.0 if discovered else 1.0), "runtime torch flame transparency changed at iteration %d room %d" % [iteration, room_id])
	_expect(light != null and light.visible == discovered, "runtime torch light visibility changed at iteration %d room %d" % [iteration, room_id])
	if light != null:
		_expect((light.light_energy > 0.0) == discovered, "runtime torch light energy changed at iteration %d room %d" % [iteration, room_id])
		_expect(not light.shadow_enabled, "runtime hidden or zero-shadow torch cast a shadow at iteration %d room %d" % [iteration, room_id])

func _make_flat_world(block_catalog: BlockCatalog) -> VoxelWorld:
	var voxel_world := VoxelWorld.new(20, 36, 5, 12.0, block_catalog)
	for x in range(-16, 17):
		for z in range(-16, 17):
			voxel_world.height_map_dict[Vector2i(x, z)] = 4
			voxel_world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return voxel_world

func _position_ready(_position: Vector3) -> bool:
	return true

func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	print("[level_runtime] FAIL: %s" % message)

func _finish(orphan_count: int) -> void:
	if _failures == 0:
		print("LEVEL_RUNTIME PASS iterations=%d assertions=%d orphan=%d" % [LIFECYCLE_ITERATIONS, _assertions, orphan_count])
		quit(0)
	else:
		print("LEVEL_RUNTIME FAILED failures=%d assertions=%d orphan=%d" % [_failures, _assertions, orphan_count])
		quit(1)
