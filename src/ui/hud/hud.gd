extends CanvasLayer
class_name HUD

@onready var hotbar: Hotbar = $Hotbar as Hotbar
@onready var side_panel: SidePanel = $SidePanel as SidePanel

func setup_with_camera(p_inventory: InventoryModel, p_inventory_stat_coordinator: InventoryStatCoordinator, cam_rig: CameraRig):
	hotbar.setup(p_inventory, p_inventory_stat_coordinator)
	side_panel.setup(p_inventory, p_inventory_stat_coordinator, cam_rig, hotbar)

func is_side_panel_open() -> bool:
	return side_panel.is_open() or side_panel.get_progress() > 0.01

func toggle_side_panel():
	side_panel.toggle()

func close_side_panel():
	side_panel.close()

func close_side_panel_immediate():
	side_panel.close_immediate()
