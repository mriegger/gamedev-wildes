extends InventorySlot
class_name HotbarSlot

var is_selected: bool = false
var _selected_style: StyleBoxFlat

@onready var key_label: Label = get_node_or_null("Key") as Label

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(64, 64)
	size = Vector2(64, 64)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ensure_nodes()
	set_key(slot_index + 1)
	refresh_visuals()
	set_process(false)

func _ensure_nodes():
	super._ensure_nodes()
	if key_label == null:
		key_label = get_node_or_null("Key") as Label
		if key_label == null:
			key_label = Label.new()
			key_label.name = "Key"
			key_label.position = Vector2(2, 2)
			add_child(key_label)
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_label.add_theme_font_size_override("font_size", 8)
	key_label.modulate = Color(0.7, 0.7, 0.7, 0.5)

func set_hotbar_styles(normal_style: StyleBoxFlat, selected_style: StyleBoxFlat):
	_normal_style = normal_style
	_selected_style = selected_style

func set_slot_index(idx: int):
	super.set_slot_index(idx)
	set_key(idx + 1)

func set_key(num: int):
	if key_label:
		key_label.text = str(num)
	else:
		call_deferred("_deferred_set_key", num)

func _deferred_set_key(num: int):
	if key_label:
		key_label.text = str(num)

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
	if icon == null or count_label == null:
		return
	if item_type == null or item_type == BlockId.Type.AIR or item_count <= 0:
		icon.color = Color(0, 0, 0, 0)
		count_label.text = ""
	else:
		var t = item_type
		var col = block_catalog.get_side_color(t) if BlockId.is_valid(t) else Color(1, 0, 1, 1)
		icon.color = col
		if item_count > 1:
			count_label.text = str(item_count)
		else:
			count_label.text = ""

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
