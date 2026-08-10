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
	var zombie := catalog.get_definition(&"zombie")
	_expect(zombie.id == &"zombie", "zombie ID changed")
	_expect(zombie.spawn_phase == EntityDefinition.SpawnPhase.NIGHT, "zombie is not night-spawned")
	_expect(zombie.max_active == 6, "zombie population cap is not six")
	var sheep := catalog.get_definition(&"sheep")
	_expect(sheep.spawn_phase == EntityDefinition.SpawnPhase.DAY, "sheep is not day-spawned")
	_expect(sheep.max_active == 6, "sheep population cap is not six")

	var coordinator := EntityCoordinator.new()
	get_root().add_child(coordinator)
	coordinator.setup(catalog, _make_world(), 1337, _always_ready)
	coordinator.tick(EntityCoordinator.SPAWN_INTERVAL_SECONDS, Vector3.ZERO, 20.0)
	_expect(coordinator.get_active_count() == 1, "night tick did not spawn one zombie")
	coordinator.tick(EntityCoordinator.SPAWN_INTERVAL_SECONDS, Vector3.ZERO, 12.0)
	_expect(coordinator.get_active_count() == 2, "day tick did not retain the zombie and spawn one sheep")
	coordinator.tick(0.0, Vector3(1000.0, 0.0, 1000.0), 12.0)
	_expect(coordinator.get_active_count() == 0, "distant zombie did not despawn")
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
