extends SceneTree

const FLAT_HEIGHT: int = 6
const FEET_Y: float = FLAT_HEIGHT + 1.0
const WORLD_RADIUS: int = 96
const FRAME_DELTA: float = 1.0 / 30.0
const SIMULATION_FRAMES: int = 1800

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[bird_runtime_integration] FAIL: %s" % message)

func _make_world(floor_id: int = BlockId.Type.GRASS) -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
		for z in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLAT_HEIGHT
			world.type_map_dict[Vector2i(x, z)] = floor_id
	return world

func _run() -> void:
	var definition := load("res://entities/definitions/bird.tres") as EntityDefinition
	_expect(definition != null and definition.validate(definition.resource_path), "bird definition is invalid")
	_expect(definition.spawn_placement == EntityDefinition.SpawnPlacement.AERIAL, "bird is not aerially placed")
	_expect(not definition.combat_targetable and definition.experience_reward == 0, "bird is not purely ambient")
	var sampled_variants: Dictionary = {}
	var variant_seeds: Dictionary = {}
	for seed_value in 64:
		var sampled_variant := BirdActor.color_variant_for_seed(seed_value)
		_expect(sampled_variant == BirdActor.color_variant_for_seed(seed_value), "bird color selection was not deterministic")
		sampled_variants[sampled_variant] = true
		if not variant_seeds.has(sampled_variant):
			variant_seeds[sampled_variant] = seed_value
	_expect(sampled_variants.size() == BirdAnimationDriver.ColorVariant.size(), "seeded birds did not cover all four color variants")
	var world := _make_world()
	var aerial_position := Vector3(0.5, FEET_Y + 10.0, 0.5)
	_expect(EntitySpawnGeometry.can_spawn(world, definition, aerial_position), "clear aerial position was rejected")
	_expect(not EntitySpawnGeometry.can_spawn(world, definition, Vector3(0.5, FEET_Y, 0.5)), "supported aerial position was accepted")
	_expect(EntitySpawnGeometry.can_spawn_grounded(world, definition, Vector3(0.5, FEET_Y, 0.5)), "valid landing position was rejected")

	var runtime := EntityRuntime.new()
	root.add_child(runtime)
	var catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	runtime.setup(catalog, world, WorldEntityCoordinator.MAX_TOTAL_ACTIVE, WorldEntityCoordinator.MAX_RETIRING_VISUALS, EntityNavigationLimits.new(24, 256, 1))
	var observation := EntityTargetObservation.create(Vector3.ZERO, Vector3.ZERO, Vector3.FORWARD, Vector3.RIGHT)
	var requests: Array[EntitySpawnRequest] = [EntitySpawnRequest.new(&"bird", aerial_position, 7171)]
	var runtime_ids := runtime.try_spawn_batch(requests)
	_expect(runtime_ids == [1], "bird did not spawn through EntityRuntime")
	var bird := runtime.get_actor(1) as BirdActor
	_expect(bird != null and bird.vocalizations != null, "bird scene did not configure vocalizations")
	var expected_stream_counts: Array[int] = [5, 7, 3, 6]
	for variant in BirdAnimationDriver.ColorVariant.size():
		var profile := bird.vocalization_profiles[variant]
		_expect(profile != null and profile.validate(), "bird variant %d did not have a valid vocalization profile" % variant)
		_expect(profile.streams.size() == expected_stream_counts[variant], "bird variant %d had the wrong vocalization stream count" % variant)
	_expect(bird.vocalizations.bus == &"SFX" and is_equal_approx(bird.vocalizations.volume_db, -4.0), "bird vocalization output was not configured")
	_expect(is_equal_approx(bird.vocalizations.unit_size, 10.0) and is_equal_approx(bird.vocalizations.max_distance, 56.0), "bird vocalization attenuation did not cover its spawn range")
	_expect(not bird.vocalizations.is_processing(), "aerial bird enabled grounded vocalizations")
	_expect(bird != null and bird._has_landing_target, "bird did not acquire an initial landing target")
	var bird_animation := bird.animation_driver as BirdAnimationDriver
	_expect(bird_animation._body_mesh.material_override is StandardMaterial3D, "bird color variant did not create an instance material")
	_expect(bird_animation._wing_flap_audio.stream != null and bird_animation._wing_flap_audio.bus == &"SFX", "bird wing audio was not configured")
	_expect(runtime.try_apply_damage(1, 1.0) == null, "direct damage affected an untargetable bird")
	var visited: Dictionary = {}
	var observed_folded_wings := false
	var observed_flight_audio := false
	var observed_grounded_silence := false
	for _frame in SIMULATION_FRAMES:
		if bird == null:
			break
		visited[bird.brain.state] = true
		runtime.tick(FRAME_DELTA, observation)
		bird.animation_driver.advance(FRAME_DELTA)
		if bird.brain.state in [BirdBrain.State.GROUNDED_IDLE, BirdBrain.State.GROUNDED_WALK]:
			var animation := bird.animation_driver as BirdAnimationDriver
			var left_fold := absf(wrapf(animation._left_wing_pivot.rotation.y - animation._left_wing_origin.basis.get_euler().y, -PI, PI))
			var right_fold := absf(wrapf(animation._right_wing_pivot.rotation.y - animation._right_wing_origin.basis.get_euler().y, -PI, PI))
			observed_folded_wings = observed_folded_wings or left_fold >= deg_to_rad(70.0) and right_fold >= deg_to_rad(70.0)
			observed_grounded_silence = observed_grounded_silence or not animation._wing_flap_audio.playing
		else:
			observed_flight_audio = observed_flight_audio or bird_animation._wing_flap_audio.playing
	_expect(visited.has(BirdBrain.State.CRUISE), "bird never cruised")
	_expect(visited.has(BirdBrain.State.DESCEND), "bird never descended")
	_expect(visited.has(BirdBrain.State.GROUNDED_IDLE), "bird never idled on the ground")
	_expect(visited.has(BirdBrain.State.GROUNDED_WALK), "bird never walked on the ground")
	_expect(visited.has(BirdBrain.State.TAKEOFF), "bird never took off")
	_expect(observed_folded_wings, "grounded bird did not fold both wings")
	_expect(observed_flight_audio, "flying bird did not play wing audio")
	_expect(observed_grounded_silence, "grounded bird did not stop wing audio")
	_expect(not VoxelBodySolver.collides_at(world, bird.global_position, definition.body_width, definition.body_height, false), "bird ended inside solid terrain")

	var canopy_world := _make_world()
	var canopy_edit := VoxelWorldTestFixture.commit_place(canopy_world, Vector3i(0, FLAT_HEIGHT + 2, 0), BlockId.Type.LEAVES)
	_expect(canopy_edit != null, "failed to construct the takeoff obstruction")
	var canopy_runtime := EntityRuntime.new()
	root.add_child(canopy_runtime)
	canopy_runtime.setup(catalog, canopy_world, 1, 1, EntityNavigationLimits.new(24, 256, 1))
	var duck_seed := variant_seeds[BirdAnimationDriver.ColorVariant.DUCK] as int
	var canopy_ids := canopy_runtime.try_spawn_batch([EntitySpawnRequest.new(&"bird", aerial_position, duck_seed)])
	var canopy_bird := canopy_runtime.get_actor(canopy_ids[0]) as BirdActor if not canopy_ids.is_empty() else null
	_expect(canopy_bird != null, "canopy test bird did not spawn")
	if canopy_bird != null:
		canopy_bird.global_position = Vector3(0.5, FEET_Y, 0.5)
		canopy_bird.on_ground = true
		canopy_bird.brain.state = BirdBrain.State.GROUNDED_IDLE
		canopy_bird._update_vocalizations()
		_expect(canopy_bird.vocalizations.is_processing(), "idle grounded duck did not enable vocalizations")
		canopy_bird.vocalizations._remaining_seconds = 0.0
		canopy_bird.vocalizations._process(0.0)
		_expect(canopy_bird.vocalizations.playing, "idle grounded duck did not start a call")
		var canopy_animation := canopy_bird.animation_driver as BirdAnimationDriver
		canopy_animation.advance(0.05)
		_expect(canopy_animation._beak_mesh.scale.y > 1.0, "duck call did not animate the beak")
		canopy_bird.tick(FRAME_DELTA, observation, Vector3.RIGHT, NavigationSearchBudget.new(1))
		_expect(not canopy_bird.vocalizations.is_processing() and not canopy_bird.vocalizations.playing, "moving idle duck continued its call")
		canopy_bird.global_position = Vector3(0.5, FEET_Y, 0.5)
		canopy_bird.velocity = Vector3.ZERO
		canopy_bird.on_ground = true
		canopy_bird.brain.state = BirdBrain.State.GROUNDED_WALK
		canopy_bird._update_vocalizations()
		_expect(not canopy_bird.vocalizations.is_processing() and not canopy_bird.vocalizations.playing, "walking duck continued its idle call")
		canopy_bird.brain.state = BirdBrain.State.TAKEOFF
		canopy_bird._handle_state_transition(BirdBrain.State.GROUNDED_WALK, BirdBrain.State.TAKEOFF)
		_expect(canopy_bird.brain.state == BirdBrain.State.GROUNDED_IDLE, "bird attempted takeoff through an overhead obstruction")
		_expect(canopy_bird.on_ground, "blocked takeoff removed grounded state")
		_expect(canopy_bird.global_position.is_equal_approx(Vector3(0.5, FEET_Y, 0.5)), "blocked takeoff moved the bird")
		canopy_bird.global_position = Vector3(0.5, float(FLAT_HEIGHT + 3), 0.5)
		canopy_bird.on_ground = true
		canopy_bird.brain.state = BirdBrain.State.DESCEND
		canopy_bird._update_vocalizations()
		canopy_bird.tick(FRAME_DELTA, observation, Vector3.ZERO, NavigationSearchBudget.new(1))
		_expect(canopy_bird.brain.state == BirdBrain.State.CRUISE, "bird accepted leaves as a landing surface")
		_expect(not canopy_bird.vocalizations.is_processing(), "bird vocalized after landing on leaves")

	var blocked_world := _make_world(BlockId.Type.STONE)
	var blocked_runtime := EntityRuntime.new()
	root.add_child(blocked_runtime)
	blocked_runtime.setup(catalog, blocked_world, 1, 1, EntityNavigationLimits.new(24, 256, 1))
	var crow_seed := variant_seeds[BirdAnimationDriver.ColorVariant.CROW] as int
	var blocked_ids := blocked_runtime.try_spawn_batch([EntitySpawnRequest.new(&"bird", aerial_position, crow_seed)])
	var blocked_bird := blocked_runtime.get_actor(blocked_ids[0]) as BirdActor if not blocked_ids.is_empty() else null
	_expect(blocked_bird != null and not blocked_bird._has_landing_target, "bird selected a disallowed landing floor")
	if blocked_bird != null:
		var blocked_animation := blocked_bird.animation_driver as BirdAnimationDriver
		_expect(blocked_bird.vocalizations.profile.streams.size() == 5, "crow vocalization profile did not contain all five calls")
		_expect(not blocked_bird.vocalizations.is_processing(), "aerial crow enabled grounded vocalizations")
		blocked_bird.global_position = Vector3(0.5, FEET_Y, 0.5)
		blocked_bird.on_ground = true
		blocked_bird.brain.state = BirdBrain.State.GROUNDED_IDLE
		blocked_bird._update_vocalizations()
		blocked_bird.vocalizations._remaining_seconds = 0.0
		blocked_bird.vocalizations._process(0.0)
		_expect(blocked_bird.vocalizations.playing, "idle grounded crow did not start a call")
		_expect(blocked_bird.vocalizations.profile.streams.has(blocked_bird.vocalizations.stream), "crow call selected a stream outside its profile")
		if canopy_bird != null:
			var canopy_material := ((canopy_bird.animation_driver as BirdAnimationDriver)._body_mesh.material_override as StandardMaterial3D)
			var blocked_material := blocked_animation._body_mesh.material_override as StandardMaterial3D
			_expect(not canopy_material.albedo_color.is_equal_approx(blocked_material.albedo_color), "different bird variants shared the same body color")
			_expect(not is_same(canopy_material, blocked_material), "bird instances shared a mutable color material")
	blocked_runtime.shutdown()
	canopy_runtime.shutdown()
	runtime.shutdown()
	blocked_runtime.queue_free()
	canopy_runtime.queue_free()
	runtime.queue_free()
	await process_frame
	await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "bird teardown ended with %d orphan nodes" % orphan_count)
	if _failures == 0:
		print("BIRD_RUNTIME_INTEGRATION PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("BIRD_RUNTIME_INTEGRATION FAIL failures=%d" % _failures)
		quit(1)
