extends SceneTree

func _init() -> void:
	var empty_result := LevelGenerator.new().generate(LevelCatalog.new(), &"stone_dungeon", 1, &"probe", Vector3i.ZERO)
	var source_catalog := load("res://levels/content/dungeons/stone/level_catalog.tres") as LevelCatalog
	var impossible_level := source_catalog.get_level(&"stone_dungeon").duplicate(true) as LevelDefinition
	impossible_level.minimum_module_count = 1
	impossible_level.maximum_module_count = 1
	var required_start := source_catalog.get_module(&"stone_entry_path").duplicate(true) as LevelModuleDefinition
	required_start.sockets[0].unused_fill_block_id = StructureCell.AIR
	var impossible_catalog := LevelCatalog.new()
	impossible_catalog.modules.assign(source_catalog.modules)
	impossible_catalog.modules[0] = required_start
	impossible_catalog.levels.append(impossible_level)
	var impossible_result := LevelGenerator.new().generate(impossible_catalog, &"stone_dungeon", 1, &"probe", Vector3i.ZERO)
	var oversized_level := source_catalog.get_level(&"stone_dungeon").duplicate(true) as LevelDefinition
	oversized_level.maximum_module_count = LevelDefinition.HARD_MAX_MODULE_COUNT + 1
	var missing_presentation := source_catalog.get_level(&"stone_dungeon").duplicate(true) as LevelDefinition
	missing_presentation.presentation = null
	var oversized_module := source_catalog.get_module(&"stone_entry_path").duplicate(true) as LevelModuleDefinition
	oversized_module.size = Vector3i(LevelDefinition.HARD_MAX_EXTENT.x + 1, oversized_module.size.y, oversized_module.size.z)
	var one_cell_socket := source_catalog.get_module(&"stone_hallway").duplicate(true) as LevelModuleDefinition
	var one_cell_upper := one_cell_socket.sockets[0].cell + Vector3i.UP
	one_cell_socket.cells[StructureCell.index_of(one_cell_upper, one_cell_socket.size)] = BlockId.Type.STONE
	var overlapping_sockets := source_catalog.get_module(&"stone_hallway").duplicate(true) as LevelModuleDefinition
	var overlapping_socket := overlapping_sockets.sockets[0].duplicate(true) as LevelSocketDefinition
	overlapping_socket.socket_id = &"north_overlap"
	overlapping_sockets.sockets.append(overlapping_socket)
	var exposed_socket := source_catalog.get_module(&"stone_hallway").duplicate(true) as LevelModuleDefinition
	var exposed_aperture := exposed_socket.socket_aperture_cells(exposed_socket.sockets[0])
	var exposed_perimeter := exposed_aperture[0]
	for aperture_cell in exposed_aperture:
		if aperture_cell.y > exposed_perimeter.y:
			exposed_perimeter = aperture_cell
	exposed_perimeter += Vector3i.UP
	exposed_socket.cells[StructureCell.index_of(exposed_perimeter, exposed_socket.size)] = StructureCell.VOID
	var invalid_socket_fill := source_catalog.get_module(&"stone_hallway").duplicate(true) as LevelModuleDefinition
	invalid_socket_fill.sockets[0].unused_fill_block_id = BlockId.Type.TORCH
	var torch_socket_overlap := source_catalog.get_module(&"stone_hallway").duplicate(true) as LevelModuleDefinition
	var overlapping_torch := LevelTorchDefinition.new()
	overlapping_torch.cell = torch_socket_overlap.sockets[0].cell + Vector3i.FORWARD
	overlapping_torch.wall_direction = LevelSocketDefinition.Direction.NORTH
	torch_socket_overlap.torches.append(overlapping_torch)
	var spawn_socket_overlap := source_catalog.get_module(&"stone_entry_path").duplicate(true) as LevelModuleDefinition
	spawn_socket_overlap.spawn_marker.cell = spawn_socket_overlap.sockets[0].cell
	var return_socket_overlap := source_catalog.get_module(&"stone_entry_path").duplicate(true) as LevelModuleDefinition
	return_socket_overlap.return_door_marker.cell = return_socket_overlap.sockets[0].cell
	var unknown_entrance := LevelEntranceDefinition.new()
	unknown_entrance.entrance_id = &"unknown"
	unknown_entrance.level_id = &"missing"
	var empty_failed := not empty_result.succeeded and empty_result.failure_code == LevelGenerationResult.FailureCode.INVALID_CATALOG and empty_result.layout == null and not empty_result.failure_reason.is_empty()
	var impossible_failed := not impossible_result.succeeded and impossible_result.failure_code == LevelGenerationResult.FailureCode.INVALID_CATALOG and impossible_result.layout == null and not impossible_result.failure_reason.is_empty()
	if empty_failed and impossible_failed and not oversized_level.validate() and not missing_presentation.validate() and not oversized_module.validate() and not one_cell_socket.validate() and not overlapping_sockets.validate() and not exposed_socket.validate() and not invalid_socket_fill.validate() and not torch_socket_overlap.validate() and not spawn_socket_overlap.validate() and not return_socket_overlap.validate() and not unknown_entrance.validate(source_catalog):
		print("LEVEL_MALFORMED_PROBE PASS")
		quit(0)
	else:
		print("LEVEL_MALFORMED_PROBE FAILED")
		quit(1)
