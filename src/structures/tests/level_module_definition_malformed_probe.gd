extends SceneTree

func _init() -> void:
	var valid := _make_valid_module()
	var obsolete_version := valid.duplicate(true) as LevelModuleDefinition
	obsolete_version.format_version = 1
	var zero_weight := valid.duplicate(true) as LevelModuleDefinition
	zero_weight.weight = 0.0
	var infinite_weight := valid.duplicate(true) as LevelModuleDefinition
	infinite_weight.weight = INF
	var nan_weight := valid.duplicate(true) as LevelModuleDefinition
	nan_weight.weight = NAN
	var invalid_socket_direction := valid.duplicate(true) as LevelModuleDefinition
	invalid_socket_direction.sockets[0].set("direction", 99)
	var invalid_torch_direction := valid.duplicate(true) as LevelModuleDefinition
	invalid_torch_direction.torches[0].set("wall_direction", 99)
	var invalid_spawn_direction := valid.duplicate(true) as LevelModuleDefinition
	invalid_spawn_direction.spawn_marker.set("facing", 99)
	var invalid_return_direction := valid.duplicate(true) as LevelModuleDefinition
	invalid_return_direction.return_door_marker.set("facing", -1)
	var unpaired_markers := valid.duplicate(true) as LevelModuleDefinition
	unpaired_markers.return_door_marker = null
	var blocked_chest := valid.duplicate(true) as LevelModuleDefinition
	blocked_chest.cells[StructureCell.index_of(blocked_chest.chest_marker.cell, blocked_chest.size)] = BlockId.Type.STONE
	var out_of_bounds_chest := valid.duplicate(true) as LevelModuleDefinition
	out_of_bounds_chest.chest_marker.cell = Vector3i(-1, 1, 1)
	var blocked_chest_headroom := valid.duplicate(true) as LevelModuleDefinition
	blocked_chest_headroom.cells[StructureCell.index_of(blocked_chest_headroom.chest_marker.cell + Vector3i.UP, blocked_chest_headroom.size)] = BlockId.Type.STONE
	var unsupported_chest := valid.duplicate(true) as LevelModuleDefinition
	unsupported_chest.cells[StructureCell.index_of(unsupported_chest.chest_marker.cell + Vector3i.DOWN, unsupported_chest.size)] = StructureCell.AIR
	var inaccessible_chest := valid.duplicate(true) as LevelModuleDefinition
	for offset in LevelChestMarkerDefinition.HORIZONTAL_NEIGHBORS:
		var adjacent_floor := inaccessible_chest.chest_marker.cell + offset + Vector3i.DOWN
		inaccessible_chest.cells[StructureCell.index_of(adjacent_floor, inaccessible_chest.size)] = StructureCell.AIR
	var socket_chest_overlap := valid.duplicate(true) as LevelModuleDefinition
	socket_chest_overlap.chest_marker.cell = socket_chest_overlap.sockets[0].cell
	var torch_chest_overlap := valid.duplicate(true) as LevelModuleDefinition
	torch_chest_overlap.torches[0].cell = torch_chest_overlap.chest_marker.cell + Vector3i.UP
	torch_chest_overlap.torches[0].wall_direction = LevelSocketDefinition.Direction.WEST
	torch_chest_overlap.cells[StructureCell.index_of(torch_chest_overlap.torches[0].cell + Vector3i.LEFT, torch_chest_overlap.size)] = BlockId.Type.STONE
	var player_chest_overlap := valid.duplicate(true) as LevelModuleDefinition
	player_chest_overlap.spawn_marker.cell = player_chest_overlap.chest_marker.cell
	var enemy_chest_overlap := valid.duplicate(true) as LevelModuleDefinition
	enemy_chest_overlap.sockets.clear()
	var enemy_zone := LevelEnemySpawnZone.new()
	enemy_zone.zone_id = &"enemy_spawn_zone"
	enemy_zone.minimum_feet_cell = enemy_chest_overlap.chest_marker.cell
	enemy_zone.maximum_feet_cell = enemy_chest_overlap.chest_marker.cell
	enemy_chest_overlap.enemy_spawn_zones.append(enemy_zone)
	var passed := valid.validate() and is_equal_approx(valid.weight, 150.25)
	passed = not obsolete_version.validate() and passed
	passed = not zero_weight.validate() and passed
	passed = not infinite_weight.validate() and passed
	passed = not nan_weight.validate() and passed
	passed = not invalid_socket_direction.validate() and passed
	passed = not invalid_torch_direction.validate() and passed
	passed = not invalid_spawn_direction.validate() and passed
	passed = not invalid_return_direction.validate() and passed
	passed = not unpaired_markers.validate() and passed
	passed = not blocked_chest.validate() and passed
	passed = not out_of_bounds_chest.validate() and passed
	passed = not blocked_chest_headroom.validate() and passed
	passed = not unsupported_chest.validate() and passed
	passed = not inaccessible_chest.validate() and passed
	passed = not socket_chest_overlap.validate() and passed
	passed = not torch_chest_overlap.validate() and passed
	passed = not player_chest_overlap.validate() and passed
	passed = not enemy_chest_overlap.validate() and passed
	if passed:
		print("LEVEL_MODULE_DEFINITION_MALFORMED PASS")
		quit(0)
	else:
		print("LEVEL_MODULE_DEFINITION_MALFORMED FAILED")
		quit(1)

func _make_valid_module() -> LevelModuleDefinition:
	var definition := LevelModuleDefinition.new()
	definition.format_version = LevelModuleDefinition.CURRENT_FORMAT_VERSION
	definition.module_id = &"malformed_probe_module"
	definition.size = Vector3i(4, 4, 4)
	definition.weight = 150.25
	definition.cells.resize(64)
	definition.cells.fill(StructureCell.AIR)
	for y in definition.size.y:
		for x in definition.size.x:
			definition.cells[StructureCell.index_of(Vector3i(x, y, 0), definition.size)] = BlockId.Type.STONE
	for cell in [Vector3i(1, 0, 0), Vector3i(0, 0, 2), Vector3i(1, 0, 2), Vector3i(3, 0, 2), Vector3i(3, 2, 3)]:
		definition.cells[StructureCell.index_of(cell, definition.size)] = BlockId.Type.STONE
	for cell in [Vector3i(1, 1, 0), Vector3i(1, 2, 0)]:
		definition.cells[StructureCell.index_of(cell, definition.size)] = StructureCell.AIR
	var socket := LevelSocketDefinition.new()
	socket.socket_id = &"north"
	socket.cell = Vector3i(1, 1, 0)
	socket.direction = LevelSocketDefinition.Direction.NORTH
	definition.sockets.append(socket)
	var torch := LevelTorchDefinition.new()
	torch.cell = Vector3i(2, 2, 3)
	torch.wall_direction = LevelSocketDefinition.Direction.EAST
	definition.torches.append(torch)
	var spawn := LevelMarkerDefinition.new()
	spawn.cell = Vector3i(0, 1, 2)
	spawn.facing = LevelSocketDefinition.Direction.EAST
	definition.spawn_marker = spawn
	var return_marker := LevelMarkerDefinition.new()
	return_marker.cell = Vector3i(3, 1, 2)
	return_marker.facing = LevelSocketDefinition.Direction.WEST
	definition.return_door_marker = return_marker
	var chest_marker := LevelChestMarkerDefinition.new()
	chest_marker.cell = Vector3i(1, 1, 2)
	definition.chest_marker = chest_marker
	return definition
