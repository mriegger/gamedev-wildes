extends RefCounted
class_name StructureDraft

const DEFAULT_SIZE: Vector3i = Vector3i(16, 16, 16)
const MAX_EXTENT: Vector3i = Vector3i(64, 64, 64)
const MAX_CELL_COUNT: int = 262144

var _size: Vector3i
var _cells: PackedInt32Array
var _torches_by_cell: Dictionary = {}
var _torch_cells_by_support: Dictionary = {}
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

func copy_cells_for_chunk(chunk: Vector3i, chunk_size: int) -> Dictionary:
	assert(chunk_size > 0)
	assert(chunk.x >= 0 and chunk.y >= 0 and chunk.z >= 0)
	var start := chunk * chunk_size
	assert(start.x < _size.x and start.y < _size.y and start.z < _size.z)
	var minimum := Vector3i(
		maxi(start.x - 1, 0),
		maxi(start.y - 1, 0),
		maxi(start.z - 1, 0)
	)
	var maximum := Vector3i(
		mini(start.x + chunk_size + 1, _size.x),
		mini(start.y + chunk_size + 1, _size.y),
		mini(start.z + chunk_size + 1, _size.z)
	)
	var copied: Dictionary = {}
	for y in range(minimum.y, maximum.y):
		for z in range(minimum.z, maximum.z):
			for x in range(minimum.x, maximum.x):
				var cell := Vector3i(x, y, z)
				copied[cell] = _cells[StructureCell.index_of(cell, _size)]
	return copied

func get_torches() -> Array[StructureTorchDefinition]:
	var cells: Array[Vector3i] = []
	for cell_value in _torches_by_cell:
		cells.append(cell_value as Vector3i)
	cells.sort_custom(_cell_less)
	var copied: Array[StructureTorchDefinition] = []
	for cell in cells:
		copied.append(_copy_torch(_torches_by_cell[cell] as StructureTorchDefinition))
	return copied

func has_torch(cell: Vector3i) -> bool:
	return _torches_by_cell.has(cell)

func is_dirty() -> bool:
	return _dirty

func can_place_block(cell: Vector3i, block_id: int) -> bool:
	if not is_in_bounds(cell) or not StructureCell.is_structure_solid(block_id):
		return false
	return not StructureCell.is_structure_solid(get_cell(cell)) and not has_torch(cell)

func try_place_block(cell: Vector3i, block_id: int) -> StructureDraftChange:
	if not can_place_block(cell, block_id):
		return StructureDraftChange.reject()
	_set_cell(cell, block_id)
	return _commit_change([cell])

func try_remove_block(cell: Vector3i) -> StructureDraftChange:
	if not is_in_bounds(cell) or not StructureCell.is_structure_solid(get_cell(cell)):
		return StructureDraftChange.reject()
	var removed_torch_cells := _get_torch_cells_supported_by(cell)
	_set_cell(cell, StructureCell.AIR)
	for torch_cell in removed_torch_cells:
		_remove_torch(torch_cell)
	return _commit_change([cell], [], removed_torch_cells)

func can_place_torch(cell: Vector3i, support_direction: Vector3i) -> bool:
	if not is_in_bounds(cell) or get_cell(cell) != StructureCell.AIR or has_torch(cell):
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
	_add_torch(torch)
	return _commit_change([], [torch])

func try_remove_torch(cell: Vector3i) -> StructureDraftChange:
	if not has_torch(cell):
		return StructureDraftChange.reject()
	_remove_torch(cell)
	return _commit_change([], [], [cell])

func _commit_change(
	changed_cells: Array[Vector3i],
	added_torches: Array[StructureTorchDefinition] = [],
	removed_torch_cells: Array[Vector3i] = [],
) -> StructureDraftChange:
	_dirty = true
	return StructureDraftChange.success(changed_cells, added_torches, removed_torch_cells)

func _set_cell(cell: Vector3i, value: int) -> void:
	_cells[StructureCell.index_of(cell, _size)] = value

func _add_torch(torch: StructureTorchDefinition) -> void:
	_torches_by_cell[torch.cell] = torch
	var support_cell := torch.cell + torch.support_direction
	var supported_cells: Dictionary
	if _torch_cells_by_support.has(support_cell):
		supported_cells = _torch_cells_by_support[support_cell] as Dictionary
	else:
		supported_cells = {}
		_torch_cells_by_support[support_cell] = supported_cells
	supported_cells[torch.cell] = true

func _remove_torch(cell: Vector3i) -> void:
	var torch := _torches_by_cell[cell] as StructureTorchDefinition
	var support_cell := torch.cell + torch.support_direction
	var supported_cells := _torch_cells_by_support[support_cell] as Dictionary
	supported_cells.erase(cell)
	if supported_cells.is_empty():
		_torch_cells_by_support.erase(support_cell)
	_torches_by_cell.erase(cell)

func _get_torch_cells_supported_by(support_cell: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	if not _torch_cells_by_support.has(support_cell):
		return cells
	var indexed := _torch_cells_by_support[support_cell] as Dictionary
	for cell_value in indexed:
		cells.append(cell_value as Vector3i)
	cells.sort_custom(_cell_less)
	return cells

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

static func _cell_less(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z
