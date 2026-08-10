extends SceneTree

const FLAT_HEIGHT: int = 6
const FEET_Y: float = float(FLAT_HEIGHT + 1)
const TEST_RADIUS: int = 48

const MeleeContactType := preload("res://combat/melee_contact.gd")

var _failures: int = 0
var _contacts: Array[MeleeContactType] = []

func _init() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[entity_combat_integration] FAIL: %s" % message)

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

func _on_melee_contact(contact: MeleeContactType) -> void:
	_contacts.append(contact)

func _run() -> void:
	var sword_profile := load("res://combat/profiles/copper_sword_melee.tres") as MeleeAttackProfile
	var zombie_profile := load("res://combat/profiles/zombie_melee.tres") as MeleeAttackProfile
	_expect(sword_profile != null and sword_profile.validate(sword_profile.resource_path), "copper sword profile is invalid")
	_expect(zombie_profile != null and zombie_profile.validate(zombie_profile.resource_path), "zombie profile is invalid")
	_expect(sword_profile.id == &"copper_sword_melee", "copper sword attack ID changed")
	_expect(zombie_profile.id == &"zombie_melee", "zombie attack ID changed")
	_expect(sword_profile.cooldown >= sword_profile.duration, "sword cooldown is shorter than its attack")
	_expect(zombie_profile.cooldown >= zombie_profile.duration, "zombie cooldown is shorter than its attack")
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
	combat.setup(world, player, coordinator)
	coordinator.entity_melee_contact_reached.connect(combat.try_commit_entity_contact)
	combat.melee_contact_committed.connect(coordinator.record_melee_contact)
	combat.melee_contact_committed.connect(_on_melee_contact)
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
	var ray_origin := Vector3(0.5, FEET_Y + 0.9, 6.0)
	var ray_direction := Vector3.FORWARD

	near_actor.global_position = Vector3(0.5, FEET_Y, -1.0)
	far_actor.global_position = Vector3(0.5, FEET_Y, -1.8)
	_expect(combat.acquire_player_target(ray_origin, ray_direction, sword_profile) == near_actor.runtime_id, "cursor targeting did not choose the nearest actor")

	near_actor.global_position = Vector3(0.5, FEET_Y, -4.0)
	far_actor.global_position = Vector3(0.5, FEET_Y, -5.0)
	_expect(combat.acquire_player_target(ray_origin, ray_direction, sword_profile) == -1, "cursor targeting accepted an out-of-range actor")

	near_actor.global_position = Vector3(0.5, FEET_Y, -1.0)
	far_actor.global_position = Vector3(2.5, FEET_Y, -1.8)
	world.restore_block_edits({Vector3i(0, int(FEET_Y), 2): BlockId.Type.STONE}, {})
	_expect(combat.acquire_player_target(ray_origin, ray_direction, sword_profile) == -1, "cursor targeting ignored terrain occlusion")
	world.restore_block_edits({}, {})

	var moved_target_id := combat.acquire_player_target(ray_origin, ray_direction, sword_profile)
	_expect(moved_target_id == near_actor.runtime_id, "moved-target setup did not lock the near actor")
	near_actor.global_position = Vector3(3.5, FEET_Y, -1.0)
	var contact_count_before := _contacts.size()
	_expect(not combat.try_commit_player_contact(moved_target_id, ray_origin, ray_direction, sword_profile), "contact committed after the locked target moved off ray")
	_expect(_contacts.size() == contact_count_before, "moved target emitted a contact")

	near_actor.global_position = Vector3(0.5, FEET_Y, -1.0)
	var despawned_target_id := combat.acquire_player_target(ray_origin, ray_direction, sword_profile)
	near_actor.global_position = Vector3(EntityCoordinator.DESPAWN_DISTANCE + 1.0, FEET_Y, 0.5)
	coordinator.tick(0.0, player.global_position, 20.0)
	_expect(not combat.try_commit_player_contact(despawned_target_id, ray_origin, ray_direction, sword_profile), "contact committed after the locked target despawned")
	_expect(_contacts.size() == contact_count_before, "despawned target emitted a contact")

	far_actor.global_position = Vector3(0.5, FEET_Y, -1.0)
	var target_id := far_actor.runtime_id
	contact_count_before = _contacts.size()
	_expect(combat.try_commit_player_contact(target_id, ray_origin, ray_direction, sword_profile), "accepted player contact did not commit")
	_expect(_contacts.size() == contact_count_before + 1, "accepted player contact was not emitted")
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
	player.interactor.setup(world, camera, player, inventory, input_buffer, combat)
	var sword_action := item_catalog.get_definition(&"copper_sword").primary_action as MeleeAttackActionDefinition
	player.interactor.melee_attack_action = sword_action
	player.interactor.melee_attack_timer = sword_profile.cooldown
	player.interactor.melee_attack_elapsed = 0.0
	player.interactor._melee_target_runtime_id = target_id
	player.interactor._melee_contact_pending = true
	player.interactor._melee_ray_origin = ray_origin
	player.interactor._melee_ray_direction = ray_direction
	contact_count_before = _contacts.size()
	player.interactor._advance_melee_attack(sword_profile.contact_time - 0.01)
	_expect(_contacts.size() == contact_count_before, "player contact fired before its profile time")
	player.interactor._advance_melee_attack(0.02)
	_expect(_contacts.size() == contact_count_before + 1, "player contact did not fire when its profile time was crossed")
	player.interactor._advance_melee_attack(sword_profile.duration)
	_expect(_contacts.size() == contact_count_before + 1, "one player swing contacted more than once")

	far_actor.global_position = Vector3(0.5, FEET_Y, -0.5)
	contact_count_before = _contacts.size()
	_expect(combat.try_commit_entity_contact(target_id, zombie_profile), "in-range zombie contact did not commit")
	_expect(_contacts.size() == contact_count_before + 1, "zombie contact was not emitted")
	var zombie_contact: MeleeContactType = _contacts.back()
	_expect(zombie_contact.source_runtime_id == target_id and zombie_contact.source_definition_id == &"zombie", "zombie contact source IDs are wrong")
	_expect(zombie_contact.target_runtime_id == 0 and zombie_contact.target_definition_id == &"player", "zombie contact target IDs are wrong")
	_expect(zombie_contact.attack_id == zombie_profile.id and zombie_contact.world_position.is_finite(), "zombie contact payload is wrong")
	_expect(is_equal_approx(zombie_contact.hit_direction.length(), 1.0), "zombie contact direction is not normalized")

	far_actor.global_position = Vector3(0.5, FEET_Y, -2.0)
	contact_count_before = _contacts.size()
	_expect(not combat.try_commit_entity_contact(target_id, zombie_profile), "out-of-range zombie contact committed")
	_expect(_contacts.size() == contact_count_before, "out-of-range zombie emitted a contact")

	far_actor.global_position = Vector3(0.5, FEET_Y, -0.5)
	world.restore_block_edits({Vector3i(0, int(FEET_Y), 0): BlockId.Type.STONE}, {})
	_expect(not combat.try_commit_entity_contact(target_id, zombie_profile), "terrain-occluded zombie contact committed")
	_expect(_contacts.size() == contact_count_before, "occluded zombie emitted a contact")
	world.restore_block_edits({}, {})

	var zombie_actor := far_actor as ZombieActor
	contact_count_before = _contacts.size()
	zombie_actor._arm_melee_contact(zombie_profile)
	zombie_actor._advance_melee_contact(zombie_profile.contact_time - 0.01)
	_expect(_contacts.size() == contact_count_before, "zombie contact fired before its profile time")
	zombie_actor._advance_melee_contact(0.02)
	_expect(_contacts.size() == contact_count_before + 1, "zombie contact did not fire when its profile time was crossed")
	zombie_actor._advance_melee_contact(zombie_profile.duration)
	_expect(_contacts.size() == contact_count_before + 1, "one zombie swing contacted more than once")

	await _cleanup(combat, coordinator, player, camera)
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "orphan count ended at %d" % orphan_count)
	_finish()

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
