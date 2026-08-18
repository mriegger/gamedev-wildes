extends ItemSlotView
class_name InventorySlot

var item_id = null
var inventory_model: InventoryModel = null
var inventory_stat_coordinator: InventoryStatCoordinator = null
var item_proficiency: ItemProficiency = null
var item_consumption: ItemConsumptionCoordinator = null
var empty_label: String = ""

@export var item_tooltip_scene: PackedScene

var _inventory_normal_style: StyleBoxFlat
var _inventory_empty_style: StyleBoxFlat

func _ready():
	super._ready()
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

func set_item_consumption(consumption: ItemConsumptionCoordinator) -> void:
	assert(consumption != null)
	item_consumption = consumption

func _try_handle_consumption_input(event: InputEvent) -> bool:
	if item_consumption == null or not event is InputEventMouseButton:
		return false
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_RIGHT or not item_consumption.has_consumable_at(slot_index):
		return false
	item_consumption.try_consume_at(slot_index)
	get_viewport().set_input_as_handled()
	return true

func set_inventory_styles(normal_style: StyleBoxFlat, empty_style: StyleBoxFlat):
	_inventory_normal_style = normal_style
	_inventory_empty_style = empty_style

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
	var definition := _get_tooltip_definition()
	tooltip_text = definition.display_name if definition != null else ""

func _make_custom_tooltip(_for_text: String) -> Object:
	var definition := _get_tooltip_definition()
	if tooltip_text.is_empty() or definition == null:
		return null
	assert(item_tooltip_scene != null)
	var tooltip := item_tooltip_scene.instantiate() as ItemTooltip
	assert(tooltip != null)
	tooltip.setup(
		definition,
		item_proficiency,
		inventory_model.item_catalog,
		inventory_model.get_socketed_rune_ids(slot_index),
	)
	return tooltip

func _get_tooltip_definition() -> ItemDefinition:
	if item_id == null or item_count <= 0 or inventory_model == null or item_proficiency == null:
		return null
	var catalog := inventory_model.item_catalog
	var definition := catalog.get_definition(item_id)
	if definition is RuneDefinition:
		return definition
	if not catalog.is_combat_item(item_id):
		return null
	if definition.rarity == null or definition.proficiency == null or not item_proficiency.has_proficiency(item_id):
		return null
	return definition

func refresh_visuals():
	var visual_count := _get_visual_count()
	var style: StyleBox = _selected_style if is_selected else _inventory_normal_style
	if not is_selected and (item_id == null or visual_count <= 0):
		style = _inventory_empty_style
	if style == null:
		style = _normal_style
	if style != null:
		add_theme_stylebox_override("panel", style)
	_refresh_item_visuals()

func _refresh_item_visuals():
	var visual_item_id = _drag_source_item_id if not _active_drag_data.is_empty() else item_id
	var visual_count := _get_visual_count()
	if visual_item_id == null or visual_count <= 0:
		icon.texture = null
		count_label.text = empty_label
	else:
		icon.texture = inventory_model.item_catalog.get_definition(visual_item_id).icon
		if _count_visible and visual_count > 1:
			count_label.text = str(visual_count)
		else:
			count_label.text = ""

var _drag_preview_layer: CanvasLayer = null
var _active_drag_data: Dictionary = {}
var _drag_source_item_id = null
var _drag_source_count: int = 0

func _get_visual_count() -> int:
	if _active_drag_data.is_empty():
		return item_count
	return _drag_source_count - int(_active_drag_data.get("drag_count", 0))

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
	if _try_handle_consumption_input(event):
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click and inventory_stat_coordinator != null:
			var changed := inventory_stat_coordinator.try_unequip_armor(slot_index) if InventoryModel.is_equipment_index(slot_index) else inventory_stat_coordinator.try_equip_armor(slot_index)
			if changed:
				get_viewport().set_input_as_handled()
			return

func _input(event: InputEvent) -> void:
	if _active_drag_data.is_empty() or not get_viewport().gui_is_dragging():
		return
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return
	var drag_count := int(_active_drag_data.get("drag_count", 0))
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		drag_count = maxi(1, drag_count - 1)
	else:
		drag_count = mini(_drag_source_count, drag_count + 1)
	_set_drag_count(drag_count)
	get_viewport().set_input_as_handled()

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
	_active_drag_data = data
	_drag_source_item_id = source_item_id
	_drag_source_count = count
	_show_high_layer_preview(source_item_id, count)
	refresh_visuals()
	set_process_input(true)
	set_drag_preview(Control.new())
	return data

func _set_drag_count(count: int) -> void:
	if _active_drag_data.is_empty():
		return
	_active_drag_data["drag_count"] = clampi(count, 1, _drag_source_count)
	_update_high_layer_preview_count(int(_active_drag_data["drag_count"]))
	refresh_visuals()

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
	var lbl = Label.new()
	lbl.name = "Count"
	lbl.text = str(count) if count > 1 else ""
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

func _update_high_layer_preview_count(count: int) -> void:
	if _drag_preview_layer == null or not is_instance_valid(_drag_preview_layer) or _drag_preview_layer.get_child_count() == 0:
		return
	var panel := _drag_preview_layer.get_child(0) as Control
	var label := panel.get_node_or_null("Count") as Label
	if label != null:
		label.text = str(count) if count > 1 else ""

func _hide_high_layer_preview():
	if _drag_preview_layer != null and is_instance_valid(_drag_preview_layer):
		_drag_preview_layer.queue_free()
	_drag_preview_layer = null
	set_process(false)

func _notification(what):
	if what == NOTIFICATION_DRAG_END:
		_active_drag_data.clear()
		_drag_source_item_id = null
		_drag_source_count = 0
		set_process_input(false)
		_hide_high_layer_preview()
		if is_node_ready():
			refresh_visuals()
	elif what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		set_process_input(false)
		_hide_high_layer_preview()
