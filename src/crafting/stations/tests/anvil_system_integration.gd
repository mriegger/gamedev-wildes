extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var general_catalog := load("res://crafting/crafting_recipe_catalog.tres") as CraftingRecipeCatalog
	var anvil_catalog := load("res://crafting/stations/anvil_recipe_catalog.tres") as CraftingRecipeCatalog
	var cauldron_catalog := load("res://crafting/stations/cauldron_recipe_catalog.tres") as CraftingRecipeCatalog
	_expect(block_catalog != null and block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog != null and item_catalog.validate(block_catalog), "item catalog invalid")
	_expect(general_catalog != null and general_catalog.validate(item_catalog), "general crafting catalog invalid")
	_expect(anvil_catalog != null and anvil_catalog.validate(item_catalog), "anvil crafting catalog invalid")
	_expect(cauldron_catalog != null and cauldron_catalog.validate(item_catalog), "cauldron crafting catalog invalid")
	if block_catalog == null or item_catalog == null:
		_finish()
		return

	var anvil_block := block_catalog.get_definition(BlockId.Type.ANVIL)
	var anvil_item := item_catalog.get_definition(&"anvil")
	var placement := anvil_item.secondary_action as BlockPlacementActionDefinition
	_expect(BlockId.get_display_name(BlockId.Type.ANVIL) == "Anvil", "anvil display name is incorrect")
	_expect(not BlockId.is_chunk_cube(BlockId.Type.ANVIL), "anvil is still baked into the cube mesh")
	_expect(BlockId.is_ao_solid(BlockId.Type.ANVIL), "anvil does not occlude ambient light")
	_expect(anvil_block.crafting_station != null and anvil_block.crafting_station.id == &"anvil", "anvil crafting-station metadata is invalid")
	_expect(anvil_block.is_solid and not anvil_block.is_opaque and anvil_block.is_raycast_solid, "anvil physical properties are invalid")
	_expect(anvil_block.is_breakable and anvil_block.mining_tool_tag == &"pickaxe" and anvil_block.minimum_mining_power == 1, "anvil does not use normal pickaxe mining")
	_expect(anvil_block.drop_item_id == &"anvil", "mined anvil does not use the normal block drop")
	_expect(placement != null and placement.block == anvil_block, "anvil item does not place the canonical block")
	_expect(item_catalog.get_item_for_block(BlockId.Type.ANVIL) == anvil_item, "anvil reverse block mapping is invalid")
	_expect(anvil_item.max_stack == 1, "anvil stack limit is not one")
	_expect(anvil_item.icon.resource_path == "res://assets/textures/items/anvil.png", "anvil uses the wrong inventory icon")
	var icon_image := anvil_item.icon.get_image()
	_expect(icon_image != null and icon_image.get_size() == Vector2i(16, 16), "anvil inventory icon is not 16x16 pixel art")
	_expect(icon_image != null and icon_image.detect_alpha() != Image.ALPHA_NONE, "anvil inventory icon has no transparency")
	var icon_colors: Dictionary = {}
	var partial_alpha_pixels := 0
	if icon_image != null:
		for y in range(icon_image.get_height()):
			for x in range(icon_image.get_width()):
				var pixel := icon_image.get_pixel(x, y)
				if pixel.a > 0.0:
					icon_colors[Color(pixel.r, pixel.g, pixel.b, 1.0)] = true
				if pixel.a > 0.0 and pixel.a < 1.0:
					partial_alpha_pixels += 1
	_expect(icon_colors.size() <= 4, "anvil inventory icon exceeds its pixel-art palette")
	_expect(partial_alpha_pixels == 0, "anvil inventory icon contains anti-aliased pixels")
	_expect(general_catalog.has_definition(&"anvil"), "anvil is not craftable from general crafting")
	_expect(general_catalog.get_definition(&"anvil").get_ingredient_counts() == {&"copper": 10}, "anvil recipe does not require ten copper")
	for recipe_id in [&"copper_pickaxe", &"copper_hoe", &"copper_sword", &"copper_hammer", &"copper_helmet", &"copper_chest_plate", &"copper_pants", &"copper_shoes"]:
		_expect(not general_catalog.has_definition(recipe_id), "%s leaked into general crafting" % recipe_id)
		_expect(anvil_catalog.has_definition(recipe_id), "%s is missing from anvil crafting" % recipe_id)
	await _test_cauldron(block_catalog, item_catalog, general_catalog, cauldron_catalog)

	var renderer := AnvilRenderer.new()
	root.add_child(renderer)
	renderer.setup()
	var position := Vector3i(3, 4, 5)
	var rendered := renderer.spawn_anvil(position)
	_expect(rendered != null and rendered.position == Vector3(position), "anvil renderer placed the model incorrectly")
	_expect(rendered.get_child_count() == 4, "anvil model does not contain the expected simplified parts")
	var top := rendered.get_node_or_null("Top") as MeshInstance3D
	var horn := rendered.get_node_or_null("Horn") as MeshInstance3D
	_expect(top != null and top.mesh is BoxMesh, "anvil top is missing")
	_expect(horn != null and horn.mesh is ArrayMesh and (horn.mesh as ArrayMesh).get_faces().size() == 18, "anvil horn is not the simplified wedge")
	if horn != null:
		var horn_bounds := horn.get_aabb()
		_expect(is_equal_approx(horn_bounds.end.y, 0.75), "anvil horn rises above the top surface")
		_expect(horn_bounds.end.x > 0.95, "anvil horn does not extend far enough horizontally")
	var anvil_material := top.material_override as StandardMaterial3D
	_expect(top != null and anvil_material.albedo_color.get_luminance() > 0.3 and anvil_material.albedo_color.get_luminance() < 0.5, "anvil model is not medium gray")
	_expect(anvil_material.metallic < 0.15 and anvil_material.roughness > 0.8, "anvil model is not matte")
	renderer.set_hovered_anvil(position)
	_expect(top != null and top.material_overlay != null and horn.material_overlay != null, "hover highlight did not cover the full anvil")
	_expect((horn.material_overlay as StandardMaterial3D).cull_mode == BaseMaterial3D.CULL_BACK, "anvil highlight renders overlapping back faces")
	renderer.set_hovered_anvil(null)
	_expect(top != null and top.material_overlay == null, "anvil hover highlight did not clear")
	var targeting_view := TargetingView.new()
	targeting_view._set_interaction_cursor(true)
	_expect(targeting_view._interaction_cursor_active, "anvil interaction did not enable the pointing-hand cursor state")
	targeting_view._set_interaction_cursor(false)
	_expect(not targeting_view._interaction_cursor_active, "anvil interaction cursor state did not reset")
	var cursor_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	var cursor_interactor := PlayerInteractor.new()
	cursor_interactor.inventory_model = cursor_inventory
	cursor_interactor.target_has = true
	cursor_interactor.can_interact_target = true
	cursor_interactor.target_crafting_station = anvil_block.crafting_station
	targeting_view.interactor = cursor_interactor
	_expect(targeting_view._should_show_interaction(), "empty-hand anvil interaction did not enable the pointing cursor")
	InventoryTestFixture.restore_slot(cursor_inventory, 0, InventoryStack.new(
		&"stone_pickaxe",
		1,
		cursor_inventory.equipment_instance_factory.create(&"stone_pickaxe"),
	))
	_expect(cursor_interactor.is_attempting_crafting_station_mining(), "pickaxe did not select anvil mining mode")
	_expect(not targeting_view._should_show_interaction(), "pickaxe mining mode enabled the anvil interaction cursor")
	renderer.set_placement_preview(Vector3i(6, 7, 8), true)
	_expect(renderer._placement_preview != null and renderer._placement_preview.visible, "anvil placement preview was not shown")
	_expect(renderer._placement_preview.global_position == Vector3(6, 7, 8), "anvil placement preview used the wrong position")
	renderer.set_placement_preview(null, false)
	_expect(not renderer._placement_preview.visible, "anvil placement preview did not hide")

	var texture_set := BlockTextureSet.new(block_catalog)
	var mesher := ChunkMesher.new(1, 4, 1, false, texture_set)
	var cache := PackedInt32Array()
	cache.resize(3 * 4 * 3)
	cache.fill(BlockId.Type.AIR)
	var stone_index := 1 * 4 * 3 + 1 * 3 + 1
	var anvil_index := 1 * 4 * 3 + 2 * 3 + 1
	cache[stone_index] = BlockId.Type.STONE
	cache[anvil_index] = BlockId.Type.ANVIL
	var mesh_data = mesher.build_mesh_data_from_cache({
		"cache": cache,
		"origin_x": 0,
		"origin_z": 0,
		"size_x": 1,
		"size_z": 1,
		"size_y": 4,
		"cache_x": 3,
		"cache_z": 3,
	})
	_expect(mesh_data != null and (mesh_data["vertices"] as PackedVector3Array).size() == 24, "anvil hid a face of the supporting terrain block")

	var world := VoxelWorld.new(20, 36, 5, 12.0, block_catalog)
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	var inventory_loadout := InventoryTestFixture.create_loadout(inventory)
	_expect(inventory_loadout != null, "inventory loadout setup failed")
	var coordinator := AnvilCoordinator.new()
	coordinator.setup(world)
	var pickup_position := Vector3i(2, 20, 2)
	var placed := VoxelWorldTestFixture.commit_place(world, pickup_position, BlockId.Type.ANVIL)
	_expect(placed != null, "test anvil could not be placed")
	var unarmed_action := load("res://items/actions/definitions/unarmed_mining.tres") as MiningActionDefinition
	var pickaxe_action := item_catalog.get_definition(&"stone_pickaxe").primary_action as MiningActionDefinition
	_expect(not unarmed_action.can_mine(anvil_block), "bare hands can mine an anvil")
	_expect(pickaxe_action.can_mine(anvil_block), "stone pickaxe cannot mine an anvil")
	var torch_position := pickup_position + Vector3i.RIGHT
	_expect(VoxelWorldTestFixture.commit_place(world, torch_position, BlockId.Type.TORCH, Vector3i.LEFT) != null, "test torch could not attach to the anvil")
	var mine_change := VoxelWorldTestFixture.commit_mine(world, pickup_position)
	var mine_batch: Array[BlockEdit] = [] if mine_change == null else mine_change.get_edits()
	_expect(mine_batch.size() == 2, "mining an anvil did not include its attached torch")
	var collected_item_ids: Array[StringName] = []
	for edit in mine_batch:
		var block_edit := edit as BlockEdit
		_expect(block_edit.is_success() and block_edit.is_mine(), "anvil mining emitted a non-mining edit")
		var drop_item_id := block_catalog.get_definition(block_edit.old_id).drop_item_id
		if not drop_item_id.is_empty():
			collected_item_ids.append(drop_item_id)
	_expect(collected_item_ids == [&"anvil", &"torch"], "anvil mining did not return both item drops")
	_expect(inventory_loadout.add_batch(collected_item_ids), "anvil mining drops could not be added to inventory")
	_expect(world.get_block_id_at(pickup_position) == BlockId.Type.AIR, "picked-up anvil remained in the world")
	_expect(world.get_block_id_at(torch_position) == BlockId.Type.AIR, "attached torch remained after mining the anvil")
	_expect(inventory.get_inventory_item_count(&"anvil") == 1, "picked-up anvil was not returned to inventory")
	_expect(inventory.get_inventory_item_count(&"torch") == 1, "attached torch was not returned to inventory")

	var full_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	InventoryTestFixture.restore_slot(full_inventory, 0, InventoryStack.new(
		&"stone_pickaxe",
		1,
		full_inventory.equipment_instance_factory.create(&"stone_pickaxe"),
	))
	for index in range(1, InventoryModel.FILLABLE_SIZE):
		InventoryTestFixture.restore_slot(full_inventory, index, InventoryStack.new(&"dirt_block", 99))
	var full_inventory_loadout := InventoryTestFixture.create_loadout(full_inventory)
	_expect(full_inventory_loadout != null, "full inventory loadout setup failed")
	_expect(VoxelWorldTestFixture.commit_place(world, pickup_position, BlockId.Type.ANVIL) != null, "capacity-test anvil could not be placed")
	_expect(VoxelWorldTestFixture.commit_place(world, torch_position, BlockId.Type.TORCH, Vector3i.LEFT) != null, "capacity-test torch could not attach to the anvil")
	var mining_executor := MiningActionExecutor.new()
	_expect(mining_executor.setup(full_inventory, full_inventory_loadout, unarmed_action, Callable()), "mining executor setup failed")
	mining_executor.bind_world(world)
	_expect(mining_executor.try_mine(pickup_position, full_inventory.create_selected_item_source()).is_empty(), "full inventory accepted mining drops")
	_expect(world.get_block_id_at(pickup_position) == BlockId.Type.ANVIL, "failed pickup changed the world")
	_expect(world.get_block_id_at(torch_position) == BlockId.Type.TORCH, "failed pickup removed the attached torch")

	var other_chunk_position := Vector3i(45, 20, 2)
	_expect(VoxelWorldTestFixture.commit_place(world, other_chunk_position, BlockId.Type.ANVIL) != null, "indexed-load anvil could not be placed")
	var chunk_renderer := AnvilRenderer.new()
	root.add_child(chunk_renderer)
	chunk_renderer.setup()
	_expect(chunk_renderer.load_anvils_for_chunk(0, 0, 20, world) == 1, "indexed chunk load did not load the local anvil")
	_expect(not chunk_renderer.anvil_instances.has(other_chunk_position), "indexed chunk load scanned an anvil from another chunk")

	renderer.queue_free()
	chunk_renderer.queue_free()
	cursor_interactor.free()
	targeting_view.free()
	await process_frame
	_finish()

func _test_cauldron(block_catalog: BlockCatalog, item_catalog: ItemCatalog, general_catalog: CraftingRecipeCatalog, cauldron_catalog: CraftingRecipeCatalog) -> void:
	var cauldron_block := block_catalog.get_definition(BlockId.Type.CAULDRON)
	var cauldron_item := item_catalog.get_definition(&"cauldron")
	var placement := cauldron_item.secondary_action as BlockPlacementActionDefinition
	_expect(BlockId.get_display_name(BlockId.Type.CAULDRON) == "Cauldron", "cauldron display name is incorrect")
	_expect(not BlockId.is_chunk_cube(BlockId.Type.CAULDRON), "cauldron is still baked into the cube mesh")
	_expect(BlockId.is_ao_solid(BlockId.Type.CAULDRON), "cauldron does not occlude ambient light")
	_expect(cauldron_block.crafting_station != null and cauldron_block.crafting_station.id == &"cauldron", "cauldron station metadata is invalid")
	_expect(cauldron_block.is_solid and not cauldron_block.is_opaque and cauldron_block.is_raycast_solid, "cauldron physical properties are invalid")
	_expect(cauldron_block.is_breakable and cauldron_block.mining_tool_tag == &"pickaxe" and cauldron_block.minimum_mining_power == 1, "cauldron does not use normal pickaxe mining")
	_expect(cauldron_block.drop_item_id == &"cauldron", "mined cauldron does not use the normal block drop")
	_expect(placement != null and placement.block == cauldron_block, "cauldron item does not place the canonical block")
	_expect(item_catalog.get_item_for_block(BlockId.Type.CAULDRON) == cauldron_item, "cauldron reverse block mapping is invalid")
	_expect(cauldron_item.max_stack == 1, "cauldron stack limit is not one")
	var icon_image := cauldron_item.icon.get_image()
	_expect(cauldron_item.icon.resource_path == "res://assets/textures/items/cauldron.png", "cauldron uses the wrong inventory icon")
	_expect(icon_image != null and icon_image.get_size() == Vector2i(16, 16), "cauldron inventory icon is not 16x16 pixel art")
	var icon_colors: Dictionary = {}
	var partial_alpha_pixels := 0
	if icon_image != null:
		for y in range(icon_image.get_height()):
			for x in range(icon_image.get_width()):
				var pixel := icon_image.get_pixel(x, y)
				if pixel.a > 0.0:
					icon_colors[Color(pixel.r, pixel.g, pixel.b, 1.0)] = true
				if pixel.a > 0.0 and pixel.a < 1.0:
					partial_alpha_pixels += 1
	_expect(icon_colors.size() <= 6, "cauldron inventory icon exceeds its pixel-art palette")
	_expect(partial_alpha_pixels == 0, "cauldron inventory icon contains anti-aliased pixels")
	_expect(general_catalog.has_definition(&"cauldron"), "cauldron is not craftable from general crafting")
	_expect(general_catalog.get_definition(&"cauldron").get_ingredient_counts() == {&"log_block": 3, &"stone_block": 2}, "cauldron recipe ingredients are incorrect")
	_expect(not general_catalog.has_definition(&"health_potion"), "health potion leaked into general crafting")
	_expect(cauldron_catalog.has_definition(&"health_potion"), "health potion is missing from cauldron crafting")
	_expect(cauldron_catalog.get_definition(&"health_potion").get_ingredient_counts() == {&"pumpkin": 2, &"apple": 2}, "health potion recipe uses the wrong ingredients")
	var health_potion := item_catalog.get_definition(&"health_potion")
	var potion_icon := health_potion.icon.get_image()
	_expect(health_potion.max_stack == 20, "health potion stack limit is incorrect")
	_expect(health_potion.icon.resource_path == "res://assets/textures/items/health_potion.png", "health potion uses the wrong inventory icon")
	_expect(potion_icon != null and potion_icon.get_size() == Vector2i(16, 16), "health potion inventory icon is not 16x16 pixel art")
	var potion_consumption := health_potion.secondary_action as ConsumableActionDefinition
	_expect(potion_consumption != null and is_equal_approx(potion_consumption.health_restore_fraction, 1.0), "health potion does not restore full health")

	var renderer := CauldronRenderer.new()
	root.add_child(renderer)
	renderer.setup()
	var position := Vector3i(3, 4, 5)
	var rendered := renderer.spawn_cauldron(position)
	_expect(rendered != null and rendered.position == Vector3(position), "cauldron renderer placed the model incorrectly")
	_expect(rendered.get_child_count() == 15, "cauldron model does not contain the expected tripod, campfire, and smoke parts")
	var body := rendered.get_node_or_null("Body") as MeshInstance3D
	var liquid := rendered.get_node_or_null("Liquid") as MeshInstance3D
	var support_left := rendered.get_node_or_null("SupportLeft") as MeshInstance3D
	var firewood_left := rendered.get_node_or_null("FirewoodLeft") as MeshInstance3D
	var firewood_right := rendered.get_node_or_null("FirewoodRight") as MeshInstance3D
	var fire := rendered.get_node_or_null("Fire") as GPUParticles3D
	var smoke := rendered.get_node_or_null("Smoke") as GPUParticles3D
	var fire_light := rendered.get_node_or_null("FireLight") as OmniLight3D
	_expect(body != null and body.mesh is CylinderMesh and (body.mesh as CylinderMesh).radial_segments == 8, "cauldron body is not low-poly")
	_expect(liquid != null and liquid.mesh is CylinderMesh, "cauldron liquid surface is missing")
	_expect(support_left != null and support_left.mesh is CylinderMesh and support_left.position.y > 0.4, "cauldron tripod support is missing")
	_expect(firewood_left != null and firewood_right != null and firewood_left.mesh is CylinderMesh and firewood_right.mesh is CylinderMesh, "cauldron campfire logs are missing")
	var model_bounds := AABB()
	var found_model_mesh := false
	for child in rendered.get_children():
		if not child is MeshInstance3D:
			continue
		var model_mesh := child as MeshInstance3D
		var child_bounds: AABB = model_mesh.transform * model_mesh.get_aabb()
		model_bounds = model_bounds.merge(child_bounds) if found_model_mesh else child_bounds
		found_model_mesh = true
	_expect(found_model_mesh and model_bounds.position.x >= 0.0 and model_bounds.position.y >= 0.0 and model_bounds.position.z >= 0.0, "cauldron model extends below or beside its occupied voxel")
	_expect(model_bounds.end.x <= 1.0 and model_bounds.end.y <= 1.0 and model_bounds.end.z <= 1.0, "cauldron model extends into a neighboring voxel")
	_expect(fire != null and fire.emitting and fire.amount == 12, "cauldron fire effect is missing")
	_expect(smoke != null and smoke.emitting and smoke.amount == 8, "cauldron smoke effect is missing")
	var smoke_mesh := smoke.draw_pass_1 as SphereMesh if smoke != null else null
	var smoke_material := smoke_mesh.material as StandardMaterial3D if smoke_mesh != null else null
	_expect(smoke_material != null and smoke_material.vertex_color_use_as_albedo and smoke_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "cauldron smoke does not use its fading particle colors")
	_expect(fire_light != null and fire_light.light_energy > 0.0 and fire_light.light_energy < 1.2 and fire_light.omni_range < 9.0, "cauldron fire light is not dimmer than a torch")
	renderer.set_hovered_cauldron(position)
	_expect(body.material_overlay != null and liquid.material_overlay != null, "hover highlight did not cover the full cauldron")
	renderer.set_hovered_cauldron(null)
	_expect(body.material_overlay == null and liquid.material_overlay == null, "cauldron hover highlight did not clear")
	renderer.set_placement_preview(Vector3i(6, 7, 8), true)
	_expect(renderer._placement_preview != null and renderer._placement_preview.visible, "cauldron placement preview was not shown")
	renderer.set_placement_preview(null, false)
	_expect(not renderer._placement_preview.visible, "cauldron placement preview did not hide")

	var texture_set := BlockTextureSet.new(block_catalog)
	var mesher := ChunkMesher.new(1, 4, 1, false, texture_set)
	var cache := PackedInt32Array()
	cache.resize(3 * 4 * 3)
	cache.fill(BlockId.Type.AIR)
	cache[1 * 4 * 3 + 1 * 3 + 1] = BlockId.Type.STONE
	cache[1 * 4 * 3 + 2 * 3 + 1] = BlockId.Type.CAULDRON
	var mesh_data = mesher.build_mesh_data_from_cache({
		"cache": cache,
		"origin_x": 0,
		"origin_z": 0,
		"size_x": 1,
		"size_z": 1,
		"size_y": 4,
		"cache_x": 3,
		"cache_z": 3,
	})
	_expect(mesh_data != null and (mesh_data["vertices"] as PackedVector3Array).size() == 24, "cauldron hid a face of the supporting terrain block")

	var world := VoxelWorld.new(20, 36, 5, 12.0, block_catalog)
	var pickup_position := Vector3i(2, 20, 2)
	_expect(VoxelWorldTestFixture.commit_place(world, pickup_position, BlockId.Type.CAULDRON) != null, "test cauldron could not be placed")
	var unarmed_action := load("res://items/actions/definitions/unarmed_mining.tres") as MiningActionDefinition
	var pickaxe_action := item_catalog.get_definition(&"stone_pickaxe").primary_action as MiningActionDefinition
	_expect(not unarmed_action.can_mine(cauldron_block), "bare hands can mine a cauldron")
	_expect(pickaxe_action.can_mine(cauldron_block), "stone pickaxe cannot mine a cauldron")
	var mine_change := VoxelWorldTestFixture.commit_mine(world, pickup_position)
	var mine_batch: Array[BlockEdit] = [] if mine_change == null else mine_change.get_edits()
	_expect(mine_batch.size() == 1 and (mine_batch[0] as BlockEdit).is_success(), "cauldron could not be mined normally")
	_expect(block_catalog.get_definition((mine_batch[0] as BlockEdit).old_id).drop_item_id == &"cauldron", "mined cauldron returned the wrong item")

	var other_chunk_position := Vector3i(45, 20, 2)
	_expect(VoxelWorldTestFixture.commit_place(world, pickup_position, BlockId.Type.CAULDRON) != null, "indexed-load cauldron could not be placed")
	_expect(VoxelWorldTestFixture.commit_place(world, other_chunk_position, BlockId.Type.CAULDRON) != null, "other-chunk cauldron could not be placed")
	var chunk_renderer := CauldronRenderer.new()
	root.add_child(chunk_renderer)
	chunk_renderer.setup()
	_expect(chunk_renderer.load_cauldrons_for_chunk(0, 0, 20, world) == 1, "indexed chunk load did not load the local cauldron")
	_expect(not chunk_renderer.cauldron_instances.has(other_chunk_position), "indexed chunk load scanned a cauldron from another chunk")
	renderer.queue_free()
	chunk_renderer.queue_free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("ANVIL_SYSTEM PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("[anvil_system] %s" % failure)
	quit(1)
