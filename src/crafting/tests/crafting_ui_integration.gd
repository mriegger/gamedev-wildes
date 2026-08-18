extends SceneTree

class UnhandledInputProbe:
	extends Node

	var mouse_wheel_count: int = 0
	var pan_gesture_count: int = 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			mouse_wheel_count += 1
		elif event is InputEventPanGesture:
			pan_gesture_count += 1

var _frame: int = 0
var _phase: int = 0
var _errors: Array[String] = []
var _hud: HUD
var _inventory: InventoryModel
var _crafting: CraftingCoordinator
var _inventory_stats: InventoryStatCoordinator
var _stats: ActorStats
var _item_proficiency: ItemProficiency
var _recipe_catalog: CraftingRecipeCatalog
var _camera_rig: CameraRig
var _camera_follow: Node3D
var _camera_input_buffer: InputBuffer
var _unhandled_input_probe: UnhandledInputProbe

func _init() -> void:
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	_recipe_catalog = load("res://crafting/crafting_recipe_catalog.tres") as CraftingRecipeCatalog
	_inventory = InventoryModel.new(item_catalog)
	_inventory.slots[0] = InventoryStack.new(&"copper", 20)
	_inventory.slots[1] = InventoryStack.new(&"log_block", 4)
	_inventory.slots[2] = InventoryStack.new(&"stone_block", 10)
	_inventory.slots[InventoryModel.HOTBAR_SIZE] = InventoryStack.new(&"copper", 5)
	_inventory.slots[InventoryModel.HOTBAR_SIZE + 1] = InventoryStack.new(&"log_block", 6)
	_stats = ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	_item_proficiency = ItemProficiency.new(item_catalog)
	_inventory_stats = InventoryStatCoordinator.new()
	_expect(_inventory_stats.setup(_inventory, _stats), "inventory stat setup failed")
	_crafting = CraftingCoordinator.new()
	_crafting.setup(_inventory, _recipe_catalog)
	var packed := load("res://ui/hud/hud.tscn") as PackedScene
	_hud = packed.instantiate() as HUD
	root.add_child(_hud)
	_camera_rig = (load("res://player/camera/camera_rig.tscn") as PackedScene).instantiate() as CameraRig
	root.add_child(_camera_rig)
	_camera_follow = Node3D.new()
	root.add_child(_camera_follow)
	_camera_input_buffer = InputBuffer.new()
	_unhandled_input_probe = UnhandledInputProbe.new()
	root.add_child(_unhandled_input_probe)

func _process(_delta: float) -> bool:
	_frame += 1
	if _phase == 0 and _frame == 2:
		_camera_rig.setup(_camera_follow, _camera_input_buffer)
		_hud.setup_with_camera(_inventory, _inventory_stats, _crafting, _recipe_catalog, _camera_rig, _stats, _item_proficiency)
		_hud.toggle_backpack()
		_phase = 1
	elif _phase == 1 and _frame == 35:
		_expect(_hud.side_panel.is_open(), "P behavior did not open the backpack")
		_expect(not _hud.crafting_panel.is_open(), "P behavior unexpectedly opened crafting")
		_expect(_hud.side_panel.get_progress() > 0.95, "backpack-only opening animation did not complete")
		_expect(_hud.crafting_panel.get_progress() < 0.01, "crafting panel appeared in backpack-only view")
		_expect(_camera_rig.camera.h_offset > 0.0, "camera did not account for the backpack-only right panel")
		_expect(_action_uses_key("toggle_backpack", KEY_P), "toggle_backpack was not mapped to P")
		_expect(_action_uses_key("toggle_crafting", KEY_TAB), "toggle_crafting was not mapped to Tab")
		_hud.toggle_crafting()
	elif _phase == 1 and _frame == 68:
		_check_open_state()
		var sound_player := _hud.crafting_panel.get_node("CraftingSoundPlayer") as AudioStreamPlayer
		_expect(sound_player.stream.resource_path == "res://assets/audio/sfx/tools/impactGeneric_light_004.ogg", "crafting used the wrong success sound")
		_expect(sound_player.bus == &"SFX", "crafting success sound did not use the SFX bus")
		_expect(not sound_player.playing, "crafting sound played before a successful press")
		_expect(_hud.crafting_panel.get_node_or_null("CraftingImpactPlayer") == null, "repeating crafting sound player still exists")
		_expect(_hud.crafting_panel.get_node_or_null("CraftingCompletePlayer") == null, "old completion sound player still exists")
		_expect(_hud.crafting_panel.get_node_or_null("CraftingImpactTimer") == null, "crafting timer still exists")
		var button := _hud.crafting_panel.get_craft_button()
		_expect(button.get_node_or_null("Fill") == null, "crafting progress fill still exists")
		_hud.crafting_panel.select_recipe(&"stone_pickaxe")
		_expect(button.is_craft_enabled(), "available stone pickaxe recipe was disabled")
		button.pressed.emit()
		_expect(_inventory.get_inventory_item_count(&"stone_pickaxe") == 1, "button press did not craft stone pickaxe immediately")
		_expect(_inventory.get_inventory_item_count(&"stone_block") == 0, "immediate craft retained stone")
		_expect(_inventory.get_inventory_item_count(&"log_block") == 5, "immediate craft consumed wrong wood count")
		_expect(sound_player.playing, "successful craft did not play its sound")
		_expect(not button.is_craft_enabled(), "depleted recipe button remained enabled")
		_hud.crafting_panel.select_recipe(&"anvil")
		_expect(_hud.crafting_panel.get_craft_button().is_craft_enabled(), "available anvil recipe was disabled")
		_hud.crafting_panel.get_craft_button().pressed.emit()
		_expect(_inventory.get_inventory_item_count(&"anvil") == 1, "anvil did not craft immediately")
		_expect(_inventory.get_inventory_item_count(&"copper") == 15, "anvil consumed wrong copper count")
		_expect(not _recipe_catalog.has_definition(&"copper_pickaxe"), "copper pickaxe remained in general crafting")
		_hud.crafting_panel.select_recipe(&"basic_rune")
		_expect(not _hud.crafting_panel.get_craft_button().is_craft_enabled(), "unavailable recipe button remained enabled")
		sound_player.stop()
		_hud.crafting_panel.get_craft_button().pressed.emit()
		_expect(not sound_player.playing, "failed craft played the success sound")
		_hud.close_side_panel()
		_phase = 2
	elif _phase == 2 and _frame == 70:
		_expect(not _hud.side_panel.is_open() and not _hud.crafting_panel.is_open(), "HUD panels did not close together")
		_expect(_inventory.get_inventory_item_count(&"basic_rune") == 0, "failed rune craft added output")
		_expect(_inventory.get_inventory_item_count(&"copper") == 15, "closing backpack consumed copper")
		_expect(_inventory.get_inventory_item_count(&"log_block") == 5, "closing backpack changed wood")
		_hud.free()
		_camera_rig.free()
		_camera_follow.free()
		_unhandled_input_probe.free()
		_phase = 3
	elif _phase == 3 and _frame == 80:
		_finish()
	return false

func _check_open_state() -> void:
	_expect(_hud.side_panel.is_open(), "backpack did not open")
	_expect(_hud.crafting_panel.is_open(), "crafting panel did not open with backpack")
	_expect(_hud.crafting_panel.get_progress() > 0.95, "crafting panel opening animation did not complete")
	_expect(_hud.crafting_panel.get_selected_recipe_id() == &"torch_bundle", "torches were not selected first")
	_expect(not _hud.crafting_panel.get_craft_button().is_craft_enabled(), "unavailable torch recipe button was enabled")
	_expect(_camera_rig.camera.h_offset < 0.0, "camera framing did not account for the wider left panel")
	var recipe_scroll := _hud.crafting_panel.get_node("Margin/Content/Body/Recipes/RecipeScroll") as ScrollContainer
	var recipe_list := _hud.crafting_panel.get_node("Margin/Content/Body/Recipes/RecipeScroll/RecipeList") as VBoxContainer
	_expect(recipe_scroll != null and recipe_list.get_child_count() == 5, "scrollable recipe list did not contain five general recipes")
	_expect(recipe_list.get_child(0).name == "TorchBundle" and recipe_list.get_child(1).name == "Chest" and recipe_list.get_child(2).name == "Anvil", "torches, chest, and anvil are not the first recipes")
	var recipe_button := recipe_list.get_child(0) as Button
	var recipe_icon_frame := recipe_button.get_node("Content/IconFrame") as CenterContainer
	var recipe_icon := recipe_icon_frame.get_node("Icon") as TextureRect
	_expect(recipe_icon_frame.custom_minimum_size == Vector2(54, 54) and recipe_icon.custom_minimum_size == Vector2(32, 32), "recipe icon padding is incorrect")
	_expect(recipe_icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "recipe icon does not use nearest filtering")
	var scroll_bar := recipe_scroll.get_v_scroll_bar()
	scroll_bar.max_value = 200.0
	scroll_bar.page = 100.0
	var camera_size_before_scroll := _camera_rig.camera.size
	var mouse_wheel_count_before := _unhandled_input_probe.mouse_wheel_count
	var wheel_down := InputEventMouseButton.new()
	wheel_down.position = recipe_scroll.get_global_rect().get_center()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	recipe_scroll.scroll_vertical = 0
	root.push_input(wheel_down, true)
	_expect(recipe_scroll.scroll_vertical == 61, "mouse wheel did not scroll the recipe list")
	var wheel_up := InputEventMouseButton.new()
	wheel_up.position = recipe_scroll.get_global_rect().get_center()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	root.push_input(wheel_up, true)
	_expect(recipe_scroll.scroll_vertical == 0, "mouse wheel did not scroll back through the recipe list")
	recipe_scroll.scroll_vertical = 100
	root.push_input(wheel_down, true)
	_camera_rig._process(0.0)
	_expect(is_equal_approx(_camera_rig.camera.size, camera_size_before_scroll), "scrolling past the final recipe zoomed the camera")
	recipe_scroll.scroll_vertical = 0
	root.push_input(wheel_up, true)
	_camera_rig._process(0.0)
	_expect(is_equal_approx(_camera_rig.camera.size, camera_size_before_scroll), "scrolling before the first recipe zoomed the camera")
	_expect(_unhandled_input_probe.mouse_wheel_count == mouse_wheel_count_before, "recipe mouse-wheel scrolling reached unhandled gameplay input")
	var pan_gesture_count_before := _unhandled_input_probe.pan_gesture_count
	var pan_down := InputEventPanGesture.new()
	pan_down.position = recipe_scroll.get_global_rect().get_center()
	pan_down.delta = Vector2(0, 1)
	recipe_scroll.scroll_vertical = 0
	root.push_input(pan_down, true)
	_expect(recipe_scroll.scroll_vertical == 32, "trackpad gesture did not scroll the recipe list")
	var pan_up := InputEventPanGesture.new()
	pan_up.position = recipe_scroll.get_global_rect().get_center()
	pan_up.delta = Vector2(0, -1)
	root.push_input(pan_up, true)
	_expect(recipe_scroll.scroll_vertical == 0, "trackpad gesture did not scroll back through the recipe list")
	recipe_scroll.scroll_vertical = 100
	root.push_input(pan_down, true)
	recipe_scroll.scroll_vertical = 0
	root.push_input(pan_up, true)
	_expect(is_equal_approx(_camera_rig.camera.size, camera_size_before_scroll), "recipe trackpad scrolling zoomed the camera")
	_expect(_unhandled_input_probe.pan_gesture_count == pan_gesture_count_before, "recipe trackpad scrolling reached unhandled gameplay input")
	var output_icon_frame := _hud.crafting_panel.get_node("Margin/Content/Body/Details/Output/IconFrame") as CenterContainer
	var output_icon := output_icon_frame.get_node("Icon") as TextureRect
	_expect(output_icon_frame.custom_minimum_size == Vector2(64, 64) and output_icon.custom_minimum_size == Vector2(32, 32), "output icon does not match inventory padding")
	_expect(output_icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "output icon does not use nearest filtering")
	var ingredient_list := _hud.crafting_panel.get_node("Margin/Content/Body/Details/IngredientList") as VBoxContainer
	_expect(ingredient_list.get_child_count() == 2, "selected recipe ingredients were not displayed")
	var ingredient_row := ingredient_list.get_child(0) as HBoxContainer
	var ingredient_icon := ingredient_row.get_child(0) as TextureRect
	_expect(ingredient_row.custom_minimum_size.y == 38.0 and ingredient_icon.custom_minimum_size == Vector2(32, 32), "ingredient icon spacing changed")
	_expect(ingredient_icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "ingredient icon does not use nearest filtering")
	var wood_count := (ingredient_list.get_child(0) as HBoxContainer).get_child(1) as Label
	_expect(wood_count.text.contains("10 / 2"), "torch ingredient display did not include hotbar materials")
	var crafting_rect := _hud.crafting_panel.get_global_rect()
	var backpack_rect := _hud.side_panel.get_global_rect()
	for slot in _hud.hotbar.slot_nodes:
		var slot_rect := (slot as InventoryHotbarSlot).get_global_rect()
		_expect(not crafting_rect.intersects(slot_rect), "crafting panel covered hotbar slot %d" % (slot as InventoryHotbarSlot).slot_index)
		_expect(not backpack_rect.intersects(slot_rect), "backpack covered hotbar slot %d" % (slot as InventoryHotbarSlot).slot_index)

func _finish() -> void:
	if _errors.is_empty():
		print("CRAFTING_UI PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _action_uses_key(action: StringName, key: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			if key_event.keycode == key or key_event.physical_keycode == key:
				return true
	return false

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
