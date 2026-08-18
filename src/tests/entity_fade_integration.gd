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
	var definition_ids: Array[StringName] = [&"zombie", &"sheep", &"bird", &"skeleton"]
	for index in range(definition_ids.size()):
		var definition := catalog.get_definition(definition_ids[index])
		var actor := definition.actor_scene.instantiate() as EntityActor
		var geometries := _get_geometries(actor.get_node(^"ModelRoot"))
		var baselines := _get_transparencies(geometries)
		var baseline_shadows := _get_shadow_settings(geometries)
		var material_colors := _get_material_colors(geometries)
		_expect(not geometries.is_empty(), "%s visual contained no fade geometry" % definition.id)
		get_root().add_child(actor)
		actor.global_position = Vector3(float(index) + 0.5, FEET_Y, 0.5)
		actor.setup(index + 1, definition, world, 100 + index, EntityNavigationLimits.new(24, 256, 1))
		var poof := actor.death_poof
		_expect(poof.amount == 12, "%s death poof amount is not twelve" % definition.id)
		_expect(is_equal_approx(poof.lifetime, 0.35), "%s death poof lifetime is not 0.35 seconds" % definition.id)
		_expect(poof.one_shot and is_equal_approx(poof.explosiveness, 1.0), "%s death poof is not a one-shot burst" % definition.id)
		_expect(poof.color.r >= 0.75 and poof.color.g >= 0.75 and poof.color.b >= 0.75, "%s death poof is not pale" % definition.id)
		_expect(not poof.emitting and not poof.has_played(), "%s death poof began before lethal retirement" % definition.id)
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
		_expect(not poof.emitting and not poof.has_played(), "%s ordinary despawn emitted a death poof" % definition.id)
		_expect_shadows_disabled(geometries, "%s retirement start" % definition.id)
		_expect(is_equal_approx(actor.get_visual_opacity(), 1.0), "%s despawn began with an opacity jump" % definition.id)
		var fade_out_seconds := actor.visual_fader.fade_out_seconds
		_expect(not actor.advance_visual_fade(fade_out_seconds * 0.5), "%s despawn completed before its duration" % definition.id)
		_expect(is_equal_approx(actor.get_visual_opacity(), 0.5), "%s midpoint fade-out was not smoothstep-balanced" % definition.id)
		_expect_opacity(geometries, baselines, 0.5, "%s despawn midpoint" % definition.id)
		_expect_shadows_disabled(geometries, "%s despawn midpoint" % definition.id)
		_expect(actor.advance_visual_fade(fade_out_seconds * 0.5), "%s despawn did not complete" % definition.id)
		_expect(not poof.emitting and not poof.has_played(), "%s completed ordinary despawn emitted a death poof" % definition.id)
		_expect(is_zero_approx(actor.get_visual_opacity()), "%s did not finish fully transparent" % definition.id)
		_expect_opacity(geometries, baselines, 0.0, "%s despawn completion" % definition.id)
		actor.free()

func _test_instance_isolation(catalog: EntityCatalog, world: VoxelWorld) -> void:
	var definition := catalog.get_definition(&"zombie")
	var first := definition.actor_scene.instantiate() as EntityActor
	var second := definition.actor_scene.instantiate() as EntityActor
	var first_geometries := _get_geometries(first.get_node(^"ModelRoot"))
	var second_geometries := _get_geometries(second.get_node(^"ModelRoot"))
	get_root().add_child(first)
	get_root().add_child(second)
	first.setup(10, definition, world, 10, EntityNavigationLimits.new(24, 256, 1))
	second.setup(11, definition, world, 11, EntityNavigationLimits.new(24, 256, 1))
	first.advance_visual_fade(first.visual_fader.fade_in_seconds)
	_expect(is_equal_approx(first_geometries[0].transparency, 0.0), "first zombie did not become opaque")
	_expect(is_equal_approx(second_geometries[0].transparency, 1.0), "fading one zombie changed another instance")
	first.free()
	second.free()

func _test_skeleton_attack_presentation(catalog: EntityCatalog, world: VoxelWorld) -> void:
	var definition := catalog.get_definition(&"skeleton")
	var actor := definition.actor_scene.instantiate() as SkeletonActor
	get_root().add_child(actor)
	actor.global_position = Vector3(2.5, FEET_Y, 2.5)
	actor.setup(19, definition, world, 199, EntityNavigationLimits.new(32, 512, 2))
	var driver := actor.animation_driver as SkeletonAnimationDriver
	var profile := (definition.behavior as SkeletonBehaviorDefinition).melee_profile
	actor.play_attack(profile.duration)
	driver.advance(profile.duration * 0.5)
	_expect(driver.get_current_state() == SkeletonAnimationDriver.ATTACK, "skeleton attack did not select its attack presentation")
	_expect(driver.animator.attack_pose_weight > 0.99, "skeleton attack did not reach its midpoint pose")
	_expect(absf(driver.animator.left_arm_action.rotation.z) > deg_to_rad(20.0), "skeleton attack did not add its two-arm sweep")
	_expect(driver.animator.rig_root.position.z > 0.17, "skeleton attack did not lunge forward")
	actor.play_hit(Vector3.RIGHT)
	driver.advance(0.0)
	_expect(driver.get_current_state() == SkeletonAnimationDriver.HIT, "skeleton hit did not replace its attack presentation")
	_expect(not driver._attacking and not driver.animator._attacking, "skeleton hit retained its active attack")
	actor.play_attack(profile.duration)
	driver.advance(profile.duration * 0.5)
	_expect(driver.get_current_state() == SkeletonAnimationDriver.ATTACK, "skeleton did not restart its attack after a hit")
	actor.begin_death_retirement()
	_expect(driver.get_current_state() == SkeletonAnimationDriver.DEATH, "skeleton death did not replace its attack presentation")
	_expect(not driver._attacking and not driver.animator._attacking, "skeleton death retained its active attack")
	actor.play_attack(profile.duration)
	driver.advance(0.0)
	_expect(driver.get_current_state() == SkeletonAnimationDriver.DEATH, "dead skeleton accepted a new attack presentation")
	_expect(not driver._attacking and not driver.animator._attacking, "dead skeleton restarted its attack")
	actor.free()

func _test_species_death_retirement(catalog: EntityCatalog, world: VoxelWorld) -> void:
	var definition_ids: Array[StringName] = [&"zombie", &"sheep", &"skeleton"]
	for index in range(definition_ids.size()):
		var definition := catalog.get_definition(definition_ids[index])
		var actor := definition.actor_scene.instantiate() as EntityActor
		get_root().add_child(actor)
		actor.global_position = Vector3(float(index) + 0.5, FEET_Y, 2.5)
		actor.setup(index + 20, definition, world, 200 + index, EntityNavigationLimits.new(24, 256, 1))
		actor.advance_visual_fade(actor.visual_fader.fade_in_seconds)
		actor.velocity = Vector3(1.0, 2.0, 3.0)
		actor.play_hit(Vector3.RIGHT)
		var death_seconds := SheepAnimationDriver.DEATH_SECONDS
		if actor is ZombieActor:
			var zombie := actor as ZombieActor
			zombie._timed_melee_contact.arm((definition.behavior as GroundMeleeEnemyBehaviorDefinition).melee_profile)
			death_seconds = ZombieAnimationDriver.DEATH_SECONDS
		elif actor is SkeletonActor:
			death_seconds = SkeletonAnimationDriver.DEATH_SECONDS
		actor.begin_death_retirement()
		_expect(not actor.is_processing(), "%s kept normal animation processing after lethal retirement" % definition.id)
		_expect(actor.velocity.is_zero_approx(), "%s retained movement velocity after lethal retirement" % definition.id)
		var death_state: StringName
		if actor is ZombieActor:
			death_state = (actor.animation_driver as ZombieAnimationDriver).get_current_state()
		elif actor is SkeletonActor:
			death_state = (actor.animation_driver as SkeletonAnimationDriver).get_current_state()
		else:
			death_state = (actor.animation_driver as SheepAnimationDriver).get_current_state()
		_expect(death_state == &"Death", "%s did not enter its death state" % definition.id)
		_expect(not actor.animation_driver.is_death_complete(), "%s death pose completed at retirement start" % definition.id)
		_expect(is_equal_approx(actor.get_visual_opacity(), 1.0), "%s death pose began with an opacity change" % definition.id)
		_expect(not actor.death_poof.emitting and not actor.death_poof.has_played(), "%s death poof began before the pose completed" % definition.id)
		if actor is ZombieActor:
			_expect(not (actor as ZombieActor)._timed_melee_contact.is_pending(), "zombie retained a pending attack after lethal retirement")
		_expect(not actor.advance_retirement(death_seconds * 0.5), "%s retirement completed during its death pose" % definition.id)
		_expect(not actor.animation_driver.is_death_complete(), "%s death pose completed before its configured duration" % definition.id)
		_expect(is_equal_approx(actor.get_visual_opacity(), 1.0), "%s faded before its death pose completed" % definition.id)
		_expect(not actor.death_poof.emitting and not actor.death_poof.has_played(), "%s death poof began during the pose" % definition.id)
		if actor is ZombieActor:
			var zombie_animation := actor.animation_driver as ZombieAnimationDriver
			_expect(absf(zombie_animation.animator.rotation.x - zombie_animation._visual_origin_rotation.x) > deg_to_rad(1.0), "zombie did not buckle into its fall pose")
		elif actor is SkeletonActor:
			var skeleton_animation := actor.animation_driver as SkeletonAnimationDriver
			_expect(absf(skeleton_animation.animator.rotation.x - skeleton_animation._visual_origin_rotation.x) > deg_to_rad(1.0), "skeleton did not fold into its fall pose")
		else:
			var sheep_animation := actor.animation_driver as SheepAnimationDriver
			_expect(absf(sheep_animation._rig_root.rotation.z - sheep_animation._rig_origin_rotation.z) > deg_to_rad(1.0), "sheep did not rotate into its side-collapse pose")
		actor.play_hit(Vector3.LEFT)
		_expect(not actor.advance_retirement(death_seconds * 0.5), "%s retirement completed before fade-out" % definition.id)
		_expect(actor.animation_driver.is_death_complete(), "%s death pose did not complete at its configured duration" % definition.id)
		_expect(actor.death_poof.emitting and actor.death_poof.has_played(), "%s death pose completion did not emit its poof" % definition.id)
		_expect(is_zero_approx(actor.death_poof._elapsed), "%s death poof did not begin with the fade" % definition.id)
		if actor is ZombieActor:
			death_state = (actor.animation_driver as ZombieAnimationDriver).get_current_state()
		elif actor is SkeletonActor:
			death_state = (actor.animation_driver as SkeletonAnimationDriver).get_current_state()
		else:
			death_state = (actor.animation_driver as SheepAnimationDriver).get_current_state()
		_expect(death_state == &"Death", "%s hit reaction replaced its death pose" % definition.id)
		var fade_out_seconds := actor.visual_fader.fade_out_seconds
		_expect(not actor.advance_retirement(fade_out_seconds * 0.5), "%s fade completed before its configured duration" % definition.id)
		_expect(is_equal_approx(actor.get_visual_opacity(), 0.5), "%s death fade midpoint was not smoothstep-balanced" % definition.id)
		var poof_elapsed := actor.death_poof._elapsed
		_expect(is_equal_approx(poof_elapsed, fade_out_seconds * 0.5), "%s death poof did not advance with the fade" % definition.id)
		_expect(not actor.advance_retirement(0.0) and is_equal_approx(actor.death_poof._elapsed, poof_elapsed), "%s death poof restarted during retirement" % definition.id)
		_expect(actor.advance_retirement(fade_out_seconds * 0.5), "%s death retirement did not complete" % definition.id)
		actor.free()

func _test_retirement_waits_for_poof(catalog: EntityCatalog, world: VoxelWorld) -> void:
	var definition := catalog.get_definition(&"sheep")
	var actor := definition.actor_scene.instantiate() as EntityActor
	get_root().add_child(actor)
	actor.global_position = Vector3(1.5, FEET_Y, 3.5)
	actor.setup(29, definition, world, 299, EntityNavigationLimits.new(24, 256, 1))
	actor.advance_visual_fade(actor.visual_fader.fade_in_seconds)
	actor.visual_fader.fade_out_seconds = 0.15
	actor.begin_death_retirement()
	_expect(not actor.advance_retirement(SheepAnimationDriver.DEATH_SECONDS), "sheep retirement completed when the poof began")
	_expect(not actor.advance_retirement(actor.visual_fader.fade_out_seconds), "sheep retirement completed before its poof")
	_expect(is_zero_approx(actor.get_visual_opacity()), "sheep model remained visible after its shortened fade")
	_expect(actor.death_poof._elapsed < actor.death_poof.lifetime, "sheep poof completed before its lifetime")
	var remaining_poof_time := actor.death_poof.lifetime - actor.visual_fader.fade_out_seconds
	_expect(actor.advance_retirement(remaining_poof_time), "sheep retirement did not complete after both presentations")
	actor.free()

func _test_oversized_death_retirement_delta(catalog: EntityCatalog, world: VoxelWorld) -> void:
	var definition := catalog.get_definition(&"zombie")
	var actor := definition.actor_scene.instantiate() as EntityActor
	get_root().add_child(actor)
	actor.global_position = Vector3(0.5, FEET_Y, 3.5)
	actor.setup(30, definition, world, 300, EntityNavigationLimits.new(24, 256, 1))
	actor.advance_visual_fade(actor.visual_fader.fade_in_seconds)
	actor.begin_death_retirement()
	var retirement_seconds := ZombieAnimationDriver.DEATH_SECONDS + maxf(actor.visual_fader.fade_out_seconds, actor.death_poof.lifetime)
	_expect(actor.advance_retirement(retirement_seconds), "oversized death-retirement delta did not complete the lifecycle")
	_expect(is_zero_approx(actor.get_visual_opacity()), "oversized death-retirement delta did not finish transparent")
	actor.free()

func _test_coordinator_retirement(catalog: EntityCatalog, world: VoxelWorld) -> void:
	var coordinator := WorldEntityCoordinator.new()
	get_root().add_child(coordinator)
	coordinator.setup(catalog, world, 7021, _position_ready)
	var player_position := Vector3(0.5, FEET_Y, 0.5)
	coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	var actors := coordinator.get_runtime().get_active_actors()
	_expect(actors.size() == 1, "coordinator did not spawn the fade test zombie")
	if actors.is_empty():
		coordinator.shutdown()
		coordinator.queue_free()
		return
	var actor := actors[0]
	var runtime_id := actor.runtime_id
	var fade_in_step := actor.visual_fader.fade_in_seconds * 0.25
	coordinator.tick(fade_in_step, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	var interrupted_opacity := actor.get_visual_opacity()
	_expect(interrupted_opacity > 0.0 and interrupted_opacity < 1.0, "interrupted fade setup was not partially visible")
	var former_bounds := actor.get_world_bounds()
	actor.global_position = player_position + Vector3(WorldEntityCoordinator.DESPAWN_DISTANCE + 1.0, 0.0, 0.0)
	coordinator.tick(0.0, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	_expect(coordinator.get_runtime().get_actor(runtime_id) == null and coordinator.get_runtime().get_active_count() == 0, "retiring actor remained active")
	_expect(coordinator.get_runtime()._spatial_index.get_entry_count() == 0, "retiring actor remained spatially indexed")
	_expect(not coordinator.get_runtime().has_entity_overlap(former_bounds), "retiring actor still blocked placement")
	_expect(coordinator.get_runtime()._retiring.size() == 1 and is_instance_valid(actor), "retiring visual was not retained")
	_expect(is_equal_approx(actor.get_visual_opacity(), interrupted_opacity), "interrupted fade-out changed opacity at transition")
	_expect(not actor.death_poof.has_played(), "ordinary coordinator despawn emitted a death poof")
	var fade_out_seconds := actor.visual_fader.fade_out_seconds
	coordinator.tick(fade_out_seconds * 0.5, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	_expect(actor.get_visual_opacity() < interrupted_opacity and actor.get_visual_opacity() > 0.0, "retiring visual did not fade gradually")
	coordinator.tick(fade_out_seconds * 0.5, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	_expect(coordinator.get_runtime()._retiring.is_empty(), "completed retiring visual remained owned")
	await process_frame
	_expect(not is_instance_valid(actor), "completed retiring visual was not freed")
	coordinator.shutdown()
	coordinator.queue_free()
	await process_frame
	await process_frame

func _test_retiring_bound_and_population_independence(catalog: EntityCatalog, world: VoxelWorld) -> void:
	var coordinator := WorldEntityCoordinator.new()
	get_root().add_child(coordinator)
	coordinator.setup(catalog, world, 8842, _position_ready)
	var player_position := Vector3(0.5, FEET_Y, 0.5)
	for _spawn in range(6):
		coordinator._spawn_elapsed = WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS
		coordinator.tick(0.0, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	for _spawn in range(10):
		coordinator._spawn_elapsed = WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS
		coordinator.tick(0.0, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), 12.0)
	_expect(coordinator.get_runtime().get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "retiring-cap setup did not reach the active entity limit")
	var actors := coordinator.get_runtime().get_active_actors()
	actors.sort_custom(func(left: EntityActor, right: EntityActor) -> bool: return left.runtime_id < right.runtime_id)
	var first_retired_actor := actors[1]
	var first_retired_runtime_id := first_retired_actor.runtime_id
	var newest_at_capacity := actors[0]
	for index in range(1, actors.size()):
		coordinator.get_runtime().try_despawn(actors[index].runtime_id)
	coordinator.get_runtime().try_despawn(newest_at_capacity.runtime_id)
	_expect(coordinator.get_runtime().get_active_count() == 0, "mass retirement retained active entities")
	_expect(coordinator.get_runtime()._retiring.size() == WorldEntityCoordinator.MAX_RETIRING_VISUALS, "mass retirement did not fill the visual bound")
	coordinator._spawn_elapsed = WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS - 0.1
	coordinator.tick(0.1, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	_expect(coordinator.get_runtime().get_active_count() == 1, "retiring visuals suppressed an available population slot")
	var replacement := coordinator.get_runtime().get_active_actors()[0]
	replacement.global_position = player_position + Vector3(WorldEntityCoordinator.DESPAWN_DISTANCE + 1.0, 0.0, 0.0)
	coordinator.tick(0.0, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	_expect(coordinator.get_runtime()._retiring.size() == WorldEntityCoordinator.MAX_RETIRING_VISUALS, "thirteenth retirement exceeded the visual bound")
	_expect(not coordinator.get_runtime()._retiring.has(first_retired_runtime_id), "retiring bound did not evict the earliest retained visual")
	_expect(coordinator.get_runtime()._retiring.has(newest_at_capacity.runtime_id), "retiring bound evicted by runtime ID instead of retirement age")
	_expect(coordinator.get_runtime()._retiring.has(replacement.runtime_id), "retiring bound dropped the newest visual")
	await process_frame
	_expect(not is_instance_valid(first_retired_actor), "evicted retiring visual was not freed")
	coordinator.shutdown()
	coordinator.queue_free()
	await process_frame
	await process_frame

func _run() -> void:
	var catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	var world := _make_world()
	_test_species_visual_fades(catalog, world)
	_test_instance_isolation(catalog, world)
	_test_skeleton_attack_presentation(catalog, world)
	_test_species_death_retirement(catalog, world)
	_test_retirement_waits_for_poof(catalog, world)
	_test_oversized_death_retirement_delta(catalog, world)
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
