extends RefCounted
class_name WorldLootSpatialIndex

const MAXIMUM_ENTRY_COUNT: int = 128
const MINIMUM_CELL_COORDINATE: int = -2147483648
const MAXIMUM_CELL_COORDINATE: int = 2147483647

var _cell_size: float
var _positions: Dictionary = {}
var _cells: Dictionary = {}

func _init(p_cell_size: float) -> void:
	assert(is_finite(p_cell_size) and p_cell_size > 0.0)
	_cell_size = p_cell_size

func rebuild(entries: Dictionary, entry_ids: Array[int]) -> void:
	assert(entry_ids.size() <= MAXIMUM_ENTRY_COUNT)
	_positions.clear()
	_cells.clear()
	for entry_id in entry_ids:
		var entry := entries.get(entry_id) as WorldLootEntry
		assert(entry != null)
		_insert(entry_id, entry.world_position)

func can_index_position(position: Vector3) -> bool:
	return (
		position.is_finite()
		and _is_cell_coordinate(position.x)
		and _is_cell_coordinate(position.y)
		and _is_cell_coordinate(position.z)
	)

func get_entry_count() -> int:
	return _positions.size()

func _insert(entry_id: int, position: Vector3) -> void:
	assert(
		entry_id > 0
		and can_index_position(position)
		and not _positions.has(entry_id)
		and _positions.size() < MAXIMUM_ENTRY_COUNT
	)
	var cell := _cell_at(position)
	_positions[entry_id] = position
	if not _cells.has(cell):
		_cells[cell] = {}
	var bucket := _cells[cell] as Dictionary
	bucket[entry_id] = true

func _cell_at(position: Vector3) -> Vector3i:
	assert(can_index_position(position))
	return Vector3i(
		floori(position.x / _cell_size),
		floori(position.y / _cell_size),
		floori(position.z / _cell_size),
	)

func _is_cell_coordinate(coordinate: float) -> bool:
	var scaled: float = floor(coordinate / _cell_size)
	return (
		is_finite(scaled)
		and scaled >= MINIMUM_CELL_COORDINATE
		and scaled <= MAXIMUM_CELL_COORDINATE
	)
