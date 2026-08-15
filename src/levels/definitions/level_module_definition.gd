extends Resource
class_name LevelModuleDefinition

const AIR_NEIGHBORS: Array[Vector3i] = [
	Vector3i.LEFT,
	Vector3i.RIGHT,
	Vector3i.DOWN,
	Vector3i.UP,
	Vector3i.FORWARD,
	Vector3i.BACK,
]

@export var module_id: StringName
@export var size: Vector3i
@export_range(0.01, 100.0, 0.01, "or_greater") var weight: float = 1.0
@export var cells: PackedInt32Array
@export var sockets: Array[LevelSocketDefinition] = []
@export var torches: Array[LevelTorchDefinition] = []
@export var spawn_marker: LevelMarkerDefinition
@export var return_door_marker: LevelMarkerDefinition

func cell_at(cell: Vector3i) -> int:
	assert(StructureCell.is_in_bounds(cell, size))
	return cells[StructureCell.index_of(cell, size)]

func socket_aperture_cells(socket: LevelSocketDefinition) -> Array[Vector3i]:
	return LevelSocketAperture.find_cells(socket, size, cells)

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

func has_connected_traversable_air(seal_unused_sockets: bool) -> bool:
	var sealed_cells: Dictionary = {}
	if seal_unused_sockets:
		for socket in sockets:
			if socket != null and not socket.requires_connection():
				for aperture_cell in socket_aperture_cells(socket):
					sealed_cells[aperture_cell] = true
	var air_count := 0
	var first_air := Vector3i(-1, -1, -1)
	for y in size.y:
		for z in size.z:
			for x in size.x:
				var cell := Vector3i(x, y, z)
				if cell_at(cell) != StructureCell.AIR or sealed_cells.has(cell):
					continue
				if air_count == 0:
					first_air = cell
				air_count += 1
	if air_count == 0:
		return false
	var reached: Dictionary = {first_air: true}
	var pending: Array[Vector3i] = [first_air]
	var pending_index := 0
	while pending_index < pending.size():
		var cell := pending[pending_index]
		pending_index += 1
		for offset in AIR_NEIGHBORS:
			var neighbor := cell + offset
			if reached.has(neighbor) or sealed_cells.has(neighbor) or not StructureCell.is_in_bounds(neighbor, size) or cell_at(neighbor) != StructureCell.AIR:
				continue
			reached[neighbor] = true
			pending.append(neighbor)
	return reached.size() == air_count

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
	if not is_finite(weight) or weight <= 0.0:
		push_error("[LevelModuleDefinition] Weight must be positive and finite for %s" % source)
		valid = false
	for value in cells:
		if not StructureCell.is_valid(value):
			push_error("[LevelModuleDefinition] Invalid block ID %d for %s" % [value, source])
			valid = false
	var socket_ids: Dictionary = {}
	var socket_aperture_owners: Dictionary = {}
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
		var socket_valid := _validate_socket(socket, source)
		valid = socket_valid and valid
		if not socket_valid:
			continue
		for aperture_cell in socket_aperture_cells(socket):
			if socket_aperture_owners.has(aperture_cell):
				push_error("[LevelModuleDefinition] Socket apertures overlap for %s" % source)
				valid = false
			else:
				socket_aperture_owners[aperture_cell] = socket.socket_id
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
		if socket_aperture_owners.has(torch.cell):
			push_error("[LevelModuleDefinition] Torch overlaps a socket aperture for %s" % source)
			valid = false
	if (spawn_marker == null) != (return_door_marker == null):
		push_error("[LevelModuleDefinition] Player spawn and entrance/exit door markers must be paired for %s" % source)
		valid = false
	if spawn_marker != null:
		valid = _validate_marker(spawn_marker, "spawn", source) and valid
		valid = _validate_marker(return_door_marker, "entrance/exit door", source) and valid
		valid = _validate_marker_socket_clearance(spawn_marker, "spawn", socket_aperture_owners, source) and valid
		valid = _validate_marker_socket_clearance(return_door_marker, "entrance/exit door", socket_aperture_owners, source) and valid
	return valid

func _validate_socket(socket: LevelSocketDefinition, source: String) -> bool:
	if not LevelSocketDefinition.is_valid_direction(socket.direction):
		push_error("[LevelModuleDefinition] Socket direction is invalid for %s" % source)
		return false
	if not LevelSocketDefinition.is_valid_unused_fill_block(socket.unused_fill_block_id):
		push_error("[LevelModuleDefinition] Socket unused fill block is invalid for %s" % source)
		return false
	if not LevelSocketAperture.is_boundary(socket.cell, size, socket.direction):
		push_error("[LevelModuleDefinition] Socket is not on its facing boundary for %s" % source)
		return false
	if not LevelSocketAperture.is_valid(socket, size, cells):
		push_error("[LevelModuleDefinition] Socket opening is not enclosed, supported, or clear for %s" % source)
		return false
	return true

func _validate_torch(torch: LevelTorchDefinition, source: String) -> bool:
	if not LevelSocketDefinition.is_valid_direction(torch.wall_direction):
		push_error("[LevelModuleDefinition] Torch direction is invalid for %s" % source)
		return false
	if not StructureCell.is_in_bounds(torch.cell, size) or cell_at(torch.cell) != StructureCell.AIR:
		push_error("[LevelModuleDefinition] Torch is not in interior air for %s" % source)
		return false
	var support_cell := torch.cell + LevelSocketDefinition.vector_for(torch.wall_direction)
	if not StructureCell.is_in_bounds(support_cell, size) or not StructureCell.is_structure_solid(cell_at(support_cell)):
		push_error("[LevelModuleDefinition] Torch has no wall support for %s" % source)
		return false
	return true

func _validate_marker(marker: LevelMarkerDefinition, label: String, source: String) -> bool:
	if marker == null or not LevelSocketDefinition.is_valid_direction(marker.facing):
		push_error("[LevelModuleDefinition] Invalid %s marker facing for %s" % [label, source])
		return false
	if not StructureCell.is_in_bounds(marker.cell, size) or not StructureCell.is_in_bounds(marker.cell + Vector3i.UP, size):
		push_error("[LevelModuleDefinition] Invalid %s marker for %s" % [label, source])
		return false
	if cell_at(marker.cell) != StructureCell.AIR or cell_at(marker.cell + Vector3i.UP) != StructureCell.AIR:
		push_error("[LevelModuleDefinition] Invalid %s marker for %s" % [label, source])
		return false
	var floor_cell := marker.cell + Vector3i.DOWN
	if not StructureCell.is_in_bounds(floor_cell, size) or not StructureCell.is_structure_solid(cell_at(floor_cell)):
		push_error("[LevelModuleDefinition] %s marker has no floor for %s" % [label, source])
		return false
	return true

func _validate_marker_socket_clearance(marker: LevelMarkerDefinition, label: String, socket_aperture_owners: Dictionary, source: String) -> bool:
	if marker == null:
		return true
	if socket_aperture_owners.has(marker.cell) or socket_aperture_owners.has(marker.cell + Vector3i.UP):
		push_error("[LevelModuleDefinition] %s marker overlaps a socket aperture for %s" % [label, source])
		return false
	return true
