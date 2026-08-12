extends CanvasLayer
class_name HUD

@onready var hotbar: Hotbar = $Hotbar as Hotbar
@onready var health_bar: PlayerHealthBar = $HealthBar as PlayerHealthBar
@onready var side_panel: SidePanel = $SidePanel as SidePanel
@onready var crafting_panel: CraftingPanel = $CraftingPanel as CraftingPanel
@onready var dev_console: DevConsole = $DevConsole as DevConsole

func setup_with_camera(p_inventory: InventoryModel, p_inventory_stat_coordinator: InventoryStatCoordinator, p_crafting_coordinator: CraftingCoordinator, p_recipe_catalog: CraftingRecipeCatalog, cam_rig: CameraRig, stats: ActorStats):
	hotbar.setup(p_inventory, p_inventory_stat_coordinator)
	health_bar.setup(stats)
	side_panel.setup(p_inventory, p_inventory_stat_coordinator, cam_rig, hotbar, CraftingPanel.PANEL_WIDTH)
	crafting_panel.setup(p_crafting_coordinator, p_recipe_catalog, cam_rig)
	dev_console.setup(p_inventory)

func is_side_panel_open() -> bool:
	return side_panel.is_open() or side_panel.get_progress() > 0.01 or crafting_panel.get_progress() > 0.01

func toggle_backpack():
	if crafting_panel.is_open():
		crafting_panel.close()
		if not side_panel.is_open():
			side_panel.open()
	elif side_panel.is_open():
		side_panel.close()
	else:
		side_panel.open()

func toggle_crafting():
	if crafting_panel.is_open():
		close_side_panel()
	else:
		side_panel.open()
		crafting_panel.open()

func close_side_panel():
	side_panel.close()
	crafting_panel.close()

func close_side_panel_immediate():
	side_panel.close_immediate()
	crafting_panel.close_immediate()
