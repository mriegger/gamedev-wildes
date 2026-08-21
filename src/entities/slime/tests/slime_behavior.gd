extends SceneTree

const FLOOR_Y: int = 1
const FEET_Y: float = 2.0
const TEST_RADIUS: int = 12

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[slime_behavior] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-TEST_RADIUS, TEST_RADIUS + 1):
		for z in range(-TEST_RADIUS, TEST_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLOOR_Y
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.STONE
	return world

func _test_definition_content() -> void:
	var large := load("res://entities/definitions/slime_large.tres") as EntityDefinition
	var medium := load("res://entities/definitions/slime_medium.tres") as EntityDefinition
	var small := load("res://entities/definitions/slime_small.tres") as EntityDefinition
	_expect(large != null and medium != null and small != null, "slime definitions did not load")
	if large == null or medium == null or small == null:
		return
	_expect(large.id == &"slime_large" and medium.id == &"slime_medium" and small.id == &"slime_small", "stable slime IDs changed")
	_expect(is_equal_approx(large.body_width, 1.4) and is_equal_approx(large.body_height, 1.2), "large body dimensions changed")
	_expect(is_equal_approx(medium.body_width, 0.9) and is_equal_approx(medium.body_height, 0.8), "medium body dimensions changed")
	_expect(is_equal_approx(small.body_width, 0.5) and is_equal_approx(small.body_height, 0.45), "small body dimensions changed")
	_expect(large.ambient_spawn_enabled and large.ambient_max_active == 1, "large ambient lineage configuration changed")
	_expect(large.ambient_spawn_phase == EntityDefinition.SpawnPhase.NIGHT, "large slime did not remain night-spawned")
	_expect(large.ambient_spawn_floor_ids == [BlockId.Type.GRASS, BlockId.Type.DIRT, BlockId.Type.SAND, BlockId.Type.STONE], "large slime spawn floors changed")
	_expect(not large.ambient_despawn_outside_spawn_phase, "large slime no longer persists through dawn")
	_expect(not medium.ambient_spawn_enabled and medium.ambient_max_active == 0 and medium.ambient_spawn_floor_ids.is_empty(), "medium became ambient-spawnable")
	_expect(not small.ambient_spawn_enabled and small.ambient_max_active == 0 and small.ambient_spawn_floor_ids.is_empty(), "small became ambient-spawnable")
	_expect(large.defeat_spawn != null and large.defeat_spawn.child_definition_id == &"slime_medium", "large split target changed")
	_expect(medium.defeat_spawn != null and medium.defeat_spawn.child_definition_id == &"slime_small", "medium split target changed")
	_expect(small.defeat_spawn == null, "small slime unexpectedly splits")
	_expect(large.defeat_spawn.minimum_count == 2 and large.defeat_spawn.maximum_count == 4, "large split count changed")
	_expect(medium.defeat_spawn.minimum_count == 2 and medium.defeat_spawn.maximum_count == 4, "medium split count changed")
	_expect(is_equal_approx(large.defeat_spawn.child_spawn_clearance, 0.25) and is_equal_approx(large.defeat_spawn.child_damage_immunity_seconds, 0.25), "large split spawn configuration changed")
	_expect(is_equal_approx(medium.defeat_spawn.child_spawn_clearance, 0.25) and is_equal_approx(medium.defeat_spawn.child_damage_immunity_seconds, 0.25), "medium split spawn configuration changed")
	_expect(is_equal_approx(large.defeat_spawn.child_launch_planar_speed, 2.5) and is_equal_approx(large.defeat_spawn.child_launch_vertical_speed, 7.0), "large split launch configuration changed")
	_expect(is_equal_approx(medium.defeat_spawn.child_launch_planar_speed, 2.5) and is_equal_approx(medium.defeat_spawn.child_launch_vertical_speed, 7.0), "medium split launch configuration changed")
	_expect(large.experience_reward == 10 and medium.experience_reward == 4 and small.experience_reward == 1, "slime experience rewards changed")
	var definitions: Array[EntityDefinition] = [large, medium, small]
	var expected_hp: Array[float] = [240.0, 96.0, 30.0]
	var expected_defense: Array[float] = [4.0, 2.0, 0.0]
	var expected_chase: Array[float] = [2.6, 3.2, 3.8]
	var expected_hops: Array[float] = [0.9, 0.7, 0.5]
	var expected_slow: Array[float] = [0.4, 0.25, 0.15]
	var expected_damage: Array[float] = [8.0, 4.0, 2.0]
	for index in definitions.size():
		var definition := definitions[index]
		var behavior := definition.behavior as SlimeBehaviorDefinition
		_expect(behavior != null and behavior.validate(behavior.resource_path), "%s behavior is invalid" % definition.id)
		_expect(definition.stats_definition != null and definition.stats_definition.validate(), "%s stats are invalid" % definition.id)
		_expect(is_equal_approx(definition.stats_definition.maximum_hp, expected_hp[index]), "%s HP changed" % definition.id)
		_expect(is_equal_approx(definition.stats_definition.defense, expected_defense[index]), "%s defense changed" % definition.id)
		_expect(is_zero_approx(definition.stats_definition.strength), "%s strength is not zero" % definition.id)
		_expect(is_equal_approx(behavior.chase_speed, expected_chase[index]), "%s chase speed changed" % definition.id)
		_expect(is_equal_approx(behavior.gravity, 30.0) and is_equal_approx(behavior.jump_velocity, 7.0), "%s common hop physics changed" % definition.id)
		_expect(is_equal_approx(behavior.detection_range, 16.0) and is_equal_approx(behavior.forget_range, 24.0), "%s perception ranges changed" % definition.id)
		_expect(is_equal_approx(behavior.hop_interval_seconds, expected_hops[index]), "%s hop interval changed" % definition.id)
		_expect(is_equal_approx(behavior.attachment_slow_fraction, expected_slow[index]), "%s slow fraction changed" % definition.id)
		_expect(is_equal_approx(behavior.attachment_damage_profile.cooldown, 0.5), "%s damage interval changed" % definition.id)
		_expect(is_equal_approx(behavior.attachment_damage_profile.base_damage, expected_damage[index]), "%s attachment damage changed" % definition.id)
		_expect(definition.is_actor_compatible(), "%s actor rejected its behavior or presentation" % definition.id)

func _test_invalid_split_graphs() -> void:
	var source_large := load("res://entities/definitions/slime_large.tres") as EntityDefinition
	var source_medium := load("res://entities/definitions/slime_medium.tres") as EntityDefinition
	var source_small := load("res://entities/definitions/slime_small.tres") as EntityDefinition
	var missing_large := source_large.duplicate(true) as EntityDefinition
	missing_large.defeat_spawn = source_large.defeat_spawn.duplicate(true) as EntityDefeatSpawnDefinition
	missing_large.defeat_spawn.child_definition_id = &"missing_slime"
	var missing_candidates: Array[EntityDefinition] = [missing_large, source_medium, source_small]
	var missing_issue := EntityCatalog._get_defeat_spawn_validation_issue(missing_candidates)
	_expect(missing_issue.contains("Missing defeat-spawn child"), "missing split child passed catalog graph validation")
	var cyclic_large := source_large.duplicate(true) as EntityDefinition
	cyclic_large.defeat_spawn = source_large.defeat_spawn.duplicate(true) as EntityDefeatSpawnDefinition
	cyclic_large.defeat_spawn.child_definition_id = cyclic_large.id
	var cycle_candidates: Array[EntityDefinition] = [cyclic_large]
	var cycle_issue := EntityCatalog._get_defeat_spawn_validation_issue(cycle_candidates)
	_expect(cycle_issue.contains("cycle"), "cyclic split graph passed catalog validation")
	var larger_large := source_large.duplicate(true) as EntityDefinition
	var larger_medium := source_medium.duplicate(true) as EntityDefinition
	larger_medium.body_width = larger_large.body_width + 0.1
	var larger_candidates: Array[EntityDefinition] = [larger_large, larger_medium, source_small]
	var larger_issue := EntityCatalog._get_defeat_spawn_validation_issue(larger_candidates)
	_expect(larger_issue.contains("larger"), "larger split child passed catalog validation")
	_expect(EntityDefeatSpawnDefinition._are_child_launch_speeds_valid(0.0, 0.0), "disabled split launch was rejected")
	_expect(EntityDefeatSpawnDefinition._are_child_launch_speeds_valid(2.5, 7.0), "authored split launch was rejected")
	_expect(not EntityDefeatSpawnDefinition._are_child_launch_speeds_valid(-0.1, 7.0), "negative planar split launch was accepted")
	_expect(not EntityDefeatSpawnDefinition._are_child_launch_speeds_valid(2.5, NAN), "non-finite vertical split launch was accepted")
	_expect(not EntityDefeatSpawnDefinition._are_child_launch_speeds_valid(2.5, 0.0), "incomplete split launch was accepted")

func _test_deterministic_brain() -> void:
	var behavior := load("res://entities/slime/slime_medium_behavior.tres") as SlimeBehaviorDefinition
	var first := SlimeBrain.new(behavior, 4419)
	var second := SlimeBrain.new(behavior, 4419)
	var different := SlimeBrain.new(behavior, 4420)
	var origin := Vector3(0.5, FEET_Y, 0.5)
	var distant_player := Vector3(40.5, FEET_Y, 0.5)
	first.advance(0.0, origin, distant_player, false, false, true)
	second.advance(0.0, origin, distant_player, false, false, true)
	different.advance(0.0, origin, distant_player, false, false, true)
	_expect(first.state == SlimeBrain.State.WANDER, "unaware slime did not wander")
	_expect(first.get_movement_goal().is_equal_approx(second.get_movement_goal()), "identical seeds produced different wander goals")
	_expect(not first.get_movement_goal().is_equal_approx(different.get_movement_goal()), "different seeds produced the same wander goal")
	first.advance(behavior.hop_interval_seconds * 0.5, origin, distant_player, false, false, true)
	_expect(not first.consume_hop_started(), "hop started before its configured interval")
	first.advance(behavior.hop_interval_seconds * 0.5 + 0.001, origin, distant_player, false, false, true)
	_expect(first.consume_hop_started(), "grounded slime did not start its due hop")
	var remaining := first._hop_remaining
	first.advance(behavior.hop_interval_seconds * 2.0, origin, distant_player, false, false, false)
	_expect(not first.consume_hop_started(), "airborne slime started another hop")
	_expect(is_equal_approx(first._hop_remaining, remaining), "airborne time consumed the grounded hop interval")
	var nearby_player := Vector3(4.5, FEET_Y, 0.5)
	first.advance(0.0, origin, nearby_player, true, false, true)
	_expect(first.state == SlimeBrain.State.CHASE and first.get_movement_goal() == nearby_player, "visible player did not start a chase")
	first.advance(behavior.target_memory_seconds * 0.5, origin, nearby_player, false, false, true)
	_expect(first.state == SlimeBrain.State.CHASE, "slime forgot the player before memory expired")
	first.advance(0.0, origin, distant_player, false, false, true)
	_expect(first.state == SlimeBrain.State.WANDER, "forget range did not end the chase")
	first.alert_to_player(nearby_player)
	_expect(first.state == SlimeBrain.State.CHASE and first.get_movement_goal() == nearby_player, "player hit did not immediately alert the slime")
	first.advance(0.0, origin, nearby_player, true, true, false)
	_expect(first.state == SlimeBrain.State.ATTACHED and not first.consume_hop_started(), "attached slime retained locomotion")

func _test_squash_and_bounce_animation() -> void:
	var definition := load("res://entities/definitions/slime_small.tres") as EntityDefinition
	var actor := definition.actor_scene.instantiate() as SlimeActor
	get_root().add_child(actor)
	actor.global_position = Vector3(0.5, FEET_Y, 0.5)
	actor.setup(1, definition, _make_world(), 7202, EntityNavigationLimits.new(24, 256, 1))
	actor.set_process(false)
	var driver := actor.animation_driver as SlimeAnimationDriver
	var body_pivot := actor.get_node(^"ModelRoot/SlimeVisual/RigRoot/SizeRoot/BodyPivot") as Node3D
	var original_transform := actor.transform
	var original_bounds := actor.get_world_bounds()

	actor.on_ground = false
	actor.velocity = Vector3.UP * 7.0
	driver.advance(0.0)
	var launch_scale := body_pivot.scale
	_expect(driver.get_current_state() == SlimeAnimationDriver.HOP, "launch did not select the hop animation")
	_expect(launch_scale.y > 1.25 and launch_scale.x < 0.9, "launch did not produce a strong elastic stretch")
	_expect(is_equal_approx(launch_scale.x * launch_scale.y * launch_scale.z, 1.0), "launch deformation changed visual volume")
	_expect(actor.velocity.is_equal_approx(Vector3.UP * 7.0), "launch animation changed gameplay velocity")

	actor.velocity.y = 0.0
	driver.advance(0.0)
	_expect(body_pivot.scale.y < 1.0, "hop apex did not relax into a soft squash")
	actor.velocity.y = -7.0
	driver.advance(0.0)
	var fall_scale := body_pivot.scale
	_expect(fall_scale.y > 1.2 and fall_scale.x < 0.92, "fall did not stretch before impact")
	_expect(is_equal_approx(fall_scale.x * fall_scale.y * fall_scale.z, 1.0), "fall deformation changed visual volume")

	actor.on_ground = true
	actor.velocity.y = 0.0
	driver.advance(0.0)
	var impact_scale := body_pivot.scale
	_expect(driver.get_current_state() == SlimeAnimationDriver.LAND, "ground contact did not select the landing animation")
	_expect(impact_scale.y < 0.7 and impact_scale.x > 1.2, "landing did not produce a strong impact squash")
	_expect(is_equal_approx(impact_scale.x * impact_scale.y * impact_scale.z, 1.0), "landing deformation changed visual volume")
	driver.advance(SlimeAnimationDriver.LAND_SECONDS * 0.4)
	_expect(body_pivot.scale.y > 1.07, "landing squash did not rebound")
	driver.advance(SlimeAnimationDriver.LAND_SECONDS * 0.6)
	_expect(driver.get_current_state() == SlimeAnimationDriver.IDLE, "landing animation did not settle back to idle")

	_expect(actor.attach(0), "animation test slime could not attach")
	driver.advance(0.0)
	_expect(driver.get_current_state() == SlimeAnimationDriver.ATTACHED, "attachment did not select its animation")
	_expect(body_pivot.scale.y < 0.83, "attachment did not begin with an elastic splat")
	_expect(actor.detach(Vector3.RIGHT, 0.0, 0.0), "animation test slime could not detach")
	driver.advance(0.0)
	_expect(driver.get_current_state() == SlimeAnimationDriver.HOP, "detachment created a false landing animation")

	driver.play_hit(Vector3.BACK)
	driver.advance(SlimeAnimationDriver.HIT_SECONDS * 0.25)
	_expect(driver.get_current_state() == SlimeAnimationDriver.HIT, "hit did not override airborne animation")
	_expect(body_pivot.scale.y < 0.85, "hit animation did not squash before rebounding")
	driver.play_death()
	driver.advance(SlimeAnimationDriver.DEATH_SECONDS * SlimeAnimationDriver.DEATH_SQUASH_END_RATIO)
	_expect(driver.get_current_state() == SlimeAnimationDriver.DEATH, "death did not override hit animation")
	_expect(is_equal_approx(body_pivot.scale.y, SlimeAnimationDriver.DEATH_SQUASH_SCALE) and body_pivot.scale.x > 1.3, "death animation did not compress into its opening squash")
	driver.advance(
		SlimeAnimationDriver.DEATH_SECONDS
		* (SlimeAnimationDriver.DEATH_REBOUND_END_RATIO - SlimeAnimationDriver.DEATH_SQUASH_END_RATIO),
	)
	_expect(body_pivot.scale.y >= SlimeAnimationDriver.DEATH_REBOUND_SCALE - 0.001 and body_pivot.scale.x < 0.85, "death animation did not spring into its rebound stretch")
	_expect(body_pivot.position.y >= SlimeAnimationDriver.DEATH_REBOUND_LIFT - 0.001, "death rebound did not lift from the ground")
	driver.advance(driver.get_death_time_remaining())
	_expect(driver.is_death_complete(), "death animation did not complete at its configured duration")
	_expect(body_pivot.scale.is_equal_approx(Vector3.ONE * SlimeAnimationDriver.DEATH_POP_SCALE), "death animation did not contract into its snap-pop")

	_expect(actor.transform.is_equal_approx(original_transform), "slime animation moved the gameplay actor")
	_expect(actor.get_world_bounds() == original_bounds, "slime animation changed gameplay bounds")
	actor.free()

func _test_attachment_api() -> void:
	var definition := load("res://entities/definitions/slime_small.tres") as EntityDefinition
	var actor := definition.actor_scene.instantiate() as SlimeActor
	get_root().add_child(actor)
	actor.global_position = Vector3(0.5, FEET_Y, 0.5)
	actor.setup(1, definition, _make_world(), 7201, EntityNavigationLimits.new(24, 256, 1))
	var size_root := actor.get_node(^"ModelRoot/SlimeVisual/RigRoot/SizeRoot") as Node3D
	_expect(size_root.scale.is_equal_approx(Vector3(0.5, 0.45, 0.5)), "small visual did not derive its scale from body dimensions")
	_expect(actor.can_attach() and not actor.is_attached(), "fresh slime could not attach")
	var contact_count: Array[int] = [0]
	actor.melee_contact_reached.connect(func(_runtime_id: int, _profile: MeleeAttackProfile) -> void: contact_count[0] += 1)
	_expect(actor.attach(2), "valid attachment was rejected")
	_expect(actor.is_attached() and not actor.can_attach(), "attached state was not committed")
	actor.tick_gameplay(0.0, EntityTargetObservation.create(actor.global_position, actor.global_position, Vector3.FORWARD, Vector3.RIGHT), Vector3.ZERO, NavigationSearchBudget.new(1))
	_expect(actor.is_aggroed(), "attached slime did not report aggro")
	_expect(actor.commit_initial_attachment_contact(), "attachment did not commit its initial contact")
	_expect(contact_count[0] == 1, "attachment did not damage immediately")
	_expect(not actor.commit_initial_attachment_contact(), "attachment committed its initial contact twice")
	_expect(not actor.attach(3) and contact_count[0] == 1, "failed duplicate attachment emitted another contact")
	_expect(is_equal_approx(actor.get_attachment_slow_fraction(), 0.15), "small attachment slow changed")
	(actor.animation_driver as SlimeAnimationDriver).advance(0.0)
	_expect((actor.animation_driver as SlimeAnimationDriver).get_current_state() == SlimeAnimationDriver.ATTACHED, "attached presentation state was not selected")
	var observation := EntityTargetObservation.create(actor.global_position, actor.global_position, Vector3.FORWARD, Vector3.RIGHT)
	var budget := NavigationSearchBudget.new(1)
	actor.tick_gameplay(0.49, observation, Vector3.ZERO, budget)
	_expect(contact_count[0] == 1, "attachment repeated damage before its cooldown")
	actor.tick_gameplay(0.01, observation, Vector3.ZERO, budget)
	_expect(contact_count[0] == 2, "attachment did not repeat damage at 0.5 seconds")
	actor.tick_gameplay(0.5, observation, Vector3.ZERO, budget)
	_expect(contact_count[0] == 3, "attachment damage cadence changed")
	_expect(actor.detach(Vector3.RIGHT, 5.0, 0.5), "valid detach was rejected")
	_expect(not actor.is_attached() and not actor.can_attach(), "detach did not start reattachment cooldown")
	_expect(actor.knockback_velocity.is_equal_approx(Vector3.RIGHT * 5.0), "detach did not apply outward knockback")
	actor.tick_gameplay(0.5, observation, Vector3.ZERO, budget)
	_expect(actor.can_attach(), "reattachment cooldown did not expire")
	_expect(actor.attach(1), "reattachment was rejected after cooldown")
	_expect(actor.commit_initial_attachment_contact() and contact_count[0] == 4, "reattachment did not damage immediately")
	actor.tick_gameplay(0.49, observation, Vector3.ZERO, budget)
	_expect(contact_count[0] == 4, "reattachment repeated damage before its cooldown")
	actor.tick_gameplay(0.01, observation, Vector3.ZERO, budget)
	_expect(contact_count[0] == 5, "reattachment did not restart the damage cadence")
	actor.free()

func _run() -> void:
	var orphan_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_test_definition_content()
	_test_invalid_split_graphs()
	_test_deterministic_brain()
	_test_squash_and_bounce_animation()
	_test_attachment_api()
	await process_frame
	await process_frame
	var orphan_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_after == orphan_before, "slime tests changed orphan count from %d to %d" % [orphan_before, orphan_after])
	if _failures == 0:
		print("SLIME_BEHAVIOR PASS orphan=%d" % orphan_after)
		quit(0)
	else:
		print("SLIME_BEHAVIOR FAIL failures=%d" % _failures)
		quit(1)
