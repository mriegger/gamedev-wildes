extends SceneTree

const TEST_RADIUS: int = 64

var _failures: int = 0

func _init():
	call_deferred("_run")

func _expect(condition: bool, message: String):
	if condition:
		return
	_failures += 1
	push_error("[entity_domain] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(20, 36, 5, 12.0, block_catalog)
	for x in range(-TEST_RADIUS, TEST_RADIUS + 1):
		for z in range(-TEST_RADIUS, TEST_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = 1
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _always_ready(_position: Vector3) -> bool:
	return true

func _run():
	var catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	_expect(catalog != null, "entity catalog did not load")
	_expect(catalog.validate(), "entity catalog failed validation")
	_expect(catalog.has_definition(&"zombie"), "zombie definition is missing")
	_expect(catalog.has_definition(&"sheep"), "sheep definition is missing")
	_expect(catalog.has_definition(&"bird"), "bird definition is missing")
	_expect(catalog.has_definition(&"skeleton"), "Skeleton definition is missing")
	_expect(catalog.has_definition(&"stone_golem"), "Stone Golem definition is missing")
	var zombie := catalog.get_definition(&"zombie")
	_expect(zombie.id == &"zombie", "zombie ID changed")
	_expect(zombie.ambient_spawn_phase == EntityDefinition.SpawnPhase.NIGHT, "zombie is not night-spawned")
	_expect(zombie.ambient_max_active == 6, "zombie population cap is not six")
	_expect(zombie.stats_definition != null and zombie.stats_definition.validate(), "zombie combat stats are invalid")
	_expect(is_equal_approx(zombie.stats_definition.maximum_hp, 80.0), "zombie maximum HP is not 80")
	_expect(is_equal_approx(zombie.stats_definition.defense, 4.0), "zombie defense is not 4")
	_expect(is_equal_approx(zombie.stats_definition.strength, 5.0), "zombie strength is not 5")
	var slash := load("res://combat/damage/types/slash.tres") as DamageTypeDefinition
	var blunt := load("res://combat/damage/types/blunt.tres") as DamageTypeDefinition
	var pierce := load("res://combat/damage/types/pierce.tres") as DamageTypeDefinition
	_expect(slash.validate(slash.resource_path) and blunt.validate(blunt.resource_path) and pierce.validate(pierce.resource_path), "physical damage type definitions are invalid")
	var damage_type_catalog := load("res://combat/damage/damage_type_catalog.tres") as DamageTypeCatalog
	_expect(damage_type_catalog != null and damage_type_catalog.validate(), "damage type catalog failed validation")
	_expect(damage_type_catalog.definitions.size() == 3, "damage type catalog does not register three physical types")
	_expect(damage_type_catalog.has_definition(slash) and damage_type_catalog.has_definition(blunt) and damage_type_catalog.has_definition(pierce), "damage type catalog is missing a canonical physical type")
	_expect(zombie.get_damage_response(slash) == DamageAffinityDefinition.Response.WEAK, "zombie slash weakness is missing")
	_expect(zombie.get_damage_response(blunt) == DamageAffinityDefinition.Response.NEUTRAL, "zombie blunt response is not neutral")
	_expect(zombie.get_damage_response(pierce) == DamageAffinityDefinition.Response.NEUTRAL, "zombie pierce response is not neutral")
	var sheep := catalog.get_definition(&"sheep")
	_expect(sheep.ambient_spawn_phase == EntityDefinition.SpawnPhase.DAY, "sheep is not day-spawned")
	_expect(sheep.ambient_max_active == 6, "sheep population cap is not six")
	_expect(sheep.stats_definition != null and sheep.stats_definition.validate(), "sheep combat stats are invalid")
	_expect(is_equal_approx(sheep.stats_definition.maximum_hp, 40.0), "sheep maximum HP is not 40")
	_expect(is_equal_approx(sheep.stats_definition.defense, 0.0), "sheep defense is not 0")
	_expect(is_equal_approx(sheep.stats_definition.strength, 0.0), "sheep strength is not 0")
	var skeleton := catalog.get_definition(&"skeleton")
	_expect(skeleton.id == &"skeleton", "Skeleton ID changed")
	_expect(skeleton.ambient_spawn_phase == EntityDefinition.SpawnPhase.NIGHT, "Skeleton is not night-spawned")
	_expect(skeleton.ambient_max_active == 3, "Skeleton population cap is not three")
	_expect(skeleton.ambient_spawn_floor_ids == zombie.ambient_spawn_floor_ids, "Skeleton spawn floors differ from Zombie spawn floors")
	_expect(skeleton.stats_definition != null and skeleton.stats_definition.validate(), "Skeleton combat stats are invalid")
	_expect(is_equal_approx(skeleton.stats_definition.maximum_hp, 80.0), "Skeleton maximum HP is not 80")
	_expect(is_equal_approx(skeleton.stats_definition.defense, 4.0), "Skeleton defense is not 4")
	_expect(is_equal_approx(skeleton.stats_definition.strength, 5.0), "Skeleton strength is not 5")
	_expect(skeleton.get_damage_response(slash) == DamageAffinityDefinition.Response.RESISTANT, "Skeleton slash resistance is missing")
	_expect(skeleton.get_damage_response(blunt) == DamageAffinityDefinition.Response.WEAK, "Skeleton blunt weakness is missing")
	_expect(skeleton.get_damage_response(pierce) == DamageAffinityDefinition.Response.NEUTRAL, "Skeleton pierce response is not neutral")
	_expect(skeleton.experience_reward == 10, "Skeleton experience reward is not 10")
	var stone_golem := catalog.get_definition(&"stone_golem")
	_expect(stone_golem.id == &"stone_golem", "Stone Golem ID changed")
	_expect(stone_golem.ambient_spawn_phase == EntityDefinition.SpawnPhase.NIGHT, "Stone Golem is not night-spawned")
	_expect(stone_golem.ambient_max_active == 2, "Stone Golem population cap is not two")
	_expect(stone_golem.ambient_spawn_floor_ids == zombie.ambient_spawn_floor_ids, "Stone Golem spawn floors differ from Zombie spawn floors")
	_expect(stone_golem.stats_definition != null and stone_golem.stats_definition.validate(), "Stone Golem combat stats are invalid")
	_expect(is_equal_approx(stone_golem.stats_definition.maximum_hp, 200.0), "Stone Golem maximum HP is not 200")
	_expect(is_equal_approx(stone_golem.stats_definition.defense, 10.0), "Stone Golem defense is not 10")
	_expect(is_equal_approx(stone_golem.stats_definition.strength, 10.0), "Stone Golem strength is not 10")
	var stone_golem_behavior := stone_golem.behavior as StoneGolemBehaviorDefinition
	_expect(stone_golem_behavior.punch_profile.damage_type == blunt, "Stone Golem punch is not blunt damage")
	_expect(stone_golem_behavior.slam_profile.damage_type == blunt, "Stone Golem slam is not blunt damage")
	_expect(stone_golem.get_damage_response(slash) == DamageAffinityDefinition.Response.RESISTANT, "Stone Golem slash resistance is missing")
	_expect(stone_golem.get_damage_response(blunt) == DamageAffinityDefinition.Response.NEUTRAL, "Stone Golem blunt response is not neutral")
	_expect(stone_golem.get_damage_response(pierce) == DamageAffinityDefinition.Response.RESISTANT, "Stone Golem pierce resistance is missing")
	_expect(stone_golem.experience_reward == 30, "Stone Golem experience reward is not 30")
	_expect(is_equal_approx(stone_golem.body_width, 1.2), "Stone Golem body width is not 1.2")
	_expect(is_equal_approx(stone_golem.body_height, 2.4), "Stone Golem body height is not 2.4")
	var first_zombie_stats := ActorStats.new(zombie.stats_definition)
	var second_zombie_stats := ActorStats.new(zombie.stats_definition)
	first_zombie_stats.damage(16.0)
	_expect(is_equal_approx(first_zombie_stats.current_hp, 64.0), "first zombie runtime HP did not change")
	_expect(is_equal_approx(second_zombie_stats.current_hp, 80.0), "zombie runtime stats share mutable HP")
	_expect(zombie.is_actor_compatible(), "zombie actor rejected its behavior definition")
	_expect(sheep.is_actor_compatible(), "sheep actor rejected its behavior definition")
	var bird := catalog.get_definition(&"bird")
	_expect(bird.is_actor_compatible(), "bird actor rejected its behavior definition")
	_expect(bird.ambient_spawn_phase == EntityDefinition.SpawnPhase.DAY, "bird is not day-spawned")
	_expect(bird.ambient_max_active == 4, "bird population cap is not four")
	_expect(bird.spawn_placement == EntityDefinition.SpawnPlacement.AERIAL, "bird is not aerially placed")
	_expect(bird.ambient_despawn_outside_spawn_phase, "bird does not retire at night")
	_expect(not bird.combat_targetable and bird.experience_reward == 0, "bird participates in combat progression")
	_expect(skeleton.is_actor_compatible(), "Skeleton actor rejected its behavior definition")
	_expect(stone_golem.is_actor_compatible(), "Stone Golem actor rejected its behavior definition")
	var mismatched_definition := zombie.duplicate(true) as EntityDefinition
	mismatched_definition.behavior = sheep.behavior
	_expect(not mismatched_definition.is_actor_compatible(), "zombie actor accepted sheep behavior")
	var plain_root := Node3D.new()
	var plain_scene := PackedScene.new()
	_expect(plain_scene.pack(plain_root) == OK, "plain test scene could not be packed")
	plain_root.free()
	var plain_definition := zombie.duplicate(true) as EntityDefinition
	plain_definition.actor_scene = plain_scene
	_expect(not plain_definition.is_actor_compatible(), "plain Node3D passed entity actor validation")
	var incomplete_actor := ZombieActor.new()
	var incomplete_model_root := Node3D.new()
	incomplete_model_root.name = &"ModelRoot"
	incomplete_actor.add_child(incomplete_model_root)
	incomplete_model_root.owner = incomplete_actor
	var incomplete_animation_driver := EntityAnimationDriver.new()
	incomplete_animation_driver.name = &"AnimationDriver"
	incomplete_actor.add_child(incomplete_animation_driver)
	incomplete_animation_driver.owner = incomplete_actor
	var incomplete_visual_fader := EntityVisualFader.new()
	incomplete_visual_fader.name = &"VisualFader"
	incomplete_actor.add_child(incomplete_visual_fader)
	incomplete_visual_fader.owner = incomplete_actor
	var incomplete_death_poof := EntityDeathPoof.new()
	incomplete_death_poof.name = &"DeathPoof"
	incomplete_actor.add_child(incomplete_death_poof)
	incomplete_death_poof.owner = incomplete_actor
	incomplete_actor.animation_driver_path = ^"AnimationDriver"
	incomplete_actor.visual_fader_path = ^"VisualFader"
	incomplete_actor.death_poof_path = ^"DeathPoof"
	var incomplete_scene := PackedScene.new()
	_expect(incomplete_scene.pack(incomplete_actor) == OK, "incomplete actor scene could not be packed")
	incomplete_actor.free()
	var incomplete_definition := zombie.duplicate(true) as EntityDefinition
	incomplete_definition.actor_scene = incomplete_scene
	_expect(not incomplete_definition.is_actor_compatible(), "actor without fade geometry passed validation")

	var coordinator := WorldEntityCoordinator.new()
	get_root().add_child(coordinator)
	coordinator.setup(catalog, _make_world(), 1337, _always_ready)
	coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(Vector3.ZERO, Vector3.ZERO, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	_expect(coordinator.get_runtime().get_active_count() == 1, "night tick did not spawn one zombie")
	coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(Vector3.ZERO, Vector3.ZERO, Vector3.FORWARD, Vector3.RIGHT), 12.0)
	_expect(coordinator.get_runtime().get_active_count() == 2, "day tick did not retain the zombie and spawn one sheep")
	coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(Vector3.ZERO, Vector3.ZERO, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	_expect(coordinator.get_runtime().get_active_count() == 3, "second night tick did not retain existing entities and spawn one Skeleton")
	_expect(coordinator.get_runtime().get_definition_count(&"skeleton") == 1, "night rotation did not reach the Skeleton")
	coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(Vector3.ZERO, Vector3.ZERO, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	_expect(coordinator.get_runtime().get_active_count() == 4, "third night tick did not retain existing entities and spawn one Stone Golem")
	_expect(coordinator.get_runtime().get_definition_count(&"stone_golem") == 1, "night rotation did not reach the Stone Golem")
	coordinator.tick(0.0, EntityTargetObservation.create(Vector3(1000.0, 0.0, 1000.0), Vector3(1000.0, 0.0, 1000.0), Vector3.FORWARD, Vector3.RIGHT), 12.0)
	_expect(coordinator.get_runtime().get_active_count() == 0, "distant zombie did not despawn")
	coordinator.shutdown()
	coordinator.queue_free()
	await process_frame
	await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "orphan count ended at %d" % orphan_count)
	if _failures == 0:
		print("ENTITY_DOMAIN PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("ENTITY_DOMAIN FAIL failures=%d" % _failures)
		quit(1)
