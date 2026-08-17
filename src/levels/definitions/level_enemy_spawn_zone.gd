extends Resource
class_name LevelEnemySpawnZone

const SOCKET_CLEARANCE: int = 3

@export var zone_id: StringName
@export var minimum_feet_cell: Vector3i
@export var maximum_feet_cell: Vector3i

func has_valid_bounds(size: Vector3i) -> bool:
	if not StructureDefinition.is_valid_id(zone_id):
		return false
	if minimum_feet_cell.y != maximum_feet_cell.y:
		return false
	if minimum_feet_cell.x > maximum_feet_cell.x or minimum_feet_cell.z > maximum_feet_cell.z:
		return false
	if not StructureCell.is_in_bounds(minimum_feet_cell, size) or not StructureCell.is_in_bounds(maximum_feet_cell, size):
		return false
	return minimum_feet_cell.y > 0 and maximum_feet_cell.y < size.y - 1

func get_candidate_cells(
	size: Vector3i,
	cells: PackedInt32Array,
	sockets: Array[LevelSocketDefinition],
	changes: Dictionary = {},
) -> Array[Vector3i]:
	var candidates: Array[Vector3i] = []
	if not has_valid_bounds(size) or cells.size() != size.x * size.y * size.z:
		return candidates
	var socket_columns := _socket_columns(size, cells, sockets, changes)
	for z in range(minimum_feet_cell.z, maximum_feet_cell.z + 1):
		for x in range(minimum_feet_cell.x, maximum_feet_cell.x + 1):
			var feet := Vector3i(x, minimum_feet_cell.y, z)
			if _cell_value(feet, size, cells, changes) != StructureCell.AIR:
				continue
			if _cell_value(feet + Vector3i.UP, size, cells, changes) != StructureCell.AIR:
				continue
			if not StructureCell.is_structure_solid(_cell_value(feet + Vector3i.DOWN, size, cells, changes)):
				continue
			if not _has_socket_clearance(feet, socket_columns):
				continue
			candidates.append(feet)
	return candidates

static func _socket_columns(
	size: Vector3i,
	cells: PackedInt32Array,
	sockets: Array[LevelSocketDefinition],
	changes: Dictionary,
) -> Array[Vector2i]:
	var columns: Array[Vector2i] = []
	var seen: Dictionary = {}
	for socket in sockets:
		for cell in LevelSocketAperture.find_cells(socket, size, cells, changes):
			var column := Vector2i(cell.x, cell.z)
			if seen.has(column):
				continue
			seen[column] = true
			columns.append(column)
	return columns

static func _has_socket_clearance(feet: Vector3i, socket_columns: Array[Vector2i]) -> bool:
	for column in socket_columns:
		var horizontal_distance := maxi(absi(feet.x - column.x), absi(feet.z - column.y))
		if horizontal_distance < SOCKET_CLEARANCE:
			return false
	return true

static func _cell_value(cell: Vector3i, size: Vector3i, cells: PackedInt32Array, changes: Dictionary) -> int:
	if changes.has(cell):
		return int(changes[cell])
	return cells[StructureCell.index_of(cell, size)]
