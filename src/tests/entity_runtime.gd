extends SceneTree

const FLOOR_Y: int = 1
const FEET_Y: float = 2.0
const TEST_RADIUS: int = 8

var _failures: int = 0
var _defeated: Array[EntityDefeat] = []
var _removed_runtime_ids: Array[int] = []
var _aggro_changes: Array[bool] = []

func _init() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[entity_runtime] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-TEST_RADIUS, TEST_RADIUS + 1):
		for z in range(-TEST_RADIUS, TEST_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLOOR_Y
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.STONE
	return world

func _request(definition_id: StringName, x: float, seed: int) -> EntitySpawnRequest:
	return EntitySpawnRequest.new(definition_id, Vector3(x, FEET_Y, 0.5), seed)

func _on_entity_defeated(defeat: EntityDefeat) -> void:
	_defeated.append(defeat)

func _on_entity_removed(runtime_id: int) -> void:
	_removed_runtime_ids.append(runtime_id)

func _on_aggro_changed(active: bool) -> void:
	_aggro_changes.append(active)

func _observation(player_position: Vector3) -> EntityTargetObservation:
	return EntityTargetObservation.create(player_position, player_position + Vector3(0.0, 4.0, 6.0), Vector3.FORWARD, Vector3.RIGHT)

func _run() -> void:
	var runtime := EntityRuntime.new()
	root.add_child(runtime)
	var catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	var world := _make_world()
	runtime.setup(catalog, world, 3, 3, EntityNavigationLimits.new(48, 2048, 2), EntityRuntime.Mode.GAMEPLAY)
	runtime.entity_defeated.connect(_on_entity_defeated)
	runtime.entity_removed.connect(_on_entity_removed)
	runtime.aggro_changed.connect(_on_aggro_changed)

	var first_batch: Array[EntitySpawnRequest] = [
		_request(&"zombie", 0.5, 101),
		_request(&"sheep", 2.5, 102),
	]
	var first_ids := runtime.try_spawn_batch(first_batch)
	_expect(first_ids == [1, 2], "valid batch did not return stable runtime IDs")
	_expect(runtime.get_active_count() == 2, "valid batch did not commit every actor")
	_expect(runtime.get_actor(2).definition.id == &"sheep", "explicit spawn incorrectly used ambient floor restrictions")
	_expect(runtime.get_hostile_positions_near(Vector3(0.5, FEET_Y, 0.5), 3.0) == PackedVector3Array([Vector3(0.5, FEET_Y, 0.5)]), "nearby hostile query included a passive entity or omitted a hostile entity")
	_expect(runtime.get_hostile_positions_near(Vector3(0.5, FEET_Y, 0.5), 0.0) == PackedVector3Array([Vector3(0.5, FEET_Y, 0.5)]), "zero-radius hostile query omitted an exact match")
	runtime.tick_gameplay(0.2, _observation(Vector3(0.5, FEET_Y, 0.5)))
	_expect(runtime.is_aggro_active(), "nearby zombie did not activate aggregate aggro")
	_expect(_aggro_changes == [true], "zombie aggro did not emit exactly one activation")
	var distant_observation := _observation(Vector3(100.5, FEET_Y, 0.5))
	runtime.tick_gameplay(2.0, distant_observation)
	runtime.tick_gameplay(0.2, distant_observation)
	_expect(not runtime.is_aggro_active(), "distant zombie retained aggregate aggro")
	_expect(_aggro_changes == [true, false], "zombie aggro clear did not emit exactly once")

	var mixed_invalid: Array[EntitySpawnRequest] = [
		_request(&"zombie", 4.5, 103),
		_request(&"missing", 6.5, 104),
	]
	_expect(runtime.try_spawn_batch(mixed_invalid).is_empty(), "mixed invalid batch was partially accepted")
	_expect(runtime.get_active_count() == 2, "rejected batch changed active ownership")
	var overlapping: Array[EntitySpawnRequest] = [
		_request(&"zombie", 4.5, 105),
		_request(&"sheep", 4.5, 106),
	]
	_expect(runtime.try_spawn_batch(overlapping).is_empty(), "pairwise-overlapping batch was accepted")
	var third_batch: Array[EntitySpawnRequest] = [_request(&"skeleton", 4.5, 107)]
	_expect(runtime.try_spawn_batch(third_batch) == [3], "rejected batch consumed a runtime ID")
	var over_capacity: Array[EntitySpawnRequest] = [_request(&"zombie", 6.5, 108)]
	_expect(runtime.try_spawn_batch(over_capacity).is_empty(), "runtime accepted a batch beyond its active cap")
	runtime.tick_gameplay(0.2, _observation(Vector3(4.5, FEET_Y, 0.5)))
	_expect(runtime.is_aggro_active(), "nearby skeleton did not activate aggregate aggro")
	_expect(_aggro_changes == [true, false, true], "skeleton aggro did not emit exactly one activation")

	var third_actor := runtime.get_actor(3)
	var original_position := third_actor.global_position
	var original_bounds := third_actor.get_world_bounds()
	_expect(not runtime.try_teleport_actor(3, runtime.get_actor(2).global_position), "strict teleport accepted an occupied destination")
	_expect(third_actor.global_position == original_position, "rejected occupied teleport moved the actor")
	_expect(runtime.get_active_runtime_ids_overlapping(original_bounds).has(3), "occupied teleport rejection lost the original spatial entry")
	_expect(not runtime.get_active_runtime_ids_overlapping(runtime.get_actor(2).get_world_bounds()).has(3), "occupied teleport rejection indexed the actor at its destination")
	var unsupported_position := Vector3(6.5, FEET_Y + 1.0, 0.5)
	var unsupported_bounds := EntitySpawnGeometry.get_bounds(third_actor.definition, unsupported_position)
	_expect(not runtime.try_teleport_actor(3, unsupported_position), "strict teleport accepted an unsupported destination")
	_expect(third_actor.global_position == original_position, "rejected unsupported teleport moved the actor")
	_expect(runtime.get_active_runtime_ids_overlapping(original_bounds).has(3), "unsupported teleport rejection lost the original spatial entry")
	_expect(not runtime.get_active_runtime_ids_overlapping(unsupported_bounds).has(3), "unsupported teleport rejection indexed the actor at its destination")
	world.height_map_dict[Vector2i(6, 0)] = FLOOR_Y + 1
	var obstructed_position := Vector3(6.5, FEET_Y, 0.5)
	var obstructed_bounds := EntitySpawnGeometry.get_bounds(third_actor.definition, obstructed_position)
	_expect(not runtime.try_teleport_actor(3, obstructed_position), "strict teleport accepted an obstructed destination")
	_expect(third_actor.global_position == original_position, "rejected obstructed teleport moved the actor")
	_expect(runtime.get_active_runtime_ids_overlapping(original_bounds).has(3), "obstructed teleport rejection lost the original spatial entry")
	_expect(not runtime.get_active_runtime_ids_overlapping(obstructed_bounds).has(3), "obstructed teleport rejection indexed the actor at its destination")
	world.height_map_dict[Vector2i(6, 0)] = FLOOR_Y
	var teleport_position := Vector3(6.5, FEET_Y, 0.5)
	_expect(runtime.try_teleport_actor(3, teleport_position), "strict teleport rejected a clear destination")
	_expect(third_actor.global_position == teleport_position, "successful teleport did not move the actor")
	_expect(not runtime.get_active_runtime_ids_overlapping(original_bounds).has(3), "successful teleport retained the old spatial entry")
	_expect(runtime.get_active_runtime_ids_overlapping(third_actor.get_world_bounds()).has(3), "successful teleport omitted the new spatial entry")
	runtime.suspend()
	_expect(not runtime.is_aggro_active(), "suspended runtime retained aggregate aggro")
	_expect(runtime.get_active_runtime_ids_for_definition(&"zombie") == [1], "suspended definition query lost active zombie runtime IDs")
	_expect(runtime.get_active_runtime_ids_for_definition(&"skeleton") == [3], "suspended definition query lost active skeleton runtime IDs")
	_expect(runtime.get_active_runtime_ids_for_definition(&"sheep") == [2], "suspended definition query returned the wrong species")
	runtime.resume()
	_expect(runtime.is_aggro_active(), "resumed runtime did not restore aggregate aggro")

	_expect(runtime.try_despawn(1), "active actor refused ordinary despawn")
	_expect(_defeated.is_empty(), "ordinary despawn emitted an entity defeat")
	_expect(_removed_runtime_ids == [1], "ordinary despawn did not emit one removal")
	_expect(runtime.try_despawn(3), "aggroed actor refused ordinary despawn")
	_expect(not runtime.is_aggro_active(), "despawned skeleton retained aggregate aggro")
	_expect(_aggro_changes == [true, false, true, false, true, false], "aggregate aggro transition sequence was incorrect")
	_expect(_removed_runtime_ids == [1, 3], "aggroed despawn did not emit one removal")
	var lethal := runtime.try_apply_damage(2, 1000.0)
	_expect(lethal != null and lethal.defeated, "lethal explicit damage was not committed")
	_expect(runtime.get_actor(2) == null, "defeated actor remained active")
	_expect(_defeated.size() == 1, "defeat did not emit exactly once")
	_expect(_removed_runtime_ids == [1, 3, 2], "lethal defeat did not emit one removal")
	if _defeated.size() == 1:
		_expect(_defeated[0].runtime_id == 2 and _defeated[0].definition_id == &"sheep", "defeat signal identified the wrong actor")
		_expect(_defeated[0].world_position == Vector3(2.5, FEET_Y, 0.5), "defeat signal lost the actor position")
		_expect(_defeated[0].loot_seed == 102, "defeat signal lost the actor seed")
	_expect(runtime.defeat_all_active() == 0, "mass defeat reported entities in an empty runtime")

	runtime.shutdown()
	_expect(_defeated.size() == 1, "shutdown emitted an entity defeat")
	_expect(_removed_runtime_ids == [1, 3, 2], "shutdown emitted an entity removal")
	runtime.setup(catalog, world, 32, 8, EntityNavigationLimits.new(48, 2048, 2), EntityRuntime.Mode.GAMEPLAY)
	var split_batch: Array[EntitySpawnRequest] = [
		_request(&"slime_large", 0.5, 201),
		_request(&"zombie", 4.5, 202),
	]
	_expect(runtime.try_spawn_batch(split_batch) == [1, 2], "mass-defeat fixture did not spawn")
	_expect(runtime.defeat_all_active() == 2, "mass defeat reported the wrong fixture count")
	_expect(runtime.get_active_count() == 0, "mass defeat allowed defeat-spawn children to survive")
	_expect(_defeated.size() == 3, "mass defeat did not emit one defeat per fixture entity")
	_expect(runtime.defeat_all_active() == 0, "mass defeat reported entities after clearing the fixture")

	runtime.shutdown()
	_expect(_defeated.size() == 3, "shutdown emitted an entity defeat")
	_expect(_removed_runtime_ids == [1, 3, 2, 1, 2], "shutdown emitted an entity removal")
	runtime.queue_free()
	await process_frame
	await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "runtime cleanup left %d orphan nodes" % orphan_count)
	if _failures == 0:
		print("ENTITY_RUNTIME PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("ENTITY_RUNTIME FAIL failures=%d" % _failures)
		quit(1)
