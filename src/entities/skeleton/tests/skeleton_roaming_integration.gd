extends SceneTree

const FLAT_HEIGHT: int = 6
const FEET_Y: int = FLAT_HEIGHT + 1
const TEST_RADIUS: int = 40

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[skeleton_roaming_integration] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-TEST_RADIUS, TEST_RADIUS + 1):
		for z in range(-TEST_RADIUS, TEST_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLAT_HEIGHT
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _make_observation(
	player_position: Vector3,
	camera_origin: Vector3,
	camera_forward: Vector3 = Vector3.BACK,
	camera_right: Vector3 = Vector3.RIGHT,
) -> EntityTargetObservation:
	var observation := EntityTargetObservation.create(
		player_position,
		camera_origin,
		camera_forward,
		camera_right,
	)
	assert(observation != null)
	return observation

func _test_rotated_crowd_navigation(definition: EntityDefinition) -> void:
	var catalog := EntityCatalog.new()
	var definitions: Array[EntityDefinition] = [definition]
	catalog.definitions = definitions
	_expect(catalog.validate(), "Skeleton-only crowd catalog was invalid")
	var runtime := EntityRuntime.new()
	get_root().add_child(runtime)
	runtime.setup(catalog, _make_world(), 3, 3, EntityNavigationLimits.new(32, 512, 2))
	var player_position := Vector3(0.5, float(FEET_Y), 0.5)
	var spawn_positions: Array[Vector3] = [
		Vector3(-3.5, float(FEET_Y), 0.5),
		Vector3(0.5, float(FEET_Y), -3.5),
		Vector3(4.5, float(FEET_Y), 0.5),
	]
	var requests: Array[EntitySpawnRequest] = []
	for index in range(spawn_positions.size()):
		requests.append(EntitySpawnRequest.new(definition.id, spawn_positions[index], 900 + index))
	var runtime_ids := runtime.try_spawn_batch(requests)
	_expect(runtime_ids.size() == 3, "Crowd fixture did not spawn three Skeletons")
	if runtime_ids.size() != 3:
		runtime.shutdown()
		runtime.free()
		return
	var moved_ticks_by_id: Dictionary = {}
	for runtime_id in runtime_ids:
		var actor := runtime.get_actor(runtime_id) as SkeletonActor
		_expect(actor != null, "Crowd fixture returned a non-Skeleton actor")
		if actor != null:
			actor.set_process(false)
		moved_ticks_by_id[runtime_id] = 0
	var observation := _make_observation(
		player_position,
		Vector3(0.5, float(FEET_Y) + 4.0, -8.5),
	)
	for tick_index in range(3):
		var positions_before_tick: Dictionary = {}
		for runtime_id in runtime_ids:
			var actor := runtime.get_actor(runtime_id) as SkeletonActor
			actor._path_follower.request_repath()
			positions_before_tick[runtime_id] = actor.global_position
		runtime.tick(0.05, observation)
		var remaining_searches := int(runtime._navigation_search_budget._remaining_searches)
		var consumed_searches := 2 - remaining_searches
		_expect(remaining_searches >= 0, "Crowd tick %d exceeded the shared navigation budget" % tick_index)
		_expect(consumed_searches == 2, "Crowd tick %d consumed %d searches instead of two" % [tick_index, consumed_searches])
		var moved_count := 0
		for runtime_id in runtime_ids:
			var actor := runtime.get_actor(runtime_id) as SkeletonActor
			var distance := actor.global_position.distance_to(positions_before_tick[runtime_id] as Vector3)
			if distance > 0.001:
				moved_count += 1
				moved_ticks_by_id[runtime_id] = int(moved_ticks_by_id[runtime_id]) + 1
		_expect(moved_count == 2, "Crowd tick %d moved %d Skeletons instead of the two budget recipients" % [tick_index, moved_count])
	for runtime_id in runtime_ids:
		_expect(int(moved_ticks_by_id[runtime_id]) == 2, "Rotated ticks did not give Skeleton %d two navigation turns" % runtime_id)
	runtime.shutdown()
	runtime.free()

func _run() -> void:
	var definition := load("res://entities/definitions/skeleton.tres") as EntityDefinition
	_expect(definition != null and definition.validate(definition.resource_path), "Skeleton definition is invalid")
	_test_rotated_crowd_navigation(definition)
	var actor := definition.actor_scene.instantiate() as SkeletonActor
	get_root().add_child(actor)
	actor.global_position = Vector3(0.5, float(FEET_Y), 0.5)
	var world := _make_world()
	actor.setup(77, definition, world, 441, EntityNavigationLimits.new(32, 512, 2))
	actor.set_process(false)
	actor.brain._movement_goal = Vector3(8.5, float(FEET_Y), 8.5)
	actor.brain._roam_goal_remaining = 4.0
	var distant_observation := _make_observation(
		Vector3(100.0, float(FEET_Y), 100.0),
		Vector3(0.5, float(FEET_Y) + 0.9, -5.5),
	)
	var budget := NavigationSearchBudget.new(2)
	for _step in range(8):
		budget.reset()
		actor.tick(0.1, distant_observation, Vector3.ZERO, budget)
	_expect(actor.global_position.x > 0.5 and actor.global_position.z > 0.5, "Skeleton did not follow its diagonal path")
	_expect(is_equal_approx(actor.global_position.x, actor.global_position.z), "Skeleton diagonal movement became axis-biased")
	_expect(is_equal_approx(Vector2(actor.velocity.x, actor.velocity.z).length(), 2.4), "Skeleton movement speed changed")
	actor.animation_driver.advance(0.1)
	_expect((actor.animation_driver as SkeletonAnimationDriver).get_current_state() == SkeletonAnimationDriver.WALK, "Moving Skeleton did not use its walk presentation")

	var failure_origin := actor.global_position
	actor.brain._movement_goal = failure_origin + Vector3(64.0, 0.0, 0.0)
	actor.brain._roam_goal_remaining = 4.0
	actor._path_follower.request_repath()
	budget.reset()
	actor.tick(0.0, distant_observation, Vector3.ZERO, budget)
	var replacement_offset := actor.brain.get_movement_goal() - failure_origin
	_expect(Vector2(replacement_offset.x, replacement_offset.z).length() <= 30.0, "Failed path did not select a current-position-centered replacement")

	var cover_origin := Vector3(0.5, float(FEET_Y), 0.5)
	actor.global_position = cover_origin
	actor.velocity = Vector3.ZERO
	actor.on_ground = true
	actor._path_follower.request_repath()
	for y in range(FEET_Y, FEET_Y + 2):
		_expect(world.try_place_block(Vector3i(0, y, 1), BlockId.Type.STONE).is_success(), "Could not build off-position Skeleton cover fixture")
	var nearby_observation := _make_observation(
		Vector3(20.5, float(FEET_Y), 0.5),
		Vector3(0.5, float(FEET_Y) + 0.9, -8.5),
	)
	for _step in range(8):
		budget.reset()
		actor.tick(0.1, nearby_observation, Vector3.ZERO, budget)
		if actor.brain.state == SkeletonBrain.State.MOVE_TO_COVER:
			break
	_expect(actor.brain.state == SkeletonBrain.State.MOVE_TO_COVER, "Exposed Skeleton did not find reachable off-position cover")
	var cover_target := actor.brain.get_movement_goal()
	var target_offset := Vector2(cover_target.x - cover_origin.x, cover_target.z - cover_origin.z)
	_expect(target_offset.length() > 1.0, "Cover search accepted the exposed starting position")

	var maximum_travel := Vector2.ZERO
	for _step in range(60):
		budget.reset()
		actor.tick(0.1, nearby_observation, Vector3.ZERO, budget)
		var travel := Vector2(actor.global_position.x - cover_origin.x, actor.global_position.z - cover_origin.z)
		if travel.length_squared() > maximum_travel.length_squared():
			maximum_travel = travel
		if actor.brain.state == SkeletonBrain.State.HIDE:
			break
	_expect(maximum_travel.length() > 1.0, "Skeleton did not move toward its off-position cover")
	_expect(actor.brain.state == SkeletonBrain.State.HIDE, "Skeleton did not hide after reaching still-occluded cover")
	var final_offset := Vector2(cover_target.x - actor.global_position.x, cover_target.z - actor.global_position.z)
	_expect(final_offset.length() < 0.35, "Skeleton entered hide before reaching its cover target")
	actor.animation_driver.advance(0.1)
	_expect((actor.animation_driver as SkeletonAnimationDriver).get_current_state() == SkeletonAnimationDriver.HIDE, "Hiding Skeleton did not use its hide presentation")

	var rotated_observation := _make_observation(
		nearby_observation.player_position,
		Vector3(-8.5, float(FEET_Y) + 0.9, actor.global_position.z),
		Vector3.RIGHT,
		Vector3.BACK,
	)
	budget.reset()
	actor.tick(0.124, rotated_observation, Vector3.ZERO, budget)
	_expect(actor.brain.state == SkeletonBrain.State.HIDE, "Camera change invalidated cover before the 0.125-second cadence")
	budget.reset()
	budget.try_acquire()
	budget.try_acquire()
	actor.tick(0.001, rotated_observation, Vector3.ZERO, budget)
	_expect(actor.brain.state == SkeletonBrain.State.SEARCH_COVER, "Camera rotation did not invalidate hidden cover at 0.125 seconds")
	budget.reset()
	actor.tick(0.0, distant_observation, Vector3.ZERO, budget)
	_expect(actor.brain.state == SkeletonBrain.State.ROAM, "Skeleton did not return to roaming immediately outside detection range")
	budget.reset()
	actor.tick(0.0, nearby_observation, Vector3.ZERO, budget)
	_expect(actor.brain.state == SkeletonBrain.State.HIDE, "Skeleton did not recognize restored current-position cover")

	for y in range(FEET_Y, FEET_Y + 2):
		var mined_edits := world.try_mine_block(Vector3i(0, y, 1))
		_expect(not mined_edits.is_empty() and (mined_edits[0] as BlockEdit).is_success(), "Could not remove Skeleton cover fixture")
	budget.reset()
	actor.tick(0.124, nearby_observation, Vector3.ZERO, budget)
	_expect(actor.brain.state == SkeletonBrain.State.HIDE, "Mined cover invalidated hide before the 0.125-second cadence")
	budget.reset()
	actor.tick(0.001, nearby_observation, Vector3.ZERO, budget)
	_expect(actor.brain.state == SkeletonBrain.State.SEARCH_COVER, "Mined cover did not restart bounded cover search at 0.125 seconds")
	actor.animation_driver.advance(0.1)
	_expect((actor.animation_driver as SkeletonAnimationDriver).get_current_state() == SkeletonAnimationDriver.IDLE, "Exposed Skeleton retained its hide presentation")

	actor.brain.record_cover_found(actor.global_position + Vector3(40.0, 0.0, 0.0))
	actor._path_follower.request_repath()
	budget.reset()
	actor.tick(0.0, nearby_observation, Vector3.ZERO, budget)
	_expect(
		actor.brain.state == SkeletonBrain.State.SEARCH_COVER and actor.brain.needs_cover_search(),
		"Failed cover path did not request a replacement search",
	)

	var sprint_world := _make_world()
	var sprint_actor := definition.actor_scene.instantiate() as SkeletonActor
	get_root().add_child(sprint_actor)
	sprint_actor.global_position = Vector3(0.5, float(FEET_Y), 0.5)
	sprint_actor.setup(78, definition, sprint_world, 442, EntityNavigationLimits.new(32, 512, 2))
	sprint_actor.set_process(false)
	var sprint_observation := _make_observation(
		Vector3(20.5, float(FEET_Y), 0.5),
		Vector3(0.5, float(FEET_Y) + 0.9, -8.5),
	)
	var sprint_budget := NavigationSearchBudget.new(2)
	for _step in range(100):
		sprint_budget.reset()
		sprint_actor.tick(0.0, sprint_observation, Vector3.ZERO, sprint_budget)
		if sprint_actor.brain.state == SkeletonBrain.State.SPRINT:
			break
	_expect(sprint_actor.brain.state == SkeletonBrain.State.SPRINT, "No-cover search did not exhaust into sprint fallback")
	_expect(is_equal_approx(sprint_actor.max_speed, 5.5), "Sprint fallback did not update the actor speed limit")
	_expect(is_equal_approx(Vector2(sprint_actor.velocity.x, sprint_actor.velocity.z).length(), 5.5), "Sprint fallback did not move at 5.5 blocks per second")
	sprint_actor.animation_driver.advance(0.01)
	_expect((sprint_actor.animation_driver as SkeletonAnimationDriver).get_current_state() == SkeletonAnimationDriver.SPRINT, "Sprint fallback did not use its sprint presentation")

	var before_retry := sprint_actor.global_position
	sprint_budget.reset()
	sprint_actor.tick(0.999, sprint_observation, Vector3.ZERO, sprint_budget)
	_expect(not sprint_actor.brain.needs_cover_search() and not sprint_actor.brain.is_cover_search_in_progress(), "Cover retry started before one second")
	_expect(sprint_actor.global_position.distance_to(before_retry) > 1.0, "Skeleton stopped sprinting before cover retry")
	var retry_boundary_position := sprint_actor.global_position
	sprint_budget.reset()
	sprint_actor.tick(0.001, sprint_observation, Vector3.ZERO, sprint_budget)
	_expect(sprint_actor.brain.is_cover_search_in_progress(), "Cover retry did not start at exactly one second")
	_expect(sprint_actor.brain.state == SkeletonBrain.State.SPRINT, "Background retry interrupted sprint state")
	_expect(sprint_actor.global_position.distance_to(retry_boundary_position) > 0.0, "Background retry froze sprint movement")
	var active_retry_position := sprint_actor.global_position
	sprint_budget.reset()
	sprint_actor.tick(0.1, sprint_observation, Vector3.ZERO, sprint_budget)
	_expect(sprint_actor.global_position.distance_to(active_retry_position) > 0.1, "Active bounded cover search froze sprint movement")
	var outside_observation := _make_observation(
		Vector3(100.0, float(FEET_Y), 100.0),
		Vector3(0.5, float(FEET_Y) + 0.9, -8.5),
	)
	sprint_budget.reset()
	sprint_actor.tick(0.0, outside_observation, Vector3.ZERO, sprint_budget)
	_expect(sprint_actor.brain.state == SkeletonBrain.State.ROAM, "Sprint fallback did not return to roam immediately outside 30 blocks")
	_expect(is_equal_approx(sprint_actor.max_speed, 2.4), "Returning to roam retained the sprint speed limit")
	sprint_actor.animation_driver.advance(0.01)
	_expect((sprint_actor.animation_driver as SkeletonAnimationDriver).get_current_state() != SkeletonAnimationDriver.SPRINT, "Returning to roam retained sprint presentation")

	var stale_world := _make_world()
	for y in range(FEET_Y, FEET_Y + 2):
		_expect(stale_world.try_place_block(Vector3i(0, y, 5), BlockId.Type.STONE).is_success(), "Could not build stale-cover fixture")
	var stale_actor := definition.actor_scene.instantiate() as SkeletonActor
	get_root().add_child(stale_actor)
	stale_actor.global_position = Vector3(0.5, float(FEET_Y), 0.5)
	stale_actor.setup(79, definition, stale_world, 443, EntityNavigationLimits.new(32, 512, 2))
	stale_actor.set_process(false)
	var stale_initial_observation := _make_observation(
		Vector3(20.5, float(FEET_Y), 0.5),
		Vector3(0.5, float(FEET_Y) + 0.9, -8.5),
	)
	var stale_latest_observation := _make_observation(
		stale_initial_observation.player_position,
		Vector3(-8.5, float(FEET_Y) + 0.9, 6.5),
		Vector3.RIGHT,
		Vector3.BACK,
	)
	var stale_budget := NavigationSearchBudget.new(2)
	stale_budget.reset()
	stale_actor.tick(0.0, stale_initial_observation, Vector3.ZERO, stale_budget)
	_expect(stale_actor.brain.is_cover_search_in_progress(), "Stale-cover fixture did not begin an incremental search")
	for _step in range(40):
		stale_budget.reset()
		stale_actor.tick(0.0, stale_latest_observation, Vector3.ZERO, stale_budget)
		if stale_actor.brain.needs_cover_search():
			break
	_expect(stale_actor.brain.state == SkeletonBrain.State.SEARCH_COVER and stale_actor.brain.needs_cover_search(), "Cover found from an old camera snapshot was accepted against the latest camera")

	var result_world := _make_world()
	for y in range(FEET_Y, FEET_Y + 2):
		_expect(result_world.try_place_block(Vector3i(0, y, 1), BlockId.Type.STONE).is_success(), "Could not build background-result fixture")
	var result_actor := definition.actor_scene.instantiate() as SkeletonActor
	get_root().add_child(result_actor)
	result_actor.global_position = Vector3(0.5, float(FEET_Y), 0.5)
	result_actor.setup(80, definition, result_world, 444, EntityNavigationLimits.new(32, 512, 2))
	result_actor.set_process(false)
	result_actor.brain.advance(0.0, result_actor.global_position, sprint_observation.player_position, false)
	result_actor.brain.record_cover_search_started()
	result_actor.brain.record_cover_exhausted()
	result_actor.brain.advance(1.0, result_actor.global_position, sprint_observation.player_position, false)
	var result_budget := NavigationSearchBudget.new(1)
	var starved_retry_position := result_actor.global_position
	result_budget.reset()
	result_actor.tick(0.1, sprint_observation, Vector3.ZERO, result_budget)
	_expect(result_actor.brain.state == SkeletonBrain.State.SPRINT and result_actor.brain.is_cover_search_in_progress(), "Budget-starved background cover retry interrupted sprint state")
	_expect(result_actor.global_position.distance_to(starved_retry_position) > 0.1, "Budget-starved background cover retry froze sprint movement")
	var result_transitioned := false
	for _step in range(30):
		var before_result := result_actor.global_position
		result_budget.reset()
		result_actor.tick(0.1, sprint_observation, Vector3.ZERO, result_budget)
		if result_actor.brain.state == SkeletonBrain.State.MOVE_TO_COVER:
			result_transitioned = true
			_expect(result_actor.global_position.is_equal_approx(before_result), "Accepted background cover applied stale sprint velocity")
			break
	_expect(result_transitioned, "Background cover retry did not accept reachable latest cover")
	_expect(is_equal_approx(result_actor.max_speed, 2.4), "Accepted background cover retained sprint speed")

	actor.free()
	sprint_actor.free()
	stale_actor.free()
	result_actor.free()
	await process_frame
	await process_frame
	if _failures == 0:
		print("SKELETON_ROAMING PASS")
		quit(0)
	else:
		print("SKELETON_ROAMING FAIL failures=%d" % _failures)
		quit(1)
