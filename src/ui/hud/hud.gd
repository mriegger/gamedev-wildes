extends CanvasLayer
class_name HUD

@onready var hotbar: Hotbar = $Hotbar as Hotbar
@onready var health_bar: PlayerHealthBar = $HealthBar as PlayerHealthBar
@onready var experience_bar: PlayerExperienceBar = $PlayerExperienceBar as PlayerExperienceBar
@onready var side_panel: SidePanel = $SidePanel as SidePanel
@onready var crafting_panel: CraftingPanel = $CraftingPanel as CraftingPanel
@onready var dev_console: DevConsole = $DevConsole as DevConsole
@onready var player_hit_vignette: PlayerHitVignette = $PlayerHitVignette as PlayerHitVignette

func setup_with_camera(p_inventory: InventoryModel, p_inventory_stat_coordinator: InventoryStatCoordinator, p_crafting_coordinator: CraftingCoordinator, p_recipe_catalog: CraftingRecipeCatalog, cam_rig: CameraRig, stats: ActorStats, item_proficiency: ItemProficiency):
	hotbar.setup(p_inventory, p_inventory_stat_coordinator, item_proficiency)
	health_bar.setup(stats)
	experience_bar.setup(stats)
	side_panel.setup(p_inventory, p_inventory_stat_coordinator, item_proficiency, cam_rig, hotbar, CraftingPanel.PANEL_WIDTH)
	crafting_panel.setup(p_crafting_coordinator, p_recipe_catalog, cam_rig)
	side_panel.progress_changed.connect(_on_side_panel_progress_changed)
	_on_side_panel_progress_changed(side_panel.get_progress())

func setup_dev_console(inventory: InventoryModel, pumpkin_patch_preview: PumpkinPatchPreview) -> void:
	dev_console.setup(inventory, pumpkin_patch_preview)

func setup_socketing(
	inventory: InventoryModel,
	socketing_coordinator: RuneSocketingCoordinator,
	item_proficiency: ItemProficiency,
) -> void:
	crafting_panel.setup_socketing(inventory, socketing_coordinator, item_proficiency)

func _on_side_panel_progress_changed(progress: float):
	var right_inset := SidePanel.PANEL_WIDTH * progress
	health_bar.set_right_inset(right_inset)
	experience_bar.set_right_inset(right_inset)

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

func play_player_hit():
	player_hit_vignette.play()
