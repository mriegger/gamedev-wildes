extends SceneTree

var _failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_first_open_waits_and_highlights_ingredients()
	await _test_closing_completes_pending_tip()
	if _failures == 0:
		print("CRAFTING_INGREDIENTS_TUTORIAL PASS")
		quit(0)
	else:
		print("CRAFTING_INGREDIENTS_TUTORIAL FAIL failures=%d" % _failures)
		quit(1)

func _test_first_open_waits_and_highlights_ingredients() -> void:
	var fixture := await _create_fixture()
	var crafting_panel := fixture["crafting_panel"] as CraftingPanel
	var coordinator := fixture["coordinator"] as CraftingIngredientsTutorialCoordinator
	var view := fixture["view"] as CraftingIngredientsTutorialView
	var progress := fixture["progress"] as TutorialProgress
	var arbiter := fixture["arbiter"] as TutorialCalloutArbiter
	var previous_tip := Node.new()
	_expect(arbiter.try_acquire(previous_tip), "ingredients tutorial fixture could not reserve the previous callout")
	crafting_panel.open()
	crafting_panel._process(1.0)
	coordinator._process(0.0)
	_expect(not view.is_showing(), "ingredients tutorial overlapped another active callout")
	_expect(not progress.is_crafting_ingredients_tip_completed(), "waiting ingredients tutorial completed before display")
	arbiter.release(previous_tip)
	previous_tip.free()
	coordinator._process(0.0)
	_expect(view.is_showing(), "ingredients tutorial did not appear when the callout slot cleared")
	_expect(not progress.is_crafting_ingredients_tip_completed(), "ingredients tutorial completed before dismissal")
	var expected_rect := crafting_panel.get_ingredients_global_rect().grow(CraftingIngredientsTutorialView.OUTLINE_MARGIN)
	var outline := view.get_node("Content/IngredientsOutline") as Panel
	var tip_panel := view.get_node("Content/TipPanel") as PanelContainer
	var label := view.get_node("Content/TipPanel/Text") as Label
	_expect(outline.position.is_equal_approx(expected_rect.position) and outline.size.is_equal_approx(expected_rect.size), "ingredients tutorial outline did not match the selected recipe ingredients")
	_expect(tip_panel.position.x >= expected_rect.end.x + CraftingIngredientsTutorialView.TOOLTIP_GAP - 0.01, "ingredients tutorial tooltip was not placed to the right")
	_expect(label.text == "Collect resources to craft items", "ingredients tutorial text changed")
	view._process(CraftingIngredientsTutorialView.FADE_DURATION)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = expected_rect.get_center()
	crafting_panel._input(click)
	_expect(progress.is_crafting_ingredients_tip_completed(), "crafting-panel interaction did not complete the ingredients tutorial")
	var dismissal_outline_position := outline.position
	var dismissal_outline_size := outline.size
	var dismissal_tooltip_position := tip_panel.position
	crafting_panel.select_recipe(&"chest")
	var queued_tip := Node.new()
	_expect(not arbiter.try_acquire(queued_tip), "ingredients tutorial released its callout before fading out")
	view._process(CraftingIngredientsTutorialView.FADE_DURATION * 0.5)
	_expect(outline.position == dismissal_outline_position and outline.size == dismissal_outline_size, "ingredients outline moved or resized while fading out")
	_expect(tip_panel.position == dismissal_tooltip_position, "ingredients tooltip moved while fading out")
	view._process(CraftingIngredientsTutorialView.FADE_DURATION * 0.5)
	_expect(not tip_panel.visible or not (view.get_node("Content") as Control).visible, "ingredients tutorial remained visible after interaction")
	_expect(arbiter.try_acquire(queued_tip), "ingredients tutorial did not release its callout after fading out")
	arbiter.release(queued_tip)
	queued_tip.free()
	crafting_panel.close()
	crafting_panel.open()
	coordinator._process(0.0)
	_expect(not view.is_showing(), "dismissed ingredients tutorial appeared on a later crafting open")
	await _destroy_fixture(fixture)

func _test_closing_completes_pending_tip() -> void:
	var fixture := await _create_fixture()
	var crafting_panel := fixture["crafting_panel"] as CraftingPanel
	var coordinator := fixture["coordinator"] as CraftingIngredientsTutorialCoordinator
	var view := fixture["view"] as CraftingIngredientsTutorialView
	var progress := fixture["progress"] as TutorialProgress
	var arbiter := fixture["arbiter"] as TutorialCalloutArbiter
	var previous_tip := Node.new()
	_expect(arbiter.try_acquire(previous_tip), "pending-close fixture could not reserve another callout")
	crafting_panel.open()
	coordinator._process(0.0)
	crafting_panel.close()
	_expect(progress.is_crafting_ingredients_tip_completed(), "closing crafting did not complete the pending ingredients tutorial")
	arbiter.release(previous_tip)
	previous_tip.free()
	crafting_panel.open()
	coordinator._process(0.0)
	_expect(not view.is_showing(), "closed pending ingredients tutorial appeared on a later open")
	await _destroy_fixture(fixture)

func _create_fixture() -> Dictionary:
	var holder := Node.new()
	root.add_child(holder)
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	_expect(inventory.setup_empty(), "ingredients tutorial inventory setup failed")
	var stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	var proficiency := ItemProficiency.new(item_catalog)
	var loadout := InventoryLoadoutCoordinator.new()
	_expect(loadout.setup(inventory, stats, proficiency), "ingredients tutorial loadout setup failed")
	var crafting := CraftingCoordinator.new()
	var recipe_catalog := load("res://crafting/crafting_recipe_catalog.tres") as CraftingRecipeCatalog
	crafting.setup(inventory, loadout, recipe_catalog)
	var hud := (load("res://ui/hud/hud.tscn") as PackedScene).instantiate() as HUD
	holder.add_child(hud)
	var camera_rig := (load("res://player/camera/camera_rig.tscn") as PackedScene).instantiate() as CameraRig
	holder.add_child(camera_rig)
	var camera_follow := Node3D.new()
	holder.add_child(camera_follow)
	await process_frame
	camera_rig.setup(camera_follow, InputBuffer.new())
	hud.setup_with_camera(inventory, loadout, crafting, recipe_catalog, camera_rig, stats, proficiency)
	var view := CraftingIngredientsTutorialView.new()
	holder.add_child(view)
	var progress := TutorialProgress.new()
	_expect(progress.restore({
		"mining_tip_completed": true,
		"food_tip_completed": true,
		"crafting_tip_completed": true,
		"crafting_ingredients_tip_completed": false,
		"copper_mining_tip_completed": false,
	}), "ingredients tutorial progress setup failed")
	var arbiter := TutorialCalloutArbiter.new()
	var coordinator := CraftingIngredientsTutorialCoordinator.new()
	holder.add_child(coordinator)
	await process_frame
	coordinator.setup(hud.crafting_panel, view, progress, arbiter)
	coordinator.set_process(false)
	return {
		"holder": holder,
		"crafting_panel": hud.crafting_panel,
		"coordinator": coordinator,
		"view": view,
		"progress": progress,
		"arbiter": arbiter,
	}

func _destroy_fixture(fixture: Dictionary) -> void:
	(fixture["holder"] as Node).free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[crafting_ingredients_tutorial_integration] FAIL: %s" % message)
