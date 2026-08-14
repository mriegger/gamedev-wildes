extends SceneTree

var _errors: Array[String] = []
var _state_changed_count: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
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

	pumpkin_patch.state_changed.connect(_on_state_changed)
	var processor := DevConsoleCommandProcessor.new()
	processor.setup(InventoryModel.new(load("res://items/item_catalog.tres") as ItemCatalog), pumpkin_patch)
	_expect(processor.execute("spawn pumpkin_patch"), "pumpkin patch console command failed")
	_expect(_state_changed_count == 1, "persistent pumpkin patch change was not announced")
	_expect(pumpkin_patch.get_child_count() == 1, "pumpkin patch command accumulated presentations")

	var absent_patch := _new_pumpkin_patch()
	root.add_child(absent_patch)
	_expect(absent_patch.setup(voxel_world, player, 17391, {"present": false}), "older world without a patch did not restore")
	_expect(not absent_patch.has_patch() and absent_patch.get_child_count() == 0, "older world silently gained a pumpkin patch")

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
				represented_states[(holder.get_child(0) as Node).scene_file_path] = true
			var model_bounds := _calculate_bounds(holder)
			var horizontal_size := maxf(model_bounds.size.x, model_bounds.size.z)
			largest_model_width = maxf(largest_model_width, horizontal_size)
			_expect(horizontal_size <= PumpkinPatchCoordinator.MODEL_FIT_SIZE + 0.001, "%s exceeded the configured footprint" % child.name)
			_expect(absf(model_bounds.position.y - PumpkinPatchCoordinator.SOIL_SURFACE_OFFSET) < 0.001, "%s did not rest on the tilled soil" % child.name)
	_expect(soil_count == PumpkinPatchState.TILE_COUNT, "pumpkin patch did not create a 5x4 soil bed")
	_expect(state_count == PumpkinPatchState.TILE_COUNT, "pumpkin patch did not fill all twenty tiles")
	_expect(occupied_tiles.size() == state_count, "pumpkin patch placed multiple models on one tile")
	_expect(represented_states.size() == pumpkin_patch.growth_states.size(), "pumpkin patch did not represent every growth state")
	_expect(largest_model_width >= PumpkinPatchCoordinator.MODEL_FIT_SIZE - 0.001, "largest pumpkin did not reach the configured size")

func _flat_world(block_catalog: BlockCatalog, surface_block_id: int) -> VoxelWorld:
	var voxel_world := VoxelWorld.new(20, 36, -1, 12.0, block_catalog)
	for x in range(-12, 13):
		for z in range(-12, 13):
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

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
