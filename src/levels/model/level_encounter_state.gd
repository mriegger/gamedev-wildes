extends RefCounted
class_name LevelEncounterState

const MAX_CONCURRENT_ENEMIES_PER_ROOM: int = 20

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
var _sealed_door_ids: Dictionary = {}
var _runtime_to_room: Dictionary = {}
var _runtime_to_entity: Dictionary = {}

static func create(topology: LevelEncounterTopology, level_seed: int) -> LevelEncounterState:
	if topology == null:
		return null
	var state := LevelEncounterState.new()
	return state if state._initialize(topology, level_seed) else null

func get_active_room_ids() -> Array[int]:
	var active_room_ids: Array[int] = []
	for room_id in _room_ids:
		var room := _rooms[room_id] as RoomProgress
		if room.status == RoomStatus.ACTIVE:
			active_room_ids.append(room_id)
	return active_room_ids

func get_discovered_room_ids() -> Array[int]:
	var discovered_room_ids: Array[int] = []
	for room_id in _room_ids:
		var room := _rooms[room_id] as RoomProgress
		if room.status != RoomStatus.LOCKED:
			discovered_room_ids.append(room_id)
	return discovered_room_ids

func get_sealed_door_ids() -> Array[int]:
	var sealed_door_ids: Array[int] = []
	for door_id in _sealed_door_ids:
		sealed_door_ids.append(int(door_id))
	sealed_door_ids.sort()
	return sealed_door_ids

func get_summary() -> LevelEncounterSummary:
	var active_wave_count := 0
	var active_enemy_count := 0
	var pending_enemy_count := 0
	for room_id in _room_ids:
		var room := _rooms[room_id] as RoomProgress
		if room.status != RoomStatus.ACTIVE:
			continue
		active_wave_count += 1
		active_enemy_count += room.active_entity_ids.size()
		pending_enemy_count += room.enemy_ids.size() - room.defeated_count - room.active_entity_ids.size()
	return LevelEncounterSummary.new(active_wave_count, active_enemy_count, pending_enemy_count)

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
	return room != null and room.status == RoomStatus.READY and room.next_spawn_index == 0

func can_commit_activation(room_id: int, entity_ids: Array[StringName], concurrent_capacity: int) -> bool:
	var room := _rooms.get(room_id) as RoomProgress
	return can_activate(room_id) \
		and room != null \
		and not entity_ids.is_empty() \
		and concurrent_capacity >= entity_ids.size() \
		and concurrent_capacity <= MAX_CONCURRENT_ENEMIES_PER_ROOM \
		and concurrent_capacity <= room.enemy_ids.size() \
		and _entity_ids_match_next(room, entity_ids)

func get_defeat_opened_seal_ids(runtime_id: int, entity_id: StringName) -> Array[int]:
	var room := _get_assigned_room(runtime_id, entity_id)
	if room == null or not _will_clear_after_defeat(room):
		return []
	return _collect_clear_opened_seal_ids(room)

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
	var available_slots := mini(room.concurrent_capacity, MAX_CONCURRENT_ENEMIES_PER_ROOM) - room.active_entity_ids.size()
	return mini(unspawned_count, available_slots)

func commit_activation(room_id: int, runtime_ids: Array[int], entity_ids: Array[StringName], concurrent_capacity: int) -> LevelEncounterTransition:
	if not can_commit_activation(room_id, entity_ids, concurrent_capacity) or runtime_ids.is_empty():
		return null
	var room := _rooms[room_id] as RoomProgress
	if not _can_commit_spawns(room, runtime_ids, entity_ids):
		return null
	_commit_spawns(room_id, room, runtime_ids, entity_ids)
	room.concurrent_capacity = concurrent_capacity
	room.status = RoomStatus.ACTIVE
	return _make_transition(room_id, false, [])

func commit_refill(room_id: int, runtime_ids: Array[int], entity_ids: Array[StringName]) -> LevelEncounterTransition:
	var room := _rooms.get(room_id) as RoomProgress
	if room == null or room.status != RoomStatus.ACTIVE or runtime_ids.is_empty():
		return null
	if not can_commit_refill(room_id, entity_ids) or not _can_commit_spawns(room, runtime_ids, entity_ids):
		return null
	_commit_spawns(room_id, room, runtime_ids, entity_ids)
	return _make_transition(room_id, false, [])

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
	var opened_seal_ids: Array[int] = []
	if cleared:
		opened_seal_ids = _collect_clear_opened_seal_ids(room)
	room.active_entity_ids.erase(runtime_id)
	_runtime_to_room.erase(runtime_id)
	_runtime_to_entity.erase(runtime_id)
	room.defeated_count += 1
	if cleared:
		room.status = RoomStatus.CLEARED
		for child_room_id in room.definition.child_room_ids:
			var child := _rooms[child_room_id] as RoomProgress
			assert(child.status == RoomStatus.LOCKED)
			child.status = RoomStatus.READY
		_open_seals(opened_seal_ids)
	return _make_transition(room_id, cleared, opened_seal_ids)

func _initialize(topology: LevelEncounterTopology, level_seed: int) -> bool:
	_room_ids = topology.get_room_ids()
	if _room_ids.is_empty():
		return false
	_room_ids.sort()
	for doorway in topology.get_doorways():
		if doorway == null or _sealed_door_ids.has(doorway.door_id):
			return false
		_sealed_door_ids[doorway.door_id] = true
	for room_id in _room_ids:
		var definition := topology.get_room(room_id)
		if definition == null:
			return false
		var enemy_ids := _shuffle_enemy_ids(definition.enemy_ids, level_seed, room_id)
		var progress := RoomProgress.new(definition, enemy_ids)
		if definition.parent_room_id < 0:
			if not _sealed_door_ids.has(definition.parent_door_id):
				return false
			progress.status = RoomStatus.READY
			_sealed_door_ids.erase(definition.parent_door_id)
		_rooms[room_id] = progress
	return true

func _can_commit_spawns(room: RoomProgress, runtime_ids: Array[int], entity_ids: Array[StringName]) -> bool:
	if runtime_ids.size() != entity_ids.size() \
		or room.active_entity_ids.size() + runtime_ids.size() > MAX_CONCURRENT_ENEMIES_PER_ROOM \
		or not _entity_ids_match_next(room, entity_ids):
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

func _collect_clear_opened_seal_ids(room: RoomProgress) -> Array[int]:
	var opened_seal_ids: Array[int] = []
	var seen: Dictionary = {}
	for door_id in room.definition.door_ids:
		_append_opened_seal_id(door_id, seen, opened_seal_ids)
	for child_room_id in room.definition.child_room_ids:
		var child := _rooms[child_room_id] as RoomProgress
		_append_opened_seal_id(child.definition.parent_door_id, seen, opened_seal_ids)
	opened_seal_ids.sort()
	return opened_seal_ids

func _append_opened_seal_id(door_id: int, seen: Dictionary, opened_seal_ids: Array[int]) -> void:
	if _sealed_door_ids.has(door_id) and not seen.has(door_id):
		seen[door_id] = true
		opened_seal_ids.append(door_id)

func _open_seals(opened_seal_ids: Array[int]) -> void:
	for door_id in opened_seal_ids:
		assert(_sealed_door_ids.has(door_id))
		_sealed_door_ids.erase(door_id)

func _make_transition(room_id: int, cleared: bool, opened_seal_ids: Array[int]) -> LevelEncounterTransition:
	return LevelEncounterTransition.new(room_id, get_summary(), cleared, opened_seal_ids)

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
