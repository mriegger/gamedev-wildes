extends SceneTree

var _failures: Array[String] = []

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

	var storage := ChestInventoryStore.new(item_catalog)
	var first_inventory := storage.get_or_create(chest_position, container.get_slot_count())
	var second_inventory := storage.get_or_create(second_chest_position, container.get_slot_count())
	_expect(first_inventory != null and first_inventory.size == 15, "first chest does not have 15 slots")
	_expect(second_inventory != null and second_inventory != first_inventory, "two world chests share one inventory model")
	_expect(storage.get_or_create(chest_position, container.get_slot_count()) == first_inventory, "reopened chest did not recover its position-linked inventory")
	first_inventory.slots[0] = InventoryStack.new(&"log_block", 2)
	second_inventory.slots[0] = InventoryStack.new(&"leaves_block", 5)

	var encoded: Variant = JSON.parse_string(JSON.stringify(storage.snapshot()))
	var restored_storage := ChestInventoryStore.new(item_catalog)
	_expect(encoded is Dictionary and restored_storage.restore(encoded), "chest storage JSON round trip failed")
	var oversized_storage := ChestInventoryStore.new(item_catalog)
	_expect(not oversized_storage.restore({"0,0,0": {"size": ContainerBlockDefinition.MAX_SLOT_COUNT + 1, "slots": []}}), "oversized chest save was accepted")
	var restored_inventory := restored_storage.get_inventory(chest_position)
	var restored_second_inventory := restored_storage.get_inventory(second_chest_position)
	_expect(restored_inventory != null and restored_inventory.size == 15, "restored chest has the wrong size")
	_expect(restored_inventory.get_slot(0).item_id == &"log_block" and restored_inventory.get_slot(0).count == 2, "restored chest changed its stack")
	_expect(restored_second_inventory != null and restored_second_inventory != restored_inventory, "restored world chests share one inventory model")
	_expect(restored_second_inventory.get_slot(0).item_id == &"leaves_block" and restored_second_inventory.get_slot(0).count == 5, "restored second chest lost its position-linked contents")

	var interaction_inventory := InventoryModel.new(item_catalog)
	var interactor := PlayerInteractor.new()
	interactor.inventory_model = interaction_inventory
	interactor.voxel_space = world
	interactor.editable_voxel_world = null
	_expect(interactor._get_target_container(chest_position) == null, "read-only voxel space exposed an overworld chest interaction")
	interactor.editable_voxel_world = world
	_expect(interactor._get_target_container(chest_position) == container, "editable overworld did not expose its chest interaction")
	interactor.target_has = true
	interactor.target_block = chest_position
	interactor.target_container = container
	interactor.can_interact_target = true

	var chest_renderer := ChestRenderer.new()
	chest_renderer.setup(block_catalog)
	get_root().add_child(chest_renderer)
	chest_renderer.spawn_chest(chest_position)
	_expect(chest_renderer.unload_chests_in_chunk(0, 0, 16) == 1 and not chest_renderer.chest_instances.has(chest_position), "chunk unload retained its rendered chest")
	_expect(chest_renderer.load_chests_for_chunk(0, 0, 16, world) == 2, "chunk reload did not restore both rendered chests")
	var targeting := TargetingView.new()
	targeting.interactor = interactor
	targeting.chest_renderer = chest_renderer
	get_root().add_child(targeting)
	targeting.set_physics_process(false)
	await process_frame
	_expect(not targeting._should_show_mining_outline(true), "container target shows the mining wireframe")
	_expect(targeting._should_show_interaction(), "reachable chest does not expose its hover presentation")
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
	_expect(highlighted_body.material_overlay == null and highlighted_lid.material_overlay == null, "out-of-range chest retained its highlight")
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
