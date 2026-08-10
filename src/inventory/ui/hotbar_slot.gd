extends InventorySlot
class_name HotbarSlot

var is_selected: bool = false
var _selected_style: StyleBoxFlat

@onready var key_label: Label = $Key

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	key_label.text = str(slot_index + 1)
	refresh_visuals()
	set_process(false)

func set_hotbar_styles(normal_style: StyleBoxFlat, selected_style: StyleBoxFlat):
	_normal_style = normal_style
	_selected_style = selected_style

func set_slot_index(idx: int):
	super.set_slot_index(idx)
	if is_node_ready():
		key_label.text = str(idx + 1)

func set_selected(selected: bool):
	if is_selected == selected:
		return
	is_selected = selected
	refresh_visuals()

func set_mouse_interactive(enabled: bool):
	mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE

func refresh_visuals():
	if is_selected:
		add_theme_stylebox_override("panel", _selected_style)
	else:
		add_theme_stylebox_override("panel", _normal_style)
	_refresh_item_visuals()

func _gui_input(event):
	if mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return
	super._gui_input(event)

func _get_drag_data(at_position):
	if mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return null
	return super._get_drag_data(at_position)

func _can_drop_data(at_position, data) -> bool:
	if mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return false
	return super._can_drop_data(at_position, data)

func _drop_data(at_position, data):
	if mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return
	super._drop_data(at_position, data)

func _show_high_layer_preview(type, count: int):
	super._show_high_layer_preview(type, count)
	if _drag_preview_layer:
		_drag_preview_layer.name = "HotbarDragPreview"
