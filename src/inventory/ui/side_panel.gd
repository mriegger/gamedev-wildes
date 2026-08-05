extends Control
class_name SidePanel

const PANEL_WIDTH: float = 380.0
const ANIM_DURATION: float = 0.25
const TAB_TITLES: Dictionary = {
	"inventory": "INVENTORY",
	"equipment": "EQUIPMENT",
}

@export var block_catalog: BlockCatalog
@export var slot_scene: PackedScene

@onready var _background: Panel = $SidePanelBackground
@onready var _content: Control = $Margin/Content
@onready var _title_label: Label = $Margin/Content/Title
@onready var _inventory_view: Control = $Margin/Content/ViewRoot/InventoryView
@onready var _inventory_grid: GridContainer = $Margin/Content/ViewRoot/InventoryView/InventoryGrid
@onready var _equipment_view: Control = $Margin/Content/ViewRoot/EquipmentView
@onready var _equipment_grid: GridContainer = $Margin/Content/ViewRoot/EquipmentView/EquipmentGrid
@onready var _equipment_button: WildesButton = $Margin/Content/ActionButtons/EquipmentButton

var hotbar: Hotbar = null
var inventory_model: InventoryModel = null
var camera_rig: CameraRig = null

var _progress: float = 0.0
var _target_progress: float = 0.0
var _is_open: bool = false
var _frosted_panels: Array[Panel] = []
var _slot_normal_style: StyleBoxFlat
var _slot_empty_style: StyleBoxFlat
var _inventory_dirty: bool = true
var _views: Dictionary = {}
var _slot_groups: Dictionary = {}
var _current_tab_id: String = "inventory"

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = true
	_slot_normal_style = WildesStyle.make_panel(Color(0.16, 0.18, 0.20, 0.55), 6, Color(1, 1, 1, 0.14), 1)
	_slot_empty_style = WildesStyle.make_panel(Color(0.14, 0.16, 0.18, 0.32), 6, Color(1, 1, 1, 0.10), 1)
	_views = {
		"inventory": _inventory_view,
		"equipment": _equipment_view,
	}
	var inventory_slots: Array[InventorySlot] = []
	var equipment_slots: Array[InventorySlot] = []
	_slot_groups = {
		"inventory": inventory_slots,
		"equipment": equipment_slots,
	}
	_build_slot_grid_for_region("backpack", _inventory_grid, inventory_slots)
	_build_slot_grid_for_region("equipment", _equipment_grid, equipment_slots)
	_equipment_button.pressed.connect(_on_tab_button_pressed.bind("equipment"))
	_switch_to_tab_id(_current_tab_id)
	_update_size()
	_update_layout(0.0)
	_cache_frosted_panels()
	_apply_fade(_progress)
	_update_hotbar_position(_progress)
	set_process(false)

func setup(inv: InventoryModel, cam_rig: CameraRig, hb: Hotbar):
	inventory_model = inv
	camera_rig = cam_rig
	hotbar = hb
	if camera_rig:
		camera_rig.set_right_obstruction_width(PANEL_WIDTH)
	for id in _slot_groups.keys():
		for slot in _slot_groups[id] as Array:
			slot.set_inventory(inv)
	inventory_model.inventory_changed.connect(_on_inventory_changed)
	_inventory_dirty = true
	_update_hotbar_position(_progress)

func _on_inventory_changed():
	if _target_progress == 0.0 and _progress <= 0.01:
		_inventory_dirty = true
		return
	_refresh_inventory()

func _refresh_inventory():
	for id in _slot_groups.keys():
		for slot in _slot_groups[id] as Array:
			var data = inventory_model.get_slot(slot.slot_index)
			if data == null:
				slot.set_item(null, 0)
			else:
				slot.set_item(data["type"], data["count"])
	_inventory_dirty = false

func _build_slot_grid_for_region(region_name: String, grid: GridContainer, out_slots: Array[InventorySlot]):
	var indices: Array = InventoryModel.get_region_indices(region_name)
	for idx in indices:
		var slot := slot_scene.instantiate() as InventorySlot
		slot.name = "Slot_%d" % idx
		slot.set_slot_index(idx)
		slot.set_block_catalog(block_catalog)
		slot.set_inventory_styles(_slot_normal_style, _slot_empty_style)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		grid.add_child(slot)
		out_slots.append(slot)

func _on_tab_button_pressed(tab_id: String):
	if _current_tab_id == tab_id:
		_switch_to_tab_id("inventory")
	else:
		_switch_to_tab_id(tab_id)

func _switch_to_tab_id(tab_id: String):
	_current_tab_id = tab_id
	for id in _views.keys():
		var view = _views[id] as Control
		view.visible = id == tab_id
	_title_label.text = TAB_TITLES[tab_id]

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
		set_process(false)
		return
	var k = 3.5 / ANIM_DURATION
	var t = 1.0 - exp(-k * delta)
	_progress = lerp(_progress, _target_progress, t)
	if abs(_progress - _target_progress) < 0.001:
		_progress = _target_progress
	_progress = clamp(_progress, 0.0, 1.0)
	_apply_state()
	if _progress == _target_progress:
		set_process(false)

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
	if _background.material is ShaderMaterial:
		_frosted_panels.append(_background)
	_collect_frosted_panels(_content)

func _collect_frosted_panels(node: Node):
	if node is Panel and node.material is ShaderMaterial:
		_frosted_panels.append(node as Panel)
	for child in node.get_children():
		_collect_frosted_panels(child)

func _apply_fade(progress: float):
	_content.modulate = Color(1, 1, 1, progress)
	for panel in _frosted_panels:
		if is_instance_valid(panel):
			WildesStyle.set_frosted_fade(panel, progress)

func _update_camera():
	if camera_rig:
		camera_rig.set_right_obstruction_progress(_progress)

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

func get_inventory_slots() -> Array[InventorySlot]:
	return _slot_groups["inventory"] as Array[InventorySlot]

func toggle():
	if _is_open:
		close()
	else:
		open()

func open():
	if _inventory_dirty:
		_refresh_inventory()
	_target_progress = 1.0
	_is_open = true
	_update_hotbar_interactive()
	set_process(true)

func close():
	_target_progress = 0.0
	_is_open = false
	_cancel_drag_if_needed()
	set_process(true)

func _cancel_drag_if_needed():
	var vp = get_viewport()
	if vp and vp.gui_is_dragging():
		vp.gui_cancel_drag()

func close_immediate():
	_progress = 0.0
	_target_progress = 0.0
	_is_open = false
	_update_size()
	_apply_state()
	_cancel_drag_if_needed()
	set_process(false)

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_update_size()
		_update_layout(_progress)
