extends SceneTree

var _errors: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var voxel_world := _flat_world(block_catalog, BlockId.Type.GRASS)
	var player := Node3D.new()
	player.position = Vector3(0.5, 1.0, 0.5)
	root.add_child(player)
	var preview := (load("res://farming/debug/pumpkin_patch_preview.tscn") as PackedScene).instantiate() as PumpkinPatchPreview
	root.add_child(preview)
	preview.setup(voxel_world, player)
	_expect(voxel_world.get_highest_solid_y(0, 0) == 0, "flat-world fixture did not expose a surface")
	_expect(voxel_world.get_block_id_at(Vector3i.ZERO) == BlockId.Type.GRASS, "flat-world fixture did not expose grass")
	_expect(preview.soil_texture != null, "pumpkin patch soil texture was not configured")
	_expect(preview.pumpkin_scenes.size() == 6, "pumpkin patch did not configure six model scenes")
	_expect(preview._get_patch_surface_y(0, 0) == 0, "pumpkin patch rejected a known flat soil area")
	var selected_origin := preview._find_patch_origin()
	_expect(selected_origin.y >= 0, "pumpkin patch could not select flat soil terrain")
	var processor := DevConsoleCommandProcessor.new()
	processor.setup(InventoryModel.new(load("res://items/item_catalog.tres") as ItemCatalog), preview)
	_expect(processor.execute("spawn pumpkin_patch"), "flat grass terrain rejected the pumpkin patch command")
	var patch := preview.get_node_or_null("PumpkinPatch") as Node3D
	_expect(patch != null, "pumpkin patch root was not created")
	if patch != null:
		_expect(patch.position.y == 1.0, "pumpkin patch did not rest on the terrain surface")
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
				_expect(material.albedo_texture.resource_path == "res://assets/textures/blocks/farmland_dry.png", "preview soil used the wrong texture")
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
				_expect(horizontal_size <= PumpkinPatchPreview.MODEL_FIT_SIZE + 0.001, "%s exceeded the configured preview footprint" % child.name)
				_expect(absf(model_bounds.position.y - PumpkinPatchPreview.SOIL_SURFACE_OFFSET) < 0.001, "%s did not rest on the tilled soil" % child.name)
		_expect(soil_count == PumpkinPatchPreview.PATCH_WIDTH * PumpkinPatchPreview.PATCH_DEPTH, "pumpkin patch did not create a 5x4 soil bed")
		_expect(state_count == PumpkinPatchPreview.PATCH_WIDTH * PumpkinPatchPreview.PATCH_DEPTH, "pumpkin patch did not fill all twenty tiles")
		_expect(occupied_tiles.size() == state_count, "pumpkin patch placed multiple models on one tile")
		_expect(represented_states.size() == PumpkinPatchPreview.GROWTH_STATE_COUNT, "pumpkin patch did not represent all six growth states")
		_expect(largest_model_width >= PumpkinPatchPreview.MODEL_FIT_SIZE - 0.001, "largest pumpkin did not reach the configured preview size")
	_expect(voxel_world.get_block_edit_count() == 0, "pumpkin preview persisted debug terrain edits")
	_expect(processor.execute("spawn pumpkin_patch"), "repeated pumpkin patch command failed")
	_expect(preview.get_child_count() == 1, "repeated pumpkin patch command accumulated previews")
	var stone_preview := (load("res://farming/debug/pumpkin_patch_preview.tscn") as PackedScene).instantiate() as PumpkinPatchPreview
	root.add_child(stone_preview)
	stone_preview.setup(_flat_world(block_catalog, BlockId.Type.STONE), player)
	_expect(not stone_preview.spawn_patch(), "pumpkin patch accepted non-soil terrain")
	_expect(stone_preview.get_child_count() == 0, "failed pumpkin patch command created presentation")
	preview.queue_free()
	stone_preview.queue_free()
	player.queue_free()
	await process_frame
	await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "orphan count ended at %d" % orphan_count)
	if _errors.is_empty():
		print("PUMPKIN_PATCH_PREVIEW PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("PUMPKIN_PATCH_PREVIEW FAIL %s" % str(_errors))
		quit(1)

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

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
