extends SceneTree

var _failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_opening_before_mining_prevents_tip()
	await _test_delay_resets_around_other_callouts()
	await _test_prior_mining_arms_tip()
	if _failures == 0:
		print("CRAFTING_TUTORIAL PASS")
		quit(0)
	else:
		print("CRAFTING_TUTORIAL FAIL failures=%d" % _failures)
		quit(1)

func _test_opening_before_mining_prevents_tip() -> void:
	var fixture := await _create_fixture(false)
	var crafting_panel := fixture["crafting_panel"] as CraftingPanel
	var interactor := fixture["interactor"] as PlayerInteractor
	var coordinator := fixture["coordinator"] as CraftingTutorialCoordinator
	var progress := fixture["progress"] as TutorialProgress
	var view := fixture["view"] as CraftingTutorialView
	crafting_panel.open()
	_expect(progress.is_crafting_tip_completed(), "opening crafting before mining did not complete its tutorial")
	interactor.block_mined.emit(Vector3i.ZERO, BlockId.Type.STONE)
	coordinator._process(CraftingTutorialCoordinator.SHOW_DELAY_SECONDS + 1.0)
	_expect(not view.is_showing(), "crafting tutorial appeared after crafting had already opened")
	await _destroy_fixture(fixture)

func _test_delay_resets_around_other_callouts() -> void:
	var fixture := await _create_fixture(false)
	var crafting_panel := fixture["crafting_panel"] as CraftingPanel
	var interactor := fixture["interactor"] as PlayerInteractor
	var coordinator := fixture["coordinator"] as CraftingTutorialCoordinator
	var progress := fixture["progress"] as TutorialProgress
	var view := fixture["view"] as CraftingTutorialView
	var arbiter := fixture["arbiter"] as TutorialCalloutArbiter
	interactor.block_mined.emit(Vector3i(2, 1, 2), BlockId.Type.STONE)
	coordinator._process(4.0)
	_expect(not view.is_showing(), "crafting tutorial appeared before five seconds")
	var other_owner := Node.new()
	_expect(arbiter.try_acquire(other_owner), "crafting tutorial fixture could not reserve another callout")
	coordinator._process(2.0)
	_expect(not view.is_showing(), "crafting tutorial appeared while another callout was active")
	arbiter.release(other_owner)
	other_owner.free()
	coordinator._process(4.99)
	_expect(not view.is_showing(), "crafting tutorial delay did not restart after another callout")
	coordinator._process(0.02)
	_expect(view.is_showing(), "crafting tutorial did not appear after the restarted delay")
	var panel := view.get_node("TipPanel") as PanelContainer
	var label := view.get_node("TipPanel/Text") as Label
	_expect(panel.position == CraftingTutorialView.SCREEN_MARGIN, "crafting tutorial did not use its top-left margin")
	_expect(panel.custom_minimum_size == CraftingTutorialView.PANEL_SIZE, "crafting tutorial panel size changed")
	_expect(label.text == "Press Tab to open Crafting menu", "crafting tutorial text changed")
	_expect(label.get_theme_font_size("font_size") == 16, "crafting tutorial font size changed")
	_expect(label.get_theme_font("font") == WildesStyle.REGULAR_FONT, "crafting tutorial does not use the menu font")
	_expect(panel.material is ShaderMaterial and (panel.material as ShaderMaterial).shader.resource_path == "res://ui/theme/frosted_glass.gdshader", "crafting tutorial does not use the frosted menu background")
	view._process(CraftingTutorialView.FADE_DURATION)
	_expect(is_equal_approx(panel.modulate.a, 1.0), "crafting tutorial did not finish fading in")
	crafting_panel.open()
	_expect(progress.is_crafting_tip_completed(), "opening crafting did not complete the visible tutorial")
	var queued_owner := Node.new()
	_expect(not arbiter.try_acquire(queued_owner), "crafting tutorial released its callout before fading out")
	view._process(CraftingTutorialView.FADE_DURATION * 0.5)
	_expect(panel.visible and panel.modulate.a > 0.0 and panel.modulate.a < 1.0, "crafting tutorial did not fade out")
	view._process(CraftingTutorialView.FADE_DURATION * 0.5)
	_expect(not panel.visible, "crafting tutorial remained visible after fading out")
	_expect(arbiter.try_acquire(queued_owner), "crafting tutorial did not release its callout after fading out")
	arbiter.release(queued_owner)
	queued_owner.free()
	await _destroy_fixture(fixture)

func _test_prior_mining_arms_tip() -> void:
	var fixture := await _create_fixture(true)
	var coordinator := fixture["coordinator"] as CraftingTutorialCoordinator
	var view := fixture["view"] as CraftingTutorialView
	coordinator._process(CraftingTutorialCoordinator.SHOW_DELAY_SECONDS)
	_expect(view.is_showing(), "saved mining history did not arm the crafting tutorial")
	await _destroy_fixture(fixture)

func _create_fixture(has_mined_before: bool) -> Dictionary:
	var holder := Node.new()
	root.add_child(holder)
	var hud := (load("res://ui/hud/hud.tscn") as PackedScene).instantiate() as HUD
	holder.add_child(hud)
	var interactor := PlayerInteractor.new()
	holder.add_child(interactor)
	var view := CraftingTutorialView.new()
	holder.add_child(view)
	var progress := TutorialProgress.new()
	_expect(progress.restore({
		"mining_tip_completed": has_mined_before,
		"food_tip_completed": false,
		"crafting_tip_completed": false,
		"crafting_ingredients_tip_completed": false,
		"copper_mining_tip_completed": false,
		"sundown_weapon_tip_completed": false, "damage_affinity_tip_completed": false,
	}), "crafting tutorial progress setup failed")
	var arbiter := TutorialCalloutArbiter.new()
	var coordinator := CraftingTutorialCoordinator.new()
	holder.add_child(coordinator)
	await process_frame
	coordinator.setup(interactor, hud.crafting_panel, view, progress, arbiter, has_mined_before)
	coordinator.set_process(false)
	return {
		"holder": holder,
		"crafting_panel": hud.crafting_panel,
		"interactor": interactor,
		"view": view,
		"progress": progress,
		"arbiter": arbiter,
		"coordinator": coordinator,
	}

func _destroy_fixture(fixture: Dictionary) -> void:
	(fixture["holder"] as Node).free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[crafting_tutorial_integration] FAIL: %s" % message)
