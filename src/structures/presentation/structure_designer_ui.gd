extends CanvasLayer
class_name StructureDesignerUI

signal ui_blocking_changed(blocking: bool)

var _item_catalog: ItemCatalog
var _toolbelt: CreativeToolbelt
var _palette_open: bool
var _hovered_palette_item_id: StringName

@onready var _hotbar: HotbarView = $HotbarView as HotbarView
@onready var _palette_overlay: Control = $PaletteOverlay as Control
@onready var _palette_grid: GridContainer = $PaletteOverlay/PalettePanel/Margin/VBox/Scroll/PaletteGrid as GridContainer

func _ready() -> void:
	_palette_overlay.visible = false
	_hotbar.slot_selection_requested.connect(_on_hotbar_selection_requested)

func setup(item_catalog: ItemCatalog, toolbelt: CreativeToolbelt) -> void:
	assert(is_node_ready())
	assert(item_catalog != null)
	assert(toolbelt != null)
	assert(_item_catalog == null)
	_item_catalog = item_catalog
	_toolbelt = toolbelt
	_build_palette()
	_refresh_hotbar()

func open_palette() -> void:
	if _palette_open:
		return
	_palette_open = true
	_palette_overlay.visible = true
	_hotbar.set_selection_input_enabled(false)
	ui_blocking_changed.emit(true)

func close_palette() -> void:
	if not _palette_open:
		return
	_palette_open = false
	_hovered_palette_item_id = &""
	_palette_overlay.visible = false
	_hotbar.set_selection_input_enabled(true)
	ui_blocking_changed.emit(false)

func toggle_palette() -> void:
	if _palette_open:
		close_palette()
	else:
		open_palette()

func is_palette_open() -> bool:
	return _palette_open

func is_ui_blocking() -> bool:
	return _palette_open

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
	if _palette_open or not _toolbelt.try_select(slot_index):
		return
	_hotbar.set_selected_slot(slot_index)

func _on_palette_item_hovered(item_id: StringName) -> void:
	_hovered_palette_item_id = item_id

func _on_palette_item_unhovered(item_id: StringName) -> void:
	if _hovered_palette_item_id == item_id:
		_hovered_palette_item_id = &""

func _unhandled_key_input(event: InputEvent) -> void:
	if not _palette_open or not event is InputEventKey:
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
