extends RefCounted
class_name LevelSocketAperture

static func find_cells(
	socket: LevelSocketDefinition,
	size: Vector3i,
	cells: PackedInt32Array,
	changes: Dictionary = {},
) -> Array[Vector3i]:
	var aperture: Array[Vector3i] = []
	if socket == null or not LevelSocketDefinition.is_valid_direction(socket.direction):
		return aperture
	if cells.size() != size.x * size.y * size.z or not is_boundary(socket.cell, size, socket.direction):
		return aperture
	if _cell_value(socket.cell, size, cells, changes) != StructureCell.AIR:
		return aperture
	var pending: Array[Vector3i] = [socket.cell]
	var visited: Dictionary = {socket.cell: true}
	var pending_index := 0
	var transverse := _transverse_vector(socket.direction)
	var neighbors: Array[Vector3i] = [Vector3i.UP, Vector3i.DOWN, transverse, -transverse]
	while pending_index < pending.size():
		var cell := pending[pending_index]
		pending_index += 1
		aperture.append(cell)
		for offset in neighbors:
			var neighbor := cell + offset
			if visited.has(neighbor) or not is_boundary(neighbor, size, socket.direction):
				continue
			if _cell_value(neighbor, size, cells, changes) != StructureCell.AIR:
				continue
			visited[neighbor] = true
			pending.append(neighbor)
	aperture.sort_custom(func(first: Vector3i, second: Vector3i) -> bool:
		return _cell_less(first, second)
	)
	return aperture

static func is_valid(
	socket: LevelSocketDefinition,
	size: Vector3i,
	cells: PackedInt32Array,
	changes: Dictionary = {},
) -> bool:
	var aperture := find_cells(socket, size, cells, changes)
	if aperture.is_empty():
		return false
	var aperture_lookup: Dictionary = {}
	for cell in aperture:
		aperture_lookup[cell] = true
	if not aperture_lookup.has(socket.cell + Vector3i.UP):
		return false
	var inward := -LevelSocketDefinition.vector_for(socket.direction)
	var transverse_extent := size.x if _uses_x_axis(socket.direction) else size.z
	for cell in aperture:
		var transverse := cell.x if _uses_x_axis(socket.direction) else cell.z
		if cell.y <= 0 or cell.y >= size.y - 1 or transverse <= 0 or transverse >= transverse_extent - 1:
			return false
		var inner_cell := cell + inward
		if not StructureCell.is_in_bounds(inner_cell, size) or _cell_value(inner_cell, size, cells, changes) != StructureCell.AIR:
			return false
	var socket_floor := socket.cell + Vector3i.DOWN
	if not StructureCell.is_in_bounds(socket_floor, size) or not StructureCell.is_structure_solid(_cell_value(socket_floor, size, cells, changes)):
		return false
	for cell in aperture:
		var floor_cell := cell + Vector3i.DOWN
		if aperture_lookup.has(floor_cell):
			continue
		if not StructureCell.is_structure_solid(_cell_value(floor_cell, size, cells, changes)):
			return false
	return true

static func dimensions(aperture: Array[Vector3i], direction: LevelSocketDefinition.Direction) -> Vector2i:
	if aperture.is_empty() or not LevelSocketDefinition.is_valid_direction(direction):
		return Vector2i.ZERO
	var minimum_transverse := aperture[0].x if _uses_x_axis(direction) else aperture[0].z
	var maximum_transverse := minimum_transverse
	var minimum_y := aperture[0].y
	var maximum_y := minimum_y
	for cell in aperture:
		var transverse := cell.x if _uses_x_axis(direction) else cell.z
		minimum_transverse = mini(minimum_transverse, transverse)
		maximum_transverse = maxi(maximum_transverse, transverse)
		minimum_y = mini(minimum_y, cell.y)
		maximum_y = maxi(maximum_y, cell.y)
	return Vector2i(maximum_transverse - minimum_transverse + 1, maximum_y - minimum_y + 1)

static func normalized_profile(aperture: Array[Vector3i], direction: LevelSocketDefinition.Direction) -> Array[Vector2i]:
	var profile: Array[Vector2i] = []
	var aperture_size := dimensions(aperture, direction)
	if aperture_size == Vector2i.ZERO:
		return profile
	var minimum_transverse := aperture[0].x if _uses_x_axis(direction) else aperture[0].z
	var minimum_y := aperture[0].y
	for cell in aperture:
		minimum_transverse = mini(minimum_transverse, cell.x if _uses_x_axis(direction) else cell.z)
		minimum_y = mini(minimum_y, cell.y)
	for cell in aperture:
		var transverse := cell.x if _uses_x_axis(direction) else cell.z
		profile.append(Vector2i(transverse - minimum_transverse, cell.y - minimum_y))
	profile.sort_custom(func(first: Vector2i, second: Vector2i) -> bool:
		return first.x < second.x if first.x != second.x else first.y < second.y
	)
	return profile

static func is_boundary(cell: Vector3i, size: Vector3i, direction: LevelSocketDefinition.Direction) -> bool:
	if not StructureCell.is_in_bounds(cell, size):
		return false
	match direction:
		LevelSocketDefinition.Direction.NORTH:
			return cell.z == 0
		LevelSocketDefinition.Direction.EAST:
			return cell.x == size.x - 1
		LevelSocketDefinition.Direction.SOUTH:
			return cell.z == size.z - 1
		LevelSocketDefinition.Direction.WEST:
			return cell.x == 0
	return false

static func _cell_value(cell: Vector3i, size: Vector3i, cells: PackedInt32Array, changes: Dictionary) -> int:
	if changes.has(cell):
		return int(changes[cell])
	return cells[StructureCell.index_of(cell, size)]

static func _transverse_vector(direction: LevelSocketDefinition.Direction) -> Vector3i:
	return Vector3i.RIGHT if _uses_x_axis(direction) else Vector3i.BACK

static func _uses_x_axis(direction: LevelSocketDefinition.Direction) -> bool:
	return direction == LevelSocketDefinition.Direction.NORTH or direction == LevelSocketDefinition.Direction.SOUTH

static func _cell_less(first: Vector3i, second: Vector3i) -> bool:
	if first.x != second.x:
		return first.x < second.x
	if first.y != second.y:
		return first.y < second.y
	return first.z < second.z
