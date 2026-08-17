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

	var cover_position := actor.global_position
	var nearby_observation := _make_observation(
		cover_position + Vector3(0.0, 0.0, -10.0),
		cover_position + Vector3(0.0, 0.9, -6.0),
	)
	budget.reset()
	actor.tick(0.1, nearby_observation, Vector3.RIGHT * 2.0, budget)
	_expect(actor.brain.state == SkeletonBrain.State.SEARCH_COVER, "Camera-exposed Skeleton did not search for cover")
	_expect(Vector2(actor.velocity.x, actor.velocity.z).is_zero_approx(), "Cover-searching Skeleton did not stop")
	_expect(Vector2(actor.global_position.x - cover_position.x, actor.global_position.z - cover_position.z).is_zero_approx(), "Cover-searching Skeleton changed position")

	var wall_z := floori(cover_position.z) - 3
	var wall_x_min := floori(cover_position.x - definition.body_width * 0.5)
	var wall_x_max := floori(cover_position.x + definition.body_width * 0.5)
	for x in range(wall_x_min, wall_x_max + 1):
		for y in range(FEET_Y, FEET_Y + 2):
			_expect(world.try_place_block(Vector3i(x, y, wall_z), BlockId.Type.STONE).is_success(), "Could not build Skeleton cover fixture")
	budget.reset()
	actor.tick(0.1, nearby_observation, Vector3.RIGHT * 2.0, budget)
	_expect(actor.brain.state == SkeletonBrain.State.HIDE, "Fully occluded Skeleton did not hide")
	_expect(Vector2(actor.velocity.x, actor.velocity.z).is_zero_approx(), "Hiding Skeleton did not stop")
	actor.animation_driver.advance(0.1)
	_expect((actor.animation_driver as SkeletonAnimationDriver).get_current_state() == SkeletonAnimationDriver.HIDE, "Hiding Skeleton did not use its hide presentation")

	var mined_edits := world.try_mine_block(Vector3i(wall_x_max, FEET_Y + 1, wall_z))
	_expect(not mined_edits.is_empty() and (mined_edits[0] as BlockEdit).is_success(), "Could not expose the Skeleton cover fixture")
	budget.reset()
	actor.tick(0.1, nearby_observation, Vector3.RIGHT * 2.0, budget)
	_expect(actor.brain.state == SkeletonBrain.State.SEARCH_COVER, "Partially exposed Skeleton did not resume cover search")
	actor.animation_driver.advance(0.1)
	_expect((actor.animation_driver as SkeletonAnimationDriver).get_current_state() == SkeletonAnimationDriver.IDLE, "Exposed Skeleton retained its hide presentation")

	actor.free()
	await process_frame
	await process_frame
	if _failures == 0:
		print("SKELETON_ROAMING PASS")
		quit(0)
	else:
		print("SKELETON_ROAMING FAIL failures=%d" % _failures)
		quit(1)
