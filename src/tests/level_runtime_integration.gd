extends SceneTree

const LEVEL_RUNTIME_SCENE: String = "res://levels/runtime/level_runtime.tscn"
const WORLD_SCENE: String = "res://world/world.tscn"
const CATALOG_PATH: String = "res://levels/content/level_catalog.tres"
const BLOCK_CATALOG_PATH: String = "res://blocks/block_catalog.tres"
const LIFECYCLE_ITERATIONS: int = 12
const GAME_TRANSITION_CYCLES: int = 3

class TransitionGame:
	extends Game

	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_input(false)

	func _fade_to(alpha: float) -> void:
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
		_finish(0)
		return
	var generation := LevelGenerator.new().generate(catalog, &"stone_dungeon", 1337, &"runtime_test", Vector3i(7, 0, -9))
	_expect(generation.succeeded, "runtime fixture generation failed: %s" % generation.failure_reason)
	if not generation.succeeded:
		_finish(0)
		return
	var texture_set := BlockTextureSet.new(block_catalog)
	var settings := GameSettings.new()
	settings.torch_shadow_count = 0
	var root_child_baseline := root.get_child_count()
	var orphan_baseline := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for iteration in range(LIFECYCLE_ITERATIONS):
		await _run_runtime_lifecycle(runtime_scene, generation.layout, block_catalog, texture_set, settings, iteration)
	_expect(root.get_child_count() == root_child_baseline, "runtime lifecycle left children attached to SceneTree root")
	await _test_world_suspension(world_scene)
	await _test_game_transitions(catalog, block_catalog, runtime_scene)
	await process_frame
	await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == orphan_baseline, "level/world lifecycle changed orphan count from %d to %d" % [orphan_baseline, orphan_count])
	_finish(orphan_count)

func _run_runtime_lifecycle(
	runtime_scene: PackedScene,
	layout: LevelLayout,
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
	runtime.setup(layout, block_catalog, texture_set, settings)
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
	var geometry := runtime.get_node("Geometry") as MeshInstance3D
	var environment_node := runtime.get_node("WorldEnvironment") as WorldEnvironment
	var torch_renderer := runtime.get_node("Torches") as TorchRenderer
	_expect(geometry != null and geometry.mesh != null and geometry.mesh.get_surface_count() == 1, "runtime geometry was not built at iteration %d" % iteration)
	_expect(geometry.material_override is ShaderMaterial, "runtime terrain material is not shader-backed at iteration %d" % iteration)
	if geometry.material_override is ShaderMaterial:
		var terrain_material := geometry.material_override as ShaderMaterial
		_expect(terrain_material.shader != null and terrain_material.shader.resource_path == "res://levels/presentation/level_terrain.gdshader", "runtime terrain shader changed at iteration %d" % iteration)
		_expect(terrain_material.get_shader_parameter("terrain_textures") == texture_set.texture_array, "runtime terrain texture array changed at iteration %d" % iteration)
	_expect(torch_renderer.torch_instances.size() == layout.torches.size(), "runtime spawned %d/%d authored torches at iteration %d" % [torch_renderer.torch_instances.size(), layout.torches.size(), iteration])
	for torch in layout.torches:
		_expect(torch_renderer.has_torch(torch.cell), "runtime omitted authored torch %s at iteration %d" % [torch.cell, iteration])
	for cycle in range(3):
		runtime.activate()
		_expect(runtime.visible and runtime.is_processing(), "activate failed at iteration %d cycle %d" % [iteration, cycle])
		_expect(environment_node.environment != null, "activate did not install the level environment at iteration %d cycle %d" % [iteration, cycle])
		runtime.apply_settings(settings)
		for light in torch_renderer.torch_light_nodes.values():
			_expect(not (light as OmniLight3D).shadow_enabled, "zero-shadow setting left a torch shadow enabled at iteration %d cycle %d" % [iteration, cycle])
		runtime.deactivate()
		_expect(not runtime.visible and not runtime.is_processing(), "deactivate failed at iteration %d cycle %d" % [iteration, cycle])
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
	var manager := ChunkManager.new()
	manager._scheduler = world.chunk_scheduler
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
	game.player_stats_definition = load("res://player/player_stats.tres") as ActorStatsDefinition
	game.level_catalog = catalog
	game.level_runtime_scene = runtime_scene
	var world := (load(WORLD_SCENE) as PackedScene).instantiate() as WorldController
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as PlayerMotor
	var camera_rig := (load("res://player/camera/camera_rig.tscn") as PackedScene).instantiate() as CameraRig
	var environment := (load("res://environment/environment.tscn") as PackedScene).instantiate() as GameEnvironment
	var hud := (load("res://ui/hud/hud.tscn") as PackedScene).instantiate() as HUD
	var session := GameSession.new()
	var coordinator := LevelInteractionCoordinator.new()
	var entities := EntityCoordinator.new()
	var combat := MeleeCombatCoordinator.new()
	var mining_break_particles := (load("res://mining/presentation/mining_break_particles.tscn") as PackedScene).instantiate()
	var mining_hit_particles := (load("res://mining/presentation/mining_hit_particles.tscn") as PackedScene).instantiate()
	world.name = "World"
	player.name = "Player"
	camera_rig.name = "CameraRig"
	environment.name = "Environment"
	hud.name = "HUD"
	session.name = "GameSession"
	coordinator.name = "LevelInteractionCoordinator"
	entities.name = "Entities"
	combat.name = "MeleeCombat"
	mining_break_particles.name = "MiningBreakParticles"
	mining_hit_particles.name = "MiningHitParticles"
	game.add_child(world)
	game.add_child(player)
	game.add_child(camera_rig)
	game.add_child(environment)
	game.add_child(entities)
	game.add_child(combat)
	game.add_child(hud)
	game.add_child(session)
	game.add_child(coordinator)
	game.add_child(mining_break_particles)
	game.add_child(mining_hit_particles)
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
	_expect(game.game_environment == environment and game.level_interaction == coordinator, "Game transition dependencies were not wired")
	var manager := ChunkManager.new()
	manager._scheduler = world.chunk_scheduler
	world.chunk_manager = manager
	var settings := GameSettings.new()
	settings.torch_shadow_count = 0
	settings.birds_enabled = false
	game.settings = settings
	world.configure_settings(settings)
	environment.setup(6.0, settings.get_shadow_distance())
	environment.apply_settings(settings)
	game.inventory_model = InventoryModel.new(game.item_catalog)
	game.inventory_model.setup_starter()
	game.player_stats = ActorStats.new(game.player_stats_definition)
	camera_rig.setup(player, game.input_buffer)
	entities.setup(game.entity_catalog, voxel_world, 1337, _position_ready)
	combat.setup(voxel_world, player, entities)
	player.setup(camera_rig, game.inventory_model, game.input_buffer, game.player_stats, combat, entities)
	var world_spawn := voxel_world.get_spawn_position()
	var doorway_anchor := world_spawn
	player.global_position = doorway_anchor
	player.bind_space(voxel_world, world, world_spawn, voxel_world)
	game._location_state = GameplayLocationState.new(doorway_anchor)
	coordinator.setup(player, hud)
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
		await game._enter_level()
		var runtime := game._level_runtime
		_expect(runtime != null and is_instance_valid(runtime), "Game did not retain an active runtime in cycle %d" % cycle)
		_expect(game._location_state.is_in_level(), "Game location did not enter level in cycle %d" % cycle)
		_expect(game._get_persisted_position().is_equal_approx(doorway_anchor), "indoor persisted position differs from doorway anchor in cycle %d" % cycle)
		_expect(world.is_suspended() and manager._suspended and world.chunk_scheduler._suspended, "Game did not suspend world streaming in cycle %d" % cycle)
		_expect(entities.is_suspended() and not entities.visible, "Game did not suspend overworld entities in cycle %d" % cycle)
		_expect(not world.visible and not entrance.visible, "overworld presentation remained visible in cycle %d" % cycle)
		_expect(environment._world_environment.environment == null and not environment._sun.visible and not environment._sun_fill.visible, "outdoor environment remained active in cycle %d" % cycle)
		_expect(not environment._ambient_soundscape._running, "outdoor ambient audio remained active in cycle %d" % cycle)
		_expect(runtime.visible and runtime.is_processing(), "level runtime is inactive in cycle %d" % cycle)
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
		player.global_position += Vector3(2.0, 0.0, 1.0)
		_expect(game._get_persisted_position().is_equal_approx(doorway_anchor), "level-local movement changed persisted anchor in cycle %d" % cycle)
		await game._exit_level()
		_expect(not game._location_state.is_in_level(), "Game location remained in level after cycle %d" % cycle)
		_expect(player.global_position.is_equal_approx(doorway_anchor), "Game restored %s instead of exact anchor %s in cycle %d" % [player.global_position, doorway_anchor, cycle])
		_expect(player.voxel_space == voxel_world and player.interactor.voxel_space == voxel_world, "player world binding was not restored in cycle %d" % cycle)
		_expect(player.interactor.is_editing_enabled() and player.interactor.editable_voxel_world == voxel_world, "world edit authority was not restored in cycle %d" % cycle)
		_expect(player.targeting_view.voxel_space == voxel_world and player.targeting_view.selection_box.get_parent() == world, "world targeting presentation was not restored in cycle %d" % cycle)
		_expect(not world.is_suspended() and not manager._suspended and not world.chunk_scheduler._suspended, "Game did not resume world streaming in cycle %d" % cycle)
		_expect(not entities.is_suspended() and entities.visible, "Game did not resume overworld entities in cycle %d" % cycle)
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
	player.unbind_space()
	game.queue_free()
	await process_frame
	await process_frame
	await process_frame
	_expect(not is_instance_valid(game), "Game transition fixture survived teardown")
	_expect(root.get_child_count() == root_child_baseline, "Game transition fixture left root children behind")

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
