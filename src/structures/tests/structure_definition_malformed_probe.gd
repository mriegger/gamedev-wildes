extends SceneTree

func _init() -> void:
	var valid := _make_valid_definition()
	var unversioned := valid.duplicate(true) as StructureDefinition
	unversioned.format_version = 0
	var wrong_version := valid.duplicate(true) as StructureDefinition
	wrong_version.format_version = 2
	var wrong_id := valid.duplicate(true) as StructureDefinition
	wrong_id.structure_id = &"Wrong_ID"
	var wrong_size := valid.duplicate(true) as StructureDefinition
	wrong_size.size = Vector3i(65, 1, 1)
	var wrong_count := valid.duplicate(true) as StructureDefinition
	wrong_count.cells.resize(7)
	var void_cell := valid.duplicate(true) as StructureDefinition
	void_cell.cells[0] = StructureCell.VOID
	var torch_cell := valid.duplicate(true) as StructureDefinition
	torch_cell.cells[0] = BlockId.Type.TORCH
	var water_cell := valid.duplicate(true) as StructureDefinition
	water_cell.cells[0] = BlockId.Type.WATER
	var unknown_cell := valid.duplicate(true) as StructureDefinition
	unknown_cell.cells[0] = BlockId.Type.COUNT
	var empty := valid.duplicate(true) as StructureDefinition
	empty.cells.fill(StructureCell.AIR)
	empty.torches.clear()
	var null_torch := valid.duplicate(true) as StructureDefinition
	null_torch.torches.append(null)
	var occupied_torch := valid.duplicate(true) as StructureDefinition
	occupied_torch.torches[0].cell = Vector3i.ZERO
	var out_of_bounds_torch := valid.duplicate(true) as StructureDefinition
	out_of_bounds_torch.torches[0].cell = Vector3i(2, 0, 0)
	var unsupported_torch := valid.duplicate(true) as StructureDefinition
	unsupported_torch.torches[0].support_direction = Vector3i.UP
	var missing_support := valid.duplicate(true) as StructureDefinition
	missing_support.torches[0].support_direction = Vector3i.BACK
	var duplicate_torch := valid.duplicate(true) as StructureDefinition
	duplicate_torch.torches.append(duplicate_torch.torches[0].duplicate(true))
	var valid_module := _make_valid_module()
	var unversioned_module := valid_module.duplicate(true) as LevelModuleDefinition
	unversioned_module.format_version = 0
	var vertical_zone_module := valid_module.duplicate(true) as LevelModuleDefinition
	vertical_zone_module.enemy_spawn_zones[0].maximum_feet_cell.y = 2
	var blocked_zone_module := valid_module.duplicate(true) as LevelModuleDefinition
	var blocked_cell := blocked_zone_module.enemy_spawn_zones[0].minimum_feet_cell
	blocked_zone_module.cells[StructureCell.index_of(blocked_cell, blocked_zone_module.size)] = BlockId.Type.STONE
	var duplicate_zone_module := valid_module.duplicate(true) as LevelModuleDefinition
	duplicate_zone_module.enemy_spawn_zones.append(duplicate_zone_module.enemy_spawn_zones[0].duplicate(true))
	var excessive_zone_module := valid_module.duplicate(true) as LevelModuleDefinition
	excessive_zone_module.enemy_spawn_zones.clear()
	for index in LevelModuleDefinition.MAX_ENEMY_SPAWN_ZONES + 1:
		var zone := LevelEnemySpawnZone.new()
		zone.zone_id = StringName("enemy_spawn_zone_%d" % index)
		zone.minimum_feet_cell = Vector3i(1, 1, 1)
		zone.maximum_feet_cell = Vector3i(1, 1, 1)
		excessive_zone_module.enemy_spawn_zones.append(zone)
	var passed := not unversioned.validate()
	passed = not wrong_version.validate() and passed
	passed = not wrong_id.validate() and passed
	passed = not wrong_size.validate() and passed
	passed = not wrong_count.validate() and passed
	passed = not void_cell.validate() and passed
	passed = not torch_cell.validate() and passed
	passed = not water_cell.validate() and passed
	passed = not unknown_cell.validate() and passed
	passed = not empty.validate() and passed
	passed = not null_torch.validate() and passed
	passed = not occupied_torch.validate() and passed
	passed = not out_of_bounds_torch.validate() and passed
	passed = not unsupported_torch.validate() and passed
	passed = not missing_support.validate() and passed
	passed = not duplicate_torch.validate() and passed
	passed = valid_module.validate() and passed
	passed = not unversioned_module.validate() and passed
	passed = not vertical_zone_module.validate() and passed
	passed = not blocked_zone_module.validate() and passed
	passed = not duplicate_zone_module.validate() and passed
	passed = not excessive_zone_module.validate() and passed
	if passed:
		print("STRUCTURE_DEFINITION_MALFORMED PASS")
		quit(0)
	else:
		print("STRUCTURE_DEFINITION_MALFORMED FAILED")
		quit(1)

func _make_valid_definition() -> StructureDefinition:
	var definition := StructureDefinition.new()
	definition.format_version = StructureDefinition.CURRENT_FORMAT_VERSION
	definition.structure_id = &"test_structure"
	definition.size = Vector3i(2, 2, 2)
	definition.cells.resize(8)
	definition.cells.fill(StructureCell.AIR)
	definition.cells[0] = BlockId.Type.STONE
	var torch := StructureTorchDefinition.new()
	torch.cell = Vector3i(1, 0, 0)
	torch.support_direction = Vector3i.LEFT
	definition.torches.append(torch)
	return definition

func _make_valid_module() -> LevelModuleDefinition:
	var module := LevelModuleDefinition.new()
	module.format_version = LevelModuleDefinition.CURRENT_FORMAT_VERSION
	module.module_id = &"test_module"
	module.size = Vector3i(3, 4, 3)
	module.cells.resize(module.size.x * module.size.y * module.size.z)
	module.cells.fill(StructureCell.AIR)
	for z in module.size.z:
		for x in module.size.x:
			module.cells[StructureCell.index_of(Vector3i(x, 0, z), module.size)] = BlockId.Type.STONE
	var zone := LevelEnemySpawnZone.new()
	zone.zone_id = &"enemy_spawn_zone"
	zone.minimum_feet_cell = Vector3i(1, 1, 1)
	zone.maximum_feet_cell = Vector3i(1, 1, 1)
	module.enemy_spawn_zones.append(zone)
	return module
