extends SceneTree

var _errors: Array[String] = []
var _player: PlayerMotor
var _camera: Camera3D
var _inventory: InventoryModel
var _interactor: PlayerInteractor
var _input_buffer: InputBuffer
var _voxel_world: VoxelWorld
var _stone_pos := Vector3i(1, 0, 0)
var _grass_pos := Vector3i(2, 0, 0)

func _init():
	call_deferred("_run")

func _run():
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	_expect(block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog.validate(block_catalog), "item catalog invalid")
	var pickaxe := item_catalog.get_definition(&"copper_pickaxe")
	_expect(pickaxe.max_stack == 1, "pickaxe stack limit changed")
	_expect(pickaxe.primary_action is MiningActionDefinition, "pickaxe primary action is not mining")
	_expect(pickaxe.secondary_action == null, "pickaxe unexpectedly has a secondary action")
	var pickaxe_action := pickaxe.primary_action as MiningActionDefinition
	var pickaxe_stat := pickaxe_action.get_tool_stat(&"pickaxe")
	_expect(pickaxe_stat != null and pickaxe_stat.power == 1 and is_equal_approx(pickaxe_stat.speed_multiplier, 2.0), "pickaxe mining stats changed")
	var stone := block_catalog.get_definition(BlockId.Type.STONE)
	_expect(stone.mining_tool_tag == &"pickaxe" and stone.minimum_mining_power == 1, "stone mining requirement changed")
	_expect(is_equal_approx(pickaxe_action.get_mine_duration(stone), 0.35), "pickaxe stone duration changed")

	_inventory = InventoryModel.new(item_catalog)
	_inventory.setup_starter()
	_expect(_inventory.get_slot(0) is InventoryStack and _inventory.get_slot(0).item_id == &"copper_pickaxe", "starter pickaxe missing")
	var encoded := _inventory.to_dict()
	var restored := InventoryModel.new(item_catalog)
	_expect(restored.from_dict(encoded), "typed inventory did not restore")
	_expect(restored.get_slot(0) is InventoryStack and restored.get_slot(0).item_id == &"copper_pickaxe", "restored pickaxe missing")
	var legacy_encoded := encoded.duplicate(true)
	legacy_encoded["regions"]["hotbar"][0] = null
	var legacy := InventoryModel.new(item_catalog)
	_expect(legacy.from_dict(legacy_encoded), "legacy inventory did not restore")
	_expect(legacy.ensure_item(&"copper_pickaxe"), "legacy inventory could not receive pickaxe")
	_expect(legacy.get_slot(0) != null and legacy.get_slot(0).item_id == &"copper_pickaxe", "legacy pickaxe was not placed in hotbar")
	var crowded := InventoryModel.new(item_catalog)
	var grass_id := item_catalog.get_item_for_block(BlockId.Type.GRASS).id
	for index in range(InventoryModel.HOTBAR_SIZE):
		crowded.slots[index] = InventoryStack.new(grass_id, index + 1)
	_expect(crowded.ensure_item(&"copper_pickaxe"), "full legacy hotbar could not receive pickaxe")
	_expect(crowded.get_slot(0).item_id == &"copper_pickaxe" and crowded.get_slot(InventoryModel.HOTBAR_SIZE).count == 1, "legacy hotbar migration lost its displaced stack")

	_voxel_world = VoxelWorld.new(20, 36, 5, 12.0, block_catalog)
	_voxel_world.placed_blocks[_stone_pos] = BlockId.Type.STONE
	_voxel_world.placed_blocks[_grass_pos] = BlockId.Type.GRASS
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
	_interactor.setup(_voxel_world, _camera, _player, _inventory, _input_buffer)
	_interactor.set_physics_process(false)
	_player.held_item_view.setup(_inventory)
	await process_frame
	_expect(_player.held_item_view.held_node is PixelExtrudedItem, "pickaxe held scene missing")
	_expect(is_equal_approx(_player.held_item_view.rotation.x, PI * 0.25), "held-item socket does not pitch items downward")
	var held_pickaxe := _player.held_item_view.held_node as PixelExtrudedItem
	_expect(is_equal_approx(held_pickaxe.rotation.y, PI * 0.5), "pickaxe does not point toward the player's front")
	_expect(held_pickaxe.mesh_instance.mesh.get_surface_count() == 1, "pickaxe mesh surface count changed")
	var one_pixel_pickaxe := PixelItemMeshBuilder.build(held_pickaxe.texture, held_pickaxe.grip_pixel, held_pickaxe.max_dimension, 1.0)
	_expect(is_equal_approx(held_pickaxe.mesh_instance.mesh.get_aabb().size.z, one_pixel_pickaxe.get_aabb().size.z * 2.0), "pickaxe mesh is not two pixels thick")
	_verify_texture_mesh("res://assets/textures/tools/sword/copper_sword.png")

	_push_hotbar_key(KEY_2)
	await process_frame
	_expect(_inventory.selected_slot == 1, "grass hotbar selection failed")
	_expect(_player.held_item_view.held_node == null, "held pickaxe did not clear")
	var unarmed := _interactor.get_selected_primary_action() as MiningActionDefinition
	_expect(unarmed != null and not unarmed.can_mine(stone), "unarmed mining bypasses stone requirement")
	_prepare_target(_stone_pos, unarmed)
	_push_primary(true)
	await process_frame
	_input_buffer.poll()
	_interactor._handle_item_actions(0.8)
	_expect(not _interactor.is_mining, "blocked stone mining started")
	_expect(_voxel_world.get_block_id_at(_stone_pos) == BlockId.Type.STONE, "blocked stone was removed")
	_push_primary(false)
	await process_frame
	_input_buffer.poll()

	_push_hotbar_key(KEY_1)
	await process_frame
	_expect(_inventory.selected_slot == 0, "pickaxe hotbar selection failed")
	_expect(_player.held_item_view.held_node is PixelExtrudedItem, "pickaxe did not reappear")
	_prepare_target(_stone_pos, pickaxe_action)
	_expect(_interactor.can_mine_target, "pickaxe cannot target stone")
	_push_primary(true)
	await process_frame
	_input_buffer.poll()
	_expect(_input_buffer.primary_use_pressed, "primary input did not reach buffer")
	_interactor._handle_item_actions(0.0)
	_interactor._handle_item_actions(0.36)
	_expect(_voxel_world.get_block_id_at(_stone_pos) == BlockId.Type.AIR, "pickaxe did not mine stone")
	_push_primary(false)
	await process_frame
	_input_buffer.poll()

	_push_hotbar_key(KEY_2)
	await process_frame
	unarmed = _interactor.get_selected_primary_action() as MiningActionDefinition
	_prepare_target(_grass_pos, unarmed)
	_expect(_interactor.can_mine_target, "unarmed action cannot target grass")
	_push_primary(true)
	await process_frame
	_input_buffer.poll()
	_interactor._handle_item_actions(0.0)
	_interactor._handle_item_actions(0.36)
	_expect(_voxel_world.get_block_id_at(_grass_pos) == BlockId.Type.AIR, "unarmed mining no longer mines grass")
	_push_primary(false)
	await process_frame
	_input_buffer.poll()

	_player.queue_free()
	_camera.queue_free()
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

func _verify_texture_mesh(path: String):
	var texture := load(path) as Texture2D
	var mesh := PixelItemMeshBuilder.build(texture, Vector2i(14, 14), 0.75, 1.0)
	_expect(mesh.get_surface_count() == 1, "%s mesh surface count changed" % path)
	_expect(mesh.get_aabb().size.z > 0.0, "%s mesh has no depth" % path)

func _prepare_target(pos: Vector3i, action: MiningActionDefinition):
	_interactor.target_block = pos
	_interactor.target_has = true
	_interactor.can_mine_target = _interactor._can_mine_position(pos, action)

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

func _expect(condition: bool, message: String):
	if not condition:
		_errors.append(message)
		print("[tool_system] FAIL: %s" % message)
