extends RefCounted
class_name StructureDraftChange

var succeeded: bool
var changed_cells: Array[Vector3i]
var added_torches: Array[StructureTorchDefinition]
var removed_torch_cells: Array[Vector3i]
var metadata_changed: bool
var changed_enemy_spawn_zone_ids: Array[StringName] = []

static func success(
	p_changed_cells: Array[Vector3i] = [],
	p_added_torches: Array[StructureTorchDefinition] = [],
	p_removed_torch_cells: Array[Vector3i] = [],
	p_metadata_changed: bool = false,
	p_changed_enemy_spawn_zone_ids: Array[StringName] = [],
) -> StructureDraftChange:
	var change := StructureDraftChange.new()
	change.succeeded = true
	change.changed_cells.assign(p_changed_cells)
	for torch in p_added_torches:
		var copied := StructureTorchDefinition.new()
		copied.cell = torch.cell
		copied.support_direction = torch.support_direction
		change.added_torches.append(copied)
	change.removed_torch_cells.assign(p_removed_torch_cells)
	change.metadata_changed = p_metadata_changed
	change.changed_enemy_spawn_zone_ids.assign(p_changed_enemy_spawn_zone_ids)
	return change

static func reject() -> StructureDraftChange:
	return StructureDraftChange.new()
