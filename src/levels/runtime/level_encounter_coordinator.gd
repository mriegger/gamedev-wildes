extends Node
class_name LevelEncounterCoordinator

const EntitySpawnGeometryType := preload("res://entities/entity_spawn_geometry.gd")

signal door_locks_changed(changes: Dictionary)
signal encounter_progress_changed(active_enemy_count: int, pending_enemy_count: int)
signal encounter_cleared

var _topology: LevelEncounterTopology
var _state: LevelEncounterState
var _level_state: LevelState
var _entity_runtime: EntityRuntime
var _entity_catalog: EntityCatalog
var _player: PlayerMotor
var _level_seed: int
var _spawn_cells_by_room: Dictionary = {}
var _capacity_by_room: Dictionary = {}
var _refill_not_before_physics_frame: int = 0

func setup(
	topology: LevelEncounterTopology,
	state: LevelEncounterState,
	level_state: LevelState,
	entity_runtime: EntityRuntime,
	entity_catalog: EntityCatalog,
	level_seed: int,
) -> bool:
	if topology == null or state == null or level_state == null or entity_runtime == null or entity_catalog == null:
		return false
	_topology = topology
	_state = state
	_level_state = level_state
	_entity_runtime = entity_runtime
	_entity_catalog = entity_catalog
	_level_seed = level_seed
	for room_id in topology.get_room_ids():
		_spawn_cells_by_room[room_id] = _shuffle_spawn_cells(topology.get_room(room_id).spawn_cells, room_id)
		var enemy_ids := state.get_configured_enemy_ids(room_id)
		var static_batch := _build_spawn_batch(room_id, enemy_ids, true)
		var capacity := (static_batch["requests"] as Array[EntitySpawnRequest]).size()
		if capacity <= 0:
			shutdown()
			return false
		_capacity_by_room[room_id] = capacity
	if not level_state.configure_doors(topology.get_doorways(), state.get_door_locks()):
		shutdown()
		return false
	_entity_runtime.entity_defeated.connect(_on_entity_defeated)
	return true

func set_player(player: PlayerMotor) -> void:
	assert(player != null)
	_player = player

func tick() -> void:
	if _player == null or _player.is_defeated():
		return
	var active_room_id := _state.get_active_room_id()
	if active_room_id >= 0:
		if Engine.get_physics_frames() >= _refill_not_before_physics_frame:
			_try_refill(active_room_id)
		return
	var room_id := _topology.find_room_containing_body(_player.global_position, _player.player_width, _player.player_height)
	if room_id >= 0 and _state.can_activate(room_id):
		_try_activate(room_id)

func shutdown() -> void:
	if _entity_runtime != null and _entity_runtime.entity_defeated.is_connected(_on_entity_defeated):
		_entity_runtime.entity_defeated.disconnect(_on_entity_defeated)
	_topology = null
	_state = null
	_level_state = null
	_entity_runtime = null
	_entity_catalog = null
	_player = null
	_spawn_cells_by_room.clear()
	_capacity_by_room.clear()
	_refill_not_before_physics_frame = 0

func _try_activate(room_id: int) -> void:
	var capacity := int(_capacity_by_room[room_id])
	var entity_ids := _state.get_next_enemy_ids(room_id, capacity)
	var batch := _build_spawn_batch(room_id, entity_ids)
	var requests := batch["requests"] as Array[EntitySpawnRequest]
	var committed_entity_ids := batch["entity_ids"] as Array[StringName]
	if requests.is_empty() or not _state.can_commit_activation(room_id, committed_entity_ids, capacity):
		return
	var expected_door_changes := _state.get_activation_door_changes(room_id)
	if not _level_state.can_apply_door_locks(expected_door_changes):
		return
	var runtime_ids := _entity_runtime.try_spawn_batch(requests)
	if runtime_ids.is_empty():
		return
	var transition := _state.commit_activation(room_id, runtime_ids, committed_entity_ids, capacity)
	if transition == null:
		_cancel_spawn_batch(runtime_ids)
		return
	_apply_transition(transition, expected_door_changes)

func _try_refill(room_id: int) -> void:
	var refill_count := _state.get_refill_count(room_id)
	if refill_count <= 0:
		return
	var entity_ids := _state.get_next_enemy_ids(room_id, refill_count)
	var batch := _build_spawn_batch(room_id, entity_ids)
	var requests := batch["requests"] as Array[EntitySpawnRequest]
	var committed_entity_ids := batch["entity_ids"] as Array[StringName]
	if requests.is_empty() or not _state.can_commit_refill(room_id, committed_entity_ids):
		return
	var runtime_ids := _entity_runtime.try_spawn_batch(requests)
	if runtime_ids.is_empty():
		return
	var transition := _state.commit_refill(room_id, runtime_ids, committed_entity_ids)
	if transition == null:
		_cancel_spawn_batch(runtime_ids)
		return
	_apply_transition(transition, {})

func _build_spawn_batch(room_id: int, entity_ids: Array[StringName], ignore_transient_occupancy: bool = false) -> Dictionary:
	var requests: Array[EntitySpawnRequest] = []
	var committed_entity_ids: Array[StringName] = []
	var selected_bounds: Array[AABB] = []
	var used_cells: Dictionary = {}
	var player_bounds := AABB()
	if not ignore_transient_occupancy:
		player_bounds = _player_bounds()
	var spawn_index := _state.get_spawned_enemy_count(room_id)
	var spawn_cells := _spawn_cells_by_room[room_id] as Array[Vector3i]
	for entity_offset in entity_ids.size():
		var entity_id := entity_ids[entity_offset]
		var definition := _entity_catalog.get_definition(entity_id)
		var selected_cell: Variant = null
		var selected_bounds_value := AABB()
		for cell_offset in spawn_cells.size():
			var cell := spawn_cells[(spawn_index + entity_offset + cell_offset) % spawn_cells.size()]
			if used_cells.has(cell):
				continue
			var feet_position := Vector3(cell) + Vector3(0.5, 0.0, 0.5)
			if not EntitySpawnGeometryType.can_spawn(_level_state, definition, feet_position):
				continue
			var bounds := EntitySpawnGeometryType.get_bounds(definition, feet_position)
			if not ignore_transient_occupancy and (bounds.intersects(player_bounds) or _entity_runtime.has_entity_overlap(bounds)):
				continue
			var overlaps_selected := false
			for other_bounds in selected_bounds:
				if bounds.intersects(other_bounds):
					overlaps_selected = true
					break
			if overlaps_selected:
				continue
			selected_cell = cell
			selected_bounds_value = bounds
			break
		if selected_cell == null:
			break
		var cell := selected_cell as Vector3i
		var behavior_seed := _level_seed ^ (room_id * 2246822519) ^ ((spawn_index + requests.size()) * 3266489917)
		requests.append(EntitySpawnRequest.new(entity_id, Vector3(cell) + Vector3(0.5, 0.0, 0.5), behavior_seed))
		committed_entity_ids.append(entity_id)
		selected_bounds.append(selected_bounds_value)
		used_cells[cell] = true
	return {
		"requests": requests,
		"entity_ids": committed_entity_ids,
	}

func _cancel_spawn_batch(runtime_ids: Array[int]) -> void:
	for runtime_id in runtime_ids:
		assert(_entity_runtime.try_despawn(runtime_id))

func _on_entity_defeated(runtime_id: int, entity_id: StringName) -> void:
	var expected_door_changes := _state.get_defeat_door_changes(runtime_id, entity_id)
	assert(_level_state.can_apply_door_locks(expected_door_changes))
	var transition := _state.record_defeat(runtime_id, entity_id)
	if transition != null:
		_refill_not_before_physics_frame = maxi(_refill_not_before_physics_frame, Engine.get_physics_frames() + 1)
		_apply_transition(transition, expected_door_changes)

func _apply_transition(transition: LevelEncounterTransition, expected_door_changes: Dictionary) -> void:
	var changes := transition.door_changes
	assert(changes == expected_door_changes)
	if not changes.is_empty():
		_level_state.apply_door_locks(changes)
		door_locks_changed.emit(changes)
	if transition.room_cleared:
		encounter_cleared.emit()
	else:
		encounter_progress_changed.emit(transition.active_enemy_count, transition.pending_enemy_count)

func _shuffle_spawn_cells(source: Array[Vector3i], room_id: int) -> Array[Vector3i]:
	var cells: Array[Vector3i] = source.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = _level_seed ^ (room_id * 668265263)
	for index in range(cells.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var value := cells[index]
		cells[index] = cells[swap_index]
		cells[swap_index] = value
	return cells

func _player_bounds() -> AABB:
	var half_width := _player.player_width * 0.5
	return AABB(
		_player.global_position + Vector3(-half_width, 0.0, -half_width),
		Vector3(_player.player_width, _player.player_height, _player.player_width)
	)
