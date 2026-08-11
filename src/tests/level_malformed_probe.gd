extends SceneTree

func _init() -> void:
	var empty_result := LevelGenerator.new().generate(LevelCatalog.new(), &"stone_dungeon", 1, &"probe", Vector3i.ZERO)
	var source_catalog := load("res://levels/content/level_catalog.tres") as LevelCatalog
	var impossible_level := source_catalog.get_level(&"stone_dungeon").duplicate(true) as LevelDefinition
	impossible_level.minimum_module_count = 1
	impossible_level.maximum_module_count = 1
	var impossible_catalog := LevelCatalog.new()
	impossible_catalog.modules.assign(source_catalog.modules)
	impossible_catalog.levels.append(impossible_level)
	var impossible_result := LevelGenerator.new().generate(impossible_catalog, &"stone_dungeon", 1, &"probe", Vector3i.ZERO)
	var oversized_level := source_catalog.get_level(&"stone_dungeon").duplicate(true) as LevelDefinition
	oversized_level.maximum_module_count = LevelDefinition.HARD_MAX_MODULE_COUNT + 1
	var oversized_module := source_catalog.get_module(&"dungeon_start_chamber").duplicate(true) as LevelModuleDefinition
	oversized_module.size = Vector3i(LevelDefinition.HARD_MAX_EXTENT.x + 1, oversized_module.size.y, oversized_module.size.z)
	var empty_failed := not empty_result.succeeded and empty_result.failure_code == LevelGenerationResult.FailureCode.INVALID_CATALOG and empty_result.layout == null and not empty_result.failure_reason.is_empty()
	var impossible_failed := not impossible_result.succeeded and impossible_result.failure_code == LevelGenerationResult.FailureCode.INVALID_CATALOG and impossible_result.layout == null and not impossible_result.failure_reason.is_empty()
	if empty_failed and impossible_failed and not oversized_level.validate() and not oversized_module.validate():
		print("LEVEL_MALFORMED_PROBE PASS")
		quit(0)
	else:
		print("LEVEL_MALFORMED_PROBE FAILED")
		quit(1)
