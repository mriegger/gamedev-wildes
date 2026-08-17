extends VoxelSpace
class_name LevelState

const VOID: int = -1
const AIR: int = BlockId.Type.AIR

var _cells: Dictionary
var _solid_cells: Array[Vector3i]
var _highest_solid_by_column: Dictionary
var _spawn_cell: Vector3i
var _spawn_facing: LevelSocketDefinition.Direction
var _return_door_cell: Vector3i
var _return_door_facing: LevelSocketDefinition.Direction
var _bounds_min: Vector3i
var _bounds_max: Vector3i

func _init(
	p_block_catalog: BlockCatalog,
	p_cells: Dictionary,
	p_spawn_cell: Vector3i,
	p_spawn_facing: LevelSocketDefinition.Direction,
	p_return_door_cell: Vector3i,
	p_return_door_facing: LevelSocketDefinition.Direction,
	p_bounds_min: Vector3i,
	p_bounds_max: Vector3i
) -> void:
	assert(p_block_catalog != null)
	block_catalog = p_block_catalog
	_cells = p_cells.duplicate()
	_spawn_cell = p_spawn_cell
	_spawn_facing = p_spawn_facing
	_return_door_cell = p_return_door_cell
	_return_door_facing = p_return_door_facing
	_bounds_min = p_bounds_min
	_bounds_max = p_bounds_max
	_validate_cells()
	_build_solid_index()

static func from_layout(layout: LevelLayout, p_block_catalog: BlockCatalog) -> LevelState:
	return LevelState.new(
		p_block_catalog,
		layout.cells,
		layout.spawn_cell,
		layout.spawn_facing,
		layout.return_door_cell,
		layout.return_door_facing,
		layout.bounds_min,
		layout.bounds_max
	)

func _validate_cells() -> void:
	assert(_bounds_min.x <= _bounds_max.x)
	assert(_bounds_min.y <= _bounds_max.y)
	assert(_bounds_min.z <= _bounds_max.z)
	for position in _cells:
		assert(position is Vector3i)
		var block_id := int(_cells[position])
		assert(block_id != StructureCell.VOID and StructureCell.is_valid(block_id))
	assert(is_interior_open(_spawn_cell))
	assert(is_interior_open(_spawn_cell + Vector3i.UP))
	assert(is_solid(_spawn_cell + Vector3i.DOWN))
	assert(is_interior_open(_return_door_cell))
	assert(is_interior_open(_return_door_cell + Vector3i.UP))
	assert(is_solid(_return_door_cell + Vector3i.DOWN))

func _build_solid_index() -> void:
	_solid_cells.clear()
	_highest_solid_by_column.clear()
	for position in _cells:
		var cell := position as Vector3i
		if not is_solid(cell):
			continue
		_solid_cells.append(cell)
		var column := Vector2i(cell.x, cell.z)
		_highest_solid_by_column[column] = maxi(cell.y, int(_highest_solid_by_column.get(column, cell.y)))
	_solid_cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.x != b.x:
			return a.x < b.x
		if a.y != b.y:
			return a.y < b.y
		return a.z < b.z
	)

func get_cell_value(position: Vector3i) -> int:
	return int(_cells.get(position, VOID))

func has_cell(position: Vector3i) -> bool:
	return _cells.has(position)

func is_interior_open(position: Vector3i) -> bool:
	return int(_cells.get(position, VOID)) == AIR

func get_block_at(position: Vector3i) -> Variant:
	var block_id := int(_cells.get(position, VOID))
	if block_id <= AIR:
		return null
	return block_id

func get_block_id_at(position: Vector3i) -> int:
	return int(_cells.get(position, AIR))

func is_solid(position: Vector3i) -> bool:
	var block: Variant = get_block_at(position)
	return block != null and block_catalog.is_solid(block as int)

func is_raycast_solid(position: Vector3i) -> bool:
	var block: Variant = get_block_at(position)
	return block != null and block_catalog.is_raycast_solid(block as int)

func is_face_targetable(block_position: Vector3i, face_normal: Vector3i) -> bool:
	return is_raycast_solid(block_position) and is_interior_open(block_position + face_normal)

func get_highest_top(x: int, z: int) -> float:
	var highest: Variant = _highest_solid_by_column.get(Vector2i(x, z), null)
	if highest == null:
		return NO_SURFACE_Y
	return float(highest as int) + 1.0

func get_spawn_position() -> Vector3:
	return Vector3(_spawn_cell) + Vector3(0.5, 0.0, 0.5)

func get_spawn_facing() -> LevelSocketDefinition.Direction:
	return _spawn_facing

func get_return_door_cell() -> Vector3i:
	return _return_door_cell

func get_return_door_position() -> Vector3:
	return Vector3(_return_door_cell) + Vector3(0.5, 0.0, 0.5)

func get_return_door_facing() -> LevelSocketDefinition.Direction:
	return _return_door_facing

func get_bounds_min() -> Vector3i:
	return _bounds_min

func get_bounds_max() -> Vector3i:
	return _bounds_max

func get_solid_cells() -> Array[Vector3i]:
	return _solid_cells.duplicate()

func snapshot_cells() -> Dictionary:
	return _cells.duplicate()
