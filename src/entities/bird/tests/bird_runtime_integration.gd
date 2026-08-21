extends SceneTree

const FLAT_HEIGHT: int = 6
const FEET_Y: float = FLAT_HEIGHT + 1.0
const WATER_LEVEL: int = 5
const WATER_FLOOR_HEIGHT: int = 2
const WATER_SURFACE_Y: float = float(WATER_LEVEL) + VoxelSpace.WATER_SURFACE_HEIGHT
const WORLD_RADIUS: int = 96
const FRAME_DELTA: float = 1.0 / 30.0
const SIMULATION_FRAMES: int = 1800

var _failures: int = 0
var _water_ripple_events: Array[Dictionary] = []

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[bird_runtime_integration] FAIL: %s" % message)

func _make_world(floor_id: int = BlockId.Type.GRASS, terrain_height: int = FLAT_HEIGHT) -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, WATER_LEVEL, 8.0, block_catalog)
	for x in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
		for z in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = terrain_height
			world.type_map_dict[Vector2i(x, z)] = floor_id
	return world

func _make_canopy_world() -> VoxelWorld:
	var world := _make_world()
	for x in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
		for z in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
			world.tree_block_fast[Vector3i(x, FLAT_HEIGHT + 3, z)] = BlockId.Type.LEAVES
	return world

func _run() -> void:
	var definition := load("res://entities/definitions/bird.tres") as EntityDefinition
	var owl_definition := load("res://entities/definitions/owl.tres") as EntityDefinition
	_expect(definition != null and definition.validate(definition.resource_path), "bird definition is invalid")
	_expect(owl_definition != null and owl_definition.validate(owl_definition.resource_path), "owl definition is invalid")
	_expect(definition.spawn_placement == EntityDefinition.SpawnPlacement.AERIAL, "bird is not aerially placed")
	_expect(definition.combat_targetable and definition.experience_reward == 0, "bird is not a targetable non-progression creature")
	_expect(is_equal_approx(definition.stats_definition.maximum_hp, 1.0), "bird is not configured for one-hit defeat")
	_expect(owl_definition.ambient_spawn_phase == EntityDefinition.SpawnPhase.NIGHT, "owl is not night-only")
	_expect(owl_definition.ambient_spawn_enabled and owl_definition.ambient_max_active == 1 and is_equal_approx(owl_definition.ambient_spawn_weight, 45.56), "owl is not enabled and rare")
	_expect(owl_definition.combat_targetable and is_equal_approx(owl_definition.stats_definition.maximum_hp, 1.0), "owl is not configured for one-hit defeat")
	_expect(is_equal_approx(owl_definition.ambient_spawn_end_hour, 5.0), "owl dawn departure time changed")
	_expect(owl_definition.ambient_spawn_floor_ids == [BlockId.Type.LEAVES], "owl landing floors are not tree-only")
	var sampled_variants: Dictionary = {}
	var variant_seeds: Dictionary = {}
	for seed_value in 64:
		var sampled_variant := BirdColorVariant.common_for_seed(seed_value)
		_expect(sampled_variant == BirdColorVariant.common_for_seed(seed_value), "bird color selection was not deterministic")
		sampled_variants[sampled_variant] = true
		if not variant_seeds.has(sampled_variant):
			variant_seeds[sampled_variant] = seed_value
	_expect(sampled_variants.size() == BirdColorVariant.COMMON_COUNT, "seeded birds did not cover all four common color variants")
	var catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	var observation := EntityTargetObservation.create(Vector3.ZERO, Vector3.ZERO, Vector3.FORWARD, Vector3.RIGHT)
	var distant_observation := EntityTargetObservation.create(Vector3(1000.0, 0.0, 1000.0), Vector3(1000.0, 0.0, 1000.0), Vector3.FORWARD, Vector3.RIGHT)
	var duck_seed := variant_seeds[BirdColorVariant.Type.DUCK] as int
	var crow_seed := variant_seeds[BirdColorVariant.Type.CROW] as int
	var redbird_seed := variant_seeds[BirdColorVariant.Type.REDBIRD] as int
	var bluebird_seed := variant_seeds[BirdColorVariant.Type.BLUEBIRD] as int
	_expect(definition.resolve_loot_pool(crow_seed).id == &"bird_black_feather", "crow did not resolve black feather loot")
	_expect(definition.resolve_loot_pool(redbird_seed).id == &"bird_red_feather", "redbird did not resolve red feather loot")
	_expect(definition.resolve_loot_pool(bluebird_seed).id == &"bird_blue_feather", "bluebird did not resolve blue feather loot")
	_expect(definition.resolve_loot_pool(duck_seed) == null, "duck unexpectedly resolved feather loot")
	_expect(owl_definition.resolve_loot_pool(31415) == null, "owl unexpectedly resolved feather loot")
	var debug_world := _make_world()
	var debug_coordinator := WorldEntityCoordinator.new()
	root.add_child(debug_coordinator)
	debug_coordinator.setup(catalog, debug_world, 81173, Callable(self, "_position_ready"))
	var debug_player_position := Vector3(0.5, FEET_Y, 0.5)
	_expect(debug_coordinator.try_spawn_debug_birds(debug_player_position, &"", 4), "mixed debug bird command did not spawn")
	var debug_variants: Dictionary = {}
	for actor in debug_coordinator.get_runtime().get_active_actors():
		debug_variants[(actor as BirdActor).color_variant] = true
	_expect(debug_variants.size() == BirdColorVariant.COMMON_COUNT, "mixed debug bird command did not spawn every common variant")
	_expect(debug_coordinator.try_spawn_debug_birds(debug_player_position, &"redbird", 2), "specific debug bird command did not spawn")
	var redbird_count := 0
	for actor in debug_coordinator.get_runtime().get_active_actors():
		if (actor as BirdActor).color_variant == BirdColorVariant.Type.REDBIRD:
			redbird_count += 1
	_expect(redbird_count == 3, "specific debug bird command spawned the wrong variants")
	var debug_count := debug_coordinator.get_runtime().get_active_count()
	_expect(not debug_coordinator.try_spawn_debug_birds(debug_player_position, &"goose", 1), "unknown debug bird variant was accepted")
	_expect(debug_coordinator.try_spawn_debug_birds(debug_player_position, &"", WorldEntityCoordinator.MAX_TOTAL_ACTIVE * 4), "oversized debug bird command did not fill remaining runtime capacity")
	_expect(debug_coordinator.get_runtime().get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "debug bird command did not stop at the runtime cap")
	_expect(not debug_coordinator.try_spawn_debug_birds(debug_player_position, &"", 1), "debug bird command spawned beyond a full runtime")
	_expect(debug_count == 6, "debug bird capacity fixture changed")
	var canopy_debug_world := _make_canopy_world()
	var canopy_debug_coordinator := WorldEntityCoordinator.new()
	root.add_child(canopy_debug_coordinator)
	canopy_debug_coordinator.setup(catalog, canopy_debug_world, 45591, Callable(self, "_position_ready"))
	_expect(canopy_debug_coordinator.try_spawn_debug_birds(debug_player_position, &"owl", 1), "owl debug command did not spawn")
	var debug_owl := canopy_debug_coordinator.get_runtime().get_active_actors()[0] as BirdActor
	_expect(debug_owl.definition.id == &"owl" and debug_owl.color_variant == BirdColorVariant.Type.OWL, "owl debug command used the wrong definition or appearance")
	_expect(debug_owl.vocalizations != null and debug_owl.vocalizations.profile != null, "owl vocalizations were not configured")
	_expect(debug_owl.vocalizations.profile.streams.size() == 3 and debug_owl.vocalizations.profile.validate(), "owl vocalization profile is invalid")
	_expect(debug_owl._has_landing_target and not debug_owl._landing_on_water, "owl did not select a canopy landing target")
	var debug_owl_floor_y := floori(debug_owl._landing_target.y - 0.001)
	_expect(canopy_debug_world.get_block_id_at(Vector3i(floori(debug_owl._landing_target.x), debug_owl_floor_y, floori(debug_owl._landing_target.z))) == BlockId.Type.LEAVES, "owl selected a non-tree landing target")
	var owl_animation := debug_owl.animation_driver as BirdAnimationDriver
	_expect(debug_owl.model_root.scale == Vector3.ONE * 2.0, "owl was not scaled for gameplay readability")
	_expect(owl_animation._head_mesh.scale.x > 1.0 and owl_animation._left_eye_mesh.scale.x > 2.0, "owl silhouette was not applied")
	var owl_eye_material := owl_animation._left_eye_mesh.material_override as StandardMaterial3D
	_expect(owl_eye_material != null and owl_eye_material.emission_enabled, "owl eyes were not made visible at night")
	_expect(is_equal_approx(owl_eye_material.emission_energy_multiplier, BirdAnimationDriver.OWL_EYE_EMISSION_ENERGY), "owl eye glow strength changed")
	_expect(is_equal_approx(debug_owl.vocalizations.max_distance, 32.0), "owl vocalization range exceeds its readable visual range")
	debug_owl.global_position = debug_owl._landing_target
	debug_owl.velocity = Vector3.ZERO
	debug_owl.on_ground = true
	debug_owl.brain.state = BirdBrain.State.DESCEND
	debug_owl.tick_gameplay(FRAME_DELTA, distant_observation, Vector3.ZERO, NavigationSearchBudget.new(1))
	owl_animation.advance(FRAME_DELTA)
	_expect(debug_owl.brain.state == BirdBrain.State.GROUNDED_IDLE and debug_owl.on_ground, "owl rejected a tree-canopy landing")
	_expect(debug_owl.vocalizations.is_processing(), "owl vocalizations did not activate while perched")
	var common_owl_definition := owl_definition.duplicate(true) as EntityDefinition
	common_owl_definition.ambient_spawn_weight = 100.0
	var owl_catalog := EntityCatalog.new()
	owl_catalog.definitions = [common_owl_definition]
	var phase_coordinator := WorldEntityCoordinator.new()
	root.add_child(phase_coordinator)
	phase_coordinator.setup(owl_catalog, canopy_debug_world, 7331, Callable(self, "_position_ready"))
	phase_coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, observation, 12.0)
	_expect(phase_coordinator.get_runtime().get_active_count() == 0, "owl spawned during daytime")
	phase_coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, observation, 22.0)
	_expect(phase_coordinator.get_runtime().get_definition_count(&"owl") == 1, "owl did not spawn at night over a tree canopy")
	var retiring_owl := phase_coordinator.get_runtime().get_active_actors()[0] as BirdActor
	var retiring_owl_id := retiring_owl.runtime_id
	phase_coordinator.tick(0.0, observation, 4.99)
	_expect(phase_coordinator.get_runtime().get_actor(retiring_owl_id) == retiring_owl, "owl retired before 05:00")
	phase_coordinator.tick(0.0, observation, 5.0)
	_expect(phase_coordinator.get_runtime().get_actor(retiring_owl_id) == null, "owl remained active at 05:00")
	_expect(phase_coordinator.get_runtime()._retiring.has(retiring_owl_id) and retiring_owl.brain.state == BirdBrain.State.TAKEOFF, "retiring owl did not begin its departure flight")
	var departure_start_y := retiring_owl.global_position.y
	phase_coordinator.tick(0.5, observation, 5.0)
	_expect(retiring_owl.global_position.y > departure_start_y, "retiring owl did not fly upward")
	phase_coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, observation, 5.5)
	_expect(phase_coordinator.get_runtime().get_definition_count(&"owl") == 0, "owl respawned after its 05:00 cutoff")
	var water_world := _make_world(BlockId.Type.SAND, WATER_FLOOR_HEIGHT)
	var water_runtime := EntityRuntime.new()
	root.add_child(water_runtime)
	water_runtime.setup(catalog, water_world, 2, 2, EntityNavigationLimits.new(24, 256, 1), EntityRuntime.Mode.GAMEPLAY)
	water_runtime.water_surface_motion_committed.connect(_on_water_surface_motion_committed)
	var water_ids := water_runtime.try_spawn_batch([
		EntitySpawnRequest.new(&"bird", Vector3(-0.5, FEET_Y + 10.0, 0.5), crow_seed),
		EntitySpawnRequest.new(&"bird", Vector3(0.5, FEET_Y + 10.0, 0.5), duck_seed),
	])
	var water_crow := water_runtime.get_actor(water_ids[0]) as BirdActor if water_ids.size() == 2 else null
	var water_duck := water_runtime.get_actor(water_ids[1]) as BirdActor if water_ids.size() == 2 else null
	_expect(water_crow != null and not water_crow._has_landing_target, "crow selected submerged terrain as a landing target")
	_expect(water_duck != null and water_duck._has_landing_target and water_duck._landing_on_water, "duck did not select a water landing target")
	if water_duck != null:
		_expect(is_equal_approx(water_duck._landing_target.y, WATER_SURFACE_Y), "duck targeted the submerged floor instead of the water surface")
		var duck_visited_ground := false
		var duck_visited_takeoff := false
		for _frame in SIMULATION_FRAMES:
			water_runtime.tick_gameplay(FRAME_DELTA, observation)
			if water_duck.brain.state in [BirdBrain.State.GROUNDED_IDLE, BirdBrain.State.GROUNDED_WALK]:
				duck_visited_ground = true
				_expect(is_equal_approx(water_duck.global_position.y, WATER_SURFACE_Y), "grounded duck sank below the water surface")
			elif duck_visited_ground and water_duck.brain.state == BirdBrain.State.TAKEOFF:
				duck_visited_takeoff = true
				break
		_expect(duck_visited_ground, "duck never landed on the water")
		_expect(duck_visited_takeoff, "duck became stuck after landing on the water")
		var observed_landing_ripple := false
		var observed_swimming_ripple := false
		for event in _water_ripple_events:
			var ripple_position := event["position"] as Vector3
			var ripple_velocity := event["planar_velocity"] as Vector2
			_expect(is_equal_approx(ripple_position.y, WATER_SURFACE_Y), "duck ripple was not placed on the water surface")
			observed_landing_ripple = observed_landing_ripple or ripple_velocity.is_zero_approx()
			observed_swimming_ripple = observed_swimming_ripple or ripple_velocity.length() >= BirdActor.WATER_RIPPLE_MINIMUM_SPEED
		_expect(observed_landing_ripple, "duck landing did not emit a water ripple")
		_expect(observed_swimming_ripple, "swimming duck did not emit a directional water ripple")
		_expect(_water_ripple_events.size() <= 12, "swimming duck emitted unbounded water ripples")
	if water_crow != null:
		water_crow.global_position = Vector3(-0.5, float(WATER_FLOOR_HEIGHT + 1), 0.5)
		water_crow.velocity = Vector3.ZERO
		water_crow.on_ground = true
		water_crow.brain.state = BirdBrain.State.DESCEND
		water_crow.tick_gameplay(FRAME_DELTA, observation, Vector3.ZERO, NavigationSearchBudget.new(1))
		_expect(water_crow.brain.state == BirdBrain.State.TAKEOFF and not water_crow.on_ground, "crow did not escape an invalid underwater landing")
	var world := _make_world()
	var aerial_position := Vector3(0.5, FEET_Y + 10.0, 0.5)
	_expect(EntitySpawnGeometry.can_spawn(world, definition, aerial_position), "clear aerial position was rejected")
	_expect(not EntitySpawnGeometry.can_spawn(world, definition, Vector3(0.5, FEET_Y, 0.5)), "supported aerial position was accepted")
	_expect(EntitySpawnGeometry.can_spawn_grounded(world, definition, Vector3(0.5, FEET_Y, 0.5)), "valid landing position was rejected")

	var runtime := EntityRuntime.new()
	root.add_child(runtime)
	runtime.setup(catalog, world, WorldEntityCoordinator.MAX_TOTAL_ACTIVE, WorldEntityCoordinator.MAX_RETIRING_VISUALS, EntityNavigationLimits.new(24, 256, 1), EntityRuntime.Mode.GAMEPLAY)
	var requests: Array[EntitySpawnRequest] = [EntitySpawnRequest.new(&"bird", aerial_position, 7171)]
	var runtime_ids := runtime.try_spawn_batch(requests)
	_expect(runtime_ids == [1], "bird did not spawn through EntityRuntime")
	var bird := runtime.get_actor(1) as BirdActor
	_expect(bird != null and bird.vocalizations != null, "bird scene did not configure vocalizations")
	var expected_stream_counts: Array[int] = [5, 7, 3, 6]
	for variant in BirdColorVariant.COMMON_COUNT:
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
	var visited: Dictionary = {}
	var observed_folded_wings := false
	var observed_flight_audio := false
	var observed_grounded_silence := false
	for _frame in SIMULATION_FRAMES:
		if bird == null:
			break
		visited[bird.brain.state] = true
		runtime.tick_gameplay(FRAME_DELTA, observation)
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
	_expect(bird.death_audio != null and bird.death_audio.has_valid_presentation(), "bird death audio was not configured")
	var damage_result := runtime.try_apply_damage(1, 1.0)
	_expect(damage_result != null and damage_result.defeated, "one point of damage did not defeat the bird")
	_expect(runtime.get_actor(1) == null and runtime.get_presented_actor(1) == bird, "defeated bird did not enter visual retirement")
	_expect(bird.death_audio.playing and bird.death_audio.stream != null, "bird defeat did not play the death squawk")
	runtime.tick_gameplay(BirdAnimationDriver.DEATH_SECONDS, observation)
	_expect(bird.death_poof.has_played(), "bird defeat did not emit feather particles")
	var owl_runtime := EntityRuntime.new()
	root.add_child(owl_runtime)
	owl_runtime.setup(catalog, world, 1, 1, EntityNavigationLimits.new(24, 256, 1), EntityRuntime.Mode.GAMEPLAY)
	var owl_ids := owl_runtime.try_spawn_batch([EntitySpawnRequest.new(&"owl", aerial_position, 31415)])
	var grounded_owl := owl_runtime.get_actor(owl_ids[0]) as BirdActor if not owl_ids.is_empty() else null
	_expect(grounded_owl != null and not grounded_owl._has_landing_target, "owl selected open ground without a tree")
	if grounded_owl != null:
		grounded_owl.global_position = Vector3(0.5, FEET_Y, 0.5)
		grounded_owl.velocity = Vector3.ZERO
		grounded_owl.on_ground = true
		grounded_owl.brain.state = BirdBrain.State.DESCEND
		grounded_owl.tick_gameplay(FRAME_DELTA, observation, Vector3.ZERO, NavigationSearchBudget.new(1))
		_expect(grounded_owl.brain.state == BirdBrain.State.TAKEOFF and not grounded_owl.on_ground, "owl accepted a non-tree landing")

	var canopy_world := _make_world()
	var canopy_edit := VoxelWorldTestFixture.commit_place(canopy_world, Vector3i(0, FLAT_HEIGHT + 2, 0), BlockId.Type.LEAVES)
	_expect(canopy_edit != null, "failed to construct the takeoff obstruction")
	var canopy_runtime := EntityRuntime.new()
	root.add_child(canopy_runtime)
	canopy_runtime.setup(catalog, canopy_world, 1, 1, EntityNavigationLimits.new(24, 256, 1), EntityRuntime.Mode.GAMEPLAY)
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
		canopy_bird.tick_gameplay(FRAME_DELTA, distant_observation, Vector3.RIGHT, NavigationSearchBudget.new(1))
		_expect(not canopy_bird.vocalizations.is_processing() and not canopy_bird.vocalizations.playing, "moving idle duck continued its call")
		canopy_bird.brain.state = BirdBrain.State.GROUNDED_IDLE
		var outside_flee_radius := canopy_bird.global_position - Vector3(5.1, 0.0, 0.0)
		_expect(not canopy_bird._try_startle_from_player(outside_flee_radius) and canopy_bird.brain.state == BirdBrain.State.GROUNDED_IDLE, "bird fled before the player entered five blocks")
		var nearby_player := canopy_bird.global_position - Vector3(4.9, 0.0, 0.0)
		canopy_bird.tick_gameplay(FRAME_DELTA, EntityTargetObservation.create(nearby_player, nearby_player, Vector3.FORWARD, Vector3.RIGHT), Vector3.ZERO, NavigationSearchBudget.new(1))
		_expect(canopy_bird.brain.state == BirdBrain.State.TAKEOFF and not canopy_bird.on_ground, "bird did not take off when the player came within five blocks")
		_expect((canopy_bird._takeoff_target - canopy_bird.global_position).dot(Vector3.RIGHT) > 0.0, "startled bird did not choose a route away from the player")
		_expect(not canopy_bird.vocalizations.is_processing() and not canopy_bird.vocalizations.playing, "startled bird continued its call")
		canopy_bird.global_position = Vector3(0.5, FEET_Y, 0.5)
		canopy_bird.velocity = Vector3.ZERO
		canopy_bird.on_ground = true
		canopy_bird.brain.state = BirdBrain.State.GROUNDED_WALK
		canopy_bird._update_vocalizations()
		_expect(not canopy_bird.vocalizations.is_processing() and not canopy_bird.vocalizations.playing, "walking duck continued its idle call")
		canopy_bird.brain.state = BirdBrain.State.TAKEOFF
		canopy_bird._handle_state_transition(BirdBrain.State.GROUNDED_WALK, BirdBrain.State.TAKEOFF)
		_expect(canopy_bird.brain.state == BirdBrain.State.TAKEOFF, "bird abandoned takeoff below an overhead obstruction")
		_expect(not canopy_bird.on_ground, "canopy escape did not leave grounded state")
		_expect(Vector2(canopy_bird._takeoff_target.x - canopy_bird.global_position.x, canopy_bird._takeoff_target.z - canopy_bird.global_position.z).length() >= 2.0, "canopy escape did not select a lateral route")
		var escaped_canopy := false
		for _frame in 180:
			canopy_bird.tick_gameplay(FRAME_DELTA, observation, Vector3.ZERO, NavigationSearchBudget.new(1))
			if canopy_bird.brain.state == BirdBrain.State.CRUISE:
				escaped_canopy = true
				break
		_expect(escaped_canopy, "bird remained trapped below an overhead obstruction")
		canopy_bird.global_position = Vector3(0.5, float(FLAT_HEIGHT + 3), 0.5)
		canopy_bird.on_ground = true
		canopy_bird.brain.state = BirdBrain.State.DESCEND
		canopy_bird._update_vocalizations()
		canopy_bird.tick_gameplay(FRAME_DELTA, observation, Vector3.ZERO, NavigationSearchBudget.new(1))
		_expect(canopy_bird.brain.state == BirdBrain.State.TAKEOFF, "bird did not escape a landing on leaves")
		_expect(not canopy_bird.vocalizations.is_processing(), "bird vocalized after landing on leaves")

	var blocked_world := _make_world(BlockId.Type.STONE)
	var blocked_runtime := EntityRuntime.new()
	root.add_child(blocked_runtime)
	blocked_runtime.setup(catalog, blocked_world, 1, 1, EntityNavigationLimits.new(24, 256, 1), EntityRuntime.Mode.GAMEPLAY)
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
	owl_runtime.shutdown()
	runtime.shutdown()
	water_runtime.shutdown()
	phase_coordinator.shutdown()
	canopy_debug_coordinator.shutdown()
	debug_coordinator.shutdown()
	blocked_runtime.queue_free()
	canopy_runtime.queue_free()
	owl_runtime.queue_free()
	runtime.queue_free()
	water_runtime.queue_free()
	phase_coordinator.queue_free()
	canopy_debug_coordinator.queue_free()
	debug_coordinator.queue_free()
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

func _position_ready(_position: Vector3) -> bool:
	return true

func _on_water_surface_motion_committed(position: Vector3, planar_velocity: Vector2) -> void:
	_water_ripple_events.append({"position": position, "planar_velocity": planar_velocity})
