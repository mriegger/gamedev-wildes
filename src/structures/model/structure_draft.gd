extends RefCounted
class_name StructureDraft

const DEFAULT_SIZE: Vector3i = Vector3i(16, 16, 16)
const MAX_EXTENT: Vector3i = Vector3i(64, 64, 64)
const MAX_CELL_COUNT: int = 262144

var _size: Vector3i
var _cells: PackedInt32Array
var _torches: Array[StructureTorchDefinition] = []
var _dirty: bool

func _init(p_size: Vector3i, p_cells: PackedInt32Array) -> void:
	assert(is_valid_size(p_size))
	assert(p_cells.size() == p_size.x * p_size.y * p_size.z)
	for value in p_cells:
		assert(StructureCell.is_generic_valid(value))
	_size = p_size
	_cells = p_cells.duplicate()

static func create(size: Vector3i = DEFAULT_SIZE) -> StructureDraft:
	if not is_valid_size(size):
		return null
	return StructureDraft.new(size, _air_cells(size))

static func is_valid_size(value: Vector3i) -> bool:
	if value.x <= 0 or value.y <= 0 or value.z <= 0:
		return false
	if value.x > MAX_EXTENT.x or value.y > MAX_EXTENT.y or value.z > MAX_EXTENT.z:
		return false
	return value.x * value.y * value.z <= MAX_CELL_COUNT

func get_size() -> Vector3i:
	return _size

func is_in_bounds(cell: Vector3i) -> bool:
	return StructureCell.is_in_bounds(cell, _size)

func get_cell(cell: Vector3i) -> int:
	assert(is_in_bounds(cell))
	return _cells[StructureCell.index_of(cell, _size)]

func snapshot_cells() -> PackedInt32Array:
	return _cells.duplicate()

func get_torches() -> Array[StructureTorchDefinition]:
	var copied: Array[StructureTorchDefinition] = []
	for torch in _torches:
		copied.append(_copy_torch(torch))
	return copied

func is_dirty() -> bool:
	return _dirty

func can_place_block(cell: Vector3i, block_id: int) -> bool:
	if not is_in_bounds(cell) or not StructureCell.is_structure_solid(block_id):
		return false
	return not StructureCell.is_structure_solid(get_cell(cell)) and _torch_index_at(cell) == -1

func try_place_block(cell: Vector3i, block_id: int) -> StructureDraftChange:
	if not can_place_block(cell, block_id):
		return StructureDraftChange.reject()
	_set_cell(cell, block_id)
	return _commit_change([cell])

func try_remove_block(cell: Vector3i) -> StructureDraftChange:
	if not is_in_bounds(cell) or not StructureCell.is_structure_solid(get_cell(cell)):
		return StructureDraftChange.reject()
	var removed_torches := _torch_cells_supported_by(cell)
	_set_cell(cell, StructureCell.AIR)
	_remove_torches(removed_torches)
	return _commit_change([cell], not removed_torches.is_empty())

func can_place_torch(cell: Vector3i, support_direction: Vector3i) -> bool:
	if not is_in_bounds(cell) or get_cell(cell) != StructureCell.AIR or _torch_index_at(cell) != -1:
		return false
	if not StructureTorchDefinition.is_horizontal_support(support_direction):
		return false
	var support_cell := cell + support_direction
	return is_in_bounds(support_cell) and StructureCell.is_structure_solid(get_cell(support_cell))

func try_place_torch(cell: Vector3i, support_direction: Vector3i) -> StructureDraftChange:
	if not can_place_torch(cell, support_direction):
		return StructureDraftChange.reject()
	var torch := StructureTorchDefinition.new()
	torch.cell = cell
	torch.support_direction = support_direction
	_torches.append(torch)
	return _commit_change([], true)

func try_remove_torch(cell: Vector3i) -> StructureDraftChange:
	var index := _torch_index_at(cell)
	if index == -1:
		return StructureDraftChange.reject()
	_torches.remove_at(index)
	return _commit_change([], true)

func _commit_change(changed_cells: Array[Vector3i], torches_changed: bool = false) -> StructureDraftChange:
	_dirty = true
	return StructureDraftChange.success(changed_cells, torches_changed)

func _set_cell(cell: Vector3i, value: int) -> void:
	_cells[StructureCell.index_of(cell, _size)] = value

func _torch_index_at(cell: Vector3i) -> int:
	for index in _torches.size():
		if _torches[index].cell == cell:
			return index
	return -1

func _torch_cells_supported_by(support_cell: Vector3i) -> Dictionary:
	var cells: Dictionary = {}
	for torch in _torches:
		if torch.cell + torch.support_direction == support_cell:
			cells[torch.cell] = true
	return cells

func _remove_torches(cells: Dictionary) -> void:
	for index in range(_torches.size() - 1, -1, -1):
		if cells.has(_torches[index].cell):
			_torches.remove_at(index)

static func _air_cells(size: Vector3i) -> PackedInt32Array:
	var cells := PackedInt32Array()
	cells.resize(size.x * size.y * size.z)
	cells.fill(StructureCell.AIR)
	return cells

static func _copy_torch(source: StructureTorchDefinition) -> StructureTorchDefinition:
	var copied := StructureTorchDefinition.new()
	copied.cell = source.cell
	copied.support_direction = source.support_direction
	return copied
