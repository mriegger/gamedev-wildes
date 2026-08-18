extends SceneTree

var _failures: Array[String] = []
var _open_requests: int = 0

func _init():
	call_deferred("_run")

func _run():
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	_expect(block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog.validate(block_catalog), "item catalog invalid")

	var chest_definition := block_catalog.get_definition(BlockId.Type.CHEST)
	var container := chest_definition.container
	_expect(container != null and container.rows == 3 and container.columns == 5, "chest is not a 3x5 container")
	_expect(BlockId.is_ao_solid(BlockId.Type.CHEST), "separately rendered chest does not occlude ambient light")
	_expect(not chest_definition.is_breakable, "chest block is breakable")

	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	var chest_position := Vector3i(2, 10, 3)
	var second_chest_position := Vector3i(5, 10, 3)
	_expect(world.try_place_block(chest_position, BlockId.Type.CHEST).is_success(), "chest placement failed")
	_expect(world.try_place_block(second_chest_position, BlockId.Type.CHEST).is_success(), "second chest placement failed")
	var mine_result := world.try_mine_block(chest_position)
	_expect(mine_result.size() == 1 and mine_result[0].result == BlockEdit.Result.FAIL_NOT_BREAKABLE, "voxel model mined the chest")
	_expect(world.get_block_id_at(chest_position) == BlockId.Type.CHEST, "failed mining removed the chest")

	var player_inventory := InventoryModel.new(item_catalog)
	player_inventory.setup_empty()
	var backpack_a := InventoryModel.HOTBAR_SIZE
	var backpack_b := backpack_a + 1
	var backpack_c := backpack_a + 2
	player_inventory.slots[backpack_a] = InventoryStack.new(&"log_block", 10)
	player_inventory.slots[backpack_b] = InventoryStack.new(&"stone_block", 4)
	player_inventory.slots[0] = InventoryStack.new(&"torch", 8)
	var storage := ChestInventoryStore.new(item_catalog)
	var coordinator := ChestCoordinator.new()
	coordinator.setup(world, player_inventory, storage)
	_expect(coordinator.try_open(chest_position, container), "coordinator rejected a valid chest")
	_expect(coordinator.active_inventory != null and coordinator.active_inventory.size == 15, "active chest does not have 15 slots")
	_expect(not coordinator.quick_transfer(ChestCoordinator.PLAYER_SCOPE, 0), "quick transfer moved a hotbar item")
	_expect(coordinator.quick_transfer(ChestCoordinator.PLAYER_SCOPE, backpack_b), "backpack click did not move its stack to the chest")
	_expect(player_inventory.get_slot(backpack_b) == null, "backpack click retained its source stack")
	_expect(coordinator.active_inventory.get_slot(0).item_id == &"stone_block" and coordinator.active_inventory.get_slot(0).count == 4, "backpack click moved the wrong stack")
	_expect(coordinator.quick_transfer(ChestCoordinator.CHEST_SCOPE, 0), "chest click did not move its stack to the backpack")
	_expect(coordinator.active_inventory.get_slot(0) == null, "chest click retained its source stack")
	_expect(player_inventory.get_slot(backpack_b).item_id == &"stone_block" and player_inventory.get_slot(backpack_b).count == 4, "chest click moved the wrong stack")
	_expect(coordinator.can_handle_drop(ChestCoordinator.PLAYER_SCOPE, 0, ChestCoordinator.CHEST_SCOPE, 2, 3), "hotbar item was rejected as a chest transfer source")
	_expect(coordinator.handle_drop(ChestCoordinator.PLAYER_SCOPE, 0, ChestCoordinator.CHEST_SCOPE, 2, 3), "partial hotbar-to-chest transfer failed")
	_expect(player_inventory.get_slot(0).count == 5, "hotbar retained the wrong remainder")
	_expect(coordinator.active_inventory.get_slot(2).item_id == &"torch" and coordinator.active_inventory.get_slot(2).count == 3, "chest received the wrong hotbar stack")
	_expect(coordinator.handle_drop(ChestCoordinator.CHEST_SCOPE, 2, ChestCoordinator.PLAYER_SCOPE, 1, 2), "chest-to-hotbar transfer failed")
	_expect(coordinator.active_inventory.get_slot(2).count == 1, "chest retained the wrong hotbar-transfer remainder")
	_expect(player_inventory.get_slot(1).item_id == &"torch" and player_inventory.get_slot(1).count == 2, "hotbar received the wrong chest stack")

	_expect(coordinator.handle_drop(ChestCoordinator.PLAYER_SCOPE, backpack_a, ChestCoordinator.CHEST_SCOPE, 0, 4), "partial backpack-to-chest transfer failed")
	_expect(player_inventory.get_slot(backpack_a).count == 6, "partial transfer removed the wrong backpack count")
	_expect(coordinator.active_inventory.get_slot(0).item_id == &"log_block" and coordinator.active_inventory.get_slot(0).count == 4, "partial transfer stored the wrong chest stack")
	_expect(coordinator.handle_drop(ChestCoordinator.CHEST_SCOPE, 0, ChestCoordinator.PLAYER_SCOPE, backpack_c, 2), "partial chest-to-backpack transfer failed")
	_expect(coordinator.active_inventory.get_slot(0).count == 2, "chest retained the wrong remainder")
	_expect(player_inventory.get_slot(backpack_c).item_id == &"log_block" and player_inventory.get_slot(backpack_c).count == 2, "backpack received the wrong partial stack")

	coordinator.active_inventory.slots[1] = InventoryStack.new(&"sand_block", 3)
	_expect(coordinator.handle_drop(ChestCoordinator.PLAYER_SCOPE, backpack_b, ChestCoordinator.CHEST_SCOPE, 1, 4), "backpack/chest swap failed")
	_expect(player_inventory.get_slot(backpack_b).item_id == &"sand_block", "swap did not return the chest item to the backpack")
	_expect(coordinator.active_inventory.get_slot(1).item_id == &"stone_block", "swap did not move the backpack item into the chest")
	var first_chest_inventory := coordinator.active_inventory
	coordinator.close()
	_expect(coordinator.try_open(second_chest_position, container), "coordinator rejected the second chest")
	_expect(coordinator.active_inventory != first_chest_inventory, "two world chests share one inventory model")
	_expect(coordinator.active_inventory.encode_slots().all(func(stack): return stack == null), "new second chest inherited the first chest's contents")
	coordinator.active_inventory.slots[0] = InventoryStack.new(&"leaves_block", 5)
	coordinator.close()
	_expect(coordinator.try_open(chest_position, container), "coordinator could not reopen the first chest")
	_expect(coordinator.active_inventory == first_chest_inventory, "reopened chest did not recover its position-linked inventory")
	_expect(coordinator.active_inventory.get_slot(1).item_id == &"stone_block", "opening another chest changed the first chest")
	_expect(storage.get_inventory(second_chest_position).get_slot(0).item_id == &"leaves_block", "first chest changed the second chest")

	var encoded: Variant = JSON.parse_string(JSON.stringify(storage.snapshot()))
	var restored_storage := ChestInventoryStore.new(item_catalog)
	_expect(encoded is Dictionary and restored_storage.restore(encoded), "chest storage JSON round trip failed")
	var oversized_storage := ChestInventoryStore.new(item_catalog)
	_expect(not oversized_storage.restore({"0,0,0": {"size": ContainerBlockDefinition.MAX_SLOT_COUNT + 1, "slots": []}}), "oversized chest save was accepted")
	var restored_inventory := restored_storage.get_inventory(chest_position)
	_expect(restored_inventory != null and restored_inventory.size == 15, "restored chest has the wrong size")
	_expect(restored_inventory.get_slot(0).item_id == &"log_block" and restored_inventory.get_slot(0).count == 2, "restored chest changed a partial stack")
	_expect(restored_inventory.get_slot(1).item_id == &"stone_block" and restored_inventory.get_slot(1).count == 4, "restored chest changed a swapped stack")
	var restored_second_inventory := restored_storage.get_inventory(second_chest_position)
	_expect(restored_second_inventory != null and restored_second_inventory != restored_inventory, "restored world chests share one inventory model")
	_expect(restored_second_inventory.get_slot(0).item_id == &"leaves_block" and restored_second_inventory.get_slot(0).count == 5, "restored second chest lost its position-linked contents")
	var full_player_inventory := InventoryModel.new(item_catalog)
	for index in range(InventoryModel.HOTBAR_SIZE, InventoryModel.FILLABLE_SIZE):
		full_player_inventory.slots[index] = InventoryStack.new(&"sand_block", item_catalog.get_definition(&"sand_block").max_stack)
	var full_storage := ChestInventoryStore.new(item_catalog)
	var full_coordinator := ChestCoordinator.new()
	full_coordinator.setup(world, full_player_inventory, full_storage)
	_expect(full_coordinator.try_open(second_chest_position, container), "full-backpack coordinator could not open a chest")
	full_coordinator.active_inventory.slots[0] = InventoryStack.new(&"log_block", 3)
	_expect(not full_coordinator.quick_transfer(ChestCoordinator.CHEST_SCOPE, 0), "chest click moved an item into a full backpack")
	_expect(not full_coordinator.move_all_to_backpack(), "move-all changed a full backpack")
	_expect(full_coordinator.active_inventory.get_slot(0).count == 3, "full backpack transfer changed the chest stack")

	var input := InputBuffer.new()
	var interaction_inventory := InventoryModel.new(item_catalog)
	interaction_inventory.slots[0] = InventoryStack.new(&"copper_sword", 1)
	var interactor := PlayerInteractor.new()
	interactor.inventory_model = interaction_inventory
	interactor._input_buffer = input
	interactor.voxel_space = world
	interactor.editable_voxel_world = null
	_expect(interactor._get_target_container(chest_position) == null, "read-only voxel space exposed an overworld chest interaction")
	interactor.editable_voxel_world = world
	_expect(interactor._get_target_container(chest_position) == container, "editable overworld did not expose its chest interaction")
	interactor.target_has = true
	interactor.target_block = chest_position
	interactor.target_container = container
	interactor.can_interact_target = true
	interactor.container_open_requested.connect(_on_container_open_requested)
	input.primary_use_just = true
	interactor._handle_item_actions(0.0)
	_expect(_open_requests == 1, "left click did not request the chest UI")
	_expect(interactor.melee_attack_queue == 0 and not interactor.is_mining, "chest click also started an item action")
	interactor.can_interact_target = false
	_expect(not interactor._try_open_target_container(), "out-of-range chest opened")
	_expect(_open_requests == 1, "out-of-range chest emitted an open request")
	var targeting := TargetingView.new()
	targeting.interactor = interactor
	var chest_renderer := ChestRenderer.new()
	chest_renderer.setup(block_catalog)
	get_root().add_child(chest_renderer)
	chest_renderer.spawn_chest(chest_position)
	_expect(chest_renderer.unload_chests_in_chunk(0, 0, 16) == 1 and not chest_renderer.chest_instances.has(chest_position), "chunk unload retained its rendered chest")
	_expect(chest_renderer.load_chests_for_chunk(0, 0, 16, world) == 2, "chunk reload did not restore both rendered chests")
	targeting.chest_renderer = chest_renderer
	get_root().add_child(targeting)
	targeting.set_physics_process(false)
	await process_frame
	_expect(not targeting._should_show_mining_outline(true), "container target shows the mining wireframe")
	interactor.can_interact_target = true
	_expect(targeting._should_show_interaction(), "in-range chest does not expose its hover presentation without a pickaxe")
	targeting._update_interaction_visuals(1.0)
	chest_renderer._process(1.0)
	var rendered_chest := chest_renderer.chest_instances[chest_position] as Node3D
	var rendered_lid := chest_renderer.get_lid(chest_position)
	_expect(rendered_chest.get_node_or_null("Body") != null and rendered_lid != null, "chest is not rendered as separate body and lid meshes")
	var body_height := 1.0 - ChestRenderer.LID_HEIGHT
	var body_face_positions := {
		"Front": Vector3(0.5, body_height * 0.5, 0.0),
		"Back": Vector3(0.5, body_height * 0.5, 1.0),
		"Left": Vector3(0.0, body_height * 0.5, 0.5),
		"Right": Vector3(1.0, body_height * 0.5, 0.5),
		"Bottom": Vector3(0.5, 0.0, 0.5),
	}
	for face_name in body_face_positions:
		var face := rendered_chest.get_node("Body/%s" % face_name) as MeshInstance3D
		_expect(face != null and face.position == body_face_positions[face_name], "chest body %s face has the wrong transform" % face_name)
	var body_texture := ((rendered_chest.get_node("Body/Right") as MeshInstance3D).material_override as StandardMaterial3D).albedo_texture
	var body_front_texture := ((rendered_chest.get_node("Body/Front") as MeshInstance3D).material_override as StandardMaterial3D).albedo_texture
	var lid_texture := ((rendered_lid.get_node("Shell") as MeshInstance3D).material_override as StandardMaterial3D).albedo_texture
	var lid_front_texture := ((rendered_lid.get_node("Front") as MeshInstance3D).material_override as StandardMaterial3D).albedo_texture
	_expect(body_texture.resource_path == "res://assets/textures/blocks/chest_body_side.png", "chest body does not use its dedicated light wood texture")
	_expect(body_front_texture.resource_path == "res://assets/textures/blocks/chest_body_front.png", "chest body front does not use its lower latch texture")
	_expect(lid_texture.resource_path == "res://assets/textures/blocks/chest_lid_side.png", "chest lid does not use its dedicated dark wood texture")
	_expect(lid_front_texture.resource_path == "res://assets/textures/blocks/chest_lid_front.png", "chest lid front does not use its upper latch texture")
	var rendered_interior := rendered_chest.get_node("Interior") as MeshInstance3D
	_expect(rendered_interior != null and (rendered_interior.mesh as PlaneMesh).size == Vector2.ONE, "open chest interior does not fully cover the body top")
	_expect(rendered_lid.position == Vector3(0.5, body_height, 1.0), "chest lid pivot is not on the rear bottom edge")
	_expect(is_equal_approx((rendered_lid.get_node("Shell") as MeshInstance3D).position.y, ChestRenderer.LID_HEIGHT * 0.5), "chest lid shell is not above its bottom-edge pivot")
	_expect(is_equal_approx(rendered_lid.rotation.x, deg_to_rad(ChestRenderer.LID_OPEN_ANGLE)), "hovered chest lid did not hinge open")
	var highlighted_body := rendered_chest.get_node("Body/Right") as MeshInstance3D
	var highlighted_lid := rendered_lid.get_node("Shell") as MeshInstance3D
	_expect(highlighted_body.material_overlay != null, "hovered chest body is not highlighted")
	_expect(highlighted_lid.material_overlay != null, "hovered chest lid is not highlighted")
	var highlight_material := highlighted_body.material_overlay as StandardMaterial3D
	_expect(highlight_material != null and is_equal_approx(highlight_material.albedo_color.a, ChestRenderer.HIGHLIGHT_ALPHA), "chest hover highlight has the wrong strength")
	interactor.can_interact_target = false
	targeting._update_interaction_visuals(1.0)
	chest_renderer._process(1.0)
	_expect(is_zero_approx(rendered_lid.rotation.x), "out-of-range chest lid stayed open")
	_expect(highlighted_body.material_overlay == null and highlighted_lid.material_overlay == null, "out-of-range chest retained its hover highlight")
	var preview_position := Vector3i(9, 11, 3)
	chest_renderer.set_placement_preview(preview_position, true)
	var chest_preview := chest_renderer._placement_preview
	var preview_body := chest_preview.get_node("Body/Right") as MeshInstance3D
	var preview_lid := chest_preview.get_node("Lid") as Node3D
	var preview_body_material := preview_body.material_override as StandardMaterial3D
	_expect(chest_preview.visible and chest_preview.global_position == Vector3(preview_position), "chest placement preview used the wrong position")
	_expect(preview_lid != null and preview_body_material.albedo_texture.resource_path == body_texture.resource_path, "chest placement preview does not match the placed chest model")
	_expect(is_equal_approx(preview_body_material.albedo_color.a, 0.48), "valid chest placement preview has the wrong opacity")
	chest_renderer.set_placement_preview(preview_position, false)
	_expect(is_equal_approx(preview_body_material.albedo_color.a, 0.18), "invalid chest placement preview has the wrong opacity")
	chest_renderer.set_placement_preview(null, false)
	_expect(not chest_preview.visible, "chest placement preview remained visible after clearing")
	_test_split_chest_textures()
	interactor.free()
	targeting.queue_free()
	chest_renderer.queue_free()
	await process_frame

	var stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	var inventory_stats := InventoryStatCoordinator.new()
	_expect(inventory_stats.setup(player_inventory, stats), "inventory stat coordinator setup failed")
	var recipe_catalog := load("res://crafting/crafting_recipe_catalog.tres") as CraftingRecipeCatalog
	var crafting := CraftingCoordinator.new()
	crafting.setup(player_inventory, recipe_catalog)
	var hud := (load("res://ui/hud/hud.tscn") as PackedScene).instantiate() as HUD
	get_root().add_child(hud)
	await process_frame
	var ui_coordinator := ChestCoordinator.new()
	ui_coordinator.setup(world, player_inventory, restored_storage)
	hud.setup_with_camera(player_inventory, inventory_stats, crafting, recipe_catalog, null, stats, ItemProficiency.new(item_catalog), ui_coordinator)
	hud.open_container(chest_position, container)
	_expect(hud.chest_panel.is_open(), "chest panel did not open")
	_expect(hud.side_panel.is_open(), "opening a chest did not open the right-side backpack")
	_expect(hud.chest_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "full-screen chest overlay blocks the backpack")
	_expect(hud.chest_panel._panel.mouse_filter == Control.MOUSE_FILTER_STOP, "chest modal passes input through to the world")
	_expect(hud.chest_panel.get_chest_slots().size() == 15, "chest panel did not create 15 slots")
	_expect(hud.chest_panel.get_node_or_null("Center/Panel/Margin/Content/BackpackGrid") == null, "centered chest panel still duplicates the backpack")
	_expect(hud.chest_panel._move_all_button != null, "chest panel has no move-all button")
	_expect(hud.chest_panel._move_all_button.get_parent().name == "ActionRow", "move-all button is not above the chest grid")
	var move_all_icon := hud.chest_panel._move_all_button.get_node("Content/Icon") as TextureRect
	var move_all_text := hud.chest_panel._move_all_button.get_node("Content/Text") as Label
	_expect(move_all_text.text == "Take all" and move_all_text.get_theme_font_size("font_size") == 12, "move-all button label is missing or too large")
	_expect(move_all_icon.texture.resource_path == "res://assets/images/icons/button/move_to_backpack.png", "move-all button uses the wrong icon")
	_expect(move_all_icon.custom_minimum_size == Vector2(16, 16), "move-all button icon is too large")
	_expect(hud.chest_panel._chest_grid.columns == 5, "chest panel does not use five columns")
	var saved_backpack_slots: Array[InventoryStack] = []
	for index in range(InventoryModel.HOTBAR_SIZE, InventoryModel.FILLABLE_SIZE):
		saved_backpack_slots.append(null if player_inventory.slots[index] == null else player_inventory.slots[index].copy())
	for index in range(InventoryModel.HOTBAR_SIZE, InventoryModel.FILLABLE_SIZE):
		player_inventory.slots[index] = InventoryStack.new(&"sand_block", item_catalog.get_definition(&"sand_block").max_stack)
	player_inventory.inventory_changed.emit()
	_expect(hud.chest_panel._move_all_button.disabled, "move-all stayed enabled for a full backpack")
	for offset in range(saved_backpack_slots.size()):
		player_inventory.slots[InventoryModel.HOTBAR_SIZE + offset] = saved_backpack_slots[offset]
	player_inventory.inventory_changed.emit()
	_expect(not hud.chest_panel._move_all_button.disabled, "move-all did not re-enable when backpack space became available")
	_expect(hud.side_panel._equipment_button.is_disabled(), "equipment tab remains available while chest storage is open")
	var chest_slot := hud.chest_panel.get_chest_slots()[0]
	var backpack_slot := hud.side_panel.get_inventory_slots()[3]
	hud.chest_panel._update_layout_for_size(Vector2(684, 480))
	var rendered_chest_right := hud.chest_panel._panel.position.x + hud.chest_panel._panel.size.x * hud.chest_panel._panel.scale.x
	_expect(rendered_chest_right <= 684.0 - SidePanel.PANEL_WIDTH + 0.01, "chest panel overlaps the backpack at 684px: %.2f" % rendered_chest_right)
	hud.chest_panel._update_layout()
	hud.side_panel._set_progress(1.0)
	var hover_motion := InputEventMouseMotion.new()
	hover_motion.position = backpack_slot.get_global_rect().get_center()
	hover_motion.global_position = hover_motion.position
	get_root().push_input(hover_motion, true)
	await process_frame
	var hovered: Control = get_root().gui_get_hovered_control()
	var backpack_receives_pointer := false
	while hovered != null:
		if hovered == backpack_slot:
			backpack_receives_pointer = true
			break
		hovered = hovered.get_parent() as Control
	_expect(backpack_receives_pointer, "chest overlay intercepts pointer routing over the backpack")
	var quick_backpack_slot := hud.side_panel.get_inventory_slots()[10]
	player_inventory.slots[quick_backpack_slot.slot_index] = InventoryStack.new(&"grass_block", 2)
	player_inventory.inventory_changed.emit()
	var interrupted_press := InputEventMouseButton.new()
	interrupted_press.button_index = MOUSE_BUTTON_LEFT
	interrupted_press.pressed = true
	quick_backpack_slot._gui_input(interrupted_press)
	hud.side_panel.set_inventory_transfer_context(null)
	var interrupted_release := InputEventMouseButton.new()
	interrupted_release.button_index = MOUSE_BUTTON_LEFT
	interrupted_release.pressed = false
	quick_backpack_slot._gui_input(interrupted_release)
	_expect(player_inventory.get_slot(quick_backpack_slot.slot_index).count == 2, "closing transfer context completed a pending click")
	hud.side_panel.set_inventory_transfer_context(ui_coordinator)
	_click_slot(quick_backpack_slot)
	_expect(player_inventory.get_slot(quick_backpack_slot.slot_index) == null, "clicking a backpack item did not clear its slot")
	var quick_chest_slot := hud.chest_panel.get_chest_slots()[3]
	_expect(restored_inventory.get_slot(quick_chest_slot.slot_index).item_id == &"grass_block", "clicking a backpack item did not add it to the chest")
	_click_slot(quick_chest_slot)
	_expect(restored_inventory.get_slot(quick_chest_slot.slot_index) == null, "clicking a chest item did not clear its slot")
	_expect(player_inventory.get_backpack_item_count(&"grass_block") == 2, "clicking a chest item did not add it to the backpack")
	var ui_drag := {
		"source_scope": ChestCoordinator.CHEST_SCOPE,
		"source_index": chest_slot.slot_index,
		"drag_count": 1,
	}
	var drag_backpack_slot := hud.side_panel.get_inventory_slots()[15]
	_expect(drag_backpack_slot._can_drop_data(Vector2.ZERO, ui_drag), "backpack UI rejected a chest drag")
	_expect(not hud.side_panel._trash_target._can_drop_data(Vector2.ZERO, ui_drag), "trash target accepted a chest drag as a player item")
	drag_backpack_slot._drop_data(Vector2.ZERO, ui_drag)
	_expect(restored_inventory.get_slot(0).count == 1, "UI drag did not remove one chest item")
	_expect(player_inventory.get_slot(drag_backpack_slot.slot_index).item_id == &"log_block", "UI drag did not add the item to the backpack")
	var chest_torch_slot := hud.chest_panel.get_chest_slots()[2]
	var hotbar_slot := hud.hotbar.slot_nodes[1]
	var chest_to_hotbar_drag := {
		"source_scope": ChestCoordinator.CHEST_SCOPE,
		"source_index": chest_torch_slot.slot_index,
		"drag_count": 1,
	}
	_expect(hotbar_slot._can_drop_data(Vector2.ZERO, chest_to_hotbar_drag), "hotbar UI rejected a chest drag")
	hotbar_slot._drop_data(Vector2.ZERO, chest_to_hotbar_drag)
	_expect(restored_inventory.get_slot(2) == null, "chest-to-hotbar UI drag retained the chest stack")
	_expect(player_inventory.get_slot(1).item_id == &"torch" and player_inventory.get_slot(1).count == 3, "chest-to-hotbar UI drag produced the wrong stack")
	var empty_chest_slot := hud.chest_panel.get_chest_slots()[3]
	var hotbar_to_chest_drag := {
		"source_scope": InventoryTransferCoordinator.PLAYER_SCOPE,
		"source_index": hotbar_slot.slot_index,
		"drag_count": 2,
	}
	_expect(empty_chest_slot._can_drop_data(Vector2.ZERO, hotbar_to_chest_drag), "chest UI rejected a hotbar drag")
	empty_chest_slot._drop_data(Vector2.ZERO, hotbar_to_chest_drag)
	_expect(player_inventory.get_slot(1).count == 1, "hotbar-to-chest UI drag retained the wrong hotbar remainder")
	_expect(restored_inventory.get_slot(3).item_id == &"torch" and restored_inventory.get_slot(3).count == 2, "hotbar-to-chest UI drag produced the wrong chest stack")
	var chest_counts: Dictionary[StringName, int] = {}
	for stack in restored_inventory.slots:
		if stack != null:
			chest_counts[stack.item_id] = chest_counts.get(stack.item_id, 0) + stack.count
	for item_id in chest_counts:
		chest_counts[item_id] = player_inventory.get_inventory_item_count(item_id) + chest_counts[item_id]
	hud.chest_panel._move_all_button.pressed.emit()
	_expect(restored_inventory.slots.all(func(stack): return stack == null), "move-all retained items in the chest")
	for item_id in chest_counts:
		_expect(player_inventory.get_inventory_item_count(item_id) == chest_counts[item_id], "move-all lost %s items" % item_id)
	_expect(hud.chest_panel._move_all_button.disabled, "move-all button stayed enabled for an empty chest")
	hud.toggle_backpack()
	_expect(not hud.chest_panel.is_open() and not hud.side_panel.is_open(), "P did not close the chest and backpack together")
	hud.open_container(chest_position, container)
	hud.toggle_crafting()
	_expect(not hud.chest_panel.is_open(), "Tab did not close the chest")
	_expect(hud.side_panel.is_open() and hud.crafting_panel.is_open(), "Tab did not replace the chest with backpack and crafting")
	_expect(backpack_slot.inventory_transfer_coordinator == null, "closing the chest retained its transfer context")
	_expect(hotbar_slot.inventory_transfer_coordinator == null, "closing the chest retained the hotbar transfer context")
	_expect(not hud.side_panel._equipment_button.is_disabled(), "closing the chest left the equipment tab disabled")
	hud.close_side_panel_immediate()
	hud.queue_free()
	await process_frame

	if _failures.is_empty():
		print("CHEST_SYSTEM PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("[chest_system_integration] FAIL: %s" % failure)
		quit(1)

func _expect(condition: bool, message: String):
	if not condition:
		_failures.append(message)

func _on_container_open_requested(_position: Vector3i, _definition: ContainerBlockDefinition):
	_open_requests += 1

func _click_slot(slot: InventorySlot):
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	slot._gui_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	slot._gui_input(release)

func _test_split_chest_textures():
	var body_side := (load("res://assets/textures/blocks/chest_body_side.png") as Texture2D).get_image()
	var body_front := (load("res://assets/textures/blocks/chest_body_front.png") as Texture2D).get_image()
	var lid_side := (load("res://assets/textures/blocks/chest_lid_side.png") as Texture2D).get_image()
	var lid_front := (load("res://assets/textures/blocks/chest_lid_front.png") as Texture2D).get_image()
	for image in [body_side, body_front, lid_side, lid_front]:
		_expect(image.get_size() == Vector2i(16, 16), "split chest texture is not 16x16")
	var body_differences: Array[Vector2i] = []
	var lid_differences: Array[Vector2i] = []
	var body_luminance := 0.0
	var lid_luminance := 0.0
	for y in range(16):
		for x in range(16):
			if body_front.get_pixel(x, y) != body_side.get_pixel(x, y):
				body_differences.append(Vector2i(x, y))
			if lid_front.get_pixel(x, y) != lid_side.get_pixel(x, y):
				lid_differences.append(Vector2i(x, y))
			if x > 0 and x < 15:
				body_luminance += body_side.get_pixel(x, y).get_luminance()
				lid_luminance += lid_side.get_pixel(x, y).get_luminance()
	_expect(body_differences == [Vector2i(7, 0), Vector2i(8, 0), Vector2i(7, 1), Vector2i(8, 1)], "chest body front does not contain only the lower latch half at its top")
	_expect(lid_differences == [Vector2i(7, 14), Vector2i(8, 14), Vector2i(7, 15), Vector2i(8, 15)], "chest lid front does not contain only the upper latch half at its bottom")
	for x in range(2, 14):
		_expect(body_side.get_pixel(x, 5) == body_side.get_pixel(x, 10), "chest body plank seams do not match")
		_expect(body_side.get_pixel(x, 5).get_luminance() < body_side.get_pixel(x, 4).get_luminance(), "chest body does not have three visible plank rows")
	_expect(body_luminance > lid_luminance, "chest body wood is not lighter than the lid wood")
