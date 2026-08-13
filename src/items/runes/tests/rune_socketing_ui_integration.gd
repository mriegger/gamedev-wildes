extends SceneTree

const GEAR_INDEX: int = 0
const RUNE_INDEX: int = 1

var _frame: int = 0
var _errors: Array[String] = []
var _inventory: InventoryModel
var _proficiency: ItemProficiency
var _socketing: RuneSocketingCoordinator
var _crafting: CraftingCoordinator
var _recipe_catalog: CraftingRecipeCatalog
var _panel: CraftingPanel

func _init() -> void:
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	_inventory = InventoryModel.new(item_catalog)
	_inventory.slots[GEAR_INDEX] = InventoryStack.new(&"copper_sword", 1)
	_inventory.slots[RUNE_INDEX] = InventoryStack.new(&"basic_rune", 2)
	_inventory.slots[2] = InventoryStack.new(&"stone_block", 10)
	_inventory.slots[3] = InventoryStack.new(&"log_block", 5)
	_proficiency = ItemProficiency.new(item_catalog)
	_socketing = RuneSocketingCoordinator.new()
	_expect(_socketing.setup(_inventory, _proficiency), "socketing setup failed")
	_recipe_catalog = load("res://crafting/crafting_recipe_catalog.tres") as CraftingRecipeCatalog
	_crafting = CraftingCoordinator.new()
	_crafting.setup(_inventory, _recipe_catalog)
	_panel = (load("res://crafting/presentation/crafting_panel.tscn") as PackedScene).instantiate() as CraftingPanel
	root.add_child(_panel)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_panel.setup(_crafting, _recipe_catalog)
		_panel.setup_socketing(_inventory, _socketing)
	elif _frame == 3:
		_start_workspace_test()
	elif _frame == 5:
		_test_workspace_and_slot_states()
	elif _frame == 7:
		_test_socket_and_unsocket()
	elif _frame == 9:
		_test_close_and_reopen()
		_panel.free()
	elif _frame == 25:
		_finish()
	return false

func _start_workspace_test() -> void:
	_panel.open()
	_expect(_panel.get_current_workspace_id() == CraftingPanel.CRAFTING_WORKSPACE_ID, "panel did not open on crafting")

func _test_workspace_and_slot_states() -> void:
	(_panel.get_node("Margin/Content/WorkspaceTabs/Runes") as Button).pressed.emit()
	_expect(_panel.get_current_workspace_id() == CraftingPanel.RUNES_WORKSPACE_ID, "rune workspace did not open")
	var rune_panel := _panel.get_rune_socketing_panel()
	var gear_payload := {"source_index": GEAR_INDEX, "drag_count": 1}
	_expect(rune_panel.get_gear_slot()._can_drop_data(Vector2.ZERO, gear_payload), "gear drop was rejected")
	rune_panel.get_gear_slot()._drop_data(Vector2.ZERO, gear_payload)
	_expect(rune_panel.get_selected_gear_index() == GEAR_INDEX, "gear drop did not select a reference")
	var rune_slots := rune_panel.get_rune_slots()
	_expect(rune_slots[0].get_state() == RuneSocketingSlot.State.LOCKED, "locked rune slot was not rendered")
	_expect(rune_slots[1].get_state() == RuneSocketingSlot.State.UNAVAILABLE, "second unavailable slot was not rendered")
	_expect(rune_slots[2].get_state() == RuneSocketingSlot.State.UNAVAILABLE, "third unavailable slot was not rendered")
	_expect(_proficiency.add_experience(&"copper_sword", 100.0) == 1, "fixture did not unlock the common rune slot")
	rune_panel.clear_gear_reference()
	rune_panel.get_gear_slot()._drop_data(Vector2.ZERO, gear_payload)
	_expect(rune_slots[0].get_state() == RuneSocketingSlot.State.EMPTY, "unlocked empty rune slot was not rendered")

func _test_socket_and_unsocket() -> void:
	var rune_panel := _panel.get_rune_socketing_panel()
	var slot := rune_panel.get_rune_slots()[0]
	var rune_payload := {"source_index": RUNE_INDEX, "drag_count": 2}
	_expect(slot._can_drop_data(Vector2.ZERO, rune_payload), "compatible rune drop was rejected")
	slot._drop_data(Vector2.ZERO, rune_payload)
	_expect(slot.get_state() == RuneSocketingSlot.State.FILLED, "socketed rune slot was not rendered as filled")
	_expect(_inventory.get_socketed_rune_ids(GEAR_INDEX) == _rune_ids([&"basic_rune"]), "rune UI did not socket the rune")
	_expect(_inventory.get_slot(RUNE_INDEX).count == 1, "rune UI consumed the wrong count")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	slot._gui_input(click)
	_expect(slot.get_state() == RuneSocketingSlot.State.EMPTY, "unsocketed rune slot did not return to empty")
	_expect(_inventory.get_socketed_rune_ids(GEAR_INDEX).is_empty(), "rune UI did not unsocket the rune")
	_expect(_inventory.get_inventory_item_count(&"basic_rune") == 2, "unsocket did not return the rune")

func _test_close_and_reopen() -> void:
	_panel.close_immediate()
	_expect(_panel.get_rune_socketing_panel().get_selected_gear_index() == -1, "closing retained the gear reference")
	_panel.open()
	_expect(_panel.get_current_workspace_id() == CraftingPanel.CRAFTING_WORKSPACE_ID, "reopening did not restore crafting")

func _finish() -> void:
	if _errors.is_empty():
		print("RUNE_SOCKETING_UI PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _rune_ids(values: Array[StringName]) -> Array[StringName]:
	return values

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
