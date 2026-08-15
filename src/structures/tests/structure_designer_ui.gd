extends SceneTree

var _failures: Array[String] = []
var _blocking_states: Array[bool] = []
var _weights: Array[float] = []
var _void_request_count: int
var _connection_targeting_count: int = 0
var _removed_sockets: Array[StringName] = []
var _socket_fill_requests: Array[Array] = []
var _marker_targets: Array[Array] = []
var _marker_commits: Array[Array] = []
var _marker_clear_count: int

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
	var placeable_copy := toolbelt.get_placeable_item_ids()
	placeable_copy.clear()
	_expect(toolbelt.get_placeable_item_ids().size() == 12, "placeable query exposed mutable state")
	_expect(not toolbelt.try_assign(-1, &"torch"), "negative assignment index was accepted")
	_expect(not toolbelt.try_assign(9, &"torch"), "out-of-range assignment index was accepted")
	_expect(not toolbelt.try_assign(0, &"copper_pickaxe"), "non-placeable assignment was accepted")
	await _test_generic_ui(item_catalog, toolbelt)
	await _test_module_ui(item_catalog)
	if _failures.is_empty():
		print("STRUCTURE_DESIGNER_UI PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

func _test_generic_ui(item_catalog: ItemCatalog, toolbelt: CreativeToolbelt) -> void:
	var ui := await _create_ui(item_catalog, toolbelt, StructureDraft.Format.GENERIC_STRUCTURE)
	var module_panel := ui.get_node("ModulePanel") as PanelContainer
	var module_tools_hint := ui.get_node("ModuleToolsHint") as Label
	var palette_grid := ui.get_node("PaletteOverlay/PalettePanel/Margin/VBox/Scroll/PaletteGrid") as GridContainer
	var crosshair := ui.get_node("Crosshair") as Label
	var hotbar := ui.get_node("HotbarView") as HotbarView
	_expect(not module_panel.visible and not module_tools_hint.visible, "generic structure exposed Level Module tools")
	ui.open_module_panel()
	_expect(not ui.is_module_panel_open() and not ui.is_ui_blocking(), "generic structure opened Level Module tools")
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

func _test_module_ui(item_catalog: ItemCatalog) -> void:
	var toolbelt := CreativeToolbelt.new()
	_expect(toolbelt.setup(item_catalog), "module toolbelt setup failed")
	var ui := await _create_ui(item_catalog, toolbelt, StructureDraft.Format.LEVEL_MODULE)
	var module_panel := ui.get_node("ModulePanel") as PanelContainer
	var module_tools_hint := ui.get_node("ModuleToolsHint") as Label
	var connection_mode_hint := ui.get_node("ConnectionModeHint") as Label
	var weight_input := ui.get_node("ModulePanel/Margin/VBox/WeightRow/Weight") as SpinBox
	var connection_button := ui.get_node("ModulePanel/Margin/VBox/ConnectionHeader/PlaceConnections") as Button
	var connection_summary := ui.get_node("ModulePanel/Margin/VBox/ConnectionSummary") as Label
	var socket_list := ui.get_node("ModulePanel/Margin/VBox/SocketScroll/SocketList") as VBoxContainer
	var socket_help := ui.get_node("ModulePanel/Margin/VBox/SocketHelp") as Label
	var marker_title := ui.get_node("ModulePanel/Margin/VBox/MarkersTitle") as Label
	var spawn_title := ui.get_node("ModulePanel/Margin/VBox/Markers/Spawn/Title") as Label
	var entrance_exit_title := ui.get_node("ModulePanel/Margin/VBox/Markers/Return/Title") as Label
	var marker_commit := ui.get_node("ModulePanel/Margin/VBox/Markers/Actions/Commit") as Button
	_expect(not module_panel.visible and module_tools_hint.visible, "Level Module did not start in first-person build mode")
	_expect(module_panel.find_children("*Torch*", "Control", true, false).is_empty(), "Level Module panel retained torch metadata clutter")
	_expect(socket_help.text.contains("1×2") and socket_help.text.contains("prebuilt opening") and socket_help.text.contains("unused doorway") and socket_help.text.contains("Must connect"), "connection controls did not explain variable openings and unused fills")
	_expect(marker_title.text.contains("aim before opening") and spawn_title.text == "Player Spawn" and entrance_exit_title.text == "Entrance / Exit Door", "entry marker controls did not distinguish spawn from the shared entrance/exit door")
	var blocking_state_start := _blocking_states.size()
	ui.ui_blocking_changed.connect(_on_ui_blocking_changed)
	ui.open_module_panel()
	_expect(ui.is_module_panel_open() and module_panel.visible and not module_tools_hint.visible, "opening module tools did not show the panel")
	_expect(ui.is_ui_blocking(), "open module tools did not block first-person input")
	ui.open_palette()
	_expect(ui.is_palette_open() and not ui.is_module_panel_open() and not module_panel.visible, "palette did not replace module tools")
	ui.open_module_panel()
	_expect(not ui.is_palette_open() and ui.is_module_panel_open() and module_panel.visible, "module tools did not replace the palette")
	_expect(_blocking_states.slice(blocking_state_start) == [true], "switching designer panels toggled input blocking")
	ui.weight_requested.connect(_on_weight_requested)
	ui.void_requested.connect(_on_void_requested)
	ui.connection_targeting_requested.connect(_on_connection_targeting_requested)
	ui.socket_remove_requested.connect(_on_socket_remove_requested)
	ui.socket_unused_fill_block_requested.connect(_on_socket_unused_fill_block_requested)
	ui.marker_target_requested.connect(_on_marker_target_requested)
	ui.markers_commit_requested.connect(_on_markers_commit_requested)
	ui.markers_clear_requested.connect(_on_markers_clear_requested)
	var north_socket := LevelSocketDefinition.new()
	north_socket.socket_id = &"north"
	north_socket.cell = Vector3i(3, 1, 0)
	north_socket.direction = LevelSocketDefinition.Direction.NORTH
	north_socket.unused_fill_block_id = BlockId.Type.STONE
	var east_socket := LevelSocketDefinition.new()
	east_socket.socket_id = &"east"
	east_socket.cell = Vector3i(6, 1, 3)
	east_socket.direction = LevelSocketDefinition.Direction.EAST
	var south_socket := LevelSocketDefinition.new()
	south_socket.socket_id = &"south"
	south_socket.cell = Vector3i(3, 1, 6)
	south_socket.direction = LevelSocketDefinition.Direction.SOUTH
	var west_socket := LevelSocketDefinition.new()
	west_socket.socket_id = &"west"
	west_socket.cell = Vector3i(0, 1, 3)
	west_socket.direction = LevelSocketDefinition.Direction.WEST
	var spawn_marker := LevelMarkerDefinition.new()
	spawn_marker.cell = Vector3i(1, 1, 1)
	spawn_marker.facing = LevelSocketDefinition.Direction.SOUTH
	var return_marker := LevelMarkerDefinition.new()
	return_marker.cell = Vector3i(5, 1, 5)
	return_marker.facing = LevelSocketDefinition.Direction.WEST
	var sockets: Array[LevelSocketDefinition] = [north_socket, east_socket]
	var aperture_sizes: Dictionary = {
		&"north": Vector2i(3, 6),
		&"east": Vector2i(1, 2),
		&"south": Vector2i(1, 2),
		&"west": Vector2i(1, 2),
	}
	ui.present_module_state(0.05, sockets, aperture_sizes, null, null)
	_expect(connection_summary.text.contains("eligible as an expansion module"), "two connections were not presented as expansion-eligible")
	_expect((socket_list.get_child(0).get_child(0).get_child(0) as Label).text.contains("3×6"), "connection list omitted the opening size")
	var north_fill := socket_list.get_child(0).get_child(1).get_child(1) as OptionButton
	_expect(north_fill.get_item_count() == 12, "unused-fill selector did not contain Must connect plus every placeable cube")
	_expect(north_fill.get_item_index(BlockId.Type.COPPER) == -1, "unused-fill selector included Copper material")
	_expect(north_fill.get_item_index(BlockId.Type.TORCH) == -1 and north_fill.get_item_index(BlockId.Type.WATER) == -1, "unused-fill selector included a non-cube block")
	_expect(north_fill.get_selected_id() == BlockId.Type.STONE, "unused-fill selector did not present the socket's current block")
	var stone_bricks_index := north_fill.get_item_index(BlockId.Type.STONE_BRICKS)
	north_fill.select(stone_bricks_index)
	north_fill.item_selected.emit(stone_bricks_index)
	_expect(_socket_fill_requests == [[&"north", BlockId.Type.STONE_BRICKS]], "unused-fill selector emitted the wrong socket or block")
	var must_connect_index := north_fill.get_item_index(StructureCell.AIR)
	north_fill.select(must_connect_index)
	north_fill.item_selected.emit(must_connect_index)
	_expect(_socket_fill_requests == [[&"north", BlockId.Type.STONE_BRICKS], [&"north", StructureCell.AIR]], "Must connect did not emit the required-connection sentinel")
	var one_socket: Array[LevelSocketDefinition] = [north_socket]
	ui.present_module_state(0.05, one_socket, aperture_sizes, null, null)
	_expect(_socket_fill_requests.size() == 2, "rebuilding connection rows emitted a fill request")
	_expect(connection_summary.text.contains("cap or dead end"), "one connection was not presented as cap-eligible")
	var four_sockets: Array[LevelSocketDefinition] = [north_socket, east_socket, south_socket, west_socket]
	ui.present_module_state(0.05, four_sockets, aperture_sizes, null, null)
	_expect(socket_list.get_child_count() == 4 and connection_button.disabled, "four-sided room did not complete the simple connection workflow")
	ui.present_module_state(0.05, sockets, aperture_sizes, spawn_marker, return_marker)
	_expect(weight_input.value == 0.05 and _weights.is_empty(), "module weight presentation changed or re-emitted an imported sub-tenth value")
	_expect(is_zero_approx(weight_input.step) and weight_input.allow_lesser and weight_input.allow_greater, "module weight editor did not preserve the positive finite weight contract")
	_expect(socket_list.get_child_count() == 2, "module socket list presentation mismatch")
	_expect(not connection_button.disabled, "partial connection layout disabled connection targeting")
	_expect(connection_summary.text.contains("eligible as a start module"), "paired markers were not presented as start-eligible")
	weight_input.value = 3.25
	_expect(_weights == [3.25], "weight editor quantized a non-tenth request")
	(ui.get_node("ModulePanel/Margin/VBox/SetVoid") as Button).pressed.emit()
	_expect(_void_request_count == 1, "VOID control did not emit an intent")
	connection_button.pressed.emit()
	_expect(_connection_targeting_count == 1, "connection control did not request targeting mode")
	_expect(not ui.is_module_panel_open() and not ui.is_ui_blocking(), "connection control did not return to first-person mode")
	ui.set_connection_targeting(true)
	_expect(connection_mode_hint.visible and not module_tools_hint.visible, "connection targeting did not replace the module hint")
	ui.present_connection_target(LevelSocketDefinition.Direction.NORTH, true, true, Vector2i(3, 6))
	_expect(connection_mode_hint.text.contains("North 3×6 opening ready") and connection_mode_hint.text.contains("Left-click"), "valid connection target guidance is unclear")
	ui.present_connection_target(LevelSocketDefinition.Direction.NORTH, false, false, Vector2i(3, 6))
	_expect(connection_mode_hint.text.contains("already has a connection"), "used connection side guidance is unclear")
	ui.set_connection_targeting(false)
	ui.open_module_panel()
	(socket_list.get_child(1).get_child(0).get_child(1) as Button).pressed.emit()
	_expect(_removed_sockets == [&"east"], "socket remove control emitted the wrong ID")
	var spawn_facing := ui.get_node("ModulePanel/Margin/VBox/Markers/Spawn/Controls/Facing") as OptionButton
	spawn_facing.select(LevelSocketDefinition.Direction.EAST)
	(ui.get_node("ModulePanel/Margin/VBox/Markers/Spawn/Controls/Set") as Button).pressed.emit()
	_expect(_marker_targets == [[StructureDesignerUI.MarkerRole.SPAWN, LevelSocketDefinition.Direction.EAST]], "spawn target control emitted the wrong role or facing")
	var return_facing := ui.get_node("ModulePanel/Margin/VBox/Markers/Return/Controls/Facing") as OptionButton
	return_facing.select(LevelSocketDefinition.Direction.WEST)
	(ui.get_node("ModulePanel/Margin/VBox/Markers/Return/Controls/Set") as Button).pressed.emit()
	_expect(_marker_targets == [
		[StructureDesignerUI.MarkerRole.SPAWN, LevelSocketDefinition.Direction.EAST],
		[StructureDesignerUI.MarkerRole.RETURN, LevelSocketDefinition.Direction.WEST],
	], "return target control emitted the wrong role or facing")
	ui.set_pending_marker(StructureDesignerUI.MarkerRole.SPAWN, Vector3i(1, 1, 2), LevelSocketDefinition.Direction.EAST)
	_expect(marker_commit.disabled, "one pending marker enabled paired commit")
	ui.set_pending_marker(StructureDesignerUI.MarkerRole.RETURN, Vector3i(4, 1, 5), LevelSocketDefinition.Direction.WEST)
	_expect(not marker_commit.disabled, "two pending markers did not enable paired commit")
	marker_commit.pressed.emit()
	_expect(_marker_commits == [[Vector3i(1, 1, 2), LevelSocketDefinition.Direction.EAST, Vector3i(4, 1, 5), LevelSocketDefinition.Direction.WEST]], "paired marker commit emitted incorrect candidates")
	(ui.get_node("ModulePanel/Margin/VBox/Markers/Actions/Clear") as Button).pressed.emit()
	_expect(_marker_clear_count == 1 and marker_commit.disabled, "marker clear did not emit or retained pending state")
	(ui.get_node("ModulePanel/Margin/VBox/Header/Close") as Button).pressed.emit()
	_expect(not ui.is_module_panel_open() and not module_panel.visible and module_tools_hint.visible, "module close control did not restore build mode")
	_expect(not ui.is_ui_blocking() and _blocking_states.back() == false, "closing module tools did not release input blocking")
	ui.queue_free()
	await process_frame

func _create_ui(item_catalog: ItemCatalog, toolbelt: CreativeToolbelt, format: StructureDraft.Format) -> StructureDesignerUI:
	var ui := (load("res://structures/presentation/structure_designer_ui.tscn") as PackedScene).instantiate() as StructureDesignerUI
	root.add_child(ui)
	await process_frame
	ui.setup(item_catalog, toolbelt, format)
	await process_frame
	return ui

func _on_ui_blocking_changed(blocking: bool) -> void:
	_blocking_states.append(blocking)

func _on_weight_requested(weight: float) -> void:
	_weights.append(weight)

func _on_void_requested() -> void:
	_void_request_count += 1

func _on_connection_targeting_requested() -> void:
	_connection_targeting_count += 1

func _on_socket_remove_requested(socket_id: StringName) -> void:
	_removed_sockets.append(socket_id)

func _on_socket_unused_fill_block_requested(socket_id: StringName, block_id: int) -> void:
	_socket_fill_requests.append([socket_id, block_id])

func _on_marker_target_requested(role: StructureDesignerUI.MarkerRole, facing: LevelSocketDefinition.Direction) -> void:
	_marker_targets.append([role, facing])

func _on_markers_commit_requested(
	spawn_cell: Vector3i,
	spawn_facing: LevelSocketDefinition.Direction,
	return_cell: Vector3i,
	return_facing: LevelSocketDefinition.Direction,
) -> void:
	_marker_commits.append([spawn_cell, spawn_facing, return_cell, return_facing])

func _on_markers_clear_requested() -> void:
	_marker_clear_count += 1

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
