extends SceneTree

var _frame: int = 0
var _phase: int = 0
var _errors: Array[String] = []
var _hud: HUD
var _inventory: InventoryModel
var _crafting: CraftingCoordinator
var _inventory_stats: InventoryStatCoordinator
var _stats: ActorStats
var _recipe_catalog: CraftingRecipeCatalog
var _camera_rig: CameraRig

func _init() -> void:
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	_recipe_catalog = load("res://crafting/crafting_recipe_catalog.tres") as CraftingRecipeCatalog
	_inventory = InventoryModel.new(item_catalog)
	_inventory.slots[0] = InventoryStack.new(&"stone_block", 9)
	_inventory.slots[1] = InventoryStack.new(&"log_block", 4)
	_inventory.slots[InventoryModel.HOTBAR_SIZE] = InventoryStack.new(&"stone_block", 1)
	_inventory.slots[InventoryModel.HOTBAR_SIZE + 1] = InventoryStack.new(&"log_block", 1)
	_stats = ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	_inventory_stats = InventoryStatCoordinator.new()
	_expect(_inventory_stats.setup(_inventory, _stats), "inventory stat setup failed")
	_crafting = CraftingCoordinator.new()
	_crafting.setup(_inventory, _recipe_catalog)
	var packed := load("res://ui/hud/hud.tscn") as PackedScene
	_hud = packed.instantiate() as HUD
	root.add_child(_hud)
	_camera_rig = (load("res://player/camera/camera_rig.tscn") as PackedScene).instantiate() as CameraRig
	root.add_child(_camera_rig)

func _process(_delta: float) -> bool:
	_frame += 1
	if _phase == 0 and _frame == 2:
		_hud.setup_with_camera(_inventory, _inventory_stats, _crafting, _recipe_catalog, _camera_rig, _stats)
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
		_hud.crafting_panel.get_craft_button().pressed.emit()
		_phase = 2
	elif _phase == 2 and _frame == 70:
		_expect(_crafting.is_crafting(), "craft button did not start selected recipe")
		var impact_player := _hud.crafting_panel.get_node("CraftingImpactPlayer") as AudioStreamPlayer
		var complete_player := _hud.crafting_panel.get_node("CraftingCompletePlayer") as AudioStreamPlayer
		var impact_timer := _hud.crafting_panel.get_node("CraftingImpactTimer") as Timer
		_expect(impact_player.stream.resource_path == "res://assets/audio/sfx/tools/impactGeneric_light_003.ogg", "crafting used the wrong repeating impact sound")
		_expect(complete_player.stream.resource_path == "res://assets/audio/sfx/tools/impactGeneric_light_004.ogg", "crafting used the wrong completion sound")
		_expect(impact_player.bus == &"SFX", "crafting impact did not use the SFX bus")
		_expect(complete_player.bus == &"SFX", "crafting completion did not use the SFX bus")
		_expect(impact_player.playing, "crafting impact did not play when crafting started")
		_expect(not complete_player.playing, "crafting completion played before crafting completed")
		_expect(not impact_timer.is_stopped() and is_equal_approx(impact_timer.wait_time, 0.5), "crafting impact did not repeat twice per second")
		_crafting.advance_time(1.0)
		_phase = 3
	elif _phase == 3 and _frame == 72:
		var button := _hud.crafting_panel.get_craft_button()
		_expect(button.get_progress() > 0.49 and button.get_progress() < 0.55, "craft button did not show half progress")
		_expect(button.get_rendered_progress() > 0.49 and button.get_rendered_progress() < 0.55, "craft button fill did not render half progress")
		var fill := button.get_node("Fill") as ProgressBar
		_expect(fill != null and fill.visible, "craft button fill was not visible while crafting")
		_expect(fill.fill_mode == ProgressBar.FILL_BEGIN_TO_END, "craft button fill did not move left-to-right")
		var fill_style := fill.get_theme_stylebox("fill") as StyleBoxFlat
		var base_style := (button.get_node("Base") as Panel).get_theme_stylebox("panel") as StyleBoxFlat
		_expect(fill_style.bg_color.get_luminance() > base_style.bg_color.get_luminance(), "craft button fill was not lighter than its background")
		_hud.crafting_panel.select_recipe(&"copper_sword")
		_phase = 4
	elif _phase == 4 and _frame == 74:
		_expect(not _crafting.is_crafting(), "recipe selection did not cancel crafting")
		_expect(is_zero_approx(_hud.crafting_panel.get_craft_button().get_progress()), "recipe selection did not reset button")
		_expect(is_zero_approx(_hud.crafting_panel.get_craft_button().get_rendered_progress()), "recipe selection did not reset rendered fill")
		_expect(not (_hud.crafting_panel.get_craft_button().get_node("Fill") as ProgressBar).visible, "recipe selection did not hide rendered fill")
		_expect((_hud.crafting_panel.get_node("CraftingImpactTimer") as Timer).is_stopped(), "recipe selection did not stop crafting audio timer")
		_expect(not (_hud.crafting_panel.get_node("CraftingImpactPlayer") as AudioStreamPlayer).playing, "recipe selection did not stop crafting audio")
		_expect(not (_hud.crafting_panel.get_node("CraftingCompletePlayer") as AudioStreamPlayer).playing, "recipe cancellation played completion audio")
		_expect(_inventory.get_inventory_item_count(&"stone_block") == 10, "recipe selection consumed stone")
		_expect(_inventory.get_inventory_item_count(&"log_block") == 5, "recipe selection consumed wood")
		_hud.crafting_panel.select_recipe(&"copper_pickaxe")
		_hud.crafting_panel.get_craft_button().pressed.emit()
		_crafting.advance_time(2.0)
		_phase = 5
	elif _phase == 5 and _frame == 76:
		_expect(_inventory.get_inventory_item_count(&"copper_pickaxe") == 1, "completed UI craft did not add output")
		_expect(_inventory.get_inventory_item_count(&"stone_block") == 7, "completed UI craft consumed wrong stone count")
		_expect(_inventory.get_inventory_item_count(&"log_block") == 3, "completed UI craft consumed wrong wood count")
		_expect((_hud.crafting_panel.get_node("CraftingImpactTimer") as Timer).is_stopped(), "completed craft did not stop crafting audio timer")
		_expect(not (_hud.crafting_panel.get_node("CraftingImpactPlayer") as AudioStreamPlayer).playing, "completed craft did not stop crafting audio")
		_expect((_hud.crafting_panel.get_node("CraftingCompletePlayer") as AudioStreamPlayer).playing, "completed craft did not play completion audio")
		_hud.crafting_panel.select_recipe(&"copper_helmet")
		_expect(not _hud.crafting_panel.get_craft_button().is_craft_enabled(), "unavailable recipe button remained enabled")
		_hud.crafting_panel.select_recipe(&"copper_sword")
		_expect(_hud.crafting_panel.get_craft_button().is_craft_enabled(), "available recipe button was disabled")
		_hud.crafting_panel.get_craft_button().pressed.emit()
		_crafting.advance_time(1.0)
		_hud.close_side_panel()
		_phase = 6
	elif _phase == 6 and _frame == 78:
		_expect(not _crafting.is_crafting(), "closing backpack did not cancel crafting")
		_expect(not _hud.side_panel.is_open() and not _hud.crafting_panel.is_open(), "HUD panels did not close together")
		_expect((_hud.crafting_panel.get_node("CraftingImpactTimer") as Timer).is_stopped(), "closing backpack did not stop crafting audio timer")
		_expect(not (_hud.crafting_panel.get_node("CraftingImpactPlayer") as AudioStreamPlayer).playing, "closing backpack did not stop crafting audio")
		_expect(not (_hud.crafting_panel.get_node("CraftingCompletePlayer") as AudioStreamPlayer).playing, "closing backpack did not stop completion audio")
		_expect(_inventory.get_inventory_item_count(&"copper_sword") == 0, "canceled sword craft added output")
		_expect(_inventory.get_inventory_item_count(&"stone_block") == 7, "closing backpack consumed stone")
		_expect(_inventory.get_inventory_item_count(&"log_block") == 3, "closing backpack consumed wood")
		_hud.free()
		_camera_rig.free()
		_phase = 7
	elif _phase == 7 and _frame == 88:
		_finish()
	return false

func _check_open_state() -> void:
	_expect(_hud.side_panel.is_open(), "backpack did not open")
	_expect(_hud.crafting_panel.is_open(), "crafting panel did not open with backpack")
	_expect(_hud.crafting_panel.get_progress() > 0.95, "crafting panel opening animation did not complete")
	_expect(_hud.crafting_panel.get_selected_recipe_id() == &"copper_pickaxe", "first recipe was not selected")
	_expect(_hud.crafting_panel.get_craft_button().is_craft_enabled(), "selected craft button was disabled")
	_expect(_camera_rig.camera.h_offset < 0.0, "camera framing did not account for the wider left panel")
	var recipe_scroll := _hud.crafting_panel.get_node("Margin/Content/Body/Recipes/RecipeScroll") as ScrollContainer
	var recipe_list := _hud.crafting_panel.get_node("Margin/Content/Body/Recipes/RecipeScroll/RecipeList") as VBoxContainer
	_expect(recipe_scroll != null and recipe_list.get_child_count() == 7, "scrollable recipe list did not contain seven recipes")
	var ingredient_list := _hud.crafting_panel.get_node("Margin/Content/Body/Details/IngredientList") as VBoxContainer
	_expect(ingredient_list.get_child_count() == 2, "selected recipe ingredients were not displayed")
	var stone_count := (ingredient_list.get_child(0) as HBoxContainer).get_child(1) as Label
	_expect(stone_count.text.contains("10 / 3"), "ingredient display did not include hotbar materials")
	var crafting_rect := _hud.crafting_panel.get_global_rect()
	var backpack_rect := _hud.side_panel.get_global_rect()
	for slot in _hud.hotbar.slot_nodes:
		var slot_rect := (slot as HotbarSlot).get_global_rect()
		_expect(not crafting_rect.intersects(slot_rect), "crafting panel covered hotbar slot %d" % (slot as HotbarSlot).slot_index)
		_expect(not backpack_rect.intersects(slot_rect), "backpack covered hotbar slot %d" % (slot as HotbarSlot).slot_index)

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
