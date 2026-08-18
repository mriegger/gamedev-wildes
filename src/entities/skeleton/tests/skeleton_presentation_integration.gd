extends SceneTree

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[skeleton_presentation_integration] FAIL: %s" % message)

func _test_rig(animator: BlockyHumanoidAnimator, driver: SkeletonAnimationDriver) -> void:
	_expect(driver.jaw_pivot.get_node_or_null(^"Jaw") is MeshInstance3D, "articulated jaw mesh was missing")
	_expect(driver.left_forearm_pivot.get_node_or_null(^"Forearm") is MeshInstance3D, "left articulated forearm was missing")
	_expect(driver.left_forearm_pivot.get_node_or_null(^"Hand") is MeshInstance3D, "left hand did not follow its forearm")
	_expect(driver.right_forearm_pivot.get_node_or_null(^"Forearm") is MeshInstance3D, "right articulated forearm was missing")
	_expect(driver.right_forearm_pivot.get_node_or_null(^"Hand") is MeshInstance3D, "right hand did not follow its forearm")
	for leg_base in [animator.left_leg_base, animator.right_leg_base]:
		_expect(leg_base.get_node_or_null(^"UpperLeg") is MeshInstance3D, "upper leg bone was missing")
		_expect(leg_base.get_node_or_null(^"Knee") is MeshInstance3D, "knee joint was missing")
		_expect(leg_base.get_node_or_null(^"LowerLeg") is MeshInstance3D, "lower leg bone was missing")

func _expect_articulated_origins(driver: SkeletonAnimationDriver, context: String) -> void:
	_expect(driver.jaw_pivot.rotation.is_equal_approx(driver._jaw_origin_rotation), "%s retained jaw pose" % context)
	_expect(driver.left_forearm_pivot.rotation.is_equal_approx(driver._left_forearm_origin_rotation), "%s retained left forearm pose" % context)
	_expect(driver.right_forearm_pivot.rotation.is_equal_approx(driver._right_forearm_origin_rotation), "%s retained right forearm pose" % context)

func _test_states(actor: SkeletonActor, driver: SkeletonAnimationDriver, melee_profile: MeleeAttackProfile) -> void:
	var animator := driver.animator
	driver.advance(0.0)
	_expect(driver.get_current_state() == SkeletonAnimationDriver.IDLE, "stationary Skeleton did not begin idle")

	actor.max_speed = 2.4
	actor.velocity = Vector3(0.0, 0.0, 2.4)
	driver.advance(animator.profile.walk_cycle_seconds * 0.2)
	_expect(driver.get_current_state() == SkeletonAnimationDriver.WALK, "roaming Skeleton did not select its walk state")
	_expect(not animator.left_leg_locomotion.position.is_equal_approx(animator._left_leg_origin), "walk gait left its articulated legs stationary")

	actor.max_speed = 5.5
	actor.velocity = Vector3(0.0, 0.0, 5.5)
	driver.set_sprinting(true)
	driver.advance(animator.profile.sprint_cycle_seconds * 0.2)
	_expect(driver.get_current_state() == SkeletonAnimationDriver.SPRINT, "fast Skeleton did not select its sprint state")
	_expect(driver.left_forearm_pivot.rotation.x > deg_to_rad(20.0), "sprint did not flex the left forearm")
	_expect(driver.right_forearm_pivot.rotation.x > deg_to_rad(20.0), "sprint did not flex the right forearm")

	actor.velocity = Vector3.ZERO
	driver.set_sprinting(false)
	driver.advance(0.0)
	_expect_articulated_origins(driver, "sprint exit")
	driver.set_hiding(true)
	driver.advance(0.05)
	_expect(driver.get_current_state() == SkeletonAnimationDriver.HIDE, "hidden Skeleton did not select its hide state")
	_expect(driver.animator.position.y < driver._visual_origin_position.y - 0.1, "hide pose did not lower the silhouette")
	_expect(driver.left_forearm_pivot.rotation.x > deg_to_rad(50.0), "hide pose did not fold the left arm")
	_expect(driver.right_forearm_pivot.rotation.x > deg_to_rad(50.0), "hide pose did not fold the right arm")
	driver.set_hiding(false)
	driver.advance(0.0)
	_expect_articulated_origins(driver, "hide exit")

	actor.play_attack(melee_profile.duration)
	driver.advance(melee_profile.duration * 0.5)
	_expect(driver.get_current_state() == SkeletonAnimationDriver.ATTACK, "melee swing did not select its attack state")
	_expect(driver.jaw_pivot.rotation.x > deg_to_rad(8.0), "attack did not articulate the jaw")
	_expect(driver.left_forearm_pivot.rotation.x > deg_to_rad(45.0), "attack did not articulate the lead forearm")
	driver.advance(melee_profile.duration)
	_expect_articulated_origins(driver, "attack exit")

	actor.play_hit(Vector3.RIGHT)
	driver.advance(SkeletonAnimationDriver.HIT_SECONDS * 0.5)
	_expect(driver.get_current_state() == SkeletonAnimationDriver.HIT, "damage did not select the hit state")
	_expect(driver.jaw_pivot.rotation.x > deg_to_rad(18.0), "hit reaction did not open the jaw")
	_expect(not driver._attacking and not driver.animator._attacking, "hit reaction retained the interrupted attack")
	driver.advance(SkeletonAnimationDriver.HIT_SECONDS)
	_expect_articulated_origins(driver, "hit exit")

	actor.begin_death_retirement()
	_expect(driver.get_current_state() == SkeletonAnimationDriver.DEATH, "lethal retirement did not select the death state")
	driver.advance(SkeletonAnimationDriver.DEATH_SECONDS * 0.25)
	var death_elapsed := driver._death_elapsed
	var death_rotation := driver.animator.rotation
	var death_jaw_rotation := driver.jaw_pivot.rotation
	actor.begin_death_retirement()
	_expect(is_equal_approx(driver._death_elapsed, death_elapsed), "repeated death reset elapsed progress")
	_expect(driver.animator.rotation.is_equal_approx(death_rotation), "repeated death reset the fall pose")
	_expect(driver.jaw_pivot.rotation.is_equal_approx(death_jaw_rotation), "repeated death reset the jaw pose")
	driver.advance(SkeletonAnimationDriver.DEATH_SECONDS * 0.25)
	_expect(driver.jaw_pivot.rotation.x > deg_to_rad(20.0), "death pose did not release the jaw")
	_expect(absf(driver.animator.left_arm_action.rotation.z) > deg_to_rad(60.0), "death pose did not splay the left arm")
	_expect(absf(driver.animator.right_arm_action.rotation.z) > deg_to_rad(60.0), "death pose did not splay the right arm")

func _run() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(8, 16, 3, 4.0, block_catalog)
	var entity_catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	var definition := entity_catalog.get_definition(&"skeleton")
	var actor := definition.actor_scene.instantiate() as SkeletonActor
	_expect(actor.vocalizations_path.is_empty(), "Skeleton scene unexpectedly wired audio")
	get_root().add_child(actor)
	actor.setup(41, definition, world, 4101, EntityNavigationLimits.new(32, 512, 2))
	_expect(actor.vocalizations == null, "Skeleton setup unexpectedly created audio")
	var driver := actor.animation_driver as SkeletonAnimationDriver
	_expect(driver != null, "production Skeleton animation driver was missing")
	_test_rig(driver.animator, driver)
	_test_states(actor, driver, (definition.behavior as SkeletonBehaviorDefinition).melee_profile)
	actor.queue_free()
	for _frame_index in range(10):
		await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "Skeleton presentation test ended with %d orphan nodes" % orphan_count)
	if _failures == 0:
		print("SKELETON_PRESENTATION PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("SKELETON_PRESENTATION FAIL failures=%d" % _failures)
		quit(1)
