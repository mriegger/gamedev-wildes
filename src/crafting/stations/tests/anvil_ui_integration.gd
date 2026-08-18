extends SceneTree

var _frame: int = 0
var _phase: int = 0
var _failures: Array[String] = []
var _hud: HUD
var _inventory: InventoryModel
var _anvil_coordinator: AnvilCoordinator
var _anvil_crafting: CraftingCoordinator
var _general_crafting: CraftingCoordinator
var _anvil_catalog: CraftingRecipeCatalog
var _general_catalog: CraftingRecipeCatalog
var _camera_rig: CameraRig
var _camera_follow: Node3D
var _inventory_stats: InventoryStatCoordinator
var _stats: ActorStats
var _item_proficiency: ItemProficiency
var _world: VoxelWorld
var _position := Vector3i(3, 20, 4)
var _station: CraftingStationBlockDefinition

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	_general_catalog = load("res://crafting/crafting_recipe_catalog.tres") as CraftingRecipeCatalog
	_anvil_catalog = load("res://crafting/stations/anvil_recipe_catalog.tres") as CraftingRecipeCatalog
	_inventory = InventoryModel.new(item_catalog)
	_inventory.slots[0] = InventoryStack.new(&"copper", 20)
	_inventory.slots[1] = InventoryStack.new(&"log_block", 5)
	_stats = ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	_item_proficiency = ItemProficiency.new(item_catalog)
	_inventory_stats = InventoryStatCoordinator.new()
	_expect(_inventory_stats.setup(_inventory, _stats), "inventory stat setup failed")
	_general_crafting = CraftingCoordinator.new()
	_general_crafting.setup(_inventory, _general_catalog)
	_anvil_crafting = CraftingCoordinator.new()
	_anvil_crafting.setup(_inventory, _anvil_catalog)
	_world = VoxelWorld.new(20, 36, 5, 12.0, block_catalog)
	_expect(_world.try_place_block(_position, BlockId.Type.ANVIL).is_success(), "test anvil could not be placed")
	_anvil_coordinator = AnvilCoordinator.new()
	_anvil_coordinator.setup(_world)
	_station = (load("res://blocks/definitions/anvil.tres") as BlockDefinition).crafting_station
	_hud = (load("res://ui/hud/hud.tscn") as PackedScene).instantiate() as HUD
	root.add_child(_hud)
	_camera_rig = (load("res://player/camera/camera_rig.tscn") as PackedScene).instantiate() as CameraRig
	root.add_child(_camera_rig)
	_camera_follow = Node3D.new()
	root.add_child(_camera_follow)

func _process(_delta: float) -> bool:
	_frame += 1
	if _phase == 0 and _frame == 2:
		_camera_rig.setup(_camera_follow, InputBuffer.new())
		_hud.setup_with_camera(_inventory, _inventory_stats, _general_crafting, _general_catalog, _camera_rig, _stats, _item_proficiency)
		_hud.setup_anvil(_anvil_coordinator, _station, _anvil_crafting, _anvil_catalog, _camera_rig)
		_hud.open_crafting_station(_position, _station)
		_phase = 1
	elif _phase == 1 and _frame == 35:
		_expect(_hud.side_panel.is_open(), "opening the anvil did not open the backpack")
		_expect(_hud.anvil_panel.is_open() and _hud.anvil_panel.get_progress() > 0.95, "anvil panel did not open")
		_expect(not _hud.crafting_panel.is_open(), "general crafting remained open with the anvil")
		_expect(_hud.anvil_panel.get_node("Margin/Content/Title").text == _station.display_name.to_upper(), "anvil panel does not use the station display name")
		_expect(not (_hud.anvil_panel.get_node("Margin/Content/WorkspaceTabs") as Control).visible, "anvil panel exposed general crafting workspaces")
		var recipe_list := _hud.anvil_panel.get_node("Margin/Content/Body/Recipes/RecipeScroll/RecipeList") as VBoxContainer
		_expect(recipe_list.get_child_count() == 7, "anvil panel did not show seven metal recipes")
		_expect(_hud.anvil_panel.get_selected_recipe_id() == &"copper_pickaxe", "anvil did not select the first metal recipe")
		_expect(_hud.anvil_panel.get_craft_button().is_craft_enabled(), "available anvil recipe was disabled")
		_hud.anvil_panel.get_craft_button().pressed.emit()
		_expect(_inventory.get_inventory_item_count(&"copper_pickaxe") == 1, "anvil did not craft the copper pickaxe")
		_expect(_inventory.get_inventory_item_count(&"copper") == 10 and _inventory.get_inventory_item_count(&"log_block") == 0, "anvil craft consumed the wrong ingredients")
		var mined := _world.try_mine_block(_position)
		_expect(not mined.is_empty() and (mined[0] as BlockEdit).is_success(), "open test anvil could not be mined")
		_expect(not _hud.anvil_panel.is_open(), "mining the active anvil left its crafting panel usable")
		_expect(_hud.side_panel.is_open(), "mining the active anvil unexpectedly closed the backpack")
		_expect(_world.try_place_block(_position, BlockId.Type.ANVIL).is_success(), "test anvil could not be restored")
		_hud.toggle_backpack()
		_phase = 2
	elif _phase == 2 and _frame == 68:
		_expect(not _hud.anvil_panel.is_open() and not _hud.side_panel.is_open(), "P did not close the anvil and backpack")
		_hud.open_crafting_station(_position, _station)
		_hud.toggle_crafting()
		_phase = 3
	elif _phase == 3 and _frame == 101:
		_expect(not _hud.anvil_panel.is_open(), "Tab did not close the anvil")
		_expect(_hud.crafting_panel.is_open() and _hud.side_panel.is_open(), "Tab did not open general crafting and the backpack")
		var general_recipe_list := _hud.crafting_panel.get_node("Margin/Content/Body/Recipes/RecipeScroll/RecipeList") as VBoxContainer
		_expect(general_recipe_list.get_child_count() == 5, "general crafting contains metal recipes or is missing the chest recipe")
		_hud.free()
		_camera_rig.free()
		_camera_follow.free()
		_phase = 4
	elif _phase == 4 and _frame == 110:
		_finish()
	return false

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("ANVIL_UI PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("[anvil_ui] %s" % failure)
	quit(1)
