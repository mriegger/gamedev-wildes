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

func _run() -> void:
	var definition := load("res://entities/definitions/skeleton.tres") as EntityDefinition
	_expect(definition != null and definition.validate(definition.resource_path), "Skeleton definition is invalid")
	var actor := definition.actor_scene.instantiate() as SkeletonActor
	get_root().add_child(actor)
	actor.global_position = Vector3(0.5, float(FEET_Y), 0.5)
	actor.setup(77, definition, _make_world(), 441, EntityNavigationLimits.new(32, 512, 2))
	actor.set_process(false)
	actor.brain._movement_goal = Vector3(8.5, float(FEET_Y), 8.5)
	actor.brain._roam_goal_remaining = 4.0
	var budget := NavigationSearchBudget.new(2)
	for _step in range(8):
		budget.reset()
		actor.tick(0.1, Vector3.ZERO, Vector3.ZERO, budget)
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
	actor.tick(0.0, Vector3.ZERO, Vector3.ZERO, budget)
	var replacement_offset := actor.brain.get_movement_goal() - failure_origin
	_expect(Vector2(replacement_offset.x, replacement_offset.z).length() <= 30.0, "Failed path did not select a current-position-centered replacement")

	actor.free()
	await process_frame
	await process_frame
	if _failures == 0:
		print("SKELETON_ROAMING PASS")
		quit(0)
	else:
		print("SKELETON_ROAMING FAIL failures=%d" % _failures)
		quit(1)
