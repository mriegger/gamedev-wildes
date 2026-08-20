extends SceneTree

var _errors: Array[String] = []
var _state_changed_count: int = 0
var _harvest_completed_count: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var pumpkin_item := item_catalog.get_definition(&"pumpkin")
	_expect(pumpkin_item.display_name == "Pumpkin", "pumpkin display name mismatch")
	_expect(pumpkin_item.max_stack == 20, "pumpkin stack limit mismatch")
	_expect(pumpkin_item.icon != null and pumpkin_item.icon.resource_path == "res://assets/textures/items/pumpkin.png", "pumpkin icon mismatch")
	_expect(pumpkin_item.icon.get_size() == Vector2(64.0, 64.0), "pumpkin icon dimensions mismatch")
	var voxel_world := _flat_world(block_catalog, BlockId.Type.GRASS)
	var player := Node3D.new()
	player.position = Vector3(0.5, 1.0, 0.5)
	root.add_child(player)
	var pumpkin_patch := _new_pumpkin_patch()
	root.add_child(pumpkin_patch)
	_expect(pumpkin_patch.setup(voxel_world, player, 17391, null), "new world did not generate a pumpkin patch")
	_expect(pumpkin_patch.has_patch(), "generated pumpkin patch did not own persistent state")
	var generated_snapshot := pumpkin_patch.snapshot()
	_expect(generated_snapshot.get("present", false), "generated snapshot was absent")
	_expect(generated_snapshot.get("version", 0) == PumpkinPatchState.SNAPSHOT_VERSION, "generated snapshot version mismatch")
	_expect(_find_state_index(generated_snapshot, &"empty") == -1, "new patch generated an empty tile")
	_expect(_count_state(generated_snapshot, &"crop") >= 3, "new patch generated fewer than three harvestable pumpkins")
	var origin := generated_snapshot.get("origin", []) as Array
	if origin.size() == 3:
		var patch_center := Vector2(float(origin[0]) + float(PumpkinPatchCoordinator.PATCH_WIDTH) * 0.5, float(origin[2]) + float(PumpkinPatchCoordinator.PATCH_DEPTH) * 0.5)
		var player_center := Vector2(player.position.x, player.position.z)
		_expect(patch_center.distance_squared_to(player_center) >= PumpkinPatchCoordinator.MIN_PLAYER_DISTANCE_SQUARED, "pumpkin patch spawned inside the minimum discovery distance")
		_expect(absi(int(origin[0]) - floori(player.position.x)) <= PumpkinPatchCoordinator.SEARCH_RADIUS, "pumpkin patch spawned beyond the configured X range")
		_expect(absi(int(origin[2]) - floori(player.position.z)) <= PumpkinPatchCoordinator.SEARCH_RADIUS, "pumpkin patch spawned beyond the configured Z range")
	else:
		_expect(false, "generated snapshot omitted its origin")
	_validate_patch_presentation(pumpkin_patch)
	_validate_cleared_foliage_footprint(voxel_world, generated_snapshot, "empty generation")

	var dense_foliage_world := _flat_world(block_catalog, BlockId.Type.GRASS)
	_fill_with_foliage(dense_foliage_world)
	var dense_foliage_patch := _new_pumpkin_patch()
	root.add_child(dense_foliage_patch)
	_expect(dense_foliage_patch.setup(dense_foliage_world, player, 17391, null), "dense foliage prevented new pumpkin patch placement")
	_validate_cleared_foliage_footprint(dense_foliage_world, dense_foliage_patch.snapshot(), "generated")
	var restored_foliage_world := _flat_world(block_catalog, BlockId.Type.GRASS)
	_fill_with_foliage(restored_foliage_world)
	var restored_foliage_patch := _new_pumpkin_patch()
	root.add_child(restored_foliage_patch)
	_expect(restored_foliage_patch.setup(restored_foliage_world, player, 17391, generated_snapshot), "saved pumpkin patch did not clear regenerated foliage")
	_validate_cleared_foliage_footprint(restored_foliage_world, restored_foliage_patch.snapshot(), "restored")
	var deferred_foliage_world := _flat_world(block_catalog, BlockId.Type.GRASS)
	var deferred_foliage_patch := _new_pumpkin_patch()
	root.add_child(deferred_foliage_patch)
	_expect(deferred_foliage_patch.setup(deferred_foliage_world, player, 17391, generated_snapshot), "unloaded saved patch did not reserve its footprint")
	_validate_cleared_foliage_footprint(deferred_foliage_world, deferred_foliage_patch.snapshot(), "deferred")
	_fill_snapshot_footprint_with_foliage(deferred_foliage_world, deferred_foliage_patch.snapshot())
	_validate_cleared_foliage_footprint(deferred_foliage_world, deferred_foliage_patch.snapshot(), "streamed")
	var saved_origin := generated_snapshot.get("origin", []) as Array
	if saved_origin.size() == 3:
		var occupied_world := _flat_world(block_catalog, BlockId.Type.GRASS)
		var occupied_position := Vector3i(int(saved_origin[0]), int(saved_origin[1]) + 1, int(saved_origin[2]))
		_expect(VoxelWorldTestFixture.commit_place(occupied_world, occupied_position, BlockId.Type.STONE) != null, "saved-patch fixture could not place a player block")
		var occupied_patch := _new_pumpkin_patch()
		root.add_child(occupied_patch)
		_expect(occupied_patch.setup(occupied_world, player, 17391, generated_snapshot), "saved patch rejected a player-built footprint block")
		_expect(occupied_world.get_block_id_at(occupied_position) == BlockId.Type.STONE, "saved patch cleared a player-built footprint block")
		_expect(occupied_world.is_foliage_clearance_reserved(occupied_position), "saved patch omitted clearance beneath the player block")
		var occupied_edits := occupied_world.snapshot_block_edits()
		_expect((occupied_edits["placed"] as Dictionary).has(occupied_position), "saved patch lost the player block edit")
		_expect(not (occupied_edits["removed"] as Dictionary).has(occupied_position), "saved patch persisted a removal beneath the player block")
		occupied_patch.queue_free()

	var hud := (load("res://ui/hud/hud.tscn") as PackedScene).instantiate() as HUD
	root.add_child(hud)
	await process_frame
	var prompt_coordinator := InteractionPromptCoordinator.new()
	prompt_coordinator.setup(hud, Callable(self, "_is_interaction_blocked"))
	prompt_coordinator.set_level_prompt("F  Enter Dungeon")
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	var inventory_loadout := InventoryTestFixture.create_loadout(inventory)
	var harvest := HarvestCoordinator.new()
	var harvest_sources: Array[HarvestSource] = [pumpkin_patch]
	_expect(harvest.setup(harvest_sources, inventory, inventory_loadout, prompt_coordinator), "pumpkin harvest setup rejected valid content")
	harvest.harvest_completed.connect(_on_harvest_completed)
	var crop_index := _find_state_index(generated_snapshot, &"crop")
	_expect(crop_index >= 0, "generated patch omitted a mature crop")
	if crop_index >= 0:
		_target_tile(harvest, pumpkin_patch, crop_index)
		_expect(harvest.has_target(), "mature pumpkin ray did not produce a harvest target")
		_expect(harvest.can_harvest_target(), "mature pumpkin was not harvestable with inventory capacity")
		_expect(hud.interaction_prompt.visible and hud.interaction_prompt.text == pumpkin_patch.get_harvest_prompt(), "harvest prompt did not override the level prompt")
		pumpkin_patch.state_changed.connect(_on_state_changed)
		var harvest_input := InputBuffer.new()
		var harvest_interactor := PlayerInteractor.new()
		harvest_interactor.inventory_model = inventory
		harvest_interactor.inventory_loadout = inventory_loadout
		harvest_interactor._input_buffer = harvest_input
		harvest_interactor.harvest = harvest
		harvest_input.primary_use_just = true
		harvest_input.primary_use_pressed = true
		harvest_interactor._handle_item_actions(0.0)
		_expect(not harvest_input.primary_use_just, "harvest click remained available to another primary action")
		_expect(harvest_interactor._primary_harvest_latched, "harvest did not latch the held mouse press")
		_expect(inventory.get_inventory_item_count(&"pumpkin") == 1, "pumpkin harvest did not add exactly one item")
		_expect(_state_changed_count == 1, "pumpkin harvest did not announce its persistent state change")
		_expect(_harvest_completed_count == 1, "pumpkin harvest did not announce its completed transaction")
		_expect(not harvest.has_target(), "successful harvest retained a stale target")
		_expect(hud.interaction_prompt.visible and hud.interaction_prompt.text == "F  Enter Dungeon", "level prompt did not return after harvest")
		var harvested_snapshot := pumpkin_patch.snapshot()
		_expect((harvested_snapshot["growth_state_ids"] as Array)[crop_index] == "empty", "harvest did not transition the crop state to empty")
		var emptied_holder := pumpkin_patch.get_node("PumpkinPatch/State%02d" % (crop_index + 1)) as Node3D
		_expect(emptied_holder.get_child_count() == 0, "harvested tile retained a plant model")
		var harvested_restore := _new_pumpkin_patch()
		root.add_child(harvested_restore)
		_expect(harvested_restore.setup(voxel_world, player, 17391, harvested_snapshot), "harvested pumpkin state did not restore")
		_expect(harvested_restore.snapshot() == harvested_snapshot, "harvested pumpkin changed during save round trip")
		_expect(not harvested_restore.can_harvest_tile(crop_index), "restored empty tile remained harvestable")
		var restored_empty_holder := harvested_restore.get_node("PumpkinPatch/State%02d" % (crop_index + 1)) as Node3D
		_expect(restored_empty_holder.get_child_count() == 0, "restored empty tile gained a plant model")
		harvested_restore.queue_free()
		_expect(not harvest.try_harvest_target(), "harvest target could be collected twice")
		harvest_interactor.free()

	var full_patch := _new_pumpkin_patch()
	root.add_child(full_patch)
	_expect(full_patch.setup(voxel_world, player, 17391, generated_snapshot), "full-inventory harvest patch did not restore")
	var full_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	var full_slots: Dictionary = {}
	for index in range(InventoryModel.FILLABLE_SIZE):
		full_slots[index] = InventoryStack.new(&"dirt_block", 99)
	_expect(InventoryTestFixture.restore_slots(full_inventory, full_slots), "full inventory contents could not be restored")
	var full_loadout := InventoryTestFixture.create_loadout(full_inventory)
	var full_harvest := HarvestCoordinator.new()
	var full_harvest_sources: Array[HarvestSource] = [full_patch]
	_expect(full_harvest.setup(full_harvest_sources, full_inventory, full_loadout, prompt_coordinator), "full-inventory harvest setup failed")
	full_harvest.harvest_completed.connect(_on_harvest_completed)
	if crop_index >= 0:
		var full_snapshot_before := full_patch.snapshot()
		var full_inventory_before := full_inventory.to_dict()
		_target_tile(full_harvest, full_patch, crop_index)
		_expect(full_harvest.has_target(), "full inventory hid the mature pumpkin target")
		_expect(not full_harvest.can_harvest_target(), "full inventory reported harvest capacity")
		_expect(hud.interaction_prompt.text == HarvestCoordinator.INVENTORY_FULL_PROMPT, "full inventory did not show its harvest prompt")
		_expect(not full_harvest.try_harvest_target(), "pumpkin harvest succeeded with a full inventory")
		_expect(_harvest_completed_count == 1, "failed harvest announced a completed transaction")
		_expect(full_patch.snapshot() == full_snapshot_before, "failed harvest changed persistent crop state")
		_expect(full_inventory.to_dict() == full_inventory_before, "failed harvest partially changed inventory")
	full_harvest.clear_target()
	_run_atomic_harvest_regressions(
		voxel_world,
		player,
		item_catalog,
		generated_snapshot,
		prompt_coordinator,
	)

	var encoded_snapshot = JSON.parse_string(JSON.stringify(generated_snapshot))
	var restored_patch := _new_pumpkin_patch()
	root.add_child(restored_patch)
	_expect(restored_patch.setup(voxel_world, player, 17391, encoded_snapshot), "saved pumpkin patch did not restore")
	_expect(restored_patch.snapshot() == generated_snapshot, "save round trip changed pumpkin placement or growth states")
	_validate_patch_presentation(restored_patch)

	var repeated_generation := _new_pumpkin_patch()
	root.add_child(repeated_generation)
	_expect(repeated_generation.setup(voxel_world, player, 17391, null), "repeated deterministic generation failed")
	_expect(repeated_generation.snapshot() == generated_snapshot, "same world seed generated a different pumpkin patch")
	var different_seed_generation := _new_pumpkin_patch()
	root.add_child(different_seed_generation)
	_expect(different_seed_generation.setup(voxel_world, player, 17392, null), "different-seed generation failed")
	_expect(different_seed_generation.snapshot() != generated_snapshot, "different world seeds generated the same pumpkin patch")

	_state_changed_count = 0
	var processor := DevConsoleCommandProcessor.new()
	var actor_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	var structure_command := Callable(self, "_accept_structure_command")
	var console_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	var console_loadout := InventoryTestFixture.create_loadout(console_inventory, actor_stats)
	processor.setup(
		console_inventory,
		console_loadout,
		actor_stats,
		pumpkin_patch,
		structure_command,
		structure_command,
		structure_command,
		structure_command,
		Callable(self, "_accept_ripple_strength"),
		Callable(self, "_accept_bird_spawn"),
		Callable(self, "_accept_dungeon_clear"),
	)
	_expect(processor.execute("spawn pumpkin_patch") == DevConsoleCommandProcessor.ExecutionResult.KEEP_OPEN, "pumpkin patch console command failed")
	_expect(_state_changed_count == 1, "persistent pumpkin patch change was not announced")
	_expect(_count_state(pumpkin_patch.snapshot(), &"crop") >= 3, "spawned patch generated fewer than three harvestable pumpkins")
	_expect(pumpkin_patch.get_child_count() == 1, "pumpkin patch command accumulated presentations")

	var absent_patch := _new_pumpkin_patch()
	root.add_child(absent_patch)
	_expect(absent_patch.setup(voxel_world, player, 17391, {"present": false}), "older world without a patch did not restore")
	_expect(not absent_patch.has_patch() and absent_patch.get_child_count() == 0, "older world silently gained a pumpkin patch")

	var legacy_snapshot := generated_snapshot.duplicate(true)
	legacy_snapshot.erase("version")
	(legacy_snapshot["growth_state_ids"] as Array)[crop_index] = "harvested"
	var migrated_patch := _new_pumpkin_patch()
	root.add_child(migrated_patch)
	_expect(migrated_patch.setup(voxel_world, player, 17391, legacy_snapshot), "legacy harvested state did not migrate")
	var migrated_snapshot := migrated_patch.snapshot()
	_expect(migrated_snapshot.get("version", 0) == PumpkinPatchState.SNAPSHOT_VERSION, "legacy pumpkin snapshot did not upgrade")
	_expect((migrated_snapshot["growth_state_ids"] as Array)[crop_index] == "empty", "legacy harvested state did not become empty")
	var migrated_empty_holder := migrated_patch.get_node("PumpkinPatch/State%02d" % (crop_index + 1)) as Node3D
	_expect(migrated_empty_holder.get_child_count() == 0, "migrated empty tile retained a plant model")

	var invalid_patch := _new_pumpkin_patch()
	root.add_child(invalid_patch)
	_expect(not invalid_patch.setup(voxel_world, player, 17391, {"present": true}), "invalid pumpkin patch save was accepted")
	_expect(invalid_patch.get_child_count() == 0, "invalid restore created a partial presentation")

	var stone_patch := _new_pumpkin_patch()
	root.add_child(stone_patch)
	_expect(not stone_patch.setup(_flat_world(block_catalog, BlockId.Type.STONE), player, 17391, null), "new pumpkin patch accepted non-soil terrain")
	_expect(stone_patch.get_child_count() == 0, "failed generation created a partial presentation")

	pumpkin_patch.queue_free()
	restored_patch.queue_free()
	repeated_generation.queue_free()
	different_seed_generation.queue_free()
	absent_patch.queue_free()
	invalid_patch.queue_free()
	stone_patch.queue_free()
	migrated_patch.queue_free()
	full_patch.queue_free()
	dense_foliage_patch.queue_free()
	restored_foliage_patch.queue_free()
	deferred_foliage_patch.queue_free()
	hud.queue_free()
	player.queue_free()
	await process_frame
	await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "orphan count ended at %d" % orphan_count)
	if _errors.is_empty():
		print("PUMPKIN_PATCH_PERSISTENCE PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("PUMPKIN_PATCH_PERSISTENCE FAIL %s" % str(_errors))
		quit(1)

func _new_pumpkin_patch() -> PumpkinPatchCoordinator:
	return (load("res://farming/pumpkin/pumpkin_patch_coordinator.tscn") as PackedScene).instantiate() as PumpkinPatchCoordinator

func _run_atomic_harvest_regressions(
	voxel_world: VoxelWorld,
	player: Node3D,
	item_catalog: ItemCatalog,
	generated_snapshot: Dictionary,
	prompt_coordinator: InteractionPromptCoordinator,
) -> void:
	var crop_indices: Array[int] = []
	var state_ids := generated_snapshot.get("growth_state_ids", []) as Array
	for index in range(state_ids.size()):
		if state_ids[index] == "crop":
			crop_indices.append(index)
	_expect(crop_indices.size() >= 3, "atomic harvest regressions require three mature crops")
	if crop_indices.size() < 3:
		return

	var direct_patch := _new_pumpkin_patch()
	var foreign_patch := _new_pumpkin_patch()
	root.add_child(direct_patch)
	root.add_child(foreign_patch)
	_expect(direct_patch.setup(voxel_world, player, 17391, generated_snapshot), "prepared harvest patch setup failed")
	_expect(foreign_patch.setup(voxel_world, player, 17391, generated_snapshot), "foreign prepared harvest patch setup failed")
	var direct_change := direct_patch.prepare_harvest_target(crop_indices[0])
	_expect(direct_change != null, "valid pumpkin harvest did not prepare")
	if direct_change != null:
		_expect(not foreign_patch.can_commit_prepared_harvest(direct_change), "foreign pumpkin patch accepted a prepared harvest")
		var direct_notifications: Array[bool] = []
		direct_patch.state_changed.connect(func() -> void: direct_notifications.append(true))
		_expect(direct_patch._commit_prepared_harvest(direct_change, false), "silent pumpkin harvest commit failed")
		_expect(direct_notifications.is_empty(), "silent pumpkin harvest emitted state_changed")
		_expect(_find_state_index_at(direct_patch.snapshot(), crop_indices[0]) == &"empty", "silent pumpkin harvest did not commit state")
		var silent_holder := direct_patch.get_node("PumpkinPatch/State%02d" % (crop_indices[0] + 1)) as Node3D
		_expect(silent_holder.get_child_count() == 1, "silent pumpkin harvest updated presentation before notification")
		_expect(not direct_patch.can_commit_prepared_harvest(direct_change), "committed pumpkin harvest remained valid")
		_expect(not direct_patch._commit_prepared_harvest(direct_change, false), "prepared pumpkin harvest committed twice")
		_expect(direct_patch._notify_prepared_harvest(direct_change), "silent pumpkin harvest notification failed")
		_expect(direct_notifications.size() == 1, "prepared pumpkin harvest did not notify exactly once")
		var notified_holder := direct_patch.get_node("PumpkinPatch/State%02d" % (crop_indices[0] + 1)) as Node3D
		_expect(notified_holder.get_child_count() == 0, "pumpkin harvest notification did not update presentation")
		_expect(not direct_patch._notify_prepared_harvest(direct_change), "prepared pumpkin harvest notified twice")
	direct_patch.free()
	foreign_patch.free()

	var stale_patch := _new_pumpkin_patch()
	root.add_child(stale_patch)
	_expect(stale_patch.setup(voxel_world, player, 17391, generated_snapshot), "stale harvest patch setup failed")
	var stale_change := stale_patch.prepare_harvest_target(crop_indices[0])
	_expect(stale_change != null, "stale pumpkin harvest did not prepare")
	_expect(_commit_source_harvest(stale_patch, crop_indices[1]), "intervening pumpkin harvest failed")
	var stale_snapshot := stale_patch.snapshot()
	_expect(not stale_patch._commit_prepared_harvest(stale_change, false), "stale prepared pumpkin harvest committed")
	_expect(stale_patch.snapshot() == stale_snapshot, "stale prepared pumpkin harvest changed patch state")
	stale_patch.free()

	var inventory_stale_patch := _new_pumpkin_patch()
	root.add_child(inventory_stale_patch)
	_expect(inventory_stale_patch.setup(voxel_world, player, 17391, generated_snapshot), "inventory-stale harvest patch setup failed")
	var inventory_stale_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	var inventory_stale_loadout := InventoryTestFixture.create_loadout(inventory_stale_inventory)
	var inventory_stale_harvest := HarvestCoordinator.new()
	var inventory_stale_sources: Array[HarvestSource] = [inventory_stale_patch]
	_expect(inventory_stale_harvest.setup(
		inventory_stale_sources,
		inventory_stale_inventory,
		inventory_stale_loadout,
		prompt_coordinator,
	), "inventory-stale harvest setup failed")
	_target_tile(inventory_stale_harvest, inventory_stale_patch, crop_indices[0])
	var inventory_stale_transaction := inventory_stale_harvest._prepare_target_harvest()
	_expect(inventory_stale_transaction != null, "inventory-stale harvest transaction did not prepare")
	_expect(inventory_stale_loadout.add_backpack_item(&"dirt_block", 1), "inventory-stale setup mutation failed")
	var inventory_stale_snapshot := inventory_stale_patch.snapshot()
	_expect(not inventory_stale_harvest._can_commit_prepared_harvest(inventory_stale_transaction), "harvest accepted a stale inventory revision")
	_expect(inventory_stale_patch.snapshot() == inventory_stale_snapshot, "inventory-stale harvest partially changed patch state")
	_expect(inventory_stale_inventory.get_inventory_item_count(&"pumpkin") == 0, "inventory-stale harvest partially granted a pumpkin")
	_expect(inventory_stale_inventory.get_inventory_item_count(&"dirt_block") == 1, "inventory-stale harvest changed the intervening inventory mutation")
	inventory_stale_patch.free()

	var patch_stale_patch := _new_pumpkin_patch()
	root.add_child(patch_stale_patch)
	_expect(patch_stale_patch.setup(voxel_world, player, 17391, generated_snapshot), "patch-stale harvest patch setup failed")
	var patch_stale_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	var patch_stale_loadout := InventoryTestFixture.create_loadout(patch_stale_inventory)
	var patch_stale_harvest := HarvestCoordinator.new()
	var patch_stale_sources: Array[HarvestSource] = [patch_stale_patch]
	_expect(patch_stale_harvest.setup(
		patch_stale_sources,
		patch_stale_inventory,
		patch_stale_loadout,
		prompt_coordinator,
	), "patch-stale harvest setup failed")
	_target_tile(patch_stale_harvest, patch_stale_patch, crop_indices[0])
	var patch_stale_transaction := patch_stale_harvest._prepare_target_harvest()
	_expect(patch_stale_transaction != null, "patch-stale harvest transaction did not prepare")
	_expect(_commit_source_harvest(patch_stale_patch, crop_indices[1]), "patch-stale setup mutation failed")
	var patch_stale_snapshot := patch_stale_patch.snapshot()
	_expect(not patch_stale_harvest._can_commit_prepared_harvest(patch_stale_transaction), "harvest accepted a stale source revision")
	_expect(patch_stale_patch.snapshot() == patch_stale_snapshot, "patch-stale harvest changed the intervening patch mutation")
	_expect(_find_state_index_at(patch_stale_snapshot, crop_indices[0]) == &"crop", "patch-stale harvest consumed its reserved crop")
	_expect(patch_stale_inventory.get_inventory_item_count(&"pumpkin") == 0, "patch-stale harvest partially granted a pumpkin")
	patch_stale_patch.free()

	var observed_patch := _new_pumpkin_patch()
	root.add_child(observed_patch)
	_expect(observed_patch.setup(voxel_world, player, 17391, generated_snapshot), "observed harvest patch setup failed")
	var observed_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	var observed_loadout := InventoryTestFixture.create_loadout(observed_inventory)
	var observed_harvest := HarvestCoordinator.new()
	var observed_sources: Array[HarvestSource] = [observed_patch]
	_expect(observed_harvest.setup(
		observed_sources,
		observed_inventory,
		observed_loadout,
		prompt_coordinator,
	), "observed harvest setup failed")
	_target_tile(observed_harvest, observed_patch, crop_indices[0])
	var observed_transaction := observed_harvest._prepare_target_harvest()
	_expect(observed_transaction != null, "observed harvest transaction did not prepare")
	_expect(observed_harvest._can_commit_prepared_harvest(observed_transaction), "observed harvest transaction was not committable")
	var patch_observations: Array[bool] = []
	var inventory_observations: Array[bool] = []
	var reentrant_results: Array[bool] = []
	observed_patch.state_changed.connect(func() -> void:
		patch_observations.append(observed_inventory.get_inventory_item_count(&"pumpkin") == 1)
		reentrant_results.append(observed_harvest.try_harvest_target())
	)
	observed_inventory.inventory_changed.connect(func() -> void:
		inventory_observations.append(_find_state_index_at(observed_patch.snapshot(), crop_indices[0]) == &"empty")
		reentrant_results.append(observed_harvest.try_harvest_target())
	)
	_expect(observed_harvest.try_harvest_target(), "observed pumpkin harvest transaction failed")
	_expect(patch_observations == [true], "patch observer saw inventory before the harvest commit")
	_expect(inventory_observations == [true], "inventory observer saw patch state before the harvest commit")
	_expect(reentrant_results == [false, false], "harvest signal reentrancy committed the crop twice")
	_expect(observed_inventory.get_inventory_item_count(&"pumpkin") == 1, "observed harvest granted the wrong pumpkin count")
	_expect(not observed_harvest._can_commit_prepared_harvest(observed_transaction), "committed combined pumpkin harvest transaction remained valid")
	_expect(patch_observations.size() == 1 and inventory_observations.size() == 1, "duplicate pumpkin harvest emitted another owner notification")
	observed_patch.free()

func _find_state_index_at(snapshot: Dictionary, tile_index: int) -> StringName:
	return StringName((snapshot.get("growth_state_ids", []) as Array)[tile_index])

func _find_state_index(snapshot: Dictionary, state_id: StringName) -> int:
	return (snapshot.get("growth_state_ids", []) as Array).find(String(state_id))

func _count_state(snapshot: Dictionary, state_id: StringName) -> int:
	return (snapshot.get("growth_state_ids", []) as Array).count(String(state_id))

func _commit_source_harvest(source: HarvestSource, target_id: int) -> bool:
	var prepared := source.prepare_harvest_target(target_id)
	return prepared != null and source._commit_prepared_harvest(prepared)

func _target_tile(harvest: HarvestCoordinator, pumpkin_patch: PumpkinPatchCoordinator, tile_index: int) -> void:
	var bounds := pumpkin_patch.get_tile_world_bounds(tile_index)
	var target_center := bounds.get_center()
	harvest.update_target(target_center + Vector3.UP * 5.0, Vector3.DOWN, 10.0, target_center, 6.0)

func _validate_patch_presentation(pumpkin_patch: PumpkinPatchCoordinator) -> void:
	_expect(pumpkin_patch.soil_texture != null, "pumpkin patch soil texture was not configured")
	_expect(pumpkin_patch.growth_states.size() == 6, "pumpkin patch did not configure six growth-state definitions")
	var patch := pumpkin_patch.get_node_or_null("PumpkinPatch") as Node3D
	_expect(patch != null, "pumpkin patch root was not created")
	if patch == null:
		return
	var soil_count := 0
	var state_count := 0
	var largest_model_width := 0.0
	var occupied_tiles: Dictionary = {}
	var represented_states: Dictionary = {}
	for child in patch.get_children():
		if child is MeshInstance3D:
			soil_count += 1
			var soil := child as MeshInstance3D
			var material := soil.mesh.material as StandardMaterial3D
			_expect(material.albedo_texture.resource_path == "res://assets/textures/blocks/farmland_dry.png", "pumpkin soil used the wrong texture")
		elif child is Node3D:
			state_count += 1
			var holder := child as Node3D
			var quarter_turns := holder.rotation.y / (PI * 0.5)
			_expect(is_equal_approx(quarter_turns, roundf(quarter_turns)), "%s rotation was not a 90-degree increment" % child.name)
			occupied_tiles[Vector2i(floori(holder.position.x), floori(holder.position.z))] = true
			if holder.get_child_count() == 1:
				var model := holder.get_child(0) as Node3D
				represented_states[model.scene_file_path] = true
				_expect(is_zero_approx(model.position.x) and is_zero_approx(model.position.z), "%s did not preserve its authored horizontal origin" % child.name)
			var model_bounds := _calculate_bounds(holder)
			var horizontal_size := maxf(model_bounds.size.x, model_bounds.size.z)
			largest_model_width = maxf(largest_model_width, horizontal_size)
			_expect(horizontal_size <= PumpkinPatchCoordinator.MODEL_FIT_SIZE + 0.001, "%s exceeded the configured footprint" % child.name)
			_expect(absf(model_bounds.position.y - PumpkinPatchCoordinator.SOIL_SURFACE_OFFSET) < 0.001, "%s did not rest on the tilled soil" % child.name)
	_expect(soil_count == PumpkinPatchState.TILE_COUNT, "pumpkin patch did not create a 5x4 soil bed")
	_expect(state_count == PumpkinPatchState.TILE_COUNT, "pumpkin patch did not fill all twenty tiles")
	_expect(occupied_tiles.size() == state_count, "pumpkin patch placed multiple models on one tile")
	var generated_state_count := 0
	for definition in pumpkin_patch.growth_states:
		if definition.generate_in_new_patch:
			generated_state_count += 1
	_expect(represented_states.size() == generated_state_count, "pumpkin patch did not represent every generated growth state")
	_expect(largest_model_width >= PumpkinPatchCoordinator.MODEL_FIT_SIZE - 0.001, "largest pumpkin did not reach the configured size")

func _flat_world(block_catalog: BlockCatalog, surface_block_id: int) -> VoxelWorld:
	var voxel_world := VoxelWorld.new(20, 36, -1, 12.0, block_catalog)
	for x in range(-90, 91):
		for z in range(-90, 91):
			var key := Vector2i(x, z)
			voxel_world.height_map_dict[key] = 0
			voxel_world.type_map_dict[key] = surface_block_id
	return voxel_world

func _fill_with_foliage(voxel_world: VoxelWorld) -> void:
	var chunks: Dictionary = {}
	for x in range(-50, 51):
		for z in range(-50, 51):
			var position := Vector3i(x, 1, z)
			var coord := ChunkCoord.world_to_chunk_vec3i(position, voxel_world.chunk_size)
			if not chunks.has(coord):
				chunks[coord] = {}
			(chunks[coord] as Dictionary)[position] = BlockId.Type.SHORT_GRASS
	for coord in chunks:
		voxel_world.apply_foliage_chunk_for_coord(coord, {"foliage_block_fast": chunks[coord]})

func _fill_snapshot_footprint_with_foliage(voxel_world: VoxelWorld, snapshot: Dictionary) -> void:
	var encoded_origin := snapshot.get("origin", []) as Array
	_expect(encoded_origin.size() == 3, "deferred foliage patch omitted its origin")
	if encoded_origin.size() != 3:
		return
	var origin := Vector3i(int(encoded_origin[0]), int(encoded_origin[1]), int(encoded_origin[2]))
	var chunks: Dictionary = {}
	for x_offset in range(PumpkinPatchCoordinator.PATCH_WIDTH):
		for z_offset in range(PumpkinPatchCoordinator.PATCH_DEPTH):
			var position := origin + Vector3i(x_offset, 1, z_offset)
			var coord := ChunkCoord.world_to_chunk_vec3i(position, voxel_world.chunk_size)
			if not chunks.has(coord):
				chunks[coord] = {}
			(chunks[coord] as Dictionary)[position] = BlockId.Type.SHORT_GRASS
	for coord in chunks:
		voxel_world.apply_foliage_chunk_for_coord(coord, {"foliage_block_fast": chunks[coord]})

func _validate_cleared_foliage_footprint(voxel_world: VoxelWorld, snapshot: Dictionary, label: String) -> void:
	var encoded_origin := snapshot.get("origin", []) as Array
	_expect(encoded_origin.size() == 3, "%s clearance patch omitted its origin" % label)
	if encoded_origin.size() != 3:
		return
	var origin := Vector3i(int(encoded_origin[0]), int(encoded_origin[1]), int(encoded_origin[2]))
	var removed := voxel_world.snapshot_block_edits()["removed"] as Dictionary
	var reserved_count := 0
	var persisted_count := 0
	for x_offset in range(PumpkinPatchCoordinator.PATCH_WIDTH):
		for z_offset in range(PumpkinPatchCoordinator.PATCH_DEPTH):
			var position := origin + Vector3i(x_offset, 1, z_offset)
			if voxel_world.is_foliage_clearance_reserved(position):
				reserved_count += 1
			_expect(voxel_world.get_block_id_at(position) == BlockId.Type.AIR, "%s pumpkin footprint lost its clearance" % label)
			if removed.has(position):
				persisted_count += 1
	_expect(reserved_count == PumpkinPatchState.TILE_COUNT, "%s pumpkin footprint reserved %d cells" % [label, reserved_count])
	_expect(persisted_count == 0, "%s pumpkin footprint fabricated %d block removals" % [label, persisted_count])

func _calculate_bounds(root_node: Node3D) -> AABB:
	var mesh_bounds: Array[AABB] = []
	_collect_bounds(root_node, Transform3D.IDENTITY, mesh_bounds)
	if mesh_bounds.is_empty():
		return AABB()
	var combined := mesh_bounds[0]
	for index in range(1, mesh_bounds.size()):
		combined = combined.merge(mesh_bounds[index])
	return combined

func _collect_bounds(node: Node, parent_transform: Transform3D, output: Array[AABB]) -> void:
	for child in node.get_children():
		var child_transform := parent_transform
		if child is Node3D:
			child_transform = parent_transform * (child as Node3D).transform
		if child is MeshInstance3D:
			output.append(child_transform * (child as MeshInstance3D).get_aabb())
		_collect_bounds(child, child_transform, output)

func _on_state_changed() -> void:
	_state_changed_count += 1

func _accept_structure_command() -> bool:
	return true

func _accept_ripple_strength(_strength: float) -> bool:
	return true

func _accept_bird_spawn(_variant_id: StringName, _count: int) -> bool:
	return true

func _accept_dungeon_clear() -> bool:
	return true

func _is_interaction_blocked() -> bool:
	return false

func _on_harvest_completed() -> void:
	_harvest_completed_count += 1

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
