extends SceneTree

const FLAT_HEIGHT: int = 6
const FEET_Y: int = FLAT_HEIGHT + 1
const TEST_RADIUS: int = 12
const BODY_WIDTH: float = 0.6
const BODY_HEIGHT: float = 1.8

var _failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[entity_navigation_integration] FAIL: %s" % message)

func _make_flat_world() -> VoxelWorld:
	var catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, catalog)
	for x in range(-TEST_RADIUS, TEST_RADIUS + 1):
		for z in range(-TEST_RADIUS, TEST_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLAT_HEIGHT
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _set_height(world: VoxelWorld, x: int, z: int, height: int) -> void:
	world.height_map_dict[Vector2i(x, z)] = height
	world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS

func _expect_cardinal_path(path: Array[Vector3i], message: String) -> void:
	for index in range(1, path.size()):
		var offset := path[index] - path[index - 1]
		_expect(abs(offset.x) + abs(offset.z) == 1, "%s used a non-cardinal edge at %d" % [message, index])
		_expect(abs(offset.y) <= 1, "%s exceeded one block of elevation at %d" % [message, index])

func _test_deterministic_bounded_pathfinding() -> void:
	var world := _make_flat_world()
	var start := Vector3i(0, FEET_Y, 0)
	var goal := Vector3i(4, FEET_Y, 3)
	var first := VoxelPathfinder.find_path(world, start, goal, BODY_WIDTH, BODY_HEIGHT, 8, 128)
	var second := VoxelPathfinder.find_path(world, start, goal, BODY_WIDTH, BODY_HEIGHT, 8, 128)
	_expect(first.is_success(), "flat-ground path was not found")
	_expect(first.path == second.path, "same search inputs produced different paths")
	_expect(first.path.size() == 8, "flat path was not the seven-edge shortest path")
	_expect(first.path.front() == start and first.path.back() == goal, "path endpoints changed")
	_expect(first.visited_nodes <= 128, "successful search exceeded its node budget")
	_expect_cardinal_path(first.path, "flat path")

	var outside_radius := VoxelPathfinder.find_path(world, start, Vector3i(5, FEET_Y, 0), BODY_WIDTH, BODY_HEIGHT, 4, 128)
	_expect(outside_radius.status == VoxelPathResult.Status.NO_PATH, "goal outside radius did not fail")
	_expect(outside_radius.visited_nodes == 0, "out-of-radius search visited nodes")

	var limited := VoxelPathfinder.find_path(world, start, goal, BODY_WIDTH, BODY_HEIGHT, 8, 2)
	_expect(limited.status == VoxelPathResult.Status.LIMIT_REACHED, "node-limited search did not report its limit")
	_expect(limited.visited_nodes <= 2, "node-limited search exceeded its budget")

func _test_elevation_clearance_and_water() -> void:
	var step_up_world := _make_flat_world()
	_set_height(step_up_world, 1, 0, FLAT_HEIGHT + 1)
	var step_up := VoxelPathfinder.find_path(step_up_world, Vector3i(0, FEET_Y, 0), Vector3i(2, FEET_Y, 0), BODY_WIDTH, BODY_HEIGHT, 4, 64)
	_expect(step_up.is_success(), "one-block rise was not traversable")
	_expect(step_up.path.has(Vector3i(1, FEET_Y + 1, 0)), "one-block rise was not represented in the path")
	_expect_cardinal_path(step_up.path, "step-up path")

	var step_down_world := _make_flat_world()
	_set_height(step_down_world, 1, 0, FLAT_HEIGHT - 1)
	var step_down := VoxelPathfinder.find_path(step_down_world, Vector3i(0, FEET_Y, 0), Vector3i(2, FEET_Y, 0), BODY_WIDTH, BODY_HEIGHT, 4, 64)
	_expect(step_down.is_success(), "one-block drop was not traversable")
	_expect(step_down.path.has(Vector3i(1, FEET_Y - 1, 0)), "one-block drop was not represented in the path")
	_expect_cardinal_path(step_down.path, "step-down path")

	var ceiling_world := _make_flat_world()
	_set_height(ceiling_world, 1, 0, FLAT_HEIGHT + 1)
	ceiling_world.restore_block_edits({Vector3i(0, FEET_Y + 2, 0): BlockId.Type.STONE}, {})
	var ceiling_detour := VoxelPathfinder.find_path(ceiling_world, Vector3i(0, FEET_Y, 0), Vector3i(2, FEET_Y, 0), BODY_WIDTH, BODY_HEIGHT, 4, 64)
	_expect(ceiling_detour.is_success(), "step obstruction prevented a valid detour")
	_expect(ceiling_detour.path.size() > 3, "step obstruction did not require a detour")
	_expect(ceiling_detour.path.size() < 2 or ceiling_detour.path[1] != Vector3i(1, FEET_Y + 1, 0), "path stepped directly through insufficient head clearance")

	var invalid_goal_world := _make_flat_world()
	invalid_goal_world.restore_block_edits({Vector3i(2, FEET_Y + 1, 0): BlockId.Type.STONE}, {})
	var invalid_goal := VoxelPathfinder.find_path(invalid_goal_world, Vector3i(0, FEET_Y, 0), Vector3i(2, FEET_Y, 0), BODY_WIDTH, BODY_HEIGHT, 4, 64)
	_expect(invalid_goal.status == VoxelPathResult.Status.INVALID_GOAL, "low-ceiling goal passed body-clearance validation")

	var water_world := _make_flat_world()
	var water_cell := Vector3i(1, FEET_Y, 0)
	water_world.restore_block_edits({water_cell: BlockId.Type.WATER}, {})
	var around_water := VoxelPathfinder.find_path(water_world, Vector3i(0, FEET_Y, 0), Vector3i(2, FEET_Y, 0), BODY_WIDTH, BODY_HEIGHT, 4, 64)
	_expect(around_water.is_success(), "water obstacle prevented a valid dry detour")
	_expect(not around_water.path.has(water_cell), "path entered a water cell")
	var water_goal := VoxelPathfinder.find_path(water_world, Vector3i(0, FEET_Y, 0), water_cell, BODY_WIDTH, BODY_HEIGHT, 4, 64)
	_expect(water_goal.status == VoxelPathResult.Status.INVALID_GOAL, "water goal was accepted as walkable")

func _test_failed_path_repath_throttle() -> void:
	var world := _make_flat_world()
	var blocking_edits: Dictionary = {}
	for direction in VoxelPathfinder.CARDINAL_DIRECTIONS:
		blocking_edits[Vector3i(direction.x, FEET_Y, direction.z)] = BlockId.Type.STONE
		blocking_edits[Vector3i(direction.x, FEET_Y + 1, direction.z)] = BlockId.Type.STONE
	world.restore_block_edits(blocking_edits, {})
	var follower := VoxelPathFollower.new(world, BODY_WIDTH, BODY_HEIGHT, 0.5, EntityNavigationLimits.new(24, 256, 1))
	var search_budget := NavigationSearchBudget.new(1)
	var start := Vector3(0.5, float(FEET_Y), 0.5)
	var goal := Vector3(4.5, float(FEET_Y), 0.5)
	var first := follower.advance(0.0, start, goal, 1.0, true, search_budget)
	_expect(first.path_failed, "unreachable goal did not report its initial failed search")
	var changed_goal := Vector3(-4.5, float(FEET_Y), 0.5)
	search_budget.reset()
	var throttled := follower.advance(0.1, start, changed_goal, 1.0, true, search_budget)
	_expect(not throttled.path_failed, "changed failed goal bypassed the repath interval")
	search_budget.reset()
	var retry := follower.advance(0.4, start, changed_goal, 1.0, true, search_budget)
	_expect(retry.path_failed, "failed path did not retry after the repath interval")

func _test_successful_path_repath_throttle() -> void:
	var world := _make_flat_world()
	var follower := VoxelPathFollower.new(world, BODY_WIDTH, BODY_HEIGHT, 0.5, EntityNavigationLimits.new(24, 256, 1))
	var search_budget := NavigationSearchBudget.new(1)
	var start := Vector3(0.5, float(FEET_Y), 0.5)
	var first := follower.advance(0.0, start, Vector3(4.5, float(FEET_Y), 0.5), 1.0, true, search_budget)
	_expect(first.desired_velocity.x > 0.0, "initial successful path did not lead toward its goal")
	search_budget.reset()
	var throttled := follower.advance(0.1, start, Vector3(-4.5, float(FEET_Y), 0.5), 1.0, true, search_budget)
	_expect(throttled.desired_velocity.x > 0.0, "changed successful goal bypassed the repath interval")
	search_budget.reset()
	var rebuilt := follower.advance(0.4, start, Vector3(-4.5, float(FEET_Y), 0.5), 1.0, true, search_budget)
	_expect(rebuilt.desired_velocity.x < 0.0, "changed successful goal was not applied after the repath interval")

func _test_blocked_motion_keeps_repath_cadence() -> void:
	var world := _make_flat_world()
	world.restore_block_edits({
		Vector3i(1, FEET_Y, 0): BlockId.Type.STONE,
		Vector3i(1, FEET_Y + 1, 0): BlockId.Type.STONE,
	}, {})
	var definition := load("res://entities/definitions/zombie.tres") as EntityDefinition
	var actor := definition.actor_scene.instantiate() as ZombieActor
	get_root().add_child(actor)
	actor.global_position = Vector3(0.5, float(FEET_Y), 0.5)
	actor.setup(20, definition, world, 19, EntityNavigationLimits.new(24, 256, 1))
	actor._path_follower._repath_remaining = 0.3
	actor.advance_voxel_motion(0.5, Vector3(2.0, 0.0, 0.0), actor._behavior.gravity)
	_expect(is_zero_approx(actor.velocity.x), "blocked-motion test did not collide with its wall")
	_expect(is_equal_approx(actor._path_follower._repath_remaining, 0.3), "blocked motion forced an immediate repath")
	actor.free()

func _test_shared_navigation_search_budget() -> void:
	var world := _make_flat_world()
	var start := Vector3(0.5, float(FEET_Y), 0.5)
	var goal := Vector3(4.5, float(FEET_Y), 0.5)
	var first_follower := VoxelPathFollower.new(world, BODY_WIDTH, BODY_HEIGHT, 0.5, EntityNavigationLimits.new(24, 256, 1))
	var second_follower := VoxelPathFollower.new(world, BODY_WIDTH, BODY_HEIGHT, 0.5, EntityNavigationLimits.new(24, 256, 1))
	var search_budget := NavigationSearchBudget.new(1)
	var first := first_follower.advance(0.0, start, goal, 1.0, true, search_budget)
	var deferred := second_follower.advance(0.0, start, goal, 1.0, true, search_budget)
	_expect(not first.desired_velocity.is_zero_approx(), "first due follower did not acquire the shared search budget")
	_expect(deferred.desired_velocity.is_zero_approx() and not deferred.path_failed, "exhausted search budget did not defer the second follower")
	search_budget.reset()
	var second := second_follower.advance(0.0, start, goal, 1.0, true, search_budget)
	_expect(not second.desired_velocity.is_zero_approx(), "deferred follower did not search after the budget reset")

func _test_shared_body_solver() -> void:
	var world := _make_flat_world()
	var start := Vector3(0.5, float(FEET_Y), 0.5)
	_expect(is_equal_approx(VoxelBodySolver.get_ground_y(world, start, BODY_WIDTH), float(FEET_Y)), "solver did not resolve flat ground")
	var free_motion := VoxelBodySolver.sweep(world, start, Vector3(1.0, 0.0, 0.0), Vector3(0.5, 0.0, 0.0), BODY_WIDTH, BODY_HEIGHT)
	_expect(is_equal_approx(free_motion.position.x, 1.0), "solver changed unobstructed horizontal motion")
	_expect(is_equal_approx(free_motion.velocity.x, 1.0), "solver zeroed unobstructed velocity")

	var wall_world := _make_flat_world()
	_set_height(wall_world, 2, 0, FEET_Y + 1)
	var blocked_motion := VoxelBodySolver.sweep(wall_world, start, Vector3(2.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0), BODY_WIDTH, BODY_HEIGHT)
	_expect(blocked_motion.position.x < 1.7, "solver swept through a solid column")
	_expect(is_zero_approx(blocked_motion.velocity.x), "solver retained velocity on a blocked axis")

	var falling_motion := VoxelBodySolver.sweep(world, start + Vector3.UP * 0.2, Vector3(0.0, -1.0, 0.0), Vector3(0.0, -0.3, 0.0), BODY_WIDTH, BODY_HEIGHT)
	_expect(is_equal_approx(falling_motion.position.y, float(FEET_Y)), "solver did not snap a short fall to ground")
	_expect(is_zero_approx(falling_motion.velocity.y), "solver retained downward velocity after landing")

func _make_behavior() -> ZombieBehaviorDefinition:
	var behavior := ZombieBehaviorDefinition.new()
	behavior.wander_speed = 1.0
	behavior.chase_speed = 2.0
	behavior.gravity = 30.0
	behavior.jump_velocity = 7.0
	behavior.detection_range = 10.0
	behavior.forget_range = 15.0
	behavior.target_memory_seconds = 2.0
	var melee_profile := MeleeAttackProfile.new()
	melee_profile.id = &"test_zombie_melee"
	melee_profile.reach = 1.5
	melee_profile.duration = 0.5
	melee_profile.contact_time = 0.25
	melee_profile.cooldown = 1.0
	behavior.melee_profile = melee_profile
	behavior.wander_radius = 4.0
	behavior.wander_goal_seconds = 2.0
	behavior.repath_seconds = 0.5
	return behavior

func _test_zombie_brain_transitions() -> void:
	var behavior := _make_behavior()
	_expect(behavior.validate("test"), "valid zombie behavior definition was rejected")
	var self_position := Vector3.ZERO
	var first := ZombieBrain.new(behavior, 1337)
	var second := ZombieBrain.new(behavior, 1337)
	first.advance(0.1, self_position, Vector3(20.0, 0.0, 0.0), false)
	second.advance(0.1, self_position, Vector3(20.0, 0.0, 0.0), false)
	_expect(first.state == ZombieBrain.State.WANDER, "unaware zombie did not wander")
	_expect(first.get_movement_goal() == second.get_movement_goal(), "wander goal was not deterministic for its seed")

	var seen_position := Vector3(5.0, 0.0, 0.0)
	first.advance(0.1, self_position, seen_position, true)
	_expect(first.state == ZombieBrain.State.CHASE, "visible target inside detection range was not chased")
	_expect(first.get_movement_goal() == seen_position, "chase goal did not use the last seen position")
	first.advance(1.0, self_position, Vector3(6.0, 0.0, 0.0), false)
	_expect(first.state == ZombieBrain.State.CHASE, "zombie forgot its target before memory elapsed")
	_expect(first.get_movement_goal() == seen_position, "hidden target changed the remembered chase goal")
	first.advance(1.1, self_position, Vector3(6.0, 0.0, 0.0), false)
	_expect(first.state == ZombieBrain.State.WANDER, "zombie did not return to wander after memory elapsed")

	var attacker := ZombieBrain.new(behavior, 7)
	var attack_target := Vector3(1.0, 0.0, 0.0)
	attacker.advance(0.1, self_position, attack_target, true)
	_expect(attacker.state == ZombieBrain.State.ATTACK, "target inside attack range did not start an attack")
	_expect(attacker.consume_attack_started(), "attack start was not exposed once")
	_expect(not attacker.consume_attack_started(), "attack start was exposed more than once")
	attacker.advance(0.25, self_position, attack_target, true)
	_expect(attacker.state == ZombieBrain.State.ATTACK, "attack ended before its duration")
	attacker.advance(0.3, self_position, attack_target, true)
	_expect(attacker.state == ZombieBrain.State.ATTACK, "attack state was not retained on its completion tick")
	attacker.advance(0.01, self_position, attack_target, true)
	_expect(attacker.state == ZombieBrain.State.CHASE, "attack cooldown did not suppress an immediate repeat")
	attacker.advance(0.5, self_position, attack_target, true)
	_expect(attacker.state == ZombieBrain.State.ATTACK and attacker.consume_attack_started(), "attack did not restart after cooldown")

func _test_zombie_visibility_cadence() -> void:
	var world := _make_flat_world()
	var definition := load("res://entities/definitions/zombie.tres") as EntityDefinition
	var first := definition.actor_scene.instantiate() as ZombieActor
	var second := definition.actor_scene.instantiate() as ZombieActor
	get_root().add_child(first)
	get_root().add_child(second)
	first.global_position = Vector3(0.5, float(FEET_Y), 0.5)
	second.global_position = Vector3(0.5, float(FEET_Y), 1.5)
	first.setup(1, definition, world, 31, EntityNavigationLimits.new(24, 256, 1))
	second.setup(2, definition, world, 32, EntityNavigationLimits.new(24, 256, 1))
	_expect(not is_equal_approx(first._vision_sample_remaining, second._vision_sample_remaining), "zombie visibility samples were not phase-staggered")
	var target := Vector3(4.5, float(FEET_Y), 0.5)
	first._vision_sample_remaining = 0.0
	_expect(first._sample_player_visibility(0.0, target), "clear target was not visible on the sample tick")
	world.restore_block_edits({Vector3i(2, FEET_Y + 1, 0): BlockId.Type.STONE}, {})
	var half_interval := ZombieActor.VISION_SAMPLE_INTERVAL_SECONDS * 0.5
	_expect(first._sample_player_visibility(half_interval, target), "visibility cache changed before the next sample")
	_expect(not first._sample_player_visibility(half_interval, target), "occlusion was not observed on the next sample")
	first._player_visible = true
	first._vision_sample_remaining = ZombieActor.VISION_SAMPLE_INTERVAL_SECONDS
	var outside_detection := first.global_position + Vector3(first._behavior.detection_range + 1.0, 0.0, 0.0)
	_expect(not first._sample_player_visibility(0.0, outside_detection), "target outside detection range retained cached visibility")
	first.free()
	second.free()

func _test_zombie_actor_movement_and_animation() -> void:
	var world := _make_flat_world()
	var definition := load("res://entities/definitions/zombie.tres") as EntityDefinition
	var actor := definition.actor_scene.instantiate() as ZombieActor
	get_root().add_child(actor)
	actor.global_position = Vector3(0.5, float(FEET_Y), 0.5)
	actor.setup(1, definition, world, 99, EntityNavigationLimits.new(24, 256, 1))
	var target := Vector3(4.5, float(FEET_Y), 0.5)
	var initial_distance := actor.global_position.distance_to(target)
	var search_budget := NavigationSearchBudget.new(1)
	for _step in range(5):
		search_budget.reset()
		actor.tick(0.1, target, Vector3.ZERO, search_budget)
	actor.animation_driver.advance(0.1)
	_expect(actor.brain.state == ZombieBrain.State.CHASE, "zombie actor did not enter chase")
	_expect(actor.global_position.distance_to(target) < initial_distance, "zombie actor did not move toward its target")
	_expect((actor.animation_driver as ZombieAnimationDriver).get_current_state() == ZombieAnimationDriver.CHASE, "custom zombie animation did not enter chase")

	actor.global_position = target - Vector3(1.0, 0.0, 0.0)
	actor.velocity = Vector3.ZERO
	search_budget.reset()
	actor.tick(0.01, target, Vector3.ZERO, search_budget)
	actor.animation_driver.advance(0.0)
	_expect(actor.brain.state == ZombieBrain.State.ATTACK, "zombie actor did not enter attack at melee range")
	var animation := actor.animation_driver as ZombieAnimationDriver
	_expect(animation.get_current_state() == ZombieAnimationDriver.ATTACK, "custom zombie animation did not enter attack")
	animation.play_hit(Vector3.RIGHT)
	animation.advance(ZombieAnimationDriver.HIT_SECONDS * 0.5)
	_expect((animation.animator.position - animation._visual_origin_position).dot(Vector3.RIGHT) > 0.0, "zombie recoil moved toward the attacker")
	actor.free()

func _run() -> void:
	_test_deterministic_bounded_pathfinding()
	_test_elevation_clearance_and_water()
	_test_failed_path_repath_throttle()
	_test_successful_path_repath_throttle()
	_test_blocked_motion_keeps_repath_cadence()
	_test_shared_navigation_search_budget()
	_test_shared_body_solver()
	_test_zombie_brain_transitions()
	_test_zombie_visibility_cadence()
	_test_zombie_actor_movement_and_animation()
	if _failures == 0:
		print("ENTITY_NAVIGATION_INTEGRATION PASS")
		quit(0)
	else:
		print("ENTITY_NAVIGATION_INTEGRATION FAIL failures=%d" % _failures)
		quit(1)
