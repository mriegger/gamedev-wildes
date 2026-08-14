extends RefCounted
class_name EntitySpatialIndex

class Entry:
	var position: Vector3
	var bounds: AABB
	var min_cell: Vector3i
	var max_cell: Vector3i

	func _init(p_position: Vector3, p_bounds: AABB, p_min_cell: Vector3i, p_max_cell: Vector3i) -> void:
		position = p_position
		bounds = p_bounds
		min_cell = p_min_cell
		max_cell = p_max_cell

var _cell_size: float
var _entries: Dictionary = {}
var _cells: Dictionary = {}

func _init(p_cell_size: float) -> void:
	assert(is_finite(p_cell_size) and p_cell_size > 0.0)
	_cell_size = p_cell_size

func upsert(runtime_id: int, position: Vector3, bounds: AABB) -> void:
	assert(runtime_id >= 0)
	assert(position.is_finite())
	assert(bounds.position.is_finite() and bounds.size.is_finite())
	assert(bounds.size.x > 0.0 and bounds.size.y > 0.0 and bounds.size.z > 0.0)
	assert(bounds.has_point(position))
	var min_cell := _cell_at(bounds.position)
	var max_cell := _cell_at(bounds.end - Vector3.ONE * 0.000001)
	if _entries.has(runtime_id):
		var existing := _entries[runtime_id] as Entry
		existing.position = position
		existing.bounds = bounds
		if existing.min_cell == min_cell and existing.max_cell == max_cell:
			return
		_unindex(runtime_id, existing)
		existing.min_cell = min_cell
		existing.max_cell = max_cell
		_index(runtime_id, existing)
		return
	var entry := Entry.new(position, bounds, min_cell, max_cell)
	_entries[runtime_id] = entry
	_index(runtime_id, entry)

func remove(runtime_id: int) -> bool:
	if not _entries.has(runtime_id):
		return false
	_unindex(runtime_id, _entries[runtime_id] as Entry)
	_entries.erase(runtime_id)
	return true

func clear() -> void:
	_entries.clear()
	_cells.clear()

func query_nearby(position: Vector3, radius: float) -> Array[int]:
	assert(position.is_finite())
	assert(is_finite(radius) and radius >= 0.0)
	var extent := Vector3.ONE * radius
	var min_cell := _cell_at(position - extent)
	var max_cell := _cell_at(position + extent)
	var candidates := _collect_candidates(min_cell, max_cell)
	var radius_squared := radius * radius
	var result: Array[int] = []
	for runtime_id in candidates:
		var entry := _entries[runtime_id] as Entry
		if entry.position.distance_squared_to(position) <= radius_squared:
			result.append(runtime_id as int)
	result.sort()
	return result

func query_overlapping(bounds: AABB) -> Array[int]:
	assert(bounds.position.is_finite() and bounds.size.is_finite())
	assert(bounds.size.x > 0.0 and bounds.size.y > 0.0 and bounds.size.z > 0.0)
	var cells := _cell_range_for_bounds(bounds)
	var candidates := _collect_candidates(cells[0], cells[1])
	var result: Array[int] = []
	for runtime_id in candidates:
		var entry := _entries[runtime_id] as Entry
		if entry.bounds.intersects(bounds):
			result.append(runtime_id as int)
	result.sort()
	return result

func get_entry_count() -> int:
	return _entries.size()

func get_cell_count() -> int:
	return _cells.size()

func _unindex(runtime_id: int, entry: Entry) -> void:
	for x in range(entry.min_cell.x, entry.max_cell.x + 1):
		for y in range(entry.min_cell.y, entry.max_cell.y + 1):
			for z in range(entry.min_cell.z, entry.max_cell.z + 1):
				var cell := Vector3i(x, y, z)
				var bucket := _cells[cell] as Dictionary
				bucket.erase(runtime_id)
				if bucket.is_empty():
					_cells.erase(cell)

func _index(runtime_id: int, entry: Entry) -> void:
	for x in range(entry.min_cell.x, entry.max_cell.x + 1):
		for y in range(entry.min_cell.y, entry.max_cell.y + 1):
			for z in range(entry.min_cell.z, entry.max_cell.z + 1):
				var cell := Vector3i(x, y, z)
				if not _cells.has(cell):
					_cells[cell] = {}
				var bucket := _cells[cell] as Dictionary
				bucket[runtime_id] = true

func _cell_range_for_bounds(bounds: AABB) -> Array[Vector3i]:
	var epsilon := Vector3.ONE * 0.000001
	return [_cell_at(bounds.position), _cell_at(bounds.end - epsilon)]

func _cell_at(position: Vector3) -> Vector3i:
	return Vector3i(
		floori(position.x / _cell_size),
		floori(position.y / _cell_size),
		floori(position.z / _cell_size)
	)

func _collect_candidates(min_cell: Vector3i, max_cell: Vector3i) -> Dictionary:
	var candidates: Dictionary = {}
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			for z in range(min_cell.z, max_cell.z + 1):
				var cell := Vector3i(x, y, z)
				if not _cells.has(cell):
					continue
				var bucket := _cells[cell] as Dictionary
				for runtime_id in bucket:
					candidates[runtime_id] = true
	return candidates
