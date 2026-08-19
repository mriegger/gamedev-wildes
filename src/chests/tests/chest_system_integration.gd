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

	var chest_block := block_catalog.get_definition(BlockId.Type.CHEST)
	var container := chest_block.container
	_expect(container != null and container.rows == 3 and container.columns == 5, "chest is not a 3x5 container")
	_expect(BlockId.is_ao_solid(BlockId.Type.CHEST), "separately rendered chest does not occlude ambient light")
	_expect(chest_block.is_breakable and chest_block.mining_tool_tag == &"pickaxe" and chest_block.minimum_mining_power == 1, "chest mining metadata is invalid")
	var unarmed := load("res://items/actions/definitions/unarmed_mining.tres") as MiningActionDefinition
	var stone_pickaxe := item_catalog.get_definition(&"stone_pickaxe").primary_action as MiningActionDefinition
	var copper_pickaxe := item_catalog.get_definition(&"copper_pickaxe").primary_action as MiningActionDefinition
	_expect(not unarmed.can_mine(chest_block), "hands can mine the chest")
	_expect(stone_pickaxe.can_mine(chest_block), "stone pickaxe cannot mine the chest")
	_expect(copper_pickaxe.can_mine(chest_block), "copper pickaxe cannot mine the chest")

	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	var chest_position := Vector3i(2, 10, 3)
	var second_chest_position := Vector3i(5, 10, 3)
	var pickup_position := Vector3i(8, 10, 3)
	var attached_torch_position := pickup_position + Vector3i(1, 0, 0)
	_expect(world.try_place_block(chest_position, BlockId.Type.CHEST).is_success(), "chest placement failed")
	_expect(world.try_place_block(second_chest_position, BlockId.Type.CHEST).is_success(), "second chest placement failed")
	_expect(world.try_place_block(pickup_position, BlockId.Type.CHEST).is_success(), "pickup chest placement failed")
	_expect(world.try_place_block(attached_torch_position, BlockId.Type.TORCH, Vector3i(-1, 0, 0)).is_success(), "pickup chest torch placement failed")

	var player_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	player_inventory.setup_empty()
	var backpack_a := InventoryModel.HOTBAR_SIZE
	var backpack_b := backpack_a + 1
	var backpack_c := backpack_a + 2
	var backpack_d := backpack_a + 3
	var backpack_e := backpack_a + 4
	_expect(InventoryTestFixture.restore_slot(player_inventory, backpack_a, InventoryStack.new(&"log_block", 10)), "log fixture failed")
	_expect(InventoryTestFixture.restore_slot(player_inventory, backpack_b, InventoryStack.new(&"stone_block", 4)), "stone fixture failed")
	_expect(InventoryTestFixture.restore_slot(player_inventory, backpack_e, InventoryStack.new(&"grass_block", 1)), "reentrancy fixture failed")
	_expect(InventoryTestFixture.restore_slot(player_inventory, 0, InventoryStack.new(&"torch", 8)), "torch fixture failed")
	var vicious := item_catalog.get_equipment_affix(&"vicious")
	var variant_affixes: Array[EquipmentAffixDefinition] = [vicious]
	var variant_runes: Array[StringName] = [&"basic_rune"]
	var variant := player_inventory.equipment_instance_factory.create(&"copper_sword", variant_affixes, variant_runes)
	_expect(variant != null, "variant sword fixture failed")
	_expect(InventoryTestFixture.restore_slot(player_inventory, backpack_d, InventoryStack.new(&"copper_sword", 1, variant)), "variant sword restore failed")
	var player_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	var player_loadout := InventoryTestFixture.create_loadout(player_inventory, player_stats)
	_expect(player_loadout != null, "player loadout setup failed")
	var storage := ChestStorage.new(item_catalog, player_inventory.equipment_instance_factory, container.get_slot_count())
	_expect(storage.create_chest(chest_position), "first chest storage creation failed")
	_expect(storage.create_chest(second_chest_position), "second chest storage creation failed")
	_expect(storage.create_chest(pickup_position), "pickup chest storage creation failed")
	_expect(storage.add_stack(chest_position, InventoryStack.new(&"sand_block", 3), 1), "swap fixture storage failed")
	_expect(storage.add_stack(second_chest_position, InventoryStack.new(&"leaves_block", 5), 0), "second chest fixture storage failed")
	_expect(storage.add_stack(pickup_position, InventoryStack.new(&"log_block", 1), 0), "pickup fixture storage failed")
	var coordinator := ChestCoordinator.new()
	_expect(coordinator.setup(storage, player_inventory, player_loadout, world, chest_block), "coordinator setup failed")
	world.block_edit_committed.connect(coordinator.handle_block_edit)
	var bound_snapshot := storage.snapshot()
	var bound_revision := storage.get_revision()
	_expect(storage.prepare_add_stack(chest_position, InventoryStack.new(&"dirt_block", 1), 3) != null, "bound storage rejected canonical add preparation")
	_expect(storage.prepare_remove_stack(chest_position, 1) != null, "bound storage rejected canonical remove preparation")
	_expect(not storage.add_stack(chest_position, InventoryStack.new(&"dirt_block", 1), 3), "bound storage allowed direct add mutation")
	_expect(storage.remove_stack(chest_position, 1) == null, "bound storage allowed direct remove mutation")
	_expect(storage.snapshot() == bound_snapshot and storage.get_revision() == bound_revision, "bound direct mutation guards changed storage")
	_expect(coordinator.try_open(chest_position, container), "coordinator rejected a valid chest")
	_expect(coordinator.get_active_position() == chest_position and storage.get_slot_count() == 15, "active chest does not have 15 slots")
	_expect(not coordinator.quick_transfer(ChestCoordinator.PLAYER_SCOPE, 0), "quick transfer moved a hotbar item")
	var inventory_observations: Array[bool] = []
	var contents_observations: Array[bool] = []
	var reentrant_results: Array[bool] = []
	var inventory_observer := func():
		inventory_observations.append(player_inventory.get_slot(backpack_b) == null and storage.get_slot(chest_position, 0) != null)
		reentrant_results.append(coordinator.quick_transfer(ChestCoordinator.PLAYER_SCOPE, backpack_e))
	var contents_observer := func(position: Vector3i):
		if position == chest_position:
			contents_observations.append(player_inventory.get_slot(backpack_b) == null and storage.get_slot(chest_position, 0) != null)
	player_inventory.inventory_changed.connect(inventory_observer)
	coordinator.contents_changed.connect(contents_observer)
	_expect(coordinator.quick_transfer(ChestCoordinator.PLAYER_SCOPE, backpack_b), "backpack click did not move its stack to the chest")
	player_inventory.inventory_changed.disconnect(inventory_observer)
	coordinator.contents_changed.disconnect(contents_observer)
	_expect(inventory_observations == [true] and contents_observations == [true], "cross-owner observers saw a partially committed transfer")
	_expect(reentrant_results == [false] and player_inventory.get_slot(backpack_e).count == 1, "cross-owner notification allowed a reentrant chest mutation")
	_expect(player_inventory.get_slot(backpack_b) == null, "backpack click retained its source stack")
	_expect(storage.get_slot(chest_position, 0).item_id == &"stone_block" and storage.get_slot(chest_position, 0).count == 4, "backpack click moved the wrong stack")
	_expect(coordinator.quick_transfer(ChestCoordinator.CHEST_SCOPE, 0), "chest click did not move its stack to the backpack")
	_expect(storage.get_slot(chest_position, 0) == null, "chest click retained its source stack")
	_expect(player_inventory.get_slot(backpack_b).item_id == &"stone_block" and player_inventory.get_slot(backpack_b).count == 4, "chest click moved the wrong stack")
	_expect(coordinator.can_handle_drop(ChestCoordinator.PLAYER_SCOPE, 0, ChestCoordinator.CHEST_SCOPE, 2, 3), "hotbar item was rejected as a chest transfer source")
	_expect(coordinator.handle_drop(ChestCoordinator.PLAYER_SCOPE, 0, ChestCoordinator.CHEST_SCOPE, 2, 3), "partial hotbar-to-chest transfer failed")
	_expect(player_inventory.get_slot(0).count == 5, "hotbar retained the wrong remainder")
	_expect(storage.get_slot(chest_position, 2).item_id == &"torch" and storage.get_slot(chest_position, 2).count == 3, "chest received the wrong hotbar stack")
	_expect(coordinator.handle_drop(ChestCoordinator.CHEST_SCOPE, 2, ChestCoordinator.PLAYER_SCOPE, 1, 2), "chest-to-hotbar transfer failed")
	_expect(storage.get_slot(chest_position, 2).count == 1, "chest retained the wrong hotbar-transfer remainder")
	_expect(player_inventory.get_slot(1).item_id == &"torch" and player_inventory.get_slot(1).count == 2, "hotbar received the wrong chest stack")

	_expect(coordinator.handle_drop(ChestCoordinator.PLAYER_SCOPE, backpack_a, ChestCoordinator.CHEST_SCOPE, 0, 4), "partial backpack-to-chest transfer failed")
	_expect(player_inventory.get_slot(backpack_a).count == 6, "partial transfer removed the wrong backpack count")
	_expect(storage.get_slot(chest_position, 0).item_id == &"log_block" and storage.get_slot(chest_position, 0).count == 4, "partial transfer stored the wrong chest stack")
	_expect(coordinator.handle_drop(ChestCoordinator.CHEST_SCOPE, 0, ChestCoordinator.PLAYER_SCOPE, backpack_c, 2), "partial chest-to-backpack transfer failed")
	_expect(storage.get_slot(chest_position, 0).count == 2, "chest retained the wrong remainder")
	_expect(player_inventory.get_slot(backpack_c).item_id == &"log_block" and player_inventory.get_slot(backpack_c).count == 2, "backpack received the wrong partial stack")

	_expect(coordinator.handle_drop(ChestCoordinator.PLAYER_SCOPE, backpack_b, ChestCoordinator.CHEST_SCOPE, 1, 4), "backpack/chest swap failed")
	_expect(player_inventory.get_slot(backpack_b).item_id == &"sand_block", "swap did not return the chest item to the backpack")
	_expect(storage.get_slot(chest_position, 1).item_id == &"stone_block", "swap did not move the backpack item into the chest")
	var variant_fingerprint := variant.to_dict()
	_expect(coordinator.handle_drop(ChestCoordinator.PLAYER_SCOPE, backpack_d, ChestCoordinator.CHEST_SCOPE, 4, 1), "variant sword did not move into chest storage")
	_expect(storage.get_slot(chest_position, 4).equipment_instance.to_dict() == variant_fingerprint, "variant sword changed while entering chest storage")
	_expect(coordinator.handle_drop(ChestCoordinator.CHEST_SCOPE, 4, ChestCoordinator.PLAYER_SCOPE, backpack_d, 1), "variant sword did not return to the backpack")
	_expect(player_inventory.get_slot(backpack_d).equipment_instance.to_dict() == variant_fingerprint, "variant sword changed while leaving chest storage")
	_expect(coordinator.handle_drop(ChestCoordinator.PLAYER_SCOPE, backpack_d, ChestCoordinator.CHEST_SCOPE, 4, 1), "variant sword did not return to chest storage")
	coordinator.close()
	_expect(coordinator.try_open(second_chest_position, container), "coordinator rejected the second chest")
	_expect(storage.get_slot(second_chest_position, 0).item_id == &"leaves_block", "second chest lost its position-linked contents")
	coordinator.close()
	_expect(coordinator.try_open(chest_position, container), "coordinator could not reopen the first chest")
	_expect(storage.get_slot(chest_position, 1).item_id == &"stone_block", "opening another chest changed the first chest")
	_expect(storage.get_slot(second_chest_position, 0).item_id == &"leaves_block", "first chest changed the second chest")

	_expect(coordinator.try_open(pickup_position, container), "pickup chest did not open")
	_expect(not coordinator.can_break(pickup_position), "non-empty chest was breakable")
	_expect(coordinator.quick_transfer(ChestCoordinator.CHEST_SCOPE, 0), "pickup chest contents could not be removed")
	_expect(coordinator.can_break(pickup_position), "empty chest remained blocked")
	var pickup_edits := world.try_mine_block(pickup_position)
	_expect(not pickup_edits.is_empty() and pickup_edits[0].is_success(), "empty chest mining failed")
	_expect(not coordinator.is_open() and world.get_block_id_at(pickup_position) == BlockId.Type.AIR, "mined chest remained open or in the world")
	_expect(world.get_block_id_at(attached_torch_position) == BlockId.Type.AIR, "mined chest left its attached torch behind")
	_expect(not storage.has_chest(pickup_position), "mined chest retained storage state")
	var lifecycle_position := Vector3i(11, 10, 3)
	_expect(world.try_place_block(lifecycle_position, BlockId.Type.CHEST).is_success(), "runtime chest placement failed")
	_expect(storage.has_chest(lifecycle_position) and storage.is_chest_empty(lifecycle_position), "runtime chest placement did not create storage")
	var lifecycle_edits := world.try_mine_block(lifecycle_position)
	_expect(not lifecycle_edits.is_empty() and lifecycle_edits[0].is_success(), "runtime chest mining returned no edit")
	_expect(not storage.has_chest(lifecycle_position), "runtime chest mining retained storage")

	var storage_snapshot := storage.snapshot()
	var restored_storage := ChestStorage.new(item_catalog, player_inventory.equipment_instance_factory, container.get_slot_count())
	_expect(restored_storage.restore(storage_snapshot), "chest storage snapshot round trip failed")
	var oversized_storage := ChestStorage.new(item_catalog, EquipmentInstanceFactory.new(item_catalog), container.get_slot_count())
	var oversized_slots: Array = []
	oversized_slots.resize(container.get_slot_count() + 1)
	_expect(not oversized_storage.restore({chest_position: oversized_slots}), "oversized chest save was accepted")
	_expect(restored_storage.get_slot(chest_position, 0).item_id == &"log_block" and restored_storage.get_slot(chest_position, 0).count == 2, "restored chest changed a partial stack")
	_expect(restored_storage.get_slot(chest_position, 1).item_id == &"stone_block" and restored_storage.get_slot(chest_position, 1).count == 4, "restored chest changed a swapped stack")
	_expect(restored_storage.get_slot(chest_position, 4).equipment_instance.to_dict() == variant_fingerprint, "restored chest changed variant equipment")
	_expect(restored_storage.get_slot(second_chest_position, 0).item_id == &"leaves_block" and restored_storage.get_slot(second_chest_position, 0).count == 5, "restored second chest lost its position-linked contents")

	var full_player_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	full_player_inventory.setup_empty()
	for index in range(InventoryModel.HOTBAR_SIZE, InventoryModel.FILLABLE_SIZE):
		InventoryTestFixture.restore_slot(full_player_inventory, index, InventoryStack.new(&"sand_block", item_catalog.get_definition(&"sand_block").max_stack))
	var full_loadout := InventoryTestFixture.create_loadout(full_player_inventory)
	var full_storage := ChestStorage.new(item_catalog, full_player_inventory.equipment_instance_factory, container.get_slot_count())
	_expect(full_storage.create_chest(second_chest_position), "full-backpack chest storage creation failed")
	_expect(full_storage.add_stack(second_chest_position, InventoryStack.new(&"log_block", 3), 0), "full-backpack chest fixture failed")
	var full_coordinator := ChestCoordinator.new()
	_expect(full_coordinator.setup(full_storage, full_player_inventory, full_loadout, world, chest_block), "full-backpack coordinator setup failed")
	_expect(full_coordinator.try_open(second_chest_position, container), "full-backpack coordinator could not open a chest")
	_expect(not full_coordinator.quick_transfer(ChestCoordinator.CHEST_SCOPE, 0), "chest click moved an item into a full backpack")
	_expect(not full_coordinator.move_all_to_backpack(), "move-all changed a full backpack")
	_expect(full_storage.get_slot(second_chest_position, 0).count == 3, "full backpack transfer changed the chest stack")

	var input := InputBuffer.new()
	var interaction_factory := EquipmentInstanceFactory.new(item_catalog, player_inventory.equipment_instance_factory.get_next_instance_id())
	var interaction_inventory := InventoryModel.new(item_catalog, interaction_factory)
	interaction_inventory.setup_empty()
	var interaction_sword := interaction_factory.create(&"copper_sword")
	var interaction_pickaxe := interaction_factory.create(&"stone_pickaxe")
	_expect(InventoryTestFixture.restore_slot(interaction_inventory, 0, InventoryStack.new(&"copper_sword", 1, interaction_sword)), "interaction sword fixture failed")
	_expect(InventoryTestFixture.restore_slot(interaction_inventory, 1, InventoryStack.new(&"stone_pickaxe", 1, interaction_pickaxe)), "interaction pickaxe fixture failed")
	var interaction_loadout := InventoryTestFixture.create_loadout(interaction_inventory)
	var interaction_storage := ChestStorage.new(item_catalog, interaction_factory, container.get_slot_count())
	_expect(interaction_storage.restore(storage_snapshot), "interaction chest restore failed")
	var interaction_chest_coordinator := ChestCoordinator.new()
	_expect(interaction_chest_coordinator.setup(interaction_storage, interaction_inventory, interaction_loadout, world, chest_block), "interaction chest setup failed")
	var interactor := PlayerInteractor.new()
	interactor.inventory_model = interaction_inventory
	interactor.inventory_loadout = interaction_loadout
	interactor._input_buffer = input
	interactor.voxel_space = world
	interactor.editable_voxel_world = null
	_expect(interactor._get_target_container(chest_position) == null, "read-only voxel space exposed an overworld chest interaction")
	interactor.editable_voxel_world = world
	_expect(interactor._get_target_container(chest_position) == container, "editable overworld did not expose its chest interaction")
	_expect(not interactor._can_mine_position(chest_position, stone_pickaxe), "non-empty chest passed the player mining validator")
	interactor.target_has = true
	interactor.target_block = chest_position
	interactor.target_container = container
	interactor.can_interact_target = true
	interactor.container_open_requested.connect(_on_container_open_requested)
	input.primary_use_just = true
	interactor._handle_item_actions(0.0)
	_expect(_open_requests == 1, "left click did not request the chest UI")
	_expect(interactor.melee_attack_queue == 0 and not interactor.is_mining, "chest click also started an item action")
	_expect(interaction_loadout.select_slot(1), "interaction pickaxe selection failed")
	input.primary_use_just = true
	interactor._handle_item_actions(0.0)
	_expect(_open_requests == 1, "pickaxe click opened a non-empty chest instead of attempting to mine it")
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
	_expect(targeting._should_show_mining_outline(true), "pickaxe chest target does not show the mining wireframe")
	targeting.voxel_space = world
	targeting.block_catalog = block_catalog
	interactor.can_primary_target = false
	targeting._update_selection_visuals()
	_expect(targeting.selection_box.visible and targeting._selection_edge_mat.albedo_color.r > targeting._selection_edge_mat.albedo_color.g, "non-empty chest does not show the blocked mining outline")
	interactor.can_primary_target = true
	targeting._update_selection_visuals()
	_expect(targeting._selection_edge_mat.albedo_color.g > targeting._selection_edge_mat.albedo_color.r * 0.8, "empty chest does not show the mineable outline")
	interactor.can_interact_target = true
	targeting._update_interaction_visuals(1.0)
	chest_renderer._process(1.0)
	_expect(not targeting._should_show_interaction(), "pickaxe chest target also shows its interaction hover")
	_expect(not targeting._interaction_cursor_active, "pickaxe chest target enabled the interaction cursor")
	_expect(interaction_loadout.select_slot(0), "interaction sword selection failed")
	_expect(targeting._should_show_interaction(), "in-range chest does not expose its hover presentation without a pickaxe")
	targeting._update_interaction_visuals(1.0)
	chest_renderer._process(1.0)
	_expect(targeting._interaction_cursor_active, "interactable chest did not enable the pointing-hand cursor")
	targeting._hide_interaction_visuals()
	_expect(not targeting._interaction_cursor_active, "chest interaction cursor did not reset")
	targeting._update_interaction_visuals(1.0)
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

	var recipe_catalog := load("res://crafting/crafting_recipe_catalog.tres") as CraftingRecipeCatalog
	var crafting := CraftingCoordinator.new()
	crafting.setup(player_inventory, player_loadout, recipe_catalog)
	var hud := (load("res://ui/hud/hud.tscn") as PackedScene).instantiate() as HUD
	get_root().add_child(hud)
	await process_frame
	var ui_coordinator := ChestCoordinator.new()
	_expect(ui_coordinator.setup(restored_storage, player_inventory, player_loadout, world, chest_block), "UI chest coordinator setup failed")
	hud.setup_with_camera(player_inventory, player_loadout, crafting, recipe_catalog, null, player_stats, ItemProficiency.new(item_catalog), ui_coordinator)
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
	var variant_chest_slot := hud.chest_panel.get_chest_slots()[4]
	var presented_variant: EquipmentInstance = variant_chest_slot._get_presented_equipment_instance()
	_expect(presented_variant != null and presented_variant.to_dict() == variant_fingerprint, "chest slot presentation lost variant equipment data")
	var saved_backpack_slots: Array[InventoryStack] = []
	for index in range(InventoryModel.HOTBAR_SIZE, InventoryModel.FILLABLE_SIZE):
		saved_backpack_slots.append(player_inventory.get_slot(index))
	for index in range(InventoryModel.HOTBAR_SIZE, InventoryModel.FILLABLE_SIZE):
		_expect(_replace_inventory_slot(player_loadout, player_inventory, index, InventoryStack.new(&"sand_block", item_catalog.get_definition(&"sand_block").max_stack)), "full-backpack UI fixture failed at %d" % index)
	_expect(hud.chest_panel._move_all_button.disabled, "move-all stayed enabled for a full backpack")
	for offset in range(saved_backpack_slots.size()):
		_expect(_replace_inventory_slot(player_loadout, player_inventory, InventoryModel.HOTBAR_SIZE + offset, saved_backpack_slots[offset]), "backpack UI fixture restore failed at %d" % offset)
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
	var grass_count_before := player_inventory.get_backpack_item_count(&"grass_block")
	_expect(_replace_inventory_slot(player_loadout, player_inventory, quick_backpack_slot.slot_index, InventoryStack.new(&"grass_block", 2)), "quick-transfer UI fixture failed")
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
	_expect(restored_storage.get_slot(chest_position, quick_chest_slot.slot_index).item_id == &"grass_block", "clicking a backpack item did not add it to the chest")
	_click_slot(quick_chest_slot)
	_expect(restored_storage.get_slot(chest_position, quick_chest_slot.slot_index) == null, "clicking a chest item did not clear its slot")
	_expect(player_inventory.get_backpack_item_count(&"grass_block") == grass_count_before + 2, "clicking a chest item did not add it to the backpack")
	var ui_drag := {
		"source_scope": ChestCoordinator.CHEST_SCOPE,
		"source_index": chest_slot.slot_index,
		"drag_count": 1,
	}
	var drag_backpack_slot := hud.side_panel.get_inventory_slots()[15]
	_expect(drag_backpack_slot._can_drop_data(Vector2.ZERO, ui_drag), "backpack UI rejected a chest drag")
	_expect(not hud.side_panel._trash_target._can_drop_data(Vector2.ZERO, ui_drag), "trash target accepted a chest drag as a player item")
	drag_backpack_slot._drop_data(Vector2.ZERO, ui_drag)
	_expect(restored_storage.get_slot(chest_position, 0).count == 1, "UI drag did not remove one chest item")
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
	_expect(restored_storage.get_slot(chest_position, 2) == null, "chest-to-hotbar UI drag retained the chest stack")
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
	_expect(restored_storage.get_slot(chest_position, 3).item_id == &"torch" and restored_storage.get_slot(chest_position, 3).count == 2, "hotbar-to-chest UI drag produced the wrong chest stack")
	var chest_counts: Dictionary[StringName, int] = {}
	for stack in restored_storage.get_slots(chest_position):
		if stack != null:
			chest_counts[stack.item_id] = chest_counts.get(stack.item_id, 0) + stack.count
	for item_id in chest_counts:
		chest_counts[item_id] = player_inventory.get_inventory_item_count(item_id) + chest_counts[item_id]
	hud.chest_panel._move_all_button.pressed.emit()
	_expect(restored_storage.is_chest_empty(chest_position), "move-all retained items in the chest")
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

func _replace_inventory_slot(
	loadout: InventoryLoadoutCoordinator,
	inventory: InventoryModel,
	index: int,
	replacement: InventoryStack,
) -> bool:
	var current := inventory.get_slot(index)
	if current == null and replacement == null:
		return true
	if current != null and replacement != null and current.to_dict() == replacement.to_dict():
		return true
	var inventory_change := inventory.prepare_replace_stack_at(index, current, replacement)
	var loadout_change := loadout.prepare_inventory_change(inventory_change)
	return loadout_change != null and loadout.commit_prepared_change(loadout_change)

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
