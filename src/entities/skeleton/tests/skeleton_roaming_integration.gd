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

func _make_observation(player_position: Vector3, camera_origin: Vector3) -> EntityTargetObservation:
	var observation := EntityTargetObservation.create(
		player_position,
		camera_origin,
		Vector3.BACK,
		Vector3.RIGHT,
	)
	assert(observation != null)
	return observation

func _run() -> void:
	var definition := load("res://entities/definitions/skeleton.tres") as EntityDefinition
	_expect(definition != null and definition.validate(definition.resource_path), "Skeleton definition is invalid")
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

	for y in range(FEET_Y, FEET_Y + 2):
		var mined_edits := world.try_mine_block(Vector3i(0, y, 1))
		_expect(not mined_edits.is_empty() and (mined_edits[0] as BlockEdit).is_success(), "Could not remove Skeleton cover fixture")
	budget.reset()
	actor.tick(0.1, nearby_observation, Vector3.ZERO, budget)
	_expect(actor.brain.state == SkeletonBrain.State.SEARCH_COVER, "Exposed Skeleton did not restart bounded cover search")
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

	actor.free()
	await process_frame
	await process_frame
	if _failures == 0:
		print("SKELETON_ROAMING PASS")
		quit(0)
	else:
		print("SKELETON_ROAMING FAIL failures=%d" % _failures)
		quit(1)
