extends RefCounted
class_name StructureDraftChange

var succeeded: bool
var changed_cells: Array[Vector3i]
var torches_changed: bool

static func success(
	p_changed_cells: Array[Vector3i] = [],
	p_torches_changed: bool = false,
) -> StructureDraftChange:
	var change := StructureDraftChange.new()
	change.succeeded = true
	change.changed_cells.assign(p_changed_cells)
	change.torches_changed = p_torches_changed
	return change

static func reject() -> StructureDraftChange:
	return StructureDraftChange.new()
