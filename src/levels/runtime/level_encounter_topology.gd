extends RefCounted
class_name LevelEncounterTopology

var _rooms_by_id: Dictionary = {}
var _room_ids: Array[int] = []
var _doorways: Array[LevelDoorway] = []

static func create(layout: LevelLayout, definition: LevelDefinition) -> LevelEncounterTopology:
	if layout == null or definition == null:
		return null
	var topology := LevelEncounterTopology.new()
	return topology if topology._build(layout, definition) else null

func get_room_ids() -> Array[int]:
	return _room_ids.duplicate()

func get_room(room_id: int) -> LevelEncounterRoom:
	return _rooms_by_id.get(room_id) as LevelEncounterRoom

func get_doorways() -> Array[LevelDoorway]:
	return _doorways.duplicate()

func find_room_containing_body(feet_position: Vector3, body_width: float, body_height: float) -> int:
	for room_id in _room_ids:
		var room := get_room(room_id)
		if room.contains_body(feet_position, body_width, body_height, _doorways):
			return room_id
	return -1

func _build(layout: LevelLayout, definition: LevelDefinition) -> bool:
	if layout.placed_modules.is_empty() or layout.connections.size() != layout.placed_modules.size() - 1:
		return false
	var placements: Dictionary = {}
	var connections: Dictionary = {}
	var adjacency: Dictionary = {}
	for placement in layout.placed_modules:
		if placement == null or placement.placement_id < 0 or placements.has(placement.placement_id):
			return false
		placements[placement.placement_id] = placement
		adjacency[placement.placement_id] = []
	if not placements.has(0):
		return false
	for connection in layout.connections:
		if connection == null or connections.has(connection.connection_id):
			return false
		if not placements.has(connection.first_placement_id) or not placements.has(connection.second_placement_id):
			return false
		connections[connection.connection_id] = connection
		(adjacency[connection.first_placement_id] as Array).append(connection.connection_id)
		(adjacency[connection.second_placement_id] as Array).append(connection.connection_id)
	var parent_placement: Dictionary = {0: -1}
	var parent_connection: Dictionary = {}
	var pending: Array[int] = [0]
	var pending_index := 0
	while pending_index < pending.size():
		var placement_id := pending[pending_index]
		pending_index += 1
		for connection_id in adjacency[placement_id] as Array:
			var connection := connections[connection_id] as LevelConnection
			var neighbor := connection.second_placement_id if connection.first_placement_id == placement_id else connection.first_placement_id
			if parent_placement.has(neighbor):
				if int(parent_placement[placement_id]) != neighbor:
					return false
				continue
			parent_placement[neighbor] = placement_id
			parent_connection[neighbor] = connection_id
			pending.append(neighbor)
	if parent_placement.size() != placements.size():
		return false
	var requirements: Dictionary = {}
	for requirement in definition.room_requirements:
		if requirement != null:
			requirements[requirement.room_type_id] = requirement
	var room_parent_ids: Dictionary = {}
	var room_child_ids: Dictionary = {}
	var room_door_ids: Dictionary = {}
	var room_placement_ids: Array[int] = []
	var reveal_placement_owners: Dictionary = {}
	for placement_id in placements:
		var placement := placements[placement_id] as LevelPlacedModule
		if placement.room_type_id.is_empty():
			continue
		if not requirements.has(placement.room_type_id):
			return false
		room_placement_ids.append(placement_id)
		room_child_ids[placement_id] = []
		room_door_ids[placement_id] = []
		var ancestor_id := int(parent_placement[placement_id])
		while ancestor_id >= 0 and (placements[ancestor_id] as LevelPlacedModule).room_type_id.is_empty():
			ancestor_id = int(parent_placement[ancestor_id])
		room_parent_ids[placement_id] = ancestor_id
	room_placement_ids.sort()
	for room_id in room_placement_ids:
		var parent_room_id := int(room_parent_ids[room_id])
		if parent_room_id >= 0:
			if not room_child_ids.has(parent_room_id):
				return false
			(room_child_ids[parent_room_id] as Array).append(room_id)
	var door_key_to_id: Dictionary = {}
	var connection_ids: Array = connections.keys()
	connection_ids.sort()
	for connection_id in connection_ids:
		var connection := connections[connection_id] as LevelConnection
		if room_door_ids.has(connection.first_placement_id):
			if not _append_doorway(
				connection,
				placements[connection.first_placement_id] as LevelPlacedModule,
				connection.first_socket_id,
				connection.first_direction,
				connection.first_aperture_cells,
				room_door_ids,
				door_key_to_id
			):
				return false
		if room_door_ids.has(connection.second_placement_id):
			if not _append_doorway(
				connection,
				placements[connection.second_placement_id] as LevelPlacedModule,
				connection.second_socket_id,
				connection.second_direction,
				connection.second_aperture_cells,
				room_door_ids,
				door_key_to_id
			):
				return false
	for room_id in room_placement_ids:
		var placement := placements[room_id] as LevelPlacedModule
		var requirement := requirements[placement.room_type_id] as LevelRoomRequirement
		if requirement.encounter == null or not parent_connection.has(room_id):
			return false
		var parent_door_key := _door_key(room_id, int(parent_connection[room_id]))
		if not door_key_to_id.has(parent_door_key):
			return false
		var enemy_ids: Array[StringName] = []
		for group in requirement.encounter.enemy_groups:
			for _index in group.count:
				enemy_ids.append(group.entity_id)
		var spawn_cells: Array[Vector3i] = []
		for local_cell in placement.definition.get_enemy_spawn_candidate_cells():
			spawn_cells.append(placement.world_cell(local_cell))
		var interior_cells: Dictionary = {}
		for y in placement.definition.size.y:
			for z in placement.definition.size.z:
				for x in placement.definition.size.x:
					var local_cell := Vector3i(x, y, z)
					if placement.definition.cell_at(local_cell) == StructureCell.AIR:
						interior_cells[placement.world_cell(local_cell)] = true
		var child_ids: Array[int] = []
		child_ids.assign(room_child_ids[room_id])
		child_ids.sort()
		var door_ids: Array[int] = []
		door_ids.assign(room_door_ids[room_id])
		door_ids.sort()
		var reveal_placement_ids := _collect_reveal_placement_ids(room_id, int(room_parent_ids[room_id]), parent_placement)
		if enemy_ids.is_empty() or spawn_cells.is_empty() or door_ids.is_empty() or reveal_placement_ids.is_empty():
			return false
		for placement_id in reveal_placement_ids:
			if placement_id == 0 or reveal_placement_owners.has(placement_id):
				return false
			reveal_placement_owners[placement_id] = room_id
		_rooms_by_id[room_id] = LevelEncounterRoom.new(
			room_id,
			int(room_parent_ids[room_id]),
			int(door_key_to_id[parent_door_key]),
			child_ids,
			door_ids,
			enemy_ids,
			spawn_cells,
			reveal_placement_ids,
			interior_cells
		)
	if reveal_placement_owners.size() != placements.size() - 1:
		return false
	_room_ids.assign(room_placement_ids)
	return not _rooms_by_id.is_empty()

func _append_doorway(
	connection: LevelConnection,
	placement: LevelPlacedModule,
	socket_id: StringName,
	direction: LevelSocketDefinition.Direction,
	aperture_cells: Array[Vector3i],
	room_door_ids: Dictionary,
	door_key_to_id: Dictionary,
) -> bool:
	var fill_block_id := _find_socket_fill_block(placement.definition, socket_id)
	if not StructureCell.is_structure_solid(fill_block_id):
		return false
	var door_id := _doorways.size()
	_doorways.append(LevelDoorway.new(
		door_id,
		placement.placement_id,
		direction,
		aperture_cells,
		fill_block_id,
	))
	(room_door_ids[placement.placement_id] as Array).append(door_id)
	door_key_to_id[_door_key(placement.placement_id, connection.connection_id)] = door_id
	return true

func _find_socket_fill_block(module: LevelModuleDefinition, socket_id: StringName) -> int:
	for socket in module.sockets:
		if socket != null and socket.socket_id == socket_id:
			return socket.unused_fill_block_id
	return StructureCell.AIR

func _collect_reveal_placement_ids(room_id: int, parent_room_id: int, parent_placement: Dictionary) -> Array[int]:
	var result: Array[int] = []
	var stop_placement_id := parent_room_id if parent_room_id >= 0 else 0
	var placement_id := room_id
	while placement_id != stop_placement_id:
		if placement_id < 0 or not parent_placement.has(placement_id):
			return []
		result.push_front(placement_id)
		placement_id = int(parent_placement[placement_id])
	return result

func _door_key(room_id: int, connection_id: int) -> String:
	return "%d:%d" % [room_id, connection_id]
