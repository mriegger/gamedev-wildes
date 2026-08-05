extends Panel
class_name InventorySlot

var slot_index: int = 0
var item_type = null
var item_count: int = 0
var inventory_model: InventoryModel = null
var block_catalog: BlockCatalog

var _normal_style: StyleBoxFlat
var _empty_style: StyleBoxFlat

@onready var icon: ColorRect = get_node_or_null("Color") as ColorRect
@onready var count_label: Label = get_node_or_null("Count") as Label

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(64, 64)
	size = Vector2(64, 64)
	_ensure_nodes()
	refresh_visuals()
	set_process(false)

func set_inventory(p_inv: InventoryModel):
	inventory_model = p_inv

func set_block_catalog(p_catalog: BlockCatalog):
	block_catalog = p_catalog

func set_inventory_styles(normal_style: StyleBoxFlat, empty_style: StyleBoxFlat):
	_normal_style = normal_style
	_empty_style = empty_style

func set_slot_index(idx: int):
	slot_index = idx

func set_item(type, count: int):
	if item_type == type and item_count == count:
		return
	item_type = type
	item_count = count
	refresh_visuals()

func _ensure_nodes():
	if icon == null:
		icon = get_node_or_null("Color") as ColorRect
		if icon == null:
			icon = ColorRect.new()
			icon.name = "Color"
			icon.custom_minimum_size = Vector2(36, 36)
			icon.position = Vector2(14, 8)
			icon.size = Vector2(36, 36)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(icon)
		else:
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if count_label == null:
		count_label = get_node_or_null("Count") as Label
		if count_label == null:
			count_label = Label.new()
			count_label.name = "Count"
			count_label.position = Vector2(4, 40)
			count_label.size = Vector2(56, 18)
			count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			count_label.add_theme_font_size_override("font_size", 14)
			count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(count_label)
		else:
			count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

func refresh_visuals():
	if item_type == null or item_type == BlockId.Type.AIR or item_count <= 0:
		add_theme_stylebox_override("panel", _empty_style)
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

var _drag_preview_layer: CanvasLayer = null

func _process(_delta):
	if _drag_preview_layer == null:
		set_process(false)
		return
	if not is_instance_valid(_drag_preview_layer):
		_drag_preview_layer = null
		set_process(false)
		return
	var vp = get_viewport()
	if vp == null:
		_hide_high_layer_preview()
		return
	if not vp.gui_is_dragging():
		_hide_high_layer_preview()
		return
	var panel = _drag_preview_layer.get_child(0) as Control
	if panel:
		panel.position = vp.get_mouse_position() - panel.size * 0.5

func _gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if item_type != null and item_count > 0:
				# Use model count for accurate half-split if available
				var src_type = item_type
				var src_count = item_count
				if inventory_model:
					var s = inventory_model.get_slot(slot_index)
					if s != null:
						src_type = s["type"]
						src_count = int(s["count"])
					else:
						return
				var half = int(ceil(float(src_count) / 2.0))
				var data = {"source_index": slot_index, "drag_count": half}
				_show_high_layer_preview(src_type, half)
				force_drag(data, Control.new())
				get_viewport().set_input_as_handled()
				return

func _get_drag_data(_at_position):
	if item_type == null or item_count <= 0:
		return null
	if inventory_model == null:
		return null
	var s = inventory_model.get_slot(slot_index)
	if s == null:
		return null
	var count = s["count"] as int
	var type = s["type"]
	var data = {"source_index": slot_index, "drag_count": count}
	_show_high_layer_preview(type, count)
	set_drag_preview(Control.new())
	return data

func _can_drop_data(_at_position, data) -> bool:
	if data == null or not data is Dictionary:
		return false
	if not data.has("source_index") or not data.has("drag_count"):
		return false
	if inventory_model == null:
		return false
	var src_idx = int(data.get("source_index", -1))
	var drag_count = int(data.get("drag_count", 0))
	return inventory_model.can_handle_drop(src_idx, slot_index, drag_count)

func _drop_data(_at_position, data):
	if data == null or not data is Dictionary:
		return
	if inventory_model == null:
		return
	var src_idx = int(data.get("source_index", -1))
	var drag_count = int(data.get("drag_count", 0))
	inventory_model.handle_drop(src_idx, slot_index, drag_count)

func _create_drag_preview(type, count: int) -> Control:
	var preview = Panel.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.custom_minimum_size = Vector2(64, 64)
	preview.size = Vector2(64, 64)
	preview.z_index = 100
	preview.z_as_relative = false
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.18, 0.20, 0.85)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(1, 1, 1, 0.4)
	preview.add_theme_stylebox_override("panel", sb)
	var col_rect = ColorRect.new()
	col_rect.position = Vector2(14, 8)
	col_rect.size = Vector2(36, 36)
	col_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col = block_catalog.get_side_color(type) if BlockId.is_valid(type) else Color(1, 0, 1, 1)
	col_rect.color = col
	preview.add_child(col_rect)
	if count > 1:
		var lbl = Label.new()
		lbl.text = str(count)
		lbl.position = Vector2(4, 40)
		lbl.size = Vector2(56, 18)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.add_child(lbl)
	preview.modulate = Color(1, 1, 1, 0.9)
	return preview

func _show_high_layer_preview(type, count: int):
	_hide_high_layer_preview()
	var layer = CanvasLayer.new()
	layer.layer = 100
	layer.name = "InventoryDragPreview"
	var preview = _create_drag_preview(type, count)
	preview.position = get_viewport().get_mouse_position() - preview.size * 0.5
	layer.add_child(preview)
	get_tree().root.add_child(layer)
	_drag_preview_layer = layer
	set_process(true)

func _hide_high_layer_preview():
	if _drag_preview_layer != null and is_instance_valid(_drag_preview_layer):
		_drag_preview_layer.queue_free()
	_drag_preview_layer = null
	set_process(false)

func _notification(what):
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		_hide_high_layer_preview()
