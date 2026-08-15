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
	_test_discovery_partition(topology, generation.layout)
	_test_production_progression(topology, generation.layout.seed_value)
	_test_concurrent_waves_and_capacity()
	_test_two_full_waves()
	_test_seal_overlay(topology, generation.layout, block_catalog)
	_finish()

func _test_production_progression(topology: LevelEncounterTopology, level_seed: int) -> void:
	var state := LevelEncounterState.create(topology, level_seed)
	_expect(state != null, "encounter state creation failed")
	if state == null:
		return
	var expected_discovered_room_ids: Array[int] = []
	var expected_sealed_door_ids := _all_door_ids(topology)
	var root_with_child_id := -1
	for room_id in topology.get_room_ids():
		var room := topology.get_room(room_id)
		if room.parent_room_id < 0:
			expected_discovered_room_ids.append(room_id)
			expected_sealed_door_ids.erase(room.parent_door_id)
			_expect(_room_progress(state, room_id).status == LevelEncounterState.RoomStatus.READY, "root room did not begin ready: %d" % room_id)
			if not room.child_room_ids.is_empty():
				root_with_child_id = room_id
		else:
			_expect(_room_progress(state, room_id).status == LevelEncounterState.RoomStatus.LOCKED, "child room did not begin locked: %d" % room_id)
	expected_discovered_room_ids.sort()
	expected_sealed_door_ids.sort()
	_expect(state.get_active_room_ids().is_empty(), "encounter began with an active wave")
	_expect(state.get_discovered_room_ids() == expected_discovered_room_ids, "initial discovery did not contain exactly the ready roots")
	_expect(state.get_sealed_door_ids() == expected_sealed_door_ids, "initial seals did not exclude exactly the root incoming doorways")
	_expect(_summary_equals(state.get_summary(), 0, 0, 0), "inactive state reported encounter counts")
	var copied_discovered_ids := state.get_discovered_room_ids()
	var copied_sealed_ids := state.get_sealed_door_ids()
	copied_discovered_ids.clear()
	copied_sealed_ids.clear()
	_expect(state.get_discovered_room_ids() == expected_discovered_room_ids, "discovered-room query exposed mutable ownership")
	_expect(state.get_sealed_door_ids() == expected_sealed_door_ids, "sealed-door query exposed mutable ownership")
	_expect(root_with_child_id >= 0, "production topology has no root room with a child")
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
	var copied_discovery_placements := root_room.discovery_placement_ids
	var expected_discovery_placements := copied_discovery_placements.duplicate()
	copied_discovery_placements.clear()
	_expect(root_room.discovery_placement_ids == expected_discovery_placements, "room discovery-placement query exposed mutable ownership")

	var initial_enemy_ids := state.get_next_enemy_ids(root_with_child_id, 2)
	_expect(initial_enemy_ids.size() == 2, "root encounter did not expose two initial enemies")
	if initial_enemy_ids.size() != 2:
		return
	var expected_enemy_ids := initial_enemy_ids.duplicate()
	var configured_enemy_ids := state.get_configured_enemy_ids(root_with_child_id)
	var expected_configured_enemy_ids := configured_enemy_ids.duplicate()
	configured_enemy_ids.clear()
	initial_enemy_ids.clear()
	_expect(state.get_next_enemy_ids(root_with_child_id, 2) == expected_enemy_ids, "next-enemy query exposed mutable ownership")
	_expect(state.get_configured_enemy_ids(root_with_child_id) == expected_configured_enemy_ids, "configured-enemy query exposed mutable ownership")
	_expect(not state.can_commit_activation(root_with_child_id, [&"sheep"], 2), "activation accepted the wrong entity sequence")
	_expect(not state.can_commit_activation(root_with_child_id, expected_enemy_ids, 1), "activation accepted insufficient capacity")
	_expect(state.commit_activation(root_with_child_id, [101, 101], expected_enemy_ids, 2) == null, "activation accepted duplicate runtime IDs")
	_expect(state.get_sealed_door_ids() == expected_sealed_door_ids, "failed activation changed seals")

	var activation := state.commit_activation(root_with_child_id, [101, 102], expected_enemy_ids, 2)
	_expect(activation != null, "valid activation did not commit")
	if activation == null:
		return
	_expect(activation.room_id == root_with_child_id, "activation transition reported the wrong room")
	_expect(not activation.room_cleared and activation.opened_seal_ids.is_empty(), "activation opened or resealed a doorway")
	_expect(state.get_active_room_ids() == [root_with_child_id], "activated room was not retained")
	_expect(state.get_sealed_door_ids() == expected_sealed_door_ids, "activation changed monotonic seals")
	_expect(_summary_equals(activation.summary, 1, 2, expected_configured_enemy_ids.size() - 2), "activation transition summary was incorrect")
	_expect(_summary_equals(state.get_summary(), 1, 2, expected_configured_enemy_ids.size() - 2), "activation state summary was incorrect")
	_expect(state.record_defeat(9999, &"zombie") == null, "unassigned defeat changed encounter state")
	_expect(state.record_defeat(101, &"sheep") == null, "assigned runtime accepted the wrong entity ID")

	var active_runtime_ids: Array[int] = [101, 102]
	var entity_by_runtime: Dictionary = {
		101: expected_enemy_ids[0],
		102: expected_enemy_ids[1],
	}
	var next_runtime_id := 103
	var final_transition: LevelEncounterTransition
	var final_preflight: Array[int] = []
	while not active_runtime_ids.is_empty():
		var runtime_id: int = active_runtime_ids.pop_front()
		var entity_id := entity_by_runtime[runtime_id] as StringName
		var remaining_before := _remaining_enemy_count(state, root_with_child_id)
		var opened_seal_ids := state.get_defeat_opened_seal_ids(runtime_id, entity_id)
		var defeat := state.record_defeat(runtime_id, entity_id)
		entity_by_runtime.erase(runtime_id)
		_expect(defeat != null, "assigned runtime defeat was rejected: %d" % runtime_id)
		if defeat == null:
			return
		var should_clear := remaining_before == 1
		_expect(defeat.room_id == root_with_child_id, "defeat transition lost room ownership")
		_expect(defeat.room_cleared == should_clear, "room clear did not match the final configured defeat")
		_expect(defeat.opened_seal_ids == opened_seal_ids, "defeat transition differed from seal preflight")
		if should_clear:
			final_transition = defeat
			final_preflight = opened_seal_ids
			break
		_expect(opened_seal_ids.is_empty(), "non-final defeat proposed opening a seal")
		var refill_count := state.get_refill_count(root_with_child_id)
		if refill_count > 0:
			var refill_enemy_ids := state.get_next_enemy_ids(root_with_child_id, refill_count)
			var refill_runtime_ids: Array[int] = [next_runtime_id]
			var refill := state.commit_refill(root_with_child_id, refill_runtime_ids, refill_enemy_ids)
			_expect(refill != null and refill.room_id == root_with_child_id, "room refill failed")
			if refill == null:
				return
			active_runtime_ids.append(next_runtime_id)
			entity_by_runtime[next_runtime_id] = refill_enemy_ids[0]
			next_runtime_id += 1

	_expect(final_transition != null, "production room never emitted a clear transition")
	if final_transition == null:
		return
	var expected_opened_seal_ids: Array[int] = []
	for door_id in root_room.door_ids:
		if expected_sealed_door_ids.has(door_id):
			expected_opened_seal_ids.append(door_id)
	for child_room_id in expected_child_ids:
		var child := topology.get_room(child_room_id)
		if expected_sealed_door_ids.has(child.parent_door_id) and not expected_opened_seal_ids.has(child.parent_door_id):
			expected_opened_seal_ids.append(child.parent_door_id)
	expected_opened_seal_ids.sort()
	_expect(final_preflight == expected_opened_seal_ids, "clear preflight did not open the current and child incoming seals")
	var copied_opened_ids := final_transition.opened_seal_ids
	copied_opened_ids.clear()
	_expect(final_transition.opened_seal_ids == expected_opened_seal_ids, "transition opened-seal query exposed mutable ownership")
	for opened_id in expected_opened_seal_ids:
		expected_sealed_door_ids.erase(opened_id)
	_expect(state.get_sealed_door_ids() == expected_sealed_door_ids, "clear did not remove exactly the opened seals")
	_expect(state.get_active_room_ids().is_empty(), "cleared production room remained active")
	_expect(_summary_equals(final_transition.summary, 0, 0, 0), "final transition retained a finished wave")
	for child_room_id in expected_child_ids:
		_expect(_room_progress(state, child_room_id).status == LevelEncounterState.RoomStatus.READY, "clear did not make child ready: %d" % child_room_id)
		expected_discovered_room_ids.append(child_room_id)
	expected_discovered_room_ids.sort()
	_expect(state.get_discovered_room_ids() == expected_discovered_room_ids, "clear did not discover exactly the child branches")

func _test_concurrent_waves_and_capacity() -> void:
	var topology := _make_concurrent_topology()
	_expect(topology.get_maximum_simultaneous_encounter_enemy_count() == 34, "weighted tree capacity did not choose max(parent, sum(children)) across roots")
	var state := LevelEncounterState.create(topology, WORLD_SEED)
	_expect(state != null, "concurrent synthetic encounter state failed to initialize")
	if state == null:
		return
	_expect(state.get_discovered_room_ids() == [10, 20, 30], "synthetic roots did not begin discovered")
	_expect(state.get_sealed_door_ids() == [1, 2, 3, 4], "synthetic child branches did not begin sealed")

	var root_a_ids := state.get_next_enemy_ids(10, 4)
	var root_a_activation := state.commit_activation(10, [100, 101, 102, 103], root_a_ids, 4)
	_expect(root_a_activation != null, "first root wave did not activate")
	var root_b_ids := state.get_next_enemy_ids(20, 2)
	_expect(state.commit_activation(20, [100, 201], root_b_ids, 2) == null, "second wave reused another room's runtime ID")
	var root_b_activation := state.commit_activation(20, [200, 201], root_b_ids, 2)
	_expect(root_b_activation != null, "second root wave did not activate while the first remained active")
	var oversized_ids := state.get_next_enemy_ids(30, LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM + 1)
	var oversized_runtime_ids: Array[int] = []
	for runtime_id in range(300, 300 + oversized_ids.size()):
		oversized_runtime_ids.append(runtime_id)
	_expect(not state.can_commit_activation(30, oversized_ids, oversized_ids.size()), "third wave accepted more than twenty active enemies")
	_expect(state.commit_activation(30, oversized_runtime_ids, oversized_ids, oversized_ids.size()) == null, "third wave committed more than twenty active enemies")
	var root_c_ids := state.get_next_enemy_ids(30, LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM)
	var root_c_runtime_ids: Array[int] = []
	for runtime_id in range(300, 320):
		root_c_runtime_ids.append(runtime_id)
	var root_c_activation := state.commit_activation(30, root_c_runtime_ids, root_c_ids, LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM)
	_expect(root_c_activation != null, "third concurrent root wave did not activate at its twenty-enemy cap")
	_expect(state.get_active_room_ids() == [10, 20, 30], "active-room query was not sorted or omitted concurrent waves")
	var copied_active_ids := state.get_active_room_ids()
	copied_active_ids.clear()
	_expect(state.get_active_room_ids() == [10, 20, 30], "active-room query exposed mutable ownership")
	_expect(_summary_equals(state.get_summary(), 3, 26, 23), "three-wave aggregate summary was incorrect")
	_expect(state.get_sealed_door_ids() == [1, 2, 3, 4], "concurrent activation changed seals")

	for runtime_id in [100, 101, 102]:
		_expect(state.get_defeat_opened_seal_ids(runtime_id, &"zombie").is_empty(), "non-final root defeat proposed seals")
		_expect(state.record_defeat(runtime_id, &"zombie") != null, "first root rejected an assigned defeat")
	var final_opened_ids := state.get_defeat_opened_seal_ids(103, &"zombie")
	_expect(final_opened_ids == [1, 2, 3, 4], "first root clear did not propose both child branches")
	var root_a_clear := state.record_defeat(103, &"zombie")
	_expect(root_a_clear != null and root_a_clear.room_cleared, "first root did not clear independently")
	_expect(root_a_clear != null and root_a_clear.opened_seal_ids == final_opened_ids, "first root clear did not commit its seal preflight")
	_expect(state.get_sealed_door_ids().is_empty(), "opened seals were not removed monotonically")
	_expect(state.get_active_room_ids() == [20, 30], "clearing one wave stopped another active wave")
	_expect(state.get_discovered_room_ids() == [10, 11, 12, 20, 30], "root clear did not discover both child branches")
	_expect(_summary_equals(state.get_summary(), 2, 22, 23), "independent clear corrupted remaining wave totals")

	var child_a_ids := state.get_next_enemy_ids(11, 3)
	var child_b_ids := state.get_next_enemy_ids(12, 6)
	_expect(state.commit_activation(11, [400, 401, 402], child_a_ids, 3) != null, "first child did not activate alongside existing waves")
	_expect(state.commit_activation(12, [500, 501, 502, 503, 504, 505], child_b_ids, 6) != null, "sibling child did not activate alongside existing waves")
	_expect(state.get_active_room_ids() == [11, 12, 20, 30], "four simultaneous waves were not retained")
	_expect(_summary_equals(state.get_summary(), 4, 31, 23), "four-wave summary did not preserve per-room counts")

	_expect(state.record_defeat(200, &"zombie") != null, "second root rejected its defeat")
	_expect(state.get_refill_count(20) == 1, "second root did not schedule its own refill slot")
	_expect(_room_progress(state, 30).active_entity_ids.size() == 20, "second-root defeat changed the third wave")
	var root_b_refill_ids := state.get_next_enemy_ids(20, 1)
	var root_b_refill := state.commit_refill(20, [202], root_b_refill_ids)
	_expect(root_b_refill != null, "second root failed to refill independently")
	_expect(_summary_equals(state.get_summary(), 4, 31, 22), "independent refill did not update aggregate active and pending counts")

func _test_two_full_waves() -> void:
	var topology := LevelEncounterTopology.new()
	topology._rooms_by_id[1] = _make_room(1, -1, 0, [], [0], 40)
	topology._rooms_by_id[2] = _make_room(2, -1, 1, [], [1], 40)
	topology._room_ids.assign([1, 2])
	topology._doorways.assign([
		LevelDoorway.new(0, 1, LevelSocketDefinition.Direction.NORTH, [Vector3i.ZERO], BlockId.Type.STONE_BRICKS),
		LevelDoorway.new(1, 2, LevelSocketDefinition.Direction.NORTH, [Vector3i(2, 0, 0)], BlockId.Type.STONE_BRICKS),
	])
	var state := LevelEncounterState.create(topology, WORLD_SEED)
	_expect(state != null, "two-wave cap fixture failed to initialize")
	if state == null:
		return
	var first_runtime_ids: Array[int] = []
	var second_runtime_ids: Array[int] = []
	for index in LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM:
		first_runtime_ids.append(index + 1)
		second_runtime_ids.append(index + 101)
	var first_ids := state.get_next_enemy_ids(1, LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM)
	var second_ids := state.get_next_enemy_ids(2, LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM)
	_expect(state.commit_activation(1, first_runtime_ids, first_ids, LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM) != null, "first full wave did not activate")
	_expect(state.commit_activation(2, second_runtime_ids, second_ids, LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM) != null, "second full wave did not activate")
	_expect(_summary_equals(state.get_summary(), 2, 40, 40), "two full room waves did not permit forty active enemies with independent pending totals")

func _test_discovery_partition(topology: LevelEncounterTopology, layout: LevelLayout) -> void:
	var placement_owners: Dictionary = {}
	for room_id in topology.get_room_ids():
		var room := topology.get_room(room_id)
		_expect(not room.discovery_placement_ids.is_empty(), "room has no discovery placements: %d" % room_id)
		for placement_id in room.discovery_placement_ids:
			_expect(placement_id > 0, "room discovery partition claimed the entry placement")
			_expect(not placement_owners.has(placement_id), "room discovery partitions overlap at placement %d" % placement_id)
			placement_owners[placement_id] = room_id
	_expect(placement_owners.size() == layout.placed_modules.size() - 1, "room discovery partitions did not cover every non-entry placement")

func _test_seal_overlay(topology: LevelEncounterTopology, layout: LevelLayout, block_catalog: BlockCatalog) -> void:
	var encounter_state := LevelEncounterState.create(topology, layout.seed_value)
	var level_state := LevelState.from_layout(layout, block_catalog)
	_expect(encounter_state != null, "seal-overlay encounter state creation failed")
	if encounter_state == null:
		return
	var sealed_door_ids := encounter_state.get_sealed_door_ids()
	_expect(not sealed_door_ids.is_empty(), "generated encounter has no initially sealed doorway")
	if sealed_door_ids.is_empty():
		return
	_expect(level_state.configure_seals(topology.get_doorways(), sealed_door_ids), "level state rejected encounter seal configuration")
	var sealed_door_id := sealed_door_ids[0]
	sealed_door_ids.clear()
	var doorway: LevelDoorway
	for candidate in topology.get_doorways():
		if candidate.door_id == sealed_door_id:
			doorway = candidate
			break
	_expect(doorway != null, "sealed doorway was not retained by topology")
	if doorway == null:
		return
	var copied_aperture := doorway.aperture_cells
	var authoritative_aperture := copied_aperture.duplicate()
	copied_aperture.clear()
	_expect(doorway.aperture_cells == authoritative_aperture, "door aperture query exposed mutable ownership")
	_expect(doorway.fill_block_id == BlockId.Type.STONE_BRICKS, "stone seal did not retain its authored Stone Bricks fill")
	for cell in authoritative_aperture:
		_expect(layout.get_cell(cell) == StructureCell.AIR, "connected doorway base cell is not AIR: %s" % cell)
		_expect(level_state.has_cell(cell), "seal overlay escaped level cells: %s" % cell)
		_expect(level_state.get_cell_value(cell) == doorway.fill_block_id, "sealed cell did not read as its authored fill: %s" % cell)
		_expect(level_state.get_block_at(cell) == doorway.fill_block_id, "sealed block query did not return its authored fill: %s" % cell)
		_expect(level_state.get_block_id_at(cell) == doorway.fill_block_id, "sealed block ID did not return its authored fill: %s" % cell)
		_expect(level_state.is_solid(cell), "sealed cell did not block movement: %s" % cell)
		_expect(level_state.is_raycast_solid(cell), "sealed cell did not block raycasts: %s" % cell)
		_expect(not level_state.is_interior_open(cell), "sealed cell remained open: %s" % cell)
		_expect(level_state.is_base_interior_open(cell), "seal changed the immutable base cell: %s" % cell)
		_expect(int(level_state.snapshot_cells()[cell]) == StructureCell.AIR, "seal was written into the base snapshot: %s" % cell)
	_expect(not level_state.can_open_seals([999999]), "level state accepted an unknown seal")
	_expect(not level_state.can_open_seals([sealed_door_id, sealed_door_id]), "level state accepted a duplicate seal opening")
	_expect(level_state.can_open_seals([sealed_door_id]), "level state rejected a configured seal opening")
	level_state.open_seals([sealed_door_id])
	_expect(not level_state.can_open_seals([sealed_door_id]), "level state allowed a seal to be reopened")
	for cell in authoritative_aperture:
		_expect(level_state.get_cell_value(cell) == StructureCell.AIR, "opened seal did not restore AIR: %s" % cell)
		_expect(level_state.get_block_at(cell) == null, "opened seal retained a block: %s" % cell)
		_expect(level_state.get_block_id_at(cell) == BlockId.Type.AIR, "opened seal retained a block ID: %s" % cell)
		_expect(not level_state.is_solid(cell), "opened seal still blocked movement: %s" % cell)
		_expect(not level_state.is_raycast_solid(cell), "opened seal still blocked raycasts: %s" % cell)
		_expect(level_state.is_interior_open(cell), "opened seal did not restore open interior: %s" % cell)

func _make_concurrent_topology() -> LevelEncounterTopology:
	var topology := LevelEncounterTopology.new()
	topology._rooms_by_id[10] = _make_room(10, -1, 0, [11, 12], [0, 1, 2], 4)
	topology._rooms_by_id[11] = _make_room(11, 10, 3, [], [3], 3)
	topology._rooms_by_id[12] = _make_room(12, 10, 4, [], [4], 6)
	topology._rooms_by_id[20] = _make_room(20, -1, 5, [], [5], 5)
	topology._rooms_by_id[30] = _make_room(30, -1, 6, [], [6], 40)
	topology._room_ids.assign([10, 11, 12, 20, 30])
	var doorway_room_ids: Array[int] = [10, 10, 10, 11, 12, 20, 30]
	for door_id in doorway_room_ids.size():
		topology._doorways.append(LevelDoorway.new(
			door_id,
			doorway_room_ids[door_id],
			LevelSocketDefinition.Direction.NORTH,
			[Vector3i(door_id * 2, 1, 0)],
			BlockId.Type.STONE_BRICKS,
		))
	return topology

func _make_room(
	room_id: int,
	parent_room_id: int,
	parent_door_id: int,
	child_room_ids: Array[int],
	door_ids: Array[int],
	enemy_count: int,
) -> LevelEncounterRoom:
	var enemy_ids: Array[StringName] = []
	for _index in enemy_count:
		enemy_ids.append(&"zombie")
	var room_cell := Vector3i(room_id, 1, room_id)
	return LevelEncounterRoom.new(
		room_id,
		parent_room_id,
		parent_door_id,
		child_room_ids,
		door_ids,
		enemy_ids,
		[room_cell],
		[room_id],
		{room_cell: true},
	)

func _all_door_ids(topology: LevelEncounterTopology) -> Array[int]:
	var door_ids: Array[int] = []
	for doorway in topology.get_doorways():
		door_ids.append(doorway.door_id)
	door_ids.sort()
	return door_ids

func _room_progress(state: LevelEncounterState, room_id: int) -> LevelEncounterState.RoomProgress:
	return state._rooms[room_id] as LevelEncounterState.RoomProgress

func _remaining_enemy_count(state: LevelEncounterState, room_id: int) -> int:
	var room := _room_progress(state, room_id)
	return room.enemy_ids.size() - room.defeated_count

func _summary_equals(summary: LevelEncounterSummary, waves: int, active: int, pending: int) -> bool:
	return summary != null \
		and summary.active_wave_count == waves \
		and summary.active_enemy_count == active \
		and summary.pending_enemy_count == pending

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
