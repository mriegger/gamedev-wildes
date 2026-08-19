extends SceneTree

var _frame: int = 0
var _phase: int = 0
var _errors: Array[String] = []
var _actor_stats: ActorStats
var _perk_coordinator: PlayerPerkCoordinator
var _crafting_coordinator: CraftingCoordinator
var _panel: CraftingPanel

func _init() -> void:
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	InventoryTestFixture.restore_slots(inventory, {
		0: InventoryStack.new(&"stone_block", 10),
		1: InventoryStack.new(&"log_block", 5),
	})
	_actor_stats = ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	var inventory_loadout := InventoryTestFixture.create_loadout(inventory, _actor_stats)
	_expect(inventory_loadout != null, "inventory loadout setup failed")
	var recipe_catalog := load("res://crafting/crafting_recipe_catalog.tres") as CraftingRecipeCatalog
	_crafting_coordinator = CraftingCoordinator.new()
	_crafting_coordinator.setup(inventory, inventory_loadout, recipe_catalog)
	_expect(_actor_stats.set_progression(4, 50), "progression fixture was rejected")
	var perk_rules := load("res://progression/player_perk_rules.tres") as PlayerPerkRules
	var player_perks := PlayerPerks.new(perk_rules)
	_perk_coordinator = PlayerPerkCoordinator.new()
	_expect(_perk_coordinator.setup(player_perks, _actor_stats), "perk coordinator setup failed")
	_panel = (load("res://crafting/presentation/crafting_panel.tscn") as PackedScene).instantiate() as CraftingPanel
	root.add_child(_panel)

func _process(_delta: float) -> bool:
	_frame += 1
	if _phase == 0 and _frame == 1:
		var recipe_catalog := load("res://crafting/crafting_recipe_catalog.tres") as CraftingRecipeCatalog
		_panel.setup(_crafting_coordinator, recipe_catalog)
		_panel.setup_progression(_actor_stats, _perk_coordinator)
		_panel.open()
		_phase = 1
	elif _phase == 1 and _frame == 3:
		_open_progression_workspace()
		_phase = 2
	elif _phase == 2 and _frame == 5:
		_check_initial_progression()
		_phase = 3
	elif _phase == 3 and _frame == 7:
		_check_allocation_and_exhaust_points()
		_phase = 4
	elif _phase == 4 and _frame == 9:
		_check_visible_progress_refresh()
		_phase = 5
	elif _phase == 5 and _frame == 11:
		_check_workspace_lifecycle()
		_panel.free()
		_phase = 6
	elif _phase == 6 and _frame == 18:
		_finish()
	return false

func _open_progression_workspace() -> void:
	_expect(_panel.get_current_workspace_id() == CraftingPanel.CRAFTING_WORKSPACE_ID, "panel did not open on crafting")
	(_panel.get_node("Margin/Content/WorkspaceTabs/Progression") as Button).pressed.emit()
	_expect(_panel.get_current_workspace_id() == CraftingPanel.PROGRESSION_WORKSPACE_ID, "progression workspace did not open")
	_expect(_panel.get_progression_panel().is_processing(), "visible progression workspace did not refresh live state")

func _check_initial_progression() -> void:
	var progression := _panel.get_progression_panel()
	_expect(progression.visible, "progression panel was hidden in its workspace")
	_expect(not _panel.get_rune_socketing_panel().visible, "rune panel remained visible in progression")
	_expect(not (_panel.get_node("Margin/Content/Body") as Control).visible, "crafting body remained visible in progression")
	_expect((_panel.get_node("Margin/Content/Title") as Label).text == "PROGRESSION", "workspace title did not identify progression")
	_expect(progression.level_label.text == "LEVEL 4", "level label did not show level four")
	_expect(progression.experience_label.text == "XP 50 / 175", "XP label did not show current progress")
	_expect(is_equal_approx(progression.experience_bar.value, 50.0), "XP bar did not show current XP")
	_expect(is_equal_approx(progression.experience_bar.max_value, 175.0), "XP bar did not show required XP")
	_expect(progression.available_points_label.text == "AVAILABLE POINTS: 3", "available points did not match earned levels")
	_expect(Array(progression.get_displayed_perk_ids()) == [&"health", &"strength", &"defense"], "perks did not use authored order")
	_check_row(&"health", "Health", "+10 HP per rank · +0 HP total", "Rank 0 / 10", true)
	_check_row(&"strength", "Strength", "+1 Strength per rank · +0 Strength total", "Rank 0 / 10", true)
	_check_row(&"defense", "Defense", "+1 Defense per rank · +0 Defense total", "Rank 0 / 10", true)
	(_get_row_control(&"health", "Allocate") as Button).pressed.emit()

func _check_allocation_and_exhaust_points() -> void:
	_expect(_perk_coordinator.get_rank(&"health") == 1, "health allocation did not reach the coordinator")
	_expect(is_equal_approx(_actor_stats.get_value(&"hp"), 110.0), "health allocation did not apply its stat")
	_expect(_panel.get_progression_panel().available_points_label.text == "AVAILABLE POINTS: 2", "health allocation did not refresh available points")
	_check_row(&"health", "Health", "+10 HP per rank · +10 HP total", "Rank 1 / 10", true)
	(_get_row_control(&"strength", "Allocate") as Button).pressed.emit()
	(_get_row_control(&"defense", "Allocate") as Button).pressed.emit()
	_expect(_perk_coordinator.get_rank(&"strength") == 1, "strength allocation did not reach the coordinator")
	_expect(_perk_coordinator.get_rank(&"defense") == 1, "defense allocation did not reach the coordinator")
	_expect(is_equal_approx(_actor_stats.get_value(&"strength"), 11.0), "strength allocation did not apply its stat")
	_expect(is_equal_approx(_actor_stats.get_value(&"defense"), 1.0), "defense allocation did not apply its stat")
	_expect(_panel.get_progression_panel().available_points_label.text == "AVAILABLE POINTS: 0", "spent points remained available")
	for perk_id in [&"health", &"strength", &"defense"]:
		_expect((_get_row_control(perk_id, "Allocate") as Button).disabled, "%s allocation stayed enabled without points" % perk_id)
	_expect(_actor_stats.add_experience(125) == 1, "visible refresh fixture did not gain a level")

func _check_visible_progress_refresh() -> void:
	var progression := _panel.get_progression_panel()
	_expect(progression.level_label.text == "LEVEL 5", "visible panel did not refresh the new level")
	_expect(progression.experience_label.text == "XP 0 / 200", "visible panel did not refresh XP rollover")
	_expect(progression.available_points_label.text == "AVAILABLE POINTS: 1", "visible panel did not refresh the earned point")
	for perk_id in [&"health", &"strength", &"defense"]:
		_expect(not (_get_row_control(perk_id, "Allocate") as Button).disabled, "%s allocation did not enable after leveling" % perk_id)
	(_get_row_control(&"health", "Allocate") as Button).pressed.emit()
	_check_row(&"health", "Health", "+10 HP per rank · +20 HP total", "Rank 2 / 10", false)

func _check_workspace_lifecycle() -> void:
	(_panel.get_node("Margin/Content/WorkspaceTabs/Crafting") as Button).pressed.emit()
	_expect(_panel.get_current_workspace_id() == CraftingPanel.CRAFTING_WORKSPACE_ID, "crafting workspace did not reopen")
	_expect(not _panel.get_progression_panel().is_processing(), "hidden progression workspace kept polling")
	_panel.close_immediate()
	_panel.open()
	_expect(_panel.get_current_workspace_id() == CraftingPanel.CRAFTING_WORKSPACE_ID, "reopening did not default to crafting")
	_expect(not _panel.get_progression_panel().is_processing(), "crafting default activated progression polling")

func _check_row(perk_id: StringName, display_name: String, effect: String, rank: String, can_allocate: bool) -> void:
	_expect((_get_row_control(perk_id, "Details/Name") as Label).text == display_name, "%s row has the wrong name" % perk_id)
	_expect((_get_row_control(perk_id, "Details/Effect") as Label).text == effect, "%s row has the wrong effect" % perk_id)
	_expect((_get_row_control(perk_id, "Rank") as Label).text == rank, "%s row has the wrong rank" % perk_id)
	_expect((_get_row_control(perk_id, "Allocate") as Button).disabled == not can_allocate, "%s row has the wrong allocation state" % perk_id)

func _get_row_control(perk_id: StringName, path: String) -> Control:
	var row := _panel.get_progression_panel().get_perk_row(perk_id)
	_expect(row != null, "%s row is missing" % perk_id)
	return row.get_node("Content/%s" % path) as Control

func _finish() -> void:
	if _errors.is_empty():
		print("PROGRESSION_UI PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
