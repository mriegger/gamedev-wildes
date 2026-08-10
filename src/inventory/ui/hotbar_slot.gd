extends InventorySlot
class_name HotbarSlot

var is_selected: bool = false
var _selected_style: StyleBoxFlat
var _left_click_candidate: bool = false
var _backpack_open: bool = false

@onready var key_label: Label = $Key

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
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

func set_backpack_open(open: bool):
	_backpack_open = open
	_left_click_candidate = false

func refresh_visuals():
	if is_selected:
		add_theme_stylebox_override("panel", _selected_style)
	else:
		add_theme_stylebox_override("panel", _normal_style)
	_refresh_item_visuals()

func _gui_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_left_click_candidate = true
		elif _left_click_candidate:
			_left_click_candidate = false
			if get_viewport().gui_is_dragging() or inventory_model == null:
				return
			var changed := false
			if _backpack_open:
				changed = inventory_model.move_hotbar_slot_to_backpack(slot_index)
			elif inventory_model.get_slot(slot_index) != null:
				changed = inventory_model.select_slot(slot_index)
			if changed:
				get_viewport().set_input_as_handled()
				return
	if _backpack_open:
		super._gui_input(event)

func _get_drag_data(at_position):
	_left_click_candidate = false
	if not _backpack_open:
		return null
	return super._get_drag_data(at_position)

func _can_drop_data(at_position, data) -> bool:
	if not _backpack_open:
		return false
	return super._can_drop_data(at_position, data)

func _drop_data(at_position, data):
	if not _backpack_open:
		return
	super._drop_data(at_position, data)

func _show_high_layer_preview(type, count: int):
	super._show_high_layer_preview(type, count)
	if _drag_preview_layer:
		_drag_preview_layer.name = "HotbarDragPreview"
