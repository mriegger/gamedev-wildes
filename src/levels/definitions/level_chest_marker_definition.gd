extends Resource
class_name LevelChestMarkerDefinition

const HORIZONTAL_NEIGHBORS: Array[Vector3i] = [
	Vector3i.LEFT,
	Vector3i.RIGHT,
	Vector3i.FORWARD,
	Vector3i.BACK,
]

@export var cell: Vector3i

static func has_accessible_side(
	marker_cell: Vector3i,
	size: Vector3i,
	cells: PackedInt32Array,
	changes: Dictionary = {},
	blocked_cells: Dictionary = {},
) -> bool:
	var cell_value := func(cell: Vector3i) -> int:
		if not StructureCell.is_in_bounds(cell, size):
			return StructureCell.VOID
		if changes.has(cell):
			return int(changes[cell])
		return cells[StructureCell.index_of(cell, size)]
	return _has_accessible_side(marker_cell, cell_value, blocked_cells)

static func has_accessible_side_in_world(marker_cell: Vector3i, cells: Dictionary) -> bool:
	var cell_value := func(cell: Vector3i) -> int:
		return int(cells.get(cell, StructureCell.VOID))
	return _has_accessible_side(marker_cell, cell_value, {})

static func _has_accessible_side(marker_cell: Vector3i, cell_value: Callable, blocked_cells: Dictionary) -> bool:
	for offset in HORIZONTAL_NEIGHBORS:
		var feet_cell := marker_cell + offset
		var head_cell := feet_cell + Vector3i.UP
		var support_cell := feet_cell + Vector3i.DOWN
		if (
			not blocked_cells.has(feet_cell)
			and not blocked_cells.has(head_cell)
			and int(cell_value.call(feet_cell)) == StructureCell.AIR
			and int(cell_value.call(head_cell)) == StructureCell.AIR
			and StructureCell.is_structure_solid(int(cell_value.call(support_cell)))
		):
			return true
	return false
