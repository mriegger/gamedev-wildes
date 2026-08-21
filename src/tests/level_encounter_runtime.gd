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
var _summary_events: Array[LevelEncounterSummary] = []
var _cleared_room_ids: Array[int] = []

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
	runtime.setup(entity_catalog, level_state, 64, 64, EntityNavigationLimits.new(48, 2048, 2), EntityRuntime.Mode.GAMEPLAY)
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
	var texture_set := BlockTextureSet.new(block_catalog)
	var incompatible_shader := Shader.new()
	incompatible_shader.code = "shader_type spatial; void fragment() { ALBEDO = vec3(1.0); }"
	_expect(not renderer.setup(
		generation.layout,
		level_state,
		topology,
		state.get_sealed_door_ids(),
		state.get_discovered_room_ids(),
		texture_set,
		incompatible_shader,
		torch_renderer,
	), "geometry renderer accepted a shader without the terrain texture contract")
	_expect(renderer.get_child_count() == 0, "incompatible shader setup partially committed scene nodes")
	_expect(renderer._room_meshes.is_empty() and renderer._seal_meshes.is_empty(), "incompatible shader setup partially committed geometry indexes")
	var wrong_texture_type_shader := Shader.new()
	wrong_texture_type_shader.code = "shader_type spatial; uniform sampler2D terrain_textures; void fragment() { ALBEDO = vec3(1.0); }"
	_expect(not renderer.setup(
		generation.layout,
		level_state,
		topology,
		state.get_sealed_door_ids(),
		state.get_discovered_room_ids(),
		texture_set,
		wrong_texture_type_shader,
		torch_renderer,
	), "geometry renderer accepted a two-dimensional terrain texture uniform")
	var invalid_seals := state.get_sealed_door_ids()
	invalid_seals.append(invalid_seals[0])
	_expect(not renderer.setup(
		generation.layout,
		level_state,
		topology,
		invalid_seals,
		state.get_discovered_room_ids(),
		texture_set,
		definition.presentation.terrain_shader,
		torch_renderer,
	), "geometry renderer accepted duplicate seals")
	_expect(renderer.get_child_count() == 0, "failed geometry setup partially committed scene nodes")
	_expect(renderer._room_meshes.is_empty() and renderer._seal_meshes.is_empty(), "failed geometry setup partially committed geometry indexes")
	for torch_cell in torch_attachments:
		_expect_torch_state(torch_renderer, torch_cell as Vector3i, 1.0, "failed geometry setup")
	_expect(renderer.setup(
		generation.layout,
		level_state,
		topology,
		state.get_sealed_door_ids(),
		state.get_discovered_room_ids(),
		texture_set,
		definition.presentation.terrain_shader,
		torch_renderer,
	), "geometry renderer setup failed")
	_expect_initial_geometry_state(renderer, topology, state, torch_renderer, texture_set)
	coordinator.set_player(player)
	coordinator.seals_opened.connect(renderer.open_seals)
	coordinator.encounter_summary_changed.connect(_on_summary_changed)
	coordinator.encounter_summary_changed.connect(hud.show_summary)
	coordinator.room_cleared.connect(_on_room_cleared)
	coordinator.room_cleared.connect(func(cleared_room_id: int) -> void:
		var discovered_room_ids := topology.get_discovered_room_ids_after_clear(cleared_room_id)
		if not discovered_room_ids.is_empty():
			renderer.discover_rooms(discovered_room_ids)
		if state.get_summary().active_wave_count == 0:
			hud.show_cleared()
	)

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
	_expect(state.get_active_room_ids().is_empty(), "player intersecting the incoming gate activated the room")
	_expect(_room_progress(state, room_id).status == LevelEncounterState.RoomStatus.READY, "failed boundary activation changed room state")
	_expect(runtime.get_active_count() == unrelated_ids.size(), "failed boundary activation spawned encounter entities")

	var parent_seal := renderer._seal_meshes[room.parent_door_id] as MeshInstance3D
	_expect(
		not parent_seal.visible \
			and is_equal_approx(parent_seal.transparency, 1.0) \
			and parent_seal.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"ready root incoming doorway retained visible or shadow-casting seal geometry",
	)
	var root_room_mesh := renderer._room_meshes[room_id] as MeshInstance3D
	_expect(
		root_room_mesh.visible \
			and is_zero_approx(root_room_mesh.transparency) \
			and root_room_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"ready root room did not begin fully visible and shadow-casting",
	)
	var revealed_child_room_id := room.child_room_ids[0]
	var child_mesh := renderer._room_meshes[revealed_child_room_id] as MeshInstance3D
	_expect(
		not child_mesh.visible \
			and is_equal_approx(child_mesh.transparency, 1.0) \
			and child_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"locked child branch remained visible or shadow-casting",
	)
	for torch_cell in renderer._room_torch_cells[revealed_child_room_id] as Array[Vector3i]:
		_expect_torch_state(torch_renderer, torch_cell, 0.0, "locked child branch")
	player.global_position = Vector3(constrained_spawn_cells[0]) + Vector3(0.5, 0.0, 0.5)
	var sealed_before_activation := state.get_sealed_door_ids()
	var visible_seal_id := _find_sealed_door_for_room(room, sealed_before_activation)
	_expect(visible_seal_id >= 0, "ready root room had no visible authored seal to open")
	var visible_seal := renderer._seal_meshes.get(visible_seal_id) as MeshInstance3D
	_expect(
		visible_seal != null \
			and visible_seal.visible \
			and is_zero_approx(visible_seal.transparency) \
			and visible_seal.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
			and visible_seal.material_override == _shared_terrain_material(renderer),
		"ready root authored seal was not opaque, shadow-casting, and terrain-textured",
	)
	coordinator.tick()
	var progress := _room_progress(state, room_id)
	_expect(progress.status == LevelEncounterState.RoomStatus.ACTIVE, "fully contained player did not activate the ready room")
	_expect(state.get_active_room_ids() == [room_id], "activated room ID was not retained")
	_expect(progress.active_entity_ids.size() == 2, "initial transactional spawn did not fill both available slots")
	_expect(state.get_spawned_enemy_count(room_id) == 2, "initial spawn advanced by the wrong count")
	_expect(runtime.get_active_count() == unrelated_ids.size() + 2, "initial spawn did not commit atomically to the runtime")
	_expect(not _summary_events.is_empty() and _summary_events.back().active_enemy_count == 2, "activation did not publish aggregate encounter progress")
	var expected_pending := progress.enemy_ids.size() - progress.defeated_count - progress.active_entity_ids.size()
	_expect(
		(hud.get_node("Panel/Margin/Label") as Label).text == "1 wave  •  2 active  •  %d pending" % expected_pending,
		"HUD did not present aggregate wave, active, and pending counts",
	)
	_expect(state.get_sealed_door_ids() == sealed_before_activation, "room activation changed monotonic seals")
	_expect(not parent_seal.visible and is_equal_approx(parent_seal.transparency, 1.0), "room activation resealed the discovered retreat path")

	for door_id in room.door_ids:
		var doorway := _find_doorway(topology, door_id)
		for cell in doorway.aperture_cells:
			if sealed_before_activation.has(door_id):
				_expect(level_state.get_cell_value(cell) == doorway.fill_block_id, "seal did not project its authored fill at %s" % cell)
				_expect(level_state.is_solid(cell), "seal did not block movement at %s" % cell)
				_expect(level_state.is_raycast_solid(cell), "seal did not block raycasts at %s" % cell)
			else:
				_expect(level_state.get_cell_value(cell) == StructureCell.AIR, "discovered doorway was resealed at %s" % cell)

	if gate_path.size() == 2:
		var start_cell := gate_path[0]
		var goal_cell := gate_path[1]
		var retreat_path := VoxelPathfinder.find_path(level_state, start_cell, goal_cell, player.player_width, player.player_height, 8, 512)
		_expect(retreat_path.status == VoxelPathResult.Status.FOUND, "pathfinding could not retreat through the discovered doorway")
		var ray_origin := Vector3(start_cell) + Vector3(0.5, player.player_height * 0.5, 0.5)
		var ray_target := Vector3(goal_cell) + Vector3(0.5, player.player_height * 0.5, 0.5)
		_expect(VoxelLineOfSight.has_clear_path(level_state, ray_origin, ray_target), "line of sight did not remain open through the discovered doorway")
		var ray_hit := VoxelRaycast.cast(level_state, ray_origin, ray_origin.direction_to(ray_target), ray_origin.distance_to(ray_target))
		_expect(ray_hit == null or not parent_doorway.aperture_cells.has(ray_hit.target_cell), "voxel raycast hit a removed incoming seal")
		_expect(not VoxelBodySolver.collides_at(level_state, _aperture_body_position(parent_doorway), player.player_width, player.player_height, false), "player body collided with the discovered doorway")

	var unblocked_player_position: Variant = _find_player_position_clear_of_spawns(room, topology, constrained_spawn_cells, player.player_width, player.player_height)
	_expect(unblocked_player_position is Vector3, "root room had no player position clear of constrained spawn cells")
	if unblocked_player_position is Vector3:
		var spawned_before_unblocking := state.get_spawned_enemy_count(room_id)
		player.global_position = unblocked_player_position as Vector3
		coordinator.tick()
		_expect(state.get_spawned_enemy_count(room_id) == spawned_before_unblocking + 1, "freed transient spawn position was not retried")
		_expect(progress.active_entity_ids.size() == 3, "freed static encounter slot did not restore deterministic capacity")

	var second_room_id := _find_highest_capacity_ready_root(topology, state, coordinator._capacity_by_room, room_id)
	_expect(second_room_id >= 0, "generated topology has no second ready root for concurrent waves")
	var second_progress: LevelEncounterState.RoomProgress
	var second_room_position: Variant = null
	if second_room_id >= 0:
		var second_room := topology.get_room(second_room_id)
		second_room_position = Vector3(second_room.spawn_cells[0]) + Vector3(0.5, 0.0, 0.5)
		player.global_position = second_room_position as Vector3
		coordinator.tick()
		second_progress = _room_progress(state, second_room_id)
		var expected_active_rooms: Array[int] = [room_id, second_room_id]
		expected_active_rooms.sort()
		_expect(state.get_active_room_ids() == expected_active_rooms, "entering another discovered room did not preserve both waves")
		_expect(second_progress.status == LevelEncounterState.RoomStatus.ACTIVE and not second_progress.active_entity_ids.is_empty(), "second room did not activate independently")
		_expect(second_progress.active_entity_ids.size() == LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM, "concurrent fixture did not activate a full twenty-enemy second wave")
		var aggregate := state.get_summary()
		_expect(aggregate.active_wave_count == 2, "concurrent activation did not report two waves")
		_expect(
			(hud.get_node("Panel/Margin/Label") as Label).text == "2 waves  •  %d active  •  %d pending" % [aggregate.active_enemy_count, aggregate.pending_enemy_count],
			"HUD did not aggregate concurrent waves",
		)
		var active_wave_room_ids: Array[int] = [room_id, second_room_id]
		var expected_congregated_count := progress.active_entity_ids.size() + second_progress.active_entity_ids.size()
		var congregated_count := _move_active_waves_into_room(
			runtime,
			state,
			active_wave_room_ids,
			room_id,
			topology,
			level_state,
			zombie_definition,
		)
		_expect(expected_congregated_count > LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM, "concurrent fixture did not exceed one room's origin-wave cap")
		_expect(congregated_count == expected_congregated_count, "enemies from concurrent origins could not physically congregate in one room")

	if second_progress != null and unblocked_player_position is Vector3:
		var roaming_runtime_id := _first_runtime_id(second_progress.active_entity_ids)
		var roaming_actor := runtime.get_actor(roaming_runtime_id)
		var first_wave_active_before := progress.active_entity_ids.size()
		var second_wave_active_before := second_progress.active_entity_ids.size()
		_expect(roaming_actor != null, "second wave had no actor to test cross-room ownership")
		if roaming_actor != null:
			roaming_actor.global_position = unblocked_player_position as Vector3
			runtime.tick_gameplay(0.0, EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT))
			var roaming_defeat := runtime.try_apply_damage(roaming_runtime_id, 10000.0)
			_expect(roaming_defeat != null and roaming_defeat.defeated, "roaming encounter enemy defeat failed")
			_expect(progress.active_entity_ids.size() == first_wave_active_before, "roaming enemy defeat was charged to its physical room")
			_expect(second_progress.active_entity_ids.size() == second_wave_active_before - 1, "roaming enemy defeat lost its originating-wave ownership")
			await physics_frame
			coordinator.tick()
			_expect(second_progress.active_entity_ids.size() == second_wave_active_before, "originating wave did not refill after a roaming defeat")

	if second_progress != null:
		var first_active_before_parallel_refill := progress.active_entity_ids.size()
		var second_active_before_parallel_refill := second_progress.active_entity_ids.size()
		var first_spawned_before_parallel_refill := state.get_spawned_enemy_count(room_id)
		var second_spawned_before_parallel_refill := state.get_spawned_enemy_count(second_room_id)
		_expect(progress.enemy_ids.size() > first_spawned_before_parallel_refill, "first wave had no pending enemy for overlapping refill coverage")
		_expect(second_progress.enemy_ids.size() > second_spawned_before_parallel_refill, "second wave had no pending enemy for overlapping refill coverage")
		var first_parallel_runtime_id := _first_runtime_id(progress.active_entity_ids)
		var second_parallel_runtime_id := _first_runtime_id(second_progress.active_entity_ids)
		var first_defeat_driver := PhysicsDefeatDriver.new()
		var second_defeat_driver := PhysicsDefeatDriver.new()
		var parallel_tick_driver := PhysicsEncounterTickDriver.new()
		first_defeat_driver.setup(runtime, first_parallel_runtime_id)
		second_defeat_driver.setup(runtime, second_parallel_runtime_id)
		parallel_tick_driver.setup(coordinator)
		root.add_child(first_defeat_driver)
		root.add_child(second_defeat_driver)
		root.add_child(parallel_tick_driver)
		var parallel_same_frame_tick: int = await parallel_tick_driver.tick_completed
		_expect(first_defeat_driver.result != null and first_defeat_driver.result.defeated, "first overlapping-wave defeat failed")
		_expect(second_defeat_driver.result != null and second_defeat_driver.result.defeated, "second overlapping-wave defeat failed")
		_expect(first_defeat_driver.defeat_frame == second_defeat_driver.defeat_frame, "overlapping-wave defeats did not occur in the same physics frame")
		_expect(parallel_same_frame_tick == first_defeat_driver.defeat_frame, "overlapping-wave fixture did not tick after both same-frame defeats")
		_expect(state.get_spawned_enemy_count(room_id) == first_spawned_before_parallel_refill, "first wave refilled during its defeat frame")
		_expect(state.get_spawned_enemy_count(second_room_id) == second_spawned_before_parallel_refill, "second wave refilled during its defeat frame")
		_expect(progress.active_entity_ids.size() == first_active_before_parallel_refill - 1, "first wave did not retain its independent open slot")
		_expect(second_progress.active_entity_ids.size() == second_active_before_parallel_refill - 1, "second wave did not retain its independent open slot")
		var parallel_later_frame_tick: int = await parallel_tick_driver.tick_completed
		_expect(parallel_later_frame_tick > parallel_same_frame_tick, "overlapping replacements did not wait for the next physics frame")
		_expect(state.get_spawned_enemy_count(room_id) == first_spawned_before_parallel_refill + 1, "first wave did not refill on the shared next tick")
		_expect(state.get_spawned_enemy_count(second_room_id) == second_spawned_before_parallel_refill + 1, "second wave did not refill on the shared next tick")
		_expect(progress.active_entity_ids.size() == first_active_before_parallel_refill, "first wave did not restore its own capacity")
		_expect(second_progress.active_entity_ids.size() == second_active_before_parallel_refill, "second wave did not restore its own capacity")
		parallel_tick_driver.set_physics_process(false)
		first_defeat_driver.queue_free()
		second_defeat_driver.queue_free()
		parallel_tick_driver.queue_free()

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

	var runtime_api := LevelRuntime.new()
	_expect(not runtime_api.try_request_current_encounter_clear(), "unconfigured level runtime accepted a room clear")
	runtime_api._encounter_coordinator = coordinator
	var passive_room_position: Variant = _find_passive_room_position(
		topology,
		player.player_width,
		player.player_height,
	)
	_expect(passive_room_position is Vector3, "generated topology had no passive room position")
	if passive_room_position is Vector3:
		player.global_position = passive_room_position as Vector3
		_expect(not runtime_api.try_request_current_encounter_clear(), "passive room accepted an encounter clear")
	var active_runtime_ids := state.get_active_runtime_ids(room_id)
	var sorted_active_runtime_ids := active_runtime_ids.duplicate()
	sorted_active_runtime_ids.sort()
	_expect(not active_runtime_ids.is_empty(), "active room query returned no assigned runtime IDs")
	_expect(active_runtime_ids == sorted_active_runtime_ids, "active room query did not sort assigned runtime IDs")
	active_runtime_ids.clear()
	_expect(state.get_active_runtime_ids(room_id) == sorted_active_runtime_ids, "mutating an active runtime ID result changed encounter state")
	player.global_position = unblocked_player_position as Vector3
	var second_runtime_ids_before_clear: Array[int] = []
	var second_spawned_before_clear := 0
	var second_defeated_before_clear := 0
	if second_progress != null:
		second_runtime_ids_before_clear = state.get_active_runtime_ids(second_room_id)
		second_spawned_before_clear = state.get_spawned_enemy_count(second_room_id)
		second_defeated_before_clear = second_progress.defeated_count
	var first_spawned_before_clear := state.get_spawned_enemy_count(room_id)
	_expect(progress.enemy_ids.size() >= 25, "debug clear fixture did not contain at least twenty-five configured enemies")
	_expect(progress.next_spawn_index < progress.enemy_ids.size(), "debug clear fixture had no pending enemies")
	_expect(runtime_api.try_request_current_encounter_clear(), "active player room rejected a debug clear request")
	_expect(not runtime_api.try_request_current_encounter_clear(), "repeated debug clear request was accepted")
	_expect(coordinator._clear_requested_room_id == room_id, "debug clear request did not retain its originating room")
	runtime_api._encounter_coordinator = null
	runtime_api.free()
	coordinator.tick()
	_expect(progress.status == LevelEncounterState.RoomStatus.ACTIVE, "debug clear completed before pending enemies spawned")
	_expect(progress.active_entity_ids.is_empty(), "debug clear did not defeat the active room snapshot")
	_expect(state.get_spawned_enemy_count(room_id) == first_spawned_before_clear, "debug clear refilled in the request frame")
	coordinator.tick()
	_expect(state.get_spawned_enemy_count(room_id) == first_spawned_before_clear, "debug clear refilled twice in the request frame")
	_expect(progress.active_entity_ids.is_empty(), "same-frame debug clear tick spawned replacement enemies")
	await physics_frame
	coordinator.tick()
	_expect(state.get_spawned_enemy_count(room_id) > first_spawned_before_clear, "debug clear did not refill on the next physics frame")
	var clear_tick_count := 1
	var observed_clear_transition_start := false
	if progress.status == LevelEncounterState.RoomStatus.CLEARED:
		observed_clear_transition_start = true
	while state.get_active_room_ids().has(room_id) and clear_tick_count < LevelRoomEncounterDefinition.MAX_ENEMY_COUNT + 2:
		await physics_frame
		coordinator.tick()
		progress = _room_progress(state, room_id)
		if progress.status == LevelEncounterState.RoomStatus.CLEARED:
			observed_clear_transition_start = true
			_expect(
				visible_seal != null \
					and visible_seal.visible \
					and is_zero_approx(visible_seal.transparency) \
					and visible_seal.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"opening a visible seal did not disable its shadow before fading",
			)
			_expect_room_discovery_start(renderer, topology, state, torch_renderer, revealed_child_room_id)
		clear_tick_count += 1

	progress = _room_progress(state, room_id)
	_expect(progress.status == LevelEncounterState.RoomStatus.CLEARED, "room did not clear after every configured enemy died")
	_expect(not state.get_active_room_ids().has(room_id), "cleared room remained active")
	_expect(progress.next_spawn_index == progress.enemy_ids.size(), "room cleared before every configured enemy spawned")
	_expect(progress.defeated_count == progress.enemy_ids.size(), "room cleared before every configured enemy died")
	_expect(progress.active_entity_ids.is_empty(), "cleared room retained assigned runtime IDs")
	_expect(_cleared_room_ids == [room_id], "clear signal did not identify exactly the cleared room")
	_expect(observed_clear_transition_start, "room clearance did not expose the seal and branch transition start")
	_expect(second_progress != null and second_progress.status == LevelEncounterState.RoomStatus.ACTIVE, "clearing one room stopped the other wave")
	if second_progress != null:
		_expect(state.get_active_runtime_ids(second_room_id) == second_runtime_ids_before_clear, "debug clear defeated an unrelated concurrent room")
		_expect(state.get_spawned_enemy_count(second_room_id) == second_spawned_before_clear, "debug clear spawned enemies for an unrelated concurrent room")
		_expect(second_progress.defeated_count == second_defeated_before_clear, "debug clear advanced an unrelated concurrent room")
	_expect(not coordinator.try_request_current_encounter_clear(), "cleared encounter room accepted another clear request")
	var remaining_summary := state.get_summary()
	_expect(remaining_summary.active_wave_count == 1, "clearing one of two waves lost the remaining aggregate")
	_expect(
		(hud.get_node("Panel/Margin/Label") as Label).text == "1 wave  •  %d active  •  %d pending" % [remaining_summary.active_enemy_count, remaining_summary.pending_enemy_count],
		"room clear notice replaced an ongoing wave summary",
	)
	for door_id in room.door_ids:
		var doorway := _find_doorway(topology, door_id)
		if sealed_before_activation.has(door_id):
			_expect(not state.get_sealed_door_ids().has(door_id), "cleared room seal remained authoritative: %d" % door_id)
			for cell in doorway.aperture_cells:
				_expect(level_state.get_cell_value(cell) == StructureCell.AIR, "cleared seal did not restore AIR at %s" % cell)
				_expect(not level_state.is_solid(cell), "cleared seal still blocked movement at %s" % cell)
	for discovered_room_id in topology.get_discovered_room_ids_after_clear(room_id):
		var discovered_room := topology.get_room(discovered_room_id)
		if discovered_room.has_encounter():
			_expect(_room_progress(state, discovered_room_id).status == LevelEncounterState.RoomStatus.READY, "cleared room did not ready downstream encounter %d" % discovered_room_id)
			_expect(not state.get_sealed_door_ids().has(discovered_room.parent_door_id), "cleared room did not open downstream encounter seal %d" % discovered_room.parent_door_id)
		else:
			_expect(not state._rooms.has(discovered_room_id), "cleared room created wave progress for passive room %d" % discovered_room_id)
			for door_id in discovered_room.door_ids:
				_expect(not state.get_sealed_door_ids().has(door_id), "passive room doorway became sealed: %d" % door_id)
	await create_timer(LevelGeometryRenderer.TRANSITION_SECONDS * 0.35).timeout
	_expect(
		visible_seal != null \
			and visible_seal.visible \
			and visible_seal.transparency > 0.0 \
			and visible_seal.transparency < 1.0 \
			and visible_seal.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"opened seal did not fade without casting shadows",
	)
	_expect_room_discovery_midpoint(renderer, topology, state, torch_renderer, revealed_child_room_id)
	await create_timer(LevelGeometryRenderer.TRANSITION_SECONDS + 0.05).timeout
	_expect(
		visible_seal != null \
			and not visible_seal.visible \
			and is_equal_approx(visible_seal.transparency, 1.0) \
			and visible_seal.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"opened seal did not finish hidden and non-shadowing",
	)
	_expect_room_discovery_complete(renderer, topology, state, torch_renderer, revealed_child_room_id)
	for torch_cell in renderer._room_torch_cells[revealed_child_room_id] as Array[Vector3i]:
		_expect_torch_state(torch_renderer, torch_cell, 1.0, "unlocked child branch")
	if gate_path.size() == 2:
		var start_cell := gate_path[0]
		var goal_cell := gate_path[1]
		var reopened_path := VoxelPathfinder.find_path(level_state, start_cell, goal_cell, player.player_width, player.player_height, 8, 512)
		_expect(reopened_path.status == VoxelPathResult.Status.FOUND, "pathfinding did not traverse the cleared incoming gate")
		var ray_origin := Vector3(start_cell) + Vector3(0.5, player.player_height * 0.5, 0.5)
		var ray_target := Vector3(goal_cell) + Vector3(0.5, player.player_height * 0.5, 0.5)
		_expect(VoxelLineOfSight.has_clear_path(level_state, ray_origin, ray_target), "line of sight did not reopen through the cleared incoming gate")
		_expect(not VoxelBodySolver.collides_at(level_state, _aperture_body_position(parent_doorway), player.player_width, player.player_height, false), "player body still collided with the cleared gate")
	if second_progress != null and second_room_position is Vector3:
		player.global_position = second_room_position as Vector3
		_expect(coordinator.try_request_current_encounter_clear(), "second active room rejected a retained shutdown request")
		_expect(coordinator._clear_requested_room_id == second_room_id, "second room clear request was not retained before shutdown")

	await _cleanup(runtime, coordinator, renderer, torch_renderer, hud, player)
	_finish()

func _find_ready_root_with_child(topology: LevelEncounterTopology, state: LevelEncounterState) -> int:
	for room_id in topology.get_encounter_room_ids():
		if state.can_activate(room_id) and not topology.get_discovered_room_ids_after_clear(room_id).is_empty():
			return room_id
	return -1

func _find_highest_capacity_ready_root(
	topology: LevelEncounterTopology,
	state: LevelEncounterState,
	capacity_by_room: Dictionary,
	excluded_room_id: int,
) -> int:
	var selected_room_id := -1
	var selected_capacity := -1
	for room_id in topology.get_encounter_room_ids():
		if room_id != excluded_room_id and state.can_activate(room_id):
			var capacity := int(capacity_by_room.get(room_id, 0))
			if capacity > selected_capacity:
				selected_room_id = room_id
				selected_capacity = capacity
	return selected_room_id

func _find_passive_room_position(
	topology: LevelEncounterTopology,
	body_width: float,
	body_height: float,
) -> Variant:
	for room_id in topology.get_room_ids():
		var room := topology.get_room(room_id)
		if room.has_encounter():
			continue
		var interior_cells: Array = room._interior_cells.keys()
		interior_cells.sort_custom(_cell_less)
		for value in interior_cells:
			var position := Vector3(value as Vector3i) + Vector3(0.5, 0.0, 0.5)
			if room.contains_body(position, body_width, body_height, topology.get_doorways()):
				return position
	return null

func _move_active_waves_into_room(
	runtime: EntityRuntime,
	state: LevelEncounterState,
	source_room_ids: Array[int],
	target_room_id: int,
	topology: LevelEncounterTopology,
	level_state: LevelState,
	entity_definition: EntityDefinition,
) -> int:
	var target_room := topology.get_room(target_room_id)
	var target_positions: Array[Vector3] = []
	var interior_cells: Array = target_room._interior_cells.keys()
	interior_cells.sort_custom(_cell_less)
	for value in interior_cells:
		var position := Vector3(value as Vector3i) + Vector3(0.5, 0.0, 0.5)
		if EntitySpawnGeometryType.can_spawn(level_state, entity_definition, position) \
			and target_room.contains_body(position, entity_definition.body_width, entity_definition.body_height, topology.get_doorways()):
			target_positions.append(position)
	if target_positions.is_empty():
		return 0
	var moved_count := 0
	for source_room_id in source_room_ids:
		var runtime_ids: Array = _room_progress(state, source_room_id).active_entity_ids.keys()
		runtime_ids.sort()
		for value in runtime_ids:
			var actor := runtime.get_actor(int(value))
			if actor == null:
				continue
			actor.global_position = target_positions[moved_count % target_positions.size()]
			if topology.find_room_containing_body(actor.global_position, entity_definition.body_width, entity_definition.body_height) == target_room_id:
				moved_count += 1
	return moved_count

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
	runtime.setup(entity_catalog, level_state, 64, 64, EntityNavigationLimits.new(48, 2048, 2), EntityRuntime.Mode.GAMEPLAY)
	_expect(coordinator.setup(topology, state, level_state, runtime, entity_catalog, layout.seed_value), "production room-cap coordinator setup failed")
	var master_room_id := -1
	for room_id in topology.get_encounter_room_ids():
		var capacity := int(coordinator._capacity_by_room[room_id])
		_expect(capacity <= LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM, "production room capacity exceeded twenty: %d" % room_id)
		if state.get_configured_enemy_ids(room_id).size() == 40:
			master_room_id = room_id
			_expect(capacity == LevelEncounterState.MAX_CONCURRENT_ENEMIES_PER_ROOM, "production master room did not expose twenty concurrent slots")
	_expect(master_room_id >= 0, "production topology has no forty-enemy master room")
	for room_id in topology.get_room_ids():
		if topology.get_room(room_id).has_encounter():
			continue
		_expect(not coordinator._spawn_cells_by_room.has(room_id), "coordinator retained passive-room spawn cells: %d" % room_id)
		_expect(not coordinator._capacity_by_room.has(room_id), "coordinator retained passive-room capacity: %d" % room_id)
		_expect(not state._rooms.has(room_id), "encounter state retained passive-room wave progress: %d" % room_id)
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

func _find_sealed_door_for_room(room: LevelEncounterRoom, sealed_door_ids: Array[int]) -> int:
	for door_id in room.door_ids:
		if sealed_door_ids.has(door_id):
			return door_id
	return -1

func _expect_initial_geometry_state(
	renderer: LevelGeometryRenderer,
	topology: LevelEncounterTopology,
	state: LevelEncounterState,
	torch_renderer: TorchRenderer,
	texture_set: BlockTextureSet,
) -> void:
	var terrain_material := _shared_terrain_material(renderer)
	_expect(terrain_material != null, "geometry renderer did not retain one shared terrain material")
	if terrain_material == null:
		return
	_expect(terrain_material.shader != null and terrain_material.shader.resource_path == "res://levels/presentation/level_terrain.gdshader", "geometry renderer did not use the level terrain shader")
	_expect(terrain_material.get_shader_parameter("terrain_textures") == texture_set.texture_array, "geometry renderer did not bind the terrain texture array")
	var entry_mesh := renderer.get_node_or_null("EntryGeometry") as MeshInstance3D
	_expect(
		entry_mesh != null \
			and entry_mesh.visible \
			and is_zero_approx(entry_mesh.transparency) \
			and entry_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
			and entry_mesh.material_override == terrain_material,
		"entry geometry did not use the opaque shared terrain presentation",
	)
	var discovered_room_ids := state.get_discovered_room_ids()
	var sealed_door_ids := state.get_sealed_door_ids()
	for room_id in topology.get_room_ids():
		var discovered := discovered_room_ids.has(room_id)
		var room_mesh := renderer._room_meshes.get(room_id) as MeshInstance3D
		_expect(room_mesh != null and room_mesh.material_override == terrain_material, "room %d did not use the shared terrain material" % room_id)
		if room_mesh != null:
			_expect(room_mesh.visible == discovered, "room %d visibility did not match discovery" % room_id)
			_expect(is_equal_approx(room_mesh.transparency, 0.0 if discovered else 1.0), "room %d transparency did not match discovery" % room_id)
			_expect(
				room_mesh.cast_shadow == (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if discovered else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF),
				"room %d shadow state did not match discovery" % room_id,
			)
		for torch_cell in renderer._room_torch_cells[room_id] as Array[Vector3i]:
			_expect_torch_state(torch_renderer, torch_cell, 1.0 if discovered else 0.0, "room %d" % room_id)
	for doorway in topology.get_doorways():
		var seal := renderer._seal_meshes.get(doorway.door_id) as MeshInstance3D
		var owner_discovered := discovered_room_ids.has(doorway.room_id)
		var expected_visible := sealed_door_ids.has(doorway.door_id) and owner_discovered
		_expect(seal != null and seal.material_override == terrain_material, "seal %d did not use the authored shared terrain material" % doorway.door_id)
		_expect_seal_mesh_faces_room(seal, doorway, texture_set)
		if seal != null:
			_expect(seal.visible == expected_visible, "seal %d visibility ignored its seal or discovery state" % doorway.door_id)
			_expect(is_equal_approx(seal.transparency, 0.0 if expected_visible else 1.0), "seal %d transparency ignored its seal or discovery state" % doorway.door_id)
			_expect(
				seal.cast_shadow == (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if expected_visible else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF),
				"seal %d shadow state ignored its seal or discovery state" % doorway.door_id,
			)

func _expect_room_discovery_start(
	renderer: LevelGeometryRenderer,
	topology: LevelEncounterTopology,
	state: LevelEncounterState,
	torch_renderer: TorchRenderer,
	room_id: int,
) -> void:
	var room_mesh := renderer._room_meshes.get(room_id) as MeshInstance3D
	_expect(
		room_mesh != null \
			and room_mesh.visible \
			and is_equal_approx(room_mesh.transparency, 1.0) \
			and room_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"discovered branch did not start fully transparent and non-shadowing",
	)
	for torch_cell in renderer._room_torch_cells[room_id] as Array[Vector3i]:
		_expect_torch_state(torch_renderer, torch_cell, 0.0, "discovered branch fade start")
	_expect_owned_seals(renderer, topology, state, room_id, 1.0, false)

func _expect_room_discovery_midpoint(
	renderer: LevelGeometryRenderer,
	topology: LevelEncounterTopology,
	state: LevelEncounterState,
	torch_renderer: TorchRenderer,
	room_id: int,
) -> void:
	var room_mesh := renderer._room_meshes.get(room_id) as MeshInstance3D
	_expect(
		room_mesh != null \
			and room_mesh.visible \
			and room_mesh.transparency > 0.0 \
			and room_mesh.transparency < 1.0 \
			and room_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"discovered branch did not fade in without casting shadows",
	)
	for torch_cell in renderer._room_torch_cells[room_id] as Array[Vector3i]:
		var strength := _torch_reveal_strength(torch_renderer, torch_cell)
		_expect(strength > 0.0 and strength < 1.0, "discovered branch torch did not fade in")
		_expect_torch_light_state(torch_renderer, torch_cell, true, "discovered branch fade")
	_expect_owned_seals(renderer, topology, state, room_id, room_mesh.transparency, false)

func _expect_room_discovery_complete(
	renderer: LevelGeometryRenderer,
	topology: LevelEncounterTopology,
	state: LevelEncounterState,
	torch_renderer: TorchRenderer,
	room_id: int,
) -> void:
	var room_mesh := renderer._room_meshes.get(room_id) as MeshInstance3D
	_expect(
		room_mesh != null \
			and room_mesh.visible \
			and is_zero_approx(room_mesh.transparency) \
			and room_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"discovered branch did not finish opaque, visible, and shadow-casting",
	)
	for torch_cell in renderer._room_torch_cells[room_id] as Array[Vector3i]:
		_expect_torch_state(torch_renderer, torch_cell, 1.0, "discovered branch fade completion")
	_expect_owned_seals(renderer, topology, state, room_id, 0.0, true)

func _expect_owned_seals(
	renderer: LevelGeometryRenderer,
	topology: LevelEncounterTopology,
	state: LevelEncounterState,
	room_id: int,
	visible_transparency: float,
	visible_casts_shadow: bool,
) -> void:
	var sealed_door_ids := state.get_sealed_door_ids()
	for doorway in topology.get_doorways():
		if doorway.room_id != room_id:
			continue
		var seal := renderer._seal_meshes.get(doorway.door_id) as MeshInstance3D
		var remains_sealed := sealed_door_ids.has(doorway.door_id)
		_expect(seal != null and seal.material_override == _shared_terrain_material(renderer), "room %d seal %d lost the shared terrain material" % [room_id, doorway.door_id])
		if seal == null:
			continue
		if remains_sealed:
			_expect(seal.visible and is_equal_approx(seal.transparency, visible_transparency), "room %d sealed wall %d did not follow branch visibility" % [room_id, doorway.door_id])
			_expect(
				seal.cast_shadow == (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if visible_casts_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF),
				"room %d sealed wall %d used the wrong shadow state" % [room_id, doorway.door_id],
			)
		else:
			_expect(
				not seal.visible \
					and is_equal_approx(seal.transparency, 1.0) \
					and seal.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"room %d opened incoming seal %d became visible during discovery" % [room_id, doorway.door_id],
			)

func _expect_torch_state(renderer: TorchRenderer, cell: Vector3i, expected_strength: float, context: String) -> void:
	var root_node := renderer.torch_instances.get(cell) as Node3D
	_expect(root_node != null, "%s omitted torch %s" % [context, cell])
	if root_node == null:
		return
	var stem := root_node.get_node("Stem") as MeshInstance3D
	var flame := root_node.get_node("Flame") as MeshInstance3D
	var visible := expected_strength > 0.0
	_expect(stem.visible == visible and is_equal_approx(stem.transparency, 1.0 - expected_strength), "%s torch %s stem visibility was incorrect" % [context, cell])
	_expect(flame.visible == visible and is_equal_approx(flame.transparency, 1.0 - expected_strength), "%s torch %s flame visibility was incorrect" % [context, cell])
	_expect_torch_light_state(renderer, cell, visible, context)

func _expect_torch_light_state(renderer: TorchRenderer, cell: Vector3i, expected_visible: bool, context: String) -> void:
	var light := renderer.torch_light_nodes.get(cell) as OmniLight3D
	_expect(light != null, "%s omitted torch light %s" % [context, cell])
	if light == null:
		return
	_expect(light.visible == expected_visible, "%s torch light %s visibility was incorrect" % [context, cell])
	_expect((light.light_energy > 0.0) == expected_visible, "%s torch light %s energy was incorrect" % [context, cell])
	_expect(not light.shadow_enabled, "%s torch light %s cast a shadow" % [context, cell])

func _expect_seal_mesh_faces_room(seal: MeshInstance3D, doorway: LevelDoorway, texture_set: BlockTextureSet) -> void:
	var mesh := seal.mesh as ArrayMesh if seal != null else null
	_expect(mesh != null and mesh.get_surface_count() == 1, "seal %d did not retain one mesh surface" % doorway.door_id)
	if mesh == null or mesh.get_surface_count() != 1:
		return
	var arrays := mesh.surface_get_arrays(0)
	var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var texture_layers := arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array
	var face_count := doorway.aperture_cells.size()
	var inward_normal := Vector3(-LevelSocketDefinition.vector_for(doorway.direction))
	_expect(normals.size() == face_count * 4, "seal %d rendered more than one face per aperture cell" % doorway.door_id)
	_expect(indices.size() == face_count * 6, "seal %d retained non-room-facing triangles" % doorway.door_id)
	_expect(texture_layers.size() == normals.size(), "seal %d texture-layer count did not match its vertices" % doorway.door_id)
	var faces_room := true
	for normal in normals:
		if normal.dot(inward_normal) <= 0.9999:
			faces_room = false
			break
	_expect(faces_room, "seal %d exposed a face toward its hidden hallway" % doorway.door_id)
	var expected_layer := int(texture_set.side_layers[doorway.fill_block_id])
	var uses_authored_texture := true
	for layer in texture_layers:
		if roundi(layer.x) != expected_layer or not is_zero_approx(layer.y):
			uses_authored_texture = false
			break
	_expect(uses_authored_texture, "seal %d did not retain its authored fill-block side texture" % doorway.door_id)

func _shared_terrain_material(renderer: LevelGeometryRenderer) -> ShaderMaterial:
	var entry_mesh := renderer.get_node_or_null("EntryGeometry") as MeshInstance3D
	return entry_mesh.material_override as ShaderMaterial if entry_mesh != null else null

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

func _on_summary_changed(summary: LevelEncounterSummary) -> void:
	_summary_events.append(summary)

func _on_room_cleared(room_id: int) -> void:
	_cleared_room_ids.append(room_id)

func _cleanup(
	runtime: EntityRuntime,
	coordinator: LevelEncounterCoordinator,
	renderer: LevelGeometryRenderer,
	torch_renderer: TorchRenderer,
	hud: LevelEncounterHUD,
	player: PlayerMotor,
) -> void:
	coordinator.shutdown()
	_expect(coordinator._clear_requested_room_id == -1, "encounter shutdown retained a debug clear request")
	runtime.shutdown()
	coordinator.queue_free()
	renderer.queue_free()
	torch_renderer.queue_free()
	hud.queue_free()
	player.queue_free()
	runtime.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
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
		print("LEVEL_ENCOUNTER_RUNTIME PASS assertions=%d summary_events=%d" % [_assertions, _summary_events.size()])
		quit(0)
	else:
		print("LEVEL_ENCOUNTER_RUNTIME FAILED failures=%d assertions=%d" % [_failures, _assertions])
		quit(1)
