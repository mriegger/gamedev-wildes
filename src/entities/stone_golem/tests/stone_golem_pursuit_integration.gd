extends SceneTree

const StoneGolemActorType := preload("res://entities/stone_golem/stone_golem_actor.gd")
const StoneGolemAnimationDriverType := preload("res://entities/stone_golem/stone_golem_animation_driver.gd")
const StoneGolemBrainType := preload("res://entities/stone_golem/stone_golem_brain.gd")

const FLAT_HEIGHT: int = 6
const FEET_Y: float = FLAT_HEIGHT + 1.0
const WORLD_RADIUS: int = 48

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[stone_golem_pursuit_integration] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
		for z in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLAT_HEIGHT
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _observation(player_position: Vector3) -> EntityTargetObservation:
	var observation := EntityTargetObservation.create(
		player_position,
		player_position + Vector3(12.0, 16.0, 12.0),
		Vector3(-0.5, -0.5, -0.5),
		Vector3(1.0, 0.0, -1.0),
	)
	assert(observation != null)
	return observation

func _spawn_actor(
	definition: EntityDefinition,
	world: VoxelWorld,
	runtime_id: int,
	position: Vector3,
	navigation_limits: EntityNavigationLimits = null,
) -> StoneGolemActorType:
	var actor := definition.actor_scene.instantiate() as StoneGolemActorType
	get_root().add_child(actor)
	actor.global_position = position
	var limits := navigation_limits if navigation_limits != null else EntityNavigationLimits.new(32, 512, 2)
	actor.setup(runtime_id, definition, world, 7000 + runtime_id, limits)
	actor.set_process(false)
	actor.on_ground = true
	return actor

func _planar_length(value: Vector3) -> float:
	return Vector2(value.x, value.z).length()

func _test_last_seen_pursuit(definition: EntityDefinition, world: VoxelWorld) -> void:
	var behavior := definition.behavior as StoneGolemBehaviorDefinition
	var actor := _spawn_actor(definition, world, 8, Vector3(0.5, FEET_Y, 0.5))
	var budget := NavigationSearchBudget.new(2)
	var initial_position := actor.global_position
	var outside_detection := initial_position + Vector3(behavior.detection_range + 0.5, 0.0, 0.0)
	actor.tick(0.0, _observation(outside_detection), Vector3(4.0, 0.0, 0.0), budget)
	_expect(actor.brain.state == StoneGolemBrainType.State.DORMANT, "out-of-range target woke the dormant Stone Golem")
	_expect(actor.global_position.is_equal_approx(initial_position), "dormant Stone Golem accepted crowd separation")
	_expect(is_zero_approx(_planar_length(actor.velocity)), "dormant Stone Golem retained planar velocity")

	var visible_player := initial_position + Vector3(6.0, 0.0, 6.0)
	budget.reset()
	actor.tick(VoxelPlayerVisibilitySensor.SAMPLE_INTERVAL_SECONDS, _observation(visible_player), Vector3.ZERO, budget)
	_expect(actor.brain.state == StoneGolemBrainType.State.CHASE, "clear nearby target did not start pursuit")
	_expect(actor.brain.get_movement_goal().is_equal_approx(visible_player), "pursuit did not record the visible player position")
	_expect(actor.velocity.x > 0.0 and actor.velocity.z > 0.0, "visible diagonal target did not produce diagonal motion")
	_expect(is_equal_approx(_planar_length(actor.velocity), behavior.movement_speed), "diagonal pursuit changed the 1.2 planar speed")
	actor.animation_driver.advance(0.1)
	_expect(
		(actor.animation_driver as StoneGolemAnimationDriverType).get_current_state() == StoneGolemAnimationDriverType.WALK,
		"moving Stone Golem did not select walk presentation",
	)

	var retained_goal := actor.brain.get_movement_goal()
	var hidden_player := actor.global_position + Vector3(-8.0, 0.0, 0.0)
	var wall_x := floori((actor.global_position.x + hidden_player.x) * 0.5)
	var wall_z := floori(actor.global_position.z)
	world.restore_block_edits({Vector3i(wall_x, FLAT_HEIGHT + 2, wall_z): BlockId.Type.STONE}, {})
	var distance_before_memory := actor.global_position.distance_to(retained_goal)
	budget.reset()
	actor.tick(VoxelPlayerVisibilitySensor.SAMPLE_INTERVAL_SECONDS * 0.5, _observation(hidden_player), Vector3.ZERO, budget)
	_expect(not actor._visibility_sensor.did_sample_line_of_sight(), "between-sample hidden movement unexpectedly sampled LOS")
	_expect(actor.brain.get_movement_goal().is_equal_approx(retained_goal), "cached hidden player replaced the last-seen pursuit goal")
	_expect(actor.global_position.distance_to(retained_goal) < distance_before_memory, "Stone Golem did not continue toward the last-seen goal")
	var moved_hidden_player := hidden_player + Vector3(-1.0, 0.0, 0.0)
	budget.reset()
	actor.tick(VoxelPlayerVisibilitySensor.SAMPLE_INTERVAL_SECONDS * 0.5, _observation(moved_hidden_player), Vector3.ZERO, budget)
	_expect(actor._visibility_sensor.did_sample_line_of_sight(), "hidden player was not sampled at the next boundary")
	_expect(not actor.brain.get_movement_goal().is_equal_approx(moved_hidden_player), "freshly occluded player replaced the last-seen pursuit goal")
	budget.reset()
	actor.tick(0.5, _observation(moved_hidden_player), Vector3.ZERO, budget)
	_expect(actor.brain.get_movement_goal().is_equal_approx(retained_goal), "moving hidden player replaced the last-seen pursuit goal")
	var position_before_expiry := actor.global_position
	budget.reset()
	actor.tick(behavior.target_memory_seconds, _observation(moved_hidden_player), Vector3.ZERO, budget)
	_expect(actor.brain.state == StoneGolemBrainType.State.DORMANT, "Stone Golem kept pursuing after target memory elapsed")
	_expect(actor.global_position.is_equal_approx(position_before_expiry), "Stone Golem moved after target memory elapsed")
	_expect(is_zero_approx(_planar_length(actor.velocity)), "expired target memory retained planar velocity")

	world.restore_block_edits({}, {})
	var restored_visible_player := actor.global_position + Vector3(5.0, 0.0, 5.0)
	budget.reset()
	actor.tick(0.125, _observation(restored_visible_player), Vector3.ZERO, budget)
	_expect(actor.brain.state == StoneGolemBrainType.State.CHASE, "restored line of sight did not restart pursuit")
	var position_before_forget := actor.global_position
	var beyond_forget := actor.global_position + Vector3(behavior.forget_range + 0.001, 0.0, 0.0)
	budget.reset()
	actor.tick(0.1, _observation(beyond_forget), Vector3(4.0, 0.0, 0.0), budget)
	_expect(actor.brain.state == StoneGolemBrainType.State.DORMANT, "target beyond 24 blocks did not stop pursuit immediately")
	_expect(actor.global_position.is_equal_approx(position_before_forget), "Stone Golem moved after the target crossed the forget range")
	actor.free()

func _test_bounded_navigation_recovery(definition: EntityDefinition, world: VoxelWorld) -> void:
	var behavior := definition.behavior as StoneGolemBehaviorDefinition
	var actor := _spawn_actor(
		definition,
		world,
		16,
		Vector3(20.5, FEET_Y, 0.5),
		EntityNavigationLimits.new(2, 32, 2),
	)
	var budget := NavigationSearchBudget.new(2)
	var initial_position := actor.global_position
	var unreachable_goal := initial_position + Vector3(8.0, 0.0, 8.0)
	actor.tick(0.125, _observation(unreachable_goal), Vector3.ZERO, budget)
	_expect(actor.brain.state == StoneGolemBrainType.State.CHASE, "bounded path failure cleared awareness")
	_expect(actor.global_position.is_equal_approx(initial_position), "bounded path failure produced movement")
	_expect(budget._remaining_searches == 1, "bounded path failure did not consume exactly one search")
	var reachable_goal := initial_position + Vector3(1.0, 0.0, 1.0)
	budget.reset()
	actor.tick(0.5, _observation(reachable_goal), Vector3.ZERO, budget)
	_expect(actor.brain.get_movement_goal().is_equal_approx(reachable_goal), "visible reachable goal did not replace a failed path goal")
	_expect(actor.global_position.distance_to(initial_position) > 0.0, "Stone Golem did not recover after a bounded path failure")
	_expect(is_equal_approx(_planar_length(actor.velocity), behavior.movement_speed), "recovered path did not use configured movement speed")
	actor.free()

func _test_obstacle_detour(definition: EntityDefinition, world: VoxelWorld) -> void:
	var actor := _spawn_actor(definition, world, 24, Vector3(-20.5, FEET_Y, 0.5))
	var target := actor.global_position + Vector3(8.0, 0.0, 0.0)
	var budget := NavigationSearchBudget.new(2)
	actor.tick(0.0, _observation(target), Vector3.ZERO, budget)
	_expect(actor.brain.state == StoneGolemBrainType.State.CHASE, "obstacle fixture did not start pursuit")
	var wall_blocks: Dictionary = {}
	for y in range(FLAT_HEIGHT + 1, FLAT_HEIGHT + 3):
		for z in range(-1, 2):
			wall_blocks[Vector3i(-19, y, z)] = BlockId.Type.STONE
	world.restore_block_edits(wall_blocks, {})
	actor._path_follower.request_repath()
	var initial_position := actor.global_position
	var maximum_lateral_offset := 0.0
	for _step in range(20):
		budget.reset()
		actor.tick(0.1, _observation(target), Vector3.ZERO, budget)
		maximum_lateral_offset = maxf(maximum_lateral_offset, absf(actor.global_position.z - initial_position.z))
	_expect(actor.global_position.distance_to(initial_position) > 1.0, "Stone Golem did not progress around a bounded obstacle")
	_expect(maximum_lateral_offset > 0.2, "Stone Golem path did not detour around the blocking wall")
	_expect(
		not VoxelBodySolver.collides_at(world, actor.global_position, definition.body_width, definition.body_height, false),
		"Stone Golem obstacle detour ended inside terrain",
	)
	actor.free()
	world.restore_block_edits({}, {})

func _test_rotated_budget_and_crowd_separation(definition: EntityDefinition, world: VoxelWorld) -> void:
	var catalog := EntityCatalog.new()
	var definitions: Array[EntityDefinition] = [definition]
	catalog.definitions = definitions
	_expect(catalog.validate(), "Stone-Golem-only crowd catalog was invalid")
	var runtime := EntityRuntime.new()
	get_root().add_child(runtime)
	runtime.setup(catalog, world, 3, 3, EntityNavigationLimits.new(32, 512, 2))
	var requests: Array[EntitySpawnRequest] = [
		EntitySpawnRequest.new(definition.id, Vector3(-4.5, FEET_Y, 0.5), 9101),
		EntitySpawnRequest.new(definition.id, Vector3(0.5, FEET_Y, -4.5), 9102),
		EntitySpawnRequest.new(definition.id, Vector3(5.5, FEET_Y, 0.5), 9103),
	]
	var runtime_ids := runtime.try_spawn_batch(requests)
	_expect(runtime_ids.size() == 3, "crowd fixture did not spawn three Stone Golems")
	if runtime_ids.size() != 3:
		runtime.shutdown()
		runtime.free()
		return
	var crowded_positions: Array[Vector3] = [
		Vector3(-0.55, FEET_Y, 0.5),
		Vector3(0.5, FEET_Y, 0.5),
		Vector3(1.55, FEET_Y, 0.5),
	]
	var search_turns: Dictionary = {}
	for index in runtime_ids.size():
		var runtime_id := runtime_ids[index]
		var actor := runtime.get_actor(runtime_id) as StoneGolemActorType
		actor.set_process(false)
		actor.global_position = crowded_positions[index]
		actor.on_ground = true
		runtime._spatial_index.upsert(runtime_id, actor.global_position, actor.get_world_bounds())
		search_turns[runtime_id] = 0
	var observation := _observation(Vector3(8.5, FEET_Y, 8.5))
	for tick_index in range(3):
		var separation_by_id: Dictionary = {}
		for runtime_id in runtime_ids:
			var actor := runtime.get_actor(runtime_id) as StoneGolemActorType
			actor._path_follower.request_repath()
			separation_by_id[runtime_id] = runtime._get_separation_velocity(actor)
		runtime.tick(0.125, observation)
		_expect(runtime._navigation_search_budget._remaining_searches == 0, "crowd tick %d did not consume the shared two-search budget" % tick_index)
		var expected_starved_id := runtime_ids[(tick_index + 2) % runtime_ids.size()]
		for runtime_id in runtime_ids:
			var actor := runtime.get_actor(runtime_id) as StoneGolemActorType
			var received_search := not actor._path_follower._path.is_empty()
			if received_search:
				search_turns[runtime_id] = int(search_turns[runtime_id]) + 1
			_expect(received_search == (runtime_id != expected_starved_id), "crowd tick %d did not rotate its starved navigation turn deterministically" % tick_index)
		var starved_actor := runtime.get_actor(expected_starved_id) as StoneGolemActorType
		var starved_separation := separation_by_id[expected_starved_id] as Vector3
		_expect(not starved_separation.is_zero_approx(), "crowded budget-starved Stone Golem had no separation velocity")
		_expect(
			_planar_length(starved_actor.velocity) > 0.0
			and Vector2(starved_actor.velocity.x, starved_actor.velocity.z).normalized().dot(Vector2(starved_separation.x, starved_separation.z).normalized()) > 0.99,
			"budget-starved Stone Golem did not apply crowd separation",
		)
	for runtime_id in runtime_ids:
		_expect(int(search_turns[runtime_id]) == 2, "rotated ticks did not give Stone Golem %d two navigation searches" % runtime_id)
	runtime.shutdown()
	runtime.free()

func _run() -> void:
	var definition := load("res://entities/definitions/stone_golem.tres") as EntityDefinition
	_expect(definition != null and definition.validate(definition.resource_path), "Stone Golem definition was invalid")
	var world := _make_world()
	_test_last_seen_pursuit(definition, world)
	_test_obstacle_detour(definition, world)
	_test_bounded_navigation_recovery(definition, world)
	_test_rotated_budget_and_crowd_separation(definition, world)
	await process_frame
	await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "pursuit integration ended with %d orphan nodes" % orphan_count)
	if _failures == 0:
		print("STONE_GOLEM_PURSUIT_INTEGRATION PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("STONE_GOLEM_PURSUIT_INTEGRATION FAIL failures=%d" % _failures)
		quit(1)
