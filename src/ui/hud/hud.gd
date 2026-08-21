extends CanvasLayer
class_name HUD

const NavigationCompassType := preload("res://ui/hud/navigation_compass.gd")

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
@onready var navigation_compass: NavigationCompassType = $NavigationCompass as NavigationCompassType

var anvil_coordinator: AnvilCoordinator
var chest_coordinator: ChestTransferCoordinator
var cauldron_coordinator: CauldronCoordinator
var _left_panel_camera_rig: CameraRig
var _external_menu_open: bool = false

func setup_with_camera(
	p_inventory: InventoryModel,
	p_inventory_loadout_coordinator: InventoryLoadoutCoordinator,
	p_crafting_coordinator: CraftingCoordinator,
	p_recipe_catalog: CraftingRecipeCatalog,
	cam_rig: CameraRig,
	stats: ActorStats,
	item_proficiency: ItemProficiency,
):
	assert(p_inventory != null)
	assert(p_inventory_loadout_coordinator != null and p_inventory_loadout_coordinator.inventory_model == p_inventory)
	assert(stats != null and p_inventory_loadout_coordinator.actor_stats == stats)
	_left_panel_camera_rig = cam_rig
	hotbar.setup(p_inventory, p_inventory_loadout_coordinator, item_proficiency)
	health_bar.setup(stats)
	experience_bar.setup(stats)
	side_panel.setup(p_inventory, p_inventory_loadout_coordinator, item_proficiency, cam_rig, hotbar, CraftingPanel.PANEL_WIDTH)
	crafting_panel.setup(p_crafting_coordinator, p_recipe_catalog)
	crafting_panel.progress_changed.connect(_on_left_panel_progress_changed)
	var chest_panel_ready := chest_panel.setup(p_inventory, item_proficiency)
	assert(chest_panel_ready)
	if not chest_panel_ready:
		return
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

func setup_compass(camera: Camera3D, tracked_position: Node3D) -> void:
	navigation_compass.setup(camera, tracked_position)

func set_compass_target(position: Vector3) -> void:
	navigation_compass.set_target_position(position)

func clear_compass_target() -> void:
	navigation_compass.clear_target()

func set_compass_enemy_positions(positions: PackedVector3Array) -> void:
	navigation_compass.set_enemy_positions(positions)

func get_compass_enemy_radius() -> float:
	return navigation_compass.ENEMY_MARKER_RADIUS

func set_compass_available(available: bool) -> void:
	navigation_compass.set_available(available)

func set_compass_external_menu_open(open: bool) -> void:
	_external_menu_open = open
	_refresh_compass_menu_state()

func _on_side_panel_progress_changed(progress: float):
	var right_inset := SidePanel.PANEL_WIDTH * progress
	health_bar.set_right_inset(right_inset)
	experience_bar.set_right_inset(right_inset)
	_refresh_compass_menu_state()

func _on_left_panel_progress_changed(_progress: float) -> void:
	_refresh_compass_menu_state()
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
		return
	if cauldron_panel.is_open():
		close_cauldron()
		return
	if chest_panel.is_open():
		chest_panel.close()
		side_panel.open_inventory()
		crafting_panel.open()
		return
	if crafting_panel.is_open():
		close_side_panel()
		return
	if side_panel.is_open():
		side_panel.close()
		return
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

func open_container(coordinator: ChestTransferCoordinator, position: Vector3i, definition: ContainerBlockDefinition) -> bool:
	if coordinator == null or definition == null:
		return false
	if chest_coordinator != null:
		close_chest()
	if anvil_panel.is_open():
		close_anvil(false)
	if cauldron_panel.is_open():
		close_cauldron(false)
	crafting_panel.close()
	side_panel.open_inventory()
	if not chest_panel.bind(coordinator):
		side_panel.close()
		return false
	chest_coordinator = coordinator
	chest_coordinator.closed.connect(_on_chest_closed)
	_set_chest_transfer_context(chest_coordinator)
	if not chest_coordinator.try_open(position, definition):
		chest_coordinator.closed.disconnect(_on_chest_closed)
		chest_coordinator = null
		chest_panel.release()
		_set_chest_transfer_context(null)
		side_panel.close()
		return false
	_refresh_compass_menu_state()
	return true

func is_chest_open() -> bool:
	return chest_panel.is_open()

func close_chest():
	chest_panel.close()
	_set_chest_transfer_context(null)
	side_panel.close()

func _on_chest_closed():
	var closed_coordinator := chest_coordinator
	chest_coordinator = null
	if closed_coordinator != null and closed_coordinator.closed.is_connected(_on_chest_closed):
		closed_coordinator.closed.disconnect(_on_chest_closed)
	chest_panel.release()
	_set_chest_transfer_context(null)
	_refresh_compass_menu_state()

func _refresh_compass_menu_state() -> void:
	var panel_open := (
		side_panel.get_progress() > 0.01
		or crafting_panel.get_progress() > 0.01
		or anvil_panel.get_progress() > 0.01
		or cauldron_panel.get_progress() > 0.01
		or chest_panel.is_open()
	)
	navigation_compass.set_menu_open(_external_menu_open or panel_open)

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
