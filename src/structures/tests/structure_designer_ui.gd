extends SceneTree

var _failures: Array[String] = []
var _blocking_states: Array[bool] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var expected_placeables: Array[StringName] = []
	for definition in item_catalog.definitions:
		if definition.secondary_action is BlockPlacementActionDefinition:
			expected_placeables.append(definition.id)
	_expect(expected_placeables.size() == 12, "item catalog did not expose the expected 12 placeables")
	var toolbelt := CreativeToolbelt.new()
	_expect(toolbelt.setup(item_catalog), "creative toolbelt setup failed")
	_expect(toolbelt.get_placeable_item_ids() == expected_placeables, "toolbelt placeables did not follow catalog placement actions")
	_expect(toolbelt.get_assigned_item_ids() == expected_placeables.slice(0, CreativeToolbelt.SLOT_COUNT), "toolbelt defaults did not follow catalog order")
	var assignment_copy := toolbelt.get_assigned_item_ids()
	assignment_copy[0] = &"torch"
	_expect(toolbelt.get_assigned_item_ids()[0] == expected_placeables[0], "assignment query exposed mutable state")
	_expect(not toolbelt.try_assign(-1, &"torch"), "negative assignment index was accepted")
	_expect(not toolbelt.try_assign(9, &"torch"), "out-of-range assignment index was accepted")
	_expect(not toolbelt.try_assign(0, &"copper_pickaxe"), "non-placeable assignment was accepted")
	await _test_palette(item_catalog, toolbelt)
	if _failures.is_empty():
		print("STRUCTURE_DESIGNER_UI PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

func _test_palette(item_catalog: ItemCatalog, toolbelt: CreativeToolbelt) -> void:
	var ui := (load("res://structures/presentation/structure_designer_ui.tscn") as PackedScene).instantiate() as StructureDesignerUI
	root.add_child(ui)
	await process_frame
	ui.setup(item_catalog, toolbelt)
	await process_frame
	var palette_grid := ui.get_node("PaletteOverlay/PalettePanel/Margin/VBox/Scroll/PaletteGrid") as GridContainer
	var crosshair := ui.get_node("Crosshair") as Label
	var hotbar := ui.get_node("HotbarView") as HotbarView
	_expect(not ui.has_node("ModulePanel"), "generic workspace retained a Level Module panel")
	_expect(palette_grid.get_child_count() == 12, "palette did not contain every placeable item")
	_expect(crosshair.get_global_rect().get_center().is_equal_approx(root.get_visible_rect().get_center()), "crosshair was not centered")
	_expect(hotbar.slot_nodes.size() == CreativeToolbelt.SLOT_COUNT, "designer hotbar did not contain nine slots")
	for index in range(CreativeToolbelt.SLOT_COUNT):
		var expected_icon := item_catalog.get_definition(toolbelt.get_assigned_item_ids()[index]).icon
		_expect(hotbar.slot_nodes[index].icon.texture == expected_icon, "designer hotbar icon mismatch at %d" % index)
		_expect(hotbar.slot_nodes[index].count_label.text.is_empty(), "designer hotbar displayed a count at %d" % index)
	ui.ui_blocking_changed.connect(_on_ui_blocking_changed)
	ui.open_palette()
	_expect(ui.is_palette_open() and ui.is_ui_blocking(), "opening palette did not block designer input")
	_expect(_blocking_states == [true], "opening palette did not emit blocking state")
	var torch_button: Button
	for button in palette_grid.get_children():
		if button.name == "Item_torch":
			torch_button = button as Button
			break
	_expect(torch_button != null, "palette omitted the torch placement item")
	if torch_button != null:
		torch_button.mouse_entered.emit()
		var assign_key := InputEventKey.new()
		assign_key.pressed = true
		assign_key.physical_keycode = KEY_2
		ui._unhandled_key_input(assign_key)
	_expect(toolbelt.get_assigned_item_ids()[1] == &"torch", "hovered palette item was not assigned to key 2")
	_expect(hotbar.slot_nodes[1].count_label.text.is_empty(), "palette assignment added an item count")
	hotbar.slot_nodes[5].request_selection()
	_expect(toolbelt.get_selected_index() == 0, "open palette allowed hotbar selection")
	ui.close_palette()
	_expect(not ui.is_palette_open() and _blocking_states == [true, false], "closing palette retained blocking state")
	hotbar.slot_nodes[5].request_selection()
	_expect(toolbelt.get_selected_index() == 5, "closed palette blocked hotbar selection")
	ui.queue_free()
	await process_frame

func _on_ui_blocking_changed(blocking: bool) -> void:
	_blocking_states.append(blocking)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
