extends Panel
class_name InventorySlot

var slot_index: int = 0
var item_id = null
var item_count: int = 0
var inventory_model: InventoryModel = null
var inventory_stat_coordinator: InventoryStatCoordinator = null
var item_proficiency: ItemProficiency = null
var empty_label: String = ""

@export var gear_tooltip_scene: PackedScene

var _normal_style: StyleBoxFlat
var _empty_style: StyleBoxFlat

@onready var icon: TextureRect = $Icon
@onready var count_label: Label = $Count

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	if not empty_label.is_empty():
		count_label.add_theme_font_size_override("font_size", 10)
	refresh_visuals()
	set_process(false)

func set_inventory(p_inv: InventoryModel):
	inventory_model = p_inv

func set_inventory_stat_coordinator(coordinator: InventoryStatCoordinator):
	inventory_stat_coordinator = coordinator

func set_item_proficiency(proficiency: ItemProficiency):
	item_proficiency = proficiency
	_update_tooltip_text()

func set_inventory_styles(normal_style: StyleBoxFlat, empty_style: StyleBoxFlat):
	_normal_style = normal_style
	_empty_style = empty_style

func set_slot_index(idx: int):
	slot_index = idx

func set_empty_label(label: String):
	empty_label = label
	_update_tooltip_text()
	if is_node_ready():
		refresh_visuals()

func set_item(p_item_id, count: int):
	if item_id == p_item_id and item_count == count:
		return
	item_id = p_item_id
	item_count = count
	_update_tooltip_text()
	refresh_visuals()

func _update_tooltip_text() -> void:
	if item_id == null or item_count <= 0:
		tooltip_text = empty_label
		return
	if inventory_model == null or item_proficiency == null:
		tooltip_text = ""
		return
	var definition := _get_gear_tooltip_definition()
	tooltip_text = definition.display_name if definition != null else ""

func _make_custom_tooltip(_for_text: String) -> Object:
	var definition := _get_gear_tooltip_definition()
	if tooltip_text.is_empty() or definition == null:
		return null
	assert(gear_tooltip_scene != null)
	var tooltip := gear_tooltip_scene.instantiate() as GearTooltip
	assert(tooltip != null)
	tooltip.setup(definition, item_proficiency)
	return tooltip

func _get_gear_tooltip_definition() -> ItemDefinition:
	if item_id == null or item_count <= 0 or inventory_model == null or item_proficiency == null:
		return null
	var catalog := inventory_model.item_catalog
	if not catalog.is_combat_item(item_id):
		return null
	var definition := catalog.get_definition(item_id)
	if definition.rarity == null or definition.proficiency == null or not item_proficiency.has_proficiency(item_id):
		return null
	return definition

func refresh_visuals():
	if item_id == null or item_count <= 0:
		add_theme_stylebox_override("panel", _empty_style)
	else:
		add_theme_stylebox_override("panel", _normal_style)
	_refresh_item_visuals()

func _refresh_item_visuals():
	if item_id == null or item_count <= 0:
		icon.texture = null
		count_label.text = empty_label
	else:
		icon.texture = inventory_model.item_catalog.get_definition(item_id).icon
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
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click and inventory_stat_coordinator != null:
			var changed := inventory_stat_coordinator.try_unequip_armor(slot_index) if InventoryModel.is_equipment_index(slot_index) else inventory_stat_coordinator.try_equip_armor(slot_index)
			if changed:
				get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if item_id != null and item_count > 0:
				var src_item_id = item_id
				var src_count = item_count
				if inventory_model:
					var s = inventory_model.get_slot(slot_index)
					if s != null:
						src_item_id = s.item_id
						src_count = s.count
					else:
						return
				var half = int(ceil(float(src_count) / 2.0))
				var data = {"source_index": slot_index, "drag_count": half}
				_show_high_layer_preview(src_item_id, half)
				force_drag(data, Control.new())
				get_viewport().set_input_as_handled()
				return

func _get_drag_data(_at_position):
	if item_id == null or item_count <= 0:
		return null
	if inventory_model == null:
		return null
	var s: InventoryStack = inventory_model.get_slot(slot_index)
	if s == null:
		return null
	var count: int = s.count
	var source_item_id: StringName = s.item_id
	var data = {"source_index": slot_index, "drag_count": count}
	_show_high_layer_preview(source_item_id, count)
	set_drag_preview(Control.new())
	return data

func _can_drop_data(_at_position, data) -> bool:
	if data == null or not data is Dictionary:
		return false
	if not data.has("source_index") or not data.has("drag_count"):
		return false
	if inventory_model == null or inventory_stat_coordinator == null:
		return false
	var src_idx = int(data.get("source_index", -1))
	var drag_count = int(data.get("drag_count", 0))
	return inventory_stat_coordinator.can_handle_drop(src_idx, slot_index, drag_count)

func _drop_data(_at_position, data):
	if data == null or not data is Dictionary:
		return
	if inventory_model == null or inventory_stat_coordinator == null:
		return
	var src_idx = int(data.get("source_index", -1))
	var drag_count = int(data.get("drag_count", 0))
	inventory_stat_coordinator.handle_drop(src_idx, slot_index, drag_count)

func _create_drag_preview(source_item_id: StringName, count: int) -> Control:
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
	var preview_icon := TextureRect.new()
	preview_icon.name = "Icon"
	preview_icon.position = Vector2(8, 4)
	preview_icon.size = Vector2(48, 48)
	preview_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_icon.texture = inventory_model.item_catalog.get_definition(source_item_id).icon
	preview.add_child(preview_icon)
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

func _show_high_layer_preview(source_item_id: StringName, count: int):
	_hide_high_layer_preview()
	var layer = CanvasLayer.new()
	layer.layer = 100
	layer.name = "InventoryDragPreview"
	var preview = _create_drag_preview(source_item_id, count)
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
