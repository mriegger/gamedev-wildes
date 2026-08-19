extends SceneTree

var _errors: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var entity_catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var factory := EquipmentInstanceFactory.new(item_catalog, 700)
	var world_state := WorldLootState.new(item_catalog, factory)
	var entity_runtime := EntityRuntime.new()
	var coordinator := OverworldLootCoordinator.new()
	root.add_child(entity_runtime)
	root.add_child(coordinator)
	coordinator.setup(
		entity_catalog,
		item_catalog,
		factory,
		world_state,
		entity_runtime,
		load("res://loot/presentation/loot_drop_view.tscn") as PackedScene,
	)
	for loot_seed in range(10):
		entity_runtime.entity_defeated.emit(
			EntityDefeat.new(
				loot_seed + 1,
				&"zombie",
				Vector3(float(loot_seed), 0.0, 0.0),
				loot_seed,
			),
		)
	_expect(world_state.get_entry_count() > 0, "entity defeat did not reach the loot transaction")
	_expect(
		coordinator.get_child_count() == world_state.get_entry_count(),
		"world loot views did not follow committed state",
	)
	var before_sheep := world_state.get_entry_count()
	entity_runtime.entity_defeated.emit(EntityDefeat.new(20, &"sheep", Vector3.ZERO, 20))
	_expect(world_state.get_entry_count() == before_sheep, "entity without a loot pool created a drop")
	coordinator.free()
	entity_runtime.free()
	if _errors.is_empty():
		print("LOOT_INTEGRATION PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
