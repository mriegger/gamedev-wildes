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
	_expect(voxel_world.get_block_edit_count() == 0, "pumpkin patch generation changed authoritative terrain")

	var hud := (load("res://ui/hud/hud.tscn") as PackedScene).instantiate() as HUD
	root.add_child(hud)
	await process_frame
	var prompt_coordinator := InteractionPromptCoordinator.new()
	prompt_coordinator.setup(hud, Callable(self, "_is_interaction_blocked"))
	prompt_coordinator.set_level_prompt("F  Enter Dungeon")
	var inventory := InventoryModel.new(item_catalog)
	var harvest := PumpkinHarvestCoordinator.new()
	_expect(harvest.setup(pumpkin_patch, inventory, prompt_coordinator), "pumpkin harvest setup rejected valid content")
	harvest.harvest_completed.connect(_on_harvest_completed)
	var crop_index := _find_state_index(generated_snapshot, &"crop")
	_expect(crop_index >= 0, "generated patch omitted a mature crop")
	if crop_index >= 0:
		_target_tile(harvest, pumpkin_patch, crop_index)
		_expect(harvest.has_target(), "mature pumpkin ray did not produce a harvest target")
		_expect(harvest.can_harvest_target(), "mature pumpkin was not harvestable with inventory capacity")
		_expect(hud.interaction_prompt.visible and hud.interaction_prompt.text == PumpkinHarvestCoordinator.HARVEST_PROMPT, "harvest prompt did not override the level prompt")
		pumpkin_patch.state_changed.connect(_on_state_changed)
		var harvest_input := InputBuffer.new()
		var harvest_interactor := PlayerInteractor.new()
		harvest_interactor.inventory_model = inventory
		harvest_interactor._input_buffer = harvest_input
		harvest_interactor.pumpkin_harvest = harvest
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
	var full_inventory := InventoryModel.new(item_catalog)
	for index in range(InventoryModel.FILLABLE_SIZE):
		full_inventory.slots[index] = InventoryStack.new(&"dirt_block", 99)
	var full_harvest := PumpkinHarvestCoordinator.new()
	_expect(full_harvest.setup(full_patch, full_inventory, prompt_coordinator), "full-inventory harvest setup failed")
	full_harvest.harvest_completed.connect(_on_harvest_completed)
	if crop_index >= 0:
		var full_snapshot_before := full_patch.snapshot()
		var full_inventory_before := full_inventory.to_dict()
		_target_tile(full_harvest, full_patch, crop_index)
		_expect(full_harvest.has_target(), "full inventory hid the mature pumpkin target")
		_expect(not full_harvest.can_harvest_target(), "full inventory reported harvest capacity")
		_expect(hud.interaction_prompt.text == PumpkinHarvestCoordinator.INVENTORY_FULL_PROMPT, "full inventory did not show its harvest prompt")
		_expect(not full_harvest.try_harvest_target(), "pumpkin harvest succeeded with a full inventory")
		_expect(_harvest_completed_count == 1, "failed harvest announced a completed transaction")
		_expect(full_patch.snapshot() == full_snapshot_before, "failed harvest changed persistent crop state")
		_expect(full_inventory.to_dict() == full_inventory_before, "failed harvest partially changed inventory")
	full_harvest.clear_target()

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
	processor.setup(InventoryModel.new(load("res://items/item_catalog.tres") as ItemCatalog), actor_stats, pumpkin_patch, structure_command, structure_command, structure_command, structure_command)
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

func _find_state_index(snapshot: Dictionary, state_id: StringName) -> int:
	return (snapshot.get("growth_state_ids", []) as Array).find(String(state_id))

func _count_state(snapshot: Dictionary, state_id: StringName) -> int:
	return (snapshot.get("growth_state_ids", []) as Array).count(String(state_id))

func _target_tile(harvest: PumpkinHarvestCoordinator, pumpkin_patch: PumpkinPatchCoordinator, tile_index: int) -> void:
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

func _is_interaction_blocked() -> bool:
	return false

func _on_harvest_completed() -> void:
	_harvest_completed_count += 1

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
