extends RefCounted
class_name StructureDraft

enum Format {
	GENERIC_STRUCTURE,
	LEVEL_MODULE,
}

class SocketEdit:
	var socket: LevelSocketDefinition
	var changed_cells: Array[Vector3i]
	var removed_torch_cells: Array[Vector3i]
	var aperture_cells: Array[Vector3i]

const DEFAULT_LEVEL_MODULE_SIZE: Vector3i = Vector3i(7, 4, 7)

var _format: Format
var _size: Vector3i
var _cells: PackedInt32Array
var _torches_by_cell: Dictionary = {}
var _torch_cells_by_support: Dictionary = {}
var _sockets: Array[LevelSocketDefinition] = []
var _spawn_marker: LevelMarkerDefinition
var _return_door_marker: LevelMarkerDefinition
var _weight: float = 1.0
var _required_air_cells: Dictionary = {}
var _required_solid_cells: Dictionary = {}
var _required_non_air_cells: Dictionary = {}
var _socket_aperture_owners: Dictionary = {}
var _identifier: StringName
var _source_path: String
var _dirty: bool

func _init(p_format: Format, p_size: Vector3i, p_cells: PackedInt32Array) -> void:
	assert(p_format == Format.GENERIC_STRUCTURE or p_format == Format.LEVEL_MODULE)
	assert(StructureDefinition.is_valid_size(p_size) if p_format == Format.GENERIC_STRUCTURE else is_valid_level_module_size(p_size))
	assert(p_cells.size() == p_size.x * p_size.y * p_size.z)
	for value in p_cells:
		assert(StructureCell.is_generic_valid(value) if p_format == Format.GENERIC_STRUCTURE else StructureCell.is_valid(value))
	_format = p_format
	_size = p_size
	_cells = p_cells.duplicate()

static func create_generic(size: Vector3i = StructureDefinition.DEFAULT_SIZE) -> StructureDraft:
	if not StructureDefinition.is_valid_size(size):
		return null
	return StructureDraft.new(Format.GENERIC_STRUCTURE, size, _air_cells(size))

static func create_level_module(size: Vector3i = DEFAULT_LEVEL_MODULE_SIZE) -> StructureDraft:
	if not is_valid_level_module_size(size):
		return null
	return StructureDraft.new(Format.LEVEL_MODULE, size, _air_cells(size))

static func restore_structure(definition: StructureDefinition, source_path: String) -> StructureDraft:
	if definition == null or not definition.validate() or not source_path.is_absolute_path():
		return null
	var draft := StructureDraft.new(Format.GENERIC_STRUCTURE, definition.size, definition.cells)
	draft._identifier = definition.structure_id
	draft._source_path = source_path.simplify_path()
	for torch in definition.torches:
		draft._add_torch(_copy_torch(torch))
	return draft

static func restore_level_module(definition: LevelModuleDefinition, source_path: String) -> StructureDraft:
	if definition == null or not definition.validate() or not source_path.is_absolute_path():
		return null
	var draft := StructureDraft.new(Format.LEVEL_MODULE, definition.size, definition.cells)
	draft._identifier = definition.module_id
	draft._source_path = source_path.simplify_path()
	draft._weight = definition.weight
	for torch in definition.torches:
		var copied_torch := StructureTorchDefinition.new()
		copied_torch.cell = torch.cell
		copied_torch.support_direction = LevelSocketDefinition.vector_for(torch.wall_direction)
		draft._add_torch(copied_torch)
	for socket in definition.sockets:
		draft._sockets.append(_copy_socket(socket))
	draft._spawn_marker = _copy_marker(definition.spawn_marker)
	draft._return_door_marker = _copy_marker(definition.return_door_marker)
	draft._index_module_metadata()
	return draft

static func is_valid_level_module_size(value: Vector3i) -> bool:
	if value.x <= 0 or value.y <= 0 or value.z <= 0:
		return false
	return value.x <= LevelDefinition.HARD_MAX_EXTENT.x and value.y <= LevelDefinition.HARD_MAX_EXTENT.y and value.z <= LevelDefinition.HARD_MAX_EXTENT.z

func get_format() -> Format:
	return _format

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
	var copied: Array[StructureTorchDefinition] = []
	for cell_value in _torches_by_cell:
		var cell := cell_value as Vector3i
		copied.append(_copy_torch(_torches_by_cell[cell] as StructureTorchDefinition))
	return copied

func has_torch(cell: Vector3i) -> bool:
	return _torches_by_cell.has(cell)

func get_sockets() -> Array[LevelSocketDefinition]:
	var copied: Array[LevelSocketDefinition] = []
	for socket in _sockets:
		copied.append(_copy_socket(socket))
	return copied

func get_socket_aperture_cells(socket_id: StringName) -> Array[Vector3i]:
	for socket in _sockets:
		if socket.socket_id == socket_id:
			return LevelSocketAperture.find_cells(socket, _size, _cells)
	return []

func get_socket_candidate_cells(cell: Vector3i, direction: LevelSocketDefinition.Direction) -> Array[Vector3i]:
	if _format != Format.LEVEL_MODULE or not LevelSocketDefinition.is_valid_direction(direction) or not is_in_bounds(cell):
		return []
	var edit := _prepare_socket_edit(cell, direction)
	if edit != null:
		return edit.aperture_cells.duplicate()
	var socket := LevelSocketDefinition.new()
	socket.cell = cell
	socket.direction = direction
	return LevelSocketAperture.find_cells(socket, _size, _cells)

func get_boundary_directions(cell: Vector3i) -> Array[LevelSocketDefinition.Direction]:
	var directions: Array[LevelSocketDefinition.Direction] = []
	if _format != Format.LEVEL_MODULE or not is_in_bounds(cell):
		return directions
	for value in LevelSocketDefinition.Direction.values():
		var direction := value as LevelSocketDefinition.Direction
		if LevelSocketAperture.is_boundary(cell, _size, direction):
			directions.append(direction)
	return directions

func has_socket_direction(direction: LevelSocketDefinition.Direction) -> bool:
	for socket in _sockets:
		if socket.direction == direction:
			return true
	return false

func get_spawn_marker() -> LevelMarkerDefinition:
	return _copy_marker(_spawn_marker)

func get_return_door_marker() -> LevelMarkerDefinition:
	return _copy_marker(_return_door_marker)

func get_weight() -> float:
	return _weight

func get_identifier() -> StringName:
	return _identifier

func get_source_path() -> String:
	return _source_path

func is_bound() -> bool:
	return not _identifier.is_empty() and not _source_path.is_empty()

func is_dirty() -> bool:
	return _dirty

func is_empty() -> bool:
	for value in _cells:
		if StructureCell.is_structure_solid(value):
			return false
	return true

func can_place_block(cell: Vector3i, block_id: int) -> bool:
	if not is_in_bounds(cell) or not StructureCell.is_structure_solid(block_id):
		return false
	if StructureCell.is_structure_solid(get_cell(cell)) or has_torch(cell):
		return false
	return not _required_air_cells.has(cell)

func try_place_block(cell: Vector3i, block_id: int) -> StructureDraftChange:
	if not can_place_block(cell, block_id):
		return StructureDraftChange.reject()
	_set_cell(cell, block_id)
	return _commit_change([cell])

func try_remove_block(cell: Vector3i) -> StructureDraftChange:
	if not is_in_bounds(cell) or not StructureCell.is_structure_solid(get_cell(cell)):
		return StructureDraftChange.reject()
	if _required_solid_cells.has(cell) or _required_non_air_cells.has(cell):
		return StructureDraftChange.reject()
	var removed_torch_cells := _get_torch_cells_supported_by(cell)
	_set_cell(cell, StructureCell.AIR)
	for torch_cell in removed_torch_cells:
		_remove_torch(torch_cell)
	return _commit_change([cell], [], removed_torch_cells)

func try_set_void(cell: Vector3i) -> StructureDraftChange:
	if _format != Format.LEVEL_MODULE or not is_in_bounds(cell):
		return StructureDraftChange.reject()
	if get_cell(cell) == StructureCell.VOID or has_torch(cell):
		return StructureDraftChange.reject()
	if _required_air_cells.has(cell) or _required_solid_cells.has(cell):
		return StructureDraftChange.reject()
	var removed_torch_cells := _get_torch_cells_supported_by(cell)
	_set_cell(cell, StructureCell.VOID)
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

func try_add_socket(cell: Vector3i, direction: LevelSocketDefinition.Direction) -> StructureDraftChange:
	var edit := _prepare_socket_edit(cell, direction)
	if edit == null:
		return StructureDraftChange.reject()
	for changed_cell in edit.changed_cells:
		_set_cell(changed_cell, StructureCell.AIR)
	for torch_cell in edit.removed_torch_cells:
		_remove_torch(torch_cell)
	_sockets.append(edit.socket)
	_add_socket_requirements(edit.socket)
	return _commit_change(edit.changed_cells, [], edit.removed_torch_cells, true)

func can_add_socket(cell: Vector3i, direction: LevelSocketDefinition.Direction) -> bool:
	return _prepare_socket_edit(cell, direction) != null

func try_remove_socket(socket_id: StringName) -> StructureDraftChange:
	if _format != Format.LEVEL_MODULE or socket_id.is_empty():
		return StructureDraftChange.reject()
	for index in _sockets.size():
		var socket := _sockets[index]
		if socket.socket_id != socket_id:
			continue
		_remove_socket_requirements(socket)
		_sockets.remove_at(index)
		return _commit_change([], [], [], true)
	return StructureDraftChange.reject()

func try_set_markers(
	spawn_cell: Vector3i,
	spawn_facing: LevelSocketDefinition.Direction,
	return_cell: Vector3i,
	return_facing: LevelSocketDefinition.Direction,
) -> StructureDraftChange:
	if _format != Format.LEVEL_MODULE:
		return StructureDraftChange.reject()
	if not LevelSocketDefinition.is_valid_direction(spawn_facing) or not LevelSocketDefinition.is_valid_direction(return_facing):
		return StructureDraftChange.reject()
	var spawn := LevelMarkerDefinition.new()
	spawn.cell = spawn_cell
	spawn.facing = spawn_facing
	var return_marker := LevelMarkerDefinition.new()
	return_marker.cell = return_cell
	return_marker.facing = return_facing
	if not _marker_is_valid(spawn) or not _marker_is_valid(return_marker):
		return StructureDraftChange.reject()
	if _markers_equal(_spawn_marker, spawn) and _markers_equal(_return_door_marker, return_marker):
		return StructureDraftChange.reject()
	_remove_marker_requirements(_spawn_marker)
	_remove_marker_requirements(_return_door_marker)
	_spawn_marker = spawn
	_return_door_marker = return_marker
	_add_marker_requirements(_spawn_marker)
	_add_marker_requirements(_return_door_marker)
	return _commit_change([], [], [], true)

func try_clear_markers() -> StructureDraftChange:
	if _format != Format.LEVEL_MODULE or _spawn_marker == null:
		return StructureDraftChange.reject()
	assert(_return_door_marker != null)
	_remove_marker_requirements(_spawn_marker)
	_remove_marker_requirements(_return_door_marker)
	_spawn_marker = null
	_return_door_marker = null
	return _commit_change([], [], [], true)

func try_set_weight(value: float) -> StructureDraftChange:
	if _format != Format.LEVEL_MODULE or not is_finite(value) or value <= 0.0 or _weight == value:
		return StructureDraftChange.reject()
	_weight = value
	return _commit_change([], [], [], true)

func accept_export(identifier: StringName, source_path: String) -> bool:
	var simplified_path := source_path.simplify_path()
	if not StructureDefinition.is_valid_id(identifier) or not simplified_path.is_absolute_path():
		return false
	if is_bound() and (_identifier != identifier or _source_path != simplified_path):
		return false
	_identifier = identifier
	_source_path = simplified_path
	_dirty = false
	return true

func _commit_change(
	changed_cells: Array[Vector3i],
	added_torches: Array[StructureTorchDefinition] = [],
	removed_torch_cells: Array[Vector3i] = [],
	metadata_changed: bool = false,
) -> StructureDraftChange:
	_dirty = true
	return StructureDraftChange.success(changed_cells, added_torches, removed_torch_cells, metadata_changed)

func _prepare_socket_edit(cell: Vector3i, direction: LevelSocketDefinition.Direction) -> SocketEdit:
	if _format != Format.LEVEL_MODULE or not LevelSocketDefinition.is_valid_direction(direction) or not LevelSocketAperture.is_boundary(cell, _size, direction):
		return null
	for socket in _sockets:
		if socket.cell == cell:
			return null
	var upper := cell + Vector3i.UP
	if not is_in_bounds(upper):
		return null
	for changed_cell in [cell, upper]:
		if _required_solid_cells.has(changed_cell) or _required_non_air_cells.has(changed_cell):
			return null
	var socket := LevelSocketDefinition.new()
	socket.socket_id = _next_socket_id(direction)
	socket.cell = cell
	socket.direction = direction
	var changes: Dictionary = {cell: StructureCell.AIR, upper: StructureCell.AIR}
	if not LevelSocketAperture.is_valid(socket, _size, _cells, changes):
		return null
	var aperture_cells := LevelSocketAperture.find_cells(socket, _size, _cells, changes)
	for aperture_cell in aperture_cells:
		if _socket_aperture_owners.has(aperture_cell):
			return null
	var edit := SocketEdit.new()
	edit.socket = socket
	for aperture_cell in [cell, upper]:
		if get_cell(aperture_cell) != StructureCell.AIR:
			edit.changed_cells.append(aperture_cell)
	edit.removed_torch_cells = _get_torch_cells_supported_by_many(edit.changed_cells)
	edit.aperture_cells = aperture_cells
	return edit

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

func _get_torch_cells_supported_by_many(support_cells: Array[Vector3i]) -> Array[Vector3i]:
	var indexed: Dictionary = {}
	for support_cell in support_cells:
		for torch_cell in _get_torch_cells_supported_by(support_cell):
			indexed[torch_cell] = true
	var cells: Array[Vector3i] = []
	for cell_value in indexed:
		cells.append(cell_value as Vector3i)
	cells.sort_custom(_cell_less)
	return cells

func _index_module_metadata() -> void:
	assert(_format == Format.LEVEL_MODULE)
	for socket in _sockets:
		_add_socket_requirements(socket)
	_add_marker_requirements(_spawn_marker)
	_add_marker_requirements(_return_door_marker)

func _add_socket_requirements(socket: LevelSocketDefinition) -> void:
	var inward := -LevelSocketDefinition.vector_for(socket.direction)
	var aperture_cells := LevelSocketAperture.find_cells(socket, _size, _cells)
	var aperture_lookup: Dictionary = {}
	for aperture_cell in aperture_cells:
		aperture_lookup[aperture_cell] = true
		_socket_aperture_owners[aperture_cell] = socket.socket_id
		_increment_requirement(_required_air_cells, aperture_cell)
		_increment_requirement(_required_air_cells, aperture_cell + inward)
	var closure_cells := _socket_closure_cells(aperture_cells, aperture_lookup, socket.direction)
	for closure_cell in closure_cells:
		_increment_requirement(_required_non_air_cells, closure_cell)
	for aperture_cell in aperture_cells:
		var floor_cell := aperture_cell + Vector3i.DOWN
		if not aperture_lookup.has(floor_cell):
			_increment_requirement(_required_solid_cells, floor_cell)

func _remove_socket_requirements(socket: LevelSocketDefinition) -> void:
	var inward := -LevelSocketDefinition.vector_for(socket.direction)
	var aperture_cells := LevelSocketAperture.find_cells(socket, _size, _cells)
	var aperture_lookup: Dictionary = {}
	for aperture_cell in aperture_cells:
		aperture_lookup[aperture_cell] = true
		_socket_aperture_owners.erase(aperture_cell)
		_decrement_requirement(_required_air_cells, aperture_cell)
		_decrement_requirement(_required_air_cells, aperture_cell + inward)
	var closure_cells := _socket_closure_cells(aperture_cells, aperture_lookup, socket.direction)
	for closure_cell in closure_cells:
		_decrement_requirement(_required_non_air_cells, closure_cell)
	for aperture_cell in aperture_cells:
		var floor_cell := aperture_cell + Vector3i.DOWN
		if not aperture_lookup.has(floor_cell):
			_decrement_requirement(_required_solid_cells, floor_cell)

func _socket_closure_cells(
	aperture_cells: Array[Vector3i],
	aperture_lookup: Dictionary,
	direction: LevelSocketDefinition.Direction,
) -> Array[Vector3i]:
	var closure_lookup: Dictionary = {}
	var transverse := Vector3i.RIGHT if direction == LevelSocketDefinition.Direction.NORTH or direction == LevelSocketDefinition.Direction.SOUTH else Vector3i.BACK
	for aperture_cell in aperture_cells:
		for offset in [Vector3i.UP, Vector3i.DOWN, transverse, -transverse]:
			var neighbor: Vector3i = aperture_cell + offset
			if aperture_lookup.has(neighbor) or not LevelSocketAperture.is_boundary(neighbor, _size, direction):
				continue
			closure_lookup[neighbor] = true
	var closure_cells: Array[Vector3i] = []
	for cell_value in closure_lookup:
		closure_cells.append(cell_value as Vector3i)
	closure_cells.sort_custom(_cell_less)
	return closure_cells

func _add_marker_requirements(marker: LevelMarkerDefinition) -> void:
	if marker == null:
		return
	_increment_requirement(_required_air_cells, marker.cell)
	_increment_requirement(_required_air_cells, marker.cell + Vector3i.UP)
	_increment_requirement(_required_solid_cells, marker.cell + Vector3i.DOWN)

func _remove_marker_requirements(marker: LevelMarkerDefinition) -> void:
	if marker == null:
		return
	_decrement_requirement(_required_air_cells, marker.cell)
	_decrement_requirement(_required_air_cells, marker.cell + Vector3i.UP)
	_decrement_requirement(_required_solid_cells, marker.cell + Vector3i.DOWN)

func _increment_requirement(index: Dictionary, cell: Vector3i) -> void:
	index[cell] = int(index.get(cell, 0)) + 1

func _decrement_requirement(index: Dictionary, cell: Vector3i) -> void:
	var count := int(index.get(cell, 0))
	assert(count > 0)
	if count == 1:
		index.erase(cell)
	else:
		index[cell] = count - 1

func _marker_is_valid(marker: LevelMarkerDefinition) -> bool:
	var upper := marker.cell + Vector3i.UP
	var floor_cell := marker.cell + Vector3i.DOWN
	if not is_in_bounds(marker.cell) or not is_in_bounds(upper) or not is_in_bounds(floor_cell):
		return false
	return get_cell(marker.cell) == StructureCell.AIR and get_cell(upper) == StructureCell.AIR and StructureCell.is_structure_solid(get_cell(floor_cell))

func _next_socket_id(direction: LevelSocketDefinition.Direction) -> StringName:
	var base := String(LevelSocketDefinition.Direction.find_key(direction)).to_lower()
	var used: Dictionary = {}
	for socket in _sockets:
		used[socket.socket_id] = true
	if not used.has(StringName(base)):
		return StringName(base)
	var suffix := 2
	while used.has(StringName("%s_%d" % [base, suffix])):
		suffix += 1
	return StringName("%s_%d" % [base, suffix])

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

static func _copy_socket(source: LevelSocketDefinition) -> LevelSocketDefinition:
	if source == null:
		return null
	var copied := LevelSocketDefinition.new()
	copied.socket_id = source.socket_id
	copied.cell = source.cell
	copied.direction = source.direction
	return copied

static func _copy_marker(source: LevelMarkerDefinition) -> LevelMarkerDefinition:
	if source == null:
		return null
	var copied := LevelMarkerDefinition.new()
	copied.cell = source.cell
	copied.facing = source.facing
	return copied

static func _markers_equal(first: LevelMarkerDefinition, second: LevelMarkerDefinition) -> bool:
	if first == null or second == null:
		return first == second
	return first.cell == second.cell and first.facing == second.facing

static func _cell_less(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z
