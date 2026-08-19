extends CanvasLayer
class_name HUD

@onready var hotbar: InventoryHotbar = $InventoryHotbar as InventoryHotbar
@onready var health_bar: PlayerHealthBar = $HealthBar as PlayerHealthBar
@onready var experience_bar: PlayerExperienceBar = $PlayerExperienceBar as PlayerExperienceBar
@onready var side_panel: SidePanel = $SidePanel as SidePanel
@onready var crafting_panel: CraftingPanel = $CraftingPanel as CraftingPanel
@onready var anvil_panel: CraftingPanel = $AnvilPanel as CraftingPanel
@onready var chest_panel: ChestPanel = $ChestPanel as ChestPanel
@onready var cauldron_panel: CraftingPanel = $CauldronPanel as CraftingPanel
@onready var player_hit_vignette: PlayerHitVignette = $PlayerHitVignette as PlayerHitVignette
@onready var interaction_prompt: Label = $InteractionPrompt as Label

var anvil_coordinator: AnvilCoordinator
var chest_coordinator: ChestCoordinator
var cauldron_coordinator: CauldronCoordinator
var _left_panel_camera_rig: CameraRig

func setup_with_camera(
	p_inventory: InventoryModel,
	p_inventory_loadout_coordinator: InventoryLoadoutCoordinator,
	p_crafting_coordinator: CraftingCoordinator,
	p_recipe_catalog: CraftingRecipeCatalog,
	cam_rig: CameraRig,
	stats: ActorStats,
	item_proficiency: ItemProficiency,
	p_chest_coordinator: ChestCoordinator = null,
):
	assert(p_inventory != null)
	assert(p_inventory_loadout_coordinator != null and p_inventory_loadout_coordinator.inventory_model == p_inventory)
	assert(stats != null and p_inventory_loadout_coordinator.actor_stats == stats)
	chest_coordinator = p_chest_coordinator
	_left_panel_camera_rig = cam_rig
	hotbar.setup(p_inventory, p_inventory_loadout_coordinator, item_proficiency)
	health_bar.setup(stats)
	experience_bar.setup(stats)
	side_panel.setup(p_inventory, p_inventory_loadout_coordinator, item_proficiency, cam_rig, hotbar, CraftingPanel.PANEL_WIDTH)
	crafting_panel.setup(p_crafting_coordinator, p_recipe_catalog)
	crafting_panel.progress_changed.connect(_on_left_panel_progress_changed)
	if p_chest_coordinator != null:
		chest_panel.setup(p_chest_coordinator, p_inventory, item_proficiency)
		p_chest_coordinator.closed.connect(_on_chest_closed)
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
	assert(_left_panel_camera_rig == cam_rig)
	anvil_panel.setup(p_crafting_coordinator, p_recipe_catalog, p_station_definition.display_name.to_upper(), false)
	anvil_panel.progress_changed.connect(_on_left_panel_progress_changed)
	anvil_coordinator.closed.connect(_on_anvil_closed)

func setup_cauldron(
	p_cauldron_coordinator: CauldronCoordinator,
	p_station_definition: CraftingStationBlockDefinition,
	p_crafting_coordinator: CraftingCoordinator,
	p_recipe_catalog: CraftingRecipeCatalog,
	cam_rig: CameraRig,
) -> void:
	assert(p_cauldron_coordinator != null and p_station_definition != null)
	cauldron_coordinator = p_cauldron_coordinator
	assert(_left_panel_camera_rig == cam_rig)
	cauldron_panel.setup(p_crafting_coordinator, p_recipe_catalog, p_station_definition.display_name.to_upper(), false)
	cauldron_panel.progress_changed.connect(_on_left_panel_progress_changed)
	cauldron_coordinator.closed.connect(_on_cauldron_closed)

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

func _on_left_panel_progress_changed(_progress: float) -> void:
	if _left_panel_camera_rig == null:
		return
	var obstruction_progress := maxf(crafting_panel.get_progress(), maxf(anvil_panel.get_progress(), cauldron_panel.get_progress()))
	_left_panel_camera_rig.set_left_panel_obstruction_progress(obstruction_progress)

func is_side_panel_open() -> bool:
	return side_panel.is_open() or side_panel.get_progress() > 0.01 or crafting_panel.get_progress() > 0.01 or anvil_panel.get_progress() > 0.01 or cauldron_panel.get_progress() > 0.01 or chest_panel.is_open()

func toggle_backpack():
	if anvil_panel.is_open():
		close_anvil()
		return
	if cauldron_panel.is_open():
		close_cauldron()
		return
	if chest_panel.is_open():
		close_chest()
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
	if cauldron_panel.is_open():
		close_cauldron()
		side_panel.open()
		crafting_panel.open()
		return
	if chest_panel.is_open():
		chest_panel.close()
		side_panel.open_inventory()
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
	cauldron_panel.close()
	if anvil_coordinator != null:
		anvil_coordinator.close()
	if cauldron_coordinator != null:
		cauldron_coordinator.close()
	chest_panel.close()
	_set_chest_transfer_context(null)

func close_side_panel_immediate():
	side_panel.close_immediate()
	crafting_panel.close_immediate()
	anvil_panel.close_immediate()
	cauldron_panel.close_immediate()
	if anvil_coordinator != null:
		anvil_coordinator.close()
	if cauldron_coordinator != null:
		cauldron_coordinator.close()
	chest_panel.close_immediate()
	_set_chest_transfer_context(null)

func open_crafting_station(position: Vector3i, definition: CraftingStationBlockDefinition) -> void:
	if definition == null:
		return
	if chest_panel.is_open():
		chest_panel.close()
		_set_chest_transfer_context(null)
	crafting_panel.close()
	match definition.id:
		&"anvil":
			if anvil_coordinator == null:
				return
			close_cauldron(false)
			if not anvil_coordinator.try_open(position, definition):
				return
			side_panel.open()
			anvil_panel.open()
		&"cauldron":
			if cauldron_coordinator == null:
				return
			close_anvil(false)
			if not cauldron_coordinator.try_open(position, definition):
				return
			side_panel.open()
			cauldron_panel.open()

func close_anvil(close_backpack: bool = true) -> void:
	if anvil_coordinator != null:
		anvil_coordinator.close()
	anvil_panel.close()
	if close_backpack:
		side_panel.close()

func close_cauldron(close_backpack: bool = true) -> void:
	if cauldron_coordinator != null:
		cauldron_coordinator.close()
	cauldron_panel.close()
	if close_backpack:
		side_panel.close()

func _on_anvil_closed() -> void:
	anvil_panel.close()

func _on_cauldron_closed() -> void:
	cauldron_panel.close()

func open_container(position: Vector3i, definition: ContainerBlockDefinition):
	if chest_coordinator == null:
		return
	if anvil_panel.is_open():
		close_anvil(false)
	if cauldron_panel.is_open():
		close_cauldron(false)
	crafting_panel.close()
	side_panel.open_inventory()
	_set_chest_transfer_context(chest_coordinator)
	if not chest_coordinator.try_open(position, definition):
		_set_chest_transfer_context(null)
		side_panel.close()

func is_chest_open() -> bool:
	return chest_panel.is_open()

func close_chest():
	chest_panel.close()
	_set_chest_transfer_context(null)
	side_panel.close()

func _on_chest_closed():
	_set_chest_transfer_context(null)

func _set_chest_transfer_context(coordinator: InventoryTransferCoordinator):
	side_panel.set_inventory_transfer_context(coordinator)
	hotbar.set_inventory_transfer_context(coordinator)

func play_player_hit():
	player_hit_vignette.play()

func show_interaction_prompt(text: String):
	interaction_prompt.text = text
	interaction_prompt.visible = true

func hide_interaction_prompt():
	interaction_prompt.visible = false
