extends SceneTree

var _failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_bare_hand_attempt_shows_one_time_callout()
	await _test_warning_preempts_active_mining_tip()
	await _test_other_callout_and_successful_mining_resolution()
	await _test_tool_and_distance_filters()
	if _failures == 0:
		print("COPPER_MINING_TUTORIAL PASS")
		quit(0)
	else:
		print("COPPER_MINING_TUTORIAL FAIL failures=%d" % _failures)
		quit(1)

func _test_bare_hand_attempt_shows_one_time_callout() -> void:
	var fixture := await _create_fixture(false)
	var coordinator := fixture["coordinator"] as CopperMiningTutorialCoordinator
	var interactor := fixture["interactor"] as PlayerInteractor
	var view := fixture["view"] as CopperMiningTutorialView
	var progress := fixture["progress"] as TutorialProgress
	var player := fixture["player"] as Node3D
	var position := fixture["copper_position"] as Vector3i
	interactor.mining_tool_requirement_failed.emit(position, BlockId.Type.COPPER, interactor.unarmed_primary_action)
	await process_frame
	_expect(view.is_showing(), "bare-hand copper attempt did not show the warning")
	_expect(progress.is_copper_mining_tip_completed(), "shown copper warning was not persisted as one-time")
	var selection := view.get_node("TutorialSelectionBox") as Node3D
	var panel := view.get_node("OverlayLayer/Overlay/TipPanel") as PanelContainer
	var label := view.get_node("OverlayLayer/Overlay/TipPanel/Text/Title") as Label
	_expect(selection.global_position.is_equal_approx(Vector3(position) + Vector3.ONE * 0.5), "copper warning did not highlight the attempted block")
	_expect(label.text == "Copper is too hard to mine by hand. Craft a Pickaxe.", "copper warning text changed")
	var expected_anchor := (fixture["camera"] as Camera3D).unproject_position(
		Vector3(position) + Vector3(0.5, 1.0 + TutorialCalloutView.TOOLTIP_HEIGHT, 0.5)
	)
	_expect(is_equal_approx(panel.position.x + panel.size.x * 0.5, expected_anchor.x), "copper warning was not centered horizontally over the block")
	_expect(label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "copper warning text was not centered inside its panel")
	interactor.target_has = true
	interactor.target_block = position
	coordinator._process(0.0)
	_expect(not selection.visible, "white copper warning remained under the normal targeting outline")
	interactor.target_has = false
	coordinator._process(0.0)
	_expect(selection.visible, "white copper warning did not return after target hover ended")
	view._process(TutorialCalloutView.FADE_DURATION)
	player.global_position = Vector3(30.0, 1.0, 30.0)
	coordinator._process(0.0)
	view._process(TutorialCalloutView.FADE_DURATION)
	interactor.mining_tool_requirement_failed.emit(position, BlockId.Type.COPPER, interactor.unarmed_primary_action)
	_expect(not view.is_showing(), "persisted copper warning appeared a second time")
	await _destroy_fixture(fixture)

func _test_warning_preempts_active_mining_tip() -> void:
	var fixture := await _create_fixture(false, false)
	var mining_coordinator := fixture["mining_coordinator"] as MiningTutorialCoordinator
	var mining_view := fixture["mining_view"] as MiningTutorialView
	var copper_coordinator := fixture["coordinator"] as CopperMiningTutorialCoordinator
	var copper_view := fixture["view"] as CopperMiningTutorialView
	var interactor := fixture["interactor"] as PlayerInteractor
	var progress := fixture["progress"] as TutorialProgress
	var arbiter := fixture["arbiter"] as TutorialCalloutArbiter
	var position := fixture["copper_position"] as Vector3i
	_expect(arbiter.try_acquire(mining_coordinator, mining_coordinator.dismiss_for_priority_callout), "mining tip did not acquire the shared callout")
	mining_view.show_tip(Vector3i.ZERO)
	mining_view._process(TutorialCalloutView.FADE_DURATION)
	interactor.mining_tool_requirement_failed.emit(position, BlockId.Type.COPPER, interactor.unarmed_primary_action)
	_expect(not mining_view.is_showing(), "active mining tip did not begin hiding for the copper warning")
	_expect(progress.is_mining_tip_completed(), "preempted mining tip was not dismissed permanently")
	_expect(not copper_view.is_showing(), "copper warning overlapped the fading mining tip")
	mining_view._process(TutorialCalloutView.FADE_DURATION)
	copper_coordinator._process(0.0)
	_expect(copper_view.is_showing(), "copper warning did not show after the active mining tip faded")
	await _destroy_fixture(fixture)

func _test_other_callout_and_successful_mining_resolution() -> void:
	var fixture := await _create_fixture(false)
	var coordinator := fixture["coordinator"] as CopperMiningTutorialCoordinator
	var interactor := fixture["interactor"] as PlayerInteractor
	var view := fixture["view"] as CopperMiningTutorialView
	var progress := fixture["progress"] as TutorialProgress
	var arbiter := fixture["arbiter"] as TutorialCalloutArbiter
	var position := fixture["copper_position"] as Vector3i
	var other_owner := Node.new()
	_expect(arbiter.try_acquire(other_owner), "copper warning fixture could not reserve another callout")
	interactor.mining_tool_requirement_failed.emit(position, BlockId.Type.COPPER, interactor.unarmed_primary_action)
	_expect(not view.is_showing() and not progress.is_copper_mining_tip_completed(), "queued copper warning completed before it was displayed")
	interactor.block_mined.emit(position, BlockId.Type.COPPER)
	_expect(progress.is_copper_mining_tip_completed(), "successful copper mining did not resolve the queued warning")
	arbiter.release(other_owner)
	other_owner.free()
	coordinator._process(0.0)
	_expect(not view.is_showing(), "copper warning appeared after copper was already mined")
	await _destroy_fixture(fixture)

func _test_tool_and_distance_filters() -> void:
	var fixture := await _create_fixture(false)
	var coordinator := fixture["coordinator"] as CopperMiningTutorialCoordinator
	var interactor := fixture["interactor"] as PlayerInteractor
	var view := fixture["view"] as CopperMiningTutorialView
	var player := fixture["player"] as Node3D
	var position := fixture["copper_position"] as Vector3i
	var pickaxe_action := (load("res://items/definitions/stone_pickaxe.tres") as ItemDefinition).primary_action as MiningActionDefinition
	interactor.mining_tool_requirement_failed.emit(position, BlockId.Type.COPPER, pickaxe_action)
	coordinator._process(0.0)
	_expect(not view.is_showing(), "pickaxe attempt triggered the bare-hand copper warning")
	interactor.mining_tool_requirement_failed.emit(position, BlockId.Type.COPPER, interactor.unarmed_primary_action)
	_expect(view.is_showing(), "distance fixture did not show the copper warning")
	player.global_position = Vector3(30.0, 1.0, 30.0)
	coordinator._process(0.0)
	_expect(not view.is_showing(), "walking away did not begin hiding the copper warning")
	view._process(TutorialCalloutView.FADE_DURATION)
	_expect(not (view.get_node("TutorialSelectionBox") as Node3D).visible, "walking away did not finish hiding the copper warning")
	await _destroy_fixture(fixture)

func _create_fixture(completed: bool, mining_completed: bool = true) -> Dictionary:
	var holder := Node3D.new()
	root.add_child(holder)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 30.0
	camera.position = Vector3(10.0, 14.0, 10.0)
	holder.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var player := Node3D.new()
	holder.add_child(player)
	player.global_position = Vector3(0.5, 1.0, 0.5)
	var interactor := PlayerInteractor.new()
	interactor.unarmed_primary_action = load("res://items/actions/definitions/unarmed_mining.tres") as MiningActionDefinition
	holder.add_child(interactor)
	var world := VoxelWorld.new(16, 32, 5, 8.0, load("res://blocks/block_catalog.tres") as BlockCatalog)
	var copper_position := Vector3i(2, 1, 2)
	world.copper_block_fast[copper_position] = BlockId.Type.COPPER
	var view := CopperMiningTutorialView.new()
	holder.add_child(view)
	var mining_view := MiningTutorialView.new()
	holder.add_child(mining_view)
	var progress := TutorialProgress.new()
	_expect(progress.restore({
		"mining_tip_completed": mining_completed,
		"food_tip_completed": true,
		"crafting_tip_completed": true,
		"crafting_ingredients_tip_completed": true,
		"copper_mining_tip_completed": completed,
		"sundown_weapon_tip_completed": false, "damage_affinity_tip_completed": false,
	}), "copper warning progress setup failed")
	var arbiter := TutorialCalloutArbiter.new()
	var mining_coordinator := MiningTutorialCoordinator.new()
	holder.add_child(mining_coordinator)
	mining_coordinator.setup(
		world,
		player,
		func() -> bool: return true,
		camera,
		interactor,
		mining_view,
		progress,
		arbiter,
		90125,
	)
	mining_coordinator.set_process(false)
	var coordinator := CopperMiningTutorialCoordinator.new()
	holder.add_child(coordinator)
	coordinator.setup(
		world,
		player,
		func() -> bool: return true,
		camera,
		interactor,
		view,
		progress,
		arbiter,
	)
	coordinator.set_process(false)
	await process_frame
	return {
		"holder": holder,
		"camera": camera,
		"player": player,
		"interactor": interactor,
		"view": view,
		"mining_view": mining_view,
		"progress": progress,
		"arbiter": arbiter,
		"coordinator": coordinator,
		"mining_coordinator": mining_coordinator,
		"copper_position": copper_position,
	}

func _destroy_fixture(fixture: Dictionary) -> void:
	(fixture["holder"] as Node).free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[copper_mining_tutorial_integration] FAIL: %s" % message)
