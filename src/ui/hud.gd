extends CanvasLayer
class_name HUD

@export var block_catalog: BlockCatalog

@onready var hotbar: Hotbar = $Hotbar as Hotbar

var side_panel: SidePanel = null

func setup_with_camera(p_inventory: InventoryModel, cam_rig: CameraRig):
	hotbar.setup(p_inventory)
	side_panel.setup(p_inventory, cam_rig, hotbar)

func _ready():
	side_panel = SidePanel.new()
	side_panel.name = "SidePanel"
	side_panel.block_catalog = block_catalog
	add_child(side_panel)

func is_side_panel_open() -> bool:
	return side_panel.is_open() or side_panel.get_progress() > 0.01

func toggle_side_panel():
	side_panel.toggle()

func close_side_panel():
	side_panel.close()

func close_side_panel_immediate():
	side_panel.close_immediate()
