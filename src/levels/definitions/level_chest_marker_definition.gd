extends Resource
class_name LevelChestMarkerDefinition

const HORIZONTAL_NEIGHBORS: Array[Vector3i] = [
	Vector3i.LEFT,
	Vector3i.RIGHT,
	Vector3i.FORWARD,
	Vector3i.BACK,
]

@export var cell: Vector3i

static func has_accessible_side(marker_cell: Vector3i, size: Vector3i, cells: PackedInt32Array, changes: Dictionary = {}) -> bool:
	for offset in HORIZONTAL_NEIGHBORS:
		var feet_cell := marker_cell + offset
		var head_cell := feet_cell + Vector3i.UP
		var support_cell := feet_cell + Vector3i.DOWN
		if (
			StructureCell.is_in_bounds(feet_cell, size)
			and StructureCell.is_in_bounds(head_cell, size)
			and StructureCell.is_in_bounds(support_cell, size)
			and _cell_value(feet_cell, size, cells, changes) == StructureCell.AIR
			and _cell_value(head_cell, size, cells, changes) == StructureCell.AIR
			and StructureCell.is_structure_solid(_cell_value(support_cell, size, cells, changes))
		):
			return true
	return false

static func _cell_value(cell: Vector3i, size: Vector3i, cells: PackedInt32Array, changes: Dictionary) -> int:
	if changes.has(cell):
		return int(changes[cell])
	return cells[StructureCell.index_of(cell, size)]
