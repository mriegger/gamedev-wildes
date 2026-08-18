extends CanvasLayer
class_name HUD

@onready var hotbar: InventoryHotbar = $InventoryHotbar as InventoryHotbar
@onready var health_bar: PlayerHealthBar = $HealthBar as PlayerHealthBar
@onready var experience_bar: PlayerExperienceBar = $PlayerExperienceBar as PlayerExperienceBar
@onready var side_panel: SidePanel = $SidePanel as SidePanel
@onready var crafting_panel: CraftingPanel = $CraftingPanel as CraftingPanel
@onready var anvil_panel: CraftingPanel = $AnvilPanel as CraftingPanel
@onready var player_hit_vignette: PlayerHitVignette = $PlayerHitVignette as PlayerHitVignette
@onready var interaction_prompt: Label = $InteractionPrompt as Label

var anvil_coordinator: AnvilCoordinator

func setup_with_camera(p_inventory: InventoryModel, p_inventory_stat_coordinator: InventoryStatCoordinator, p_crafting_coordinator: CraftingCoordinator, p_recipe_catalog: CraftingRecipeCatalog, cam_rig: CameraRig, stats: ActorStats, item_proficiency: ItemProficiency):
	hotbar.setup(p_inventory, p_inventory_stat_coordinator, item_proficiency)
	health_bar.setup(stats)
	experience_bar.setup(stats)
	side_panel.setup(p_inventory, p_inventory_stat_coordinator, item_proficiency, cam_rig, hotbar, CraftingPanel.PANEL_WIDTH)
	crafting_panel.setup(p_crafting_coordinator, p_recipe_catalog, cam_rig)
	side_panel.progress_changed.connect(_on_side_panel_progress_changed)
	_on_side_panel_progress_changed(side_panel.get_progress())

func setup_anvil(
	p_anvil_coordinator: AnvilCoordinator,
	p_station_definition: CraftingStationBlockDefinition,
	p_crafting_coordinator: CraftingCoordinator,
	p_recipe_catalog: CraftingRecipeCatalog,
	cam_rig: CameraRig,
) -> void:
	assert(p_anvil_coordinator != null and p_station_definition != null)
	anvil_coordinator = p_anvil_coordinator
	anvil_panel.setup(p_crafting_coordinator, p_recipe_catalog, cam_rig, p_station_definition.display_name.to_upper(), false)
	anvil_coordinator.closed.connect(_on_anvil_closed)

func setup_socketing(
	inventory: InventoryModel,
	socketing_coordinator: RuneSocketingCoordinator,
	item_proficiency: ItemProficiency,
) -> void:
	crafting_panel.setup_socketing(inventory, socketing_coordinator, item_proficiency)

func setup_progression(actor_stats: ActorStats, perk_coordinator: PlayerPerkCoordinator) -> void:
	crafting_panel.setup_progression(actor_stats, perk_coordinator)

func setup_consumption(consumption: ItemConsumptionCoordinator) -> void:
	hotbar.setup_consumption(consumption)
	side_panel.setup_consumption(consumption)

func _on_side_panel_progress_changed(progress: float):
	var right_inset := SidePanel.PANEL_WIDTH * progress
	health_bar.set_right_inset(right_inset)
	experience_bar.set_right_inset(right_inset)

func is_side_panel_open() -> bool:
	return side_panel.is_open() or side_panel.get_progress() > 0.01 or crafting_panel.get_progress() > 0.01 or anvil_panel.get_progress() > 0.01

func toggle_backpack():
	if anvil_panel.is_open():
		close_anvil()
		return
	if crafting_panel.is_open():
		crafting_panel.close()
		if not side_panel.is_open():
			side_panel.open()
	elif side_panel.is_open():
		side_panel.close()
	else:
		side_panel.open()

func toggle_crafting():
	if anvil_panel.is_open():
		close_anvil()
		side_panel.open()
		crafting_panel.open()
		return
	if crafting_panel.is_open():
		close_side_panel()
	else:
		side_panel.open()
		crafting_panel.open()

func close_side_panel():
	side_panel.close()
	crafting_panel.close()
	anvil_panel.close()
	if anvil_coordinator != null:
		anvil_coordinator.close()

func close_side_panel_immediate():
	side_panel.close_immediate()
	crafting_panel.close_immediate()
	anvil_panel.close_immediate()
	if anvil_coordinator != null:
		anvil_coordinator.close()

func open_crafting_station(position: Vector3i, definition: CraftingStationBlockDefinition) -> void:
	if anvil_coordinator == null or definition == null or definition.id != &"anvil":
		return
	crafting_panel.close()
	if not anvil_coordinator.try_open(position, definition):
		return
	side_panel.open()
	anvil_panel.open()

func close_anvil() -> void:
	if anvil_coordinator != null:
		anvil_coordinator.close()
	anvil_panel.close()
	side_panel.close()

func _on_anvil_closed() -> void:
	anvil_panel.close()

func play_player_hit():
	player_hit_vignette.play()

func show_interaction_prompt(text: String):
	interaction_prompt.text = text
	interaction_prompt.visible = true

func hide_interaction_prompt():
	interaction_prompt.visible = false
