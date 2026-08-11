extends SceneTree

const LEVEL_RUNTIME_SCENE: String = "res://levels/runtime/level_runtime.tscn"
const CATALOG_PATH: String = "res://levels/content/level_catalog.tres"
const BLOCK_CATALOG_PATH: String = "res://blocks/block_catalog.tres"
const LIFECYCLE_ITERATIONS: int = 12

var _failures: int = 0
var _assertions: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var catalog := load(CATALOG_PATH) as LevelCatalog
	var block_catalog := load(BLOCK_CATALOG_PATH) as BlockCatalog
	var runtime_scene := load(LEVEL_RUNTIME_SCENE) as PackedScene
	_expect(catalog != null and catalog.validate(), "level catalog did not load or validate")
	_expect(block_catalog != null and block_catalog.validate(), "block catalog did not load or validate")
	_expect(runtime_scene != null, "level runtime scene did not load")
	if catalog == null or block_catalog == null or runtime_scene == null:
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
