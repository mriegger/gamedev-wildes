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
	var counts: Dictionary = {
		&"sheep": 0,
		&"zombie": 0,
		&"skeleton": 0,
		&"bird": 0,
		&"slime_large": 0,
		&"slime_medium": 0,
		&"slime_small": 0,
		&"watcher": 0,
		&"stone_golem": 0,
		&"owl": 0,
	}
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
	_expect(catalog.definitions.size() == 10, "entity catalog did not contain all ten stable species")
	_expect(catalog.has_definition(&"sheep"), "stable sheep ID was missing")
	_expect(catalog.has_definition(&"zombie"), "stable zombie ID was missing")
	_expect(catalog.has_definition(&"bird"), "stable bird ID was missing")
	_expect(catalog.has_definition(&"skeleton"), "stable Skeleton ID was missing")
	_expect(catalog.has_definition(&"slime_large"), "stable large slime ID was missing")
	_expect(catalog.has_definition(&"slime_medium"), "stable medium slime ID was missing")
	_expect(catalog.has_definition(&"slime_small"), "stable small slime ID was missing")
	_expect(catalog.has_definition(&"watcher"), "stable Watcher ID was missing")
	_expect(catalog.has_definition(&"stone_golem"), "stable Stone Golem ID was missing")
	_expect(catalog.has_definition(&"owl"), "stable owl ID was missing")
	var sheep := catalog.get_definition(&"sheep")
	var zombie := catalog.get_definition(&"zombie")
	var bird := catalog.get_definition(&"bird")
	var skeleton := catalog.get_definition(&"skeleton")
	var slime_large := catalog.get_definition(&"slime_large")
	var slime_medium := catalog.get_definition(&"slime_medium")
	var slime_small := catalog.get_definition(&"slime_small")
	var watcher := catalog.get_definition(&"watcher")
	var stone_golem := catalog.get_definition(&"stone_golem")
	var owl := catalog.get_definition(&"owl")
	_expect(sheep.id == &"sheep" and zombie.id == &"zombie" and bird.id == &"bird" and skeleton.id == &"skeleton" and slime_large.id == &"slime_large" and slime_medium.id == &"slime_medium" and slime_small.id == &"slime_small" and watcher.id == &"watcher" and stone_golem.id == &"stone_golem" and owl.id == &"owl", "species IDs changed")
	_expect(sheep.ambient_spawn_phase == EntityDefinition.SpawnPhase.DAY, "sheep were not day-spawned")
	_expect(zombie.ambient_spawn_enabled and zombie.ambient_spawn_phase == EntityDefinition.SpawnPhase.NIGHT, "zombies were not night-spawned")
	_expect(skeleton.ambient_spawn_enabled and skeleton.ambient_spawn_phase == EntityDefinition.SpawnPhase.NIGHT, "Skeletons were not night-spawned")
	_expect(bird.ambient_spawn_phase == EntityDefinition.SpawnPhase.DAY and bird.ambient_despawn_outside_spawn_phase, "birds were not phase-bound to daytime")
	_expect(zombie.ambient_max_active == 6 and skeleton.ambient_max_active == 3, "enemy ambient caps changed")
	_expect(stone_golem.ambient_spawn_phase == EntityDefinition.SpawnPhase.NIGHT, "Stone Golems were not night-spawned")
	_expect(owl.ambient_spawn_phase == EntityDefinition.SpawnPhase.NIGHT and owl.ambient_despawn_outside_spawn_phase, "owls were not phase-bound to nighttime")
	_expect(sheep.ambient_max_active == 6 and stone_golem.ambient_max_active == 2, "ground species caps changed")
	_expect(bird.ambient_max_active == 4, "bird cap was not four")
	_expect(owl.ambient_spawn_enabled and owl.ambient_max_active == 1 and is_equal_approx(owl.ambient_spawn_weight, 45.56), "owl ambient spawning or rarity settings changed")
	_expect(is_equal_approx(owl.ambient_spawn_end_hour, 5.0), "owl dawn departure time changed")
	_expect(owl.ambient_spawn_floor_ids == [BlockId.Type.LEAVES], "owl spawn floors were not tree-only")
	_expect(slime_large.ambient_spawn_enabled and slime_large.ambient_spawn_phase == EntityDefinition.SpawnPhase.NIGHT and slime_large.ambient_max_active == 1, "large slime ambient policy changed")
	_expect(not slime_medium.ambient_spawn_enabled and not slime_small.ambient_spawn_enabled, "split descendants became ambient species")
	_expect(watcher.ambient_spawn_enabled and watcher.ambient_spawn_phase == EntityDefinition.SpawnPhase.NIGHT, "Watcher ambient phase changed")
	_expect(is_equal_approx(watcher.ambient_spawn_weight, 10.0) and watcher.ambient_max_active == 0, "Watcher ambient weight or population policy changed")
	_expect(stone_golem.ambient_spawn_phase == EntityDefinition.SpawnPhase.NIGHT and stone_golem.ambient_max_active == 2, "Stone Golem ambient policy changed")
	_expect(stone_golem.ambient_spawn_floor_ids == zombie.ambient_spawn_floor_ids, "Stone Golem spawn floors differ from Zombie spawn floors")
	_expect(is_equal_approx(stone_golem.body_width, 1.2) and is_equal_approx(stone_golem.body_height, 2.4), "Stone Golem body dimensions changed")
	_expect(stone_golem.stats_definition != null and is_equal_approx(stone_golem.stats_definition.maximum_hp, 200.0), "Stone Golem maximum HP changed")
	_expect(stone_golem.stats_definition != null and is_equal_approx(stone_golem.stats_definition.defense, 10.0), "Stone Golem defense changed")
	_expect(stone_golem.stats_definition != null and is_equal_approx(stone_golem.stats_definition.strength, 10.0), "Stone Golem strength changed")
	_expect(stone_golem.experience_reward == 30, "Stone Golem experience reward changed")
	for definition in [sheep, zombie, bird, skeleton, slime_large, stone_golem]:
		_expect(is_equal_approx(definition.ambient_spawn_weight, 100.0), "%s ambient weight changed" % definition.id)

func _spawn_until_count(coordinator: WorldEntityCoordinator, player_position: Vector3, time_of_day: float, target_count: int) -> void:
	for _attempt in range(96):
		if coordinator.get_runtime().get_active_count() >= target_count:
			return
		coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), time_of_day)

func _spawn_day_population(coordinator: WorldEntityCoordinator, player_position: Vector3) -> Dictionary:
	_spawn_until_count(coordinator, player_position, DAY_TIME, 10)
	var counts := _species_counts(coordinator)
	_expect(coordinator.get_runtime().get_active_count() == 10, "day population did not reach ten")
	_expect(counts[&"sheep"] == 6 and counts[&"bird"] == 4 and counts[&"zombie"] == 0 and counts[&"skeleton"] == 0, "day population did not contain six sheep and four birds")
	var sheep_ids := _species_id_set(coordinator, &"sheep")
	var day_ids := _runtime_id_set(coordinator)
	coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), DAY_TIME)
	_expect(coordinator.get_runtime().get_active_count() == 10, "day population exceeded its species caps")
	_expect(_runtime_id_set(coordinator) == day_ids, "capped day tick replaced an existing entity")
	return sheep_ids

func _spawn_night_population(coordinator: WorldEntityCoordinator, player_position: Vector3, sheep_ids: Dictionary) -> void:
	_spawn_until_count(coordinator, player_position, NIGHT_TIME, 12)
	var counts := _species_counts(coordinator)
	_expect(coordinator.get_runtime().get_active_count() == 12, "night population did not reach twelve")
	var night_count: int = int(counts[&"zombie"]) + int(counts[&"skeleton"]) + int(counts[&"slime_large"]) + int(counts[&"watcher"]) + int(counts[&"stone_golem"]) + int(counts[&"owl"])
	_expect(counts[&"sheep"] == 6 and counts[&"bird"] == 0 and night_count == 6, "night population retained birds or changed the seeded phase mix")
	_expect(counts[&"slime_medium"] == 0 and counts[&"slime_small"] == 0, "split descendants spawned ambiently")
	_expect(coordinator.get_runtime().get_active_lineage_count(&"slime_large") == counts[&"slime_large"], "large-slime lineage count diverged from ambient roots")
	_expect(coordinator.get_runtime().get_population_cost() <= WorldEntityCoordinator.MAX_TOTAL_POPULATION_COST, "night population exceeded weighted lineage capacity")
	for runtime_id in sheep_ids:
		var actor := coordinator.get_runtime().get_actor(runtime_id)
		_expect(actor != null and actor.definition.id == &"sheep", "day sheep did not persist into night")

func _respawn_day_birds(coordinator: WorldEntityCoordinator, player_position: Vector3) -> Dictionary:
	_spawn_until_count(coordinator, player_position, DAY_TIME, WorldEntityCoordinator.MAX_TOTAL_ACTIVE)
	var counts := _species_counts(coordinator)
	_expect(coordinator.get_runtime().get_active_count() == WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "returning day did not reach the total population cap")
	var night_count: int = int(counts[&"zombie"]) + int(counts[&"skeleton"]) + int(counts[&"slime_large"]) + int(counts[&"watcher"]) + int(counts[&"stone_golem"]) + int(counts[&"owl"])
	_expect(counts[&"sheep"] == 6 and counts[&"bird"] == 4 and night_count == 6, "returning day did not preserve night entities while restoring birds")
	_expect(coordinator.get_runtime().get_population_cost() <= WorldEntityCoordinator.MAX_TOTAL_POPULATION_COST, "returning day exceeded weighted population capacity")
	return _runtime_id_set(coordinator)
func _assert_spatial_bound(coordinator: WorldEntityCoordinator, expected_entries: int) -> void:
	var entry_count := coordinator.get_runtime()._spatial_index.get_entry_count()
	var cell_count := coordinator.get_runtime()._spatial_index.get_cell_count()
	_expect(entry_count == expected_entries, "spatial entries %d did not match active count %d" % [entry_count, expected_entries])
	_expect(entry_count <= WorldEntityCoordinator.MAX_TOTAL_ACTIVE, "spatial index exceeded the total entity cap")
	_expect(cell_count <= expected_entries * 8, "spatial cell count %d exceeded the per-entity bound" % cell_count)

func _assert_debug_population_panel(coordinator: WorldEntityCoordinator) -> void:
	var snapshot := coordinator.get_runtime().get_population_snapshot()
	_expect(int(snapshot["active"]) == 10 and int(snapshot["population_capacity"]) == WorldEntityCoordinator.MAX_TOTAL_POPULATION_COST, "population snapshot reported the wrong total")
	var panel := (load("res://entities/debug/entity_population_debug_panel.tscn") as PackedScene).instantiate() as EntityPopulationDebugPanel
	get_root().add_child(panel)
	panel.setup(Callable(coordinator.get_runtime(), "get_population_snapshot"))
	panel.show_panel()
	_expect(panel.total_label.text.begins_with("Active: 10    Cost: "), "population panel reported the wrong capacity")
	_expect("Bird: 4 (cap 4)" in panel.population_label.text and "Owl: 0 (cap 1)" in panel.population_label.text, "population panel omitted bird counts")
	panel.free()

func _route_sheep_contact(coordinator: WorldEntityCoordinator, world: VoxelWorld) -> Array[Node]:
	var sheep := _first_species(coordinator, &"sheep") as SheepActor
	_expect(sheep != null, "no sheep was available for combat routing")
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as PlayerMotor
	get_root().add_child(player)
	player.global_position = Vector3(0.5, FEET_Y, 0.5)
	sheep.global_position = Vector3(1.5, FEET_Y, 0.5)
	sheep.velocity = Vector3.ZERO
	sheep.on_ground = true
	coordinator.get_runtime().tick_gameplay(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT))
	var combat := MeleeCombatCoordinator.new()
	get_root().add_child(combat)
	var player_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	_expect(inventory.setup_starter(), "combat inventory setup failed")
	var inventory_loadout := InventoryTestFixture.create_loadout(inventory, player_stats)
	_expect(inventory_loadout != null and inventory_loadout.select_slot(3), "combat sword selection failed")
	combat.setup(world, player, player_stats, inventory, coordinator.get_runtime(), load("res://combat/damage/damage_type_catalog.tres") as DamageTypeCatalog)
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
	sheep.tick_gameplay(0.05, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), Vector3.ZERO, NavigationSearchBudget.new(1))
	animation.advance(SheepAnimationDriver.HIT_SECONDS)
	_expect(animation.get_current_state() == SheepAnimationDriver.FLEE, "sheep animation did not transition from hit to flee")
	return [combat, player]

func _assert_cleanup(coordinator: WorldEntityCoordinator, player_position: Vector3) -> void:
	var distant_actor := _first_species(coordinator, &"sheep")
	_expect(distant_actor != null, "no ambient actor was available for distance cleanup")
	var distant_runtime_id := distant_actor.runtime_id
	var active_before := coordinator.get_runtime().get_active_count()
	distant_actor.global_position = player_position + Vector3(WorldEntityCoordinator.DESPAWN_DISTANCE + 5.0, 0.0, 0.0)
	coordinator.tick(0.0, EntityTargetObservation.create(player_position, player_position, Vector3.FORWARD, Vector3.RIGHT), DAY_TIME)
	_expect(coordinator.get_runtime().get_actor(distant_runtime_id) == null, "distant entity was not removed")
	_expect(coordinator.get_runtime().get_active_count() == active_before - 1, "distance cleanup removed the wrong number of entities")
	_assert_spatial_bound(coordinator, active_before - 1)
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
	coordinator.setup(catalog, world, 9167, _is_position_streamed)
	var sheep_ids := _spawn_day_population(coordinator, player_position)
	_assert_debug_population_panel(coordinator)
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
