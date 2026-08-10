extends SceneTree

const FLAT_HEIGHT: int = 6
const FEET_Y: float = float(FLAT_HEIGHT + 1)
const TEST_RADIUS: int = 48

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[entity_fade_integration] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-TEST_RADIUS, TEST_RADIUS + 1):
		for z in range(-TEST_RADIUS, TEST_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLAT_HEIGHT
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _position_ready(_position: Vector3) -> bool:
	return true

func _append_geometries(node: Node, result: Array[GeometryInstance3D]) -> void:
	if node is GeometryInstance3D:
		result.append(node as GeometryInstance3D)
	for child in node.get_children():
		_append_geometries(child, result)

func _get_geometries(node: Node) -> Array[GeometryInstance3D]:
	var result: Array[GeometryInstance3D] = []
	_append_geometries(node, result)
	return result

func _get_transparencies(geometries: Array[GeometryInstance3D]) -> Array[float]:
	var result: Array[float] = []
	for geometry in geometries:
		result.append(geometry.transparency)
	return result

func _get_shadow_settings(geometries: Array[GeometryInstance3D]) -> Array[int]:
	var result: Array[int] = []
	for geometry in geometries:
		result.append(geometry.cast_shadow)
	return result

func _expect_shadows_disabled(geometries: Array[GeometryInstance3D], context: String) -> void:
	for index in range(geometries.size()):
		_expect(geometries[index].cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s geometry %d still cast shadows" % [context, index])

func _get_material_colors(geometries: Array[GeometryInstance3D]) -> Array[Color]:
	var result: Array[Color] = []
	for geometry in geometries:
		var mesh_instance := geometry as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.mesh.surface_get_material(surface_index) as StandardMaterial3D
			if material != null:
				result.append(material.albedo_color)
	return result

func _expect_opacity(
	geometries: Array[GeometryInstance3D],
	baselines: Array[float],
	opacity: float,
	context: String,
) -> void:
	for index in range(geometries.size()):
		var expected := lerpf(1.0, baselines[index], opacity)
		_expect(is_equal_approx(geometries[index].transparency, expected), "%s geometry %d had transparency %.3f instead of %.3f" % [context, index, geometries[index].transparency, expected])

func _test_species_visual_fades(catalog: EntityCatalog, world: VoxelWorld) -> void:
	var definition_ids: Array[StringName] = [&"zombie", &"sheep"]
	for index in range(definition_ids.size()):
		var definition := catalog.get_definition(definition_ids[index])
		var actor := definition.actor_scene.instantiate() as EntityActor
		var geometries := _get_geometries(actor)
		var baselines := _get_transparencies(geometries)
		var baseline_shadows := _get_shadow_settings(geometries)
		var material_colors := _get_material_colors(geometries)
		_expect(not geometries.is_empty(), "%s visual contained no fade geometry" % definition.id)
		get_root().add_child(actor)
		actor.global_position = Vector3(float(index) + 0.5, FEET_Y, 0.5)
		actor.setup(index + 1, definition, world, 100 + index)
		_expect(is_zero_approx(actor.get_visual_opacity()), "%s did not begin fully faded out" % definition.id)
		_expect_opacity(geometries, baselines, 0.0, "%s spawn start" % definition.id)
		_expect_shadows_disabled(geometries, "%s spawn start" % definition.id)
		var fade_in_seconds := actor.visual_fader.fade_in_seconds
		_expect(not actor.advance_visual_fade(fade_in_seconds * 0.5), "%s completed retirement during fade-in" % definition.id)
		_expect(is_equal_approx(actor.get_visual_opacity(), 0.5), "%s midpoint fade-in was not smoothstep-balanced" % definition.id)
		_expect_opacity(geometries, baselines, 0.5, "%s spawn midpoint" % definition.id)
		_expect_shadows_disabled(geometries, "%s spawn midpoint" % definition.id)
		actor.advance_visual_fade(fade_in_seconds * 0.5)
		_expect(is_equal_approx(actor.get_visual_opacity(), 1.0), "%s did not finish fully visible" % definition.id)
		_expect_opacity(geometries, baselines, 1.0, "%s spawn completion" % definition.id)
		_expect(_get_shadow_settings(geometries) == baseline_shadows, "%s did not restore its shadow settings" % definition.id)
		_expect(_get_material_colors(geometries) == material_colors, "%s fade mutated its materials" % definition.id)
		_expect(actor.is_processing(), "%s stopped animation before retirement" % definition.id)
		actor.begin_despawn_fade()
		_expect(not actor.is_processing(), "%s kept animation processing during retirement" % definition.id)
		_expect_shadows_disabled(geometries, "%s retirement start" % definition.id)
		_expect(is_equal_approx(actor.get_visual_opacity(), 1.0), "%s despawn began with an opacity jump" % definition.id)
		var fade_out_seconds := actor.visual_fader.fade_out_seconds
		_expect(not actor.advance_visual_fade(fade_out_seconds * 0.5), "%s despawn completed before its duration" % definition.id)
		_expect(is_equal_approx(actor.get_visual_opacity(), 0.5), "%s midpoint fade-out was not smoothstep-balanced" % definition.id)
		_expect_opacity(geometries, baselines, 0.5, "%s despawn midpoint" % definition.id)
		_expect_shadows_disabled(geometries, "%s despawn midpoint" % definition.id)
		_expect(actor.advance_visual_fade(fade_out_seconds * 0.5), "%s despawn did not complete" % definition.id)
		_expect(is_zero_approx(actor.get_visual_opacity()), "%s did not finish fully transparent" % definition.id)
		_expect_opacity(geometries, baselines, 0.0, "%s despawn completion" % definition.id)
		actor.free()

func _test_instance_isolation(catalog: EntityCatalog, world: VoxelWorld) -> void:
	var definition := catalog.get_definition(&"zombie")
	var first := definition.actor_scene.instantiate() as EntityActor
	var second := definition.actor_scene.instantiate() as EntityActor
	var first_geometries := _get_geometries(first)
	var second_geometries := _get_geometries(second)
	get_root().add_child(first)
	get_root().add_child(second)
	first.setup(10, definition, world, 10)
	second.setup(11, definition, world, 11)
	first.advance_visual_fade(first.visual_fader.fade_in_seconds)
	_expect(is_equal_approx(first_geometries[0].transparency, 0.0), "first zombie did not become opaque")
	_expect(is_equal_approx(second_geometries[0].transparency, 1.0), "fading one zombie changed another instance")
	first.free()
	second.free()

func _test_coordinator_retirement(catalog: EntityCatalog, world: VoxelWorld) -> void:
	var coordinator := EntityCoordinator.new()
	get_root().add_child(coordinator)
	coordinator.setup(catalog, world, 7021, _position_ready)
	var player_position := Vector3(0.5, FEET_Y, 0.5)
	coordinator.tick(EntityCoordinator.SPAWN_INTERVAL_SECONDS, player_position, 20.0)
	var actors := coordinator.get_active_actors()
	_expect(actors.size() == 1, "coordinator did not spawn the fade test zombie")
	if actors.is_empty():
		coordinator.shutdown()
		coordinator.queue_free()
		return
	var actor := actors[0]
	var runtime_id := actor.runtime_id
	var fade_in_step := actor.visual_fader.fade_in_seconds * 0.25
	coordinator.tick(fade_in_step, player_position, 20.0)
	var interrupted_opacity := actor.get_visual_opacity()
	_expect(interrupted_opacity > 0.0 and interrupted_opacity < 1.0, "interrupted fade setup was not partially visible")
	var former_bounds := actor.get_world_bounds()
	actor.global_position = player_position + Vector3(EntityCoordinator.DESPAWN_DISTANCE + 1.0, 0.0, 0.0)
	coordinator.tick(0.0, player_position, 20.0)
	_expect(coordinator.get_actor(runtime_id) == null and coordinator.get_active_count() == 0, "retiring actor remained active")
	_expect(coordinator._spatial_index.get_entry_count() == 0, "retiring actor remained spatially indexed")
	_expect(not coordinator.has_entity_overlap(former_bounds), "retiring actor still blocked placement")
	_expect(coordinator._retiring.size() == 1 and is_instance_valid(actor), "retiring visual was not retained")
	_expect(is_equal_approx(actor.get_visual_opacity(), interrupted_opacity), "interrupted fade-out changed opacity at transition")
	var fade_out_seconds := actor.visual_fader.fade_out_seconds
	coordinator.tick(fade_out_seconds * 0.5, player_position, 20.0)
	_expect(actor.get_visual_opacity() < interrupted_opacity and actor.get_visual_opacity() > 0.0, "retiring visual did not fade gradually")
	coordinator.tick(fade_out_seconds * 0.5, player_position, 20.0)
	_expect(coordinator._retiring.is_empty(), "completed retiring visual remained owned")
	await process_frame
	_expect(not is_instance_valid(actor), "completed retiring visual was not freed")
	coordinator.shutdown()
	coordinator.queue_free()
	await process_frame
	await process_frame

func _test_retiring_bound_and_population_independence(catalog: EntityCatalog, world: VoxelWorld) -> void:
	var coordinator := EntityCoordinator.new()
	get_root().add_child(coordinator)
	coordinator.setup(catalog, world, 8842, _position_ready)
	var player_position := Vector3(0.5, FEET_Y, 0.5)
	for _spawn in range(6):
		coordinator.tick(EntityCoordinator.SPAWN_INTERVAL_SECONDS, player_position, 20.0)
	for _spawn in range(6):
		coordinator.tick(EntityCoordinator.SPAWN_INTERVAL_SECONDS, player_position, 12.0)
	_expect(coordinator.get_active_count() == EntityCoordinator.MAX_TOTAL_ACTIVE, "retiring-cap setup did not reach twelve active entities")
	var actors := coordinator.get_active_actors()
	actors.sort_custom(func(left: EntityActor, right: EntityActor) -> bool: return left.runtime_id < right.runtime_id)
	var oldest_actor := actors[0]
	var oldest_runtime_id := oldest_actor.runtime_id
	for index in range(actors.size()):
		actors[index].global_position = player_position + Vector3(EntityCoordinator.DESPAWN_DISTANCE + 1.0 + float(index), 0.0, 0.0)
	coordinator.tick(0.0, player_position, 20.0)
	_expect(coordinator.get_active_count() == 0, "mass retirement retained active entities")
	_expect(coordinator._retiring.size() == EntityCoordinator.MAX_RETIRING_VISUALS, "mass retirement did not fill the visual bound")
	coordinator._spawn_elapsed = EntityCoordinator.SPAWN_INTERVAL_SECONDS - 0.1
	coordinator.tick(0.1, player_position, 20.0)
	_expect(coordinator.get_active_count() == 1, "retiring visuals suppressed an available population slot")
	var replacement := coordinator.get_active_actors()[0]
	replacement.global_position = player_position + Vector3(EntityCoordinator.DESPAWN_DISTANCE + 1.0, 0.0, 0.0)
	coordinator.tick(0.0, player_position, 20.0)
	_expect(coordinator._retiring.size() == EntityCoordinator.MAX_RETIRING_VISUALS, "thirteenth retirement exceeded the visual bound")
	_expect(not coordinator._retiring.has(oldest_runtime_id), "retiring bound did not evict the oldest visual")
	_expect(coordinator._retiring.has(replacement.runtime_id), "retiring bound dropped the newest visual")
	await process_frame
	_expect(not is_instance_valid(oldest_actor), "evicted retiring visual was not freed")
	coordinator.shutdown()
	coordinator.queue_free()
	await process_frame
	await process_frame

func _run() -> void:
	var catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	var world := _make_world()
	_test_species_visual_fades(catalog, world)
	_test_instance_isolation(catalog, world)
	await _test_coordinator_retirement(catalog, world)
	await _test_retiring_bound_and_population_independence(catalog, world)
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "fade tests ended with %d orphan nodes" % orphan_count)
	if _failures == 0:
		print("ENTITY_FADE_INTEGRATION PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("ENTITY_FADE_INTEGRATION FAIL failures=%d" % _failures)
		quit(1)
