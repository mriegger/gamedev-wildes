extends CanvasLayer
class_name HUD

@onready var hotbar: Hotbar = $Hotbar as Hotbar

var side_panel: SidePanel = null
var _inv_model: InventoryModel = null
var inventory_model: InventoryModel:
	get:
		return _inv_model

var _camera_rig: CameraRig = null

func setup_with_camera(p_inventory: InventoryModel, cam_rig: CameraRig):
	_inv_model = p_inventory
	_camera_rig = cam_rig
	if hotbar:
		hotbar.inventory_model = p_inventory
	_ensure_side_panel()
	if side_panel:
		side_panel.setup(p_inventory, cam_rig, hotbar)

func _ready():
	if hotbar and _inv_model:
		hotbar.inventory_model = _inv_model
	_ensure_side_panel()
	if _inv_model and side_panel:
		side_panel.setup(_inv_model, _camera_rig, hotbar)

func _ensure_side_panel():
	if side_panel != null and is_instance_valid(side_panel):
		return
	var existing = get_node_or_null("SidePanel")
	if existing != null and existing is SidePanel:
		side_panel = existing as SidePanel
		return
	side_panel = SidePanel.new()
	side_panel.name = "SidePanel"
	add_child(side_panel)
	if _inv_model:
		side_panel.inventory_model = _inv_model
	if _camera_rig:
		side_panel.camera_rig = _camera_rig
		side_panel.hotbar = hotbar

func is_side_panel_open() -> bool:
	if side_panel == null:
		return false
	return side_panel.is_open() or side_panel.get_progress() > 0.01

func toggle_side_panel():
	if side_panel:
		side_panel.toggle()

func close_side_panel():
	if side_panel:
		side_panel.close()

func close_side_panel_immediate():
	if side_panel:
		side_panel.close_immediate()
