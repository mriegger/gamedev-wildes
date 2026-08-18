extends SceneTree

const FLAT_HEIGHT: int = 6
const FEET_Y: float = float(FLAT_HEIGHT + 1)
const TEST_RADIUS: int = 48

const MeleeContactType := preload("res://combat/melee_contact.gd")
const EnemyHealthBar3DType := preload("res://entities/presentation/enemy_health_bar_3d.gd")
const EnemyCombatFeedbackType := preload("res://combat/presentation/enemy_combat_feedback.gd")
const EnemyDamageNumber3DType := preload("res://combat/presentation/enemy_damage_number_3d.gd")

var _failures: int = 0
var _contacts: Array[MeleeContactType] = []
var _outcomes: Array[MeleeOutcome] = []
var _player_defeat_count: int = 0

func _init() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[entity_combat_integration] FAIL: %s" % message)

func _color_distance(left: Color, right: Color) -> float:
	return absf(left.r - right.r) + absf(left.g - right.g) + absf(left.b - right.b) + absf(left.a - right.a)

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
	definition.ambient_max_active = 2
	var definitions: Array[EntityDefinition] = [definition]
	var catalog := EntityCatalog.new()
	catalog.definitions = definitions
	return catalog

func _make_one_sheep_catalog() -> EntityCatalog:
	var source := load("res://entities/definitions/sheep.tres") as EntityDefinition
	var definition := source.duplicate(true) as EntityDefinition
	definition.ambient_max_active = 1
	var definitions: Array[EntityDefinition] = [definition]
	var catalog := EntityCatalog.new()
	catalog.definitions = definitions
	return catalog

func _make_one_bird_catalog() -> EntityCatalog:
	var source := load("res://entities/definitions/bird.tres") as EntityDefinition
	var definition := source.duplicate(true) as EntityDefinition
	definition.ambient_max_active = 1
	var definitions: Array[EntityDefinition] = [definition]
	var catalog := EntityCatalog.new()
	catalog.definitions = definitions
	return catalog

func _make_one_skeleton_catalog() -> EntityCatalog:
	var source := load("res://entities/definitions/skeleton.tres") as EntityDefinition
	var definition := source.duplicate(true) as EntityDefinition
	definition.ambient_max_active = 1
	var definitions: Array[EntityDefinition] = [definition]
	var catalog := EntityCatalog.new()
	catalog.definitions = definitions
	return catalog

func _make_combat_catalog(zombie_count: int, sheep_count: int) -> EntityCatalog:
	var definitions: Array[EntityDefinition] = []
	if sheep_count > 0:
		var sheep := (load("res://entities/definitions/sheep.tres") as EntityDefinition).duplicate(true) as EntityDefinition
		sheep.ambient_max_active = sheep_count
		definitions.append(sheep)
	if zombie_count > 0:
		var zombie := (load("res://entities/definitions/zombie.tres") as EntityDefinition).duplicate(true) as EntityDefinition
		zombie.ambient_max_active = zombie_count
		definitions.append(zombie)
	var catalog := EntityCatalog.new()
	catalog.definitions = definitions
	return catalog

func _make_combat_fixture(world: VoxelWorld, zombie_count: int, sheep_count: int, seed: int) -> Dictionary:
	var coordinator := WorldEntityCoordinator.new()
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
	var entity_catalog := _make_combat_catalog(zombie_count, sheep_count)
	coordinator.setup(entity_catalog, world, seed, _always_ready)
	var player_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	combat.setup(world, player, player_stats, coordinator.get_runtime())
	combat.melee_outcome_committed.connect(coordinator.get_runtime().record_melee_outcome)
	combat.melee_outcome_committed.connect(_on_melee_contact)
	for _index in range(sheep_count):
		coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 12.0)
	for _index in range(zombie_count):
		coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	return {
		"camera": camera,
		"combat": combat,
		"coordinator": coordinator,
		"entity_catalog": entity_catalog,
		"player": player,
		"player_stats": player_stats,
	}

func _get_sorted_actors(coordinator: WorldEntityCoordinator) -> Array[EntityActor]:
	var actors := coordinator.get_runtime().get_active_actors()
	actors.sort_custom(func(left: EntityActor, right: EntityActor) -> bool: return left.runtime_id < right.runtime_id)
	return actors

func _place_at_angle(actor: EntityActor, player_position: Vector3, angle_degrees: float, distance: float) -> void:
	var angle := deg_to_rad(angle_degrees)
	actor.global_position = Vector3(
		player_position.x + sin(angle) * distance,
		FEET_Y,
		player_position.z - cos(angle) * distance,
	)

func _orthographic_ray(player: PlayerMotor, planar_offset: Vector2) -> Array[Vector3]:
	var player_center := player.global_position + Vector3.UP * (player.player_height * 0.5)
	var aim_point := player_center + Vector3(planar_offset.x, 0.0, planar_offset.y)
	var direction := Vector3(0.0, -1.0, -1.0).normalized()
	return [aim_point - direction * 6.0, direction]

func _active_ids(actors: Array[EntityActor]) -> Array[int]:
	var result: Array[int] = []
	for actor in actors:
		result.append(actor.runtime_id)
	return result

func _on_melee_contact(outcome: MeleeOutcome) -> void:
	_outcomes.append(outcome)
	_contacts.append(outcome.contact)

func _on_player_defeated() -> void:
	_player_defeat_count += 1

func _run() -> void:
	var sword_profile := load("res://combat/profiles/copper_sword_melee.tres") as MeleeAttackProfile
	var hammer_profile := load("res://combat/profiles/copper_hammer_melee.tres") as MeleeAttackProfile
	var zombie_profile := load("res://combat/profiles/zombie_melee.tres") as MeleeAttackProfile
	var skeleton_profile := load("res://combat/profiles/skeleton_melee.tres") as MeleeAttackProfile
	_expect(sword_profile != null and sword_profile.validate(sword_profile.resource_path), "copper sword profile is invalid")
	_expect(hammer_profile != null and hammer_profile.validate(hammer_profile.resource_path), "copper hammer profile is invalid")
	_expect(zombie_profile != null and zombie_profile.validate(zombie_profile.resource_path), "zombie profile is invalid")
	_expect(skeleton_profile != null and skeleton_profile.validate(skeleton_profile.resource_path), "skeleton profile is invalid")
	_expect(sword_profile.id == &"copper_sword_melee", "copper sword attack ID changed")
	_expect(zombie_profile.id == &"zombie_melee", "zombie attack ID changed")
	_expect(skeleton_profile.id == &"skeleton_melee", "skeleton attack ID changed")
	_expect(is_equal_approx(sword_profile.base_damage, 10.0), "copper sword base damage changed")
	_expect(is_equal_approx(hammer_profile.damage_multiplier, 1.0), "copper hammer base damage multiplier changed")
	_expect(is_equal_approx(hammer_profile.reach, 4.0) and is_equal_approx(hammer_profile.sweep_degrees, 360.0), "copper hammer radius changed")
	_expect(hammer_profile.acquire_targets_on_contact and hammer_profile.knockback_speed > 0.0, "copper hammer impact behavior changed")
	_expect(is_equal_approx(zombie_profile.base_damage, 15.0), "zombie base damage changed")
	_expect(is_equal_approx(skeleton_profile.base_damage, 5.0), "skeleton base damage changed")
	_expect(is_equal_approx(sword_profile.sweep_degrees, 120.0), "copper sword sweep changed")
	_expect(is_zero_approx(zombie_profile.sweep_degrees), "zombie attack became a sweep")
	_expect(is_zero_approx(skeleton_profile.sweep_degrees), "skeleton attack became a sweep")
	_expect(MeleeAttackProfile.is_valid_sweep_degrees(0.0), "zero-degree sweep validation was rejected")
	_expect(MeleeAttackProfile.is_valid_sweep_degrees(360.0), "full-circle sweep validation was rejected")
	_expect(not MeleeAttackProfile.is_valid_sweep_degrees(-0.1), "negative sweep validation was accepted")
	_expect(not MeleeAttackProfile.is_valid_sweep_degrees(360.1), "over-full-circle sweep validation was accepted")
	_expect(not MeleeAttackProfile.is_valid_sweep_degrees(INF), "non-finite sweep validation was accepted")
	var full_circle_profile := sword_profile.duplicate(true) as MeleeAttackProfile
	full_circle_profile.sweep_degrees = 360.0
	_expect(not full_circle_profile.requires_planar_aim(), "full-circle sweep required a planar aim")
	_expect(sword_profile.requires_planar_aim(), "directional sword sweep did not require a planar aim")
	_expect(is_equal_approx(sword_profile.calculate_damage(10.0, 4.0), 16.0), "sword damage formula is incorrect")
	var configured_sword_damage := sword_profile.calculate_damage(10.0, 4.0)
	_expect(is_equal_approx(hammer_profile.calculate_damage_at_distance(10.0, 4.0, 0.0), configured_sword_damage * 1.5), "hammer center damage is not 1.5 times sword damage")
	_expect(is_equal_approx(hammer_profile.calculate_damage_at_distance(10.0, 4.0, hammer_profile.reach * 0.5), configured_sword_damage), "hammer midpoint damage does not match sword damage")
	_expect(is_equal_approx(hammer_profile.calculate_damage_at_distance(10.0, 4.0, hammer_profile.reach), configured_sword_damage * 0.5), "hammer edge damage is not half of sword damage")
	_expect(is_equal_approx(zombie_profile.calculate_damage(5.0, 4.0), 16.0), "zombie damage formula is incorrect")
	_expect(is_equal_approx(skeleton_profile.calculate_damage(5.0, 0.0), 10.0), "skeleton unarmored damage formula is incorrect")
	_expect(is_equal_approx(sword_profile.calculate_damage(0.0, 100.0), 1.0), "damage did not clamp to its minimum")
	_expect(sword_profile.cooldown >= sword_profile.duration, "sword cooldown is shorter than its attack")
	_expect(zombie_profile.cooldown >= zombie_profile.duration, "zombie cooldown is shorter than its attack")
	_expect(skeleton_profile.cooldown >= skeleton_profile.duration, "skeleton cooldown is shorter than its attack")
	var zombie_definition := load("res://entities/definitions/zombie.tres") as EntityDefinition
	var overkill_stats := ActorStats.new(zombie_definition.stats_definition)
	_expect(is_equal_approx(overkill_stats.damage(1000.0), 80.0), "overkill damage did not clamp to remaining HP")
	_expect(is_zero_approx(overkill_stats.current_hp) and overkill_stats.is_dead(), "overkill damage did not leave the actor dead at zero HP")
	var normalized_contact := MeleeContactType.new(0, &"player", 1, &"zombie", sword_profile.id, Vector3.ONE, Vector3(4.0, 0.0, 0.0))
	_expect(is_equal_approx(normalized_contact.hit_direction.length(), 1.0), "melee contact did not normalize its direction")

	var world := _make_flat_world()
	var coordinator := WorldEntityCoordinator.new()
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
	combat.setup(world, player, player_stats, coordinator.get_runtime())
	coordinator.get_runtime().entity_melee_contact_reached.connect(combat.try_commit_entity_contact)
	combat.melee_outcome_committed.connect(coordinator.get_runtime().record_melee_outcome)
	combat.melee_outcome_committed.connect(_on_melee_contact)
	var enemy_feedback := EnemyCombatFeedbackType.new()
	root.add_child(enemy_feedback)
	camera.size = CameraRig.DEFAULT_ORTHO_SIZE
	enemy_feedback.setup(combat, camera)
	enemy_feedback.bind_runtime(coordinator.get_runtime())
	player_stats.health_depleted.connect(_on_player_defeated)
	coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	var actors := coordinator.get_runtime().get_active_actors()
	actors.sort_custom(func(a: EntityActor, b: EntityActor): return a.runtime_id < b.runtime_id)
	_expect(actors.size() == 2, "coordinator did not spawn two test zombies")
	if actors.size() != 2:
		await _cleanup(combat, coordinator, player, camera)
		_finish()
		return
	var near_actor := actors[0]
	var far_actor := actors[1]
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(near_actor.runtime_id), 80.0), "first zombie did not spawn at full HP")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(far_actor.runtime_id), 80.0), "second zombie did not spawn at full HP")
	_expect(near_actor.health_bar != null and not near_actor.health_bar.visible, "full-health enemy bar was visible")
	_expect(far_actor.health_bar != null and not far_actor.health_bar.visible, "second full-health enemy bar was visible")
	_expect(near_actor.health_bar in near_actor.visual_fader._geometries, "enemy health bar does not follow actor fade lifecycle")
	_expect(is_equal_approx(near_actor.health_bar.position.y, near_actor.definition.body_height + EnemyHealthBar3DType.HEIGHT_OFFSET), "enemy health bar is not above the actor")
	_expect(is_equal_approx(coordinator.get_runtime().get_stat_value(near_actor.runtime_id, &"strength"), 5.0), "zombie strength changed")
	_expect(is_equal_approx(coordinator.get_runtime().get_stat_value(near_actor.runtime_id, &"defense"), 4.0), "zombie defense changed")
	_expect(coordinator.get_runtime().try_apply_damage(near_actor.runtime_id, 1.0) != null, "direct entity damage was rejected")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(near_actor.runtime_id), 79.0), "direct entity damage changed the wrong amount")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(far_actor.runtime_id), 80.0), "entity runtime stats were shared between instances")
	_expect(near_actor.health_bar.visible and is_equal_approx(near_actor.health_bar.get_health_ratio(), 79.0 / 80.0), "damaged enemy health bar did not show its health ratio")
	_expect(not far_actor.health_bar.visible, "undamaged enemy health bar became visible")
	var health_bar_image := near_actor.health_bar._image as Image
	var sampled_health_color := health_bar_image.get_pixel(1, 2)
	var sampled_background_color := health_bar_image.get_pixel(EnemyHealthBar3DType.TEXTURE_WIDTH - 2, 2)
	_expect(_color_distance(sampled_health_color, EnemyHealthBar3DType.HEALTH_COLOR) < 0.01, "enemy health bar fill is not red: %s" % sampled_health_color)
	_expect(_color_distance(sampled_background_color, EnemyHealthBar3DType.BACKGROUND_COLOR) < 0.01, "enemy health bar background is not black: %s" % sampled_background_color)
	var sword_damage := sword_profile.calculate_damage(player_stats.get_value(&"strength"), coordinator.get_runtime().get_stat_value(far_actor.runtime_id, &"defense"))
	_expect(is_equal_approx(sword_damage, 16.0), "configured player-to-zombie damage changed")
	var player_center := player.global_position + Vector3.UP * (player.player_height * 0.5)
	var ray_origin := player_center + Vector3(0.0, 6.0, 5.5)
	var ray_direction := (player_center + Vector3.FORWARD - ray_origin).normalized()

	near_actor.global_position = Vector3(0.5, FEET_Y, -1.0)
	far_actor.global_position = Vector3(0.5, FEET_Y, -1.8)
	coordinator.tick(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	var sweep_target_ids := combat.acquire_player_targets(ray_origin, ray_direction, sword_profile)
	_expect(sweep_target_ids == [near_actor.runtime_id, far_actor.runtime_id], "sword sweep did not lock both aligned actors")
	var contact_count_before := _contacts.size()
	_expect(combat.try_commit_player_contacts(sweep_target_ids, ray_origin, ray_direction, sword_profile, &"copper_sword"), "sword sweep did not commit its locked targets")
	_expect(_contacts.size() == contact_count_before + 2, "sword sweep did not emit one contact per target")
	_expect(_contacts[contact_count_before].target_runtime_id == near_actor.runtime_id and _contacts[contact_count_before + 1].target_runtime_id == far_actor.runtime_id, "sword sweep contacts were not emitted in runtime-ID order")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(near_actor.runtime_id), 63.0), "sword sweep applied incorrect damage to the first target")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(far_actor.runtime_id), 64.0), "sword sweep applied incorrect damage to the second target")
	_expect(far_actor.health_bar.visible and is_equal_approx(far_actor.health_bar.get_health_ratio(), 0.8), "sword damage did not update the second enemy health bar")
	var active_damage_numbers := enemy_feedback._damage_numbers.filter(func(number): return number.is_active())
	_expect(active_damage_numbers.size() == 2, "multi-target sword hit did not show one damage number per enemy")
	if active_damage_numbers.size() == 2:
		var first_damage_number := active_damage_numbers[0] as EnemyDamageNumber3DType
		var start_height := first_damage_number.global_position.y
		_expect(first_damage_number.text == "16" and first_damage_number.visible, "default-zoom damage number is not visible and legible")
		_expect(first_damage_number.font_size == 24 and first_damage_number.outline_size == 4, "damage number typography changed")
		enemy_feedback._process(EnemyDamageNumber3DType.DURATION_SECONDS * 0.5)
		_expect(first_damage_number.global_position.y > start_height and first_damage_number.modulate.a < 1.0, "damage number did not float upward and fade")
		_expect(first_damage_number.outline_modulate.a < EnemyDamageNumber3DType.OUTLINE_COLOR.a, "damage number outline remained opaque while its text faded")
		enemy_feedback._process(EnemyDamageNumber3DType.DURATION_SECONDS * 0.5)
		_expect(not first_damage_number.is_active() and not first_damage_number.visible, "damage number did not finish its animation")
		first_damage_number.play(Vector3.ZERO, 12.6)
		_expect(first_damage_number.text == "13", "fractional damage number was not rounded to the nearest integer")
		first_damage_number.reset()
	camera.size = EnemyCombatFeedbackType.MAX_DAMAGE_NUMBER_CAMERA_SIZE + 1.0
	enemy_feedback._on_melee_outcome_committed(_outcomes[-1])
	_expect(enemy_feedback._damage_numbers.all(func(number): return not number.is_active()), "zoomed-out combat showed an unreadable damage number")
	camera.size = CameraRig.DEFAULT_ORTHO_SIZE

	near_actor.global_position = Vector3(0.5, FEET_Y, -4.0)
	far_actor.global_position = Vector3(0.5, FEET_Y, -5.0)
	coordinator.tick(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	_expect(combat.acquire_player_targets(ray_origin, ray_direction, sword_profile).is_empty(), "cursor targeting accepted an out-of-range actor")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(near_actor.runtime_id), 63.0), "out-of-range targeting changed entity HP")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(far_actor.runtime_id), 64.0), "out-of-range targeting changed another entity's HP")

	near_actor.global_position = Vector3(0.5, FEET_Y, -1.0)
	far_actor.global_position = Vector3(4.5, FEET_Y, -1.8)
	coordinator.tick(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	world.restore_block_edits({Vector3i(0, int(FEET_Y), 0): BlockId.Type.STONE}, {})
	_expect(combat.acquire_player_targets(ray_origin, ray_direction, sword_profile).is_empty(), "cursor targeting ignored terrain occlusion")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(near_actor.runtime_id), 63.0), "occluded targeting changed entity HP")
	world.restore_block_edits({}, {})

	var moved_target_ids := combat.acquire_player_targets(ray_origin, ray_direction, sword_profile)
	_expect(moved_target_ids == [near_actor.runtime_id], "moved-target setup did not lock the near actor")
	near_actor.global_position = Vector3(3.5, FEET_Y, -1.0)
	contact_count_before = _contacts.size()
	_expect(not combat.try_commit_player_contacts(moved_target_ids, ray_origin, ray_direction, sword_profile, &"copper_sword"), "contact committed after the locked target moved outside the sweep")
	_expect(_contacts.size() == contact_count_before, "moved target emitted a contact")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(near_actor.runtime_id), 63.0), "moved target took damage from a rejected contact")

	near_actor.global_position = Vector3(0.5, FEET_Y, -1.0)
	coordinator.tick(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	var despawned_target_ids := combat.acquire_player_targets(ray_origin, ray_direction, sword_profile)
	near_actor.global_position = Vector3(WorldEntityCoordinator.DESPAWN_DISTANCE + 1.0, FEET_Y, 0.5)
	coordinator.tick(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	_expect(not combat.try_commit_player_contacts(despawned_target_ids, ray_origin, ray_direction, sword_profile, &"copper_sword"), "contact committed after the locked target despawned")
	_expect(_contacts.size() == contact_count_before, "despawned target emitted a contact")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(far_actor.runtime_id), 64.0), "stale contact changed another entity's HP")

	far_actor.global_position = Vector3(0.5, FEET_Y, -1.0)
	var target_id := far_actor.runtime_id
	contact_count_before = _contacts.size()
	_expect(combat.try_commit_player_contacts(_single_target(target_id), ray_origin, ray_direction, sword_profile, &"copper_sword"), "accepted player contact did not commit")
	_expect(_contacts.size() == contact_count_before + 1, "accepted player contact was not emitted")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(target_id), 64.0 - sword_damage), "accepted player contact applied incorrect damage")
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
	player.interactor.setup(camera, player, inventory, input_buffer, combat, coordinator.get_runtime())
	player.interactor.bind_space(world, world)
	player.voxel_space = world
	player.stats = player_stats
	player._input_buffer = input_buffer
	var sword_action := item_catalog.get_definition(&"copper_sword").primary_action as MeleeAttackActionDefinition
	player.interactor.melee_attack_action = sword_action
	player.interactor.melee_attack_timer = sword_profile.cooldown
	player.interactor.melee_attack_elapsed = 0.0
	player.interactor._melee_target_runtime_ids = [target_id]
	player.interactor._melee_contact_pending = true
	player.interactor._melee_impact_pending = true
	player.interactor._melee_source_item_id = &"copper_sword"
	player.interactor._melee_ray_origin = ray_origin
	player.interactor._melee_ray_direction = ray_direction
	contact_count_before = _contacts.size()
	var hp_before_player_swing := coordinator.get_runtime().get_current_hp(target_id)
	player.interactor._advance_melee_attack(sword_profile.contact_time - 0.01)
	_expect(_contacts.size() == contact_count_before, "player contact fired before its profile time")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(target_id), hp_before_player_swing), "player swing dealt damage before its profile time")
	player.interactor._advance_melee_attack(0.02)
	_expect(_contacts.size() == contact_count_before + 1, "player contact did not fire when its profile time was crossed")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(target_id), hp_before_player_swing - sword_damage), "player swing applied incorrect damage")
	player.interactor._advance_melee_attack(sword_profile.duration)
	_expect(_contacts.size() == contact_count_before + 1, "one player swing contacted more than once")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(target_id), hp_before_player_swing - sword_damage), "one player swing dealt damage more than once")

	far_actor.global_position = Vector3(0.5, FEET_Y, -0.5)
	var zombie_damage := zombie_profile.calculate_damage(coordinator.get_runtime().get_stat_value(target_id, &"strength"), player_stats.get_value(&"defense"))
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
	zombie_actor._timed_melee_contact.arm(zombie_profile)
	zombie_actor._emit_melee_contact(zombie_actor._timed_melee_contact.advance(zombie_profile.contact_time - 0.01))
	_expect(_contacts.size() == contact_count_before, "zombie contact fired before its profile time")
	_expect(is_equal_approx(player_stats.current_hp, player_hp_before), "zombie swing dealt damage before its profile time")
	zombie_actor._emit_melee_contact(zombie_actor._timed_melee_contact.advance(0.02))
	_expect(_contacts.size() == contact_count_before + 1, "zombie contact did not fire when its profile time was crossed")
	_expect(is_equal_approx(player_stats.current_hp, player_hp_before - zombie_damage), "zombie swing applied incorrect damage")
	zombie_actor._emit_melee_contact(zombie_actor._timed_melee_contact.advance(zombie_profile.duration))
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
	var inventory_before_defeat := inventory.to_dict()
	player.enter_defeated_state()
	_expect(player.is_defeated(), "player did not enter its defeated state")
	_expect(player.velocity.is_zero_approx() and not player.is_sprinting, "player defeat did not stop locomotion")
	_expect(is_zero_approx(player._jump_windup_remaining) and is_zero_approx(player.jump_anticipation), "player defeat did not reset jump state")
	_expect(not player.interactor.is_mining and player.interactor.melee_attack_action == null and player.interactor.melee_attack_queue == 0, "player defeat did not cancel actions")
	_expect(not player.interactor.target_has and input_buffer.move_dir == Vector2.ZERO and not input_buffer.sprint_pressed and not input_buffer.primary_use_pressed, "player defeat did not clear targeting or buffered input")
	var defeated_position := player.global_position
	contact_count_before = _contacts.size()
	input_buffer.move_dir = Vector2.ONE
	input_buffer.primary_use_just = true
	player._physics_process(0.25)
	player.interactor._physics_process(0.25)
	_expect(player.global_position.is_equal_approx(defeated_position) and player.velocity.is_zero_approx(), "defeated player processed movement input")
	_expect(player.interactor.melee_attack_action == null and _contacts.size() == contact_count_before, "defeated player processed action input")
	var respawn_position := Vector3(0.5, FEET_Y, 0.5)
	player.respawn_at(respawn_position)
	_expect(not player.is_defeated(), "player respawn did not clear the defeated state")
	_expect(player.global_position.is_equal_approx(respawn_position), "player respawn did not restore the spawn position")
	_expect(player.velocity.is_zero_approx() and not player.on_ground and not player.is_sprinting, "player respawn did not reset locomotion")
	_expect(is_zero_approx(player._jump_windup_remaining) and is_zero_approx(player.jump_anticipation), "player respawn did not reset jump state")
	_expect(not player.interactor.is_mining and player.interactor.melee_attack_action == null and player.interactor.melee_attack_queue == 0, "player respawn did not cancel actions")
	_expect(not player.interactor.target_has and input_buffer.move_dir == Vector2.ZERO and not input_buffer.sprint_pressed and not input_buffer.primary_use_pressed, "player respawn did not clear targeting or buffered input")
	_expect(is_equal_approx(player_stats.current_hp, player_stats.get_value(&"hp")), "player respawn did not restore full HP")
	_expect(inventory.to_dict() == inventory_before_defeat, "player defeat or respawn changed inventory")

	for expected_hp in [16.0]:
		_expect(combat.try_commit_player_contacts(_single_target(target_id), ray_origin, ray_direction, sword_profile, &"copper_sword"), "nonlethal zombie hit did not commit")
		_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(target_id), expected_hp), "zombie did not retain the expected HP before its fifth hit")
	var retiring_actor: WeakRef = weakref(far_actor)
	zombie_actor._timed_melee_contact.arm(zombie_profile)
	zombie_actor.velocity = Vector3(1.0, 2.0, 3.0)
	contact_count_before = _contacts.size()
	player_hp_before = player_stats.current_hp
	_expect(combat.try_commit_player_contacts(_single_target(target_id), ray_origin, ray_direction, sword_profile, &"copper_sword"), "fifth zombie hit did not commit")
	_expect(_contacts.size() == contact_count_before + 1, "lethal player contact was not emitted")
	_expect(coordinator.get_runtime().get_actor(target_id) == null, "lethal damage left the zombie active")
	_expect(coordinator.get_runtime().get_active_count() == 0, "lethal damage left an unexpected active entity")
	_expect(coordinator.get_runtime()._spatial_index.get_entry_count() == 0, "lethal damage left the zombie in the spatial index")
	_expect(coordinator.get_runtime()._retiring.has(target_id), "lethal damage did not retain the zombie for death presentation")
	_expect(coordinator.get_runtime().get_presented_actor(target_id) == zombie_actor, "lethal damage hid the retiring actor from combat presentation")
	_expect(not zombie_actor.health_bar.visible, "defeated enemy retained its health bar")
	_expect(zombie_actor.velocity.is_zero_approx(), "lethal damage did not freeze zombie movement")
	_expect(not zombie_actor._timed_melee_contact.is_pending(), "lethal damage did not cancel the zombie's pending attack")
	_expect(zombie_actor._zombie_animation.get_current_state() == ZombieAnimationDriver.DEATH, "lethal damage did not start the zombie death pose")
	coordinator._spawn_elapsed = WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS
	coordinator.tick(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	_expect(coordinator.get_runtime().get_active_count() == 1, "death presentation suppressed immediate replacement spawning")
	_expect(coordinator.get_runtime()._retiring.has(target_id), "replacement spawning discarded the zombie death presentation")
	contact_count_before = _contacts.size()
	_expect(zombie_actor._timed_melee_contact.advance(zombie_profile.contact_time + 0.01) == null, "retiring zombie retained a timed contact")
	_expect(_contacts.size() == contact_count_before, "retiring zombie completed a pending attack")
	_expect(is_equal_approx(player_stats.current_hp, player_hp_before), "retiring zombie dealt pending attack damage")
	var fade_out_seconds := zombie_actor.visual_fader.fade_out_seconds
	coordinator.tick(ZombieAnimationDriver.DEATH_SECONDS, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	_expect(coordinator.get_runtime()._retiring.has(target_id), "zombie retirement ended before fade-out")
	coordinator.tick(fade_out_seconds + 0.01, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	await process_frame
	_expect(not coordinator.get_runtime()._retiring.has(target_id), "completed zombie fade remained coordinator-owned")
	_expect(retiring_actor.get_ref() == null, "completed zombie fade did not free its actor")
	_expect(coordinator.get_runtime().get_active_count() == 1, "replacement did not remain active after zombie retirement")

	enemy_feedback.unbind_runtime()
	enemy_feedback.queue_free()
	await process_frame
	await _cleanup(combat, coordinator, player, camera)
	await _test_skeleton_timed_melee(world, skeleton_profile)
	await _test_sheep_damage(world, sword_profile)
	await _test_untargetable_bird(world, sword_profile)
	await _test_zero_degree_compatibility(world, sword_profile)
	await _test_sweep_geometry(world, sword_profile)
	await _test_full_circle_directionless(world, sword_profile)
	await _test_overlapping_and_vertical_geometry(world, sword_profile)
	await _test_sweep_reach_and_locking(world, sword_profile)
	await _test_independent_contact_revalidation(world, sword_profile)
	await _test_uncapped_mixed_damage(world, sword_profile)
	await _test_multi_target_interactor_timing(world, sword_profile)
	await _test_hammer_slam(world, hammer_profile)
	await _test_player_death_screen()
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "orphan count ended at %d" % orphan_count)
	_finish()

func _test_skeleton_timed_melee(world: VoxelWorld, profile: MeleeAttackProfile) -> void:
	var coordinator := WorldEntityCoordinator.new()
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
	coordinator.setup(_make_one_skeleton_catalog(), world, 7791, _always_ready)
	var player_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	_expect(player_stats.set_base_value(&"defense", 0.0), "skeleton fixture defense setup failed")
	combat.setup(world, player, player_stats, coordinator.get_runtime())
	coordinator.get_runtime().entity_melee_contact_reached.connect(combat.try_commit_entity_contact)
	combat.melee_outcome_committed.connect(coordinator.get_runtime().record_melee_outcome)
	combat.melee_outcome_committed.connect(_on_melee_contact)
	var observation := EntityTargetObservation.create(
		player.global_position,
		player.global_position + Vector3(0.0, 0.9, -8.0),
		Vector3.BACK,
		Vector3.RIGHT,
	)
	coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, observation, 20.0)
	var actors := coordinator.get_runtime().get_active_actors()
	_expect(actors.size() == 1 and actors[0] is SkeletonActor, "Skeleton combat fixture did not spawn one Skeleton")
	if actors.size() != 1 or not actors[0] is SkeletonActor:
		await _cleanup(combat, coordinator, player, camera)
		return
	var skeleton := actors[0] as SkeletonActor
	skeleton.global_position = player.global_position + Vector3(0.0, 0.0, -1.0)
	skeleton.velocity = Vector3.ZERO
	skeleton.on_ground = true
	var attack_origin := skeleton.global_position
	for y in range(int(FEET_Y), int(FEET_Y) + 2):
		var placement := world.try_place_block(Vector3i(0, y, 1), BlockId.Type.STONE)
		_expect(placement.is_success(), "could not build Skeleton post-attack cover")
	skeleton.brain.advance(0.0, skeleton.global_position, skeleton.global_position + Vector3(31.0, 0.0, 0.0), false)
	var boundary_observation := EntityTargetObservation.create(
		skeleton.global_position + Vector3(5.0, 0.0, 0.0),
		observation.camera_origin,
		observation.camera_forward,
		observation.camera_right,
	)
	coordinator.tick(0.0, boundary_observation, 20.0)
	_expect(skeleton.brain.state == SkeletonBrain.State.SPRINT, "Skeleton melee fixture did not sprint at the five-block threshold")
	_expect(is_equal_approx(skeleton.max_speed, 5.5), "five-block ambush did not select Skeleton sprint speed")
	_expect(is_equal_approx(Vector2(skeleton.velocity.x, skeleton.velocity.z).length(), 5.5), "five-block ambush did not move at sprint speed")
	var contact_count_before := _contacts.size()
	var player_hp_before := player_stats.current_hp
	coordinator.tick(0.0, observation, 20.0)
	_expect(skeleton.brain.state == SkeletonBrain.State.ATTACK, "production Skeleton actor did not enter its attack state")
	_expect(skeleton._timed_melee_contact.is_pending(), "production Skeleton attack did not arm timed contact")
	skeleton.animation_driver.advance(0.0)
	_expect(skeleton._skeleton_animation.get_current_state() == SkeletonAnimationDriver.ATTACK, "production Skeleton attack did not start attack presentation")
	coordinator.tick(profile.contact_time - 0.01, observation, 20.0)
	_expect(_contacts.size() == contact_count_before, "Skeleton contact fired before its profile time")
	_expect(is_equal_approx(player_stats.current_hp, player_hp_before), "Skeleton dealt damage before contact time")
	coordinator.tick(0.02, observation, 20.0)
	_expect(_contacts.size() == contact_count_before + 1, "Skeleton contact did not fire when its profile time was crossed")
	_expect(is_equal_approx(player_stats.current_hp, player_hp_before - 10.0), "Skeleton contact did not deal 10 unarmored damage")
	var contact: MeleeContactType = _contacts.back()
	_expect(contact.source_runtime_id == skeleton.runtime_id and contact.source_definition_id == &"skeleton", "Skeleton contact source IDs are wrong")
	_expect(contact.attack_id == profile.id and contact.target_definition_id == &"player", "Skeleton contact payload is wrong")
	_expect(is_equal_approx((_outcomes.back() as MeleeOutcome).applied_damage, 10.0), "Skeleton combat outcome recorded incorrect damage")
	coordinator.tick(profile.duration, observation, 20.0)
	_expect(_contacts.size() == contact_count_before + 1, "one Skeleton swing contacted more than once")
	_expect(is_equal_approx(player_stats.current_hp, player_hp_before - 10.0), "one Skeleton swing dealt damage more than once")
	var reached_cover_state := false
	for _step in range(80):
		coordinator.tick(0.1, observation, 20.0)
		if skeleton.brain.state == SkeletonBrain.State.MOVE_TO_COVER or skeleton.brain.state == SkeletonBrain.State.HIDE:
			reached_cover_state = true
		if skeleton.brain.state == SkeletonBrain.State.HIDE:
			break
	_expect(reached_cover_state, "Skeleton did not accept reachable cover after its attack")
	_expect(skeleton.brain.state == SkeletonBrain.State.HIDE, "Skeleton did not finish its post-attack cover retreat: state=%d position=%s goal=%s" % [skeleton.brain.state, skeleton.global_position, skeleton.brain.get_movement_goal()])
	_expect(skeleton.global_position.distance_to(attack_origin) > 1.0, "Skeleton accepted its attack position as post-attack cover")
	coordinator.tick(0.0, observation, 20.0)
	_expect(skeleton.brain.state == SkeletonBrain.State.SPRINT or skeleton.brain.state == SkeletonBrain.State.ATTACK, "hidden Skeleton did not resume its five-block ambush")
	await _cleanup(combat, coordinator, player, camera)
	for y in range(int(FEET_Y), int(FEET_Y) + 2):
		var mined_edits := world.try_mine_block(Vector3i(0, y, 1))
		_expect(not mined_edits.is_empty() and (mined_edits[0] as BlockEdit).is_success(), "could not remove Skeleton post-attack cover")

func _test_player_death_screen() -> void:
	var scene := load("res://ui/screens/death/player_death_screen.tscn") as PackedScene
	var screen := scene.instantiate() as PlayerDeathScreen
	var respawn_emissions: Array[int] = [0]
	var main_menu_emissions: Array[int] = [0]
	screen.respawn_requested.connect(func(): respawn_emissions[0] += 1)
	screen.main_menu_requested.connect(func(): main_menu_emissions[0] += 1)
	root.add_child(screen)
	await process_frame
	await process_frame
	var modal_root := screen.get_node("ModalRoot") as Control
	_expect(screen.layer == 300, "player death screen is not on its high presentation layer")
	_expect(modal_root.mouse_filter == Control.MOUSE_FILTER_STOP, "player death screen does not block full-screen pointer input")
	_expect(screen.panel.material is ShaderMaterial, "player death screen panel is not frosted")
	_expect(screen.title_label.text == "YOU DIED!", "player death screen title changed")
	_expect(screen.respawn_button.button_text == "RESPAWN" and screen.main_menu_button.button_text == "MAIN MENU", "player death screen button labels changed")
	_expect(screen.respawn_button._button.has_focus(), "player death screen did not focus Respawn")
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	screen._unhandled_input(escape)
	_expect(screen.is_inside_tree() and screen.visible, "Escape dismissed the player death screen")
	_expect(respawn_emissions[0] == 0 and main_menu_emissions[0] == 0, "Escape emitted a player death screen intent")
	screen.respawn_button.pressed.emit()
	_expect(respawn_emissions[0] == 1 and main_menu_emissions[0] == 0, "Respawn emitted the wrong player death screen intent")
	screen.main_menu_button.pressed.emit()
	_expect(respawn_emissions[0] == 1 and main_menu_emissions[0] == 1, "Main Menu emitted the wrong player death screen intent")
	screen.queue_free()
	await process_frame

func _test_sheep_damage(world: VoxelWorld, sword_profile: MeleeAttackProfile) -> void:
	var coordinator := WorldEntityCoordinator.new()
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
	combat.setup(world, player, player_stats, coordinator.get_runtime())
	combat.melee_outcome_committed.connect(coordinator.get_runtime().record_melee_outcome)
	combat.melee_outcome_committed.connect(_on_melee_contact)
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var inventory := InventoryModel.new(item_catalog)
	inventory.setup_starter()
	var item_proficiency := ItemProficiency.new(item_catalog)
	var progression := CombatProgressionCoordinator.new()
	progression.setup(player_stats, inventory, load("res://entities/entity_catalog.tres") as EntityCatalog, item_proficiency)
	combat.melee_outcome_committed.connect(progression.record_melee_outcome)
	coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 12.0)
	var actors := coordinator.get_runtime().get_active_actors()
	_expect(actors.size() == 1 and actors[0] is SheepActor, "sheep damage test did not spawn one sheep")
	if actors.size() != 1:
		await _cleanup(combat, coordinator, player, camera)
		return
	var sheep := actors[0] as SheepActor
	sheep.global_position = Vector3(0.5, FEET_Y, -0.5)
	var target_id := sheep.runtime_id
	var sheep_damage := sword_profile.calculate_damage(player_stats.get_value(&"strength"), coordinator.get_runtime().get_stat_value(target_id, &"defense"))
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(target_id), 40.0), "sheep did not spawn at 40 HP")
	_expect(is_equal_approx(sheep_damage, 20.0), "configured player-to-sheep damage changed")
	var player_center := player.global_position + Vector3.UP * (player.player_height * 0.5)
	var target_bounds := sheep.get_world_bounds()
	var target_center := target_bounds.position + target_bounds.size * 0.5
	var aim_point := Vector3(target_center.x, player_center.y, target_center.z)
	var ray_origin := player_center + Vector3(0.0, 6.0, 5.5)
	var ray_direction := (aim_point - ray_origin).normalized()
	var contact_count_before := _contacts.size()
	_expect(combat.try_commit_player_contacts(_single_target(target_id), ray_origin, ray_direction, sword_profile, &"copper_sword"), "first sheep hit did not commit")
	_expect(_contacts.size() == contact_count_before + 1, "first sheep hit was not emitted")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(target_id), 20.0), "first sheep hit did not leave 20 HP")
	_expect(is_equal_approx(item_proficiency.get_experience(&"copper_sword"), 20.0), "first sheep hit awarded incorrect weapon proficiency")
	_expect(player_stats.get_total_experience() == 0, "nonlethal sheep hit awarded player experience")
	_expect(sheep.brain.state == SheepBrain.State.FLEE, "nonlethal sheep hit did not start flee behavior")
	var retiring_actor: WeakRef = weakref(sheep)
	contact_count_before = _contacts.size()
	_expect(combat.try_commit_player_contacts(_single_target(target_id), ray_origin, ray_direction, sword_profile, &"copper_sword"), "second sheep hit did not commit")
	_expect(_contacts.size() == contact_count_before + 1, "second sheep hit was not emitted")
	_expect(coordinator.get_runtime().get_actor(target_id) == null and coordinator.get_runtime().get_active_count() == 0, "second sheep hit was not lethal")
	_expect(_outcomes.back().target_defeated and is_equal_approx(_outcomes.back().applied_damage, 20.0), "lethal sheep outcome is incorrect")
	_expect(is_equal_approx(item_proficiency.get_experience(&"copper_sword"), 40.0), "lethal sheep hit awarded incorrect weapon proficiency")
	_expect(player_stats.get_total_experience() == 10, "lethal sheep hit did not award configured player experience")
	_expect(coordinator.get_runtime()._spatial_index.get_entry_count() == 0, "dead sheep remained in the spatial index")
	_expect(coordinator.get_runtime()._retiring.has(target_id), "dead sheep did not enter death retirement")
	_expect(sheep._sheep_animation.get_current_state() == SheepAnimationDriver.DEATH, "lethal damage did not start the sheep death pose")
	coordinator.tick(SheepAnimationDriver.DEATH_SECONDS, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 12.0)
	_expect(coordinator.get_runtime()._retiring.has(target_id), "sheep retirement ended before fade-out")
	coordinator.tick(sheep.visual_fader.fade_out_seconds + 0.01, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 12.0)
	await process_frame
	_expect(not coordinator.get_runtime()._retiring.has(target_id), "completed sheep fade remained coordinator-owned")
	_expect(retiring_actor.get_ref() == null, "completed sheep fade did not free its actor")
	await _cleanup(combat, coordinator, player, camera)

func _test_zero_degree_compatibility(world: VoxelWorld, sword_profile: MeleeAttackProfile) -> void:
	var fixture := _make_combat_fixture(world, 2, 0, 8011)
	var coordinator := fixture["coordinator"] as WorldEntityCoordinator
	var combat := fixture["combat"] as MeleeCombatCoordinator
	var player := fixture["player"] as PlayerMotor
	var actors := _get_sorted_actors(coordinator)
	_expect(actors.size() == 2, "zero-degree fixture did not spawn two zombies")
	if actors.size() != 2:
		await _cleanup(combat, coordinator, player, fixture["camera"] as Camera3D)
		return
	var profile := sword_profile.duplicate(true) as MeleeAttackProfile
	profile.id = &"zero_degree_test"
	profile.sweep_degrees = 0.0
	_expect(profile.validate("zero_degree_test"), "zero-degree profile was invalid")
	var player_center := player.global_position + Vector3.UP * (player.player_height * 0.5)
	var ray_origin := player_center
	var ray_direction := Vector3.FORWARD
	actors[0].global_position = Vector3(player.global_position.x, FEET_Y, player.global_position.z - 1.0)
	actors[1].global_position = Vector3(player.global_position.x, FEET_Y, player.global_position.z - 2.0)
	coordinator.tick(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	var locked_ids := combat.acquire_player_targets(ray_origin, ray_direction, profile)
	_expect(locked_ids == [actors[0].runtime_id], "zero-degree ray did not lock only the nearest aligned actor")
	var contact_count_before := _contacts.size()
	_expect(combat.try_commit_player_contacts(locked_ids, ray_origin, ray_direction, profile, &"copper_sword"), "zero-degree nearest contact did not commit")
	_expect(_contacts.size() == contact_count_before + 1, "zero-degree contact did not emit exactly once")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(actors[0].runtime_id), 64.0), "zero-degree contact damaged the nearest actor incorrectly")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(actors[1].runtime_id), 80.0), "zero-degree contact damaged the farther actor")
	actors[0].global_position = Vector3(player.global_position.x, FEET_Y, player.global_position.z - 4.0)
	actors[1].global_position = Vector3(player.global_position.x + 1.0, FEET_Y, player.global_position.z - 1.0)
	coordinator.tick(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	_expect(combat.acquire_player_targets(ray_origin, ray_direction, profile).is_empty(), "zero-degree ray locked an off-ray actor inside the would-be arc")
	actors[0].global_position = Vector3(player.global_position.x, FEET_Y, player.global_position.z - 1.0)
	coordinator.tick(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	locked_ids = combat.acquire_player_targets(ray_origin, ray_direction, profile)
	actors[0].global_position = Vector3(player.global_position.x + 1.0, FEET_Y, player.global_position.z - 1.0)
	contact_count_before = _contacts.size()
	_expect(not combat.try_commit_player_contacts(locked_ids, ray_origin, ray_direction, profile, &"copper_sword"), "zero-degree contact accepted a target that moved off its locked ray")
	_expect(_contacts.size() == contact_count_before and is_equal_approx(coordinator.get_runtime().get_current_hp(actors[0].runtime_id), 64.0), "moved zero-degree target took damage")
	await _cleanup(combat, coordinator, player, fixture["camera"] as Camera3D)

func _test_untargetable_bird(world: VoxelWorld, sword_profile: MeleeAttackProfile) -> void:
	var coordinator := WorldEntityCoordinator.new()
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
	coordinator.setup(_make_one_bird_catalog(), world, 6201, _always_ready)
	var player_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	combat.setup(world, player, player_stats, coordinator.get_runtime())
	coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 12.0)
	var bird := coordinator.get_runtime().get_active_actors()[0] as BirdActor if coordinator.get_runtime().get_active_count() == 1 else null
	_expect(bird != null, "untargetable bird fixture did not spawn")
	if bird == null:
		await _cleanup(combat, coordinator, player, camera)
		return
	_place_at_angle(bird, player.global_position, 0.0, 1.5)
	coordinator.get_runtime()._spatial_index.upsert(bird.runtime_id, bird.global_position, bird.get_world_bounds())
	var ray := _orthographic_ray(player, Vector2(0.0, -1.5))
	_expect(combat.acquire_player_targets(ray[0], ray[1], sword_profile).is_empty(), "melee acquisition selected an ambient bird")
	_expect(not combat.try_commit_player_contacts(_single_target(bird.runtime_id), ray[0], ray[1], sword_profile, &"copper_sword"), "forged target command damaged an ambient bird")
	_expect(coordinator.get_runtime().try_apply_damage(bird.runtime_id, 1.0) == null, "direct runtime damage affected an ambient bird")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(bird.runtime_id), 1.0), "ambient bird health changed")
	await _cleanup(combat, coordinator, player, camera)

func _test_sweep_geometry(world: VoxelWorld, sword_profile: MeleeAttackProfile) -> void:
	var fixture := _make_combat_fixture(world, 6, 0, 8012)
	var coordinator := fixture["coordinator"] as WorldEntityCoordinator
	var combat := fixture["combat"] as MeleeCombatCoordinator
	var player := fixture["player"] as PlayerMotor
	var actors := _get_sorted_actors(coordinator)
	_expect(actors.size() == 6, "sweep-geometry fixture did not spawn six zombies")
	if actors.size() != 6:
		await _cleanup(combat, coordinator, player, fixture["camera"] as Camera3D)
		return
	var angles: Array[float] = [0.0, 60.0, -60.0, 61.0, -61.0, 180.0]
	for index in range(actors.size()):
		_place_at_angle(actors[index], player.global_position, angles[index], 1.7)
	coordinator.tick(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	var forward_ray := _orthographic_ray(player, Vector2(0.0, -1.0))
	var forward_ids := combat.acquire_player_targets(forward_ray[0], forward_ray[1], sword_profile)
	var expected_forward: Array[int] = [actors[0].runtime_id, actors[1].runtime_id, actors[2].runtime_id]
	expected_forward.sort()
	_expect(forward_ids == expected_forward, "120-degree sweep did not include exactly its center and ±60-degree boundaries")
	var same_direction_ray := _orthographic_ray(player, Vector2(1.0, 0.0))
	_expect(forward_ray[1].is_equal_approx(same_direction_ray[1]), "orthographic aim fixture changed ray direction")
	var shifted_ids := combat.acquire_player_targets(same_direction_ray[0], same_direction_ray[1], sword_profile)
	var expected_shifted: Array[int] = [actors[1].runtime_id, actors[3].runtime_id]
	expected_shifted.sort()
	_expect(shifted_ids == expected_shifted, "same-direction orthographic rays did not derive aim from their different origins")
	var player_center := player.global_position + Vector3.UP * (player.player_height * 0.5)
	var horizontal_ids := combat.acquire_player_targets(player_center, Vector3.FORWARD, sword_profile)
	_expect(horizontal_ids == expected_forward, "horizontal ray fallback changed the forward sweep")
	_expect(combat.acquire_player_targets(player_center + Vector3.UP * 5.0, Vector3.DOWN, sword_profile).is_empty(), "vertical cursor ray produced a planar sweep aim")
	_expect(combat.acquire_player_targets(player_center, Vector3.ZERO, sword_profile).is_empty(), "zero cursor ray produced sweep targets")
	_expect(actors[3].runtime_id not in forward_ids and actors[4].runtime_id not in forward_ids, "sweep accepted a target beyond a ±60-degree boundary")
	_expect(actors[5].runtime_id not in forward_ids, "sweep accepted a target behind the player")
	await _cleanup(combat, coordinator, player, fixture["camera"] as Camera3D)

func _test_full_circle_directionless(world: VoxelWorld, sword_profile: MeleeAttackProfile) -> void:
	var fixture := _make_combat_fixture(world, 4, 0, 8018)
	var coordinator := fixture["coordinator"] as WorldEntityCoordinator
	var combat := fixture["combat"] as MeleeCombatCoordinator
	var player := fixture["player"] as PlayerMotor
	var actors := _get_sorted_actors(coordinator)
	_expect(actors.size() == 4, "full-circle fixture did not spawn four zombies")
	if actors.size() != 4:
		await _cleanup(combat, coordinator, player, fixture["camera"] as Camera3D)
		return
	var profile := sword_profile.duplicate(true) as MeleeAttackProfile
	profile.id = &"full_circle_test"
	profile.sweep_degrees = 360.0
	_expect(profile.validate("full_circle_test"), "full-circle profile was invalid")
	var angles: Array[float] = [0.0, 90.0, 180.0, -90.0]
	for index in range(actors.size()):
		_place_at_angle(actors[index], player.global_position, angles[index], 1.5)
	coordinator.tick(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	var player_center := player.global_position + Vector3.UP * (player.player_height * 0.5)
	var ray_origin := player_center + Vector3.UP * 5.0
	var ray_direction := Vector3.DOWN
	var locked_ids := combat.acquire_player_targets(ray_origin, ray_direction, profile)
	_expect(locked_ids == _active_ids(actors), "vertical cursor ray did not lock every full-circle target")
	var contact_count_before := _contacts.size()
	_expect(combat.try_commit_player_contacts(locked_ids, ray_origin, ray_direction, profile, &"copper_sword"), "directionless full-circle contacts did not commit")
	_expect(_contacts.size() == contact_count_before + actors.size(), "full-circle sweep did not emit one contact per target")
	for index in range(actors.size()):
		_expect(_contacts[contact_count_before + index].target_runtime_id == actors[index].runtime_id, "full-circle contacts were not emitted in runtime-ID order")
		_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(actors[index].runtime_id), 64.0), "full-circle target took incorrect damage")
	await _cleanup(combat, coordinator, player, fixture["camera"] as Camera3D)

func _test_overlapping_and_vertical_geometry(world: VoxelWorld, sword_profile: MeleeAttackProfile) -> void:
	var fixture := _make_combat_fixture(world, 2, 0, 8017)
	var coordinator := fixture["coordinator"] as WorldEntityCoordinator
	var combat := fixture["combat"] as MeleeCombatCoordinator
	var player := fixture["player"] as PlayerMotor
	var actors := _get_sorted_actors(coordinator)
	_expect(actors.size() == 2, "overlap-geometry fixture did not spawn two zombies")
	if actors.size() != 2:
		await _cleanup(combat, coordinator, player, fixture["camera"] as Camera3D)
		return
	var player_center := player.global_position + Vector3.UP * (player.player_height * 0.5)
	actors[0].global_position = player.global_position + Vector3(0.2, 0.0, 0.0)
	actors[1].global_position = player.global_position + Vector3.UP * 1.2
	coordinator.tick(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	_expect(actors[0].get_world_bounds().has_point(player_center), "overlap target bounds did not contain the player center")
	var overlap_offset := actors[0].get_world_bounds().get_center() - player_center
	var vertical_offset := actors[1].get_world_bounds().get_center() - player_center
	_expect(not Vector2(overlap_offset.x, overlap_offset.z).is_zero_approx(), "overlap target did not retain a planar center offset")
	_expect(Vector2(vertical_offset.x, vertical_offset.z).is_zero_approx() and not is_zero_approx(vertical_offset.y), "vertical target did not have zero planar displacement")
	var ray := _orthographic_ray(player, Vector2(1.0, 0.0))
	var locked_ids := combat.acquire_player_targets(ray[0], ray[1], sword_profile)
	_expect(locked_ids == [actors[0].runtime_id], "sweep did not distinguish overlapping planar and vertically aligned targets")
	var contact_count_before := _contacts.size()
	_expect(combat.try_commit_player_contacts(locked_ids, ray[0], ray[1], sword_profile, &"copper_sword"), "overlapping target contact did not commit")
	_expect(_contacts.size() == contact_count_before + 1 and is_equal_approx(coordinator.get_runtime().get_current_hp(actors[0].runtime_id), 64.0), "overlapping target did not take one full hit")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(actors[1].runtime_id), 80.0), "vertically aligned zero-planar target took damage")
	await _cleanup(combat, coordinator, player, fixture["camera"] as Camera3D)

func _test_sweep_reach_and_locking(world: VoxelWorld, sword_profile: MeleeAttackProfile) -> void:
	var fixture := _make_combat_fixture(world, 2, 0, 8013)
	var coordinator := fixture["coordinator"] as WorldEntityCoordinator
	var combat := fixture["combat"] as MeleeCombatCoordinator
	var player := fixture["player"] as PlayerMotor
	var actors := _get_sorted_actors(coordinator)
	_expect(actors.size() == 2, "sweep-reach fixture did not spawn two zombies")
	if actors.size() != 2:
		await _cleanup(combat, coordinator, player, fixture["camera"] as Camera3D)
		return
	var half_width := actors[0].definition.body_width * 0.5
	var exact_center_distance := sword_profile.reach + half_width
	actors[0].global_position = Vector3(player.global_position.x, FEET_Y, player.global_position.z - exact_center_distance)
	actors[1].global_position = Vector3(player.global_position.x, FEET_Y, player.global_position.z - exact_center_distance - 0.01)
	coordinator.tick(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	var ray := _orthographic_ray(player, Vector2(0.0, -1.0))
	var locked_ids := combat.acquire_player_targets(ray[0], ray[1], sword_profile)
	_expect(locked_ids == [actors[0].runtime_id], "sweep did not distinguish exact reach from beyond reach")
	var contact_count_before := _contacts.size()
	_expect(combat.try_commit_player_contacts(locked_ids, ray[0], ray[1], sword_profile, &"copper_sword"), "target at exact reach did not commit")
	_expect(_contacts.size() == contact_count_before + 1 and is_equal_approx(coordinator.get_runtime().get_current_hp(actors[0].runtime_id), 64.0), "exact-reach contact applied incorrectly")
	locked_ids = combat.acquire_player_targets(ray[0], ray[1], sword_profile)
	actors[0].global_position.z -= 0.02
	actors[1].global_position = Vector3(player.global_position.x, FEET_Y, player.global_position.z - 1.0)
	contact_count_before = _contacts.size()
	_expect(not combat.try_commit_player_contacts(locked_ids, ray[0], ray[1], sword_profile, &"copper_sword"), "contact accepted a locked target that moved beyond reach")
	_expect(_contacts.size() == contact_count_before, "moved-beyond target emitted a contact")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(actors[0].runtime_id), 64.0), "moved-beyond target took damage")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(actors[1].runtime_id), 80.0), "post-start entrant was hit without being locked")
	actors[0].global_position = Vector3(player.global_position.x, FEET_Y, player.global_position.z - exact_center_distance)
	actors[1].global_position = Vector3(player.global_position.x, FEET_Y, player.global_position.z + 1.0)
	coordinator.tick(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	locked_ids = combat.acquire_player_targets(ray[0], ray[1], sword_profile)
	player.global_position += Vector3.RIGHT * 4.0
	contact_count_before = _contacts.size()
	_expect(not combat.try_commit_player_contacts(locked_ids, ray[0], ray[1], sword_profile, &"copper_sword"), "contact accepted after the player moved beyond reach")
	_expect(_contacts.size() == contact_count_before and is_equal_approx(coordinator.get_runtime().get_current_hp(actors[0].runtime_id), 64.0), "player movement did not reject the locked contact")
	await _cleanup(combat, coordinator, player, fixture["camera"] as Camera3D)

func _test_independent_contact_revalidation(world: VoxelWorld, sword_profile: MeleeAttackProfile) -> void:
	var fixture := _make_combat_fixture(world, 5, 0, 8014)
	var coordinator := fixture["coordinator"] as WorldEntityCoordinator
	var combat := fixture["combat"] as MeleeCombatCoordinator
	var player := fixture["player"] as PlayerMotor
	var actors := _get_sorted_actors(coordinator)
	_expect(actors.size() == 5, "contact-revalidation fixture did not spawn five zombies")
	if actors.size() != 5:
		await _cleanup(combat, coordinator, player, fixture["camera"] as Camera3D)
		return
	_place_at_angle(actors[0], player.global_position, -50.0, 1.8)
	_place_at_angle(actors[1], player.global_position, -10.0, 1.4)
	_place_at_angle(actors[2], player.global_position, 30.0, 2.0)
	_place_at_angle(actors[3], player.global_position, -30.0, 2.0)
	_place_at_angle(actors[4], player.global_position, 180.0, 1.5)
	coordinator.tick(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	var ray := _orthographic_ray(player, Vector2(0.0, -1.0))
	var locked_ids := combat.acquire_player_targets(ray[0], ray[1], sword_profile)
	var expected_locked: Array[int] = [actors[0].runtime_id, actors[1].runtime_id, actors[2].runtime_id, actors[3].runtime_id]
	_expect(locked_ids == expected_locked, "revalidation setup did not lock its four initial targets")
	var stale_runtime_id := actors[0].runtime_id
	actors[0].global_position = player.global_position + Vector3(WorldEntityCoordinator.DESPAWN_DISTANCE + 1.0, 0.0, 0.0)
	coordinator.tick(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	actors[1].global_position = Vector3(player.global_position.x, FEET_Y, player.global_position.z + 1.5)
	actors[4].global_position = Vector3(player.global_position.x, FEET_Y, player.global_position.z - 1.0)
	world.restore_block_edits({Vector3i(1, int(FEET_Y), -1): BlockId.Type.STONE}, {})
	var contact_count_before := _contacts.size()
	_expect(combat.try_commit_player_contacts(locked_ids, ray[0], ray[1], sword_profile, &"copper_sword"), "valid target did not commit beside stale, moved, and occluded targets")
	_expect(_contacts.size() == contact_count_before + 1, "independent revalidation committed the wrong number of targets")
	_expect(_contacts.back().target_runtime_id == actors[3].runtime_id, "independent revalidation committed the wrong target")
	_expect(coordinator.get_runtime().get_actor(stale_runtime_id) == null, "stale-target setup did not despawn its actor")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(actors[1].runtime_id), 80.0), "moved-out target took damage")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(actors[2].runtime_id), 80.0), "newly occluded target took damage")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(actors[3].runtime_id), 64.0), "visible locked target took incorrect damage")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(actors[4].runtime_id), 80.0), "post-start entrant took damage")
	_expect(not combat.try_commit_player_contacts(_single_target(stale_runtime_id), ray[0], ray[1], sword_profile, &"copper_sword"), "all-stale contact command reported success")
	world.restore_block_edits({}, {})
	await _cleanup(combat, coordinator, player, fixture["camera"] as Camera3D)

func _test_uncapped_mixed_damage(world: VoxelWorld, sword_profile: MeleeAttackProfile) -> void:
	var fixture := _make_combat_fixture(world, 3, 3, 8015)
	var coordinator := fixture["coordinator"] as WorldEntityCoordinator
	var combat := fixture["combat"] as MeleeCombatCoordinator
	var player := fixture["player"] as PlayerMotor
	var player_stats := fixture["player_stats"] as ActorStats
	var source_sword := load("res://items/definitions/copper_sword.tres") as ItemDefinition
	var progression_sword := source_sword.duplicate(true) as ItemDefinition
	var progression_definition := ProficiencyDefinition.new()
	progression_definition.experience_requirements = PackedFloat64Array([1000.0])
	progression_definition.slot_unlock_levels = PackedInt32Array([1])
	progression_sword.proficiency = progression_definition
	var progression_item_catalog := ItemCatalog.new()
	var progression_definitions: Array[ItemDefinition] = [progression_sword]
	progression_item_catalog.definitions = progression_definitions
	var progression_inventory := InventoryModel.new(progression_item_catalog)
	var item_proficiency := ItemProficiency.new(progression_item_catalog)
	var progression := CombatProgressionCoordinator.new()
	progression.setup(player_stats, progression_inventory, fixture["entity_catalog"] as EntityCatalog, item_proficiency)
	combat.melee_outcome_committed.connect(progression.record_melee_outcome)
	var actors := _get_sorted_actors(coordinator)
	_expect(actors.size() == 6, "mixed-damage fixture did not spawn six entities")
	if actors.size() != 6:
		await _cleanup(combat, coordinator, player, fixture["camera"] as Camera3D)
		return
	var angles: Array[float] = [-50.0, -30.0, -10.0, 10.0, 30.0, 50.0]
	var distances: Array[float] = [1.2, 1.6, 2.0, 1.2, 1.6, 2.0]
	for index in range(actors.size()):
		_place_at_angle(actors[index], player.global_position, angles[index], distances[index])
	coordinator.tick(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	var ray := _orthographic_ray(player, Vector2(0.0, -1.0))
	var locked_ids := combat.acquire_player_targets(ray[0], ray[1], sword_profile)
	_expect(locked_ids == _active_ids(actors), "uncapped sweep did not lock all six mixed targets")
	if locked_ids.size() != actors.size():
		await _cleanup(combat, coordinator, player, fixture["camera"] as Camera3D)
		return
	var unsorted_ids := locked_ids.duplicate()
	unsorted_ids.reverse()
	unsorted_ids.append(locked_ids[2])
	unsorted_ids.append(locked_ids[0])
	var contact_count_before := _contacts.size()
	var outcome_count_before := _outcomes.size()
	_expect(combat.try_commit_player_contacts(unsorted_ids, ray[0], ray[1], sword_profile, &"copper_sword"), "uncapped mixed sweep did not commit")
	_expect(_contacts.size() == contact_count_before + actors.size(), "uncapped sweep did not emit exactly one contact per unique target")
	if _contacts.size() != contact_count_before + actors.size():
		await _cleanup(combat, coordinator, player, fixture["camera"] as Camera3D)
		return
	for index in range(actors.size()):
		var contact := _contacts[contact_count_before + index]
		_expect(contact.target_runtime_id == actors[index].runtime_id, "mixed sweep contact order was not sorted by runtime ID")
		_expect(contact.world_position.is_finite() and is_equal_approx(contact.hit_direction.length(), 1.0), "mixed sweep emitted an invalid contact payload")
		var expected_hp := 20.0 if actors[index].definition.id == &"sheep" else 64.0
		_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(actors[index].runtime_id), expected_hp), "%s received incorrect full sweep damage" % actors[index].definition.id)
	var first_sweep_applied_damage := 0.0
	for outcome_index in range(outcome_count_before, _outcomes.size()):
		first_sweep_applied_damage += _outcomes[outcome_index].applied_damage
	var first_sweep_proficiency := item_proficiency.get_experience(&"copper_sword")
	_expect(is_equal_approx(first_sweep_proficiency, first_sweep_applied_damage), "first mixed sweep proficiency expected %.1f got %.1f" % [first_sweep_applied_damage, first_sweep_proficiency])
	_expect(player_stats.get_total_experience() == 0, "nonlethal mixed sweep awarded player experience")
	contact_count_before = _contacts.size()
	outcome_count_before = _outcomes.size()
	_expect(combat.try_commit_player_contacts(locked_ids, ray[0], ray[1], sword_profile, &"copper_sword"), "mixed lethal sweep did not commit")
	_expect(_contacts.size() == contact_count_before + actors.size(), "early lethal targets prevented later contacts")
	var defeated_count := 0
	for actor in actors:
		if actor.definition.id == &"sheep":
			defeated_count += 1
			_expect(coordinator.get_runtime().get_actor(actor.runtime_id) == null and coordinator.get_runtime()._retiring.has(actor.runtime_id), "lethal sheep did not retire during the multi-kill")
		else:
			_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(actor.runtime_id), 48.0), "nonlethal zombie did not take the second full-damage hit")
	_expect(defeated_count == 3 and coordinator.get_runtime().get_active_count() == 3, "mixed sweep did not produce three simultaneous kills")
	var second_sweep_applied_damage := 0.0
	for outcome_index in range(outcome_count_before, _outcomes.size()):
		second_sweep_applied_damage += _outcomes[outcome_index].applied_damage
	var expected_total_proficiency := first_sweep_applied_damage + second_sweep_applied_damage
	var total_sweep_proficiency := item_proficiency.get_experience(&"copper_sword")
	_expect(is_equal_approx(total_sweep_proficiency, expected_total_proficiency), "mixed lethal sweep proficiency expected %.1f got %.1f" % [expected_total_proficiency, total_sweep_proficiency])
	_expect(player_stats.get_total_experience() == 30, "mixed lethal sweep did not award one reward per defeated target")
	await _cleanup(combat, coordinator, player, fixture["camera"] as Camera3D)

func _test_multi_target_interactor_timing(world: VoxelWorld, sword_profile: MeleeAttackProfile) -> void:
	var fixture := _make_combat_fixture(world, 2, 0, 8016)
	var coordinator := fixture["coordinator"] as WorldEntityCoordinator
	var combat := fixture["combat"] as MeleeCombatCoordinator
	var player := fixture["player"] as PlayerMotor
	var camera := fixture["camera"] as Camera3D
	var actors := _get_sorted_actors(coordinator)
	_expect(actors.size() == 2, "interactor-timing fixture did not spawn two zombies")
	if actors.size() != 2:
		await _cleanup(combat, coordinator, player, camera)
		return
	_place_at_angle(actors[0], player.global_position, -25.0, 1.5)
	_place_at_angle(actors[1], player.global_position, 25.0, 1.5)
	coordinator.tick(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	var ray := _orthographic_ray(player, Vector2(0.0, -1.0))
	var locked_ids := combat.acquire_player_targets(ray[0], ray[1], sword_profile)
	_expect(locked_ids == _active_ids(actors), "interactor timing did not lock both targets")
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var inventory := InventoryModel.new(item_catalog)
	inventory.setup_starter()
	inventory.select_slot(3)
	var input_buffer := InputBuffer.new()
	player.interactor.setup(camera, player, inventory, input_buffer, combat, coordinator.get_runtime())
	player.interactor.bind_space(world, world)
	var sword_action := item_catalog.get_definition(&"copper_sword").primary_action as MeleeAttackActionDefinition
	player.interactor.melee_attack_action = sword_action
	player.interactor.melee_attack_timer = sword_profile.cooldown
	player.interactor.melee_attack_elapsed = 0.0
	player.interactor._melee_target_runtime_ids = locked_ids
	player.interactor._melee_contact_pending = true
	player.interactor._melee_impact_pending = true
	player.interactor._melee_source_item_id = &"copper_sword"
	player.interactor._melee_ray_origin = ray[0]
	player.interactor._melee_ray_direction = ray[1]
	var contact_count_before := _contacts.size()
	player.interactor._advance_melee_attack(sword_profile.contact_time - 0.01)
	_expect(_contacts.size() == contact_count_before, "multi-target interactor damaged before contact time")
	for actor in actors:
		_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(actor.runtime_id), 80.0), "multi-target interactor changed HP before contact time")
	player.interactor._advance_melee_attack(0.02)
	_expect(_contacts.size() == contact_count_before + 2, "multi-target interactor did not commit both targets at contact time")
	for actor in actors:
		_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(actor.runtime_id), 64.0), "multi-target interactor applied incorrect contact damage")
	player.interactor._advance_melee_attack(sword_profile.duration)
	_expect(_contacts.size() == contact_count_before + 2, "multi-target interactor repeated contacts during one swing")
	player.interactor.melee_attack_action = sword_action
	player.interactor.melee_attack_timer = sword_profile.cooldown
	player.interactor.melee_attack_elapsed = 0.0
	player.interactor._melee_target_runtime_ids = locked_ids
	player.interactor._melee_contact_pending = true
	player.interactor._melee_impact_pending = true
	player.interactor._melee_source_item_id = &"copper_sword"
	player.interactor._melee_ray_origin = ray[0]
	player.interactor._melee_ray_direction = ray[1]
	player.interactor.cancel_actions()
	_expect(not player.interactor._melee_contact_pending and not player.interactor._melee_impact_pending and player.interactor._melee_target_runtime_ids.is_empty(), "action cancellation retained locked sweep targets")
	player.interactor._advance_melee_attack(sword_profile.duration)
	_expect(_contacts.size() == contact_count_before + 2, "canceled sweep emitted pending contacts")
	for actor in actors:
		_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(actor.runtime_id), 64.0), "canceled sweep changed target HP")
	await _cleanup(combat, coordinator, player, camera)

func _test_hammer_slam(world: VoxelWorld, hammer_profile: MeleeAttackProfile) -> void:
	var fixture := _make_combat_fixture(world, 3, 0, 4404)
	var coordinator := fixture["coordinator"] as WorldEntityCoordinator
	var combat := fixture["combat"] as MeleeCombatCoordinator
	var player := fixture["player"] as PlayerMotor
	var camera := fixture["camera"] as Camera3D
	var actors := _get_sorted_actors(coordinator)
	_expect(actors.size() == 3, "hammer fixture did not spawn three zombies")
	if actors.size() != 3:
		await _cleanup(combat, coordinator, player, camera)
		return
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var inventory := InventoryModel.new(item_catalog)
	inventory.slots[0] = InventoryStack.new(&"copper_hammer", 1)
	var input_buffer := InputBuffer.new()
	player.interactor.setup(camera, player, inventory, input_buffer, combat, coordinator.get_runtime())
	player.interactor.bind_space(world, world)
	var hammer_action := item_catalog.get_definition(&"copper_hammer").primary_action as MeleeAttackActionDefinition
	player.interactor.melee_attack_action = hammer_action
	player.interactor._start_melee_attack()
	var locked_hammer_yaw := player.model_root.rotation.y
	_expect(player.interactor._melee_target_runtime_ids.is_empty(), "hammer attack locked targets before contact")
	var expected_impact := player.interactor._get_melee_impact_position(hammer_profile)
	var player_center := player.global_position + Vector3.UP * (player.player_height * 0.5)
	var impact_forward := expected_impact - player.global_position
	impact_forward.y = 0.0
	_expect(is_equal_approx(impact_forward.length(), hammer_profile.impact_origin_forward_offset), "hammer impact origin does not match its ground-contact offset")
	_expect(impact_forward.normalized().dot(player.model_root.global_transform.basis.z.normalized()) > 0.999, "hammer impact origin is not in front of the player")
	_place_at_angle(actors[0], expected_impact, -120.0, 0.0)
	_place_at_angle(actors[1], expected_impact, 0.0, 5.0)
	_place_at_angle(actors[2], player_center, 180.0, 3.4)
	var observation := EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT)
	coordinator.tick(0.0, observation, 20.0)
	var impacts: Array[Vector3] = []
	player.interactor.melee_attack_impacted.connect(func(action: MeleeAttackActionDefinition, position: Vector3):
		if action == hammer_action:
			impacts.append(position)
	)
	_place_at_angle(actors[1], expected_impact, 0.0, 3.0)
	coordinator.tick(0.0, observation, 20.0)
	var contact_count_before := _contacts.size()
	player.interactor._advance_melee_attack(hammer_profile.contact_time - 0.01)
	_expect(_contacts.size() == contact_count_before and impacts.is_empty(), "hammer slam resolved before contact time")
	player.is_sprinting = true
	player.model_root.rotation.y = wrapf(locked_hammer_yaw + 0.75, -PI, PI)
	player.interactor._advance_melee_attack(0.02)
	_expect(_contacts.size() == contact_count_before + 2, "hammer slam did not hit every enemy in its contact-time radius")
	player.interactor._update_melee_facing(0.0)
	_expect(is_equal_approx(player.model_root.rotation.y, locked_hammer_yaw), "sprinting overrode the locked hammer facing")
	player.is_sprinting = false
	var first_target_center := actors[0].get_world_bounds().get_center()
	var first_radial_offset := first_target_center - expected_impact
	first_radial_offset.y = 0.0
	var second_target_center := actors[1].get_world_bounds().get_center()
	var second_radial_offset := second_target_center - expected_impact
	second_radial_offset.y = 0.0
	var first_expected_damage := hammer_profile.calculate_damage_at_distance(10.0, 4.0, first_radial_offset.length())
	var second_expected_damage := hammer_profile.calculate_damage_at_distance(10.0, 4.0, second_radial_offset.length())
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(actors[0].runtime_id), 80.0 - first_expected_damage), "hammer slam applied incorrect distance-scaled damage to the first in-range enemy")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(actors[1].runtime_id), 80.0 - second_expected_damage), "hammer slam applied incorrect distance-scaled damage to the enemy that entered before contact")
	_expect(is_equal_approx(coordinator.get_runtime().get_current_hp(actors[2].runtime_id), 80.0), "hammer slam hit an enemy outside the contact-time radius")
	_expect(is_equal_approx(actors[0].knockback_velocity.length(), hammer_profile.knockback_speed), "hammer slam did not knock back the first enemy")
	_expect(is_equal_approx(actors[1].knockback_velocity.length(), hammer_profile.knockback_speed), "hammer slam did not knock back the second enemy")
	_expect(actors[2].knockback_velocity.is_zero_approx(), "hammer slam knocked back an out-of-range enemy")
	_expect(impacts.size() == 1 and impacts[0].is_finite(), "hammer slam did not emit one visual impact")
	if impacts.size() == 1:
		_expect(impacts[0].is_equal_approx(expected_impact), "hammer shockwave did not use the ground-contact combat origin")
	var first_distance_before_knockback := actors[0].global_position.distance_to(expected_impact)
	coordinator.tick(0.1, observation, 20.0)
	_expect(actors[0].global_position.distance_to(expected_impact) > first_distance_before_knockback, "hammer knockback did not push the enemy away from the ground contact")
	player.interactor._advance_melee_attack(hammer_profile.duration)
	_expect(_contacts.size() == contact_count_before + 2 and impacts.size() == 1, "hammer slam repeated its impact")
	await _cleanup(combat, coordinator, player, camera)

func _cleanup(combat: MeleeCombatCoordinator, coordinator: WorldEntityCoordinator, player: PlayerMotor, camera: Camera3D) -> void:
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
