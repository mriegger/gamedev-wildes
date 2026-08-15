extends CanvasLayer
class_name StructureDesignerUI

enum MarkerRole {
	SPAWN,
	RETURN,
}

enum ActiveOverlay {
	NONE,
	PALETTE,
	MODULE_TOOLS,
}

signal ui_blocking_changed(blocking: bool)
signal weight_requested(weight: float)
signal void_requested
signal connection_targeting_requested
signal socket_remove_requested(socket_id: StringName)
signal socket_unused_fill_block_requested(socket_id: StringName, block_id: int)
signal enemy_spawn_zone_targeting_requested
signal enemy_spawn_zone_remove_requested(zone_id: StringName)
signal marker_target_requested(role: MarkerRole, facing: LevelSocketDefinition.Direction)
signal markers_commit_requested(
	spawn_cell: Vector3i,
	spawn_facing: LevelSocketDefinition.Direction,
	return_cell: Vector3i,
	return_facing: LevelSocketDefinition.Direction,
)
signal markers_clear_requested

var _item_catalog: ItemCatalog
var _toolbelt: CreativeToolbelt
var _active_overlay: ActiveOverlay = ActiveOverlay.NONE
var _module_tools_available: bool
var _connection_targeting: bool = false
var _enemy_spawn_zone_targeting: bool = false
var _hovered_palette_item_id: StringName
var _pending_spawn_cell: Variant
var _pending_spawn_facing: LevelSocketDefinition.Direction = LevelSocketDefinition.Direction.NORTH
var _pending_return_cell: Variant
var _pending_return_facing: LevelSocketDefinition.Direction = LevelSocketDefinition.Direction.NORTH
var _enemy_spawn_zone_rows: Dictionary = {}
var _enemy_spawn_zone_candidate_counts: Dictionary = {}

@onready var _hotbar: HotbarView = $HotbarView as HotbarView
@onready var _palette_overlay: Control = $PaletteOverlay as Control
@onready var _palette_grid: GridContainer = $PaletteOverlay/PalettePanel/Margin/VBox/Scroll/PaletteGrid as GridContainer
@onready var _module_tools_hint: Label = $ModuleToolsHint as Label
@onready var _connection_mode_hint: Label = $ConnectionModeHint as Label
@onready var _enemy_spawn_zone_mode_hint: Label = $EnemySpawnZoneModeHint as Label
@onready var _module_panel: PanelContainer = $ModulePanel as PanelContainer
@onready var _module_close_button: Button = $ModulePanel/Margin/VBox/Header/Close as Button
@onready var _weight_input: SpinBox = $ModulePanel/Margin/VBox/WeightRow/Weight as SpinBox
@onready var _void_button: Button = $ModulePanel/Margin/VBox/SetVoid as Button
@onready var _connection_button: Button = $ModulePanel/Margin/VBox/ConnectionHeader/PlaceConnections as Button
@onready var _connection_summary: Label = $ModulePanel/Margin/VBox/ConnectionSummary as Label
@onready var _socket_list: VBoxContainer = $ModulePanel/Margin/VBox/SocketScroll/SocketList as VBoxContainer
@onready var _enemy_spawn_zone_button: Button = $ModulePanel/Margin/VBox/DetailsScroll/Details/EnemySpawnZoneHeader/Add as Button
@onready var _enemy_spawn_zone_summary: Label = $ModulePanel/Margin/VBox/DetailsScroll/Details/EnemySpawnZoneSummary as Label
@onready var _enemy_spawn_zone_list: VBoxContainer = $ModulePanel/Margin/VBox/DetailsScroll/Details/EnemySpawnZoneList as VBoxContainer
@onready var _spawn_current: Label = $ModulePanel/Margin/VBox/DetailsScroll/Details/Markers/Spawn/Current as Label
@onready var _spawn_pending: Label = $ModulePanel/Margin/VBox/DetailsScroll/Details/Markers/Spawn/Pending as Label
@onready var _spawn_facing: OptionButton = $ModulePanel/Margin/VBox/DetailsScroll/Details/Markers/Spawn/Controls/Facing as OptionButton
@onready var _spawn_set_button: Button = $ModulePanel/Margin/VBox/DetailsScroll/Details/Markers/Spawn/Controls/Set as Button
@onready var _return_current: Label = $ModulePanel/Margin/VBox/DetailsScroll/Details/Markers/Return/Current as Label
@onready var _return_pending: Label = $ModulePanel/Margin/VBox/DetailsScroll/Details/Markers/Return/Pending as Label
@onready var _return_facing: OptionButton = $ModulePanel/Margin/VBox/DetailsScroll/Details/Markers/Return/Controls/Facing as OptionButton
@onready var _return_set_button: Button = $ModulePanel/Margin/VBox/DetailsScroll/Details/Markers/Return/Controls/Set as Button
@onready var _marker_commit_button: Button = $ModulePanel/Margin/VBox/DetailsScroll/Details/Markers/Actions/Commit as Button
@onready var _marker_clear_button: Button = $ModulePanel/Margin/VBox/DetailsScroll/Details/Markers/Actions/Clear as Button

func _ready() -> void:
	_palette_overlay.visible = false
	_module_tools_hint.visible = false
	_connection_mode_hint.visible = false
	_enemy_spawn_zone_mode_hint.visible = false
	_module_panel.visible = false
	_hotbar.slot_selection_requested.connect(_on_hotbar_selection_requested)
	_module_close_button.pressed.connect(close_module_panel)
	_weight_input.value_changed.connect(_on_weight_changed)
	_void_button.pressed.connect(_on_void_pressed)
	_connection_button.pressed.connect(_on_connection_pressed)
	_enemy_spawn_zone_button.pressed.connect(_on_enemy_spawn_zone_pressed)
	_spawn_set_button.pressed.connect(_on_marker_target_pressed.bind(MarkerRole.SPAWN, _spawn_facing))
	_return_set_button.pressed.connect(_on_marker_target_pressed.bind(MarkerRole.RETURN, _return_facing))
	_marker_commit_button.pressed.connect(_on_markers_commit_pressed)
	_marker_clear_button.pressed.connect(_on_markers_clear_pressed)
	_populate_direction_options(_spawn_facing)
	_populate_direction_options(_return_facing)
	_refresh_pending_markers()

func setup(item_catalog: ItemCatalog, toolbelt: CreativeToolbelt, format: StructureDraft.Format) -> void:
	assert(is_node_ready())
	assert(item_catalog != null)
	assert(toolbelt != null)
	assert(_item_catalog == null)
	_item_catalog = item_catalog
	_toolbelt = toolbelt
	_module_tools_available = format == StructureDraft.Format.LEVEL_MODULE
	_build_palette()
	_refresh_hotbar()
	_present_active_overlay()

func open_palette() -> void:
	_set_active_overlay(ActiveOverlay.PALETTE)

func close_palette() -> void:
	if is_palette_open():
		_set_active_overlay(ActiveOverlay.NONE)

func toggle_palette() -> void:
	if is_palette_open():
		close_palette()
	else:
		open_palette()

func is_palette_open() -> bool:
	return _active_overlay == ActiveOverlay.PALETTE

func open_module_panel() -> void:
	if _module_tools_available:
		_set_active_overlay(ActiveOverlay.MODULE_TOOLS)

func close_module_panel() -> void:
	if is_module_panel_open():
		_set_active_overlay(ActiveOverlay.NONE)

func toggle_module_panel() -> void:
	if is_module_panel_open():
		close_module_panel()
	else:
		open_module_panel()

func is_module_panel_open() -> bool:
	return _active_overlay == ActiveOverlay.MODULE_TOOLS

func close_active_overlay() -> bool:
	if _active_overlay == ActiveOverlay.NONE:
		return false
	_set_active_overlay(ActiveOverlay.NONE)
	return true

func is_ui_blocking() -> bool:
	return _active_overlay != ActiveOverlay.NONE

func set_connection_targeting(active: bool) -> void:
	_connection_targeting = active
	if active:
		_connection_mode_hint.text = "CONNECTION MODE  •  Click a wall or an opening's floor  •  Esc when done"
	_present_active_overlay()

func set_enemy_spawn_zone_targeting(active: bool) -> void:
	_enemy_spawn_zone_targeting = active
	if active:
		_enemy_spawn_zone_mode_hint.text = "ENEMY SPAWN ZONE  •  Click the first floor corner  •  Right-click or Esc to cancel"
	_present_active_overlay()

func present_enemy_spawn_zone_target(
	first_corner: Variant,
	target_cell: Variant,
	candidate_count: int,
	valid: bool,
) -> void:
	if not _enemy_spawn_zone_targeting:
		return
	if target_cell == null:
		_enemy_spawn_zone_mode_hint.text = "ENEMY SPAWN ZONE  •  Aim at a floor  •  Right-click or Esc to cancel"
		return
	if first_corner == null:
		if valid:
			_enemy_spawn_zone_mode_hint.text = "First corner %s ready  •  Left-click  •  Right-click or Esc to cancel" % _cell_text(target_cell as Vector3i)
		else:
			_enemy_spawn_zone_mode_hint.text = "Enemy zones need solid floor and two clear blocks  •  Choose another cell"
		return
	if valid:
		_enemy_spawn_zone_mode_hint.text = "%s to %s  •  %d usable cells  •  Left-click to commit" % [_cell_text(first_corner as Vector3i), _cell_text(target_cell as Vector3i), candidate_count]
	else:
		_enemy_spawn_zone_mode_hint.text = "Second corner must share a floor level and leave at least one usable cell  •  Right-click or Esc to cancel"

func present_connection_target(
	direction: Variant,
	valid: bool,
	side_available: bool,
	aperture_size: Vector2i,
) -> void:
	if not _connection_targeting:
		return
	if direction == null:
		_connection_mode_hint.text = "CONNECTION MODE  •  Aim at a wall or an opening's floor  •  Esc when done"
		return
	var direction_text := _direction_text(direction as LevelSocketDefinition.Direction)
	if not side_available:
		_connection_mode_hint.text = "%s already has a connection  •  Choose another side  •  Esc when done" % direction_text
	elif valid:
		_connection_mode_hint.text = "%s %d×%d opening ready  •  Left-click to add  •  Esc when done" % [direction_text, aperture_size.x, aperture_size.y]
	else:
		_connection_mode_hint.text = "%s opening needs supported floors, enclosure, and clear interior  •  Esc when done" % direction_text

func present_module_state(
	weight: float,
	sockets: Array[LevelSocketDefinition],
	aperture_sizes: Dictionary,
	spawn_marker: LevelMarkerDefinition,
	return_marker: LevelMarkerDefinition,
) -> void:
	assert(_module_tools_available)
	_weight_input.set_value_no_signal(weight)
	_rebuild_socket_list(sockets, aperture_sizes)
	_connection_summary.text = _connection_summary_text(sockets.size(), spawn_marker != null)
	_connection_button.disabled = _all_cardinal_sides_used(sockets)
	_spawn_current.text = _marker_text("Current", spawn_marker)
	_return_current.text = _marker_text("Current", return_marker)

func present_enemy_spawn_zones(zones: Array[LevelEnemySpawnZone], candidate_counts: Dictionary) -> void:
	_clear_container(_enemy_spawn_zone_list)
	_enemy_spawn_zone_rows.clear()
	_enemy_spawn_zone_candidate_counts.clear()
	for zone in zones:
		present_enemy_spawn_zone(zone, int(candidate_counts.get(zone.zone_id, 0)), false)
	_refresh_enemy_spawn_zone_summary()

func present_enemy_spawn_zone(zone: LevelEnemySpawnZone, candidate_count: int, refresh_summary: bool = true) -> void:
	if zone == null:
		return
	var row := _enemy_spawn_zone_rows.get(zone.zone_id) as HBoxContainer
	if row == null:
		row = _create_enemy_spawn_zone_row(zone.zone_id)
		_enemy_spawn_zone_rows[zone.zone_id] = row
		_enemy_spawn_zone_list.add_child(row)
	(row.get_child(0) as Label).text = _enemy_spawn_zone_row_text(zone, candidate_count)
	_enemy_spawn_zone_candidate_counts[zone.zone_id] = candidate_count
	if refresh_summary:
		_refresh_enemy_spawn_zone_summary()

func remove_enemy_spawn_zone(zone_id: StringName) -> void:
	var row := _enemy_spawn_zone_rows.get(zone_id) as HBoxContainer
	if row != null:
		_enemy_spawn_zone_list.remove_child(row)
		row.queue_free()
	_enemy_spawn_zone_rows.erase(zone_id)
	_enemy_spawn_zone_candidate_counts.erase(zone_id)
	_refresh_enemy_spawn_zone_summary()

func set_pending_marker(
	role: MarkerRole,
	cell: Vector3i,
	facing: LevelSocketDefinition.Direction,
) -> void:
	if role == MarkerRole.SPAWN:
		_pending_spawn_cell = cell
		_pending_spawn_facing = facing
	else:
		_pending_return_cell = cell
		_pending_return_facing = facing
	_refresh_pending_markers()

func clear_pending_markers() -> void:
	_pending_spawn_cell = null
	_pending_return_cell = null
	_refresh_pending_markers()

func _build_palette() -> void:
	for item_id in _toolbelt.get_placeable_item_ids():
		var definition := _item_catalog.get_definition(item_id)
		var button := Button.new()
		button.name = "Item_%s" % item_id
		button.custom_minimum_size = Vector2(190.0, 52.0)
		button.text = definition.display_name
		button.icon = definition.icon
		button.expand_icon = true
		button.tooltip_text = "%s\nHover and press 1-9 to assign" % definition.display_name
		button.mouse_entered.connect(_on_palette_item_hovered.bind(item_id))
		button.mouse_exited.connect(_on_palette_item_unhovered.bind(item_id))
		_palette_grid.add_child(button)

func _refresh_hotbar() -> void:
	var assignments := _toolbelt.get_assigned_item_ids()
	for index in range(CreativeToolbelt.SLOT_COUNT):
		var definition := _item_catalog.get_definition(assignments[index])
		_hotbar.present_slot(index, definition.icon, 0, false)
	_hotbar.set_selected_slot(_toolbelt.get_selected_index())

func _on_hotbar_selection_requested(slot_index: int) -> void:
	if is_ui_blocking() or not _toolbelt.try_select(slot_index):
		return
	_hotbar.set_selected_slot(slot_index)

func _on_palette_item_hovered(item_id: StringName) -> void:
	_hovered_palette_item_id = item_id

func _on_palette_item_unhovered(item_id: StringName) -> void:
	if _hovered_palette_item_id == item_id:
		_hovered_palette_item_id = &""

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_palette_open() or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var slot_index := _get_number_key_index(key_event)
	if slot_index == -1:
		return
	if not _hovered_palette_item_id.is_empty() and _toolbelt.try_assign(slot_index, _hovered_palette_item_id):
		_refresh_hotbar()
	get_viewport().set_input_as_handled()

func _get_number_key_index(event: InputEventKey) -> int:
	var number_key := event.keycode
	if number_key < KEY_1 or number_key > KEY_9:
		number_key = event.physical_keycode
	if number_key < KEY_1 or number_key > KEY_9:
		return -1
	return number_key - KEY_1

func _set_active_overlay(overlay: ActiveOverlay) -> void:
	if overlay == _active_overlay:
		return
	var was_blocking := is_ui_blocking()
	_active_overlay = overlay
	if not is_palette_open():
		_hovered_palette_item_id = &""
	_present_active_overlay()
	if was_blocking != is_ui_blocking():
		ui_blocking_changed.emit(is_ui_blocking())

func _present_active_overlay() -> void:
	_palette_overlay.visible = is_palette_open()
	_module_panel.visible = is_module_panel_open()
	_module_tools_hint.visible = _module_tools_available and _active_overlay == ActiveOverlay.NONE and not _connection_targeting and not _enemy_spawn_zone_targeting
	_connection_mode_hint.visible = _connection_targeting
	_enemy_spawn_zone_mode_hint.visible = _enemy_spawn_zone_targeting
	_hotbar.set_selection_input_enabled(not is_ui_blocking() and not _connection_targeting and not _enemy_spawn_zone_targeting)

func _on_weight_changed(value: float) -> void:
	weight_requested.emit(value)

func _on_void_pressed() -> void:
	void_requested.emit()

func _on_connection_pressed() -> void:
	close_module_panel()
	connection_targeting_requested.emit()

func _on_enemy_spawn_zone_pressed() -> void:
	close_module_panel()
	enemy_spawn_zone_targeting_requested.emit()

func _on_socket_remove_pressed(socket_id: StringName) -> void:
	socket_remove_requested.emit(socket_id)

func _on_socket_unused_fill_block_selected(item_index: int, socket_id: StringName, option: OptionButton) -> void:
	socket_unused_fill_block_requested.emit(socket_id, option.get_item_id(item_index))

func _on_enemy_spawn_zone_remove_pressed(zone_id: StringName) -> void:
	enemy_spawn_zone_remove_requested.emit(zone_id)

func _on_marker_target_pressed(role: MarkerRole, option: OptionButton) -> void:
	marker_target_requested.emit(role, option.get_selected_id() as LevelSocketDefinition.Direction)

func _on_markers_commit_pressed() -> void:
	if _pending_spawn_cell == null or _pending_return_cell == null:
		return
	markers_commit_requested.emit(
		_pending_spawn_cell as Vector3i,
		_pending_spawn_facing,
		_pending_return_cell as Vector3i,
		_pending_return_facing,
	)

func _on_markers_clear_pressed() -> void:
	clear_pending_markers()
	markers_clear_requested.emit()

func _populate_direction_options(option: OptionButton) -> void:
	for direction in LevelSocketDefinition.Direction.values():
		option.add_item(_direction_text(direction as LevelSocketDefinition.Direction), direction)

func _rebuild_socket_list(sockets: Array[LevelSocketDefinition], aperture_sizes: Dictionary) -> void:
	_clear_container(_socket_list)
	for socket in sockets:
		var aperture_size: Vector2i = aperture_sizes.get(socket.socket_id, Vector2i.ZERO)
		var row := _socket_row(socket, aperture_size)
		_socket_list.add_child(row)

func _create_enemy_spawn_zone_row(zone_id: StringName) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var remove := Button.new()
	remove.text = "Remove"
	remove.pressed.connect(_on_enemy_spawn_zone_remove_pressed.bind(zone_id))
	row.add_child(remove)
	return row

func _enemy_spawn_zone_row_text(zone: LevelEnemySpawnZone, candidate_count: int) -> String:
	return "%s  %s → %s  •  %d cells" % [
		zone.zone_id,
		_cell_text(zone.minimum_feet_cell),
		_cell_text(zone.maximum_feet_cell),
		candidate_count,
	]

func _refresh_enemy_spawn_zone_summary() -> void:
	var total_candidates := 0
	for count in _enemy_spawn_zone_candidate_counts.values():
		total_candidates += int(count)
	var zone_count := _enemy_spawn_zone_rows.size()
	if zone_count == 0:
		_enemy_spawn_zone_summary.text = "No enemy spawn zones"
	elif zone_count == 1:
		_enemy_spawn_zone_summary.text = "1 zone • %d usable cells" % total_candidates
	else:
		_enemy_spawn_zone_summary.text = "%d zones • %d usable cells" % [zone_count, total_candidates]

func _socket_row(socket: LevelSocketDefinition, aperture_size: Vector2i) -> VBoxContainer:
	var row := VBoxContainer.new()
	var heading := HBoxContainer.new()
	var label := Label.new()
	label.text = "%s  %s  %s  %d×%d" % [socket.socket_id, _cell_text(socket.cell), _direction_text(socket.direction), aperture_size.x, aperture_size.y]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(label)
	var remove := Button.new()
	remove.text = "Remove"
	remove.pressed.connect(_on_socket_remove_pressed.bind(socket.socket_id))
	heading.add_child(remove)
	row.add_child(heading)
	var unused := HBoxContainer.new()
	var unused_label := Label.new()
	unused_label.text = "If unused"
	unused_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unused.add_child(unused_label)
	var option := OptionButton.new()
	option.custom_minimum_size.x = 176.0
	_populate_unused_fill_options(option, socket.unused_fill_block_id)
	option.item_selected.connect(_on_socket_unused_fill_block_selected.bind(socket.socket_id, option))
	unused.add_child(option)
	row.add_child(unused)
	return row

func _populate_unused_fill_options(option: OptionButton, selected_block_id: int) -> void:
	option.add_item("Must connect", StructureCell.AIR)
	for item_id in _toolbelt.get_placeable_item_ids():
		var definition := _item_catalog.get_definition(item_id)
		var placement := definition.secondary_action as BlockPlacementActionDefinition
		if placement == null or placement.block == null or not StructureCell.is_structure_solid(placement.block.id):
			continue
		option.add_item(definition.display_name, placement.block.id)
	if option.get_item_index(selected_block_id) == -1 and StructureCell.is_structure_solid(selected_block_id):
		option.add_item(BlockId.get_display_name(selected_block_id), selected_block_id)
	option.select(option.get_item_index(selected_block_id))

func _clear_container(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _refresh_pending_markers() -> void:
	_spawn_pending.text = _pending_marker_text(_pending_spawn_cell, _pending_spawn_facing)
	_return_pending.text = _pending_marker_text(_pending_return_cell, _pending_return_facing)
	_marker_commit_button.disabled = _pending_spawn_cell == null or _pending_return_cell == null

func _marker_text(prefix: String, marker: LevelMarkerDefinition) -> String:
	if marker == null:
		return "%s: not set" % prefix
	return "%s: %s %s" % [prefix, _cell_text(marker.cell), _direction_text(marker.facing)]

func _pending_marker_text(cell: Variant, facing: LevelSocketDefinition.Direction) -> String:
	if cell == null:
		return "Pending: not set"
	return "Pending: %s %s" % [_cell_text(cell as Vector3i), _direction_text(facing)]

func _cell_text(cell: Vector3i) -> String:
	return "(%d, %d, %d)" % [cell.x, cell.y, cell.z]

func _direction_text(direction: LevelSocketDefinition.Direction) -> String:
	return String(LevelSocketDefinition.Direction.find_key(direction)).capitalize()

func _connection_summary_text(connection_count: int, has_start_markers: bool) -> String:
	if has_start_markers:
		if connection_count == 0:
			return "Start markers set • add a connection for generation"
		return "%d connections • eligible as a start module" % connection_count
	if connection_count == 0:
		return "No connections • not yet usable by generation"
	if connection_count == 1:
		return "1 connection • eligible as a cap or dead end"
	return "%d connections • eligible as an expansion module" % connection_count

func _all_cardinal_sides_used(sockets: Array[LevelSocketDefinition]) -> bool:
	var used_directions: Dictionary = {}
	for socket in sockets:
		used_directions[socket.direction] = true
	return used_directions.size() == LevelSocketDefinition.Direction.size()
