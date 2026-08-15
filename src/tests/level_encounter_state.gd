extends SceneTree

const LEVEL_CATALOG_PATH: String = "res://levels/content/dungeons/stone/level_catalog.tres"
const BLOCK_CATALOG_PATH: String = "res://blocks/block_catalog.tres"
const LEVEL_ID: StringName = &"stone_dungeon"
const ENTRANCE_ID: StringName = &"overworld_dungeon_entrance"
const WORLD_SEED: int = 1337
const ENTRANCE_COORDINATE: Vector3i = Vector3i(7, 0, -9)

var _failures: int = 0
var _assertions: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var level_catalog := load(LEVEL_CATALOG_PATH) as LevelCatalog
	var block_catalog := load(BLOCK_CATALOG_PATH) as BlockCatalog
	_expect(level_catalog != null and level_catalog.validate(), "stone level catalog did not load or validate")
	_expect(block_catalog != null and block_catalog.validate(), "block catalog did not load or validate")
	if level_catalog == null or block_catalog == null:
		_finish()
		return
	var generation := LevelGenerator.new().generate(
		level_catalog,
		LEVEL_ID,
		WORLD_SEED,
		ENTRANCE_ID,
		ENTRANCE_COORDINATE
	)
	_expect(generation.succeeded, "stone dungeon generation failed: %s" % generation.failure_reason)
	if not generation.succeeded:
		_finish()
		return
	var definition := level_catalog.get_level(LEVEL_ID)
	var topology := LevelEncounterTopology.create(generation.layout, definition)
	_expect(topology != null, "encounter topology creation failed")
	if topology == null:
		_finish()
		return
	_test_reveal_partition(topology, generation.layout)
	_test_progression(topology, generation.layout.seed_value)
	_test_concurrent_enemy_limit()
	_test_door_overlay(topology, generation.layout, block_catalog)
	_finish()

func _test_progression(topology: LevelEncounterTopology, level_seed: int) -> void:
	var state := LevelEncounterState.create(topology, level_seed)
	_expect(state != null, "encounter state creation failed")
	if state == null:
		return
	var room_ids: Array[int] = state._room_ids.duplicate()
	_expect(not room_ids.is_empty(), "encounter state has no rooms")
	var root_with_child_id := -1
	var ready_count := 0
	var locked_count := 0
	var expected_revealed_room_ids: Array[int] = []
	for room_id in room_ids:
		var room := topology.get_room(room_id)
		if room.parent_room_id < 0:
			ready_count += 1
			expected_revealed_room_ids.append(room_id)
			_expect(_room_progress(state, room_id).status == LevelEncounterState.RoomStatus.READY, "root room did not begin ready: %d" % room_id)
			_expect(not bool(state.get_door_locks()[room.parent_door_id]), "root incoming door began locked: %d" % room_id)
			if not room.child_room_ids.is_empty():
				root_with_child_id = room_id
		else:
			locked_count += 1
			_expect(_room_progress(state, room_id).status == LevelEncounterState.RoomStatus.LOCKED, "child room did not begin locked: %d" % room_id)
			_expect(bool(state.get_door_locks()[room.parent_door_id]), "child incoming door began open: %d" % room_id)
	_expect(ready_count > 0, "topology has no ready root rooms")
	_expect(locked_count > 0, "topology has no initially locked rooms")
	_expect(state.get_revealed_room_ids() == expected_revealed_room_ids, "initial reveal query did not contain exactly the ready root rooms")
	var copied_revealed_room_ids := state.get_revealed_room_ids()
	copied_revealed_room_ids.clear()
	_expect(state.get_revealed_room_ids() == expected_revealed_room_ids, "revealed-room query exposed mutable ownership")
	_expect(root_with_child_id >= 0, "topology has no root room with a child branch")
	if root_with_child_id < 0:
		return

	var root_room := topology.get_room(root_with_child_id)
	var copied_children := root_room.child_room_ids
	var expected_child_ids := copied_children.duplicate()
	copied_children.clear()
	_expect(root_room.child_room_ids == expected_child_ids, "room child query exposed mutable ownership")
	var copied_spawn_cells := root_room.spawn_cells
	var expected_spawn_count := copied_spawn_cells.size()
	copied_spawn_cells.clear()
	_expect(root_room.spawn_cells.size() == expected_spawn_count, "room spawn-cell query exposed mutable ownership")
	var copied_reveal_placements := root_room.reveal_placement_ids
	var expected_reveal_placements := copied_reveal_placements.duplicate()
	copied_reveal_placements.clear()
	_expect(root_room.reveal_placement_ids == expected_reveal_placements, "room reveal-placement query exposed mutable ownership")
	var copied_locks := state.get_door_locks()
	var copied_lock_id := int(copied_locks.keys()[0])
	var authoritative_lock := bool(copied_locks[copied_lock_id])
	copied_locks[copied_lock_id] = not authoritative_lock
	_expect(bool(state.get_door_locks()[copied_lock_id]) == authoritative_lock, "door-lock query exposed mutable ownership")

	var initial_enemy_ids := state.get_next_enemy_ids(root_with_child_id, 2)
	_expect(initial_enemy_ids.size() == 2, "root encounter did not expose two initial enemies")
	if initial_enemy_ids.size() != 2:
		return
	var copied_enemy_ids := initial_enemy_ids.duplicate()
	var all_next_enemy_ids := state.get_next_enemy_ids(root_with_child_id, 64)
	var copied_configured_enemy_ids := state.get_configured_enemy_ids(root_with_child_id)
	var expected_configured_enemy_ids := copied_configured_enemy_ids.duplicate()
	copied_configured_enemy_ids.clear()
	_expect(state.get_configured_enemy_ids(root_with_child_id) == expected_configured_enemy_ids, "configured-enemy query exposed mutable ownership")
	initial_enemy_ids.clear()
	_expect(state.get_next_enemy_ids(root_with_child_id, 2) == copied_enemy_ids, "next-enemy query exposed mutable ownership")
	var initial_locks := state.get_door_locks()
	_expect(not state.can_commit_activation(root_with_child_id, [&"sheep"], 2), "activation preflight accepted the wrong entity sequence")
	_expect(not state.can_commit_activation(root_with_child_id, copied_enemy_ids, 1), "activation preflight accepted capacity below the initial batch")
	_expect(state.can_commit_activation(root_with_child_id, copied_enemy_ids, 2), "activation preflight rejected the next entity sequence")
	_expect(state.commit_activation(root_with_child_id, [], [], 2) == null, "empty activation committed")
	_expect(state.commit_activation(root_with_child_id, [101], [&"sheep"], 2) == null, "activation accepted the wrong entity sequence")
	_expect(state.commit_activation(root_with_child_id, [101, 101], copied_enemy_ids, 2) == null, "activation accepted duplicate runtime IDs")
	_expect(_room_progress(state, root_with_child_id).status == LevelEncounterState.RoomStatus.READY, "failed activation changed room status")
	_expect(state.get_spawned_enemy_count(root_with_child_id) == 0, "failed activation advanced the spawn queue")
	_expect(_room_progress(state, root_with_child_id).active_entity_ids.is_empty(), "failed activation assigned runtime IDs")
	_expect(state.get_door_locks() == initial_locks, "failed activation changed door locks")

	var expected_activation_door_changes := state.get_activation_door_changes(root_with_child_id)
	_expect(not expected_activation_door_changes.is_empty(), "activation door preflight returned no changes")
	var activation := state.commit_activation(root_with_child_id, [101, 102], copied_enemy_ids, 2)
	_expect(activation != null, "valid activation did not commit")
	if activation == null:
		return
	_expect(_room_progress(state, root_with_child_id).status == LevelEncounterState.RoomStatus.ACTIVE, "activated room is not active")
	_expect(state.get_active_room_id() == root_with_child_id, "active room ID was not assigned")
	_expect(_room_progress(state, root_with_child_id).active_entity_ids.size() == 2, "activation did not assign both runtime IDs")
	_expect(state.get_spawned_enemy_count(root_with_child_id) == 2, "activation did not advance the spawn queue")
	_expect(activation.door_changes == expected_activation_door_changes, "activation commit differed from its door preflight")
	for door_id in root_room.door_ids:
		_expect(bool(state.get_door_locks()[door_id]), "activation did not lock room door %d" % door_id)
	var copied_activation_changes := activation.door_changes
	copied_activation_changes.clear()
	_expect(not activation.door_changes.is_empty(), "transition door-change query exposed mutable ownership")
	_expect(state.record_defeat(9999, &"zombie") == null, "unassigned runtime defeat changed encounter state")
	_expect(state.record_defeat(101, &"sheep") == null, "assigned runtime accepted the wrong entity ID")
	_expect(_room_progress(state, root_with_child_id).active_entity_ids.size() == 2, "rejected defeat removed an assigned runtime")

	var active_runtime_ids: Array[int] = [101, 102]
	var entity_id_by_runtime: Dictionary = {
		101: copied_enemy_ids[0],
		102: copied_enemy_ids[1],
	}
	var first_defeat_door_changes := state.get_defeat_door_changes(101, copied_enemy_ids[0])
	var first_defeat := state.record_defeat(101, copied_enemy_ids[0])
	_expect(first_defeat != null and not first_defeat.room_cleared, "first assigned defeat did not commit normally")
	_expect(first_defeat.door_changes == first_defeat_door_changes and first_defeat_door_changes.is_empty(), "non-final defeat differed from its door preflight")
	active_runtime_ids.erase(101)
	entity_id_by_runtime.erase(101)
	_expect(_room_progress(state, root_with_child_id).active_entity_ids.size() == 1, "defeat did not retire its assigned runtime ID")
	_expect(state.get_refill_count(root_with_child_id) == 1, "defeat did not open one refill slot")
	var first_refill_enemy_ids := state.get_next_enemy_ids(root_with_child_id, 1)
	_expect(state.can_commit_refill(root_with_child_id, first_refill_enemy_ids), "refill preflight rejected the next entity sequence")
	var first_refill := state.commit_refill(root_with_child_id, [103], first_refill_enemy_ids)
	_expect(first_refill != null, "valid refill did not commit")
	if first_refill == null:
		return
	active_runtime_ids.append(103)
	entity_id_by_runtime[103] = first_refill_enemy_ids[0]
	_expect(_room_progress(state, root_with_child_id).active_entity_ids.size() == 2, "refill did not restore activation capacity")
	_expect(state.get_refill_count(root_with_child_id) == 0, "refill exceeded activation capacity")

	var next_runtime_id := 104
	while not active_runtime_ids.is_empty():
		var runtime_id: int = active_runtime_ids.pop_front()
		var remaining_before := _remaining_enemy_count(state, root_with_child_id)
		var expected_defeat_door_changes := state.get_defeat_door_changes(runtime_id, entity_id_by_runtime[runtime_id] as StringName)
		var defeat := state.record_defeat(runtime_id, entity_id_by_runtime[runtime_id] as StringName)
		entity_id_by_runtime.erase(runtime_id)
		_expect(defeat != null, "assigned runtime defeat was rejected: %d" % runtime_id)
		if defeat == null:
			return
		var should_clear := remaining_before == 1
		_expect(defeat.room_cleared == should_clear, "room clear occurred before or after the final configured defeat")
		_expect(defeat.door_changes == expected_defeat_door_changes, "defeat commit differed from its door preflight")
		if should_clear:
			break
		_expect(_room_progress(state, root_with_child_id).status == LevelEncounterState.RoomStatus.ACTIVE, "room left active state before every configured enemy died")
		var refill_count := state.get_refill_count(root_with_child_id)
		if refill_count > 0:
			_expect(refill_count == 1, "one defeat opened an unexpected refill count: %d" % refill_count)
			var refill_enemy_ids := state.get_next_enemy_ids(root_with_child_id, refill_count)
			var refill_runtime_ids: Array[int] = [next_runtime_id]
			var refill := state.commit_refill(root_with_child_id, refill_runtime_ids, refill_enemy_ids)
			_expect(refill != null, "refill failed while configured enemies remained")
			if refill == null:
				return
			active_runtime_ids.append(next_runtime_id)
			entity_id_by_runtime[next_runtime_id] = refill_enemy_ids[0]
			next_runtime_id += 1

	_expect(_room_progress(state, root_with_child_id).status == LevelEncounterState.RoomStatus.CLEARED, "room did not remain cleared after final defeat")
	_expect(state.get_active_room_id() == -1, "cleared room remained active")
	_expect(_remaining_enemy_count(state, root_with_child_id) == 0, "cleared room retained configured enemies")
	_expect(state.get_spawned_enemy_count(root_with_child_id) == all_next_enemy_ids.size(), "clear did not require every configured enemy to spawn")
	_expect(_room_progress(state, root_with_child_id).active_entity_ids.is_empty(), "cleared room retained assigned runtime IDs")
	for door_id in root_room.door_ids:
		_expect(not bool(state.get_door_locks()[door_id]), "cleared room door remained locked: %d" % door_id)
	for child_room_id in expected_child_ids:
		var child_room := topology.get_room(child_room_id)
		_expect(_room_progress(state, child_room_id).status == LevelEncounterState.RoomStatus.READY, "cleared room did not unlock child branch: %d" % child_room_id)
		_expect(not bool(state.get_door_locks()[child_room.parent_door_id]), "cleared room did not open child incoming door: %d" % child_room_id)
		expected_revealed_room_ids.append(child_room_id)
	expected_revealed_room_ids.sort()
	_expect(state.get_revealed_room_ids() == expected_revealed_room_ids, "room clear did not reveal exactly its child branches")

func _test_reveal_partition(topology: LevelEncounterTopology, layout: LevelLayout) -> void:
	var placement_owners: Dictionary = {}
	for room_id in topology.get_room_ids():
		var room := topology.get_room(room_id)
		_expect(not room.reveal_placement_ids.is_empty(), "room has no reveal placements: %d" % room_id)
		for placement_id in room.reveal_placement_ids:
			_expect(placement_id > 0, "room reveal partition claimed the entry placement")
			_expect(not placement_owners.has(placement_id), "room reveal partitions overlap at placement %d" % placement_id)
			placement_owners[placement_id] = room_id
	_expect(placement_owners.size() == layout.placed_modules.size() - 1, "room reveal partitions did not cover every non-entry placement")

func _test_concurrent_enemy_limit() -> void:
	var enemy_ids: Array[StringName] = []
	for _index in 40:
		enemy_ids.append(&"zombie")
	var doorway := LevelDoorway.new(
		0,
		0,
		LevelSocketDefinition.Direction.NORTH,
		[Vector3i.ZERO],
		BlockId.Type.STONE_BRICKS,
	)
	var room := LevelEncounterRoom.new(
		0,
		-1,
		0,
		[],
		[0],
		enemy_ids,
		[Vector3i(1, 1, 1)],
		[1],
		{Vector3i(1, 1, 1): true},
	)
	var topology := LevelEncounterTopology.new()
	topology._rooms_by_id[0] = room
	topology._room_ids.assign([0])
	topology._doorways.assign([doorway])
	var state := LevelEncounterState.create(topology, WORLD_SEED)
	_expect(state != null, "forty-enemy encounter state creation failed")
	if state == null:
		return
	_expect(state.get_configured_enemy_ids(0).size() == 40, "room cap changed the configured encounter total")
	var oversized_enemy_ids := state.get_next_enemy_ids(0, LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM + 1)
	var oversized_runtime_ids: Array[int] = []
	for runtime_id in range(1, oversized_enemy_ids.size() + 1):
		oversized_runtime_ids.append(runtime_id)
	_expect(oversized_enemy_ids.size() == LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM + 1, "forty-enemy fixture did not expose an oversized activation batch")
	_expect(
		not state.can_commit_activation(0, oversized_enemy_ids, oversized_enemy_ids.size()),
		"activation preflight accepted more than twenty concurrent enemies",
	)
	_expect(
		state.commit_activation(0, oversized_runtime_ids, oversized_enemy_ids, oversized_enemy_ids.size()) == null,
		"activation committed more than twenty concurrent enemies",
	)
	var initial_enemy_ids := state.get_next_enemy_ids(0, LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM)
	var initial_runtime_ids: Array[int] = []
	for runtime_id in range(1, initial_enemy_ids.size() + 1):
		initial_runtime_ids.append(runtime_id)
	var activation := state.commit_activation(
		0,
		initial_runtime_ids,
		initial_enemy_ids,
		LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM,
	)
	_expect(activation != null, "twenty-enemy activation did not commit")
	if activation == null:
		return
	var progress := _room_progress(state, 0)
	_expect(activation.active_enemy_count == LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM, "activation transition did not report the twenty-enemy cap")
	_expect(activation.pending_enemy_count == 20, "activation transition did not retain twenty pending enemies")
	_expect(progress.active_entity_ids.size() == LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM, "activation did not reach the twenty-enemy room cap")
	_expect(state.get_spawned_enemy_count(0) == LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM, "activation did not preserve the remaining configured total")
	_expect(state.get_refill_count(0) == 0, "full twenty-enemy room exposed a refill slot")
	var next_enemy_ids := state.get_next_enemy_ids(0, 1)
	_expect(state.commit_refill(0, [21], next_enemy_ids) == null, "full room accepted a twenty-first active enemy")
	var defeated_entity_id := progress.active_entity_ids[1] as StringName
	_expect(state.record_defeat(1, defeated_entity_id) != null, "room-cap fixture defeat did not commit")
	_expect(state.get_refill_count(0) == 1, "one defeat did not open exactly one capped refill slot")
	var refill := state.commit_refill(0, [21], next_enemy_ids)
	_expect(refill != null, "capped room did not refill one available slot")
	_expect(refill != null and refill.pending_enemy_count == 19, "capped refill did not retain the remaining configured enemies")
	_expect(progress.active_entity_ids.size() == LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM, "refill did not restore the twenty-enemy room cap")
	_expect(state.get_spawned_enemy_count(0) == LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM + 1, "refill did not advance the forty-enemy queue")

func _test_door_overlay(topology: LevelEncounterTopology, layout: LevelLayout, block_catalog: BlockCatalog) -> void:
	var encounter_state := LevelEncounterState.create(topology, layout.seed_value)
	var level_state := LevelState.from_layout(layout, block_catalog)
	_expect(encounter_state != null, "door-overlay encounter state creation failed")
	if encounter_state == null:
		return
	var initial_locks := encounter_state.get_door_locks()
	_expect(level_state.configure_doors(topology.get_doorways(), initial_locks), "level state rejected encounter door configuration")
	var locked_door_id := -1
	for door_id in initial_locks:
		if bool(initial_locks[door_id]):
			locked_door_id = int(door_id)
			break
	_expect(locked_door_id >= 0, "generated encounter has no initially locked door")
	if locked_door_id < 0:
		return
	var doorway: LevelDoorway
	for candidate in topology.get_doorways():
		if candidate.door_id == locked_door_id:
			doorway = candidate
			break
	_expect(doorway != null, "locked doorway was not retained by topology")
	if doorway == null:
		return
	var copied_aperture := doorway.aperture_cells
	var authoritative_aperture := copied_aperture.duplicate()
	copied_aperture.clear()
	_expect(doorway.aperture_cells == authoritative_aperture, "door aperture query exposed mutable ownership")
	_expect(doorway.fill_block_id == BlockId.Type.STONE_BRICKS, "stone doorway did not retain its authored Stone Bricks fill")
	for cell in authoritative_aperture:
		_expect(layout.get_cell(cell) == StructureCell.AIR, "connected doorway base cell is not AIR: %s" % cell)
		_expect(level_state.has_cell(cell), "door overlay escaped level cells: %s" % cell)
		_expect(level_state.get_cell_value(cell) == doorway.fill_block_id, "locked door cell did not read as its authored fill: %s" % cell)
		_expect(level_state.get_block_at(cell) == doorway.fill_block_id, "locked door block query did not return its authored fill: %s" % cell)
		_expect(level_state.get_block_id_at(cell) == doorway.fill_block_id, "locked door block ID did not return its authored fill: %s" % cell)
		_expect(level_state.is_solid(cell), "locked door cell did not block movement: %s" % cell)
		_expect(level_state.is_raycast_solid(cell), "locked door cell did not block raycasts: %s" % cell)
		_expect(not level_state.is_interior_open(cell), "locked door cell remained open: %s" % cell)
		_expect(level_state.is_base_interior_open(cell), "locked door changed the immutable base cell: %s" % cell)
		_expect(int(level_state.snapshot_cells()[cell]) == StructureCell.AIR, "locked door was written into the base snapshot: %s" % cell)
	_expect(not level_state.can_apply_door_locks({999999: true}), "level state accepted an unknown door lock")
	level_state.apply_door_locks({locked_door_id: false})
	for cell in authoritative_aperture:
		_expect(level_state.get_cell_value(cell) == StructureCell.AIR, "reopened door did not restore AIR cell value: %s" % cell)
		_expect(level_state.get_block_at(cell) == null, "reopened door retained a block: %s" % cell)
		_expect(level_state.get_block_id_at(cell) == BlockId.Type.AIR, "reopened door retained a block ID: %s" % cell)
		_expect(not level_state.is_solid(cell), "reopened door still blocked movement: %s" % cell)
		_expect(not level_state.is_raycast_solid(cell), "reopened door still blocked raycasts: %s" % cell)
		_expect(level_state.is_interior_open(cell), "reopened door did not restore open interior: %s" % cell)

func _room_progress(state: LevelEncounterState, room_id: int) -> LevelEncounterState.RoomProgress:
	return state._rooms[room_id] as LevelEncounterState.RoomProgress

func _remaining_enemy_count(state: LevelEncounterState, room_id: int) -> int:
	var room := _room_progress(state, room_id)
	return room.enemy_ids.size() - room.defeated_count

func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	print("[level_encounter_state] FAIL: %s" % message)

func _finish() -> void:
	if _failures == 0:
		print("LEVEL_ENCOUNTER_STATE PASS assertions=%d" % _assertions)
		quit(0)
	else:
		print("LEVEL_ENCOUNTER_STATE FAILED failures=%d assertions=%d" % [_failures, _assertions])
		quit(1)
