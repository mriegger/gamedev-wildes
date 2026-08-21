extends SceneTree

var _failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_placement_prompt()
	if _failures == 0:
		print("PLACEMENT_PROMPT PASS")
		quit(0)
	else:
		print("PLACEMENT_PROMPT FAIL failures=%d" % _failures)
		quit(1)

func _test_placement_prompt() -> void:
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	_expect(inventory.setup_empty(), "placement prompt inventory setup failed")
	_expect(InventoryTestFixture.restore_slots(inventory, {
		0: InventoryStack.new(&"stone_block", 1),
		1: InventoryStack.new(&"apple", 1),
		2: InventoryStack.new(&"chest", 1),
		3: InventoryStack.new(&"anvil", 1),
	}), "placement prompt inventory contents failed")
	var loadout := InventoryTestFixture.create_loadout(inventory)
	_expect(loadout != null, "placement prompt loadout setup failed")
	var holder := Node.new()
	root.add_child(holder)
	var hud := (load("res://ui/hud/hud.tscn") as PackedScene).instantiate() as HUD
	holder.add_child(hud)
	await process_frame
	var prompt := InteractionPromptCoordinator.new()
	prompt.setup(hud, func() -> bool: return false)
	var interactor := PlayerInteractor.new()
	holder.add_child(interactor)
	interactor.inventory_model = inventory
	interactor.editable_voxel_world = VoxelWorld.new(16, 32, 5, 8.0, load("res://blocks/block_catalog.tres") as BlockCatalog)
	var placement := PlacementPromptCoordinator.new()
	holder.add_child(placement)
	placement.setup(interactor, prompt)
	placement.set_process(false)
	placement._process(0.0)
	_expect(hud.interaction_prompt.visible and hud.interaction_prompt.text == PlacementPromptCoordinator.PROMPT, "placeable block did not show the placement prompt")
	prompt.set_level_prompt("F  Enter Dungeon")
	_expect(hud.interaction_prompt.text == "F  Enter Dungeon", "placement prompt overrode the active dungeon prompt")
	prompt.set_harvest_prompt("Left Click  Harvest Pumpkin")
	_expect(hud.interaction_prompt.text == "Left Click  Harvest Pumpkin", "placement prompt overrode the active harvest prompt")
	prompt.set_harvest_prompt("")
	_expect(hud.interaction_prompt.text == "F  Enter Dungeon", "dungeon prompt did not return after harvest targeting ended")
	prompt.set_level_prompt("")
	_expect(hud.interaction_prompt.text == PlacementPromptCoordinator.PROMPT, "placement prompt did not return after contextual prompts ended")
	_expect(loadout.select_slot(1), "placement prompt could not select the non-placeable item")
	placement._process(0.0)
	_expect(not hud.interaction_prompt.visible, "non-placeable item retained the placement prompt")
	for slot_index in [2, 3]:
		_expect(loadout.select_slot(slot_index), "placement prompt could not select placeable station slot %d" % slot_index)
		placement._process(0.0)
		_expect(hud.interaction_prompt.text == PlacementPromptCoordinator.PROMPT, "placeable station did not show the placement prompt")
	interactor.editable_voxel_world = null
	placement._process(0.0)
	_expect(not hud.interaction_prompt.visible, "placement prompt remained outside an editable world")
	holder.free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[placement_prompt_integration] FAIL: %s" % message)
