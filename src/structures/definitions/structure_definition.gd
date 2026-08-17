extends Resource
class_name StructureDefinition

const CURRENT_FORMAT_VERSION: int = 1
const DEFAULT_SIZE: Vector3i = Vector3i(16, 16, 16)
const MAX_EXTENT: Vector3i = Vector3i(64, 64, 64)
const MAX_CELL_COUNT: int = 262144

@export var format_version: int
@export var structure_id: StringName
@export var size: Vector3i = DEFAULT_SIZE
@export var cells: PackedInt32Array
@export var torches: Array[StructureTorchDefinition] = []

func cell_at(cell: Vector3i) -> int:
	assert(StructureCell.is_in_bounds(cell, size))
	return cells[StructureCell.index_of(cell, size)]

func validate() -> bool:
	var valid := true
	var source := resource_path
	if source.is_empty():
		source = String(structure_id)
	if format_version != CURRENT_FORMAT_VERSION:
		push_error("[StructureDefinition] Unsupported format version for %s" % source)
		valid = false
	if not is_valid_id(structure_id):
		push_error("[StructureDefinition] Invalid structure ID at %s" % source)
		valid = false
	if not is_valid_size(size):
		push_error("[StructureDefinition] Invalid size for %s" % source)
		return false
	if cells.size() != size.x * size.y * size.z:
		push_error("[StructureDefinition] Dense cell count mismatch for %s" % source)
		return false
	var has_solid := false
	for value in cells:
		if not StructureCell.is_generic_valid(value):
			push_error("[StructureDefinition] Invalid block ID %d for %s" % [value, source])
			valid = false
		elif StructureCell.is_structure_solid(value):
			has_solid = true
	if not has_solid:
		push_error("[StructureDefinition] Structure is empty at %s" % source)
		valid = false
	var torch_cells: Dictionary = {}
	for torch in torches:
		if torch == null:
			push_error("[StructureDefinition] Null torch for %s" % source)
			valid = false
			continue
		if torch_cells.has(torch.cell):
			push_error("[StructureDefinition] Duplicate torch cell for %s" % source)
			valid = false
			continue
		torch_cells[torch.cell] = true
		valid = _validate_torch(torch, source) and valid
	return valid

func _validate_torch(torch: StructureTorchDefinition, source: String) -> bool:
	if not StructureCell.is_in_bounds(torch.cell, size) or cell_at(torch.cell) != StructureCell.AIR:
		push_error("[StructureDefinition] Torch is not in interior air for %s" % source)
		return false
	if not StructureTorchDefinition.is_horizontal_support(torch.support_direction):
		push_error("[StructureDefinition] Torch support direction is invalid for %s" % source)
		return false
	var support_cell := torch.cell + torch.support_direction
	if not StructureCell.is_in_bounds(support_cell, size) or not StructureCell.is_structure_solid(cell_at(support_cell)):
		push_error("[StructureDefinition] Torch has no wall support for %s" % source)
		return false
	return true

static func is_valid_size(value: Vector3i) -> bool:
	if value.x <= 0 or value.y <= 0 or value.z <= 0:
		return false
	if value.x > MAX_EXTENT.x or value.y > MAX_EXTENT.y or value.z > MAX_EXTENT.z:
		return false
	return value.x * value.y * value.z <= MAX_CELL_COUNT

static func is_valid_id(value: StringName) -> bool:
	var matcher := RegEx.new()
	if matcher.compile("^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$") != OK:
		return false
	return matcher.search(String(value)) != null
