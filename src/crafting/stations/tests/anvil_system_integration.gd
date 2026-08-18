extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	_expect(block_catalog != null and block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog != null and item_catalog.validate(block_catalog), "item catalog invalid")
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
	_expect(not anvil_block.is_breakable, "anvil is configured as an ordinary mineable block")
	_expect(placement != null and placement.block == anvil_block, "anvil item does not place the canonical block")
	_expect(item_catalog.get_item_for_block(BlockId.Type.ANVIL) == anvil_item, "anvil reverse block mapping is invalid")
	_expect(anvil_item.icon.resource_path == "res://assets/textures/items/anvil.png", "anvil uses the wrong inventory icon")
	var icon_image := anvil_item.icon.get_image()
	_expect(icon_image != null and icon_image.get_size() == Vector2i(64, 64), "anvil inventory icon is not 64x64")
	_expect(icon_image != null and icon_image.detect_alpha() != Image.ALPHA_NONE, "anvil inventory icon has no transparency")

	var renderer := AnvilRenderer.new()
	root.add_child(renderer)
	renderer.setup()
	var position := Vector3i(3, 4, 5)
	var rendered := renderer.spawn_anvil(position)
	_expect(rendered != null and rendered.position == Vector3(position), "anvil renderer placed the model incorrectly")
	_expect(rendered.get_child_count() == 8, "anvil model does not contain the expected low-poly parts")
	var top := rendered.get_node_or_null("Top") as MeshInstance3D
	var horn := rendered.get_node_or_null("Horn") as MeshInstance3D
	_expect(top != null and top.mesh is BoxMesh, "anvil top is missing")
	_expect(horn != null and horn.mesh is CylinderMesh and (horn.mesh as CylinderMesh).radial_segments == 6, "anvil horn is not low-poly")
	renderer.set_hovered_anvil(position)
	_expect(top != null and top.material_overlay != null and horn.material_overlay != null, "hover highlight did not cover the full anvil")
	renderer.set_hovered_anvil(null)
	_expect(top != null and top.material_overlay == null, "anvil hover highlight did not clear")
	renderer.set_placement_preview(Vector3i(6, 7, 8), true)
	_expect(renderer._placement_preview != null and renderer._placement_preview.visible, "anvil placement preview was not shown")
	_expect(renderer._placement_preview.global_position == Vector3(6, 7, 8), "anvil placement preview used the wrong position")
	renderer.set_placement_preview(null, false)
	_expect(not renderer._placement_preview.visible, "anvil placement preview did not hide")

	var world := VoxelWorld.new(20, 36, 5, 12.0, block_catalog)
	var inventory := InventoryModel.new(item_catalog)
	var coordinator := AnvilCoordinator.new()
	coordinator.setup(world, inventory)
	var pickup_position := Vector3i(2, 20, 2)
	var placed := world.try_place_block(pickup_position, BlockId.Type.ANVIL)
	_expect(placed.is_success(), "test anvil could not be placed")
	var pickaxe_action := item_catalog.get_definition(&"stone_pickaxe").primary_action as MiningActionDefinition
	_expect(coordinator.can_pick_up_anvil(pickup_position, pickaxe_action), "pickaxe could not pick up an anvil")
	_expect(coordinator.pick_up_anvil(pickup_position, pickaxe_action), "anvil pickup failed")
	_expect(world.get_block_id_at(pickup_position) == BlockId.Type.AIR, "picked-up anvil remained in the world")
	_expect(inventory.get_inventory_item_count(&"anvil") == 1, "picked-up anvil was not returned to inventory")

	var full_inventory := InventoryModel.new(item_catalog)
	for index in range(InventoryModel.FILLABLE_SIZE):
		full_inventory.slots[index] = InventoryStack.new(&"dirt_block", 99)
	var blocked_coordinator := AnvilCoordinator.new()
	blocked_coordinator.setup(world, full_inventory)
	_expect(world.try_place_block(pickup_position, BlockId.Type.ANVIL).is_success(), "capacity-test anvil could not be placed")
	_expect(not blocked_coordinator.can_pick_up_anvil(pickup_position, pickaxe_action), "full inventory allowed anvil pickup")
	_expect(not blocked_coordinator.pick_up_anvil(pickup_position, pickaxe_action), "full inventory removed the anvil")
	_expect(world.get_block_id_at(pickup_position) == BlockId.Type.ANVIL, "failed pickup changed the world")

	renderer.queue_free()
	await process_frame
	_finish()

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
