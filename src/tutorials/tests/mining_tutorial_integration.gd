extends SceneTree

var _failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_progress_contract()
	await _test_mining_before_delay_prevents_tip()
	await _test_delay_pauses_outside_overworld()
	await _test_callout_waits_for_active_tip()
	await _test_delayed_tip_and_mining_completion()
	await _test_distance_completion()
	if _failures == 0:
		print("MINING_TUTORIAL PASS")
		quit(0)
	else:
		print("MINING_TUTORIAL FAIL failures=%d" % _failures)
		quit(1)

func _test_progress_contract() -> void:
	var progress := TutorialProgress.new()
	_expect(progress.restore({"mining_tip_completed": false, "food_tip_completed": false, "crafting_tip_completed": false, "crafting_ingredients_tip_completed": false}), "valid tutorial progress did not restore")
	_expect(not progress.is_mining_tip_completed(), "fresh tutorial progress restored as complete")
	var change_count := [0]
	progress.changed.connect(func() -> void: change_count[0] += 1)
	_expect(progress.complete_mining_tip(), "first tutorial completion was rejected")
	_expect(not progress.complete_mining_tip(), "duplicate tutorial completion was accepted")
	_expect(change_count[0] == 1, "tutorial completion emitted more than one change")
	_expect(progress.snapshot() == {"mining_tip_completed": true, "food_tip_completed": false, "crafting_tip_completed": false, "crafting_ingredients_tip_completed": false}, "tutorial snapshot changed")
	_expect(progress.complete_food_tip(), "first food tutorial completion was rejected")
	_expect(not progress.complete_food_tip(), "duplicate food tutorial completion was accepted")
	_expect(change_count[0] == 2, "food tutorial completion emitted the wrong change count")
	_expect(progress.snapshot() == {"mining_tip_completed": true, "food_tip_completed": true, "crafting_tip_completed": false, "crafting_ingredients_tip_completed": false}, "food tutorial snapshot changed")
	_expect(progress.complete_crafting_tip(), "first crafting tutorial completion was rejected")
	_expect(not progress.complete_crafting_tip(), "duplicate crafting tutorial completion was accepted")
	_expect(change_count[0] == 3, "crafting tutorial completion emitted the wrong change count")
	_expect(progress.snapshot() == {"mining_tip_completed": true, "food_tip_completed": true, "crafting_tip_completed": true, "crafting_ingredients_tip_completed": false}, "crafting tutorial snapshot changed")
	_expect(progress.complete_crafting_ingredients_tip(), "first crafting ingredients tutorial completion was rejected")
	_expect(not progress.complete_crafting_ingredients_tip(), "duplicate crafting ingredients tutorial completion was accepted")
	_expect(change_count[0] == 4, "crafting ingredients tutorial completion emitted the wrong change count")
	_expect(progress.snapshot() == {"mining_tip_completed": true, "food_tip_completed": true, "crafting_tip_completed": true, "crafting_ingredients_tip_completed": true}, "crafting ingredients tutorial snapshot changed")
	_expect(not TutorialProgress.new().restore({}), "missing tutorial completion restored")
	_expect(not TutorialProgress.new().restore({"mining_tip_completed": 1}), "non-boolean tutorial completion restored")

func _test_mining_before_delay_prevents_tip() -> void:
	var fixture := await _create_fixture(false)
	var coordinator := fixture["coordinator"] as MiningTutorialCoordinator
	var view := fixture["view"] as MiningTutorialView
	var interactor := fixture["interactor"] as PlayerInteractor
	var progress := fixture["progress"] as TutorialProgress
	interactor.block_mined.emit(Vector3i.ZERO)
	coordinator._process(MiningTutorialCoordinator.SHOW_DELAY_SECONDS + 1.0)
	_expect(progress.is_mining_tip_completed(), "mining before the delay did not complete the tutorial")
	_expect(not (view.get_node("TutorialSelectionBox") as Node3D).visible, "tip appeared after mining during the delay")
	await _destroy_fixture(fixture)

func _test_delay_pauses_outside_overworld() -> void:
	var fixture := await _create_fixture(false)
	var coordinator := fixture["coordinator"] as MiningTutorialCoordinator
	var view := fixture["view"] as MiningTutorialView
	var active_space := fixture["active_space"] as Array
	active_space[0] = false
	coordinator._process(MiningTutorialCoordinator.SHOW_DELAY_SECONDS + 1.0)
	_expect(not (view.get_node("TutorialSelectionBox") as Node3D).visible, "tutorial appeared outside the overworld")
	active_space[0] = true
	coordinator._process(MiningTutorialCoordinator.SHOW_DELAY_SECONDS - 0.01)
	_expect(not (view.get_node("TutorialSelectionBox") as Node3D).visible, "tutorial delay advanced outside the overworld")
	coordinator._process(0.02)
	_expect((view.get_node("TutorialSelectionBox") as Node3D).visible, "tutorial did not resume after returning to the overworld")
	await _destroy_fixture(fixture)

func _test_callout_waits_for_active_tip() -> void:
	var fixture := await _create_fixture(false)
	var coordinator := fixture["coordinator"] as MiningTutorialCoordinator
	var view := fixture["view"] as MiningTutorialView
	var arbiter := fixture["arbiter"] as TutorialCalloutArbiter
	var other_owner := Node.new()
	_expect(arbiter.try_acquire(other_owner), "mining tutorial fixture could not reserve another callout")
	coordinator._process(MiningTutorialCoordinator.SHOW_DELAY_SECONDS)
	_expect(not view.is_showing(), "mining tutorial displayed while another callout was active")
	arbiter.release(other_owner)
	other_owner.free()
	coordinator._process(0.0)
	_expect(view.is_showing(), "mining tutorial did not display after the active callout cleared")
	await _destroy_fixture(fixture)

func _test_delayed_tip_and_mining_completion() -> void:
	var fixture := await _create_fixture(false)
	var coordinator := fixture["coordinator"] as MiningTutorialCoordinator
	var view := fixture["view"] as MiningTutorialView
	var interactor := fixture["interactor"] as PlayerInteractor
	var progress := fixture["progress"] as TutorialProgress
	coordinator._process(MiningTutorialCoordinator.SHOW_DELAY_SECONDS - 0.01)
	_expect(not (view.get_node("TutorialSelectionBox") as Node3D).visible, "mining tip appeared before five seconds")
	coordinator._process(0.02)
	var selection := view.get_node("TutorialSelectionBox") as Node3D
	_expect(selection.visible, "mining tip did not appear after five seconds")
	_expect(selection.global_position.is_equal_approx(Vector3(2.5, 1.5, 2.5)), "mining tip did not prioritize the most visible block within mining reach")
	var camera_direction := Vector3(1.0, 0.0, 1.0).normalized()
	_expect(coordinator._get_camera_visible_side_count(Vector3i(2, 1, 2), camera_direction) == 2, "reachable terrain block did not expose two camera-facing sides")
	_expect(coordinator._get_camera_visible_side_count(Vector3i(7, 1, 6), camera_direction) == 2, "fallback terrain block did not expose two camera-facing sides")
	_expect(not coordinator._is_valid_target(Vector3i(3, 1, 3)), "tutorial selected terrain that requires a pickaxe")
	var original_reach := interactor.reach
	interactor.reach = 1.0
	var fallback_target := coordinator._choose_target() as Vector3i
	_expect(coordinator._get_camera_visible_side_count(fallback_target, camera_direction) == 2, "fallback search did not choose a maximally visible block within ten blocks")
	_expect(Vector2(fallback_target.x, fallback_target.z).length() <= MiningTutorialCoordinator.TARGET_RADIUS, "fallback search chose a block outside the ten-block radius")
	interactor.reach = original_reach
	var overlay := view.get_node("OverlayLayer/Overlay") as Control
	var panel := view.get_node("OverlayLayer/Overlay/TipPanel") as PanelContainer
	var label := view.get_node("OverlayLayer/Overlay/TipPanel/Text/Title") as Label
	var subtext := view.get_node("OverlayLayer/Overlay/TipPanel/Text/Subtext") as Label
	_expect(label.text == "Hold left mouse button to mine blocks", "mining tip text changed")
	_expect(not subtext.visible, "mining tip displayed an empty subtext row")
	_expect(not view.has_node("OverlayLayer/Overlay/PointerLine"), "mining tip retained a pointer line")
	var camera := fixture["camera"] as Camera3D
	var expected_anchor := camera.unproject_position(Vector3(2.5, 4.1, 2.5))
	_expect(is_equal_approx(panel.position.x + TutorialCalloutView.PANEL_SIZE.x * 0.5, expected_anchor.x), "mining tip tooltip was not centered above the block")
	_expect(is_equal_approx(panel.position.y + TutorialCalloutView.PANEL_SIZE.y + TutorialCalloutView.PANEL_GAP, expected_anchor.y), "mining tip tooltip did not use its raised anchor")
	var edge := selection.get_child(0) as MeshInstance3D
	var edge_mesh := edge.mesh as BoxMesh
	var edge_material := edge.material_override as StandardMaterial3D
	_expect(edge_mesh.size.is_equal_approx(Vector3(BlockOutlineBuilder.EDGE_LENGTH, BlockOutlineBuilder.EDGE_THICKNESS, BlockOutlineBuilder.EDGE_THICKNESS)), "mining tutorial outline geometry differs from targeting")
	_expect(selection.scale.is_equal_approx(Vector3.ONE / BlockOutlineBuilder.EDGE_LENGTH), "mining tutorial outline scale differs from targeting")
	_expect(edge_material.albedo_color.r == 1.0 and edge_material.albedo_color.g == 1.0 and edge_material.albedo_color.b == 1.0, "mining tip outline is not white")
	_expect(is_zero_approx(edge_material.albedo_color.a) and is_zero_approx(overlay.modulate.a), "mining tip did not begin transparent")
	view._process(MiningTutorialView.FADE_DURATION * 0.5)
	_expect(edge_material.albedo_color.a > 0.0 and edge_material.albedo_color.a < MiningTutorialView.OUTLINE_ALPHA, "mining tip outline did not fade in")
	_expect(overlay.modulate.a > 0.0 and overlay.modulate.a < 1.0, "mining tip tooltip did not fade in")
	view._process(MiningTutorialView.FADE_DURATION * 0.5)
	_expect(is_equal_approx(edge_material.albedo_color.a, MiningTutorialView.OUTLINE_ALPHA), "mining tip outline did not reach its authored alpha")
	_expect(is_equal_approx(overlay.modulate.a, 1.0), "mining tip tooltip did not finish fading in")
	var panel_size := panel.size
	camera.size = 60.0
	view._process(0.01)
	_expect(panel.size.is_equal_approx(panel_size), "screen-space mining tooltip changed size when zooming out")
	_expect(label.get_theme_font_size("font_size") == 16, "screen-space mining tooltip font size changed")
	camera.size = 30.0
	camera.look_at(camera.global_position * 2.0)
	view._process(0.01)
	_expect(not overlay.visible, "mining tip tooltip remained visible behind the camera")
	camera.look_at(Vector3.ZERO)
	view._process(0.01)
	_expect(overlay.visible, "mining tip tooltip did not return after the camera rotated back")
	interactor.target_has = true
	interactor.target_block = Vector3i(2, 1, 2)
	interactor.can_primary_target = true
	coordinator._process(0.01)
	_expect(not selection.visible, "white tutorial outline remained under the yellow hover outline")
	interactor.target_has = false
	coordinator._process(0.01)
	_expect(selection.visible, "white tutorial outline did not return after hover ended")
	interactor.block_mined.emit(Vector3i.ZERO)
	_expect(progress.is_mining_tip_completed(), "mining did not complete the tutorial")
	view._process(MiningTutorialView.FADE_DURATION * 0.5)
	_expect(selection.visible and edge_material.albedo_color.a > 0.0 and edge_material.albedo_color.a < MiningTutorialView.OUTLINE_ALPHA, "mining tip outline did not fade out")
	_expect(overlay.visible and overlay.modulate.a > 0.0 and overlay.modulate.a < 1.0, "mining tip tooltip did not fade out")
	view._process(MiningTutorialView.FADE_DURATION * 0.5)
	_expect(not selection.visible, "mining did not hide the terrain highlight after fading")
	_expect(not overlay.visible, "mining did not hide the tutorial callout after fading")
	await _destroy_fixture(fixture)

func _test_distance_completion() -> void:
	var fixture := await _create_fixture(false)
	var coordinator := fixture["coordinator"] as MiningTutorialCoordinator
	var view := fixture["view"] as MiningTutorialView
	var player := fixture["player"] as Node3D
	var progress := fixture["progress"] as TutorialProgress
	coordinator._process(MiningTutorialCoordinator.SHOW_DELAY_SECONDS)
	_expect((view.get_node("TutorialSelectionBox") as Node3D).visible, "distance fixture did not show the tutorial")
	player.global_position = Vector3(30.0, 1.0, 30.0)
	coordinator._process(0.01)
	_expect(progress.is_mining_tip_completed(), "walking away did not complete the tutorial")
	view._process(MiningTutorialView.FADE_DURATION)
	_expect(not (view.get_node("TutorialSelectionBox") as Node3D).visible, "walking away did not hide the tutorial after fading")
	await _destroy_fixture(fixture)

func _create_fixture(completed: bool) -> Dictionary:
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
	var interactor := PlayerInteractor.new()
	interactor.unarmed_primary_action = load("res://items/actions/definitions/unarmed_mining.tres") as MiningActionDefinition
	holder.add_child(interactor)
	player.global_position = Vector3(0.5, 1.0, 0.5)
	var world := VoxelWorld.new(16, 32, 5, 8.0, load("res://blocks/block_catalog.tres") as BlockCatalog)
	for x in range(-11, 12):
		for z in range(-11, 12):
			world.height_map_dict[Vector2i(x, z)] = 0
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	world.height_map_dict.erase(Vector2i(-1, -2))
	world.type_map_dict.erase(Vector2i(-1, -2))
	world.height_map_dict[Vector2i(2, 2)] = 1
	world.height_map_dict[Vector2i(7, 6)] = 1
	world.height_map_dict[Vector2i(3, 3)] = 1
	world.copper_block_fast[Vector3i(3, 1, 3)] = BlockId.Type.COPPER
	var view := MiningTutorialView.new()
	holder.add_child(view)
	var progress := TutorialProgress.new()
	_expect(progress.restore({"mining_tip_completed": completed, "food_tip_completed": false, "crafting_tip_completed": false, "crafting_ingredients_tip_completed": false}), "fixture tutorial progress did not restore")
	var coordinator := MiningTutorialCoordinator.new()
	holder.add_child(coordinator)
	var active_space := [true]
	var arbiter := TutorialCalloutArbiter.new()
	coordinator.setup(world, player, func() -> bool: return bool(active_space[0]), camera, interactor, view, progress, arbiter, 91234)
	coordinator.set_process(false)
	await process_frame
	return {
		"holder": holder,
		"camera": camera,
		"world": world,
		"active_space": active_space,
		"player": player,
		"interactor": interactor,
		"view": view,
		"progress": progress,
		"coordinator": coordinator,
		"arbiter": arbiter,
	}

func _destroy_fixture(fixture: Dictionary) -> void:
	(fixture["holder"] as Node).free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[mining_tutorial_integration] FAIL: %s" % message)
