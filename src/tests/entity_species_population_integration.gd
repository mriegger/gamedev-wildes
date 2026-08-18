extends SceneTree

const FLAT_HEIGHT: int = 6
const FEET_Y: float = FLAT_HEIGHT + 1.0
const WORLD_RADIUS: int = 96
const DAY_TIME: float = 12.0
const NIGHT_TIME: float = 20.0

var _failures: int = 0
var _streaming_enabled: bool = true

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[entity_species_population_integration] FAIL: %s" % message)

func _make_flat_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
		for z in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLAT_HEIGHT
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _is_position_streamed(_position: Vector3) -> bool:
	return _streaming_enabled

func _species_counts(coordinator: WorldEntityCoordinator) -> Dictionary:
	var counts: Dictionary = {&"sheep": 0, &"zombie": 0, &"skeleton": 0, &"bird": 0, &"stone_golem": 0}
	for actor in coordinator.get_runtime().get_active_actors():
		counts[actor.definition.id] = int(counts.get(actor.definition.id, 0)) + 1
	return counts

func _runtime_id_set(coordinator: WorldEntityCoordinator) -> Dictionary:
	var ids: Dictionary = {}
	for actor in coordinator.get_runtime().get_active_actors():
		_expect(actor.runtime_id > 0, "active entity had an invalid runtime ID")
		_expect(not ids.has(actor.runtime_id), "runtime ID %d was duplicated" % actor.runtime_id)
		ids[actor.runtime_id] = true
	return ids

func _first_species(coordinator: WorldEntityCoordinator, definition_id: StringName) -> EntityActor:
	for actor in coordinator.get_runtime().get_active_actors():
		if actor.definition.id == definition_id:
			return actor
	return null

func _species_id_set(coordinator: WorldEntityCoordinator, definition_id: StringName) -> Dictionary:
	var ids: Dictionary = {}
	for actor in coordinator.get_runtime().get_active_actors():
		if actor.definition.id == definition_id:
			ids[actor.runtime_id] = true
	return ids

func _assert_catalog(catalog: EntityCatalog) -> void:
	_expect(catalog != null and catalog.validate(), "entity catalog failed validation")
	_expect(catalog.definitions.size() == 5, "entity catalog did not contain exactly five stable species")
	_expect(catalog.has_definition(&"sheep"), "stable sheep ID was missing")
	_expect(catalog.has_definition(&"zombie"), "stable zombie ID was missing")
	_expect(catalog.has_definition(&"bird"), "stable bird ID was missing")
	_expect(catalog.has_definition(&"skeleton"), "stable Skeleton ID was missing")
	_expect(catalog.has_definition(&"stone_golem"), "stable Stone Golem ID was missing")
	var sheep := catalog.get_definition(&"sheep")
	var zombie := catalog.get_definition(&"zombie")
	var bird := catalog.get_definition(&"bird")
	var skeleton := catalog.get_definition(&"skeleton")
	var stone_golem := catalog.get_definition(&"stone_golem")
	_expect(sheep.id == &"sheep" and zombie.id == &"zombie" and bird.id == &"bird" and skeleton.id == &"skeleton" and stone_golem.id == &"stone_golem", "species IDs changed")
	_expect(sheep.ambient_spawn_phase == EntityDefinition.SpawnPhase.DAY, "sheep were not day-spawned")
	_expect(zombie.ambient_spawn_phase == EntityDefinition.SpawnPhase.NIGHT, "zombies were not night-spawned")
	_expect(skeleton.ambient_spawn_phase == EntityDefinition.SpawnPhase.NIGHT, "Skeletons were not night-spawned")
	_expect(bird.ambient_spawn_phase == EntityDefinition.SpawnPhase.DAY and bird.ambient_despawn_outside_spawn_phase, "birds were not phase-bound to daytime")
	_expect(stone_golem.ambient_spawn_phase == EntityDefinition.SpawnPhase.NIGHT, "Stone Golems were not night-spawned")
	_expect(sheep.ambient_max_active == 6 and zombie.ambient_max_active == 6 and skeleton.ambient_max_active == 3 and stone_golem.ambient_max_active == 2, "ground species caps changed")
	_expect(bird.ambient_max_active == 4, "bird cap was not four")
	_expect(stone_golem.ambient_spawn_floor_ids == zombie.ambient_spawn_floor_ids, "Stone Golem spawn floors differ from Zombie spawn floors")
	_expect(is_equal_approx(stone_golem.body_width, 1.2) and is_equal_approx(stone_golem.body_height, 2.4), "Stone Golem body dimensions changed")
	_expect(stone_golem.stats_definition != null and is_equal_approx(stone_golem.stats_definition.maximum_hp, 200.0), "Stone Golem maximum HP changed")
	_expect(stone_golem.stats_definition != null and is_equal_approx(stone_golem.stats_definition.defense, 10.0), "Stone Golem defense changed")
	_expect(stone_golem.stats_definition != null and is_equal_approx(stone_golem.stats_definition.strength, 10.0), "Stone Golem strength changed")
	_expect(stone_golem.experience_reward == 30, "Stone Golem experience reward changed")

func _spawn_day_population(coordinator: WorldEntityCoordinator, player_position: Vector3) -> Dictionary:
	for _spawn in range(10):
		coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), DAY_TIME)
	var counts := _species_counts(coordinator)
	_expect(coordinator.get_runtime().get_active_count() == 10, "day population did not reach ten")
	_expect(counts[&"sheep"] == 6 and counts[&"bird"] == 4 and counts[&"zombie"] == 0 and counts[&"skeleton"] == 0 and counts[&"stone_golem"] == 0, "day population did not contain six sheep and four birds")
	var sheep_ids := _species_id_set(coordinator, &"sheep")
	var day_ids := _runtime_id_set(coordinator)
	coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), DAY_TIME)
	_expect(coordinator.get_runtime().get_active_count() == 10, "day population exceeded its species caps")
	_expect(_runtime_id_set(coordinator) == day_ids, "capped day tick replaced an existing entity")
	return sheep_ids

func _spawn_night_population(coordinator: WorldEntityCoordinator, player_position: Vector3, sheep_ids: Dictionary) -> Dictionary:
	var expected_sequence: Array[StringName] = [&"skeleton", &"stone_golem", &"zombie", &"skeleton", &"stone_golem", &"zombie"]
	for expected_id in expected_sequence:
		coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), NIGHT_TIME)
		var latest_actor: EntityActor = null
		for actor in coordinator.get_runtime().get_active_actors():
			if latest_actor == null or actor.runtime_id > latest_actor.runtime_id:
				latest_actor = actor
		_expect(latest_actor != null and latest_actor.definition.id == expected_id, "night round-robin order did not select %s" % expected_id)
	var counts := _species_counts(coordinator)
	_expect(coordinator.get_runtime().get_active_count() == 12, "night population did not reach twelve")
	_expect(counts[&"sheep"] == 6 and counts[&"zombie"] == 2 and counts[&"skeleton"] == 2 and counts[&"stone_golem"] == 2 and counts[&"bird"] == 0, "night population retained birds or did not balance hostile species")
	for runtime_id in sheep_ids:
		var actor := coordinator.get_runtime().get_actor(runtime_id)
		_expect(actor != null and actor.definition.id == &"sheep", "day sheep did not persist into night")
	return _runtime_id_set(coordinator)

func _respawn_day_birds(coordinator: WorldEntityCoordinator, player_position: Vector3) -> Dictionary:
	for _spawn in range(4):
		coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), DAY_TIME)
	var counts := _species_counts(coordinator)
	_expect(coordinator.get_runtime().get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "returning day did not reach the total population cap")
	_expect(counts[&"sheep"] == 6 and counts[&"zombie"] == 2 and counts[&"skeleton"] == 2 and counts[&"stone_golem"] == 2 and counts[&"bird"] == 4, "returning day did not restore four birds")
	return _runtime_id_set(coordinator)

func _assert_night_species_caps(catalog: EntityCatalog, world: VoxelWorld, player_position: Vector3) -> void:
	var coordinator := WorldEntityCoordinator.new()
	get_root().add_child(coordinator)
	coordinator.setup(catalog, world, 11971, _is_position_streamed)
	for _spawn in range(WorldEntityCoordinator.MAX_TOTAL_ACTIVE):
		coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), NIGHT_TIME)
	var counts := _species_counts(coordinator)
	_expect(coordinator.get_runtime().get_active_count() == 11, "night-only population did not stop at the eligible species caps")
	_expect(counts[&"zombie"] == 6 and counts[&"skeleton"] == 3 and counts[&"stone_golem"] == 2 and counts[&"sheep"] == 0, "night-only population did not fill every enemy cap fairly")
	var ids := _runtime_id_set(coordinator)
	coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), NIGHT_TIME)
	_expect(_runtime_id_set(coordinator) == ids, "capped night tick replaced an existing enemy")
	coordinator.shutdown()
	coordinator.free()

func _assert_spatial_bound(coordinator: WorldEntityCoordinator, expected_entries: int) -> void:
	var entry_count := coordinator.get_runtime()._spatial_index.get_entry_count()
	var cell_count := coordinator.get_runtime()._spatial_index.get_cell_count()
	_expect(entry_count == expected_entries, "spatial entries %d did not match active count %d" % [entry_count, expected_entries])
	_expect(entry_count <= WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "spatial index exceeded the total entity cap")
	_expect(cell_count <= expected_entries * 8, "spatial cell count %d exceeded the per-entity bound" % cell_count)

func _route_sheep_contact(coordinator: WorldEntityCoordinator, world: VoxelWorld) -> Array[Node]:
	var sheep := _first_species(coordinator, &"sheep") as SheepActor
	_expect(sheep != null, "no sheep was available for combat routing")
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as PlayerMotor
	get_root().add_child(player)
	player.global_position = Vector3(0.5, FEET_Y, 0.5)
	sheep.global_position = Vector3(1.5, FEET_Y, 0.5)
	sheep.velocity = Vector3.ZERO
	sheep.on_ground = true
	coordinator.get_runtime().tick(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT))
	var combat := MeleeCombatCoordinator.new()
	get_root().add_child(combat)
	var player_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	_expect(inventory.setup_starter(), "combat inventory setup failed")
	var inventory_loadout := InventoryTestFixture.create_loadout(inventory, player_stats)
	_expect(inventory_loadout != null and inventory_loadout.select_slot(3), "combat sword selection failed")
	combat.setup(world, player, player_stats, inventory, coordinator.get_runtime())
	combat.melee_outcome_committed.connect(coordinator.get_runtime().record_melee_outcome)
	var player_center := player.global_position + Vector3.UP * (player.player_height * 0.5)
	var target_bounds := sheep.get_world_bounds()
	var target_center := target_bounds.position + target_bounds.size * 0.5
	var aim_point := Vector3(target_center.x, player_center.y, target_center.z)
	var ray_origin := player_center + Vector3(0.0, 6.0, 5.5)
	var ray_direction := (aim_point - ray_origin).normalized()
	var prepared := combat.prepare_player_attack(inventory.create_selected_item_source(), ray_origin, ray_direction)
	var committed := combat.try_commit_player_attack(prepared)
	_expect(committed, "player contact did not commit through MeleeCombatCoordinator")
	_expect(sheep.brain.state == SheepBrain.State.FLEE, "coordinator-routed contact did not start sheep flee")
	var animation := sheep.animation_driver as SheepAnimationDriver
	animation.advance(0.01)
	_expect(animation.get_current_state() == SheepAnimationDriver.HIT, "routed contact did not play sheep hit animation")
	sheep.tick(0.05, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), Vector3.ZERO, NavigationSearchBudget.new(1))
	animation.advance(SheepAnimationDriver.HIT_SECONDS)
	_expect(animation.get_current_state() == SheepAnimationDriver.FLEE, "sheep animation did not transition from hit to flee")
	return [combat, player]

func _assert_cleanup(coordinator: WorldEntityCoordinator, player_position: Vector3) -> void:
	var distant_zombie := _first_species(coordinator, &"zombie")
	_expect(distant_zombie != null, "no zombie was available for distance cleanup")
	var distant_runtime_id := distant_zombie.runtime_id
	distant_zombie.global_position = player_position + Vector3(WorldEntityCoordinator.DESPAWN_DISTANCE + 5.0, 0.0, 0.0)
	coordinator.tick(0.0, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), NIGHT_TIME)
	_expect(coordinator.get_runtime().get_actor(distant_runtime_id) == null, "distant entity was not removed")
	_expect(coordinator.get_runtime().get_active_count() == 15, "distance cleanup removed the wrong number of entities")
	_assert_spatial_bound(coordinator, 15)
	_streaming_enabled = false
	coordinator.tick(0.0, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), NIGHT_TIME)
	_expect(coordinator.get_runtime().get_active_count() == 0, "unstreamed entities were not removed")
	_expect(coordinator.get_runtime()._spatial_index.get_entry_count() == 0, "spatial entries survived streaming cleanup")
	_expect(coordinator.get_runtime()._spatial_index.get_cell_count() == 0, "spatial cells survived streaming cleanup")

func _run() -> void:
	var catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	_assert_catalog(catalog)
	var world := _make_flat_world()
	var coordinator := WorldEntityCoordinator.new()
	get_root().add_child(coordinator)
	var player_position := Vector3(0.5, FEET_Y, 0.5)
	_assert_night_species_caps(catalog, world, player_position)
	coordinator.setup(catalog, world, 9167, _is_position_streamed)
	var sheep_ids := _spawn_day_population(coordinator, player_position)
	_spawn_night_population(coordinator, player_position, sheep_ids)
	var all_ids := _respawn_day_birds(coordinator, player_position)
	_expect(all_ids.size() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "mixed population runtime IDs were not unique")
	_assert_spatial_bound(coordinator, WorldEntityCoordinator.MAX_TOTAL_ACTIVE)
	var combat_nodes := _route_sheep_contact(coordinator, world)
	_assert_cleanup(coordinator, player_position)
	(combat_nodes[0] as MeleeCombatCoordinator).shutdown()
	coordinator.shutdown()
	for node in combat_nodes:
		node.queue_free()
	coordinator.queue_free()
	await process_frame
	await process_frame
	await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "orphan count ended at %d" % orphan_count)
	if _failures == 0:
		print("ENTITY_SPECIES_POPULATION_INTEGRATION PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("ENTITY_SPECIES_POPULATION_INTEGRATION FAIL failures=%d" % _failures)
		quit(1)
