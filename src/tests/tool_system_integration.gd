extends SceneTree

var _errors: Array[String] = []
var _player: PlayerMotor
var _camera: Camera3D
var _inventory: InventoryModel
var _interactor: PlayerInteractor
var _input_buffer: InputBuffer
var _voxel_world: VoxelWorld
var _world_entity_coordinator: WorldEntityCoordinator
var _combat: MeleeCombatCoordinator
var _hotbar: InventoryHotbar
var _stone_pos := Vector3i(1, 0, 0)
var _grass_pos := Vector3i(2, 0, 0)
var _copper_pos := Vector3i(3, 0, 0)
var _till_grass_pos := Vector3i(1, 0, 1)
var _till_dirt_pos := Vector3i(2, 0, 1)
var _covered_dirt_pos := Vector3i(3, 0, 1)
var _nonsoil_pos := Vector3i(4, 0, 1)
var _melee_attack_directions: Array[int] = []
var _melee_attack_facings: Array[Vector3] = []
var _soil_tilled_count: int = 0

func _init():
	call_deferred("_run")

func _position_ready(_position: Vector3) -> bool:
	return true

func _run():
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	_expect(block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog.validate(block_catalog), "item catalog invalid")
	var stone_pickaxe := item_catalog.get_definition(&"stone_pickaxe")
	_expect(stone_pickaxe.max_stack == 1, "stone pickaxe stack limit changed")
	_expect(stone_pickaxe.primary_action is MiningActionDefinition, "stone pickaxe primary action is not mining")
	_expect(stone_pickaxe.secondary_action == null, "stone pickaxe unexpectedly has a secondary action")
	var pickaxe_action := stone_pickaxe.primary_action as MiningActionDefinition
	var pickaxe_stat := pickaxe_action.get_tool_stat(&"pickaxe")
	_expect(pickaxe_stat != null and pickaxe_stat.power == 1 and is_equal_approx(pickaxe_stat.speed_multiplier, 1.5), "stone pickaxe mining stats changed")
	var copper_pickaxe := item_catalog.get_definition(&"copper_pickaxe")
	var copper_pickaxe_action := copper_pickaxe.primary_action as MiningActionDefinition
	var copper_pickaxe_stat := copper_pickaxe_action.get_tool_stat(&"pickaxe")
	_expect(copper_pickaxe_stat != null and copper_pickaxe_stat.power == 2 and is_equal_approx(copper_pickaxe_stat.speed_multiplier, 2.0), "copper pickaxe mining stats changed")
	_expect(stone_pickaxe.icon.resource_path == "res://assets/textures/tools/pickaxe/stone_pickaxe.png", "stone pickaxe uses the wrong texture")
	var stone_pickaxe_image := stone_pickaxe.icon.get_image()
	var copper_pickaxe_image := copper_pickaxe.icon.get_image()
	_expect(stone_pickaxe_image.get_size() == Vector2i(16, 16), "stone pickaxe texture is not 16x16")
	_expect(stone_pickaxe_image.get_pixel(3, 1).to_html() == "d8dde2ff", "stone pickaxe head is not light gray")
	_expect(stone_pickaxe_image.get_pixel(5, 5) == copper_pickaxe_image.get_pixel(5, 5), "stone pickaxe recolor changed the wooden handle")
	var torch := item_catalog.get_definition(&"torch")
	var log := item_catalog.get_definition(&"log_block")
	_expect(torch.icon.resource_path == "res://assets/textures/items/torch.png", "torch uses the wrong inventory texture")
	_expect(torch.icon != log.icon, "torch still reuses the wood inventory texture")
	_expect(torch.icon.get_image().get_size() == Vector2i(16, 16), "torch inventory texture is not 16x16")
	var chest_item := item_catalog.get_definition(&"chest")
	var chest_block := block_catalog.get_definition(BlockId.Type.CHEST)
	var chest_placement := chest_item.secondary_action as BlockPlacementActionDefinition
	_expect(BlockId.get_display_name(BlockId.Type.CHEST) == "Chest", "chest block display name is incorrect")
	_expect(BlockId.is_chunk_cube(BlockId.Type.CHEST), "chest is not rendered as a chunk cube")
	_expect(chest_block.is_solid and chest_block.is_opaque and chest_block.is_raycast_solid, "chest is not a solid targetable block")
	_expect(chest_block.is_breakable and chest_block.drop_item_id == &"chest", "chest mining/drop configuration is invalid")
	_expect(chest_placement != null and chest_placement.block == chest_block, "chest item does not place the canonical chest block")
	_expect(item_catalog.get_item_for_block(BlockId.Type.CHEST) == chest_item, "chest reverse block mapping is incorrect")
	_expect(chest_item.icon.resource_path == "res://assets/textures/blocks/chest_front.png", "chest inventory icon does not reuse the front texture")
	_expect(chest_item.icon == chest_block.front_texture, "chest inventory and block front do not share the same texture")
	var chest_icon_image := chest_item.icon.get_image()
	_expect(chest_icon_image.get_size() == Vector2i(16, 16), "chest inventory icon is not 16x16")
	_expect(chest_block.top_texture.resource_path == "res://assets/textures/blocks/chest_top.png", "chest uses the wrong top texture")
	_expect(chest_block.side_texture.resource_path == "res://assets/textures/blocks/chest_side.png", "chest uses the wrong side texture")
	_expect(chest_block.front_texture.resource_path == "res://assets/textures/blocks/chest_front.png", "chest uses the wrong front texture")
	_expect(chest_block.front_texture != chest_block.side_texture, "chest front still shares the non-locking side texture")
	_expect(chest_block.top_texture.get_image().get_size() == Vector2i(16, 16), "chest top texture is not 16x16")
	_expect(chest_block.side_texture.get_image().get_size() == Vector2i(16, 16), "chest side texture is not 16x16")
	_expect(chest_block.front_texture.get_image().get_size() == Vector2i(16, 16), "chest front texture is not 16x16")
	var chest_top_image := chest_block.top_texture.get_image()
	var chest_front_image := chest_block.front_texture.get_image()
	var chest_side_image := chest_block.side_texture.get_image()
	var chest_front_colors: Dictionary[Color, bool] = {}
	var chest_side_colors: Dictionary[Color, bool] = {}
	var chest_top_colors: Dictionary[Color, bool] = {}
	for texture_y in range(16):
		for texture_x in range(16):
			chest_front_colors[chest_front_image.get_pixel(texture_x, texture_y)] = true
			chest_side_colors[chest_side_image.get_pixel(texture_x, texture_y)] = true
			chest_top_colors[chest_top_image.get_pixel(texture_x, texture_y)] = true
	_expect(chest_front_colors.size() <= 11, "chest front texture has regressed to an overly detailed palette")
	_expect(chest_side_colors.size() <= 9, "chest side texture has regressed to an overly detailed palette")
	_expect(chest_top_colors.size() <= 6, "chest top texture has regressed to an overly detailed palette")
	var chest_block_lid_sum := Color(0, 0, 0, 0)
	var chest_block_lid_pixels := 0
	for texture_y in range(1, 6):
		for texture_x in range(1, 15):
			chest_block_lid_sum += chest_side_image.get_pixel(texture_x, texture_y)
			chest_block_lid_pixels += 1
	var average_chest_block_lid := chest_block_lid_sum / chest_block_lid_pixels
	_expect(average_chest_block_lid.get_luminance() >= 0.28 and average_chest_block_lid.get_luminance() <= 0.34, "chest lid is not midway between the previous dark and light treatments")
	_expect(average_chest_block_lid.r >= average_chest_block_lid.g * 1.5, "chest lid is not warm brown")
	var chest_top_plank_sum := Color(0, 0, 0, 0)
	var chest_top_plank_pixels := 0
	for texture_y in [1, 2, 3, 4, 6, 7, 8, 9, 11, 12, 13, 14]:
		for texture_x in range(1, 15):
			chest_top_plank_sum += chest_top_image.get_pixel(texture_x, texture_y)
			chest_top_plank_pixels += 1
	var average_chest_top_plank := chest_top_plank_sum / chest_top_plank_pixels
	_expect(absf(average_chest_top_plank.get_luminance() - average_chest_block_lid.get_luminance()) <= 0.01, "chest top planks do not match the vertical lid brightness")
	var chest_lid_colors: Dictionary[Color, bool] = {}
	for texture_y in range(7):
		for texture_x in range(16):
			chest_lid_colors[chest_side_image.get_pixel(texture_x, texture_y)] = true
	for texture_y in range(16):
		for texture_x in range(16):
			_expect(chest_lid_colors.has(chest_top_image.get_pixel(texture_x, texture_y)), "chest top texture uses a color outside the side lid palette")
	for texture_x in range(1, 15):
		var lid_seam_pixel := chest_side_image.get_pixel(texture_x, 6)
		_expect(chest_top_image.get_pixel(texture_x, 5) == lid_seam_pixel, "chest top first horizontal plank seam does not match the side lid")
		_expect(chest_top_image.get_pixel(texture_x, 10) == lid_seam_pixel, "chest top second horizontal plank seam does not match the side lid")
	var chest_face_differences: Array[Vector2i] = []
	for texture_y in range(16):
		for texture_x in range(16):
			if chest_front_image.get_pixel(texture_x, texture_y) != chest_side_image.get_pixel(texture_x, texture_y):
				chest_face_differences.append(Vector2i(texture_x, texture_y))
	var expected_latch_pixels: Array[Vector2i] = [Vector2i(7, 6), Vector2i(8, 6), Vector2i(7, 7), Vector2i(8, 7)]
	_expect(chest_face_differences == expected_latch_pixels, "chest side does not exactly match the front apart from its four centered latch pixels")
	var chest_texture_set := BlockTextureSet.new(block_catalog)
	var chest_side_layer := chest_texture_set.side_layers[BlockId.Type.CHEST]
	var chest_front_layer := chest_texture_set.front_layers[BlockId.Type.CHEST]
	_expect(chest_side_layer != chest_front_layer, "chest front and side resolved to the same texture layer")
	_expect(chest_texture_set.front_layers[BlockId.Type.STONE] == chest_texture_set.side_layers[BlockId.Type.STONE], "ordinary blocks did not fall back to their side texture")
	var chest_cache := PackedInt32Array()
	chest_cache.resize(18)
	chest_cache.fill(-1)
	chest_cache[7] = BlockId.Type.CHEST
	var chest_mesh_data = ChunkMesher.new(1, 2, 0, false, chest_texture_set).build_mesh_data_from_cache({
		"cache": chest_cache,
		"origin_x": 0,
		"origin_z": 0,
		"size_x": 1,
		"size_z": 1,
		"size_y": 2,
		"cache_x": 3,
		"cache_z": 3,
	})
	_expect(chest_mesh_data != null, "chest mesh data was not generated")
	if chest_mesh_data != null:
		var chest_normals := chest_mesh_data["normals"] as PackedVector3Array
		var chest_layers := chest_mesh_data["texture_layers"] as PackedVector2Array
		var front_vertex_count := 0
		for vertex_index in range(chest_normals.size()):
			var normal := chest_normals[vertex_index]
			var layer := roundi(chest_layers[vertex_index].x)
			if normal == Vector3(0, 0, -1):
				front_vertex_count += 1
				_expect(layer == chest_front_layer, "chest north/front face did not use the lock texture")
			elif is_zero_approx(normal.y):
				_expect(layer == chest_side_layer, "a non-front chest face used the lock texture")
		_expect(front_vertex_count == 4, "chest mesh did not contain exactly one front face")
	var sword := item_catalog.get_definition(&"copper_sword")
	_expect(sword.max_stack == 1, "sword stack limit changed")
	_expect(sword.primary_action is MeleeAttackActionDefinition, "sword primary action is not melee")
	_expect(sword.secondary_action == null, "sword unexpectedly has a secondary action")
	var sword_action := sword.primary_action as MeleeAttackActionDefinition
	_expect(is_equal_approx(sword_action.attack_profile.duration, 0.48), "sword attack duration changed")
	_expect(is_equal_approx(sword_action.chain_input_window, 0.26), "sword chain input window changed")
	var hoe := item_catalog.get_definition(&"copper_hoe")
	_expect(hoe.max_stack == 1, "copper hoe stack limit is not one")
	_expect(hoe.primary_action is TillingActionDefinition and hoe.secondary_action == null, "copper hoe action configuration is incorrect")
	var tilling_action := hoe.primary_action as TillingActionDefinition
	var farmland := block_catalog.get_definition(BlockId.Type.FARMLAND_DRY)
	_expect(tilling_action.can_till(block_catalog.get_definition(BlockId.Type.GRASS)), "copper hoe cannot till grass")
	_expect(tilling_action.can_till(block_catalog.get_definition(BlockId.Type.DIRT)), "copper hoe cannot till dirt")
	_expect(not tilling_action.can_till(block_catalog.get_definition(BlockId.Type.STONE)), "copper hoe can till stone")
	_expect(tilling_action.result_block == farmland, "copper hoe does not use the canonical dry farmland block")
	_expect(farmland.drop_item_id == &"dirt_block", "dry farmland does not drop dirt")
	_expect(farmland.top_texture.resource_path == "res://assets/textures/blocks/farmland_dry.png", "dry farmland uses the wrong top texture")
	_expect(farmland.side_texture.resource_path == "res://assets/textures/blocks/dirt.png", "dry farmland sides are not dirt")
	_expect(hoe.icon.resource_path == "res://assets/textures/tools/hoe/copper_hoe.png", "copper hoe uses the wrong inventory icon")
	_expect(hoe.icon.get_image().get_size() == Vector2i(64, 64), "copper hoe inventory icon is not 64x64")
	_expect(hoe.equip_audio != null and hoe.equip_audio.streams.size() == 3, "copper hoe equip audio is not configured")
	_expect(hoe.held_scene != null, "copper hoe held scene is missing")
	var pumpkin := item_catalog.get_definition(&"pumpkin")
	_expect(pumpkin.primary_action == null and pumpkin.secondary_action is ConsumableActionDefinition, "pumpkin action configuration is incorrect")
	_expect(is_equal_approx((pumpkin.secondary_action as ConsumableActionDefinition).health_restore_fraction, 1.0), "pumpkin does not restore full health")
	_expect(pumpkin.consume_audio != null and pumpkin.consume_audio.streams.size() == 1, "pumpkin consume audio is not configured")
	var hoe_held := hoe.held_scene.instantiate() as Node3D
	var hoe_model := hoe_held.get_node_or_null("Model") as Node3D
	_expect(hoe_model != null and hoe_model.scale.is_equal_approx(Vector3.ONE * 4.6875), "copper hoe held scale is incorrect")
	hoe_held.free()
	var stone := block_catalog.get_definition(BlockId.Type.STONE)
	var copper := block_catalog.get_definition(BlockId.Type.COPPER)
	var unarmed_action := load("res://items/actions/definitions/unarmed_mining.tres") as MiningActionDefinition
	_expect(stone.mining_tool_tag == &"pickaxe" and stone.minimum_mining_power == 0, "stone is not hand-mineable")
	_expect(stone.drop_item_id == &"stone_block", "stone drop item changed")
	_expect(unarmed_action.can_mine(stone), "unarmed action cannot mine stone")
	_expect(unarmed_action.can_mine(chest_block), "unarmed action cannot mine a chest")
	_expect(copper.mining_tool_tag == &"pickaxe" and copper.minimum_mining_power == 1, "copper mining requirement changed")
	_expect(not unarmed_action.can_mine(copper), "unarmed action can mine copper")
	_expect(pickaxe_action.can_mine(copper), "stone pickaxe cannot mine copper")
	_expect(copper_pickaxe_action.can_mine(copper), "copper pickaxe cannot mine copper")
	_expect(copper_pickaxe_action.get_mine_duration(copper) < pickaxe_action.get_mine_duration(copper), "copper pickaxe is not faster than stone pickaxe")
	var grass_placement := item_catalog.get_definition(&"grass_block").secondary_action
	_expect(not item_catalog._is_supported_primary_action(grass_placement), "placement action was accepted as a primary action")
	_expect(not item_catalog._is_supported_secondary_action(pickaxe_action), "mining action was accepted as a secondary action")
	_expect(item_catalog._is_supported_secondary_action(pumpkin.secondary_action), "consumable action was rejected as a secondary action")
	for definition in item_catalog.definitions:
		if definition.held_scene == null:
			continue
		var held_root := definition.held_scene.instantiate()
		_expect(held_root is Node3D, "held scene root is not Node3D for %s" % definition.id)
		held_root.free()

	_inventory = InventoryModel.new(item_catalog)
	_inventory.setup_starter()
	_expect(_inventory.get_slot(0) == null, "new inventory still grants a copper pickaxe")
	_expect(_inventory.get_slot(3) is InventoryStack and _inventory.get_slot(3).item_id == &"copper_sword", "starter sword missing")
	var test_totem_slot := InventoryModel.FILLABLE_SIZE - 1
	_expect(_inventory.get_slot(test_totem_slot) is InventoryStack and _inventory.get_slot(test_totem_slot).item_id == &"test_totem", "test totem is not in the starter backpack")
	var encoded := _inventory.to_dict()
	var restored := InventoryModel.new(item_catalog)
	_expect(restored.from_dict(encoded), "typed inventory did not restore")
	_expect(restored.get_slot(0) == null, "restored new inventory gained a copper pickaxe")
	_expect(restored.get_slot(3) is InventoryStack and restored.get_slot(3).item_id == &"copper_sword", "restored sword missing")
	_expect(restored.get_slot(test_totem_slot) is InventoryStack and restored.get_slot(test_totem_slot).item_id == &"test_totem", "restored test totem missing")
	_expect(restored.starter_item_migration_version == InventoryModel.STARTER_ITEM_MIGRATION_VERSION, "starter item migration version did not restore")
	var existing_pickaxe_encoded := encoded.duplicate(true)
	existing_pickaxe_encoded["regions"]["hotbar"][0] = {
		"item_id": "copper_pickaxe",
		"count": 1,
		"socketed_rune_ids": [],
	}
	existing_pickaxe_encoded.erase("starter_item_migration_version")
	var existing_pickaxe_save := InventoryModel.new(item_catalog)
	_expect(existing_pickaxe_save.from_dict(existing_pickaxe_encoded), "existing copper pickaxe save did not restore")
	_expect(existing_pickaxe_save.migrate_starter_items(), "existing copper pickaxe save did not migrate")
	_expect(existing_pickaxe_save.get_slot(0) != null and existing_pickaxe_save.get_slot(0).item_id == &"copper_pickaxe", "existing copper pickaxe was not preserved")
	var legacy_encoded := encoded.duplicate(true)
	legacy_encoded["regions"]["hotbar"][3] = null
	legacy_encoded.erase("starter_item_migration_version")
	var legacy := InventoryModel.new(item_catalog)
	_expect(legacy.from_dict(legacy_encoded), "legacy inventory did not restore")
	_expect(legacy.migrate_starter_items(), "legacy inventory could not receive starter items")
	_expect(legacy.get_inventory_item_count(&"copper_pickaxe") == 0, "legacy migration granted a copper pickaxe")
	_expect(legacy.get_inventory_item_count(&"copper_sword") == 1, "legacy migration did not restore the sword")
	var restore_game := Game.new()
	restore_game.item_catalog = item_catalog
	restore_game.inventory_model = InventoryModel.new(item_catalog)
	restore_game._save_data = {"inventory": legacy_encoded}
	restore_game._restore_inventory()
	_expect(restore_game.inventory_model.get_inventory_item_count(&"copper_pickaxe") == 0, "game restore granted a copper pickaxe")
	_expect(restore_game.inventory_model.get_inventory_item_count(&"copper_sword") == 1, "game restore did not execute sword migration")
	restore_game.free()
	var new_game := Game.new()
	new_game.item_catalog = item_catalog
	new_game.inventory_model = InventoryModel.new(item_catalog)
	new_game._save_data = {"inventory": null}
	new_game._restore_inventory()
	for index in range(new_game.inventory_model.size):
		_expect(new_game.inventory_model.get_slot(index) == null, "new world inventory contains an item in slot %d" % index)
	_expect(new_game.inventory_model.starter_item_migration_version == InventoryModel.STARTER_ITEM_MIGRATION_VERSION, "new world inventory can receive legacy starter items after reload")
	var reloaded_new_world := InventoryModel.new(item_catalog)
	_expect(reloaded_new_world.from_dict(new_game.inventory_model.to_dict()), "new world inventory did not survive save serialization")
	_expect(reloaded_new_world.migrate_starter_items(), "new world inventory migration state did not survive reload")
	for index in range(reloaded_new_world.size):
		_expect(reloaded_new_world.get_slot(index) == null, "reloaded new world gained an item in slot %d" % index)
	new_game.free()
	for index in range(legacy.size):
		if legacy.slots[index] != null and legacy.slots[index].item_id == &"copper_sword":
			legacy.slots[index] = null
			break
	_expect(legacy.migrate_starter_items(), "completed starter migration did not remain complete")
	_expect(legacy.get_inventory_item_count(&"copper_sword") == 0, "completed starter migration re-granted a removed sword")
	var crowded := InventoryModel.new(item_catalog)
	var grass_id := item_catalog.get_item_for_block(BlockId.Type.GRASS).id
	for index in range(InventoryModel.HOTBAR_SIZE):
		crowded.slots[index] = InventoryStack.new(grass_id, index + 1)
	_expect(crowded.ensure_item(&"copper_pickaxe"), "full hotbar could not receive a pickaxe")
	_expect(crowded.get_slot(0).item_id == &"copper_pickaxe" and crowded.get_slot(InventoryModel.HOTBAR_SIZE).count == 1, "adding a pickaxe lost its displaced stack")
	var full := InventoryModel.new(item_catalog)
	for index in range(InventoryModel.FILLABLE_SIZE):
		full.slots[index] = InventoryStack.new(grass_id, 1)
	_expect(not full.migrate_starter_items(), "full inventory unexpectedly accepted starter items")
	for index in range(InventoryModel.FILLABLE_SIZE, InventoryModel.TOTAL_SIZE):
		_expect(full.slots[index] == null, "starter migration used reserved equipment slot %d" % index)
	_inventory.slots[0] = InventoryStack.new(&"stone_pickaxe", 1)

	_voxel_world = VoxelWorld.new(20, 36, 5, 12.0, block_catalog)
	_voxel_world.restore_block_edits({
		_stone_pos: BlockId.Type.STONE,
		_grass_pos: BlockId.Type.GRASS,
		_copper_pos: BlockId.Type.COPPER,
		_till_grass_pos: BlockId.Type.GRASS,
		_till_dirt_pos: BlockId.Type.DIRT,
		_covered_dirt_pos: BlockId.Type.DIRT,
		_covered_dirt_pos + Vector3i.UP: BlockId.Type.DIRT,
		_nonsoil_pos: BlockId.Type.SAND,
	}, {})
	var chest_position := Vector3i(4, 20, 0)
	var chest_place_edit := _voxel_world.try_place_block(chest_position, BlockId.Type.CHEST)
	_expect(chest_place_edit.is_success() and chest_place_edit.new_id == BlockId.Type.CHEST, "voxel world rejected chest placement")
	_expect(_voxel_world.get_block_id_at(chest_position) == BlockId.Type.CHEST, "placed chest is missing from the voxel world")
	_expect(_voxel_world.snapshot_block_edits()["placed"].get(chest_position, BlockId.Type.AIR) == BlockId.Type.CHEST, "placed chest was not persisted as a world edit")
	var chest_mine_edits := _voxel_world.try_mine_block(chest_position)
	_expect(chest_mine_edits.size() == 1 and chest_mine_edits[0].old_id == BlockId.Type.CHEST, "placed chest could not be mined")
	_expect(_voxel_world.get_block_id_at(chest_position) == BlockId.Type.AIR, "mined chest remained in the voxel world")
	_player = (load("res://player/player.tscn") as PackedScene).instantiate() as PlayerMotor
	root.add_child(_player)
	_player.global_position = Vector3.ZERO
	_camera = Camera3D.new()
	root.add_child(_camera)
	_camera.position = Vector3(0, 6, 6)
	_camera.look_at_from_position(_camera.position, Vector3.ZERO)
	_camera.current = true
	await process_frame
	_input_buffer = InputBuffer.new()
	_interactor = _player.interactor
	_world_entity_coordinator = WorldEntityCoordinator.new()
	root.add_child(_world_entity_coordinator)
	_world_entity_coordinator.setup(load("res://entities/entity_catalog.tres") as EntityCatalog, _voxel_world, 1337, _position_ready)
	_combat = MeleeCombatCoordinator.new()
	root.add_child(_combat)
	var player_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	var inventory_stat_coordinator := InventoryStatCoordinator.new()
	_expect(inventory_stat_coordinator.setup(_inventory, player_stats), "inventory stat coordinator setup failed")
	_combat.setup(_voxel_world, _player, player_stats, _world_entity_coordinator.get_runtime())
	_interactor.setup(_camera, _player, _inventory, _input_buffer, _combat, _world_entity_coordinator.get_runtime())
	_interactor.bind_space(_voxel_world, _voxel_world)
	_interactor.melee_attack_started.connect(_on_melee_attack_started)
	_interactor.soil_tilled.connect(_on_soil_tilled)
	_interactor.set_physics_process(false)
	_player.animation_driver.setup(_player, _interactor)
	_player.animation_driver.set_process(false)
	_player.held_item_view.setup(_inventory)
	_hotbar = (load("res://inventory/ui/inventory_hotbar.tscn") as PackedScene).instantiate() as InventoryHotbar
	root.add_child(_hotbar)
	_hotbar.setup(_inventory, inventory_stat_coordinator, ItemProficiency.new(item_catalog))
	await process_frame
	_expect(_player.held_item_view.held_node is PixelExtrudedItem, "pickaxe held scene missing")
	_expect(is_equal_approx(_player.held_item_view.rotation.x, PI * 0.25), "held-item socket does not pitch items downward")
	var held_pickaxe := _player.held_item_view.held_node as PixelExtrudedItem
	_expect(held_pickaxe.texture == stone_pickaxe.icon, "held stone pickaxe used the wrong texture")
	_expect(is_equal_approx(held_pickaxe.rotation.y, PI * 0.5), "pickaxe does not point toward the player's front")
	_expect(held_pickaxe.mesh_instance.mesh.get_surface_count() == 1, "pickaxe mesh surface count changed")
	var pickaxe_material := held_pickaxe.mesh_instance.mesh.surface_get_material(0) as StandardMaterial3D
	_expect(pickaxe_material.cull_mode == BaseMaterial3D.CULL_BACK, "pickaxe mesh still renders hidden backfaces")
	var pickaxe_arrays := held_pickaxe.mesh_instance.mesh.surface_get_arrays(0)
	var pickaxe_vertices := pickaxe_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var pickaxe_normals := pickaxe_arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var pickaxe_winding_valid := pickaxe_vertices.size() == pickaxe_normals.size()
	for index in range(0, pickaxe_vertices.size(), 3):
		var triangle_normal := (pickaxe_vertices[index + 1] - pickaxe_vertices[index]).cross(pickaxe_vertices[index + 2] - pickaxe_vertices[index]).normalized()
		if triangle_normal.dot(pickaxe_normals[index]) > -0.99:
			pickaxe_winding_valid = false
			break
	_expect(pickaxe_winding_valid, "pickaxe triangle winding does not face its supplied normals")
	var one_pixel_pickaxe := PixelItemMeshBuilder.build(held_pickaxe.texture, held_pickaxe.grip_pixel, held_pickaxe.max_dimension, 1.0)
	_expect(is_equal_approx(held_pickaxe.mesh_instance.mesh.get_aabb().size.z, one_pixel_pickaxe.get_aabb().size.z * 2.0), "pickaxe mesh is not two pixels thick")

	_push_hotbar_key(KEY_4)
	await process_frame
	_expect(_inventory.selected_slot == 3, "sword hotbar selection failed")
	_expect(_player.held_item_view.held_node is PixelExtrudedItem, "sword held scene missing")
	var held_sword := _player.held_item_view.held_node as PixelExtrudedItem
	_expect(held_sword.texture == sword.icon, "sword held texture changed")
	_expect(is_equal_approx(held_sword.rotation.y, PI * 0.5), "sword does not point toward the player's front")
	var one_pixel_sword := PixelItemMeshBuilder.build(held_sword.texture, held_sword.grip_pixel, held_sword.max_dimension, 1.0)
	_expect(is_equal_approx(held_sword.mesh_instance.mesh.get_aabb().size.z, one_pixel_sword.get_aabb().size.z), "sword mesh thickness changed")
	_expect(_interactor.get_selected_primary_action() == sword_action, "sword melee action was not selected")
	var resting_socket_position := _player.held_item_view.position
	var resting_socket_rotation := _player.held_item_view.rotation
	var attack_mouse_position := _interactor.get_viewport().get_mouse_position()
	var attack_ray_origin := _camera.project_ray_origin(attack_mouse_position)
	var attack_ray_direction := _camera.project_ray_normal(attack_mouse_position).normalized()
	var player_center := _player.global_position + Vector3.UP * (_player.player_height * 0.5)
	var attack_cursor_position: Variant = Plane(Vector3.UP, player_center.y).intersects_ray(attack_ray_origin, attack_ray_direction)
	_expect(attack_cursor_position is Vector3, "sword cursor ray did not reach the player-facing plane")
	var expected_attack_facing := ((attack_cursor_position as Vector3) - player_center).normalized()
	_player.model_root.rotation.y = atan2(-expected_attack_facing.x, -expected_attack_facing.z)
	_push_primary(true)
	await process_frame
	_input_buffer.poll()
	_interactor._handle_item_actions(0.0)
	_expect(_melee_attack_directions == [-1], "single sword click did not start left-to-right")
	_expect(_melee_attack_facings.size() == 1 and _melee_attack_facings[0].dot(expected_attack_facing) > 0.999, "player did not face the mouse before the sword swing started")
	_expect(_player.animation_driver.animator._attacking, "sword attack did not reach the animation driver")
	_expect(is_equal_approx(_interactor.melee_attack_timer, sword_action.attack_profile.cooldown), "sword attack timer changed")
	_player.on_ground = true
	_player.animation_driver._process(sword_action.attack_profile.duration * 0.5)
	_expect(_player.held_item_view.position.is_equal_approx(resting_socket_position + sword_action.held_position_offset), "sword did not move toward the wrist during attack")
	_expect(is_equal_approx(_player.held_item_view.rotation.x + _player.animation_driver.animator.right_arm_action.rotation.x, resting_socket_rotation.x), "sword did not flatten against the attack arm pitch")
	_interactor._handle_item_actions(sword_action.attack_profile.duration * 0.5)
	_expect(_melee_attack_directions.size() == 1, "holding primary use repeated the sword attack")
	_push_primary(false)
	await process_frame
	_input_buffer.poll()
	_push_primary(true)
	await process_frame
	_input_buffer.poll()
	_interactor._handle_item_actions(0.0)
	_expect(_melee_attack_directions.size() == 1 and _interactor.melee_attack_queue == 1, "second sword click was not queued")
	_push_primary(false)
	await process_frame
	_input_buffer.poll()
	_interactor._handle_item_actions(sword_action.attack_profile.duration * 0.5)
	_expect(_melee_attack_directions == [-1, 1], "chained sword click did not reverse direction")
	_expect(_player.animation_driver.animator._attack_direction == 1, "reversed sword swing did not reach the animator")
	_expect(not _interactor.is_mining, "sword attack started mining")
	_interactor._handle_item_actions(sword_action.attack_profile.duration)
	_push_primary(true)
	await process_frame
	_input_buffer.poll()
	_interactor._handle_item_actions(0.0)
	_expect(_melee_attack_directions == [-1, 1, -1], "isolated sword click did not reset to left-to-right")
	_push_primary(false)
	await process_frame
	_input_buffer.poll()
	for _click in range(6):
		_input_buffer.primary_use_just = true
		_interactor._handle_item_actions(0.0)
	_expect(_interactor.melee_attack_queue == 1, "rapid sword clicks accumulated an attack backlog")
	_interactor._handle_item_actions(sword_action.chain_input_window + 0.01)
	_expect(_interactor.melee_attack_queue == 0, "stale sword chain input did not expire")
	_interactor._handle_item_actions(sword_action.attack_profile.duration)
	_expect(_melee_attack_directions == [-1, 1, -1], "expired sword clicks were flushed as attacks")
	_player.animation_driver._process(sword_action.attack_profile.duration)
	_expect(_player.held_item_view.position.is_equal_approx(resting_socket_position), "sword position did not recover after attacking")
	_expect(_player.held_item_view.rotation.is_equal_approx(resting_socket_rotation), "sword rotation did not recover after attacking")
	_push_primary(true)
	await process_frame
	_input_buffer.poll()
	_interactor._handle_item_actions(0.0)
	_player.animation_driver._process(sword_action.attack_profile.duration * 0.5)
	_expect(_player.animation_driver.animator._attacking, "mid-swing cancellation setup did not start")
	_push_hotbar_key(KEY_1)
	await process_frame
	_player.animation_driver._process(0.0)
	_expect(not _player.animation_driver.animator._attacking, "switching tools did not cancel the sword animation")
	_expect(_player.animation_driver._active_attack_action == null, "switching tools retained the sword presentation action")
	_expect(_player.held_item_view.held_node is PixelExtrudedItem, "mid-swing switch did not display the pickaxe")
	_expect(_player.held_item_view.position.is_equal_approx(resting_socket_position), "mid-swing switch retained the sword position")
	_expect(_player.held_item_view.rotation.is_equal_approx(resting_socket_rotation), "mid-swing switch retained the sword rotation")
	_interactor._handle_item_actions(0.0)
	_push_primary(false)
	await process_frame
	_input_buffer.poll()

	_push_hotbar_key(KEY_2)
	await process_frame
	_expect(_inventory.selected_slot == 1, "grass hotbar selection failed")
	_expect(_player.held_item_view.held_node == null, "held pickaxe did not clear")
	var unarmed := _interactor.get_selected_primary_action() as MiningActionDefinition
	_expect(unarmed != null and unarmed.can_mine(stone), "unarmed mining cannot mine stone")
	_expect(not unarmed.can_mine(copper), "unarmed mining bypasses copper requirement")
	_prepare_target(_stone_pos, unarmed)
	_expect(_interactor.can_primary_target, "unarmed action cannot target stone")
	_push_primary(true)
	await process_frame
	_input_buffer.poll()
	_interactor._handle_item_actions(0.0)
	_interactor._handle_item_actions(0.71)
	_expect(_voxel_world.get_block_id_at(_stone_pos) == BlockId.Type.AIR, "unarmed action did not mine stone")
	_expect(_inventory.get_slot(2).count == 9, "stone drop did not use explicit block drop data")
	_push_primary(false)
	await process_frame
	_input_buffer.poll()

	_push_hotbar_key(KEY_1)
	await process_frame
	_expect(_inventory.selected_slot == 0, "pickaxe hotbar selection failed")
	_expect(_player.held_item_view.held_node is PixelExtrudedItem, "pickaxe did not reappear")
	_prepare_target(_copper_pos, pickaxe_action)
	_expect(_interactor.can_primary_target, "stone pickaxe cannot target copper")
	_push_primary(true)
	await process_frame
	_input_buffer.poll()
	_expect(_input_buffer.primary_use_pressed, "primary input did not reach buffer")
	_interactor._handle_item_actions(0.0)
	_interactor._handle_item_actions(0.61)
	_expect(_voxel_world.get_block_id_at(_copper_pos) == BlockId.Type.AIR, "stone pickaxe did not mine copper")
	_expect(_inventory.get_inventory_item_count(&"copper") == 1, "mined copper did not enter inventory")
	_push_primary(false)
	await process_frame
	_input_buffer.poll()

	_push_hotbar_key(KEY_2)
	await process_frame
	unarmed = _interactor.get_selected_primary_action() as MiningActionDefinition
	_prepare_target(_grass_pos, unarmed)
	_expect(_interactor.can_primary_target, "unarmed action cannot target grass")
	_push_primary(true)
	await process_frame
	_input_buffer.poll()
	_interactor._handle_item_actions(0.0)
	_interactor._handle_item_actions(0.36)
	_expect(_voxel_world.get_block_id_at(_grass_pos) == BlockId.Type.AIR, "unarmed mining no longer mines grass")
	_push_primary(false)
	await process_frame
	_input_buffer.poll()

	_inventory.slots[0] = InventoryStack.new(&"copper_hoe", 1)
	_push_hotbar_key(KEY_1)
	await process_frame
	_expect(_interactor.get_selected_primary_action() == tilling_action, "copper hoe tilling action was not selected")
	_expect(_interactor._can_till_position(_till_grass_pos, Vector3i.UP, tilling_action), "copper hoe cannot target an exposed grass top")
	_expect(not _interactor._can_till_position(_till_grass_pos, Vector3i.RIGHT, tilling_action), "copper hoe can till a side face")
	_expect(not _interactor._can_till_position(_covered_dirt_pos, Vector3i.UP, tilling_action), "copper hoe can till below an occupied cell")
	_expect(not _interactor._can_till_position(_nonsoil_pos, Vector3i.UP, tilling_action), "copper hoe can till a non-soil block")
	var stale_edit := _voxel_world.try_replace_block(_till_dirt_pos, BlockId.Type.GRASS, BlockId.Type.FARMLAND_DRY)
	_expect(not stale_edit.is_success() and stale_edit.result == BlockEdit.Result.FAIL_BLOCK_CHANGED, "atomic replacement accepted a stale source block")
	var grass_revision := _voxel_world.get_revision(_till_grass_pos)
	_prepare_till_target(_till_grass_pos, tilling_action)
	_input_buffer.primary_use_just = true
	_interactor._handle_item_actions(0.0)
	_expect(_voxel_world.get_block_id_at(_till_grass_pos) == BlockId.Type.FARMLAND_DRY, "copper hoe did not till grass")
	_expect(_voxel_world.get_revision(_till_grass_pos) == grass_revision + 1, "tilling grass did not commit one world edit")
	_expect(_soil_tilled_count == 1, "successful grass till did not emit one completed action")
	var tilled_revision := _voxel_world.get_revision(_till_grass_pos)
	_prepare_till_target(_till_grass_pos, tilling_action)
	_input_buffer.primary_use_just = true
	_interactor._handle_item_actions(0.0)
	_expect(_voxel_world.get_revision(_till_grass_pos) == tilled_revision, "repeated tilling changed dry farmland")
	_expect(_soil_tilled_count == 1, "failed repeated till emitted a completed action")
	_prepare_till_target(_till_dirt_pos, tilling_action)
	_input_buffer.primary_use_just = true
	_interactor._handle_item_actions(0.0)
	_expect(_voxel_world.get_block_id_at(_till_dirt_pos) == BlockId.Type.FARMLAND_DRY, "copper hoe did not till dirt")
	_expect(_soil_tilled_count == 2, "successful dirt till did not emit a completed action")
	var edit_snapshot := _voxel_world.snapshot_block_edits()
	var restored_world := VoxelWorld.new(20, 36, 5, 12.0, block_catalog)
	restored_world.restore_block_edits(edit_snapshot["placed"], edit_snapshot["removed"])
	_expect(restored_world.get_block_id_at(_till_grass_pos) == BlockId.Type.FARMLAND_DRY, "dry farmland did not survive block-edit restore")
	var dirt_count_before := _inventory.get_inventory_item_count(&"dirt_block")
	_push_hotbar_key(KEY_2)
	await process_frame
	unarmed = _interactor.get_selected_primary_action() as MiningActionDefinition
	_prepare_target(_till_dirt_pos, unarmed)
	_push_primary(true)
	await process_frame
	_input_buffer.poll()
	_interactor._handle_item_actions(0.0)
	_interactor._handle_item_actions(farmland.mine_duration + 0.01)
	_expect(_voxel_world.get_block_id_at(_till_dirt_pos) == BlockId.Type.AIR, "dry farmland could not be mined")
	_expect(_inventory.get_inventory_item_count(&"dirt_block") == dirt_count_before + 1, "mined dry farmland did not add dirt")
	_push_primary(false)
	await process_frame
	_input_buffer.poll()

	_player.queue_free()
	_camera.queue_free()
	_combat.queue_free()
	_world_entity_coordinator.queue_free()
	_hotbar.queue_free()
	await process_frame
	await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "orphan count ended at %d" % orphan_count)
	if _errors.is_empty():
		print("TOOL_SYSTEM PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("TOOL_SYSTEM FAIL %s" % str(_errors))
		quit(1)

func _prepare_target(pos: Vector3i, action: MiningActionDefinition):
	_interactor.target_block = pos
	_interactor.target_has = true
	_interactor.can_primary_target = _interactor._can_mine_position(pos, action)

func _prepare_till_target(pos: Vector3i, action: TillingActionDefinition):
	_interactor.target_block = pos
	_interactor.target_has = true
	_interactor.last_ray_normal = Vector3i.UP
	_interactor.can_primary_target = _interactor._can_till_position(pos, Vector3i.UP, action)

func _on_soil_tilled():
	_soil_tilled_count += 1

func _push_hotbar_key(keycode: Key):
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	root.push_input(event, true)

func _push_primary(pressed: bool):
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(event)
	root.push_input(event, true)

func _on_melee_attack_started(_action: MeleeAttackActionDefinition, direction: int):
	_melee_attack_directions.append(direction)
	_melee_attack_facings.append(_player.model_root.global_transform.basis * Vector3.BACK)

func _expect(condition: bool, message: String):
	if not condition:
		_errors.append(message)
		print("[tool_system] FAIL: %s" % message)
