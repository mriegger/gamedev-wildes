extends Resource
class_name LevelModuleDefinition

@export var module_id: StringName
@export var size: Vector3i
@export_range(0.01, 100.0, 0.01) var weight: float = 1.0
@export var cells: PackedInt32Array
@export var sockets: Array[LevelSocketDefinition] = []
@export var torches: Array[LevelTorchDefinition] = []
@export var spawn_marker: LevelMarkerDefinition
@export var return_door_marker: LevelMarkerDefinition

func cell_at(cell: Vector3i) -> int:
	assert(LevelCell.is_in_bounds(cell, size))
	return cells[LevelCell.index_of(cell, size)]

func rotated_size(quarter_turns: int) -> Vector3i:
	if posmod(quarter_turns, 2) == 0:
		return size
	return Vector3i(size.z, size.y, size.x)

func rotate_cell(cell: Vector3i, quarter_turns: int) -> Vector3i:
	match posmod(quarter_turns, 4):
		0:
			return cell
		1:
			return Vector3i(size.z - 1 - cell.z, cell.y, cell.x)
		2:
			return Vector3i(size.x - 1 - cell.x, cell.y, size.z - 1 - cell.z)
		3:
			return Vector3i(cell.z, cell.y, size.x - 1 - cell.x)
	return cell

func validate() -> bool:
	var valid := true
	var source := resource_path
	if source.is_empty():
		source = String(module_id)
	if module_id.is_empty():
		push_error("[LevelModuleDefinition] Empty module ID at %s" % source)
		valid = false
	if size.x <= 0 or size.y <= 0 or size.z <= 0:
		push_error("[LevelModuleDefinition] Invalid size for %s" % source)
		valid = false
		return valid
	if size.x > LevelDefinition.HARD_MAX_EXTENT.x or size.y > LevelDefinition.HARD_MAX_EXTENT.y or size.z > LevelDefinition.HARD_MAX_EXTENT.z:
		push_error("[LevelModuleDefinition] Size exceeds the hard level extent for %s" % source)
		valid = false
		return valid
	if cells.size() != size.x * size.y * size.z:
		push_error("[LevelModuleDefinition] Dense cell count mismatch for %s" % source)
		valid = false
		return valid
	if weight <= 0.0:
		push_error("[LevelModuleDefinition] Weight must be positive for %s" % source)
		valid = false
	for value in cells:
		if not LevelCell.is_valid(value):
			push_error("[LevelModuleDefinition] Invalid block ID %d for %s" % [value, source])
			valid = false
	var socket_ids: Dictionary = {}
	for socket in sockets:
		if socket == null:
			push_error("[LevelModuleDefinition] Null socket for %s" % source)
			valid = false
			continue
		if socket.socket_id.is_empty() or socket_ids.has(socket.socket_id):
			push_error("[LevelModuleDefinition] Empty or duplicate socket ID for %s" % source)
			valid = false
			continue
		socket_ids[socket.socket_id] = true
		valid = _validate_socket(socket, source) and valid
	var torch_cells: Dictionary = {}
	for torch in torches:
		if torch == null:
			push_error("[LevelModuleDefinition] Null torch for %s" % source)
			valid = false
			continue
		if torch_cells.has(torch.cell):
			push_error("[LevelModuleDefinition] Duplicate torch cell for %s" % source)
			valid = false
			continue
		torch_cells[torch.cell] = true
		valid = _validate_torch(torch, source) and valid
	if (spawn_marker == null) != (return_door_marker == null):
		push_error("[LevelModuleDefinition] Spawn and return markers must be paired for %s" % source)
		valid = false
	if spawn_marker != null:
		valid = _validate_marker(spawn_marker, "spawn", source) and valid
		valid = _validate_marker(return_door_marker, "return door", source) and valid
	return valid

func _validate_socket(socket: LevelSocketDefinition, source: String) -> bool:
	var valid := true
	if not LevelCell.is_in_bounds(socket.cell, size) or not LevelCell.is_in_bounds(socket.cell + Vector3i.UP, size):
		push_error("[LevelModuleDefinition] Socket aperture outside %s" % source)
		return false
	var boundary_valid := false
	match socket.direction:
		LevelSocketDefinition.Direction.NORTH:
			boundary_valid = socket.cell.z == 0
		LevelSocketDefinition.Direction.EAST:
			boundary_valid = socket.cell.x == size.x - 1
		LevelSocketDefinition.Direction.SOUTH:
			boundary_valid = socket.cell.z == size.z - 1
		LevelSocketDefinition.Direction.WEST:
			boundary_valid = socket.cell.x == 0
	if not boundary_valid:
		push_error("[LevelModuleDefinition] Socket is not on its facing boundary for %s" % source)
		valid = false
	var inward: Vector3i = -LevelSocketDefinition.vector_for(socket.direction)
	var aperture_cells: Array[Vector3i] = [socket.cell, socket.cell + Vector3i.UP]
	for aperture_cell in aperture_cells:
		if cell_at(aperture_cell) != LevelCell.AIR:
			push_error("[LevelModuleDefinition] Socket aperture is not air for %s" % source)
			valid = false
		var inner_cell: Vector3i = aperture_cell + inward
		if not LevelCell.is_in_bounds(inner_cell, size) or cell_at(inner_cell) != LevelCell.AIR:
			push_error("[LevelModuleDefinition] Socket does not open into interior air for %s" % source)
			valid = false
	var floor_cell := socket.cell + Vector3i.DOWN
	if not LevelCell.is_in_bounds(floor_cell, size) or not LevelCell.is_structure_solid(cell_at(floor_cell)):
		push_error("[LevelModuleDefinition] Socket has no floor for %s" % source)
		valid = false
	return valid

func _validate_torch(torch: LevelTorchDefinition, source: String) -> bool:
	if not LevelCell.is_in_bounds(torch.cell, size) or cell_at(torch.cell) != LevelCell.AIR:
		push_error("[LevelModuleDefinition] Torch is not in interior air for %s" % source)
		return false
	var support_cell := torch.cell + LevelSocketDefinition.vector_for(torch.wall_direction)
	if not LevelCell.is_in_bounds(support_cell, size) or not LevelCell.is_structure_solid(cell_at(support_cell)):
		push_error("[LevelModuleDefinition] Torch has no wall support for %s" % source)
		return false
	return true

func _validate_marker(marker: LevelMarkerDefinition, label: String, source: String) -> bool:
	if marker == null or not LevelCell.is_in_bounds(marker.cell, size) or not LevelCell.is_in_bounds(marker.cell + Vector3i.UP, size):
		push_error("[LevelModuleDefinition] Invalid %s marker for %s" % [label, source])
		return false
	if cell_at(marker.cell) != LevelCell.AIR or cell_at(marker.cell + Vector3i.UP) != LevelCell.AIR:
		push_error("[LevelModuleDefinition] Invalid %s marker for %s" % [label, source])
		return false
	var floor_cell := marker.cell + Vector3i.DOWN
	if not LevelCell.is_in_bounds(floor_cell, size) or not LevelCell.is_structure_solid(cell_at(floor_cell)):
		push_error("[LevelModuleDefinition] %s marker has no floor for %s" % [label, source])
		return false
	return true
