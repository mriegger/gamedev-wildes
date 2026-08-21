extends SceneTree

const FLOOR_Y: int = 1
const FEET_Y: float = 2.0
const TEST_RADIUS: int = 8
const SPLIT_IMPULSE_SPEED: float = 2.5
const SPLIT_LAUNCH_VERTICAL_SPEED: float = 7.0
const SPLIT_DAMAGE_IMMUNITY_SECONDS: float = 0.25

var _failures: int = 0
var _runtime: EntityRuntime
var _defeat_snapshots: Array[Dictionary] = []

func _init() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[slime_split_integration] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-TEST_RADIUS, TEST_RADIUS + 1):
		for z in range(-TEST_RADIUS, TEST_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLOOR_Y
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.STONE
	return world

func _split_expectation(seed: int, minimum_count: int, maximum_count: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var count := rng.randi_range(minimum_count, maximum_count)
	var seeds: Array[int] = []
	for _index in count:
		seeds.append(int(rng.randi()))
	return {
		"count": count,
		"seeds": seeds,
	}

func _make_observation() -> EntityTargetObservation:
	var player_position := Vector3(100.5, FEET_Y, 100.5)
	return EntityTargetObservation.create(
		player_position,
		player_position + Vector3.UP * 2.0,
		Vector3.FORWARD,
		Vector3.RIGHT,
	)

func _sorted_active_actors(runtime: EntityRuntime) -> Array[EntityActor]:
	var actors := runtime.get_active_actors()
	actors.sort_custom(func(left: EntityActor, right: EntityActor) -> bool: return left.runtime_id < right.runtime_id)
	return actors

func _actors_with_definition(runtime: EntityRuntime, definition_id: StringName) -> Array[EntityActor]:
	var matches: Array[EntityActor] = []
	for actor in _sorted_active_actors(runtime):
		if actor.definition.id == definition_id:
			matches.append(actor)
	return matches

func _on_entity_defeated(defeat: EntityDefeat) -> void:
	_defeat_snapshots.append({
		"active_count": _runtime.get_active_count(),
		"defeat": defeat,
		"lineage_count": _runtime.get_active_lineage_count(&"slime_large"),
		"population_cost": _runtime.get_population_cost(),
	})

func _expect_latest_snapshot(
	definition_id: StringName,
	active_count: int,
	population_cost: int,
	lineage_count: int,
) -> void:
	_expect(not _defeat_snapshots.is_empty(), "defeat did not emit a transactional snapshot")
	if _defeat_snapshots.is_empty():
		return
	var snapshot: Dictionary = _defeat_snapshots.back()
	var defeat := snapshot["defeat"] as EntityDefeat
	_expect(defeat.definition_id == definition_id, "defeat snapshot identified %s instead of %s" % [defeat.definition_id, definition_id])
	_expect(int(snapshot["active_count"]) == active_count, "defeat snapshot exposed a partial active set")
	_expect(int(snapshot["population_cost"]) == population_cost, "defeat snapshot exposed partial population accounting")
	_expect(int(snapshot["lineage_count"]) == lineage_count, "defeat snapshot exposed partial lineage accounting")

func _expect_split_children(
	runtime: EntityRuntime,
	world: VoxelWorld,
	first_runtime_id: int,
	definition_id: StringName,
	parent_position: Vector3,
	parent_definition: EntityDefinition,
	expectation: Dictionary,
) -> Array[EntityActor]:
	var count := int(expectation["count"])
	var seeds := expectation["seeds"] as Array[int]
	var children: Array[EntityActor] = []
	for child_index in count:
		var child := runtime.get_actor(first_runtime_id + child_index)
		_expect(child != null, "split child %d was not committed" % child_index)
		if child == null:
			continue
		children.append(child)
		_expect(child.definition.id == definition_id, "split child %d used definition %s" % [child_index, child.definition.id])
		_expect(child.behavior_seed == seeds[child_index], "split child %d received the wrong deterministic seed" % child_index)
		var radial_offset := child.global_position - parent_position
		radial_offset.y = 0.0
		_expect(not radial_offset.is_zero_approx(), "split child %d remained beneath its parent" % child_index)
		var minimum_radius := (
			(parent_definition.body_width + child.definition.body_width) * 0.5
			+ parent_definition.defeat_spawn.child_spawn_clearance
		)
		_expect(radial_offset.length() + 0.0001 >= minimum_radius, "split child %d ignored its authored radial clearance" % child_index)
		var expected_impulse := radial_offset.normalized() * SPLIT_IMPULSE_SPEED
		_expect(child.knockback_velocity.is_equal_approx(expected_impulse), "split child %d received the wrong radial impulse" % child_index)
		_expect(is_equal_approx(child.velocity.y, SPLIT_LAUNCH_VERTICAL_SPEED), "split child %d received the wrong vertical launch speed" % child_index)
		_expect(not child.on_ground, "split child %d remained grounded during launch" % child_index)
		var slime := child as SlimeActor
		_expect(slime != null and not slime.can_attach(), "split child %d allowed attachment during launch" % child_index)
		_expect(
			not VoxelBodySolver.collides_at(
				world,
				child.global_position,
				child.definition.body_width,
				child.definition.body_height,
				false,
			),
			"split child %d intersected a solid block" % child_index,
		)
		_expect(runtime.get_active_runtime_ids_overlapping(child.get_world_bounds()).has(child.runtime_id), "split child %d was missing from the spatial index" % child_index)
	for left_index in children.size():
		for right_index in range(left_index + 1, children.size()):
			var left := children[left_index]
			var right := children[right_index]
			var planar_distance := Vector2(
				left.global_position.x - right.global_position.x,
				left.global_position.z - right.global_position.z,
			).length()
			_expect(planar_distance > 0.001, "split children %d and %d shared one radial position" % [left_index, right_index])
			_expect(not left.get_world_bounds().intersects(right.get_world_bounds()), "split children %d and %d overlapped" % [left_index, right_index])
	return children

func _expect_damage_blocked(runtime: EntityRuntime, actors: Array[EntityActor], context: String) -> void:
	for actor in actors:
		var hp_before := runtime.get_current_hp(actor.runtime_id)
		var result := runtime.try_apply_damage(actor.runtime_id, 1.0)
		_expect(result == null, "%s accepted protected damage for runtime %d" % [context, actor.runtime_id])
		_expect(is_equal_approx(runtime.get_current_hp(actor.runtime_id), hp_before), "%s changed protected HP for runtime %d" % [context, actor.runtime_id])

func _expect_damageable(runtime: EntityRuntime, actors: Array[EntityActor], context: String) -> void:
	for actor in actors:
		var hp_before := runtime.get_current_hp(actor.runtime_id)
		var result := runtime.try_apply_damage(actor.runtime_id, 1.0)
		_expect(result != null and not result.defeated, "%s rejected ordinary damage for runtime %d" % [context, actor.runtime_id])
		_expect(runtime.get_current_hp(actor.runtime_id) < hp_before, "%s did not reduce HP for runtime %d" % [context, actor.runtime_id])

func _expect_exact_split_immunity(
	runtime: EntityRuntime,
	world: VoxelWorld,
	actors: Array[EntityActor],
	context: String,
) -> void:
	var launch_positions: Array[Vector3] = []
	var launch_directions: Array[Vector3] = []
	for actor in actors:
		launch_positions.append(actor.global_position)
		launch_directions.append(actor.knockback_velocity.normalized())
	_expect_damage_blocked(runtime, actors, "%s immediate" % context)
	runtime.tick_gameplay(SPLIT_DAMAGE_IMMUNITY_SECONDS * 0.5, _make_observation())
	for index in actors.size():
		var actor := actors[index]
		var displacement := actor.global_position - launch_positions[index]
		var planar_displacement := Vector3(displacement.x, 0.0, displacement.z)
		_expect(displacement.y > 0.0, "%s child %d did not rise during launch" % [context, actor.runtime_id])
		_expect(planar_displacement.dot(launch_directions[index]) > 0.0, "%s child %d did not move outward" % [context, actor.runtime_id])
		_expect(planar_displacement.normalized().is_equal_approx(launch_directions[index]), "%s child %d launch was steered by navigation or separation" % [context, actor.runtime_id])
		_expect(not VoxelBodySolver.collides_at(world, actor.global_position, actor.definition.body_width, actor.definition.body_height, false), "%s child %d entered a voxel during launch" % [context, actor.runtime_id])
		_expect(not (actor as SlimeActor).can_attach(), "%s child %d allowed attachment before landing" % [context, actor.runtime_id])
	_expect_damage_blocked(runtime, actors, "%s midpoint" % context)
	runtime.tick_gameplay(SPLIT_DAMAGE_IMMUNITY_SECONDS * 0.5, _make_observation())
	for actor in actors:
		_expect(not actor.on_ground and not (actor as SlimeActor).can_attach(), "%s child %d ended launch before landing" % [context, actor.runtime_id])
	_expect_damageable(runtime, actors, "%s boundary" % context)

func _test_ordinary_spawn_is_damageable(catalog: EntityCatalog) -> void:
	var runtime := EntityRuntime.new()
	root.add_child(runtime)
	runtime.setup(catalog, _make_world(), 32, 16, EntityNavigationLimits.new(48, 2048, 2), EntityRuntime.Mode.GAMEPLAY)
	var runtime_ids := runtime.try_spawn_batch([
		EntitySpawnRequest.new(&"slime_small", Vector3(0.5, FEET_Y, 0.5), 9001),
	])
	_expect(runtime_ids == [1], "ordinary slime spawn fixture was rejected")
	if runtime_ids == [1]:
		var actor := runtime.get_actor(1)
		if actor != null:
			_expect_damageable(runtime, [actor], "ordinary spawn")
	runtime.shutdown()
	runtime.queue_free()
	await process_frame

func _test_low_ceiling_launch(catalog: EntityCatalog) -> void:
	var world := _make_world()
	world.restore_block_edits({Vector3i(0, int(FEET_Y) + 1, 0): BlockId.Type.STONE}, {})
	var runtime := EntityRuntime.new()
	root.add_child(runtime)
	runtime.setup(catalog, world, 32, 16, EntityNavigationLimits.new(48, 2048, 2), EntityRuntime.Mode.GAMEPLAY)
	var runtime_ids := runtime.try_spawn_batch([
		EntitySpawnRequest.new(&"slime_small", Vector3(0.5, FEET_Y, 0.5), 9002),
	])
	_expect(runtime_ids == [1], "low-ceiling launch fixture was rejected")
	var actor := runtime.get_actor(1) as SlimeActor
	if actor != null:
		_expect(actor.begin_defeat_spawn_launch(Vector3.RIGHT, SPLIT_IMPULSE_SPEED, SPLIT_LAUNCH_VERTICAL_SPEED), "low-ceiling launch command was rejected")
		var ceiling_stopped_launch := false
		var landed := false
		for _frame in 120:
			runtime.tick_gameplay(1.0 / 60.0, _make_observation())
			_expect(not VoxelBodySolver.collides_at(world, actor.global_position, actor.definition.body_width, actor.definition.body_height, false), "low-ceiling launch entered a voxel")
			if not actor.on_ground and is_zero_approx(actor.velocity.y) and actor.global_position.y > FEET_Y + 0.1:
				ceiling_stopped_launch = true
				_expect(not actor.can_attach(), "ceiling impact ended attachment lockout before landing")
			if actor.on_ground:
				landed = true
				break
		_expect(ceiling_stopped_launch, "low ceiling did not stop the upward launch")
		_expect(landed and actor.can_attach(), "low-ceiling launch did not land and restore attachment")
		_expect(actor.velocity.is_zero_approx() and actor.knockback_velocity.is_zero_approx(), "low-ceiling landing retained launch velocity")
	runtime.shutdown()
	runtime.queue_free()

func _create_blocked_parent_fixture(catalog: EntityCatalog, seed: int) -> Dictionary:
	var world := _make_world()
	var runtime := EntityRuntime.new()
	root.add_child(runtime)
	runtime.setup(catalog, world, 32, 16, EntityNavigationLimits.new(48, 2048, 2), EntityRuntime.Mode.GAMEPLAY)
	var parent_position := Vector3(0.5, FEET_Y, 0.5)
	var runtime_ids := runtime.try_spawn_batch([
		EntitySpawnRequest.new(&"slime_large", parent_position, seed),
	])
	_expect(runtime_ids == [1], "blocked-parent fixture failed to spawn its parent")
	var blocking_cell := Vector3i(0, int(FEET_Y), 0)
	var placed := VoxelWorldTestFixture.commit_place(world, blocking_cell, BlockId.Type.STONE)
	_expect(placed != null, "blocked-parent fixture failed to place its obstruction")
	var parent_definition := catalog.get_definition(&"slime_large")
	_expect(
		VoxelBodySolver.collides_at(
			world,
			parent_position,
			parent_definition.body_width,
			parent_definition.body_height,
			false,
		),
		"blocked-parent fixture did not obstruct the parent body",
	)
	var expectation := _split_expectation(seed, 2, 4)
	var result := runtime.try_apply_damage(1, 1000.0)
	_expect(result != null and result.defeated, "voxel-obstructed parent did not split")
	var count := int(expectation["count"])
	_expect(runtime.get_active_count() == count, "blocked-parent split exposed a partial child set")
	_expect(runtime.get_population_cost() == count * 4, "blocked-parent split changed population accounting")
	_expect(runtime.get_active_lineage_count(&"slime_large") == 1, "blocked-parent split lost lineage ownership")
	var children := _expect_split_children(runtime, world, 2, &"slime_medium", parent_position, parent_definition, expectation)
	var positions: Array[Vector3] = []
	var impulses: Array[Vector3] = []
	for child in children:
		positions.append(child.global_position)
		impulses.append(child.knockback_velocity)
	return {
		"runtime": runtime,
		"world": world,
		"positions": positions,
		"impulses": impulses,
	}

func _test_blocked_parent_determinism(catalog: EntityCatalog) -> void:
	var first := _create_blocked_parent_fixture(catalog, 773388)
	var second := _create_blocked_parent_fixture(catalog, 773388)
	var first_positions := first["positions"] as Array[Vector3]
	var second_positions := second["positions"] as Array[Vector3]
	var first_impulses := first["impulses"] as Array[Vector3]
	var second_impulses := second["impulses"] as Array[Vector3]
	_expect(first_positions.size() == second_positions.size(), "identical blocked splits produced different child counts")
	for index in mini(first_positions.size(), second_positions.size()):
		_expect(first_positions[index].is_equal_approx(second_positions[index]), "identical blocked splits produced different position %d" % index)
		_expect(first_impulses[index].is_equal_approx(second_impulses[index]), "identical blocked splits produced different impulse %d" % index)
	var first_runtime := first["runtime"] as EntityRuntime
	var second_runtime := second["runtime"] as EntityRuntime
	var first_world := first["world"] as VoxelWorld
	var second_world := second["world"] as VoxelWorld
	var all_landed := false
	for _frame in 120:
		first_runtime.tick_gameplay(1.0 / 60.0, _make_observation())
		second_runtime.tick_gameplay(1.0 / 60.0, _make_observation())
		var first_children := _actors_with_definition(first_runtime, &"slime_medium")
		var second_children := _actors_with_definition(second_runtime, &"slime_medium")
		var landed_count := 0
		for index in mini(first_children.size(), second_children.size()):
			var first_child := first_children[index] as SlimeActor
			var second_child := second_children[index] as SlimeActor
			_expect(first_child.global_position.is_equal_approx(second_child.global_position), "identical blocked launches diverged at runtime %d" % first_child.runtime_id)
			_expect(first_child.velocity.is_equal_approx(second_child.velocity), "identical blocked launch velocity diverged at runtime %d" % first_child.runtime_id)
			_expect(not VoxelBodySolver.collides_at(first_world, first_child.global_position, first_child.definition.body_width, first_child.definition.body_height, false), "first blocked launch entered a voxel at runtime %d" % first_child.runtime_id)
			_expect(not VoxelBodySolver.collides_at(second_world, second_child.global_position, second_child.definition.body_width, second_child.definition.body_height, false), "second blocked launch entered a voxel at runtime %d" % second_child.runtime_id)
			if first_child.on_ground and second_child.on_ground:
				landed_count += 1
			else:
				_expect(not first_child.can_attach() and not second_child.can_attach(), "blocked launch allowed attachment before landing at runtime %d" % first_child.runtime_id)
		if landed_count == first_children.size() and landed_count == second_children.size():
			for child in first_children + second_children:
				_expect((child as SlimeActor).can_attach(), "landed split child remained attachment-blocked")
			all_landed = true
			break
	_expect(all_landed, "blocked split children did not finish their controlled launch")
	for fixture in [first, second]:
		var runtime := fixture["runtime"] as EntityRuntime
		runtime.shutdown()
		runtime.queue_free()

func _run() -> void:
	var catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	_expect(catalog != null and catalog.validate(), "entity catalog did not validate")
	_expect(catalog.get_maximum_lineage_capacity(&"slime_large") == 16, "large slime lineage capacity is not sixteen")
	_expect(catalog.get_maximum_lineage_capacity(&"slime_medium") == 4, "medium slime lineage capacity is not four")
	_expect(catalog.get_maximum_lineage_capacity(&"slime_small") == 1, "small slime lineage capacity is not one")
	var large_definition := catalog.get_definition(&"slime_large")
	var medium_definition := catalog.get_definition(&"slime_medium")
	_expect(is_equal_approx(large_definition.defeat_spawn.child_launch_planar_speed, SPLIT_IMPULSE_SPEED), "large split planar launch speed changed")
	_expect(is_equal_approx(large_definition.defeat_spawn.child_launch_vertical_speed, SPLIT_LAUNCH_VERTICAL_SPEED), "large split vertical launch speed changed")
	_expect(is_equal_approx(medium_definition.defeat_spawn.child_launch_planar_speed, SPLIT_IMPULSE_SPEED), "medium split planar launch speed changed")
	_expect(is_equal_approx(medium_definition.defeat_spawn.child_launch_vertical_speed, SPLIT_LAUNCH_VERTICAL_SPEED), "medium split vertical launch speed changed")
	await _test_ordinary_spawn_is_damageable(catalog)
	_test_low_ceiling_launch(catalog)

	var world := _make_world()
	_runtime = EntityRuntime.new()
	root.add_child(_runtime)
	_runtime.setup(catalog, world, 32, 16, EntityNavigationLimits.new(48, 2048, 2), EntityRuntime.Mode.GAMEPLAY)
	_runtime.entity_defeated.connect(_on_entity_defeated)
	var spawn_position := Vector3(0.5, FEET_Y, 0.5)
	var large_seed := 424242
	var large_ids := _runtime.try_spawn_batch([
		EntitySpawnRequest.new(&"slime_large", spawn_position, large_seed),
	])
	_expect(large_ids == [1], "large slime did not consume one stable runtime ID")
	_expect(_runtime.get_active_count() == 1, "large slime spawn changed the active count incorrectly")
	_expect(_runtime.get_population_cost() == 16, "large slime did not reserve its maximum lineage capacity")
	_expect(_runtime.get_active_lineage_count(&"slime_large") == 1, "large slime did not register one lineage")
	var large_expectation := _split_expectation(large_seed, 2, 4)
	var large_result := _runtime.try_apply_damage(large_ids[0], 1000.0)
	var medium_count := int(large_expectation["count"])
	var expected_active_count := medium_count
	var expected_population_cost := medium_count * 4
	_expect(large_result != null and large_result.defeated, "lethal large-slime damage did not commit")
	_expect(_runtime.get_actor(large_ids[0]) == null, "defeated large slime remained active")
	_expect(_actors_with_definition(_runtime, &"slime_medium").size() == medium_count, "large slime did not produce the deterministic medium count")
	_expect(_runtime.get_population_cost() == expected_population_cost, "large split population cost is incorrect")
	_expect(_runtime.get_active_lineage_count(&"slime_large") == 1, "large split did not preserve one lineage")
	_expect_latest_snapshot(&"slime_large", expected_active_count, expected_population_cost, 1)
	var large_children := _expect_split_children(_runtime, world, 2, &"slime_medium", spawn_position, large_definition, large_expectation)
	_expect_exact_split_immunity(_runtime, world, large_children, "large split")

	var medium_actors := _actors_with_definition(_runtime, &"slime_medium")
	var next_runtime_id := 2 + medium_count
	for medium in medium_actors:
		var expectation := _split_expectation(medium.behavior_seed, 2, 4)
		var child_count := int(expectation["count"])
		var medium_position := medium.global_position
		var result := _runtime.try_apply_damage(medium.runtime_id, 1000.0)
		expected_active_count += child_count - 1
		expected_population_cost += child_count - 4
		_expect(expected_active_count <= 16, "one large lineage exceeded sixteen active slimes")
		_expect(result != null and result.defeated, "lethal medium-slime damage did not commit")
		_expect(_runtime.get_actor(medium.runtime_id) == null, "defeated medium slime remained active")
		_expect(_runtime.get_active_count() == expected_active_count, "medium split changed the active count incorrectly")
		_expect(_runtime.get_population_cost() == expected_population_cost, "medium split changed weighted capacity incorrectly")
		_expect(_runtime.get_active_lineage_count(&"slime_large") == 1, "medium split changed the lineage count")
		_expect_latest_snapshot(&"slime_medium", expected_active_count, expected_population_cost, 1)
		_expect_split_children(_runtime, world, next_runtime_id, &"slime_small", medium_position, medium.definition, expectation)
		next_runtime_id += child_count

	var small_actors := _actors_with_definition(_runtime, &"slime_small")
	_expect(small_actors.size() == expected_active_count, "medium generation did not end with only small slimes")
	_expect(expected_population_cost == expected_active_count, "terminal generation retained excess lineage capacity")
	_expect_exact_split_immunity(_runtime, world, small_actors, "medium split")
	for small in small_actors:
		var result := _runtime.try_apply_damage(small.runtime_id, 1000.0)
		expected_active_count -= 1
		expected_population_cost -= 1
		var expected_lineage_count := 1 if expected_active_count > 0 else 0
		_expect(result != null and result.defeated, "lethal small-slime damage did not commit")
		_expect(_runtime.get_actor(small.runtime_id) == null, "terminal small slime produced a replacement")
		_expect(_runtime.get_active_count() == expected_active_count, "terminal small death changed the active count incorrectly")
		_expect(_runtime.get_population_cost() == expected_population_cost, "terminal small death changed weighted capacity incorrectly")
		_expect(_runtime.get_active_lineage_count(&"slime_large") == expected_lineage_count, "terminal small death changed the lineage count incorrectly")
		_expect_latest_snapshot(&"slime_small", expected_active_count, expected_population_cost, expected_lineage_count)

	_expect(_runtime.get_active_count() == 0, "slime lineage remained active after every terminal death")
	_expect(_runtime.get_population_cost() == 0, "slime lineage retained population cost after every terminal death")
	_expect(_runtime.get_active_lineage_count(&"slime_large") == 0, "slime lineage count remained after every terminal death")
	_test_blocked_parent_determinism(catalog)
	_runtime.shutdown()
	_runtime.queue_free()
	await process_frame
	await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "split integration left %d orphan nodes" % orphan_count)
	if _failures == 0:
		print("SLIME_SPLIT_INTEGRATION PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("SLIME_SPLIT_INTEGRATION FAIL failures=%d" % _failures)
		quit(1)
