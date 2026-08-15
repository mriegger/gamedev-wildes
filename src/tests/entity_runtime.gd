extends SceneTree

const FLOOR_Y: int = 1
const FEET_Y: float = 2.0
const TEST_RADIUS: int = 8

var _failures: int = 0
var _defeated: Array[Dictionary] = []

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

func _on_entity_defeated(runtime_id: int, definition_id: StringName) -> void:
	_defeated.append({"runtime_id": runtime_id, "definition_id": definition_id})

func _run() -> void:
	var runtime := EntityRuntime.new()
	root.add_child(runtime)
	var catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	runtime.setup(catalog, _make_world(), 3, 3, EntityNavigationLimits.new(48, 2048, 2))
	runtime.entity_defeated.connect(_on_entity_defeated)

	var first_batch: Array[EntitySpawnRequest] = [
		_request(&"zombie", 0.5, 101),
		_request(&"sheep", 2.5, 102),
	]
	var first_ids := runtime.try_spawn_batch(first_batch)
	_expect(first_ids == [1, 2], "valid batch did not return stable runtime IDs")
	_expect(runtime.get_active_count() == 2, "valid batch did not commit every actor")
	_expect(runtime.get_actor(2).definition.id == &"sheep", "explicit spawn incorrectly used ambient floor restrictions")

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
	var third_batch: Array[EntitySpawnRequest] = [_request(&"zombie", 4.5, 107)]
	_expect(runtime.try_spawn_batch(third_batch) == [3], "rejected batch consumed a runtime ID")
	var over_capacity: Array[EntitySpawnRequest] = [_request(&"zombie", 6.5, 108)]
	_expect(runtime.try_spawn_batch(over_capacity).is_empty(), "runtime accepted a batch beyond its active cap")

	_expect(runtime.try_despawn(1), "active actor refused ordinary despawn")
	_expect(_defeated.is_empty(), "ordinary despawn emitted an entity defeat")
	var lethal := runtime.try_apply_damage(2, 1000.0)
	_expect(lethal != null and lethal.defeated, "lethal explicit damage was not committed")
	_expect(runtime.get_actor(2) == null, "defeated actor remained active")
	_expect(_defeated.size() == 1, "defeat did not emit exactly once")
	if _defeated.size() == 1:
		_expect(_defeated[0].runtime_id == 2 and _defeated[0].definition_id == &"sheep", "defeat signal identified the wrong actor")

	runtime.shutdown()
	_expect(_defeated.size() == 1, "shutdown emitted an entity defeat")
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
