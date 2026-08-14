extends SceneTree

const FLAT_HEIGHT: int = 6
const FEET_Y: float = float(FLAT_HEIGHT + 1)
const TEST_RADIUS: int = 64
const GRASS_SLOT: int = 1

var _failures: int = 0
var _world: VoxelWorld
var _inventory: InventoryModel
var _player: PlayerMotor
var _camera: Camera3D
var _interactor: PlayerInteractor
var _input_buffer: InputBuffer
var _coordinator: EntityCoordinator
var _combat: MeleeCombatCoordinator
var _block_placed_count: int = 0
var _world_place_count: int = 0

func _init() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[entity_placement_integration] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-TEST_RADIUS, TEST_RADIUS + 1):
		for z in range(-TEST_RADIUS, TEST_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLAT_HEIGHT
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _make_one_zombie_catalog() -> EntityCatalog:
	var source := load("res://entities/definitions/zombie.tres") as EntityDefinition
	var definition := source.duplicate(true) as EntityDefinition
	definition.max_active = 1
	var definitions: Array[EntityDefinition] = [definition]
	var catalog := EntityCatalog.new()
	catalog.definitions = definitions
	return catalog

func _always_ready(_position: Vector3) -> bool:
	return true

func _index_actor(actor: EntityActor) -> void:
	_coordinator._spatial_index.upsert(actor.runtime_id, actor.global_position, actor.get_world_bounds())

func _grass_count() -> int:
	var stack := _inventory.get_slot(GRASS_SLOT)
	return stack.count if stack != null else 0

func _snapshot(position: Vector3i) -> Dictionary:
	return {
		"block_id": _world.get_block_id_at(position),
		"grass_count": _grass_count(),
		"edit_count": _world.get_block_edit_count(),
		"block_placed_count": _block_placed_count,
		"world_place_count": _world_place_count,
	}

func _expect_unchanged(position: Vector3i, snapshot: Dictionary, context: String) -> void:
	_expect(_world.get_block_id_at(position) == int(snapshot["block_id"]), "%s changed the target block" % context)
	_expect(_grass_count() == int(snapshot["grass_count"]), "%s changed inventory" % context)
	_expect(_world.get_block_edit_count() == int(snapshot["edit_count"]), "%s changed world edits" % context)
	_expect(_block_placed_count == int(snapshot["block_placed_count"]), "%s emitted block_placed" % context)
	_expect(_world_place_count == int(snapshot["world_place_count"]), "%s emitted a world placement" % context)

func _on_block_placed() -> void:
	_block_placed_count += 1

func _on_block_edit(edit: BlockEdit) -> void:
	if edit.is_success() and not edit.is_mine():
		_world_place_count += 1

func _aim_at_placement(position: Vector3i) -> void:
	var target := Vector3(float(position.x) + 0.5, float(position.y) - 0.5, float(position.z) + 0.5)
	var camera_position := Vector3(float(position.x) + 0.5, float(position.y) + 3.0, float(position.z) + 1.0)
	_camera.fov = 1.0
	_camera.look_at_from_position(camera_position, target)

func _run() -> void:
	_world = _make_world()
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	_inventory = InventoryModel.new(item_catalog)
	_inventory.setup_starter()
	_inventory.select_slot(GRASS_SLOT)
	_input_buffer = InputBuffer.new()

	_player = (load("res://player/player.tscn") as PackedScene).instantiate() as PlayerMotor
	_camera = Camera3D.new()
	_coordinator = EntityCoordinator.new()
	_combat = MeleeCombatCoordinator.new()
	get_root().add_child(_player)
	get_root().add_child(_camera)
	get_root().add_child(_coordinator)
	get_root().add_child(_combat)
	_player.global_position = Vector3(0.5, FEET_Y, 4.5)
	_player.set_physics_process(false)
	_camera.current = true
	await process_frame

	_interactor = _player.interactor
	_interactor.set_physics_process(false)
	_player.animation_driver.set_process(false)
	_coordinator.setup(_make_one_zombie_catalog(), _world, 1337, _always_ready)
	var player_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	_combat.setup(_world, _player, player_stats, _coordinator)
	_interactor.setup(_camera, _player, _inventory, _input_buffer, _combat, _coordinator)
	_interactor.bind_space(_world, _world)
	_interactor.block_placed.connect(_on_block_placed)
	_world.block_edit_committed.connect(_on_block_edit)
	_coordinator.tick(EntityCoordinator.SPAWN_INTERVAL_SECONDS, _player.global_position, 20.0)
	var actors := _coordinator.get_active_actors()
	_expect(actors.size() == 1, "coordinator did not spawn exactly one zombie")
	if actors.size() != 1:
		await _cleanup()
		_finish()
		return

	var zombie := actors[0]
	var target_a := Vector3i(0, int(FEET_Y), 0)
	var target_b := Vector3i(1, int(FEET_Y), 0)
	var target_c := Vector3i(2, int(FEET_Y), 0)
	var out_of_reach := Vector3i(20, int(FEET_Y), 0)
	var grass_action := _interactor.get_selected_placement_action()
	var initial_grass_count := _grass_count()

	zombie.global_position = Vector3(0.5, FEET_Y, 0.5)
	_index_actor(zombie)
	_aim_at_placement(target_a)
	await process_frame
	_interactor._handle_raycast()
	_expect(_interactor.target_has and _interactor.placement_block == target_a, "camera preview did not resolve the expected placement cell")
	_expect(not _interactor.placement_has and not _interactor.can_place_target, "preview accepted a block overlapping the zombie")
	_expect(_interactor._placement_collides_entity(target_a), "preview overlap query missed the zombie")
	var rejected_overlap := _snapshot(target_a)
	_interactor._commit_place(target_a, grass_action)
	_expect_unchanged(target_a, rejected_overlap, "direct entity-overlap rejection")

	zombie.global_position = Vector3(6.5, FEET_Y, 0.5)
	_index_actor(zombie)
	_interactor._handle_raycast()
	_expect(_interactor.placement_has and _interactor.can_place_target, "moving the zombie away did not permit the preview")
	_expect(_interactor.placement_block == target_a, "move-away preview changed placement cells")
	var before_move_success := _grass_count()
	var signals_before_move_success := _block_placed_count
	var world_signals_before_move_success := _world_place_count
	_interactor._commit_place(target_a, grass_action)
	_expect(_world.get_block_id_at(target_a) == BlockId.Type.GRASS, "move-away placement did not commit")
	_expect(_grass_count() == before_move_success - 1, "move-away placement did not consume exactly one item")
	_expect(_block_placed_count == signals_before_move_success + 1, "move-away placement did not emit block_placed exactly once")
	_expect(_world_place_count == world_signals_before_move_success + 1, "move-away placement did not emit one world edit")

	_aim_at_placement(target_b)
	await process_frame
	_interactor._handle_raycast()
	_expect(_interactor.placement_has and _interactor.can_place_target and _interactor.placement_block == target_b, "race setup did not produce a valid preview")
	zombie.global_position = Vector3(1.5, FEET_Y, 0.5)
	_index_actor(zombie)
	var moved_after_preview := _snapshot(target_b)
	_interactor._commit_place(target_b, grass_action)
	_expect_unchanged(target_b, moved_after_preview, "entity movement after preview")

	zombie.global_position = Vector3(EntityCoordinator.DESPAWN_DISTANCE + 1.0, FEET_Y, 0.5)
	_coordinator.tick(0.0, _player.global_position, 20.0)
	_expect(_coordinator.get_active_count() == 0, "despawn retained the zombie")
	_expect(_coordinator._spatial_index.get_entry_count() == 0, "despawn retained a spatial entry")
	_expect(_coordinator._spatial_index.get_cell_count() == 0, "despawn retained spatial cells")
	_expect(not _coordinator.has_entity_overlap(AABB(Vector3(target_b), Vector3.ONE)), "despawn retained an overlap query result")
	var before_despawn_success := _grass_count()
	var signals_before_despawn_success := _block_placed_count
	var world_signals_before_despawn_success := _world_place_count
	_interactor._commit_place(target_b, grass_action)
	_expect(_world.get_block_id_at(target_b) == BlockId.Type.GRASS, "despawn did not permit placement")
	_expect(_grass_count() == before_despawn_success - 1, "post-despawn placement did not consume exactly one item")
	_expect(_block_placed_count == signals_before_despawn_success + 1, "post-despawn placement did not emit block_placed exactly once")
	_expect(_world_place_count == world_signals_before_despawn_success + 1, "post-despawn placement did not emit one world edit")

	var occupied_snapshot := _snapshot(target_a)
	_interactor._commit_place(target_a, grass_action)
	_expect_unchanged(target_a, occupied_snapshot, "occupied-cell validation")

	var reach_snapshot := _snapshot(out_of_reach)
	_interactor._commit_place(out_of_reach, grass_action)
	_expect_unchanged(out_of_reach, reach_snapshot, "out-of-reach validation")

	var selected_snapshot := _snapshot(target_c)
	_inventory.select_slot(0)
	_interactor._commit_place(target_c, grass_action)
	_expect_unchanged(target_c, selected_snapshot, "selected-item-changed validation")
	_inventory.select_slot(GRASS_SLOT)

	var stale_action_snapshot := _snapshot(target_c)
	_interactor._commit_place(target_c, null)
	_expect_unchanged(target_c, stale_action_snapshot, "stale-action validation")

	_aim_at_placement(target_c)
	await process_frame
	_interactor._handle_raycast()
	_expect(_interactor.placement_has and _interactor.can_place_target and _interactor.placement_block == target_c, "stale-preview setup was not valid")
	_interactor.placement_has = false
	_interactor.secondary_use_timer = 0.0
	_input_buffer.secondary_use_just = true
	var stale_preview_snapshot := _snapshot(target_c)
	_interactor._handle_item_actions(0.0)
	_expect_unchanged(target_c, stale_preview_snapshot, "stale-preview validation")

	_expect(_grass_count() == initial_grass_count - 2, "rejected placements consumed inventory")
	_expect(_block_placed_count == 2 and _world_place_count == 2, "successful placements did not emit exactly once each")
	await _cleanup()
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "cleanup ended with %d orphan nodes" % orphan_count)
	_finish(orphan_count)

func _cleanup() -> void:
	_combat.shutdown()
	_coordinator.shutdown()
	for node in [_combat, _coordinator, _camera, _player]:
		if is_instance_valid(node):
			node.queue_free()
	await process_frame
	await process_frame

func _finish(orphan_count: int = -1) -> void:
	if _failures == 0:
		print("ENTITY_PLACEMENT_INTEGRATION PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("ENTITY_PLACEMENT_INTEGRATION FAIL failures=%d" % _failures)
		quit(1)
