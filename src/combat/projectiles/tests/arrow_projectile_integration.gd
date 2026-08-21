extends SceneTree

const FLAT_HEIGHT: int = 6
const FEET_Y: float = float(FLAT_HEIGHT + 1)

var _errors: Array[String] = []
var _outcomes: Array[ProjectileOutcome] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var entity_catalog := _make_zombie_catalog()
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-40, 41):
		for z in range(-40, 41):
			world.height_map_dict[Vector2i(x, z)] = FLAT_HEIGHT
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	var coordinator := WorldEntityCoordinator.new()
	var combat := MeleeCombatCoordinator.new()
	var projectiles := ArrowProjectileRuntime.new()
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as PlayerMotor
	root.add_child(coordinator)
	root.add_child(combat)
	root.add_child(projectiles)
	root.add_child(player)
	player.global_position = Vector3(0.5, FEET_Y, 0.5)
	player.set_physics_process(false)
	player.interactor.set_physics_process(false)
	player.animation_driver.set_process(false)
	coordinator.setup(entity_catalog, world, 6017, _always_ready)
	var player_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	InventoryTestFixture.restore_slot(inventory, 0, InventoryStack.new(&"bow", 1, inventory.equipment_instance_factory.create(&"bow")))
	InventoryTestFixture.restore_slot(inventory, 1, InventoryStack.new(&"stone_arrow", 1))
	InventoryTestFixture.restore_slot(inventory, 2, InventoryStack.new(&"copper_arrow", 1))
	var item_proficiency := ItemProficiency.new(item_catalog)
	var inventory_loadout := InventoryTestFixture.create_loadout(inventory, player_stats, item_proficiency)
	_expect(inventory_loadout != null, "inventory loadout setup failed")
	combat.setup(world, player, player_stats, inventory, coordinator.get_runtime(), load("res://combat/damage/damage_type_catalog.tres") as DamageTypeCatalog)
	combat.projectile_outcome_committed.connect(_record_outcome)
	combat.projectile_outcome_committed.connect(coordinator.get_runtime().record_projectile_outcome)
	projectiles.setup(inventory, inventory_loadout, combat)
	projectiles.bind_context(world, coordinator.get_runtime())
	coordinator.tick(WorldEntityCoordinator.SPAWN_INTERVAL_SECONDS, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT), 20.0)
	var actors := coordinator.get_runtime().get_active_actors()
	_expect(actors.size() == 1, "projectile fixture did not spawn one zombie")
	if actors.size() != 1:
		await _cleanup(projectiles, combat, coordinator, player)
		_finish()
		return
	var actor := actors[0] as EntityActor
	actor.global_position = Vector3(0.5, FEET_Y, -2.5)
	coordinator.get_runtime()._spatial_index.upsert(actor.runtime_id, actor.global_position, actor.get_world_bounds())
	var bow_action := item_catalog.get_definition(&"bow").primary_action as BowDrawActionDefinition
	var stone_ammunition := projectiles.get_available_ammunition(bow_action)
	_expect(stone_ammunition != null and stone_ammunition.id == &"stone_arrow", "stone arrow was not selected first")
	_expect(inventory_loadout.handle_drop(1, InventoryModel.HOTBAR_SIZE, 1), "stone arrow could not be moved behind the hotbar for ammunition-order testing")
	var hotbar_ammunition := projectiles.get_available_ammunition(bow_action)
	_expect(hotbar_ammunition != null and hotbar_ammunition.id == &"copper_arrow", "backpack ammunition took priority over a later hotbar arrow")
	_expect(inventory_loadout.handle_drop(2, InventoryModel.HOTBAR_SIZE + 1, 1), "copper arrow could not be moved into the backpack for ammunition-order testing")
	var backpack_ammunition := projectiles.get_available_ammunition(bow_action)
	_expect(backpack_ammunition != null and backpack_ammunition.id == &"stone_arrow", "backpack ammunition did not follow first-to-last slot order")
	_expect(inventory_loadout.handle_drop(InventoryModel.HOTBAR_SIZE, 1, 1), "stone arrow could not be restored to its original hotbar slot")
	stone_ammunition = projectiles.get_available_ammunition(bow_action)
	var launch_basis := Basis(Quaternion(Vector3.UP, Vector3.FORWARD))
	var launch_transform := Transform3D(launch_basis, Vector3(0.5, FEET_Y + 0.9, 0.5))
	var half_draw_trajectory := projectiles.predict_trajectory(bow_action, stone_ammunition, 0.5, launch_transform)
	var full_draw_trajectory := projectiles.predict_trajectory(bow_action, stone_ammunition, 1.0, launch_transform)
	_expect(half_draw_trajectory.size() >= 2 and full_draw_trajectory.size() >= 2, "draw-strength trajectories were not predicted")
	_expect(full_draw_trajectory[0].is_equal_approx(launch_transform.origin), "predicted trajectory did not start at the rendered arrow")
	_expect(full_draw_trajectory[0].distance_to(full_draw_trajectory[1]) > half_draw_trajectory[0].distance_to(half_draw_trajectory[1]), "predicted trajectory did not update with draw strength")
	var bow_source := inventory.create_selected_item_source()
	_expect(projectiles.try_fire(bow_source, bow_action, stone_ammunition, 1.0, launch_transform), "full-draw stone arrow did not fire")
	projectiles.set_physics_process(false)
	_expect(inventory.get_inventory_item_count(&"stone_arrow") == 0, "fired stone arrow was not consumed")
	_expect(projectiles._projectiles.size() == 1, "fired stone arrow was not retained by the runtime")
	var projectile: Variant = projectiles._projectiles[0]
	var trail := projectile.trail as ArrowTrailView
	_expect(trail != null and not trail.visible, "fired arrow did not create an empty bounded trail")
	_expect(is_equal_approx(projectile.damage_multiplier, 1.0), "full-draw projectile did not retain full damage")
	_expect(is_equal_approx(projectile.velocity.length(), bow_action.maximum_launch_speed), "full draw did not use maximum arrow speed")
	var launch_position: Vector3 = projectile.view.global_position
	projectiles.advance_projectiles(0.04)
	_expect(projectile.view.global_position.z < launch_position.z and projectile.velocity.y < 0.0, "arrow did not follow a forward parabolic path")
	_expect(projectile.view.global_basis.y.normalized().dot(projectile.velocity.normalized()) > 0.999, "arrow did not angle along its travel direction")
	_expect(trail.visible and trail._positions.size() >= 2 and trail._positions[trail._positions.size() - 1].is_equal_approx(projectile.view.global_position), "arrow trail did not follow the flying arrow")
	var uneven_deltas := [0.011, 0.023, 0.007]
	for step_index in range(60):
		if projectile.embedded_elapsed >= 0.0:
			break
		projectiles.advance_projectiles(uneven_deltas[step_index % uneven_deltas.size()])
	_expect(projectile.embedded_elapsed >= 0.0, "arrow passed through the zombie")
	var predicted_contact := full_draw_trajectory[full_draw_trajectory.size() - 1]
	_expect(projectile.view.global_position.distance_to(predicted_contact) < 0.001, "fired arrow did not follow its predicted path to the first contact actual=%s predicted=%s distance=%.6f" % [projectile.view.global_position, predicted_contact, projectile.view.global_position.distance_to(predicted_contact)])
	_expect(trail._finishing and trail._elapsed_samples[trail._elapsed_samples.size() - 1] - trail._elapsed_samples[0] <= ArrowTrailView.TRAIL_DURATION_SECONDS + 0.000001, "embedded arrow trail retained the full flight path")
	trail._process(ArrowTrailView.FADE_SECONDS * 0.5)
	_expect(trail.visible and trail._mesh_instance.transparency > 0.0 and trail._mesh_instance.transparency < 1.0, "embedded arrow trail did not begin fading")
	trail._process(ArrowTrailView.FADE_SECONDS * 0.5)
	_expect(not trail.visible, "embedded arrow trail did not finish fading")
	_expect(_outcomes.size() == 1, "arrow collision did not commit exactly one damage outcome")
	if not _outcomes.is_empty():
		var outcome := _outcomes[0]
		_expect(outcome.source_item_id == &"bow" and outcome.contact.target_runtime_id == actor.runtime_id, "arrow outcome identifies the wrong source or target")
		var expected_damage := stone_ammunition.projectile_profile.calculate_damage(
			player_stats.get_value(&"strength"),
			coordinator.get_runtime().get_stat_value(actor.runtime_id, &"defense"),
		) * MeleeCombatCoordinator.SNEAK_ATTACK_MULTIPLIER
		_expect(is_equal_approx(outcome.applied_damage, expected_damage), "stone arrow did not apply its full-draw sneak damage")
	_expect(actor is ZombieActor and (actor as ZombieActor).brain.is_alerted(), "sneak arrow hit did not immediately aggro the zombie")
	_expect(is_equal_approx(actor.knockback_velocity.length(), 2.0), "stone arrow did not apply two knockback")
	var embedded_position: Vector3 = projectile.view.global_position
	projectiles.advance_projectiles(projectile.ammunition.projectile_profile.embedded_seconds)
	_expect(projectile.view.global_position.is_equal_approx(embedded_position), "embedded arrow moved during its one-second hold")
	projectiles.advance_projectiles(projectile.ammunition.projectile_profile.fade_seconds * 0.5)
	_expect((projectile.view.get_node("Shaft") as GeometryInstance3D).transparency > 0.0, "embedded arrow did not begin fading")
	projectiles.advance_projectiles(projectile.ammunition.projectile_profile.fade_seconds * 0.5)
	_expect(projectiles._projectiles.is_empty(), "embedded arrow did not despawn after fading")

	actor.global_position = Vector3(8.5, FEET_Y, 8.5)
	coordinator.get_runtime()._spatial_index.upsert(actor.runtime_id, actor.global_position, actor.get_world_bounds())
	var foliage_position := Vector3i(0, FLAT_HEIGHT + 1, -1)
	var block_position := Vector3i(0, FLAT_HEIGHT + 1, -2)
	_expect(VoxelWorldTestFixture.commit_place(world, foliage_position, BlockId.Type.GRASS_FOLIAGE) != null, "projectile pass-through foliage could not be placed")
	_expect(VoxelWorldTestFixture.commit_place(world, block_position, BlockId.Type.STONE) != null, "projectile collision block could not be placed")
	var copper_ammunition := projectiles.get_available_ammunition(bow_action)
	_expect(copper_ammunition != null and copper_ammunition.id == &"copper_arrow", "copper arrow was not selected after stone ammunition ran out")
	var copper_trajectory := projectiles.predict_trajectory(bow_action, copper_ammunition, 0.5, launch_transform)
	_expect(copper_trajectory.size() >= 2, "voxel-bound trajectory was not predicted")
	_expect(copper_trajectory[copper_trajectory.size() - 1].z <= float(foliage_position.z), "projectile trajectory ended on foliage at %s" % copper_trajectory[copper_trajectory.size() - 1])
	bow_source = inventory.create_selected_item_source()
	_expect(projectiles.try_fire(bow_source, bow_action, copper_ammunition, 0.5, launch_transform), "half-draw copper arrow did not fire")
	projectiles.set_physics_process(false)
	projectile = projectiles._projectiles[0]
	_expect(is_equal_approx(projectile.velocity.length(), bow_action.get_launch_speed(0.5)), "half draw did not interpolate arrow speed")
	_expect(is_equal_approx(projectile.damage_multiplier, 0.7), "half-draw projectile did not retain seventy percent damage")
	for step_index in range(60):
		if projectile.embedded_elapsed >= 0.0:
			break
		projectiles.advance_projectiles(uneven_deltas[step_index % uneven_deltas.size()])
	_expect(projectile.embedded_elapsed >= 0.0 and projectile.view.global_position.z > -2.01, "arrow did not embed at the first solid voxel")
	_expect(projectile.view.global_position.z <= float(foliage_position.z), "arrow embedded in foliage at %s" % projectile.view.global_position)
	_expect(projectile.view.global_position.is_equal_approx(copper_trajectory[copper_trajectory.size() - 1]), "voxel impact did not match the predicted trajectory endpoint")
	_expect(_outcomes.size() == 1, "voxel impact incorrectly damaged an enemy")
	_expect(inventory.get_inventory_item_count(&"copper_arrow") == 0 and projectiles.get_available_ammunition(bow_action) == null, "copper arrow was not consumed or empty ammunition was still available")
	projectiles.clear()
	await _cleanup(projectiles, combat, coordinator, player)
	_finish()

func _make_zombie_catalog() -> EntityCatalog:
	var definition := (load("res://entities/definitions/zombie.tres") as EntityDefinition).duplicate(true) as EntityDefinition
	definition.ambient_max_active = 1
	var catalog := EntityCatalog.new()
	var definitions: Array[EntityDefinition] = [definition]
	catalog.definitions = definitions
	return catalog

func _always_ready(_position: Vector3) -> bool:
	return true

func _record_outcome(outcome: ProjectileOutcome) -> void:
	_outcomes.append(outcome)

func _cleanup(projectiles: ArrowProjectileRuntime, combat: MeleeCombatCoordinator, coordinator: WorldEntityCoordinator, player: PlayerMotor) -> void:
	projectiles.unbind_context()
	projectiles.queue_free()
	combat.queue_free()
	coordinator.queue_free()
	player.queue_free()
	await process_frame
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_errors.append(message)
	push_error("[arrow_projectile_integration] FAIL: %s" % message)

func _finish() -> void:
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "orphan count ended at %d" % orphan_count)
	if _errors.is_empty():
		print("ARROW_PROJECTILE PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("ARROW_PROJECTILE FAIL %s" % str(_errors))
		quit(1)
