extends RefCounted
class_name LevelEncounterState

enum RoomStatus {
	LOCKED,
	READY,
	ACTIVE,
	CLEARED,
}

class RoomProgress:
	var definition: LevelEncounterRoom
	var status: RoomStatus = RoomStatus.LOCKED
	var enemy_ids: Array[StringName] = []
	var next_spawn_index: int = 0
	var defeated_count: int = 0
	var concurrent_capacity: int = 0
	var active_entity_ids: Dictionary = {}

	func _init(p_definition: LevelEncounterRoom, p_enemy_ids: Array[StringName]) -> void:
		definition = p_definition
		enemy_ids.assign(p_enemy_ids)

var _rooms: Dictionary = {}
var _room_ids: Array[int] = []
var _door_locks: Dictionary = {}
var _runtime_to_room: Dictionary = {}
var _runtime_to_entity: Dictionary = {}
var _active_room_id: int = -1

static func create(topology: LevelEncounterTopology, level_seed: int) -> LevelEncounterState:
	if topology == null:
		return null
	var state := LevelEncounterState.new()
	return state if state._initialize(topology, level_seed) else null

func get_active_room_id() -> int:
	return _active_room_id

func get_door_locks() -> Dictionary:
	return _door_locks.duplicate()

func get_spawned_enemy_count(room_id: int) -> int:
	var room := _rooms.get(room_id) as RoomProgress
	assert(room != null)
	return room.next_spawn_index

func get_configured_enemy_ids(room_id: int) -> Array[StringName]:
	var room := _rooms.get(room_id) as RoomProgress
	assert(room != null)
	return room.enemy_ids.duplicate()

func can_activate(room_id: int) -> bool:
	var room := _rooms.get(room_id) as RoomProgress
	return room != null and room.status == RoomStatus.READY and _active_room_id < 0 and room.next_spawn_index == 0

func can_commit_activation(room_id: int, entity_ids: Array[StringName], concurrent_capacity: int) -> bool:
	var room := _rooms.get(room_id) as RoomProgress
	return can_activate(room_id) \
		and room != null \
		and not entity_ids.is_empty() \
		and concurrent_capacity >= entity_ids.size() \
		and concurrent_capacity <= room.enemy_ids.size() \
		and _entity_ids_match_next(room, entity_ids)

func get_activation_door_changes(room_id: int) -> Dictionary:
	var room := _rooms.get(room_id) as RoomProgress
	if not can_activate(room_id) or room == null:
		return {}
	return _collect_activation_door_changes(room)

func get_defeat_door_changes(runtime_id: int, entity_id: StringName) -> Dictionary:
	var room := _get_assigned_room(runtime_id, entity_id)
	if room == null or not _will_clear_after_defeat(room):
		return {}
	return _collect_clear_door_changes(room)

func get_next_enemy_ids(room_id: int, maximum_count: int) -> Array[StringName]:
	var result: Array[StringName] = []
	var room := _rooms.get(room_id) as RoomProgress
	if room == null or maximum_count <= 0 or room.status not in [RoomStatus.READY, RoomStatus.ACTIVE]:
		return result
	var count := mini(maximum_count, room.enemy_ids.size() - room.next_spawn_index)
	for index in range(room.next_spawn_index, room.next_spawn_index + count):
		result.append(room.enemy_ids[index])
	return result

func get_refill_count(room_id: int) -> int:
	var room := _rooms.get(room_id) as RoomProgress
	if room == null or room.status != RoomStatus.ACTIVE:
		return 0
	var unspawned_count := room.enemy_ids.size() - room.next_spawn_index
	return mini(unspawned_count, room.concurrent_capacity - room.active_entity_ids.size())

func commit_activation(room_id: int, runtime_ids: Array[int], entity_ids: Array[StringName], concurrent_capacity: int) -> LevelEncounterTransition:
	if not can_commit_activation(room_id, entity_ids, concurrent_capacity) or runtime_ids.is_empty():
		return null
	var room := _rooms[room_id] as RoomProgress
	if not _can_commit_spawns(room, runtime_ids, entity_ids):
		return null
	var door_changes := _collect_activation_door_changes(room)
	_commit_spawns(room_id, room, runtime_ids, entity_ids)
	room.concurrent_capacity = concurrent_capacity
	room.status = RoomStatus.ACTIVE
	_active_room_id = room_id
	_commit_door_changes(door_changes)
	return _make_transition(room, false, door_changes)

func commit_refill(room_id: int, runtime_ids: Array[int], entity_ids: Array[StringName]) -> LevelEncounterTransition:
	var room := _rooms.get(room_id) as RoomProgress
	if room == null or room.status != RoomStatus.ACTIVE or runtime_ids.is_empty():
		return null
	if not can_commit_refill(room_id, entity_ids) or not _can_commit_spawns(room, runtime_ids, entity_ids):
		return null
	_commit_spawns(room_id, room, runtime_ids, entity_ids)
	return _make_transition(room, false, {})

func can_commit_refill(room_id: int, entity_ids: Array[StringName]) -> bool:
	var room := _rooms.get(room_id) as RoomProgress
	return room != null \
		and room.status == RoomStatus.ACTIVE \
		and not entity_ids.is_empty() \
		and entity_ids.size() <= get_refill_count(room_id) \
		and _entity_ids_match_next(room, entity_ids)

func record_defeat(runtime_id: int, entity_id: StringName) -> LevelEncounterTransition:
	var room := _get_assigned_room(runtime_id, entity_id)
	if room == null:
		return null
	var room_id := int(_runtime_to_room[runtime_id])
	var cleared := _will_clear_after_defeat(room)
	var door_changes := _collect_clear_door_changes(room) if cleared else {}
	room.active_entity_ids.erase(runtime_id)
	_runtime_to_room.erase(runtime_id)
	_runtime_to_entity.erase(runtime_id)
	room.defeated_count += 1
	if cleared:
		room.status = RoomStatus.CLEARED
		_active_room_id = -1
		for child_room_id in room.definition.child_room_ids:
			var child := _rooms[child_room_id] as RoomProgress
			assert(child.status == RoomStatus.LOCKED)
			child.status = RoomStatus.READY
		_commit_door_changes(door_changes)
	return _make_transition(room, cleared, door_changes)

func _initialize(topology: LevelEncounterTopology, level_seed: int) -> bool:
	_room_ids = topology.get_room_ids()
	if _room_ids.is_empty():
		return false
	for doorway in topology.get_doorways():
		if doorway == null or _door_locks.has(doorway.door_id):
			return false
		_door_locks[doorway.door_id] = true
	for room_id in _room_ids:
		var definition := topology.get_room(room_id)
		if definition == null:
			return false
		var enemy_ids := _shuffle_enemy_ids(definition.enemy_ids, level_seed, room_id)
		var progress := RoomProgress.new(definition, enemy_ids)
		if definition.parent_room_id < 0:
			progress.status = RoomStatus.READY
			_door_locks[definition.parent_door_id] = false
		_rooms[room_id] = progress
	return true

func _can_commit_spawns(room: RoomProgress, runtime_ids: Array[int], entity_ids: Array[StringName]) -> bool:
	if runtime_ids.size() != entity_ids.size() or not _entity_ids_match_next(room, entity_ids):
		return false
	var seen_runtime_ids: Dictionary = {}
	for index in runtime_ids.size():
		var runtime_id := runtime_ids[index]
		if runtime_id <= 0 or seen_runtime_ids.has(runtime_id) or _runtime_to_room.has(runtime_id):
			return false
		seen_runtime_ids[runtime_id] = true
	return true

func _entity_ids_match_next(room: RoomProgress, entity_ids: Array[StringName]) -> bool:
	if entity_ids.size() > room.enemy_ids.size() - room.next_spawn_index:
		return false
	for index in entity_ids.size():
		if entity_ids[index] != room.enemy_ids[room.next_spawn_index + index]:
			return false
	return true

func _commit_spawns(room_id: int, room: RoomProgress, runtime_ids: Array[int], entity_ids: Array[StringName]) -> void:
	for index in runtime_ids.size():
		var runtime_id := runtime_ids[index]
		var entity_id := entity_ids[index]
		room.active_entity_ids[runtime_id] = entity_id
		_runtime_to_room[runtime_id] = room_id
		_runtime_to_entity[runtime_id] = entity_id
	room.next_spawn_index += runtime_ids.size()

func _get_assigned_room(runtime_id: int, entity_id: StringName) -> RoomProgress:
	if not _runtime_to_room.has(runtime_id) or _runtime_to_entity.get(runtime_id, &"") != entity_id:
		return null
	var room := _rooms[int(_runtime_to_room[runtime_id])] as RoomProgress
	return room if room.status == RoomStatus.ACTIVE and room.active_entity_ids.has(runtime_id) else null

func _will_clear_after_defeat(room: RoomProgress) -> bool:
	return room.defeated_count + 1 == room.enemy_ids.size() \
		and room.next_spawn_index == room.enemy_ids.size() \
		and room.active_entity_ids.size() == 1

func _collect_activation_door_changes(room: RoomProgress) -> Dictionary:
	var changes: Dictionary = {}
	for door_id in room.definition.door_ids:
		_append_door_change(door_id, true, changes)
	return changes

func _collect_clear_door_changes(room: RoomProgress) -> Dictionary:
	var changes: Dictionary = {}
	for door_id in room.definition.door_ids:
		_append_door_change(door_id, false, changes)
	for child_room_id in room.definition.child_room_ids:
		var child := _rooms[child_room_id] as RoomProgress
		_append_door_change(child.definition.parent_door_id, false, changes)
	return changes

func _append_door_change(door_id: int, locked: bool, changes: Dictionary) -> void:
	assert(_door_locks.has(door_id))
	if bool(_door_locks[door_id]) != locked:
		changes[door_id] = locked

func _commit_door_changes(changes: Dictionary) -> void:
	for door_id in changes:
		_door_locks[door_id] = changes[door_id]

func _make_transition(room: RoomProgress, cleared: bool, door_changes: Dictionary) -> LevelEncounterTransition:
	return LevelEncounterTransition.new(
		room.active_entity_ids.size(),
		room.enemy_ids.size() - room.next_spawn_index,
		cleared,
		door_changes,
	)

func _shuffle_enemy_ids(source: Array[StringName], level_seed: int, room_id: int) -> Array[StringName]:
	var shuffled: Array[StringName] = source.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed ^ (room_id * 2654435761)
	for index in range(shuffled.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var value: StringName = shuffled[index]
		shuffled[index] = shuffled[swap_index]
		shuffled[swap_index] = value
	return shuffled
