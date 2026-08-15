extends SceneTree

const EntitySpawnGeometryType := preload("res://entities/entity_spawn_geometry.gd")
const LevelModuleSpaceType := preload("res://levels/definitions/level_module_space.gd")

const LEVEL_CATALOG_PATH: String = "res://levels/content/dungeons/stone/level_catalog.tres"
const ENTITY_CATALOG_PATH: String = "res://entities/entity_catalog.tres"
const BLOCK_CATALOG_PATH: String = "res://blocks/block_catalog.tres"
const PLAYER_SCENE_PATH: String = "res://player/player.tscn"
const LEVEL_ID: StringName = &"stone_dungeon"
const ENTRANCE_ID: StringName = &"overworld_dungeon_entrance"
const LEVEL_SEED: int = 1337
const ENTRANCE_COORDINATE: Vector3i = Vector3i(7, 0, -9)

class PhysicsDefeatDriver:
	extends Node

	var entity_runtime: EntityRuntime
	var runtime_id: int
	var result: EntityDamageResult
	var defeat_frame: int = -1

	func setup(p_entity_runtime: EntityRuntime, p_runtime_id: int) -> void:
		entity_runtime = p_entity_runtime
		runtime_id = p_runtime_id

	func _physics_process(_delta: float) -> void:
		defeat_frame = Engine.get_physics_frames()
		result = entity_runtime.try_apply_damage(runtime_id, 10000.0)
		set_physics_process(false)

class PhysicsEncounterTickDriver:
	extends Node

	signal tick_completed(physics_frame: int)

	var coordinator: LevelEncounterCoordinator

	func setup(p_coordinator: LevelEncounterCoordinator) -> void:
		coordinator = p_coordinator

	func _physics_process(_delta: float) -> void:
		coordinator.tick()
		tick_completed.emit(Engine.get_physics_frames())

var _failures: int = 0
var _assertions: int = 0
var _progress_events: Array[Vector2i] = []
var _cleared_count: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var level_catalog := load(LEVEL_CATALOG_PATH) as LevelCatalog
	var entity_catalog := load(ENTITY_CATALOG_PATH) as EntityCatalog
	var block_catalog := load(BLOCK_CATALOG_PATH) as BlockCatalog
	_expect(level_catalog != null and level_catalog.validate(), "stone level catalog did not validate")
	_expect(entity_catalog != null and entity_catalog.validate(), "entity catalog did not validate")
	_expect(block_catalog != null and block_catalog.validate(), "block catalog did not validate")
	_expect(LevelEncounterCatalogValidator.validate(level_catalog, entity_catalog), "encounter cross-catalog validation failed")
	if level_catalog == null or entity_catalog == null or block_catalog == null:
		_finish()
		return

	var generation := LevelGenerator.new().generate(
		level_catalog,
		LEVEL_ID,
		LEVEL_SEED,
		ENTRANCE_ID,
		ENTRANCE_COORDINATE,
	)
	_expect(generation.succeeded, "stone dungeon generation failed: %s" % generation.failure_reason)
	if not generation.succeeded:
		_finish()
		return
	var definition := level_catalog.get_level(LEVEL_ID)
	var topology := LevelEncounterTopology.create(generation.layout, definition)
	var state := LevelEncounterState.create(topology, generation.layout.seed_value) if topology != null else null
	var level_state := LevelState.from_layout(generation.layout, block_catalog)
	_expect(topology != null, "encounter topology creation failed")
	_expect(state != null, "encounter state creation failed")
	if topology == null or state == null:
		_finish()
		return
	await _test_production_room_cap(topology, generation.layout, block_catalog, entity_catalog)

	var room_id := _find_ready_root_with_child(topology, state)
	_expect(room_id >= 0, "generated topology has no ready root room with a child")
	if room_id < 0:
		_finish()
		return
	var room := topology.get_room(room_id)
	var constrained_spawn_cells := _spread_spawn_cells(room.spawn_cells, 3)
	_expect(constrained_spawn_cells.size() == 3, "root room did not provide three spawn candidates")
	if constrained_spawn_cells.size() != 3:
		_finish()
		return
	var invalid_spawn_cell := constrained_spawn_cells[0] + Vector3i.UP
	var zombie_definition := entity_catalog.get_definition(&"zombie")
	_expect(
		not EntitySpawnGeometryType.can_spawn(level_state, zombie_definition, Vector3(invalid_spawn_cell) + Vector3(0.5, 0.0, 0.5)),
		"spawn-geometry fixture did not contain a rejected candidate",
	)
	var mixed_spawn_cells: Array[Vector3i] = [invalid_spawn_cell]
	mixed_spawn_cells.append_array(constrained_spawn_cells)
	room._spawn_cells.assign(mixed_spawn_cells)
	_test_module_spawn_geometry(level_catalog, zombie_definition)

	var runtime := EntityRuntime.new()
	var coordinator := LevelEncounterCoordinator.new()
	var renderer := LevelGeometryRenderer.new()
	var torch_renderer := TorchRenderer.new()
	var hud := _make_hud()
	var player := (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as PlayerMotor
	runtime.name = "DungeonEntities"
	coordinator.name = "EncounterCoordinator"
	renderer.name = "Geometry"
	torch_renderer.name = "Torches"
	player.name = "Player"
	player.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(runtime)
	root.add_child(coordinator)
	root.add_child(torch_renderer)
	root.add_child(renderer)
	root.add_child(hud)
	root.add_child(player)
	runtime.setup(entity_catalog, level_state, 64, 64, EntityNavigationLimits.new(48, 2048, 2))
	_expect(coordinator.setup(topology, state, level_state, runtime, entity_catalog, generation.layout.seed_value), "encounter coordinator setup failed")
	_expect(int(coordinator._capacity_by_room[room_id]) == 3, "static room capacity did not retain the three valid spawn cells")
	_expect(
		int(coordinator._capacity_by_room[room_id]) <= LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM,
		"coordinator static capacity exceeded the per-room enemy cap",
	)
	torch_renderer.setup(block_catalog, 0, 0.0)
	var torch_attachments: Dictionary = {}
	for torch in generation.layout.torches:
		torch_attachments[torch.cell] = LevelSocketDefinition.vector_for(torch.wall_direction)
	torch_renderer.spawn_torches(torch_attachments)
	var incompatible_shader := Shader.new()
	incompatible_shader.code = "shader_type spatial; void fragment() { ALBEDO = vec3(1.0); }"
	_expect(not renderer.setup(
		generation.layout,
		level_state,
		topology,
		state.get_door_locks(),
		state.get_revealed_room_ids(),
		BlockTextureSet.new(block_catalog),
		incompatible_shader,
		torch_renderer,
	), "geometry renderer accepted a shader without the reveal contract")
	_expect(renderer.get_child_count() == 0, "incompatible shader setup partially committed scene nodes")
	var incomplete_locks := state.get_door_locks()
	incomplete_locks.erase(incomplete_locks.keys()[0])
	_expect(not renderer.setup(
		generation.layout,
		level_state,
		topology,
		incomplete_locks,
		state.get_revealed_room_ids(),
		BlockTextureSet.new(block_catalog),
		definition.presentation.terrain_shader,
		torch_renderer,
	), "geometry renderer accepted incomplete doorway locks")
	_expect(renderer.get_child_count() == 0, "failed geometry setup partially committed scene nodes")
	for torch_cell in torch_attachments:
		_expect(is_equal_approx(_torch_reveal_strength(torch_renderer, torch_cell as Vector3i), 1.0), "failed geometry setup partially changed torch reveal state")
	_expect(renderer.setup(
		generation.layout,
		level_state,
		topology,
		state.get_door_locks(),
		state.get_revealed_room_ids(),
		BlockTextureSet.new(block_catalog),
		definition.presentation.terrain_shader,
		torch_renderer,
	), "geometry renderer setup failed")
	coordinator.set_player(player)
	coordinator.door_locks_changed.connect(renderer.apply_door_locks)
	coordinator.encounter_progress_changed.connect(_on_progress_changed)
	coordinator.encounter_progress_changed.connect(hud.show_encounter)
	coordinator.encounter_cleared.connect(_on_encounter_cleared)
	coordinator.encounter_cleared.connect(hud.show_cleared)
	coordinator.encounter_cleared.connect(func() -> void: renderer.reveal_rooms(state.get_revealed_room_ids()))

	var unrelated_ids := _spawn_unrelated_entities(runtime, topology, level_state, entity_catalog, 2)
	_expect(unrelated_ids.size() == 2, "could not create two unrelated dungeon entities")
	var parent_doorway := _find_doorway(topology, room.parent_door_id)
	_expect(parent_doorway != null, "root room parent doorway is missing")
	if parent_doorway == null:
		await _cleanup(runtime, coordinator, renderer, torch_renderer, hud, player)
		_finish()
		return

	var gate_path := _find_open_gate_path(level_state, parent_doorway, player.player_width, player.player_height)
	_expect(gate_path.size() == 2, "root incoming gate had no traversable open path")
	player.global_position = _aperture_body_position(parent_doorway)
	coordinator.tick()
	_expect(state.get_active_room_id() == -1, "player intersecting the incoming gate activated the room")
	_expect(_room_progress(state, room_id).status == LevelEncounterState.RoomStatus.READY, "failed boundary activation changed room state")
	_expect(runtime.get_active_count() == unrelated_ids.size(), "failed boundary activation spawned encounter entities")

	var parent_barrier := renderer._barrier_meshes[room.parent_door_id] as MeshInstance3D
	_expect(not parent_barrier.visible and is_equal_approx(parent_barrier.transparency, 1.0), "ready root incoming doorway retained a fill block")
	_expect(is_equal_approx(float((renderer._room_materials[room_id] as ShaderMaterial).get_shader_parameter("reveal_amount")), 1.0), "ready root room did not begin revealed")
	var revealed_child_room_id := room.child_room_ids[0]
	var child_material := renderer._room_materials[revealed_child_room_id] as ShaderMaterial
	_expect(is_zero_approx(float(child_material.get_shader_parameter("reveal_amount"))), "locked child branch did not begin completely dark")
	for torch_cell in renderer._room_torch_cells[revealed_child_room_id] as Array[Vector3i]:
		_expect(is_zero_approx(_torch_reveal_strength(torch_renderer, torch_cell)), "locked child branch retained a visible torch")
	player.global_position = Vector3(constrained_spawn_cells[0]) + Vector3(0.5, 0.0, 0.5)
	coordinator.tick()
	var progress := _room_progress(state, room_id)
	_expect(progress.status == LevelEncounterState.RoomStatus.ACTIVE, "fully contained player did not activate the ready room")
	_expect(state.get_active_room_id() == room_id, "activated room ID was not retained")
	_expect(progress.active_entity_ids.size() == 2, "initial transactional spawn did not fill both available slots")
	_expect(state.get_spawned_enemy_count(room_id) == 2, "initial spawn advanced by the wrong count")
	_expect(runtime.get_active_count() == unrelated_ids.size() + 2, "initial spawn did not commit atomically to the runtime")
	_expect(not _progress_events.is_empty() and _progress_events.back().x == 2, "activation did not publish active encounter progress")
	var expected_pending := progress.enemy_ids.size() - progress.next_spawn_index
	_expect(
		(hud.get_node("Panel/Margin/Label") as Label).text == "Room Locked  •  2 active  •  %d pending" % expected_pending,
		"HUD did not present separate active and pending encounter counts",
	)
	_expect(parent_barrier.visible and is_zero_approx(parent_barrier.transparency), "room activation did not restore its authored doorway fill")

	for door_id in room.door_ids:
		_expect(bool(state.get_door_locks()[door_id]), "activation did not logically lock room door %d" % door_id)
		var doorway := _find_doorway(topology, door_id)
		for cell in doorway.aperture_cells:
			_expect(level_state.get_cell_value(cell) == doorway.fill_block_id, "locked door did not project its authored fill at %s" % cell)
			_expect(level_state.is_solid(cell), "locked door did not block movement at %s" % cell)
			_expect(level_state.is_raycast_solid(cell), "locked door did not block raycasts at %s" % cell)

	if gate_path.size() == 2:
		var start_cell := gate_path[0]
		var goal_cell := gate_path[1]
		var blocked_path := VoxelPathfinder.find_path(level_state, start_cell, goal_cell, player.player_width, player.player_height, 8, 512)
		_expect(blocked_path.status != VoxelPathResult.Status.FOUND, "pathfinding crossed the locked incoming gate")
		var ray_origin := Vector3(start_cell) + Vector3(0.5, player.player_height * 0.5, 0.5)
		var ray_target := Vector3(goal_cell) + Vector3(0.5, player.player_height * 0.5, 0.5)
		_expect(not VoxelLineOfSight.has_clear_path(level_state, ray_origin, ray_target), "line of sight crossed the locked incoming gate")
		var ray_hit := VoxelRaycast.cast(level_state, ray_origin, ray_origin.direction_to(ray_target), ray_origin.distance_to(ray_target))
		_expect(ray_hit != null and parent_doorway.aperture_cells.has(ray_hit.target_cell), "voxel raycast did not hit the locked incoming gate")
		_expect(VoxelBodySolver.collides_at(level_state, _aperture_body_position(parent_doorway), player.player_width, player.player_height, false), "player body did not collide with the locked gate")

	var unblocked_player_position: Variant = _find_player_position_clear_of_spawns(room, topology, constrained_spawn_cells, player.player_width, player.player_height)
	_expect(unblocked_player_position is Vector3, "root room had no player position clear of constrained spawn cells")
	if unblocked_player_position is Vector3:
		var spawned_before_unblocking := state.get_spawned_enemy_count(room_id)
		player.global_position = unblocked_player_position as Vector3
		coordinator.tick()
		_expect(state.get_spawned_enemy_count(room_id) == spawned_before_unblocking + 1, "freed transient spawn position was not retried")
		_expect(progress.active_entity_ids.size() == 3, "freed static encounter slot did not restore deterministic capacity")

	if unrelated_ids.size() == 2:
		var active_before_unrelated := progress.active_entity_ids.size()
		var pending_before_unrelated := progress.enemy_ids.size() - progress.next_spawn_index
		_expect(runtime.try_despawn(unrelated_ids[0]), "unrelated entity despawn failed")
		_expect(progress.active_entity_ids.size() == active_before_unrelated, "unrelated despawn advanced encounter state")
		_expect(progress.enemy_ids.size() - progress.next_spawn_index == pending_before_unrelated, "unrelated despawn changed pending enemies")
		var unrelated_defeat := runtime.try_apply_damage(unrelated_ids[1], 10000.0)
		_expect(unrelated_defeat != null and unrelated_defeat.defeated, "unrelated entity defeat failed")
		_expect(progress.active_entity_ids.size() == active_before_unrelated, "unrelated defeat advanced encounter state")
		_expect(progress.enemy_ids.size() - progress.next_spawn_index == pending_before_unrelated, "unrelated defeat changed pending enemies")

	var spawned_before_refill := state.get_spawned_enemy_count(room_id)
	var active_capacity := progress.active_entity_ids.size()
	var first_assigned_id := _first_runtime_id(progress.active_entity_ids)
	_expect(first_assigned_id > 0, "active encounter had no assigned runtime ID")
	if first_assigned_id > 0:
		var defeat_driver := PhysicsDefeatDriver.new()
		var tick_driver := PhysicsEncounterTickDriver.new()
		defeat_driver.setup(runtime, first_assigned_id)
		tick_driver.setup(coordinator)
		root.add_child(defeat_driver)
		root.add_child(tick_driver)
		var same_frame_tick: int = await tick_driver.tick_completed
		_expect(defeat_driver.result != null and defeat_driver.result.defeated, "assigned encounter defeat failed")
		_expect(same_frame_tick == defeat_driver.defeat_frame, "physics-order fixture did not defeat before the same-frame encounter tick")
		_expect(state.get_spawned_enemy_count(room_id) == spawned_before_refill, "defeat refilled during the defeat callback")
		_expect(progress.active_entity_ids.size() == active_capacity - 1, "defeat did not open exactly one encounter slot")
		var later_frame_tick: int = await tick_driver.tick_completed
		_expect(later_frame_tick > defeat_driver.defeat_frame, "replacement tick did not advance to a later physics frame")
		_expect(state.get_spawned_enemy_count(room_id) == spawned_before_refill + 1, "next-tick refill did not spawn one pending enemy")
		_expect(progress.active_entity_ids.size() == active_capacity, "next-tick refill did not restore encounter capacity")
		tick_driver.set_physics_process(false)
		defeat_driver.queue_free()
		tick_driver.queue_free()

	var defeat_iterations := 0
	while state.get_active_room_id() == room_id and defeat_iterations < LevelRoomEncounterDefinition.MAX_ENEMY_COUNT + 2:
		progress = _room_progress(state, room_id)
		var runtime_id := _first_runtime_id(progress.active_entity_ids)
		if runtime_id <= 0:
			break
		var result := runtime.try_apply_damage(runtime_id, 10000.0)
		_expect(result != null and result.defeated, "configured encounter enemy defeat failed at iteration %d" % defeat_iterations)
		await physics_frame
		coordinator.tick()
		defeat_iterations += 1

	progress = _room_progress(state, room_id)
	_expect(progress.status == LevelEncounterState.RoomStatus.CLEARED, "room did not clear after every configured enemy died")
	_expect(state.get_active_room_id() == -1, "cleared room remained active")
	_expect(progress.next_spawn_index == progress.enemy_ids.size(), "room cleared before every configured enemy spawned")
	_expect(progress.defeated_count == progress.enemy_ids.size(), "room cleared before every configured enemy died")
	_expect(progress.active_entity_ids.is_empty(), "cleared room retained assigned runtime IDs")
	_expect(_cleared_count == 1, "clear signal did not emit exactly once")
	_expect((hud.get_node("Panel/Margin/Label") as Label).text == "Room Cleared", "HUD did not present room clearance")
	for door_id in room.door_ids:
		_expect(not bool(state.get_door_locks()[door_id]), "cleared room door remained locked: %d" % door_id)
		var doorway := _find_doorway(topology, door_id)
		for cell in doorway.aperture_cells:
			_expect(level_state.get_cell_value(cell) == StructureCell.AIR, "cleared room door did not restore AIR at %s" % cell)
			_expect(not level_state.is_solid(cell), "cleared room door still blocked movement at %s" % cell)
	for child_room_id in room.child_room_ids:
		var child_room := topology.get_room(child_room_id)
		_expect(_room_progress(state, child_room_id).status == LevelEncounterState.RoomStatus.READY, "cleared room did not ready child %d" % child_room_id)
		_expect(not bool(state.get_door_locks()[child_room.parent_door_id]), "cleared room did not open child gate %d" % child_room.parent_door_id)
	_expect(parent_barrier.visible and parent_barrier.transparency < 1.0, "cleared doorway fill disappeared without fading")
	await create_timer(LevelGeometryRenderer.TRANSITION_SECONDS + 0.05).timeout
	_expect(not parent_barrier.visible and is_equal_approx(parent_barrier.transparency, 1.0), "cleared doorway fill did not finish fading")
	_expect(is_equal_approx(float(child_material.get_shader_parameter("reveal_amount")), 1.0), "unlocked child branch did not finish fading in")
	for torch_cell in renderer._room_torch_cells[revealed_child_room_id] as Array[Vector3i]:
		_expect(is_equal_approx(_torch_reveal_strength(torch_renderer, torch_cell), 1.0), "unlocked child branch torch did not finish fading in")
	if gate_path.size() == 2:
		var start_cell := gate_path[0]
		var goal_cell := gate_path[1]
		var reopened_path := VoxelPathfinder.find_path(level_state, start_cell, goal_cell, player.player_width, player.player_height, 8, 512)
		_expect(reopened_path.status == VoxelPathResult.Status.FOUND, "pathfinding did not traverse the cleared incoming gate")
		var ray_origin := Vector3(start_cell) + Vector3(0.5, player.player_height * 0.5, 0.5)
		var ray_target := Vector3(goal_cell) + Vector3(0.5, player.player_height * 0.5, 0.5)
		_expect(VoxelLineOfSight.has_clear_path(level_state, ray_origin, ray_target), "line of sight did not reopen through the cleared incoming gate")
		_expect(not VoxelBodySolver.collides_at(level_state, _aperture_body_position(parent_doorway), player.player_width, player.player_height, false), "player body still collided with the cleared gate")

	await _cleanup(runtime, coordinator, renderer, torch_renderer, hud, player)
	_finish()

func _find_ready_root_with_child(topology: LevelEncounterTopology, state: LevelEncounterState) -> int:
	for room_id in topology.get_room_ids():
		var room := topology.get_room(room_id)
		if room.parent_room_id < 0 and not room.child_room_ids.is_empty() and _room_progress(state, room_id).status == LevelEncounterState.RoomStatus.READY:
			return room_id
	return -1

func _spread_spawn_cells(cells: Array[Vector3i], count: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if cells.size() < count or count <= 0:
		return result
	for index in count:
		var source_index := 0 if count == 1 else roundi(float(index) * float(cells.size() - 1) / float(count - 1))
		result.append(cells[source_index])
	return result

func _test_module_spawn_geometry(level_catalog: LevelCatalog, source_entity: EntityDefinition) -> void:
	var module := level_catalog.get_module(&"stone_room").duplicate(true) as LevelModuleDefinition
	var candidates := module.get_enemy_spawn_candidate_cells()
	_expect(candidates.size() > 1, "spawn-geometry module fixture had fewer than two candidates")
	if candidates.size() <= 1:
		return
	var entity := source_entity.duplicate(true) as EntityDefinition
	entity.body_height = 2.2
	var blocked_candidate := candidates[0]
	module.cells[StructureCell.index_of(blocked_candidate + Vector3i.UP * 2, module.size)] = BlockId.Type.STONE
	var space := LevelModuleSpaceType.new(module)
	var blocked_position := Vector3(blocked_candidate) + Vector3(0.5, 0.0, 0.5)
	_expect(not EntitySpawnGeometryType.can_spawn(space, entity, blocked_position), "module spawn geometry accepted a body-obstructed candidate")
	var valid_count := 0
	for candidate in candidates.slice(1):
		var position := Vector3(candidate) + Vector3(0.5, 0.0, 0.5)
		if EntitySpawnGeometryType.can_spawn(space, entity, position):
			valid_count += 1
	_expect(valid_count > 0, "module spawn geometry did not retain any fitting candidate")
	_expect(LevelEncounterCatalogValidator._has_usable_candidate(module, entity), "catalog validation rejected a module with a fitting candidate subset")

func _test_production_room_cap(
	topology: LevelEncounterTopology,
	layout: LevelLayout,
	block_catalog: BlockCatalog,
	entity_catalog: EntityCatalog,
) -> void:
	var state := LevelEncounterState.create(topology, layout.seed_value)
	var level_state := LevelState.from_layout(layout, block_catalog)
	var runtime := EntityRuntime.new()
	var coordinator := LevelEncounterCoordinator.new()
	root.add_child(runtime)
	root.add_child(coordinator)
	runtime.setup(entity_catalog, level_state, 64, 64, EntityNavigationLimits.new(48, 2048, 2))
	_expect(coordinator.setup(topology, state, level_state, runtime, entity_catalog, layout.seed_value), "production room-cap coordinator setup failed")
	var master_room_id := -1
	for room_id in topology.get_room_ids():
		var capacity := int(coordinator._capacity_by_room[room_id])
		_expect(capacity <= LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM, "production room capacity exceeded twenty: %d" % room_id)
		if state.get_configured_enemy_ids(room_id).size() == 40:
			master_room_id = room_id
			_expect(capacity == LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM, "production master room did not expose twenty concurrent slots")
	_expect(master_room_id >= 0, "production topology has no forty-enemy master room")
	coordinator.shutdown()
	runtime.shutdown()
	coordinator.queue_free()
	runtime.queue_free()
	await process_frame
	await process_frame

func _spawn_unrelated_entities(
	runtime: EntityRuntime,
	topology: LevelEncounterTopology,
	level_state: LevelState,
	entity_catalog: EntityCatalog,
	count: int,
) -> Array[int]:
	var runtime_ids: Array[int] = []
	var definition := entity_catalog.get_definition(&"sheep")
	var cells: Array[Vector3i] = []
	for value in level_state.snapshot_cells().keys():
		var cell := value as Vector3i
		if level_state.is_interior_open(cell) and level_state.is_solid(cell + Vector3i.DOWN):
			cells.append(cell)
	cells.sort_custom(_cell_less)
	for cell in cells:
		var position := Vector3(cell) + Vector3(0.5, 0.0, 0.5)
		if topology.find_room_containing_body(position, definition.body_width, definition.body_height) >= 0:
			continue
		var requests: Array[EntitySpawnRequest] = [EntitySpawnRequest.new(&"sheep", position, 9000 + runtime_ids.size())]
		var spawned := runtime.try_spawn_batch(requests)
		if spawned.is_empty():
			continue
		runtime_ids.append(spawned[0])
		if runtime_ids.size() == count:
			break
	return runtime_ids

func _find_doorway(topology: LevelEncounterTopology, door_id: int) -> LevelDoorway:
	for doorway in topology.get_doorways():
		if doorway.door_id == door_id:
			return doorway
	return null

func _find_open_gate_path(
	level_state: LevelState,
	doorway: LevelDoorway,
	body_width: float,
	body_height: float,
) -> Array[Vector3i]:
	var direction := LevelSocketDefinition.vector_for(doorway.direction)
	var aperture := doorway.aperture_cells
	aperture.sort_custom(_cell_less)
	for aperture_cell in aperture:
		for inward_distance in range(1, 4):
			var start := aperture_cell - direction * inward_distance
			for outward_distance in range(1, 4):
				var goal := aperture_cell + direction * outward_distance
				var result := VoxelPathfinder.find_path(level_state, start, goal, body_width, body_height, 8, 512)
				if result.status == VoxelPathResult.Status.FOUND:
					return [start, goal]
	return []

func _aperture_body_position(doorway: LevelDoorway) -> Vector3:
	var aperture := doorway.aperture_cells
	aperture.sort_custom(_cell_less)
	return Vector3(aperture[0]) + Vector3(0.5, 0.0, 0.5)

func _find_player_position_clear_of_spawns(
	room: LevelEncounterRoom,
	topology: LevelEncounterTopology,
	spawn_cells: Array[Vector3i],
	body_width: float,
	body_height: float,
) -> Variant:
	var interior_cells: Array = room._interior_cells.keys()
	interior_cells.sort_custom(_cell_less)
	for value in interior_cells:
		var cell := value as Vector3i
		var clear := true
		for spawn_cell in spawn_cells:
			if Vector2(cell.x - spawn_cell.x, cell.z - spawn_cell.z).length_squared() < 9.0:
				clear = false
				break
		if not clear:
			continue
		var position := Vector3(cell) + Vector3(0.5, 0.0, 0.5)
		if room.contains_body(position, body_width, body_height, topology.get_doorways()):
			return position
	return null

func _first_runtime_id(active_entity_ids: Dictionary) -> int:
	if active_entity_ids.is_empty():
		return -1
	var runtime_ids: Array = active_entity_ids.keys()
	runtime_ids.sort()
	return int(runtime_ids[0])

func _room_progress(state: LevelEncounterState, room_id: int) -> LevelEncounterState.RoomProgress:
	return state._rooms[room_id] as LevelEncounterState.RoomProgress

func _torch_reveal_strength(renderer: TorchRenderer, cell: Vector3i) -> float:
	var root_node := renderer.torch_instances.get(cell) as Node3D
	assert(root_node != null)
	var stem := root_node.get_node("Stem") as MeshInstance3D
	return 0.0 if not stem.visible else 1.0 - stem.transparency

func _make_hud() -> LevelEncounterHUD:
	var hud := LevelEncounterHUD.new()
	var panel := PanelContainer.new()
	var margin := MarginContainer.new()
	var label := Label.new()
	panel.name = "Panel"
	margin.name = "Margin"
	label.name = "Label"
	margin.add_child(label)
	panel.add_child(margin)
	hud.add_child(panel)
	return hud

func _cell_less(first: Vector3i, second: Vector3i) -> bool:
	if first.x != second.x:
		return first.x < second.x
	if first.y != second.y:
		return first.y < second.y
	return first.z < second.z

func _on_progress_changed(active_enemy_count: int, pending_enemy_count: int) -> void:
	_progress_events.append(Vector2i(active_enemy_count, pending_enemy_count))

func _on_encounter_cleared() -> void:
	_cleared_count += 1

func _cleanup(
	runtime: EntityRuntime,
	coordinator: LevelEncounterCoordinator,
	renderer: LevelGeometryRenderer,
	torch_renderer: TorchRenderer,
	hud: LevelEncounterHUD,
	player: PlayerMotor,
) -> void:
	coordinator.shutdown()
	runtime.shutdown()
	coordinator.queue_free()
	renderer.queue_free()
	torch_renderer.queue_free()
	hud.queue_free()
	player.queue_free()
	runtime.queue_free()
	await process_frame
	await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "runtime test left %d orphan nodes" % orphan_count)

func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	print("[level_encounter_runtime] FAIL: %s" % message)

func _finish() -> void:
	if _failures == 0:
		print("LEVEL_ENCOUNTER_RUNTIME PASS assertions=%d progress_events=%d" % [_assertions, _progress_events.size()])
		quit(0)
	else:
		print("LEVEL_ENCOUNTER_RUNTIME FAILED failures=%d assertions=%d" % [_failures, _assertions])
		quit(1)
