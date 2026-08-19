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
var _inventory_loadout: InventoryLoadoutCoordinator
var _stone_pos := Vector3i(1, 0, 0)
var _grass_pos := Vector3i(2, 0, 0)
var _copper_pos := Vector3i(3, 0, 0)
var _till_grass_pos := Vector3i(1, 0, 1)
var _till_dirt_pos := Vector3i(2, 0, 1)
var _covered_dirt_pos := Vector3i(3, 0, 1)
var _nonsoil_pos := Vector3i(4, 0, 1)
var _flower_pos := Vector3i(-1, 0, 0)
var _flower_support_pos := Vector3i(-2, 0, 0)
var _blocked_flower_pos := Vector3i(-3, 0, 0)
var _melee_attack_directions: Array[int] = []
var _melee_attack_facings: Array[Vector3] = []
var _soil_tilled_count: int = 0

func _init():
	call_deferred("_run")

func _position_ready(_position: Vector3) -> bool:
	return true

func _run():
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
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
	_expect(not BlockId.is_chunk_cube(BlockId.Type.CHEST), "chest is still baked into the chunk cube mesh")
	_expect(chest_block.is_solid and chest_block.is_opaque and chest_block.is_raycast_solid, "chest is not a solid targetable block")
	_expect(chest_block.is_breakable and chest_block.drop_item_id == &"chest", "chest does not use normal block drops")
	_expect(chest_block.mining_tool_tag == &"pickaxe" and chest_block.minimum_mining_power == 1, "chest mining requirements are invalid")
	_expect(chest_block.container != null and chest_block.container.rows == 3 and chest_block.container.columns == 5, "chest container dimensions are invalid")
	_expect(chest_placement != null and chest_placement.block == chest_block, "chest item does not place the canonical chest block")
	_expect(item_catalog.get_item_for_block(BlockId.Type.CHEST) == chest_item, "chest reverse block mapping is incorrect")
	_expect(chest_item.icon.resource_path == "res://assets/textures/blocks/chest_front.png", "chest inventory icon does not reuse the front texture")
	var chest_icon_image := chest_item.icon.get_image()
	_expect(chest_icon_image.get_size() == Vector2i(16, 16), "chest inventory icon is not 16x16")
	_expect(chest_block.top_texture.resource_path == "res://assets/textures/blocks/chest_top.png", "chest uses the wrong top texture")
	_expect(chest_block.side_texture.resource_path == "res://assets/textures/blocks/chest_side.png", "chest uses the wrong side texture")
	_expect(chest_block.top_texture.get_image().get_size() == Vector2i(16, 16), "chest top texture is not 16x16")
	_expect(chest_block.side_texture.get_image().get_size() == Vector2i(16, 16), "chest side texture is not 16x16")
	var chest_top_image := chest_block.top_texture.get_image()
	var chest_front_image := chest_icon_image
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
	_expect(chest_texture_set.side_layers[BlockId.Type.CHEST] == -1, "special chest renderer textures leaked into the chunk texture set")
	var sword := item_catalog.get_definition(&"copper_sword")
	_expect(sword.max_stack == 1, "sword stack limit changed")
	_expect(sword.primary_action is MeleeAttackActionDefinition, "sword primary action is not melee")
	_expect(sword.secondary_action == null, "sword unexpectedly has a secondary action")
	var sword_action := sword.primary_action as MeleeAttackActionDefinition
	_expect(is_equal_approx(sword_action.attack_profile.duration, 0.48), "sword attack duration changed")
	_expect(is_equal_approx(sword_action.attack_profile.base_damage, 10.0) and sword_action.attack_profile.base_damage_random_reduction == 2, "sword base damage spread is not 8-10")
	_expect(is_equal_approx(sword_action.chain_input_window, 0.26), "sword chain input window changed")
	var hammer := item_catalog.get_definition(&"copper_hammer")
	_expect(hammer.max_stack == 1, "copper hammer stack limit is not one")
	_expect(hammer.primary_action is MeleeAttackActionDefinition and hammer.secondary_action == null, "copper hammer action configuration is incorrect")
	_expect(hammer.icon.resource_path == "res://assets/textures/tools/hammer/copper_hammer.png", "copper hammer uses the wrong inventory icon")
	var hammer_icon := hammer.icon.get_image()
	_expect(hammer_icon != null and hammer_icon.get_size() == Vector2i(16, 16), "copper hammer inventory icon is not 16x16")
	_expect(hammer_icon != null and hammer_icon.detect_alpha() != Image.ALPHA_NONE, "copper hammer inventory icon has no transparency")
	var hammer_icon_colors: Dictionary[Color, bool] = {}
	var hammer_partial_alpha_pixels := 0
	if hammer_icon != null:
		for y in range(hammer_icon.get_height()):
			for x in range(hammer_icon.get_width()):
				var pixel := hammer_icon.get_pixel(x, y)
				if pixel.a > 0.0:
					hammer_icon_colors[Color(pixel.r, pixel.g, pixel.b, 1.0)] = true
				if pixel.a > 0.0 and pixel.a < 1.0:
					hammer_partial_alpha_pixels += 1
	_expect(hammer_icon_colors.size() <= 6, "copper hammer inventory icon exceeds its pixel-art palette")
	_expect(hammer_partial_alpha_pixels == 0, "copper hammer inventory icon contains anti-aliased pixels")
	var hammer_action := hammer.primary_action as MeleeAttackActionDefinition
	_expect(hammer_action.animation_style == MeleeAttackActionDefinition.AnimationStyle.OVERHEAD_SLAM and hammer_action.two_handed_pose, "copper hammer does not use the two-handed slam presentation")
	_expect(not hammer_action.compensate_attack_arm_pitch and is_equal_approx(hammer_action.impact_effect_radius, 4.0), "copper hammer impact presentation is misconfigured")
	var hammer_profile := hammer_action.attack_profile
	_expect(hammer_profile.duration >= sword_action.attack_profile.duration * 2.0, "copper hammer attack is not at least twice as slow as the sword")
	_expect(is_equal_approx(hammer_profile.reach, 4.0) and is_equal_approx(hammer_profile.sweep_degrees, 360.0), "copper hammer does not use a four-block radial attack")
	_expect(is_equal_approx(hammer_action.impact_effect_radius, hammer_profile.reach), "hammer shockwave radius does not match its damage and knockback radius")
	_expect(is_equal_approx(hammer_profile.base_damage, 15.0) and is_equal_approx(hammer_profile.damage_multiplier, 1.0), "copper hammer base damage is not fifteen")
	_expect(is_equal_approx(hammer_profile.radial_damage_center_multiplier, 1.0) and is_equal_approx(hammer_profile.radial_damage_edge_multiplier, 1.0 / 3.0), "copper hammer radial damage falloff is misconfigured")
	_expect(hammer_profile.acquire_targets_on_contact and is_equal_approx(hammer_profile.knockback_speed, 8.0) and is_equal_approx(hammer_profile.impact_origin_forward_offset, 1.445), "copper hammer impact behavior is incomplete")
	_expect(hammer.rarity == sword.rarity and hammer.proficiency == sword.proficiency, "copper hammer does not use canonical weapon progression")
	var highlight_color := CombatPresentationPalette.WEAK_DAMAGE_COLOR.to_html(false)
	_expect(ItemStatFormatter.get_item_stat_lines(stone_pickaxe) == [
		"Mining Power: [b][color=#%s]1[/color][/b]" % highlight_color,
		"Speed Multiplier: [b][color=#%s]1.5x[/color][/b]" % highlight_color,
	], "stone pickaxe presentation stats are incorrect")
	_expect(ItemStatFormatter.get_item_stat_lines(copper_pickaxe) == [
		"Mining Power: [b][color=#%s]2[/color][/b]" % highlight_color,
		"Speed Multiplier: [b][color=#%s]2x[/color][/b]" % highlight_color,
	], "copper pickaxe presentation stats are incorrect")
	var pickaxe_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	InventoryTestFixture.restore_slot(pickaxe_inventory, 0, InventoryStack.new(
		&"stone_pickaxe",
		1,
		pickaxe_inventory.equipment_instance_factory.create(&"stone_pickaxe"),
	))
	var pickaxe_slot := (load("res://inventory/ui/inventory_slot.tscn") as PackedScene).instantiate() as InventorySlot
	root.add_child(pickaxe_slot)
	pickaxe_slot.set_inventory(pickaxe_inventory)
	pickaxe_slot.set_item_proficiency(ItemProficiency.new(item_catalog))
	pickaxe_slot.set_slot_index(0)
	pickaxe_slot.set_item(&"stone_pickaxe", 1)
	var pickaxe_tooltip := pickaxe_slot._make_custom_tooltip(pickaxe_slot.tooltip_text) as ItemTooltip
	_expect(pickaxe_tooltip != null, "stone pickaxe did not expose its mining stat tooltip")
	if pickaxe_tooltip != null:
		root.add_child(pickaxe_tooltip)
		_expect(pickaxe_tooltip.stats_label.get_parsed_text().contains("Mining Power: 1") and pickaxe_tooltip.stats_label.get_parsed_text().contains("Speed Multiplier: 1.5x"), "stone pickaxe tooltip stats are incomplete")
		pickaxe_tooltip.free()
	pickaxe_slot.free()
	var hammer_held := hammer.held_scene.instantiate() as Node3D
	var hammer_handle := hammer_held.get_node_or_null("Handle") as MeshInstance3D
	var hammer_head := hammer_held.get_node_or_null("Head") as MeshInstance3D
	_expect(hammer_handle != null and hammer_handle.mesh is CylinderMesh and (hammer_handle.mesh as CylinderMesh).height >= 1.1, "copper hammer does not have a long wooden handle")
	_expect(hammer_head != null and hammer_head.mesh is BoxMesh and (hammer_head.mesh as BoxMesh).size.x >= 0.7, "copper hammer does not have a large head")
	hammer_held.free()
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
	_expect(is_equal_approx((pumpkin.secondary_action as ConsumableActionDefinition).health_restore_fraction, 0.1), "pumpkin does not restore ten percent health")
	_expect(pumpkin.consume_audio != null and pumpkin.consume_audio.streams.size() == 1, "pumpkin consume audio is not configured")
	var health_potion := item_catalog.get_definition(&"health_potion")
	_expect(health_potion.primary_action == null and health_potion.secondary_action is ConsumableActionDefinition, "health potion action configuration is incorrect")
	_expect(is_equal_approx((health_potion.secondary_action as ConsumableActionDefinition).health_restore_fraction, 1.0), "health potion does not restore full health")
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
	_expect(not unarmed_action.can_mine(chest_block), "unarmed action can mine a chest")
	_expect(pickaxe_action.can_mine(chest_block), "stone pickaxe cannot mine a chest")
	_expect(copper_pickaxe_action.can_mine(chest_block), "copper pickaxe cannot mine a chest")
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

	_inventory = InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	_inventory.setup_starter()
	_expect(_inventory.get_slot(0) == null, "new inventory still grants a copper pickaxe")
	_expect(_inventory.get_slot(3) is InventoryStack and _inventory.get_slot(3).item_id == &"copper_sword", "starter sword missing")
	var test_totem_slot := InventoryModel.FILLABLE_SIZE - 1
	_expect(_inventory.get_slot(test_totem_slot) is InventoryStack and _inventory.get_slot(test_totem_slot).item_id == &"test_totem", "test totem is not in the starter backpack")
	var encoded := _inventory.to_dict()
	var restored_next_instance_id := _inventory.equipment_instance_factory.get_next_instance_id()
	var restored := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog, restored_next_instance_id))
	_expect(restored.from_dict(encoded), "typed inventory did not restore")
	_expect(restored.get_slot(0) == null, "restored new inventory gained a copper pickaxe")
	_expect(restored.get_slot(3) is InventoryStack and restored.get_slot(3).item_id == &"copper_sword", "restored sword missing")
	_expect(restored.get_slot(test_totem_slot) is InventoryStack and restored.get_slot(test_totem_slot).item_id == &"test_totem", "restored test totem missing")
	_expect(restored.get_starter_item_migration_version() == InventoryModel.STARTER_ITEM_MIGRATION_VERSION, "starter item migration version did not restore")
	var existing_pickaxe_encoded := encoded.duplicate(true)
	existing_pickaxe_encoded["regions"]["hotbar"][0] = {
		"item_id": "copper_pickaxe",
		"count": 1,
		"equipment_instance": null,
	}
	existing_pickaxe_encoded.erase("starter_item_migration_version")
	var existing_pickaxe_save := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog, restored_next_instance_id))
	_expect(existing_pickaxe_save.from_dict(existing_pickaxe_encoded), "existing copper pickaxe save did not restore")
	_expect(InventoryTestFixture.create_loadout(existing_pickaxe_save).migrate_starter_items(), "existing copper pickaxe save did not migrate")
	_expect(existing_pickaxe_save.get_slot(0) != null and existing_pickaxe_save.get_slot(0).item_id == &"copper_pickaxe", "existing copper pickaxe was not preserved")
	var legacy_encoded := encoded.duplicate(true)
	legacy_encoded["regions"]["hotbar"][3] = null
	legacy_encoded.erase("starter_item_migration_version")
	var legacy := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog, restored_next_instance_id))
	_expect(legacy.from_dict(legacy_encoded), "legacy inventory did not restore")
	var legacy_loadout := InventoryTestFixture.create_loadout(legacy)
	_expect(legacy_loadout != null and legacy_loadout.migrate_starter_items(), "legacy inventory could not receive starter items")
	_expect(legacy.get_inventory_item_count(&"copper_pickaxe") == 0, "legacy migration granted a copper pickaxe")
	_expect(legacy.get_inventory_item_count(&"copper_sword") == 1, "legacy migration did not restore the sword")
	var restore_game := Game.new()
	restore_game.item_catalog = item_catalog
	restore_game.inventory_model = InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog, restored_next_instance_id))
	restore_game._save_data = {"inventory": legacy_encoded}
	restore_game._restore_inventory()
	_expect(restore_game.inventory_model.get_inventory_item_count(&"copper_pickaxe") == 0, "game restore granted a copper pickaxe")
	_expect(restore_game.inventory_model.get_inventory_item_count(&"copper_sword") == 0, "inventory restore executed runtime migration")
	var restore_loadout := InventoryTestFixture.create_loadout(restore_game.inventory_model)
	_expect(restore_loadout != null and restore_loadout.migrate_starter_items(), "restored game inventory could not execute runtime migration")
	_expect(restore_game.inventory_model.get_inventory_item_count(&"copper_sword") == 1, "runtime migration did not restore the sword")
	restore_game.free()
	var new_game := Game.new()
	new_game.item_catalog = item_catalog
	new_game.inventory_model = InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	new_game._save_data = {"inventory": null}
	new_game._restore_inventory()
	for index in range(new_game.inventory_model.get_size()):
		_expect(new_game.inventory_model.get_slot(index) == null, "new world inventory contains an item in slot %d" % index)
	_expect(new_game.inventory_model.get_starter_item_migration_version() == InventoryModel.STARTER_ITEM_MIGRATION_VERSION, "new world inventory can receive legacy starter items after reload")
	var reloaded_new_world := InventoryModel.new(
		item_catalog,
		EquipmentInstanceFactory.new(item_catalog, new_game.inventory_model.equipment_instance_factory.get_next_instance_id()),
	)
	_expect(reloaded_new_world.from_dict(new_game.inventory_model.to_dict()), "new world inventory did not survive save serialization")
	_expect(InventoryTestFixture.create_loadout(reloaded_new_world).migrate_starter_items(), "new world inventory migration state did not survive reload")
	for index in range(reloaded_new_world.get_size()):
		_expect(reloaded_new_world.get_slot(index) == null, "reloaded new world gained an item in slot %d" % index)
	new_game.free()
	for index in range(legacy.get_size()):
		if legacy.get_slot(index) != null and legacy.get_slot(index).item_id == &"copper_sword":
			_expect(legacy_loadout.discard_stack(index, 1), "completed starter sword could not be discarded")
			break
	_expect(legacy_loadout.migrate_starter_items(), "completed starter migration did not remain complete")
	_expect(legacy.get_inventory_item_count(&"copper_sword") == 0, "completed starter migration re-granted a removed sword")
	var crowded := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	var grass_id := item_catalog.get_item_for_block(BlockId.Type.GRASS).id
	for index in range(InventoryModel.HOTBAR_SIZE):
		InventoryTestFixture.restore_slot(crowded, index, InventoryStack.new(grass_id, index + 1))
	_expect(InventoryTestFixture.create_loadout(crowded).ensure_item(&"copper_pickaxe"), "full hotbar could not receive a pickaxe")
	_expect(crowded.get_slot(0).item_id == &"copper_pickaxe" and crowded.get_slot(InventoryModel.HOTBAR_SIZE).count == 1, "adding a pickaxe lost its displaced stack")
	var full := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	for index in range(InventoryModel.FILLABLE_SIZE):
		InventoryTestFixture.restore_slot(full, index, InventoryStack.new(grass_id, 1))
	_expect(not InventoryTestFixture.create_loadout(full).migrate_starter_items(), "full inventory unexpectedly accepted starter items")
	for index in range(InventoryModel.FILLABLE_SIZE, InventoryModel.TOTAL_SIZE):
		_expect(full.get_slot(index) == null, "starter migration used reserved equipment slot %d" % index)
	InventoryTestFixture.restore_slot(_inventory, 0, InventoryStack.new(
		&"stone_pickaxe",
		1,
		_inventory.equipment_instance_factory.create(&"stone_pickaxe"),
	))

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
		_flower_pos: BlockId.Type.BLUE_WILDFLOWER,
		_flower_support_pos: BlockId.Type.GRASS,
		_flower_support_pos + Vector3i.UP: BlockId.Type.RED_FLOWER,
		_blocked_flower_pos: BlockId.Type.ORANGE_TULIP,
	}, {})
	var chest_position := Vector3i(4, 20, 0)
	var chest_place_change := VoxelWorldTestFixture.commit_place(_voxel_world, chest_position, BlockId.Type.CHEST)
	_expect(chest_place_change != null and chest_place_change.get_primary_edit().new_id == BlockId.Type.CHEST, "voxel world rejected chest placement")
	_expect(_voxel_world.get_block_id_at(chest_position) == BlockId.Type.CHEST, "placed chest is missing from the voxel world")
	_expect(_voxel_world.snapshot_block_edits()["placed"].get(chest_position, BlockId.Type.AIR) == BlockId.Type.CHEST, "placed chest was not persisted as a world edit")
	var chest_mine_change := VoxelWorldTestFixture.commit_mine(_voxel_world, chest_position)
	_expect(chest_mine_change != null and chest_mine_change.get_edits().size() == 1, "placed chest could not be mined")
	_expect(_voxel_world.get_block_id_at(chest_position) == BlockId.Type.AIR, "mined chest remained in the world")
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
	var item_proficiency := ItemProficiency.new(item_catalog)
	_inventory_loadout = InventoryLoadoutCoordinator.new()
	_expect(_inventory_loadout.setup(_inventory, player_stats, item_proficiency), "inventory stat coordinator setup failed")
	_combat.setup(_voxel_world, _player, player_stats, _inventory, _world_entity_coordinator.get_runtime(), load("res://combat/damage/damage_type_catalog.tres") as DamageTypeCatalog)
	var movement_camera_rig := (load("res://player/camera/camera_rig.tscn") as PackedScene).instantiate() as CameraRig
	root.add_child(movement_camera_rig)
	movement_camera_rig.camera = _camera
	movement_camera_rig.camera.size = CameraRig.DEFAULT_ORTHO_SIZE
	movement_camera_rig.setup(_player, _input_buffer)
	_player.setup(
		movement_camera_rig,
		_inventory,
		_inventory_loadout,
		InventoryTestFixture.create_player_action_executors(_inventory, _inventory_loadout, _interactor.unarmed_primary_action),
		_input_buffer,
		player_stats,
		_combat,
		_world_entity_coordinator.get_runtime(),
	)
	_player.bind_space(_voxel_world, root, Vector3.ZERO, _voxel_world)
	_interactor.melee_attack_started.connect(_on_melee_attack_started)
	_interactor.soil_tilled.connect(_on_soil_tilled)
	_player.set_physics_process(false)
	_interactor.set_physics_process(false)
	_player.animation_driver.set_process(false)
	_expect(_inventory_loadout.discard_stack(0, 1), "stone pickaxe could not be replaced for the hammer presentation test")
	_expect(_inventory_loadout.add_stack(InventoryStack.new(
		&"copper_hammer",
		1,
		_inventory.equipment_instance_factory.create(&"copper_hammer"),
	)), "hammer could not be added for the presentation test")
	var hammer_source := _find_inventory_item(&"copper_hammer")
	_expect(hammer_source >= 0 and (hammer_source == 0 or _inventory_loadout.assign_slot_to_hotbar(hammer_source, 0)), "hammer could not be moved to the selected slot")
	_expect(_inventory.get_slot(0) != null and _inventory.get_slot(0).item_id == &"copper_hammer", "hammer did not occupy the selected slot")
	_player.animation_driver.animator._placing = true
	_player.animation_driver.animator._place_elapsed = 0.05
	_player.animation_driver.animator._mining_active = true
	_player.animation_driver.animator._mine_blend = 1.0
	_player.animation_driver._on_melee_attack_started(hammer_action, -1)
	_expect(not _player.animation_driver.animator._placing and not _player.animation_driver.animator._mining_active and is_zero_approx(_player.animation_driver.animator._mine_blend), "immediate hammer attack retained a stale placement or mining pose")
	var immediate_attack_idle: Transform3D = _player.animation_driver.animator.global_transform.affine_inverse() * _player.held_item_view.global_transform
	var immediate_idle_global: Transform3D = _player.animation_driver.animator.right_arm_base.global_transform * _player.held_item_view._attack_idle_relative_transform
	var immediate_idle_relative: Transform3D = _player.animation_driver.animator.global_transform.affine_inverse() * immediate_idle_global
	_expect(immediate_attack_idle.origin.distance_to(immediate_idle_relative.origin) < 0.001, "immediate hammer attack cached a transient held-item position")
	_expect(immediate_attack_idle.basis.orthonormalized().get_rotation_quaternion().angle_to(immediate_idle_relative.basis.orthonormalized().get_rotation_quaternion()) < 0.001, "immediate hammer attack cached a transient held-item rotation")
	_player.animation_driver.animator.cancel_attack()
	_player.animation_driver._active_attack_action = null
	_player.animation_driver.animator.set_held_melee_action(null)
	_expect(_inventory_loadout.discard_stack(0, 1), "hammer could not be removed after the presentation test")
	_expect(_inventory_loadout.add_stack(InventoryStack.new(
		&"stone_pickaxe",
		1,
		_inventory.equipment_instance_factory.create(&"stone_pickaxe"),
	)), "stone pickaxe could not be restored after the hammer presentation test")
	var restored_pickaxe_source := _find_inventory_item(&"stone_pickaxe")
	_expect(restored_pickaxe_source >= 0 and (restored_pickaxe_source == 0 or _inventory_loadout.assign_slot_to_hotbar(restored_pickaxe_source, 0)), "stone pickaxe could not be moved back to the selected slot")
	_expect(_inventory.get_slot(0) != null and _inventory.get_slot(0).item_id == &"stone_pickaxe", "stone pickaxe did not return to the selected slot")
	_player.held_item_view.set_attack_pose(0.0, 0.0, null)
	var shockwave := _player.get_node("HammerShockwave") as HammerShockwaveView
	movement_camera_rig._camera_rest_position = _camera.position
	var shockwave_position := Vector3(2.0, 0.04, 3.0)
	var camera_rest_position := movement_camera_rig.camera.position
	_interactor.melee_attack_impacted.emit(hammer_action, shockwave_position)
	_expect(shockwave.visible and shockwave.global_position.is_equal_approx(shockwave_position), "hammer impact did not show its shockwave at the contact point")
	_expect(is_zero_approx(movement_camera_rig._impact_shake_elapsed), "hammer impact did not start the camera shake")
	movement_camera_rig._update_impact_shake(0.02)
	_expect(not movement_camera_rig.camera.position.is_equal_approx(camera_rest_position), "hammer camera shake did not offset the camera")
	_expect(movement_camera_rig.camera.position.distance_to(camera_rest_position) <= CameraRig.IMPACT_SHAKE_STRENGTH, "hammer camera shake was not subtle")
	var default_zoom_shake_distance := movement_camera_rig.camera.position.distance_to(camera_rest_position)
	movement_camera_rig.camera.size = movement_camera_rig.min_ortho_size
	movement_camera_rig.play_impact_shake()
	movement_camera_rig._update_impact_shake(0.02)
	var zoomed_in_shake_distance := movement_camera_rig.camera.position.distance_to(camera_rest_position)
	movement_camera_rig.camera.size = movement_camera_rig.max_ortho_size
	movement_camera_rig.play_impact_shake()
	movement_camera_rig._update_impact_shake(0.02)
	var zoomed_out_shake_distance := movement_camera_rig.camera.position.distance_to(camera_rest_position)
	_expect(zoomed_in_shake_distance > default_zoom_shake_distance and default_zoom_shake_distance > zoomed_out_shake_distance, "hammer camera shake did not scale with orthographic zoom")
	_expect(absf(zoomed_in_shake_distance / default_zoom_shake_distance - sqrt(CameraRig.DEFAULT_ORTHO_SIZE / movement_camera_rig.min_ortho_size)) < 0.001, "fully zoomed-in hammer shake used the wrong softened scale")
	_expect(absf(zoomed_out_shake_distance / default_zoom_shake_distance - sqrt(CameraRig.DEFAULT_ORTHO_SIZE / movement_camera_rig.max_ortho_size)) < 0.001, "fully zoomed-out hammer shake used the wrong softened scale")
	movement_camera_rig.camera.size = CameraRig.DEFAULT_ORTHO_SIZE
	_expect(shockwave._mesh_instance != null and shockwave._mesh_instance.mesh is ImmediateMesh, "hammer shockwave does not use a procedural ring")
	var initial_shockwave_scale := shockwave.scale.x
	shockwave._process(HammerShockwaveView.DURATION_SECONDS * 0.1)
	_expect(shockwave.scale.x > initial_shockwave_scale and is_zero_approx(shockwave._inner_radius_ratio), "hammer shockwave inner edge appeared before its delay")
	shockwave._process(HammerShockwaveView.DURATION_SECONDS * 0.4)
	_expect(shockwave._inner_radius_ratio > 0.0 and shockwave._inner_radius_ratio < HammerShockwaveView.FINAL_INNER_RADIUS_RATIO and shockwave._material.albedo_color.a > 0.0, "hammer shockwave inner edge did not trail the outer edge")
	shockwave._process(HammerShockwaveView.DURATION_SECONDS * 0.41)
	_expect(is_equal_approx(shockwave._inner_radius_ratio, HammerShockwaveView.FINAL_INNER_RADIUS_RATIO) and shockwave._material.albedo_color.a > 0.0 and shockwave.visible, "hammer shockwave inner edge did not reach the outer edge before fading")
	shockwave._process(HammerShockwaveView.DURATION_SECONDS * 0.1)
	_expect(not shockwave.visible, "hammer shockwave did not finish")
	movement_camera_rig._update_impact_shake(CameraRig.IMPACT_SHAKE_DURATION)
	_expect(movement_camera_rig.camera.position.is_equal_approx(camera_rest_position), "hammer camera shake did not restore the camera")
	var sword_arc := _player.get_node("SwordSwingArc") as SwordSwingArcView
	_expect(_interactor.melee_attack_started.is_connected(sword_arc._on_melee_attack_started), "sword arc is not wired to live melee attacks")
	_interactor.melee_attack_action = sword_action
	sword_arc.play(sword_action, -1)
	_expect(not sword_arc.visible and sword_arc._active_action == sword_action, "sword arc appeared before the authored windup completed")
	_expect(is_equal_approx(sword_arc._reach, sword_action.attack_profile.reach) and is_equal_approx(sword_arc._sweep_radians, deg_to_rad(sword_action.attack_profile.sweep_degrees)), "sword arc does not use the combat profile geometry")
	var arc_origin_before_move := sword_arc.global_position
	_player.global_position.x += 0.25
	sword_arc._process(sword_action.attack_profile.duration * MeleeAttackActionDefinition.SWEEP_WINDUP_END)
	_expect(not sword_arc.visible, "sword arc rendered during the windup")
	var sword_contact_progress := sword_action.get_sweep_contact_progress()
	var half_strike_duration := sword_action.attack_profile.duration * (sword_contact_progress - MeleeAttackActionDefinition.SWEEP_WINDUP_END) * 0.5
	sword_arc._process(half_strike_duration)
	_expect(is_zero_approx(sword_arc._leading_angle) and sword_arc._lagging_angle > sword_arc._leading_angle and sword_arc.visible, "left-to-right sword scan did not cross forward in the sword's direction")
	_expect(sword_arc._leading_progress > sword_arc._lagging_progress and is_zero_approx(sword_arc._lagging_progress), "sword scan's trailing edge started before the leading edge completed")
	_expect(is_equal_approx(sword_arc.global_position.x, arc_origin_before_move.x + 0.25), "sword arc did not follow the moving player's attack origin")
	_expect(is_equal_approx(sword_arc.global_position.y, _player.global_position.y + _player.player_height * SwordSwingArcView.HEIGHT_RATIO), "sword scan is not positioned just below the held sword")
	_expect(is_equal_approx(SwordSwingArcView.PEAK_ALPHA, 0.56), "sword scan opacity changed")
	var sword_arc_arrays := sword_arc._mesh.surface_get_arrays(0)
	var sword_arc_vertices := sword_arc_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var sword_arc_colors := sword_arc_arrays[Mesh.ARRAY_COLOR] as PackedColorArray
	var sword_arc_outer_radius := 0.0
	var sword_arc_inner_radius := INF
	for vertex in sword_arc_vertices:
		var vertex_radius := Vector2(vertex.x, vertex.z).length()
		sword_arc_outer_radius = maxf(sword_arc_outer_radius, vertex_radius)
		sword_arc_inner_radius = minf(sword_arc_inner_radius, vertex_radius)
	_expect(absf(sword_arc_outer_radius - sword_action.attack_profile.reach) < 0.001, "sword arc outer edge does not match melee reach")
	_expect(is_zero_approx(sword_arc_inner_radius), "sword scan does not extend from the player to maximum melee reach")
	_expect(not sword_arc_colors.is_empty() and sword_arc_colors[0].a < sword_arc_colors[sword_arc_colors.size() - 1].a, "sword arc does not fade behind its moving edge")
	sword_arc._process(half_strike_duration)
	_expect(sword_arc.visible and is_equal_approx(sword_arc._leading_progress, 1.0) and is_zero_approx(sword_arc._lagging_progress), "sword scan's trailing edge started before the leading edge reached the damage contact frame")
	var contact_arc_alpha := (sword_arc._mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray)[-1].a
	var half_recovery_duration := sword_action.attack_profile.duration * (1.0 - sword_contact_progress) * 0.5
	sword_arc._process(half_recovery_duration)
	var recovery_arc_colors := sword_arc._mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
	_expect(sword_arc.visible and is_equal_approx(sword_arc._leading_progress, 1.0) and is_equal_approx(sword_arc._lagging_progress, 0.5), "sword scan's trailing edge did not clear across the completed sector")
	_expect(recovery_arc_colors[recovery_arc_colors.size() - 1].a < contact_arc_alpha, "sword scan did not fade while its trailing edge caught up")
	sword_arc._process(half_recovery_duration)
	_expect(not sword_arc.visible and sword_arc._active_action == null, "sword scan did not converge and finish with the attack")
	sword_arc.play(sword_action, 1)
	sword_arc._process(sword_action.attack_profile.duration * (MeleeAttackActionDefinition.SWEEP_WINDUP_END + (sword_contact_progress - MeleeAttackActionDefinition.SWEEP_WINDUP_END) * 0.25))
	_expect(sword_arc._leading_angle > sword_arc._lagging_angle, "right-to-left sword scan did not reverse its direction")
	_interactor.melee_attack_action = null
	sword_arc._process(0.01)
	_expect(not sword_arc.visible, "canceling a sword attack left its arc visible")
	sword_arc.play(hammer_action, -1)
	_expect(not sword_arc.visible, "overhead hammer attack incorrectly showed a sword arc")
	_player.global_position.x -= 0.25
	_interactor.cancel_actions()
	_hotbar = (load("res://inventory/ui/inventory_hotbar.tscn") as PackedScene).instantiate() as InventoryHotbar
	root.add_child(_hotbar)
	_hotbar.setup(_inventory, _inventory_loadout, item_proficiency)
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
	_expect(_inventory.get_selected_slot() == 3, "sword hotbar selection failed")
	_expect(_player.held_item_view.held_node is PixelExtrudedItem, "sword held scene missing")
	var held_sword := _player.held_item_view.held_node as PixelExtrudedItem
	_expect(held_sword.texture == sword.icon, "sword held texture changed")
	_expect(is_equal_approx(held_sword.rotation.y, PI * 0.5), "sword does not point toward the player's front")
	var one_pixel_sword := PixelItemMeshBuilder.build(held_sword.texture, held_sword.grip_pixel, held_sword.max_dimension, 1.0)
	_expect(is_equal_approx(held_sword.mesh_instance.mesh.get_aabb().size.z, one_pixel_sword.get_aabb().size.z), "sword mesh thickness changed")
	_expect(_interactor.get_selected_primary_action() == sword_action, "sword melee action was not selected")
	_player.model_root.rotation.y = 0.0
	_input_buffer.move_dir = Vector2.RIGHT
	_player._handle_movement(0.0)
	var armed_strafe_world_velocity := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	var armed_strafe_local_velocity := _player.model_root.global_transform.basis.inverse() * armed_strafe_world_velocity
	_expect(is_zero_approx(_player.model_root.rotation.y), "armed strafe changed player facing")
	_expect(armed_strafe_local_velocity.x > _player.move_speed * 0.9 and absf(armed_strafe_local_velocity.z) < 0.01, "armed right movement was not a full local strafe")
	_input_buffer.move_dir = Vector2(0.0, 1.0)
	_player._handle_movement(0.0)
	var armed_forward_world_velocity := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	var armed_forward_local_velocity := _player.model_root.global_transform.basis.inverse() * armed_forward_world_velocity
	_expect(armed_forward_local_velocity.z < -_player.move_speed * 0.9, "camera-forward movement did not become backward movement while aiming behind")
	_input_buffer.move_dir = Vector2.ZERO

	var facing_direction := Vector3(1.0, 0.0, 1.0).normalized()
	var facing_target_yaw := atan2(facing_direction.x, facing_direction.z)
	var facing_start_yaw := facing_target_yaw - 1.0
	_player.model_root.rotation.y = facing_start_yaw
	_player.turn_toward_direction(facing_direction, 0.1)
	var single_step_yaw := _player.model_root.rotation.y
	var expected_single_step_yaw := lerp_angle(facing_start_yaw, facing_target_yaw, 1.0 - exp(-10.0 * 0.1))
	_expect(is_equal_approx(single_step_yaw, expected_single_step_yaw), "smooth facing did not use exponential response")
	_expect(absf(wrapf(single_step_yaw - facing_target_yaw, -PI, PI)) > 0.1, "smooth facing snapped to its target")

	_player.model_root.rotation.y = facing_start_yaw
	_player.turn_toward_direction(facing_direction, 0.05)
	_player.turn_toward_direction(facing_direction, 0.05)
	_expect(absf(wrapf(_player.model_root.rotation.y - single_step_yaw, -PI, PI)) < 0.00001, "smooth facing changed with frame subdivision")

	_player.model_root.rotation.y = facing_start_yaw
	_player._turn_toward_movement(facing_direction, 0.1)
	_expect(is_equal_approx(_player.model_root.rotation.y, facing_start_yaw), "movement changed facing while a melee weapon was selected")

	_input_buffer.sprint_pressed = true
	_input_buffer.move_dir = Vector2.RIGHT
	_player._handle_movement(0.0)
	var armed_sprint_velocity := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	_expect(_player.is_sprinting, "armed movement did not enter sprinting")
	_expect(is_equal_approx(armed_sprint_velocity.length(), _player.sprint_speed), "armed sprint speed changed")
	_player.model_root.rotation.y = facing_start_yaw
	_player._turn_toward_movement(facing_direction, 0.1)
	_expect(is_equal_approx(_player.model_root.rotation.y, expected_single_step_yaw), "armed sprinting did not restore movement-facing")
	_input_buffer.sprint_pressed = false
	_input_buffer.move_dir = Vector2.ZERO
	_player._handle_movement(0.0)

	var aim_mouse_position := _interactor.get_viewport().get_mouse_position()
	var aim_ray_origin := _camera.project_ray_origin(aim_mouse_position)
	var aim_ray_direction := _camera.project_ray_normal(aim_mouse_position).normalized()
	var aim_direction := _interactor._get_cursor_planar_direction(aim_ray_origin, aim_ray_direction)
	_expect(not aim_direction.is_zero_approx(), "cursor aim did not reach the player-height plane")
	var aim_target_yaw := atan2(aim_direction.x, aim_direction.z)
	var aim_start_yaw := aim_target_yaw - 1.0
	_player.model_root.rotation.y = aim_start_yaw
	_player.is_sprinting = true
	_interactor._update_melee_facing(0.1)
	_expect(is_equal_approx(_player.model_root.rotation.y, aim_start_yaw), "armed sprinting tracked the cursor")
	_player.is_sprinting = false

	_player.model_root.rotation.y = aim_start_yaw
	_player.on_ground = false
	_player.velocity = Vector3(-2.0, 3.0, 1.0)
	_interactor._update_melee_facing(0.1)
	var expected_aim_yaw := lerp_angle(aim_start_yaw, aim_target_yaw, 1.0 - exp(-10.0 * 0.1))
	_expect(is_equal_approx(_player.model_root.rotation.y, expected_aim_yaw), "airborne moving melee aim did not track the cursor smoothly")

	var held_aim_yaw := _player.model_root.rotation.y
	_interactor.pointer_over_ui = true
	_interactor._update_melee_facing(0.2)
	_expect(is_equal_approx(_player.model_root.rotation.y, held_aim_yaw), "melee aim changed while the pointer was over UI")
	_interactor.pointer_over_ui = false
	_player.velocity = Vector3.ZERO

	var aim_plane_center := _player.global_position + Vector3.UP * (_player.player_height * 0.5)
	var parallel_aim := _interactor._get_cursor_planar_direction(aim_plane_center + Vector3.UP, Vector3.RIGHT)
	var centered_aim := _interactor._get_cursor_planar_direction(aim_plane_center + Vector3.UP, Vector3.DOWN)
	_expect(parallel_aim.is_zero_approx(), "parallel cursor ray produced a facing direction")
	_expect(centered_aim.is_zero_approx(), "cursor directly above the player produced a facing direction")

	var resting_socket_position := _player.held_item_view.position
	var resting_socket_rotation := _player.held_item_view.rotation
	var attack_mouse_position := _interactor.get_viewport().get_mouse_position()
	var attack_ray_origin := _camera.project_ray_origin(attack_mouse_position)
	var attack_ray_direction := _camera.project_ray_normal(attack_mouse_position).normalized()
	var expected_attack_facing := _interactor._get_cursor_planar_direction(attack_ray_origin, attack_ray_direction)
	_expect(not expected_attack_facing.is_zero_approx(), "sword cursor ray did not reach the player-facing plane")
	_player.model_root.rotation.y = atan2(-expected_attack_facing.x, -expected_attack_facing.z)
	_push_primary(true)
	await process_frame
	_input_buffer.poll()
	_interactor._handle_item_actions(0.0)
	_expect(_melee_attack_directions == [-1], "single sword click did not start left-to-right")
	_expect(_melee_attack_facings.size() == 1 and _melee_attack_facings[0].dot(expected_attack_facing) > 0.999, "player did not face the mouse before the sword swing started")
	_expect(_player.animation_driver.animator._attacking, "sword attack did not reach the animation driver")
	_expect(is_equal_approx(_interactor.melee_attack_timer, sword_action.attack_profile.cooldown), "sword attack timer changed")
	_expect(_interactor._melee_attack_command._get_ray_origin().is_equal_approx(attack_ray_origin), "sword attack facing and targeting used different ray origins")
	_expect(_interactor._melee_attack_command._get_ray_direction().is_equal_approx(attack_ray_direction), "sword attack facing and targeting used different ray directions")
	var locked_attack_yaw := _player.model_root.rotation.y
	_player.is_sprinting = true
	_player._turn_toward_movement(-expected_attack_facing, 0.2)
	_expect(not is_equal_approx(_player.model_root.rotation.y, locked_attack_yaw), "sprint movement did not turn the player during the attack lock test")
	_interactor._update_melee_facing(0.0)
	_expect(is_equal_approx(_player.model_root.rotation.y, locked_attack_yaw), "sprinting overrode the locked sword facing")
	_player.is_sprinting = false

	var attack_camera_transform := _camera.transform
	_camera.look_at_from_position(Vector3(6.0, 6.0, 0.0), Vector3.ZERO)
	var redirected_mouse_position := _interactor.get_viewport().get_mouse_position()
	var redirected_ray_origin := _camera.project_ray_origin(redirected_mouse_position)
	var redirected_ray_direction := _camera.project_ray_normal(redirected_mouse_position).normalized()
	var redirected_aim := _interactor._get_cursor_planar_direction(redirected_ray_origin, redirected_ray_direction)
	_expect(not redirected_aim.is_zero_approx() and redirected_aim.dot(expected_attack_facing) < 0.99, "attack lock test did not redirect the cursor ray")
	_interactor._update_melee_facing(0.2)
	_expect(is_equal_approx(_player.model_root.rotation.y, locked_attack_yaw), "player facing changed during an active sword swing")
	_camera.transform = attack_camera_transform
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
	_player.model_root.rotation.y = facing_start_yaw
	_player.is_sprinting = true
	_player._turn_toward_movement(facing_direction, 0.1)
	var post_attack_sprint_yaw := _player.model_root.rotation.y
	_interactor._update_melee_facing(0.1)
	_expect(is_equal_approx(_player.model_root.rotation.y, post_attack_sprint_yaw), "cursor-facing resumed during a post-attack sprint")
	_player.is_sprinting = false

	var resumed_aim_start_yaw := aim_target_yaw - 1.0
	_player.model_root.rotation.y = resumed_aim_start_yaw
	_interactor._update_melee_facing(0.1)
	_expect(not is_equal_approx(_player.model_root.rotation.y, resumed_aim_start_yaw), "melee aim did not resume after the swing duration")
	_expect(absf(wrapf(_player.model_root.rotation.y - aim_target_yaw, -PI, PI)) > 0.1, "resumed melee aim snapped to the cursor")
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
	var pickaxe_facing_start_yaw := -0.5
	_player.model_root.rotation.y = pickaxe_facing_start_yaw
	_player._turn_toward_movement(Vector3.RIGHT, 0.1)
	_expect(not is_equal_approx(_player.model_root.rotation.y, pickaxe_facing_start_yaw), "non-melee movement stopped controlling facing")
	var pickaxe_movement_yaw := _player.model_root.rotation.y
	_interactor._update_melee_facing(0.5)
	_expect(is_equal_approx(_player.model_root.rotation.y, pickaxe_movement_yaw), "non-melee item started cursor-facing")
	_input_buffer.move_dir = Vector2(0.0, 1.0)
	_player._handle_movement(0.0)
	var pickaxe_world_velocity := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	_expect(pickaxe_world_velocity.is_equal_approx(armed_forward_world_velocity), "melee cursor-facing changed camera-relative world velocity")
	_input_buffer.move_dir = Vector2.ZERO
	_player.voxel_space = null
	_player.camera_rig = null
	movement_camera_rig.free()
	_push_primary(false)
	await process_frame
	_input_buffer.poll()

	_push_hotbar_key(KEY_2)
	await process_frame
	_expect(_inventory.get_selected_slot() == 1, "grass hotbar selection failed")
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
	_expect(_inventory.get_selected_slot() == 0, "pickaxe hotbar selection failed")
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

	var blue_flower_count := _inventory.get_inventory_item_count(&"blue_wildflower")
	_prepare_target(_flower_pos, unarmed)
	_interactor._commit_mine(_flower_pos, _inventory.create_selected_item_source())
	_expect(_voxel_world.get_block_id_at(_flower_pos) == BlockId.Type.AIR, "flower block was not mined")
	_expect(_inventory.get_inventory_item_count(&"blue_wildflower") == blue_flower_count + 1, "mined flower did not enter inventory")

	var grass_count := _inventory.get_inventory_item_count(&"grass_block")
	var red_flower_count := _inventory.get_inventory_item_count(&"red_flower")
	var support_preview := _voxel_world.prepare_mine_block(_flower_support_pos)
	var support_preview_edits: Array[BlockEdit] = [] if support_preview == null else support_preview.get_edits()
	_expect(support_preview_edits.size() == 2 and support_preview_edits[0].old_id == BlockId.Type.GRASS and support_preview_edits[1].old_id == BlockId.Type.RED_FLOWER, "support mining preview omitted its flower drop")
	_prepare_target(_flower_support_pos, unarmed)
	_interactor._commit_mine(_flower_support_pos, _inventory.create_selected_item_source())
	_expect(_voxel_world.get_block_id_at(_flower_support_pos) == BlockId.Type.AIR, "flower support block was not mined")
	_expect(_voxel_world.get_block_id_at(_flower_support_pos + Vector3i.UP) == BlockId.Type.AIR, "unsupported flower remained in the world")
	_expect(_inventory.get_inventory_item_count(&"grass_block") == grass_count + 1, "mined flower support did not add its block drop")
	_expect(_inventory.get_inventory_item_count(&"red_flower") == red_flower_count + 1, "support mining did not collect the flower above")

	var selected_stack := _inventory.get_slot(0)
	if selected_stack != null:
		_expect(_inventory_loadout.discard_stack(0, selected_stack.count), "selected tool could not be cleared")
	var hoe_batch: Array[StringName] = [&"copper_hoe"]
	_expect(_inventory_loadout.add_batch(hoe_batch), "copper hoe could not be added")
	var hoe_source := _find_inventory_item(&"copper_hoe")
	_expect(hoe_source >= 0 and (hoe_source == 0 or _inventory_loadout.assign_slot_to_hotbar(hoe_source, 0)), "copper hoe could not be assigned to the selected slot")
	_push_hotbar_key(KEY_1)
	await process_frame
	_expect(_interactor.get_selected_primary_action() == tilling_action, "copper hoe tilling action was not selected")
	_expect(_interactor._can_till_position(_till_grass_pos, Vector3i.UP, tilling_action), "copper hoe cannot target an exposed grass top")
	_expect(not _interactor._can_till_position(_till_grass_pos, Vector3i.RIGHT, tilling_action), "copper hoe can till a side face")
	_expect(not _interactor._can_till_position(_covered_dirt_pos, Vector3i.UP, tilling_action), "copper hoe can till below an occupied cell")
	_expect(not _interactor._can_till_position(_nonsoil_pos, Vector3i.UP, tilling_action), "copper hoe can till a non-soil block")
	var stale_change := VoxelWorldTestFixture.commit_replace(_voxel_world, _till_dirt_pos, BlockId.Type.GRASS, BlockId.Type.FARMLAND_DRY)
	_expect(stale_change == null, "atomic replacement accepted a stale source block")
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

	var full_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	var grass_max_stack: int = item_catalog.get_definition(&"grass_block").max_stack
	for index in range(InventoryModel.FILLABLE_SIZE):
		_expect(InventoryTestFixture.restore_slot(full_inventory, index, InventoryStack.new(&"grass_block", grass_max_stack)), "full-inventory flower fixture slot could not be restored")
	var full_inventory_loadout := InventoryTestFixture.create_loadout(full_inventory)
	_expect(full_inventory_loadout != null, "full-inventory flower loadout setup failed")
	var full_inventory_mining := MiningActionExecutor.new()
	_expect(full_inventory_mining.setup(full_inventory, full_inventory_loadout, unarmed_action, Callable()), "full-inventory flower mining setup failed")
	full_inventory_mining.bind_world(_voxel_world)
	_expect(full_inventory_mining.try_mine(_blocked_flower_pos, full_inventory.create_selected_item_source()).is_empty(), "full inventory allowed flower mining")
	_expect(_voxel_world.get_block_id_at(_blocked_flower_pos) == BlockId.Type.ORANGE_TULIP, "full inventory allowed flower mining")
	_expect(full_inventory.get_inventory_item_count(&"orange_tulip") == 0, "full inventory received an uncommitted flower drop")

	_player.queue_free()
	_camera.queue_free()
	_combat.queue_free()
	_world_entity_coordinator.queue_free()
	_hotbar.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
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

func _find_inventory_item(item_id: StringName) -> int:
	for index in range(_inventory.get_size()):
		var stack := _inventory.get_slot(index)
		if stack != null and stack.item_id == item_id:
			return index
	return -1

func _expect(condition: bool, message: String):
	if not condition:
		_errors.append(message)
		print("[tool_system] FAIL: %s" % message)
