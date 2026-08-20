extends SceneTree

var _frame: int = 0
var _phase: int = 0
var _failures: Array[String] = []
var _hud: HUD
var _inventory: InventoryModel
var _anvil_coordinator: AnvilCoordinator
var _cauldron_coordinator: CauldronCoordinator
var _anvil_crafting: CraftingCoordinator
var _cauldron_crafting: CraftingCoordinator
var _general_crafting: CraftingCoordinator
var _anvil_catalog: CraftingRecipeCatalog
var _cauldron_catalog: CraftingRecipeCatalog
var _general_catalog: CraftingRecipeCatalog
var _camera_rig: CameraRig
var _camera_follow: Node3D
var _inventory_loadout: InventoryLoadoutCoordinator
var _stats: ActorStats
var _item_proficiency: ItemProficiency
var _world: VoxelWorld
var _position := Vector3i(3, 20, 4)
var _cauldron_position := Vector3i(5, 20, 4)
var _station: CraftingStationBlockDefinition
var _cauldron_station: CraftingStationBlockDefinition

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	_general_catalog = load("res://crafting/crafting_recipe_catalog.tres") as CraftingRecipeCatalog
	_anvil_catalog = load("res://crafting/stations/anvil_recipe_catalog.tres") as CraftingRecipeCatalog
	_cauldron_catalog = load("res://crafting/stations/cauldron_recipe_catalog.tres") as CraftingRecipeCatalog
	_inventory = InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	InventoryTestFixture.restore_slots(_inventory, {
		0: InventoryStack.new(&"copper", 20),
		1: InventoryStack.new(&"log_block", 5),
		2: InventoryStack.new(&"pumpkin", 2),
		3: InventoryStack.new(&"apple", 2),
	})
	_stats = ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	_item_proficiency = ItemProficiency.new(item_catalog)
	_inventory_loadout = InventoryLoadoutCoordinator.new()
	_expect(_inventory_loadout.setup(_inventory, _stats, _item_proficiency), "inventory loadout setup failed")
	_general_crafting = CraftingCoordinator.new()
	_general_crafting.setup(_inventory, _inventory_loadout, _general_catalog)
	_anvil_crafting = CraftingCoordinator.new()
	_anvil_crafting.setup(_inventory, _inventory_loadout, _anvil_catalog)
	_cauldron_crafting = CraftingCoordinator.new()
	_cauldron_crafting.setup(_inventory, _inventory_loadout, _cauldron_catalog)
	_world = VoxelWorld.new(20, 36, 5, 12.0, block_catalog)
	_expect(VoxelWorldTestFixture.commit_place(_world, _position, BlockId.Type.ANVIL) != null, "test anvil could not be placed")
	_expect(VoxelWorldTestFixture.commit_place(_world, _cauldron_position, BlockId.Type.CAULDRON) != null, "test cauldron could not be placed")
	_anvil_coordinator = AnvilCoordinator.new()
	_anvil_coordinator.setup(_world)
	_cauldron_coordinator = CauldronCoordinator.new()
	_cauldron_coordinator.setup(_world)
	_station = (load("res://blocks/definitions/anvil.tres") as BlockDefinition).crafting_station
	_cauldron_station = (load("res://blocks/definitions/cauldron.tres") as BlockDefinition).crafting_station
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
		_hud.setup_with_camera(_inventory, _inventory_loadout, _general_crafting, _general_catalog, _camera_rig, _stats, _item_proficiency)
		_hud.setup_anvil(_anvil_coordinator, _station, _anvil_crafting, _anvil_catalog, _camera_rig)
		_hud.setup_cauldron(_cauldron_coordinator, _cauldron_station, _cauldron_crafting, _cauldron_catalog, _camera_rig)
		_hud.open_crafting_station(_position, _station)
		_phase = 1
	elif _phase == 1 and _frame == 35:
		_expect(_hud.side_panel.is_open(), "opening the anvil did not open the backpack")
		_expect(_hud.anvil_panel.is_open() and _hud.anvil_panel.get_progress() > 0.95, "anvil panel did not open")
		_expect(not _hud.crafting_panel.is_open(), "general crafting remained open with the anvil")
		_expect(_hud.anvil_panel.get_node("Margin/Content/Title").text == _station.display_name.to_upper(), "anvil panel does not use the station display name")
		_expect(not (_hud.anvil_panel.get_node("Margin/Content/WorkspaceTabs") as Control).visible, "anvil panel exposed general crafting workspaces")
		var recipe_list := _hud.anvil_panel.get_node("Margin/Content/Body/Recipes/RecipeScroll/RecipeList") as VBoxContainer
		_expect(recipe_list.get_child_count() == 9, "anvil panel did not show all nine metal recipes")
		_expect(_hud.anvil_panel.get_selected_recipe_id() == &"copper_pickaxe", "anvil did not select the first metal recipe")
		var stats_heading := _hud.anvil_panel.get_node("Margin/Content/Body/Details/StatsHeading") as Label
		var stats_label := _hud.anvil_panel.get_node("Margin/Content/Body/Details/Stats") as RichTextLabel
		_expect(stats_label.has_theme_font_override(&"bold_font") and stats_label.size_flags_vertical == Control.SIZE_SHRINK_CENTER and stats_label.get_theme_font_size(&"bold_font_size") == 13 and stats_label.get_theme_constant(&"line_separation") == 3, "crafting stats no longer use the compact card layout")
		_expect(stats_heading.visible and stats_label.visible, "copper pickaxe recipe did not display mining stats")
		_expect(stats_label.get_parsed_text().contains("Mining Power: 2") and stats_label.get_parsed_text().contains("Speed Multiplier: 2x"), "copper pickaxe recipe stats are incomplete")
		_hud.anvil_panel.select_recipe(&"copper_sword")
		_expect(stats_heading.visible and stats_label.visible, "sword recipe did not display weapon stats")
		for expected_stat in ["Slash: 10 (8–10)", "Reach: 2.5", "Cooldown: 0.48s", "Sweep: 120°", "Knockback: 0"]:
			_expect(stats_label.get_parsed_text().contains(expected_stat), "sword recipe stats are missing %s" % expected_stat)
		_expect(not stats_label.get_parsed_text().contains("Base Damage"), "sword recipe still labels damage as base damage")
		_expect(stats_label.text.contains(CombatPresentationPalette.WEAK_DAMAGE_COLOR.to_html(false)), "sword recipe numbers are not yellow-gold")
		_expect(stats_label.text.contains("[b][color=#%s]0.48s[/color][/b]" % CombatPresentationPalette.WEAK_DAMAGE_COLOR.to_html(false)), "sword recipe cooldown number and unit are not highlighted and bold")
		_expect(stats_label.text.contains("[b][color=#%s]120°[/color][/b]" % CombatPresentationPalette.WEAK_DAMAGE_COLOR.to_html(false)), "sword recipe sweep number and unit are not highlighted and bold")
		_hud.anvil_panel.select_recipe(&"copper_hammer")
		for expected_stat in ["Blunt: 15 (5–15)", "Reach: 4", "Cooldown: 1.65s", "Sweep: 360°", "Knockback: 8"]:
			_expect(stats_label.get_parsed_text().contains(expected_stat), "hammer recipe stats are missing %s" % expected_stat)
		_hud.anvil_panel.select_recipe(&"copper_arrow_bundle")
		_expect(stats_heading.visible and stats_label.visible and stats_label.get_parsed_text().contains("Pierce: 12") and stats_label.get_parsed_text().contains("Knockback: 2"), "copper arrow recipe did not display its combat stats")
		_hud.anvil_panel.select_recipe(&"copper_helmet")
		_expect(stats_heading.visible and stats_label.visible, "armor recipe did not display item stats")
		_expect(stats_label.get_parsed_text().contains("Slot: Head") and stats_label.get_parsed_text().contains("Defense: +1"), "helmet recipe stats are incomplete")
		_expect(stats_label.text.contains(CombatPresentationPalette.WEAK_DAMAGE_COLOR.to_html(false)), "helmet recipe defense is not yellow-gold")
		_hud.anvil_panel.select_recipe(&"copper_pickaxe")
		_expect(_hud.anvil_panel.get_craft_button().is_craft_enabled(), "available anvil recipe was disabled")
		_hud.anvil_panel.get_craft_button().pressed.emit()
		_expect(_inventory.get_inventory_item_count(&"copper_pickaxe") == 1, "anvil did not craft the copper pickaxe")
		_expect(_inventory.get_inventory_item_count(&"copper") == 10 and _inventory.get_inventory_item_count(&"log_block") == 0, "anvil craft consumed the wrong ingredients")
		var mined := VoxelWorldTestFixture.commit_mine(_world, _position)
		_expect(mined != null and not mined.get_edits().is_empty(), "open test anvil could not be mined")
		_expect(not _hud.anvil_panel.is_open(), "mining the active anvil left its crafting panel usable")
		_expect(_hud.side_panel.is_open(), "mining the active anvil unexpectedly closed the backpack")
		_expect(VoxelWorldTestFixture.commit_place(_world, _position, BlockId.Type.ANVIL) != null, "test anvil could not be restored")
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
		_expect(general_recipe_list.get_child_count() == 8, "general crafting contains metal recipes or is missing a recipe")
		_hud.crafting_panel.select_recipe(&"stone_pickaxe")
		var general_stats := _hud.crafting_panel.get_node("Margin/Content/Body/Details/Stats") as RichTextLabel
		_expect(general_stats.visible and general_stats.get_parsed_text().contains("Mining Power: 1") and general_stats.get_parsed_text().contains("Speed Multiplier: 1.5x"), "stone pickaxe recipe stats are incomplete")
		_hud.open_crafting_station(_cauldron_position, _cauldron_station)
		_phase = 4
	elif _phase == 4 and _frame == 134:
		_expect(_hud.side_panel.is_open(), "opening the cauldron did not keep the backpack open")
		_expect(_hud.cauldron_panel.is_open() and _hud.cauldron_panel.get_progress() > 0.95, "cauldron panel did not open")
		_expect(not _hud.anvil_panel.is_open() and not _hud.crafting_panel.is_open(), "another crafting panel remained open with the cauldron")
		_expect(_hud.cauldron_panel.get_node("Margin/Content/Title").text == _cauldron_station.display_name.to_upper(), "cauldron panel does not use the station display name")
		var recipe_list := _hud.cauldron_panel.get_node("Margin/Content/Body/Recipes/RecipeScroll/RecipeList") as VBoxContainer
		_expect(recipe_list.get_child_count() == 1, "cauldron panel did not show one potion recipe")
		_expect(_hud.cauldron_panel.get_selected_recipe_id() == &"health_potion", "cauldron did not select the health potion recipe")
		var potion_stats := _hud.cauldron_panel.get_node("Margin/Content/Body/Details/Stats") as RichTextLabel
		_expect(potion_stats.visible and potion_stats.get_parsed_text().contains("Health: +100"), "health potion recipe did not show its recovery stat")
		_expect(potion_stats.text.contains("[b][color=#%s]+100[/color][/b]" % CombatPresentationPalette.WEAK_DAMAGE_COLOR.to_html(false)), "health potion recovery value is not highlighted and bold")
		_expect(_hud.cauldron_panel.get_craft_button().is_craft_enabled(), "available health potion recipe was disabled")
		_hud.cauldron_panel.get_craft_button().pressed.emit()
		_expect(_inventory.get_inventory_item_count(&"health_potion") == 1, "cauldron did not craft a health potion")
		_expect(_inventory.get_inventory_item_count(&"pumpkin") == 0 and _inventory.get_inventory_item_count(&"apple") == 0, "cauldron craft consumed the wrong ingredients")
		var cauldron_mined := VoxelWorldTestFixture.commit_mine(_world, _cauldron_position)
		_expect(cauldron_mined != null and not cauldron_mined.get_edits().is_empty(), "open test cauldron could not be mined")
		_expect(not _hud.cauldron_panel.is_open(), "mining the active cauldron left its crafting panel usable")
		_expect(_hud.side_panel.is_open(), "mining the active cauldron unexpectedly closed the backpack")
		_expect(VoxelWorldTestFixture.commit_place(_world, _cauldron_position, BlockId.Type.CAULDRON) != null, "test cauldron could not be restored")
		_hud.open_crafting_station(_cauldron_position, _cauldron_station)
		_hud.toggle_backpack()
		_phase = 5
	elif _phase == 5 and _frame == 167:
		_expect(not _hud.cauldron_panel.is_open() and not _hud.side_panel.is_open(), "P did not close the cauldron and backpack")
		_hud.open_crafting_station(_cauldron_position, _cauldron_station)
		_hud.toggle_crafting()
		_phase = 6
	elif _phase == 6 and _frame == 200:
		_expect(not _hud.cauldron_panel.is_open(), "Tab did not close the cauldron")
		_expect(_hud.crafting_panel.is_open() and _hud.side_panel.is_open(), "Tab did not open general crafting after the cauldron")
		_expect(_camera_rig._left_panel_progress > 0.95, "closing the cauldron cleared the open general panel camera offset")
		_hud.free()
		_camera_rig.free()
		_camera_follow.free()
		_phase = 7
	elif _phase == 7 and _frame == 210:
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
