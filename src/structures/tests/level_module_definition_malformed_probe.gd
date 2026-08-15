extends SceneTree

func _init() -> void:
	var valid := _make_valid_module()
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
	var passed := valid.validate() and is_equal_approx(valid.weight, 150.25)
	passed = not zero_weight.validate() and passed
	passed = not infinite_weight.validate() and passed
	passed = not nan_weight.validate() and passed
	passed = not invalid_socket_direction.validate() and passed
	passed = not invalid_torch_direction.validate() and passed
	passed = not invalid_spawn_direction.validate() and passed
	passed = not invalid_return_direction.validate() and passed
	passed = not unpaired_markers.validate() and passed
	if passed:
		print("LEVEL_MODULE_DEFINITION_MALFORMED PASS")
		quit(0)
	else:
		print("LEVEL_MODULE_DEFINITION_MALFORMED FAILED")
		quit(1)

func _make_valid_module() -> LevelModuleDefinition:
	var definition := LevelModuleDefinition.new()
	definition.module_id = &"malformed_probe_module"
	definition.size = Vector3i(4, 4, 4)
	definition.weight = 150.25
	definition.cells.resize(64)
	definition.cells.fill(StructureCell.AIR)
	for y in definition.size.y:
		for x in definition.size.x:
			definition.cells[StructureCell.index_of(Vector3i(x, y, 0), definition.size)] = BlockId.Type.STONE
	for cell in [Vector3i(1, 0, 0), Vector3i(0, 0, 2), Vector3i(3, 0, 2), Vector3i(3, 2, 3)]:
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
	return definition
