extends SceneTree

class TestFoodSource extends HarvestSource:
	var target_bounds := AABB(Vector3(7.75, 0.0, 0.25), Vector3(0.5, 0.5, 0.5))
	var item_ids: Array[StringName] = [&"apple"]

	func validate_harvest_items(item_catalog: ItemCatalog) -> bool:
		for item_id in item_ids:
			if not item_catalog.has_definition(item_id):
				return false
		return true

	func find_harvest_target(ray_origin: Vector3, ray_direction: Vector3, max_distance: float) -> Dictionary:
		var hit = target_bounds.intersects_ray(ray_origin, ray_direction)
		if not hit is Vector3:
			return {}
		var distance := ray_origin.distance_to(hit as Vector3)
		return {"target_id": 1, "distance": distance} if distance <= max_distance else {}

	func get_harvest_target_bounds(target_id: int) -> AABB:
		assert(target_id == 1)
		return target_bounds

	func get_harvest_target_ids() -> Array[int]:
		return [1]

	func can_harvest_target(target_id: int) -> bool:
		return target_id == 1

	func get_harvest_item_ids(target_id: int) -> Array[StringName]:
		assert(target_id == 1)
		return item_ids.duplicate()

var _failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_nearby_food_tip_and_pickup_completion()
	await _test_distance_completion()
	await _test_non_food_and_inventory_capacity()
	if _failures == 0:
		print("FOOD_TUTORIAL PASS")
		quit(0)
	else:
		print("FOOD_TUTORIAL FAIL failures=%d" % _failures)
		quit(1)

func _test_nearby_food_tip_and_pickup_completion() -> void:
	var fixture := await _create_fixture(false)
	var coordinator := fixture["coordinator"] as FoodTutorialCoordinator
	var view := fixture["view"] as FoodTutorialView
	var player := fixture["player"] as Node3D
	var harvest := fixture["harvest"] as HarvestCoordinator
	var source := fixture["source"] as TestFoodSource
	var progress := fixture["progress"] as TutorialProgress
	var arbiter := fixture["arbiter"] as TutorialCalloutArbiter
	_expect(progress.is_mining_tip_completed(), "food tutorial fixture did not preserve independent mining completion")
	_expect(not progress.is_food_tip_completed(), "mining completion also completed the food tutorial")
	coordinator._process(0.0)
	_expect(not view.is_showing(), "food tutorial appeared outside its activation radius")
	var mining_owner := Node.new()
	_expect(arbiter.try_acquire(mining_owner), "food tutorial fixture could not reserve the mining callout")
	player.global_position = Vector3(0.5, 0.5, 0.5)
	coordinator._process(FoodTutorialCoordinator.SEARCH_INTERVAL)
	_expect(not view.is_showing(), "food tutorial displayed while the mining callout owned the screen")
	arbiter.release(mining_owner)
	mining_owner.free()
	coordinator._process(FoodTutorialCoordinator.SEARCH_INTERVAL)
	var selection := view.get_node("TutorialSelectionBox") as Node3D
	_expect(view.is_showing() and selection.visible, "food tutorial did not appear near collectible food")
	_expect(selection.global_position.is_equal_approx(source.target_bounds.get_center()), "food tutorial did not highlight the collectible")
	_expect(selection.scale.is_equal_approx(source.target_bounds.size / BlockOutlineBuilder.EDGE_LENGTH), "food tutorial outline did not match harvest targeting")
	var panel := view.get_node("OverlayLayer/Overlay/TipPanel") as PanelContainer
	var title := view.get_node("OverlayLayer/Overlay/TipPanel/Text/Title") as Label
	var subtext := view.get_node("OverlayLayer/Overlay/TipPanel/Text/Subtext") as Label
	_expect(title.text == "Consume food to recover health", "food tutorial title changed")
	_expect(subtext.text == "Tip: Craft a Hoe at the Anvil to grow your own food", "food tutorial subtext changed")
	_expect(title.get_theme_font_size("font_size") == 16 and subtext.get_theme_font_size("font_size") == 12, "food tutorial text hierarchy changed")
	_expect(panel.custom_minimum_size == TutorialCalloutView.PANEL_WITH_SUBTEXT_SIZE, "food tutorial did not use the subtext panel size")
	var camera := fixture["camera"] as Camera3D
	var expected_anchor := camera.unproject_position(Vector3(source.target_bounds.get_center().x, source.target_bounds.end.y + TutorialCalloutView.TOOLTIP_HEIGHT, source.target_bounds.get_center().z))
	_expect(is_equal_approx(panel.position.x + TutorialCalloutView.PANEL_WITH_SUBTEXT_SIZE.x * 0.5, expected_anchor.x), "food tutorial was not centered above the collectible")
	view._process(TutorialCalloutView.FADE_DURATION)
	var overlay := view.get_node("OverlayLayer/Overlay") as Control
	_expect(is_equal_approx(overlay.modulate.a, 1.0), "food tutorial did not finish fading in")
	var target_center := source.target_bounds.get_center()
	harvest.update_target(target_center + Vector3.UP, Vector3.DOWN, 2.0, player.global_position, 10.0)
	coordinator._process(0.0)
	_expect(not selection.visible, "food tutorial outline remained under the normal harvest outline")
	harvest.clear_target()
	coordinator._process(0.0)
	_expect(selection.visible, "food tutorial outline did not return after harvest hover ended")
	var stone_items: Array[StringName] = [&"stone_block"]
	harvest.items_harvested.emit(stone_items)
	_expect(not progress.is_food_tip_completed(), "non-food pickup completed the food tutorial")
	var apple_items: Array[StringName] = [&"apple"]
	harvest.items_harvested.emit(apple_items)
	_expect(progress.is_food_tip_completed(), "apple pickup did not complete the food tutorial")
	var queued_owner := Node.new()
	_expect(not arbiter.try_acquire(queued_owner), "food callout released ownership before fading out")
	view._process(TutorialCalloutView.FADE_DURATION * 0.5)
	_expect(overlay.visible and overlay.modulate.a > 0.0 and overlay.modulate.a < 1.0, "food tutorial did not fade out after pickup")
	view._process(TutorialCalloutView.FADE_DURATION * 0.5)
	_expect(not overlay.visible and not selection.visible, "food tutorial remained after its pickup fade")
	_expect(arbiter.try_acquire(queued_owner), "food callout did not release ownership after fading out")
	arbiter.release(queued_owner)
	queued_owner.free()
	await _destroy_fixture(fixture)

func _test_distance_completion() -> void:
	var fixture := await _create_fixture(false)
	var coordinator := fixture["coordinator"] as FoodTutorialCoordinator
	var view := fixture["view"] as FoodTutorialView
	var player := fixture["player"] as Node3D
	var progress := fixture["progress"] as TutorialProgress
	player.global_position = Vector3(0.5, 0.5, 0.5)
	coordinator._process(0.0)
	_expect(view.is_showing(), "distance fixture did not show the food tutorial")
	player.global_position = Vector3(30.0, 0.5, 30.0)
	coordinator._process(0.0)
	_expect(progress.is_food_tip_completed(), "walking away did not complete the food tutorial")
	view._process(TutorialCalloutView.FADE_DURATION)
	_expect(not (view.get_node("TutorialSelectionBox") as Node3D).visible, "walking away did not hide the food highlight")
	await _destroy_fixture(fixture)

func _test_non_food_and_inventory_capacity() -> void:
	var prior_pickup_fixture := await _create_fixture(false)
	var pumpkin_items: Array[StringName] = [&"pumpkin"]
	(prior_pickup_fixture["harvest"] as HarvestCoordinator).items_harvested.emit(pumpkin_items)
	(prior_pickup_fixture["player"] as Node3D).global_position = Vector3(0.5, 0.5, 0.5)
	(prior_pickup_fixture["coordinator"] as FoodTutorialCoordinator)._process(FoodTutorialCoordinator.SEARCH_INTERVAL)
	_expect((prior_pickup_fixture["progress"] as TutorialProgress).is_food_tip_completed(), "pumpkin pickup before proximity did not complete the food tutorial")
	_expect(not (prior_pickup_fixture["view"] as FoodTutorialView).is_showing(), "food tutorial appeared after an earlier food pickup")
	await _destroy_fixture(prior_pickup_fixture)
	var non_food_items: Array[StringName] = [&"stone_block"]
	var non_food_fixture := await _create_fixture(false, false, non_food_items)
	(non_food_fixture["player"] as Node3D).global_position = Vector3(0.5, 0.5, 0.5)
	(non_food_fixture["coordinator"] as FoodTutorialCoordinator)._process(0.0)
	_expect(not (non_food_fixture["view"] as FoodTutorialView).is_showing(), "food tutorial highlighted a non-food harvest target")
	await _destroy_fixture(non_food_fixture)
	var full_fixture := await _create_fixture(false, true)
	(full_fixture["player"] as Node3D).global_position = Vector3(0.5, 0.5, 0.5)
	(full_fixture["coordinator"] as FoodTutorialCoordinator)._process(0.0)
	_expect(not (full_fixture["view"] as FoodTutorialView).is_showing(), "food tutorial highlighted food that could not fit in the inventory")
	await _destroy_fixture(full_fixture)

func _create_fixture(completed: bool, full_inventory: bool = false, item_ids: Array[StringName] = [&"apple"]) -> Dictionary:
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
	player.global_position = Vector3(-20.0, 0.5, -20.0)
	var source := TestFoodSource.new()
	source.item_ids = item_ids
	holder.add_child(source)
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	_expect(inventory.setup_empty(), "food tutorial inventory setup failed")
	if full_inventory:
		var slots: Dictionary = {}
		for index in range(InventoryModel.FILLABLE_SIZE):
			slots[index] = InventoryStack.new(&"dirt_block", 99)
		_expect(InventoryTestFixture.restore_slots(inventory, slots), "food tutorial full inventory setup failed")
	var inventory_loadout := InventoryTestFixture.create_loadout(inventory)
	_expect(inventory_loadout != null, "food tutorial loadout setup failed")
	var hud := (load("res://ui/hud/hud.tscn") as PackedScene).instantiate() as HUD
	holder.add_child(hud)
	await process_frame
	var prompt := InteractionPromptCoordinator.new()
	prompt.setup(hud, func() -> bool: return false)
	var harvest := HarvestCoordinator.new()
	var sources: Array[HarvestSource] = [source]
	_expect(harvest.setup(sources, inventory, inventory_loadout, prompt), "food tutorial harvest setup failed")
	var view := FoodTutorialView.new()
	holder.add_child(view)
	var progress := TutorialProgress.new()
	_expect(progress.restore({"mining_tip_completed": true, "food_tip_completed": completed}), "food tutorial progress setup failed")
	var coordinator := FoodTutorialCoordinator.new()
	holder.add_child(coordinator)
	var arbiter := TutorialCalloutArbiter.new()
	coordinator.setup(player, func() -> bool: return true, camera, harvest, view, progress, arbiter)
	coordinator.set_process(false)
	await process_frame
	return {
		"holder": holder,
		"camera": camera,
		"player": player,
		"source": source,
		"harvest": harvest,
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
	push_error("[food_tutorial_integration] FAIL: %s" % message)
