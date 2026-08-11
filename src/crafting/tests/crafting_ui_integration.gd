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

func _init() -> void:
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	_recipe_catalog = load("res://crafting/crafting_recipe_catalog.tres") as CraftingRecipeCatalog
	_inventory = InventoryModel.new(item_catalog)
	_inventory.slots[InventoryModel.HOTBAR_SIZE] = InventoryStack.new(&"stone_block", 10)
	_inventory.slots[InventoryModel.HOTBAR_SIZE + 1] = InventoryStack.new(&"log_block", 5)
	_stats = ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	_inventory_stats = InventoryStatCoordinator.new()
	_expect(_inventory_stats.setup(_inventory, _stats), "inventory stat setup failed")
	_crafting = CraftingCoordinator.new()
	_crafting.setup(_inventory, _recipe_catalog)
	var packed := load("res://ui/hud/hud.tscn") as PackedScene
	_hud = packed.instantiate() as HUD
	root.add_child(_hud)

func _process(_delta: float) -> bool:
	_frame += 1
	if _phase == 0 and _frame == 2:
		_hud.setup_with_camera(_inventory, _inventory_stats, _crafting, _recipe_catalog, null, _stats)
		_hud.toggle_backpack()
		_phase = 1
	elif _phase == 1 and _frame == 35:
		_expect(_hud.side_panel.is_open(), "P behavior did not open the backpack")
		_expect(not _hud.crafting_panel.is_open(), "P behavior unexpectedly opened crafting")
		_expect(_hud.side_panel.get_progress() > 0.95, "backpack-only opening animation did not complete")
		_expect(_hud.crafting_panel.get_progress() < 0.01, "crafting panel appeared in backpack-only view")
		_expect(_action_uses_key("toggle_backpack", KEY_P), "toggle_backpack was not mapped to P")
		_expect(_action_uses_key("toggle_crafting", KEY_TAB), "toggle_crafting was not mapped to Tab")
		_hud.toggle_crafting()
	elif _phase == 1 and _frame == 68:
		_check_open_state()
		_hud.crafting_panel.get_craft_button().pressed.emit()
		_phase = 2
	elif _phase == 2 and _frame == 70:
		_expect(_crafting.is_crafting(), "craft button did not start selected recipe")
		_crafting.advance_time(1.0)
		_phase = 3
	elif _phase == 3 and _frame == 72:
		var button := _hud.crafting_panel.get_craft_button()
		_expect(button.get_progress() > 0.49 and button.get_progress() < 0.55, "craft button did not show half progress")
		_hud.crafting_panel.select_recipe(&"copper_sword")
		_phase = 4
	elif _phase == 4 and _frame == 74:
		_expect(not _crafting.is_crafting(), "recipe selection did not cancel crafting")
		_expect(is_zero_approx(_hud.crafting_panel.get_craft_button().get_progress()), "recipe selection did not reset button")
		_expect(_inventory.get_backpack_item_count(&"stone_block") == 10, "recipe selection consumed stone")
		_expect(_inventory.get_backpack_item_count(&"log_block") == 5, "recipe selection consumed wood")
		_hud.crafting_panel.select_recipe(&"copper_pickaxe")
		_hud.crafting_panel.get_craft_button().pressed.emit()
		_crafting.advance_time(2.0)
		_phase = 5
	elif _phase == 5 and _frame == 76:
		_expect(_inventory.get_backpack_item_count(&"copper_pickaxe") == 1, "completed UI craft did not add output")
		_expect(_inventory.get_backpack_item_count(&"stone_block") == 7, "completed UI craft consumed wrong stone count")
		_expect(_inventory.get_backpack_item_count(&"log_block") == 3, "completed UI craft consumed wrong wood count")
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
		_expect(_inventory.get_backpack_item_count(&"copper_sword") == 0, "canceled sword craft added output")
		_expect(_inventory.get_backpack_item_count(&"stone_block") == 7, "closing backpack consumed stone")
		_expect(_inventory.get_backpack_item_count(&"log_block") == 3, "closing backpack consumed wood")
		_hud.free()
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
	var recipe_scroll := _hud.crafting_panel.get_node("Margin/Content/Body/Recipes/RecipeScroll") as ScrollContainer
	var recipe_list := _hud.crafting_panel.get_node("Margin/Content/Body/Recipes/RecipeScroll/RecipeList") as VBoxContainer
	_expect(recipe_scroll != null and recipe_list.get_child_count() == 7, "scrollable recipe list did not contain seven recipes")
	var ingredient_list := _hud.crafting_panel.get_node("Margin/Content/Body/Details/IngredientList") as VBoxContainer
	_expect(ingredient_list.get_child_count() == 2, "selected recipe ingredients were not displayed")

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
