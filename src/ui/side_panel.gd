extends Control
class_name SidePanel

const PANEL_WIDTH: float = 380.0
const ANIM_DURATION: float = 0.25

# Single source of truth for tabs: id, title, icon, region, columns, placeholder
# Adding a new tab requires only one entry here.
const TAB_DEFS: Array[Dictionary] = [
	{"id": "inventory", "title": "INVENTORY", "icon": "", "icon_size": Vector2(20, 20), "region": "backpack", "cols": 5, "placeholder": ""},
	{"id": "crafting", "title": "CRAFTING", "icon": "res://assets/images/icons/button/crafting_icon.png", "icon_size": Vector2(25, 25), "region": "", "cols": 0, "placeholder": "CRAFTING — coming soon"},
	{"id": "equipment", "title": "EQUIPMENT", "icon": "res://assets/images/icons/button/equipment_icon.png", "icon_size": Vector2(20, 20), "region": "equipment", "cols": 2, "placeholder": ""},
]

var _hotbar_backing: Hotbar = null
var hotbar: Hotbar:
	get: return _hotbar_backing
	set(value):
		_hotbar_backing = value
		_update_hotbar_position(_progress)
var inventory_model: InventoryModel = null
var camera_rig: CameraRig = null

var _progress: float = 0.0
var _target_progress: float = 0.0
var _is_open: bool = false

var _background: Panel
var _content: Control
var _view_root: Control
var _title_label: Label
var _action_buttons: HBoxContainer
var _frosted_panels: Array[Panel] = []

# Generic tab storage derived from TAB_DEFS
var _views: Dictionary = {} # id -> Control
var _slot_groups: Dictionary = {} # id -> Array[InventorySlot]
var _tab_buttons: Dictionary = {} # id -> WildesButton
var _current_tab_id: String = "inventory"

# Legacy aliases for compat - populated from _slot_groups/_views
var _slots: Array[InventorySlot] = []
var _equipment_slots: Array[InventorySlot] = []
var _crafting_wrapper: WildesButton
var _equipment_wrapper: WildesButton

func _get_region_indices(region_name: String) -> Array:
	for r in InventoryModel.REGIONS:
		if r["name"] == region_name:
			var out: Array = []
			for i in range(r["size"]):
				out.append(r["start"] + i)
			return out
	return []

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = true
	_build_ui()
	_update_size()
	_update_layout(0.0)
	_apply_fade(_progress)
	_update_hotbar_position(_progress)

func setup(inv: InventoryModel, cam_rig: CameraRig, hb: Hotbar):
	inventory_model = inv
	camera_rig = cam_rig
	hotbar = hb
	if camera_rig:
		camera_rig.set_side_panel_width(PANEL_WIDTH)
	for id in _slot_groups.keys():
		for slot in _slot_groups[id] as Array:
			slot.set_inventory(inv)
	# Keep legacy arrays in sync
	for slot in _slots:
		slot.set_inventory(inv)
	for slot in _equipment_slots:
		slot.set_inventory(inv)
	_connect_inventory()
	_update_size()
	_update_layout(_progress)
	_update_hotbar_position(_progress)

func _connect_inventory():
	if inventory_model == null:
		return
	for conn in inventory_model.inventory_changed.get_connections():
		if conn["callable"].get_object() == self:
			inventory_model.inventory_changed.disconnect(conn["callable"])
	inventory_model.inventory_changed.connect(_on_inventory_changed)
	_on_inventory_changed()

func _on_inventory_changed():
	if inventory_model == null:
		return
	for id in _slot_groups.keys():
		for slot in _slot_groups[id] as Array:
			var data = inventory_model.get_slot(slot.slot_index)
			if data == null:
				slot.set_item(null, 0)
			else:
				slot.set_item(data["type"], data["count"])
	# Legacy sync
	for slot in _slots:
		var data = inventory_model.get_slot(slot.slot_index)
		if data == null:
			slot.set_item(null, 0)
		else:
			slot.set_item(data["type"], data["count"])
	for slot in _equipment_slots:
		var data = inventory_model.get_slot(slot.slot_index)
		if data == null:
			slot.set_item(null, 0)
		else:
			slot.set_item(data["type"], data["count"])

func _build_ui():
	_background = Panel.new()
	_background.name = "SidePanelBackground"
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb = WildesStyle.make_modal(0, Color(0, 0, 0, 0))
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_top = 0
	sb.border_width_bottom = 0
	sb.border_color = Color(0, 0, 0, 0)
	WildesStyle.apply_frosted_panel(_background, sb, 4.5, false)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin = MarginContainer.new()
	margin.name = "Margin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 16
	margin.offset_top = 16
	margin.offset_right = -16
	margin.offset_bottom = -16

	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_content)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.text = "INVENTORY"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_override("font", WildesStyle.BOLD_FONT)
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(0.96, 0.95, 0.9, 1))
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_title_label)

	var title_spacer = Control.new()
	title_spacer.name = "TitleSpacer"
	title_spacer.custom_minimum_size = Vector2(0, 10)
	title_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(title_spacer)

	_view_root = Control.new()
	_view_root.name = "ViewRoot"
	_view_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_view_root)

	# Build all tabs from single TAB_DEFS table
	for tab_def in TAB_DEFS:
		_build_tab_view(tab_def)
	_sync_legacy_aliases()
	_switch_to_tab_id(_current_tab_id)

	var spacer = Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(spacer)

	_action_buttons = HBoxContainer.new()
	_action_buttons.name = "ActionButtons"
	_action_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_buttons.add_theme_constant_override("separation", 8)
	_action_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_buttons.size_flags_vertical = Control.SIZE_SHRINK_END
	_content.add_child(_action_buttons)

	# Create buttons for tabs that have icons (derived from TAB_DEFS)
	for tab_def in TAB_DEFS:
		var icon_path: String = tab_def.get("icon", "")
		if icon_path == "":
			continue
		var tid: String = tab_def["id"]
		var title: String = tab_def["title"]
		var icon_size: Vector2 = tab_def.get("icon_size", Vector2(20, 20))
		var btn = _create_wildes_button(title, icon_path, icon_size)
		_tab_buttons[tid] = btn
		# Keep legacy wrappers
		if tid == "crafting":
			_crafting_wrapper = btn
		elif tid == "equipment":
			_equipment_wrapper = btn
		btn.pressed.connect(func(): _on_tab_button_pressed(tid))
		_action_buttons.add_child(btn)

	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_cache_frosted_panels()

func _on_tab_button_pressed(tid: String):
	if _current_tab_id == tid:
		_switch_to_tab_id(TAB_DEFS[0]["id"])
	else:
		_switch_to_tab_id(tid)

func _sync_legacy_aliases():
	if _slot_groups.has("inventory"):
		_slots = _slot_groups["inventory"]
	if _slot_groups.has("equipment"):
		_equipment_slots = _slot_groups["equipment"]

func _build_tab_view(tab_def: Dictionary):
	var tid: String = tab_def["id"]
	var region: String = tab_def.get("region", "")
	var title: String = tab_def.get("title", "")
	var cols: int = int(tab_def.get("cols", 5))
	var placeholder: String = tab_def.get("placeholder", "")

	var view = VBoxContainer.new()
	view.name = tid.capitalize() + "View"
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.visible = false
	_view_root.add_child(view)
	_views[tid] = view

	if region != "":
		# Slot grid tab (inventory, equipment)
		if tid == "equipment":
			var lbl = Label.new()
			lbl.text = title
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.add_theme_font_override("font", WildesStyle.BOLD_FONT)
			lbl.add_theme_font_size_override("font_size", 14)
			lbl.add_theme_color_override("font_color", Color(0.96, 0.95, 0.9, 1))
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			view.add_child(lbl)
		var grid = GridContainer.new()
		grid.name = "Grid_%s" % tid
		grid.columns = cols
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if tid == "equipment":
			grid.add_theme_constant_override("h_separation", 12)
			grid.add_theme_constant_override("v_separation", 12)
		else:
			grid.add_theme_constant_override("h_separation", 6)
			grid.add_theme_constant_override("v_separation", 6)
		view.add_child(grid)
		var slots_arr: Array[InventorySlot] = []
		_slot_groups[tid] = slots_arr
		_build_slot_grid_for_region(region, grid, slots_arr)
	else:
		var lbl = Label.new()
		lbl.text = placeholder if placeholder != "" else title + " — coming soon"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_override("font", WildesStyle.BOLD_FONT)
		lbl.add_theme_font_size_override("font_size", 14)
		if tid == "crafting":
			lbl.add_theme_color_override("font_color", Color(0.96, 0.95, 0.9, 0.7))
		else:
			lbl.add_theme_color_override("font_color", Color(0.96, 0.95, 0.9, 1))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.add_child(lbl)

func _build_slot_grid_for_region(region_name: String, grid: GridContainer, out_slots: Array[InventorySlot]):
	var indices: Array = _get_region_indices(region_name)
	for idx in indices:
		var slot = InventorySlot.new()
		slot.name = "Slot_%d" % idx
		slot.set_slot_index(idx)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		grid.add_child(slot)
		out_slots.append(slot)
		if inventory_model:
			slot.set_inventory(inventory_model)

func _switch_to_tab_id(tid: String):
	_current_tab_id = tid
	for key in _views.keys():
		var v = _views[key] as Control
		if v:
			v.visible = (key == tid)
	if _title_label:
		for tab_def in TAB_DEFS:
			if tab_def["id"] == tid:
				_title_label.text = tab_def["title"]
				break

func _create_wildes_button(text: String, icon_path: String, icon_size: Vector2 = Vector2(20, 20), font_size: int = 14) -> WildesButton:
	var scene = load("res://ui/main_menu/wildes_button.tscn") as PackedScene
	var btn = scene.instantiate() as WildesButton
	btn.name = text.capitalize() + "Button"
	btn.button_text = text
	btn.button_icon = load(icon_path) as Texture2D
	btn.button_icon_size = icon_size
	btn.button_font_size = font_size
	btn.custom_minimum_size = Vector2(0, 44)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	# Inner Button is not yet ready, defer focus disable until it exists
	btn.set_meta("_side_panel_no_focus", true)
	return btn

func _apply_state():
	_update_layout(_progress)
	_apply_fade(_progress)
	_update_camera()
	_update_hotbar_position(_progress)
	_update_hotbar_interactive()

func _process(delta):
	if abs(_progress - _target_progress) < 0.001:
		if _progress != _target_progress:
			_progress = _target_progress
			_apply_state()
		return
	var k = (3.5 / ANIM_DURATION) if ANIM_DURATION > 0.001 else 14.0
	var t = 1.0 - exp(-k * delta)
	_progress = lerp(_progress, _target_progress, t)
	if abs(_progress - _target_progress) < 0.001:
		_progress = _target_progress
	_progress = clamp(_progress, 0.0, 1.0)
	_apply_state()

func _update_size():
	var vp_size = Vector2(1280, 720)
	var vp = get_viewport()
	if vp:
		var rect = vp.get_visible_rect()
		if rect.size.x > 10 and rect.size.y > 10:
			vp_size = rect.size
	custom_minimum_size = Vector2(PANEL_WIDTH, vp_size.y)
	size = Vector2(PANEL_WIDTH, vp_size.y)

func _update_layout(progress: float):
	var vp_size = Vector2(1280, 720)
	var vp = get_viewport()
	if vp:
		var rect = vp.get_visible_rect()
		if rect.size.x > 10 and rect.size.y > 10:
			vp_size = rect.size
	position = Vector2(vp_size.x - PANEL_WIDTH * progress, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP if progress > 0.01 else Control.MOUSE_FILTER_IGNORE
	modulate = Color(1, 1, 1, 1)

func _cache_frosted_panels():
	_frosted_panels.clear()
	if _background and _background.material is ShaderMaterial:
		_frosted_panels.append(_background)
	_collect_frosted_panels(_content)

func _collect_frosted_panels(node: Node):
	if node == null:
		return
	if node is Panel and node.material is ShaderMaterial:
		_frosted_panels.append(node as Panel)
	for child in node.get_children():
		_collect_frosted_panels(child)

func _apply_fade(progress: float):
	if _background and not _frosted_panels.has(_background):
		WildesStyle.set_frosted_fade(_background, progress)
	if _content:
		_content.modulate = Color(1, 1, 1, progress)
	for panel in _frosted_panels:
		if is_instance_valid(panel):
			WildesStyle.set_frosted_fade(panel, progress)

func _set_frosted_fade_recursive(node: Node, progress: float):
	if node is Panel and node.material is ShaderMaterial:
		WildesStyle.set_frosted_fade(node as Panel, progress)
	for child in node.get_children():
		_set_frosted_fade_recursive(child, progress)

func _update_camera():
	if camera_rig:
		camera_rig.set_side_panel_progress(_progress)

func _update_hotbar_position(progress: float):
	if hotbar == null:
		return
	var shift = PANEL_WIDTH * progress * 0.5
	hotbar.offset_left = -shift
	hotbar.offset_right = -shift

func _update_hotbar_interactive():
	if hotbar == null:
		return
	var should_interact = _target_progress > 0.5 or _progress > 0.01
	hotbar.set_slots_interactive(should_interact)

func is_open() -> bool:
	return _is_open

func get_progress() -> float:
	return _progress

func toggle():
	if _is_open:
		close()
	else:
		open()

func open():
	_target_progress = 1.0
	_is_open = true
	_update_hotbar_interactive()

func close():
	_target_progress = 0.0
	_is_open = false
	_cancel_drag_if_needed()

func _cancel_drag_if_needed():
	var vp = get_viewport()
	if vp and vp.has_method("gui_is_dragging") and vp.has_method("gui_cancel_drag"):
		if vp.gui_is_dragging():
			vp.gui_cancel_drag()

func close_immediate():
	_progress = 0.0
	_target_progress = 0.0
	_is_open = false
	_update_size()
	_apply_state()
	_cancel_drag_if_needed()

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_update_size()
		_update_layout(_progress)
