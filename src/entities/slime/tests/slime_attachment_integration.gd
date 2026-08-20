extends SceneTree

const FLOOR_Y: int = 1
const FEET_Y: float = 2.0
const TEST_RADIUS: int = 24
const PLAYER_POSITION: Vector3 = Vector3(10.0, FEET_Y, 10.0)

var _failures: int = 0
var _outcomes: Array[MeleeOutcome] = []

func _init() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[slime_attachment_integration] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-TEST_RADIUS, TEST_RADIUS + 1):
		for z in range(-TEST_RADIUS, TEST_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLOOR_Y
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.STONE
	return world

func _make_observation(player_position: Vector3) -> EntityTargetObservation:
	return EntityTargetObservation.create(
		player_position,
		player_position + Vector3(0.0, 6.0, 6.0),
		Vector3(0.0, -1.0, -1.0),
		Vector3.RIGHT,
	)

func _on_melee_outcome(outcome: MeleeOutcome) -> void:
	_outcomes.append(outcome)

func _expect_multiplier(player_stats: ActorStats, expected: float, context: String) -> void:
	_expect(
		is_equal_approx(player_stats.get_value(&"movement_speed_multiplier"), expected),
		"%s movement multiplier was %s instead of %s" % [
			context,
			player_stats.get_value(&"movement_speed_multiplier"),
			expected,
		],
	)

func _run() -> void:
	var catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	var world := _make_world()
	var runtime := EntityRuntime.new()
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as PlayerMotor
	var coordinator := SlimeAttachmentCoordinator.new()
	var combat := MeleeCombatCoordinator.new()
	root.add_child(runtime)
	root.add_child(player)
	root.add_child(coordinator)
	root.add_child(combat)
	player.global_position = PLAYER_POSITION
	player.set_physics_process(false)
	player.interactor.set_physics_process(false)
	player.animation_driver.set_process(false)
	var player_stats := ActorStats.new(load("res://player/player_stats.tres") as PlayerStatsDefinition)
	_expect(player_stats.set_base_value(&"defense", 3.0), "player defense fixture setup failed")
	player.stats = player_stats
	player.voxel_space = world
	var input_buffer := InputBuffer.new()
	player._input_buffer = input_buffer
	runtime.setup(catalog, world, 32, 16, EntityNavigationLimits.new(48, 2048, 2))
	var defeat_count := [0]
	runtime.entity_defeated.connect(func(_defeat: EntityDefeat) -> void: defeat_count[0] += 1)
	coordinator.setup(player, player_stats)
	coordinator.bind_runtime(runtime)
	coordinator.set_physics_process(false)
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	_expect(inventory.setup_starter(), "combat inventory fixture setup failed")
	combat.setup(world, player, player_stats, inventory, runtime)
	runtime.entity_melee_contact_reached.connect(combat.try_commit_entity_contact)
	combat.melee_outcome_committed.connect(_on_melee_outcome)

	var runtime_ids := runtime.try_spawn_batch([
		EntitySpawnRequest.new(&"slime_large", Vector3(-12.5, FEET_Y, -12.5), 1001),
		EntitySpawnRequest.new(&"slime_medium", Vector3(-8.5, FEET_Y, -12.5), 2002),
		EntitySpawnRequest.new(&"slime_medium", Vector3(-4.5, FEET_Y, -12.5), 3003),
		EntitySpawnRequest.new(&"slime_small", Vector3(-0.5, FEET_Y, -12.5), 4004),
	])
	_expect(runtime_ids == [1, 2, 3, 4], "mixed slime fixture did not receive stable runtime IDs")
	if runtime_ids.size() != 4:
		await _cleanup(combat, coordinator, runtime, player)
		_finish()
		return
	var hp_before := player_stats.current_hp
	for runtime_id in runtime_ids:
		_expect(runtime.try_relocate_actor(runtime_id, PLAYER_POSITION), "slime %d could not be overlapped with the player" % runtime_id)
	coordinator._physics_process(0.0)
	_expect(coordinator.get_attached_count() == 4, "overlap did not fill all four attachment slots")
	_expect(_outcomes.size() == 4, "initial attachment committed %d contacts instead of four" % _outcomes.size())
	_expect(is_equal_approx(player_stats.current_hp, hp_before - 8.0), "initial attachment damage left %s HP instead of %s" % [player_stats.current_hp, hp_before - 8.0])
	for slot_index in runtime_ids.size():
		var runtime_id := runtime_ids[slot_index]
		var actor := runtime.get_actor(runtime_id) as SlimeActor
		var anchor_position := player.get_slime_attachment_anchor_position(slot_index)
		_expect(actor != null and actor.is_attached(), "slime %d was not attached" % runtime_id)
		if actor == null:
			continue
		_expect(actor.global_position.is_equal_approx(anchor_position), "slime %d was not assigned to authored anchor %d" % [runtime_id, slot_index])
		var probe := AABB(anchor_position - Vector3.ONE * 0.01, Vector3.ONE * 0.02)
		_expect(runtime.get_active_runtime_ids_overlapping(probe).has(runtime_id), "slime %d relocation was missing from the spatial index" % runtime_id)
	_expect_multiplier(player_stats, 0.4, "four-slime capped")

	var hammer_profile := load("res://combat/profiles/copper_hammer_melee.tres") as MeleeAttackProfile
	var player_center := player.get_world_bounds().get_center()
	var ray_origin := player_center + Vector3(0.0, 6.0, 6.0)
	var ray_direction := (player_center - ray_origin).normalized()
	var attached_targets := combat.acquire_player_targets(ray_origin, ray_direction, hammer_profile)
	for runtime_id in runtime_ids:
		_expect(attached_targets.has(runtime_id), "attached slime %d was not melee-targetable" % runtime_id)

	var observation := _make_observation(player.global_position)
	runtime.tick(0.375, observation)
	_expect(_outcomes.size() == 4, "attached slime repeated damage before 0.5 seconds")
	_expect(is_equal_approx(player_stats.current_hp, hp_before - 8.0), "pre-cadence attachment tick changed player HP")
	runtime.tick(0.125, observation)
	_expect(_outcomes.size() == 8, "first attachment repeat committed %d total contacts instead of eight" % _outcomes.size())
	_expect(is_equal_approx(player_stats.current_hp, hp_before - 16.0), "attachment repeat damage left %s HP instead of %s" % [player_stats.current_hp, hp_before - 16.0])

	player.on_ground = false
	player.velocity = Vector3.ZERO
	input_buffer.jump_just = true
	player._handle_movement(0.01)
	_expect(coordinator.get_attached_count() == 4, "failed airborne jump detached a slime")
	_expect((runtime.get_actor(1) as SlimeActor).is_attached(), "failed airborne jump detached the highest-priority slime")
	_expect_multiplier(player_stats, 0.4, "failed airborne jump")

	player.global_position = PLAYER_POSITION
	player.velocity = Vector3.ZERO
	player.on_ground = true
	input_buffer.jump_just = true
	player._handle_movement(player.jump_windup_seconds)
	player._handle_movement(0.0)
	var large := runtime.get_actor(1) as SlimeActor
	_expect(coordinator.get_attached_count() == 3, "successful jump did not detach exactly one slime")
	_expect(not coordinator.is_attached(1) and large != null and not large.is_attached(), "successful jump did not prioritize the large slime")
	if large != null:
		_expect(is_equal_approx(large.knockback_velocity.length(), 5.0), "jump detach did not apply 5.0 knockback")
		_expect(not large.can_attach(), "jump-detached slime skipped its reattachment cooldown")
	_expect_multiplier(player_stats, 0.4, "post-large detach cap")

	observation = _make_observation(player.global_position)
	runtime.tick(3.99, observation)
	_expect(large != null and not large.can_attach(), "jump-detached slime cooldown ended before four seconds")
	runtime.tick(0.01, observation)
	_expect(large != null and large.can_attach(), "jump-detached slime cooldown did not end at four seconds")

	player.jump_committed.emit()
	var oldest_medium := runtime.get_actor(2) as SlimeActor
	var newer_medium := runtime.get_actor(3) as SlimeActor
	_expect(coordinator.get_attached_count() == 2, "second jump did not detach exactly one slime")
	_expect(oldest_medium != null and not oldest_medium.is_attached(), "equal-slow jump priority did not detach the oldest medium slime")
	_expect(newer_medium != null and newer_medium.is_attached(), "equal-slow jump priority detached the newer medium slime")
	if oldest_medium != null:
		_expect(is_equal_approx(oldest_medium.knockback_velocity.length(), 5.0), "oldest-medium detach did not apply 5.0 knockback")
	_expect_multiplier(player_stats, 0.6, "priority medium detach")

	var attached_parent_position := newer_medium.global_position
	var active_ids_before_split: Dictionary = {}
	for actor in runtime.get_active_actors():
		active_ids_before_split[actor.runtime_id] = true
	var split_result := runtime.try_apply_damage(newer_medium.runtime_id, 1000.0)
	_expect(split_result != null and split_result.defeated, "lethal attached-medium damage did not commit")
	_expect(runtime.get_actor(newer_medium.runtime_id) == null, "attached split parent remained active")
	_expect(not coordinator.is_attached(newer_medium.runtime_id), "attached split parent remained registered")
	_expect(coordinator.get_attached_count() == 1, "attached parent split changed unrelated attachment ownership")
	_expect(defeat_count[0] == 1, "attached parent defeat did not emit exactly one normal defeat")
	_expect_multiplier(player_stats, 0.85, "attached parent defeat")
	var split_children: Array[SlimeActor] = []
	for actor in runtime.get_active_actors():
		if not active_ids_before_split.has(actor.runtime_id):
			split_children.append(actor as SlimeActor)
	split_children.sort_custom(func(left: SlimeActor, right: SlimeActor) -> bool: return left.runtime_id < right.runtime_id)
	_expect(split_children.size() >= 2 and split_children.size() <= 4, "attached medium did not split into two to four children")
	for child in split_children:
		_expect(child.definition.id == &"slime_small", "attached medium produced a non-small child")
		var outward_direction := child.global_position - attached_parent_position
		outward_direction.y = 0.0
		_expect(not outward_direction.is_zero_approx(), "attached split child remained at the parent anchor")
		_expect(not child.on_ground and is_equal_approx(child.velocity.y, 7.0), "attached split child did not begin an airborne 7.0 launch")
		_expect(not child.can_attach(), "attached split child could attach during its controlled launch")
		_expect(not VoxelBodySolver.collides_at(world, child.global_position, child.definition.body_width, child.definition.body_height, false), "attached split child was placed in a voxel collision")
		_expect(not child.is_attached() and child.definition.combat_targetable, "attached split child inherited attachment or lost targetability")
		_expect(runtime.get_active_runtime_ids_overlapping(child.get_world_bounds()).has(child.runtime_id), "attached split child was missing from the spatial index")
		var planar_launch := Vector3(child.knockback_velocity.x, 0.0, child.knockback_velocity.z)
		_expect(is_zero_approx(child.knockback_velocity.y) and is_equal_approx(planar_launch.length(), 2.5), "attached split child received the wrong planar launch speed")
		if not outward_direction.is_zero_approx():
			_expect(planar_launch.normalized().is_equal_approx(outward_direction.normalized()), "attached split child launch did not point away from the parent anchor")
		var child_hp := runtime.get_current_hp(child.runtime_id)
		_expect(runtime.try_apply_damage(child.runtime_id, 1.0) == null, "attached split child accepted damage during spawn immunity")
		_expect(is_equal_approx(runtime.get_current_hp(child.runtime_id), child_hp), "attached split child spawn immunity changed HP")
	for left_index in split_children.size():
		for right_index in range(left_index + 1, split_children.size()):
			_expect(not split_children[left_index].get_world_bounds().intersects(split_children[right_index].get_world_bounds()), "attached split children %d and %d overlap" % [left_index, right_index])
	runtime.tick(0.125, observation)
	for child in split_children:
		_expect(not child.on_ground and not child.can_attach(), "attached split child left controlled launch before the immunity midpoint")
		_expect(not VoxelBodySolver.collides_at(world, child.global_position, child.definition.body_width, child.definition.body_height, false), "attached split child entered a voxel during controlled launch")
		var midpoint_hp := runtime.get_current_hp(child.runtime_id)
		_expect(runtime.try_apply_damage(child.runtime_id, 1.0) == null, "attached split child lost damage immunity during controlled launch")
		_expect(is_equal_approx(runtime.get_current_hp(child.runtime_id), midpoint_hp), "controlled-launch immunity changed attached split child HP")
	var split_children_landed := false
	for _launch_step in 120:
		runtime.tick(1.0 / 60.0, observation)
		split_children_landed = true
		for child in split_children:
			_expect(not VoxelBodySolver.collides_at(world, child.global_position, child.definition.body_width, child.definition.body_height, false), "attached split child entered a voxel before landing")
			if not child.on_ground:
				split_children_landed = false
				_expect(not child.can_attach(), "attached split child became attachable before landing")
		if split_children_landed:
			break
	_expect(split_children_landed, "attached split children did not land after controlled launch")
	for child in split_children:
		_expect(child.on_ground and child.can_attach(), "attached split child did not become attachable after landing")

	var remaining_small := runtime.get_actor(4) as SlimeActor
	var active_before_clear := runtime.get_active_count()
	coordinator.clear_attachments()
	_expect(coordinator.get_attached_count() == 0, "defeat-style clear retained an attachment")
	_expect(remaining_small != null and not remaining_small.is_attached(), "defeat-style clear did not detach the remaining slime")
	_expect(runtime.get_active_count() == active_before_clear and defeat_count[0] == 1, "defeat-style clear removed or defeated a slime")
	_expect_multiplier(player_stats, 1.0, "defeat-style clear")
	var offset := 0
	for actor in runtime.get_active_actors():
		runtime.try_relocate_actor(actor.runtime_id, Vector3(-18.0 + float(offset) * 2.0, FEET_Y, -18.0))
		offset += 1
	var despawn_target := split_children[0]
	_expect(runtime.try_relocate_actor(despawn_target.runtime_id, player.global_position), "despawn target could not be overlapped")
	coordinator._physics_process(0.0)
	_expect(coordinator.get_attached_count() == 1 and despawn_target.is_attached(), "despawn target did not attach")
	_expect(runtime.try_despawn(despawn_target.runtime_id), "attached despawn target was not removed")
	coordinator._physics_process(0.0)
	_expect(coordinator.get_attached_count() == 0 and defeat_count[0] == 1, "attached despawn retained ownership or emitted defeat")
	_expect_multiplier(player_stats, 1.0, "attached despawn")
	var unbind_target := split_children[1]
	_expect(runtime.try_relocate_actor(unbind_target.runtime_id, player.global_position), "unbind target could not be overlapped")
	coordinator._physics_process(0.0)
	_expect(coordinator.get_attached_count() == 1 and unbind_target.is_attached(), "unbind target did not attach")
	coordinator.unbind_runtime()
	_expect(coordinator.get_attached_count() == 0, "runtime unbind retained an attachment")
	_expect(not unbind_target.is_attached(), "runtime unbind did not detach its slime")
	_expect_multiplier(player_stats, 1.0, "runtime unbind")

	coordinator.bind_runtime(runtime)
	runtime.tick(4.0, observation)
	if unbind_target != null:
		var suspension_id := unbind_target.runtime_id
		var suspension_target := unbind_target
		_expect(runtime.try_relocate_actor(suspension_id, player.global_position), "suspension target could not be overlapped")
		coordinator._physics_process(0.0)
		_expect(coordinator.is_attached(suspension_id) and suspension_target.is_attached(), "suspension target did not attach")
		_expect_multiplier(player_stats, 0.85, "pre-suspension")
		runtime.suspend()
		coordinator._physics_process(0.0)
		player.jump_committed.emit()
		_expect(coordinator.is_attached(suspension_id), "runtime suspension erased coordinator attachment ownership")
		_expect(suspension_target.is_attached(), "runtime suspension detached only the actor state")
		_expect_multiplier(player_stats, 0.85, "suspended runtime")
		runtime.resume()
		coordinator._physics_process(0.0)
		_expect(coordinator.is_attached(suspension_id) and suspension_target.is_attached(), "runtime resume did not preserve attachment ownership")
		runtime.suspend()
		coordinator.unbind_runtime()
		_expect(not suspension_target.is_attached(), "suspended runtime unbind left the actor attached")
		_expect_multiplier(player_stats, 1.0, "suspended runtime unbind")
		runtime.resume()
		coordinator.bind_runtime(runtime)
		runtime.tick(4.0, observation)
		var immediate_defeat_count: Array[int] = [0]
		var immediate_defeat_callback := func() -> void:
			immediate_defeat_count[0] += 1
			coordinator.clear_attachments()
			player.enter_defeated_state()
		player_stats.health_depleted.connect(immediate_defeat_callback)
		var outcomes_before_lethal_attachment := _outcomes.size()
		_expect(player_stats.set_current_hp(1.0), "lethal attachment fixture could not set player HP")
		_expect(runtime.try_relocate_actor(suspension_id, player.global_position), "defeated-player target could not be overlapped")
		coordinator._physics_process(0.0)
		_expect(immediate_defeat_count[0] == 1 and player_stats.is_dead() and player.is_defeated(), "initial attachment contact did not defeat the one-HP player")
		_expect(_outcomes.size() == outcomes_before_lethal_attachment + 1 and _outcomes.back().target_defeated, "lethal initial attachment contact did not commit exactly one outcome")
		_expect(coordinator.get_attached_count() == 0 and not suspension_target.is_attached(), "lethal initial attachment retained attachment ownership")
		_expect_multiplier(player_stats, 1.0, "lethal initial attachment")
		runtime.tick(4.0, observation)
		_expect(runtime.try_relocate_actor(suspension_id, player.global_position), "defeated-player target could not be returned to overlap")
		coordinator._physics_process(0.0)
		_expect(coordinator.get_attached_count() == 0 and not suspension_target.is_attached(), "defeated player reacquired an overlapping slime")
		_expect(_outcomes.size() == outcomes_before_lethal_attachment + 1, "defeated-player overlap emitted another attachment contact")
		_expect_multiplier(player_stats, 1.0, "defeated player")
		player_stats.health_depleted.disconnect(immediate_defeat_callback)

	await _cleanup(combat, coordinator, runtime, player)
	_finish()

func _cleanup(
	combat: MeleeCombatCoordinator,
	coordinator: SlimeAttachmentCoordinator,
	runtime: EntityRuntime,
	player: PlayerMotor,
) -> void:
	combat.shutdown()
	coordinator.unbind_runtime()
	runtime.shutdown()
	for node in [combat, coordinator, runtime, player]:
		if is_instance_valid(node):
			node.queue_free()
	await process_frame
	await process_frame

func _finish() -> void:
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "attachment integration left %d orphan nodes" % orphan_count)
	if _failures == 0:
		print("SLIME_ATTACHMENT_INTEGRATION PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("SLIME_ATTACHMENT_INTEGRATION FAIL failures=%d" % _failures)
		quit(1)
