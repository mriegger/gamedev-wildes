extends SceneTree

const FLAT_HEIGHT: int = 6
const FEET_Y: float = float(FLAT_HEIGHT + 1)
const TEST_RADIUS: int = 48

const MeleeContactType := preload("res://combat/melee_contact.gd")

var _failures: int = 0
var _contacts: Array[MeleeContactType] = []
var _player_defeat_count: int = 0

func _init() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[entity_combat_integration] FAIL: %s" % message)

func _single_target(runtime_id: int) -> Array[int]:
	return [runtime_id]

func _make_flat_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-TEST_RADIUS, TEST_RADIUS + 1):
		for z in range(-TEST_RADIUS, TEST_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLAT_HEIGHT
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _always_ready(_position: Vector3) -> bool:
	return true

func _make_two_zombie_catalog() -> EntityCatalog:
	var source := load("res://entities/definitions/zombie.tres") as EntityDefinition
	var definition := source.duplicate(true) as EntityDefinition
	definition.max_active = 2
	var definitions: Array[EntityDefinition] = [definition]
	var catalog := EntityCatalog.new()
	catalog.definitions = definitions
	return catalog

func _make_one_sheep_catalog() -> EntityCatalog:
	var source := load("res://entities/definitions/sheep.tres") as EntityDefinition
	var definition := source.duplicate(true) as EntityDefinition
	definition.max_active = 1
	var definitions: Array[EntityDefinition] = [definition]
	var catalog := EntityCatalog.new()
	catalog.definitions = definitions
	return catalog

func _on_melee_contact(contact: MeleeContactType) -> void:
	_contacts.append(contact)

func _on_player_defeated() -> void:
	_player_defeat_count += 1

func _run() -> void:
	var sword_profile := load("res://combat/profiles/copper_sword_melee.tres") as MeleeAttackProfile
	var zombie_profile := load("res://combat/profiles/zombie_melee.tres") as MeleeAttackProfile
	_expect(sword_profile != null and sword_profile.validate(sword_profile.resource_path), "copper sword profile is invalid")
	_expect(zombie_profile != null and zombie_profile.validate(zombie_profile.resource_path), "zombie profile is invalid")
	_expect(sword_profile.id == &"copper_sword_melee", "copper sword attack ID changed")
	_expect(zombie_profile.id == &"zombie_melee", "zombie attack ID changed")
	_expect(is_equal_approx(sword_profile.base_damage, 10.0), "copper sword base damage changed")
	_expect(is_equal_approx(zombie_profile.base_damage, 15.0), "zombie base damage changed")
	_expect(is_equal_approx(sword_profile.sweep_degrees, 120.0), "copper sword sweep changed")
	_expect(is_zero_approx(zombie_profile.sweep_degrees), "zombie attack became a sweep")
	_expect(is_equal_approx(sword_profile.calculate_damage(10.0, 4.0), 16.0), "sword damage formula is incorrect")
	_expect(is_equal_approx(zombie_profile.calculate_damage(5.0, 4.0), 16.0), "zombie damage formula is incorrect")
	_expect(is_equal_approx(sword_profile.calculate_damage(0.0, 100.0), 1.0), "damage did not clamp to its minimum")
	_expect(sword_profile.cooldown >= sword_profile.duration, "sword cooldown is shorter than its attack")
	_expect(zombie_profile.cooldown >= zombie_profile.duration, "zombie cooldown is shorter than its attack")
	var zombie_definition := load("res://entities/definitions/zombie.tres") as EntityDefinition
	var overkill_stats := ActorStats.new(zombie_definition.stats_definition)
	_expect(is_equal_approx(overkill_stats.damage(1000.0), 80.0), "overkill damage did not clamp to remaining HP")
	_expect(is_zero_approx(overkill_stats.current_hp) and overkill_stats.is_dead(), "overkill damage did not leave the actor dead at zero HP")
	var normalized_contact := MeleeContactType.new(0, &"player", 1, &"zombie", sword_profile.id, Vector3.ONE, Vector3(4.0, 0.0, 0.0))
	_expect(is_equal_approx(normalized_contact.hit_direction.length(), 1.0), "melee contact did not normalize its direction")

	var world := _make_flat_world()
	var coordinator := EntityCoordinator.new()
	var combat := MeleeCombatCoordinator.new()
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as PlayerMotor
	var camera := Camera3D.new()
	root.add_child(coordinator)
	root.add_child(combat)
	root.add_child(player)
	root.add_child(camera)
	player.global_position = Vector3(0.5, FEET_Y, 0.5)
	player.set_physics_process(false)
	player.interactor.set_physics_process(false)
	player.animation_driver.set_process(false)
	coordinator.setup(_make_two_zombie_catalog(), world, 1337, _always_ready)
	var player_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	_expect(player_stats.set_base_value(&"defense", 4.0), "player defense setup failed")
	combat.setup(world, player, player_stats, coordinator)
	coordinator.entity_melee_contact_reached.connect(combat.try_commit_entity_contact)
	combat.melee_contact_committed.connect(coordinator.record_melee_contact)
	combat.melee_contact_committed.connect(_on_melee_contact)
	player_stats.health_depleted.connect(_on_player_defeated)
	coordinator.tick(EntityCoordinator.SPAWN_INTERVAL_SECONDS, player.global_position, 20.0)
	coordinator.tick(EntityCoordinator.SPAWN_INTERVAL_SECONDS, player.global_position, 20.0)
	var actors := coordinator.get_active_actors()
	actors.sort_custom(func(a: EntityActor, b: EntityActor): return a.runtime_id < b.runtime_id)
	_expect(actors.size() == 2, "coordinator did not spawn two test zombies")
	if actors.size() != 2:
		await _cleanup(combat, coordinator, player, camera)
		_finish()
		return
	var near_actor := actors[0]
	var far_actor := actors[1]
	_expect(is_equal_approx(coordinator.get_current_hp(near_actor.runtime_id), 80.0), "first zombie did not spawn at full HP")
	_expect(is_equal_approx(coordinator.get_current_hp(far_actor.runtime_id), 80.0), "second zombie did not spawn at full HP")
	_expect(is_equal_approx(coordinator.get_stat_value(near_actor.runtime_id, &"strength"), 5.0), "zombie strength changed")
	_expect(is_equal_approx(coordinator.get_stat_value(near_actor.runtime_id, &"defense"), 4.0), "zombie defense changed")
	_expect(coordinator.try_apply_damage(near_actor.runtime_id, 1.0), "direct entity damage was rejected")
	_expect(is_equal_approx(coordinator.get_current_hp(near_actor.runtime_id), 79.0), "direct entity damage changed the wrong amount")
	_expect(is_equal_approx(coordinator.get_current_hp(far_actor.runtime_id), 80.0), "entity runtime stats were shared between instances")
	var sword_damage := sword_profile.calculate_damage(player_stats.get_value(&"strength"), coordinator.get_stat_value(far_actor.runtime_id, &"defense"))
	_expect(is_equal_approx(sword_damage, 16.0), "configured player-to-zombie damage changed")
	var player_center := player.global_position + Vector3.UP * (player.player_height * 0.5)
	var ray_origin := player_center + Vector3(0.0, 6.0, 5.5)
	var ray_direction := (player_center + Vector3.FORWARD - ray_origin).normalized()

	near_actor.global_position = Vector3(0.5, FEET_Y, -1.0)
	far_actor.global_position = Vector3(0.5, FEET_Y, -1.8)
	coordinator.tick(0.0, player.global_position, 20.0)
	var sweep_target_ids := combat.acquire_player_targets(ray_origin, ray_direction, sword_profile)
	_expect(sweep_target_ids == [near_actor.runtime_id, far_actor.runtime_id], "sword sweep did not lock both aligned actors")
	var contact_count_before := _contacts.size()
	_expect(combat.try_commit_player_contacts(sweep_target_ids, ray_origin, ray_direction, sword_profile), "sword sweep did not commit its locked targets")
	_expect(_contacts.size() == contact_count_before + 2, "sword sweep did not emit one contact per target")
	_expect(_contacts[contact_count_before].target_runtime_id == near_actor.runtime_id and _contacts[contact_count_before + 1].target_runtime_id == far_actor.runtime_id, "sword sweep contacts were not emitted in runtime-ID order")
	_expect(is_equal_approx(coordinator.get_current_hp(near_actor.runtime_id), 63.0), "sword sweep applied incorrect damage to the first target")
	_expect(is_equal_approx(coordinator.get_current_hp(far_actor.runtime_id), 64.0), "sword sweep applied incorrect damage to the second target")

	near_actor.global_position = Vector3(0.5, FEET_Y, -4.0)
	far_actor.global_position = Vector3(0.5, FEET_Y, -5.0)
	coordinator.tick(0.0, player.global_position, 20.0)
	_expect(combat.acquire_player_targets(ray_origin, ray_direction, sword_profile).is_empty(), "cursor targeting accepted an out-of-range actor")
	_expect(is_equal_approx(coordinator.get_current_hp(near_actor.runtime_id), 63.0), "out-of-range targeting changed entity HP")
	_expect(is_equal_approx(coordinator.get_current_hp(far_actor.runtime_id), 64.0), "out-of-range targeting changed another entity's HP")

	near_actor.global_position = Vector3(0.5, FEET_Y, -1.0)
	far_actor.global_position = Vector3(4.5, FEET_Y, -1.8)
	coordinator.tick(0.0, player.global_position, 20.0)
	world.restore_block_edits({Vector3i(0, int(FEET_Y), 0): BlockId.Type.STONE}, {})
	_expect(combat.acquire_player_targets(ray_origin, ray_direction, sword_profile).is_empty(), "cursor targeting ignored terrain occlusion")
	_expect(is_equal_approx(coordinator.get_current_hp(near_actor.runtime_id), 63.0), "occluded targeting changed entity HP")
	world.restore_block_edits({}, {})

	var moved_target_ids := combat.acquire_player_targets(ray_origin, ray_direction, sword_profile)
	_expect(moved_target_ids == [near_actor.runtime_id], "moved-target setup did not lock the near actor")
	near_actor.global_position = Vector3(3.5, FEET_Y, -1.0)
	contact_count_before = _contacts.size()
	_expect(not combat.try_commit_player_contacts(moved_target_ids, ray_origin, ray_direction, sword_profile), "contact committed after the locked target moved outside the sweep")
	_expect(_contacts.size() == contact_count_before, "moved target emitted a contact")
	_expect(is_equal_approx(coordinator.get_current_hp(near_actor.runtime_id), 63.0), "moved target took damage from a rejected contact")

	near_actor.global_position = Vector3(0.5, FEET_Y, -1.0)
	coordinator.tick(0.0, player.global_position, 20.0)
	var despawned_target_ids := combat.acquire_player_targets(ray_origin, ray_direction, sword_profile)
	near_actor.global_position = Vector3(EntityCoordinator.DESPAWN_DISTANCE + 1.0, FEET_Y, 0.5)
	coordinator.tick(0.0, player.global_position, 20.0)
	_expect(not combat.try_commit_player_contacts(despawned_target_ids, ray_origin, ray_direction, sword_profile), "contact committed after the locked target despawned")
	_expect(_contacts.size() == contact_count_before, "despawned target emitted a contact")
	_expect(is_equal_approx(coordinator.get_current_hp(far_actor.runtime_id), 64.0), "stale contact changed another entity's HP")

	far_actor.global_position = Vector3(0.5, FEET_Y, -1.0)
	var target_id := far_actor.runtime_id
	contact_count_before = _contacts.size()
	_expect(combat.try_commit_player_contacts(_single_target(target_id), ray_origin, ray_direction, sword_profile), "accepted player contact did not commit")
	_expect(_contacts.size() == contact_count_before + 1, "accepted player contact was not emitted")
	_expect(is_equal_approx(coordinator.get_current_hp(target_id), 64.0 - sword_damage), "accepted player contact applied incorrect damage")
	var accepted_contact: MeleeContactType = _contacts.back()
	_expect(accepted_contact.source_runtime_id == 0 and accepted_contact.target_runtime_id == target_id, "committed player contact IDs are wrong")
	_expect(accepted_contact.source_definition_id == &"player" and accepted_contact.target_definition_id == &"zombie", "committed player contact definition IDs are wrong")
	_expect(accepted_contact.attack_id == sword_profile.id, "committed player contact attack ID is wrong")
	_expect(accepted_contact.world_position.is_finite(), "committed player contact position is invalid")
	_expect(is_equal_approx(accepted_contact.hit_direction.length(), 1.0), "committed player contact direction is not normalized")

	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var inventory := InventoryModel.new(item_catalog)
	inventory.setup_starter()
	inventory.select_slot(3)
	var input_buffer := InputBuffer.new()
	player.interactor.setup(world, camera, player, inventory, input_buffer, combat, coordinator)
	player.voxel_world = world
	player.stats = player_stats
	player._input_buffer = input_buffer
	var sword_action := item_catalog.get_definition(&"copper_sword").primary_action as MeleeAttackActionDefinition
	player.interactor.melee_attack_action = sword_action
	player.interactor.melee_attack_timer = sword_profile.cooldown
	player.interactor.melee_attack_elapsed = 0.0
	player.interactor._melee_target_runtime_ids = [target_id]
	player.interactor._melee_contact_pending = true
	player.interactor._melee_ray_origin = ray_origin
	player.interactor._melee_ray_direction = ray_direction
	contact_count_before = _contacts.size()
	var hp_before_player_swing := coordinator.get_current_hp(target_id)
	player.interactor._advance_melee_attack(sword_profile.contact_time - 0.01)
	_expect(_contacts.size() == contact_count_before, "player contact fired before its profile time")
	_expect(is_equal_approx(coordinator.get_current_hp(target_id), hp_before_player_swing), "player swing dealt damage before its profile time")
	player.interactor._advance_melee_attack(0.02)
	_expect(_contacts.size() == contact_count_before + 1, "player contact did not fire when its profile time was crossed")
	_expect(is_equal_approx(coordinator.get_current_hp(target_id), hp_before_player_swing - sword_damage), "player swing applied incorrect damage")
	player.interactor._advance_melee_attack(sword_profile.duration)
	_expect(_contacts.size() == contact_count_before + 1, "one player swing contacted more than once")
	_expect(is_equal_approx(coordinator.get_current_hp(target_id), hp_before_player_swing - sword_damage), "one player swing dealt damage more than once")

	far_actor.global_position = Vector3(0.5, FEET_Y, -0.5)
	var zombie_damage := zombie_profile.calculate_damage(coordinator.get_stat_value(target_id, &"strength"), player_stats.get_value(&"defense"))
	_expect(is_equal_approx(zombie_damage, 16.0), "configured zombie-to-player damage changed")
	contact_count_before = _contacts.size()
	var player_hp_before := player_stats.current_hp
	_expect(combat.try_commit_entity_contact(target_id, zombie_profile), "in-range zombie contact did not commit")
	_expect(_contacts.size() == contact_count_before + 1, "zombie contact was not emitted")
	_expect(is_equal_approx(player_stats.current_hp, player_hp_before - zombie_damage), "zombie contact did not apply player defense")
	var zombie_contact: MeleeContactType = _contacts.back()
	_expect(zombie_contact.source_runtime_id == target_id and zombie_contact.source_definition_id == &"zombie", "zombie contact source IDs are wrong")
	_expect(zombie_contact.target_runtime_id == 0 and zombie_contact.target_definition_id == &"player", "zombie contact target IDs are wrong")
	_expect(zombie_contact.attack_id == zombie_profile.id and zombie_contact.world_position.is_finite(), "zombie contact payload is wrong")
	_expect(is_equal_approx(zombie_contact.hit_direction.length(), 1.0), "zombie contact direction is not normalized")

	far_actor.global_position = Vector3(0.5, FEET_Y, -2.0)
	contact_count_before = _contacts.size()
	player_hp_before = player_stats.current_hp
	_expect(not combat.try_commit_entity_contact(target_id, zombie_profile), "out-of-range zombie contact committed")
	_expect(_contacts.size() == contact_count_before, "out-of-range zombie emitted a contact")
	_expect(is_equal_approx(player_stats.current_hp, player_hp_before), "out-of-range zombie contact changed player HP")

	far_actor.global_position = Vector3(0.5, FEET_Y, -0.5)
	world.restore_block_edits({Vector3i(0, int(FEET_Y), 0): BlockId.Type.STONE}, {})
	_expect(not combat.try_commit_entity_contact(target_id, zombie_profile), "terrain-occluded zombie contact committed")
	_expect(_contacts.size() == contact_count_before, "occluded zombie emitted a contact")
	_expect(is_equal_approx(player_stats.current_hp, player_hp_before), "occluded zombie contact changed player HP")
	world.restore_block_edits({}, {})

	var zombie_actor := far_actor as ZombieActor
	contact_count_before = _contacts.size()
	player_hp_before = player_stats.current_hp
	zombie_actor._arm_melee_contact(zombie_profile)
	zombie_actor._advance_melee_contact(zombie_profile.contact_time - 0.01)
	_expect(_contacts.size() == contact_count_before, "zombie contact fired before its profile time")
	_expect(is_equal_approx(player_stats.current_hp, player_hp_before), "zombie swing dealt damage before its profile time")
	zombie_actor._advance_melee_contact(0.02)
	_expect(_contacts.size() == contact_count_before + 1, "zombie contact did not fire when its profile time was crossed")
	_expect(is_equal_approx(player_stats.current_hp, player_hp_before - zombie_damage), "zombie swing applied incorrect damage")
	zombie_actor._advance_melee_contact(zombie_profile.duration)
	_expect(_contacts.size() == contact_count_before + 1, "one zombie swing contacted more than once")
	_expect(is_equal_approx(player_stats.current_hp, player_hp_before - zombie_damage), "one zombie swing dealt damage more than once")

	_expect(player_stats.set_current_hp(zombie_damage), "player lethal-contact setup failed")
	contact_count_before = _contacts.size()
	_expect(combat.try_commit_entity_contact(target_id, zombie_profile), "lethal zombie contact did not commit")
	_expect(_contacts.size() == contact_count_before + 1, "lethal zombie contact was not emitted")
	_expect(player_stats.is_dead() and is_zero_approx(player_stats.current_hp), "lethal zombie contact did not defeat the player")
	_expect(_player_defeat_count == 1, "player defeat did not emit exactly once")
	contact_count_before = _contacts.size()
	_expect(not combat.try_commit_entity_contact(target_id, zombie_profile), "dead player accepted another entity contact")
	_expect(_contacts.size() == contact_count_before and _player_defeat_count == 1, "dead player emitted another contact or defeat")
	_expect(is_zero_approx(player_stats.current_hp), "rejected post-defeat contact changed player HP")
	player.global_position = Vector3(5.5, FEET_Y, 5.5)
	player.velocity = Vector3(3.0, 4.0, 5.0)
	player.on_ground = true
	player.is_sprinting = true
	player._jump_windup_remaining = 0.5
	player.jump_anticipation = 0.5
	player.interactor.is_mining = true
	player.interactor.melee_attack_queue = 1
	player.interactor.target_has = true
	input_buffer.move_dir = Vector2.ONE
	input_buffer.sprint_pressed = true
	input_buffer.primary_use_pressed = true
	var respawn_position := Vector3(0.5, FEET_Y, 0.5)
	player.respawn_at(respawn_position)
	_expect(player.global_position.is_equal_approx(respawn_position), "player respawn did not restore the spawn position")
	_expect(player.velocity.is_zero_approx() and not player.on_ground and not player.is_sprinting, "player respawn did not reset locomotion")
	_expect(is_zero_approx(player._jump_windup_remaining) and is_zero_approx(player.jump_anticipation), "player respawn did not reset jump state")
	_expect(not player.interactor.is_mining and player.interactor.melee_attack_action == null and player.interactor.melee_attack_queue == 0, "player respawn did not cancel actions")
	_expect(not player.interactor.target_has and input_buffer.move_dir == Vector2.ZERO and not input_buffer.sprint_pressed and not input_buffer.primary_use_pressed, "player respawn did not clear targeting or buffered input")
	_expect(is_equal_approx(player_stats.current_hp, player_stats.get_value(&"hp")), "player respawn did not restore full HP")

	for expected_hp in [16.0]:
		_expect(combat.try_commit_player_contacts(_single_target(target_id), ray_origin, ray_direction, sword_profile), "nonlethal zombie hit did not commit")
		_expect(is_equal_approx(coordinator.get_current_hp(target_id), expected_hp), "zombie did not retain the expected HP before its fifth hit")
	var retiring_actor: WeakRef = weakref(far_actor)
	zombie_actor._arm_melee_contact(zombie_profile)
	zombie_actor.velocity = Vector3(1.0, 2.0, 3.0)
	contact_count_before = _contacts.size()
	player_hp_before = player_stats.current_hp
	_expect(combat.try_commit_player_contacts(_single_target(target_id), ray_origin, ray_direction, sword_profile), "fifth zombie hit did not commit")
	_expect(_contacts.size() == contact_count_before + 1, "lethal player contact was not emitted")
	_expect(coordinator.get_actor(target_id) == null, "lethal damage left the zombie active")
	_expect(coordinator.get_active_count() == 0, "lethal damage left an unexpected active entity")
	_expect(coordinator._spatial_index.get_entry_count() == 0, "lethal damage left the zombie in the spatial index")
	_expect(coordinator._retiring.has(target_id), "lethal damage did not retain the zombie for death presentation")
	_expect(zombie_actor.velocity.is_zero_approx(), "lethal damage did not freeze zombie movement")
	_expect(not zombie_actor._melee_contact_pending, "lethal damage did not cancel the zombie's pending attack")
	_expect(zombie_actor._zombie_animation.get_current_state() == ZombieAnimationDriver.DEATH, "lethal damage did not start the zombie death pose")
	coordinator._spawn_elapsed = EntityCoordinator.SPAWN_INTERVAL_SECONDS
	coordinator.tick(0.0, player.global_position, 20.0)
	_expect(coordinator.get_active_count() == 1, "death presentation suppressed immediate replacement spawning")
	_expect(coordinator._retiring.has(target_id), "replacement spawning discarded the zombie death presentation")
	contact_count_before = _contacts.size()
	zombie_actor._advance_melee_contact(zombie_profile.contact_time + 0.01)
	_expect(_contacts.size() == contact_count_before, "retiring zombie completed a pending attack")
	_expect(is_equal_approx(player_stats.current_hp, player_hp_before), "retiring zombie dealt pending attack damage")
	var fade_out_seconds := zombie_actor.visual_fader.fade_out_seconds
	coordinator.tick(ZombieAnimationDriver.DEATH_SECONDS, player.global_position, 20.0)
	_expect(coordinator._retiring.has(target_id), "zombie retirement ended before fade-out")
	coordinator.tick(fade_out_seconds + 0.01, player.global_position, 20.0)
	await process_frame
	_expect(not coordinator._retiring.has(target_id), "completed zombie fade remained coordinator-owned")
	_expect(retiring_actor.get_ref() == null, "completed zombie fade did not free its actor")
	_expect(coordinator.get_active_count() == 1, "replacement did not remain active after zombie retirement")

	await _cleanup(combat, coordinator, player, camera)
	await _test_sheep_damage(world, sword_profile)
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "orphan count ended at %d" % orphan_count)
	_finish()

func _test_sheep_damage(world: VoxelWorld, sword_profile: MeleeAttackProfile) -> void:
	var coordinator := EntityCoordinator.new()
	var combat := MeleeCombatCoordinator.new()
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as PlayerMotor
	var camera := Camera3D.new()
	root.add_child(coordinator)
	root.add_child(combat)
	root.add_child(player)
	root.add_child(camera)
	player.global_position = Vector3(0.5, FEET_Y, 0.5)
	player.set_physics_process(false)
	player.interactor.set_physics_process(false)
	player.animation_driver.set_process(false)
	coordinator.setup(_make_one_sheep_catalog(), world, 7331, _always_ready)
	var player_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	combat.setup(world, player, player_stats, coordinator)
	combat.melee_contact_committed.connect(coordinator.record_melee_contact)
	combat.melee_contact_committed.connect(_on_melee_contact)
	coordinator.tick(EntityCoordinator.SPAWN_INTERVAL_SECONDS, player.global_position, 12.0)
	var actors := coordinator.get_active_actors()
	_expect(actors.size() == 1 and actors[0] is SheepActor, "sheep damage test did not spawn one sheep")
	if actors.size() != 1:
		await _cleanup(combat, coordinator, player, camera)
		return
	var sheep := actors[0] as SheepActor
	sheep.global_position = Vector3(0.5, FEET_Y, -0.5)
	var target_id := sheep.runtime_id
	var sheep_damage := sword_profile.calculate_damage(player_stats.get_value(&"strength"), coordinator.get_stat_value(target_id, &"defense"))
	_expect(is_equal_approx(coordinator.get_current_hp(target_id), 40.0), "sheep did not spawn at 40 HP")
	_expect(is_equal_approx(sheep_damage, 20.0), "configured player-to-sheep damage changed")
	var player_center := player.global_position + Vector3.UP * (player.player_height * 0.5)
	var target_bounds := sheep.get_world_bounds()
	var target_center := target_bounds.position + target_bounds.size * 0.5
	var aim_point := Vector3(target_center.x, player_center.y, target_center.z)
	var ray_origin := player_center + Vector3(0.0, 6.0, 5.5)
	var ray_direction := (aim_point - ray_origin).normalized()
	var contact_count_before := _contacts.size()
	_expect(combat.try_commit_player_contacts(_single_target(target_id), ray_origin, ray_direction, sword_profile), "first sheep hit did not commit")
	_expect(_contacts.size() == contact_count_before + 1, "first sheep hit was not emitted")
	_expect(is_equal_approx(coordinator.get_current_hp(target_id), 20.0), "first sheep hit did not leave 20 HP")
	_expect(sheep.brain.state == SheepBrain.State.FLEE, "nonlethal sheep hit did not start flee behavior")
	var retiring_actor: WeakRef = weakref(sheep)
	contact_count_before = _contacts.size()
	_expect(combat.try_commit_player_contacts(_single_target(target_id), ray_origin, ray_direction, sword_profile), "second sheep hit did not commit")
	_expect(_contacts.size() == contact_count_before + 1, "second sheep hit was not emitted")
	_expect(coordinator.get_actor(target_id) == null and coordinator.get_active_count() == 0, "second sheep hit was not lethal")
	_expect(coordinator._spatial_index.get_entry_count() == 0, "dead sheep remained in the spatial index")
	_expect(coordinator._retiring.has(target_id), "dead sheep did not enter death retirement")
	_expect(sheep._sheep_animation.get_current_state() == SheepAnimationDriver.DEATH, "lethal damage did not start the sheep death pose")
	coordinator.tick(SheepAnimationDriver.DEATH_SECONDS, player.global_position, 12.0)
	_expect(coordinator._retiring.has(target_id), "sheep retirement ended before fade-out")
	coordinator.tick(sheep.visual_fader.fade_out_seconds + 0.01, player.global_position, 12.0)
	await process_frame
	_expect(not coordinator._retiring.has(target_id), "completed sheep fade remained coordinator-owned")
	_expect(retiring_actor.get_ref() == null, "completed sheep fade did not free its actor")
	await _cleanup(combat, coordinator, player, camera)

func _cleanup(combat: MeleeCombatCoordinator, coordinator: EntityCoordinator, player: PlayerMotor, camera: Camera3D) -> void:
	combat.shutdown()
	coordinator.shutdown()
	for node in [combat, coordinator, player, camera]:
		if is_instance_valid(node):
			node.queue_free()
	await process_frame
	await process_frame

func _finish() -> void:
	if _failures == 0:
		print("ENTITY_COMBAT_INTEGRATION PASS")
		quit(0)
	else:
		print("ENTITY_COMBAT_INTEGRATION FAIL failures=%d" % _failures)
		quit(1)
