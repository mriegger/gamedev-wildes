extends RefCounted
class_name WorldLootSpatialIndex

const MAXIMUM_ENTRY_COUNT: int = 128
const MAXIMUM_BUCKET_PROBES: int = 4096
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

func query_ids(position: Vector3, radius: float) -> Array[int]:
	assert(position.is_finite())
	assert(is_finite(radius) and radius >= 0.0)
	var bounds := _query_cell_bounds(position, radius)
	if bounds.is_empty():
		return _scan_ids(position, radius)
	var minimum := bounds[0] as Vector3i
	var maximum := bounds[1] as Vector3i
	if not _is_probe_count_bounded(minimum, maximum):
		return _scan_ids(position, radius)
	var result: Array[int] = []
	for x in range(minimum.x, maximum.x + 1):
		for y in range(minimum.y, maximum.y + 1):
			for z in range(minimum.z, maximum.z + 1):
				var cell := Vector3i(x, y, z)
				if not _cells.has(cell):
					continue
				var bucket := _cells[cell] as Dictionary
				for raw_entry_id in bucket:
					var entry_id := int(raw_entry_id)
					var entry_position := _positions[entry_id] as Vector3
					if _is_within_radius(entry_position, position, radius):
						result.append(entry_id)
	result.sort()
	return result

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

func _query_cell_bounds(position: Vector3, radius: float) -> Array[Vector3i]:
	var minimum_x: float = floor((position.x - radius) / _cell_size)
	var minimum_y: float = floor((position.y - radius) / _cell_size)
	var minimum_z: float = floor((position.z - radius) / _cell_size)
	var maximum_x: float = floor((position.x + radius) / _cell_size)
	var maximum_y: float = floor((position.y + radius) / _cell_size)
	var maximum_z: float = floor((position.z + radius) / _cell_size)
	for coordinate in [
		minimum_x,
		minimum_y,
		minimum_z,
		maximum_x,
		maximum_y,
		maximum_z,
	]:
		if (
			not is_finite(coordinate)
			or coordinate < MINIMUM_CELL_COORDINATE
			or coordinate > MAXIMUM_CELL_COORDINATE
		):
			return []
	return [
		Vector3i(int(minimum_x), int(minimum_y), int(minimum_z)),
		Vector3i(int(maximum_x), int(maximum_y), int(maximum_z)),
	]

func _is_cell_coordinate(coordinate: float) -> bool:
	var scaled: float = floor(coordinate / _cell_size)
	return (
		is_finite(scaled)
		and scaled >= MINIMUM_CELL_COORDINATE
		and scaled <= MAXIMUM_CELL_COORDINATE
	)

func _is_probe_count_bounded(minimum: Vector3i, maximum: Vector3i) -> bool:
	var x_count := int(maximum.x) - int(minimum.x) + 1
	var y_count := int(maximum.y) - int(minimum.y) + 1
	var z_count := int(maximum.z) - int(minimum.z) + 1
	if x_count < 1 or y_count < 1 or z_count < 1:
		return false
	if x_count > MAXIMUM_BUCKET_PROBES:
		return false
	if y_count > MAXIMUM_BUCKET_PROBES / x_count:
		return false
	var xy_count := x_count * y_count
	return z_count <= MAXIMUM_BUCKET_PROBES / xy_count

func _scan_ids(position: Vector3, radius: float) -> Array[int]:
	assert(_positions.size() <= MAXIMUM_ENTRY_COUNT)
	var result: Array[int] = []
	for raw_entry_id in _positions:
		var entry_id := int(raw_entry_id)
		if _is_within_radius(_positions[entry_id] as Vector3, position, radius):
			result.append(entry_id)
	result.sort()
	return result

static func _is_within_radius(first: Vector3, second: Vector3, radius: float) -> bool:
	var x_distance := absf(first.x - second.x)
	var y_distance := absf(first.y - second.y)
	var z_distance := absf(first.z - second.z)
	if (
		not is_finite(x_distance)
		or not is_finite(y_distance)
		or not is_finite(z_distance)
		or x_distance > radius
		or y_distance > radius
		or z_distance > radius
	):
		return false
	if radius == 0.0:
		return x_distance == 0.0 and y_distance == 0.0 and z_distance == 0.0
	var normalized := Vector3(x_distance / radius, y_distance / radius, z_distance / radius)
	return normalized.length_squared() <= 1.0
