extends SceneTree

var _failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_unarmed_sundown_warning()
	await _test_weapon_skips_warning()
	await _test_bow_requires_ammunition()
	await _test_pending_warning_respects_inventory_and_arbiter()
	if _failures == 0:
		print("SUNDOWN_WEAPON_TUTORIAL PASS")
		quit(0)
	else:
		print("SUNDOWN_WEAPON_TUTORIAL FAIL failures=%d" % _failures)
		quit(1)

func _test_unarmed_sundown_warning() -> void:
	var fixture := await _create_fixture(16.9)
	var coordinator := fixture["coordinator"] as SundownWeaponTutorialCoordinator
	var view := fixture["view"] as SundownWeaponTutorialView
	var progress := fixture["progress"] as TutorialProgress
	var time := fixture["time"] as Array
	coordinator._process(0.0)
	_expect(not view.is_showing(), "sundown warning appeared before 17:00")
	time[0] = 17.0
	coordinator._process(0.0)
	_expect(view.is_showing(), "unarmed player did not receive the sundown warning")
	_expect(progress.is_sundown_weapon_tip_completed(), "shown sundown warning was not persisted")
	var panel := view.get_node("TipPanel") as PanelContainer
	var label := view.get_node("TipPanel/Text") as Label
	_expect(panel.position == SundownWeaponTutorialView.SCREEN_MARGIN, "sundown warning did not use the crafting hint's top-left margin")
	_expect(panel.custom_minimum_size == SundownWeaponTutorialView.PANEL_SIZE, "sundown warning panel size changed")
	_expect(panel.size.x < 580.0, "sundown warning retained its oversized horizontal padding")
	_expect(label.text == "Night approaching! Craft a weapon at the\nAnvil to defend yourself against enemy threats.", "sundown warning text changed")
	view._process(SundownWeaponTutorialView.FADE_DURATION)
	view._process(SundownWeaponTutorialView.DISPLAY_DURATION_SECONDS - 0.01)
	_expect(view.is_showing() and panel.visible, "sundown warning ended before fifteen seconds")
	view._process(0.02)
	_expect(not view.is_showing() and panel.visible, "sundown warning did not begin fading after fifteen seconds")
	view._process(SundownWeaponTutorialView.FADE_DURATION)
	_expect(not panel.visible, "sundown warning remained visible after fading out")
	await _destroy_fixture(fixture)

func _test_weapon_skips_warning() -> void:
	var fixture := await _create_fixture(16.9, &"copper_sword")
	var coordinator := fixture["coordinator"] as SundownWeaponTutorialCoordinator
	var view := fixture["view"] as SundownWeaponTutorialView
	var progress := fixture["progress"] as TutorialProgress
	var inventory := fixture["inventory"] as InventoryModel
	var time := fixture["time"] as Array
	time[0] = 17.0
	coordinator._process(0.0)
	_expect(progress.is_sundown_weapon_tip_completed(), "armed sundown was not persisted as resolved")
	_expect(not view.is_showing(), "armed player received the sundown warning")
	_expect(InventoryTestFixture.restore_slot(inventory, 0, null), "weapon could not be removed from the sundown fixture")
	time[0] = 16.9
	coordinator._process(0.0)
	time[0] = 17.0
	coordinator._process(0.0)
	_expect(not view.is_showing(), "completed sundown warning appeared on a later day")
	await _destroy_fixture(fixture)

func _test_pending_warning_respects_inventory_and_arbiter() -> void:
	var fixture := await _create_fixture(16.9)
	var coordinator := fixture["coordinator"] as SundownWeaponTutorialCoordinator
	var view := fixture["view"] as SundownWeaponTutorialView
	var progress := fixture["progress"] as TutorialProgress
	var inventory := fixture["inventory"] as InventoryModel
	var arbiter := fixture["arbiter"] as TutorialCalloutArbiter
	var time := fixture["time"] as Array
	var other_owner := Node.new()
	_expect(arbiter.try_acquire(other_owner), "sundown fixture could not reserve another callout")
	time[0] = 17.0
	coordinator._process(0.0)
	_expect(not view.is_showing() and not progress.is_sundown_weapon_tip_completed(), "blocked sundown warning completed before display")
	_expect(InventoryTestFixture.restore_slot(inventory, InventoryModel.HOTBAR_SIZE, InventoryStack.new(&"copper_sword", 1, inventory.equipment_instance_factory.create(&"copper_sword"))), "pending sundown fixture could not add a backpack weapon")
	_expect(progress.is_sundown_weapon_tip_completed() and not view.is_showing(), "acquiring a weapon did not resolve the pending sundown warning")
	arbiter.release(other_owner)
	other_owner.free()
	await _destroy_fixture(fixture)

func _test_bow_requires_ammunition() -> void:
	var bow_only := await _create_fixture(16.9, &"bow")
	var bow_only_time := bow_only["time"] as Array
	bow_only_time[0] = 17.0
	(bow_only["coordinator"] as SundownWeaponTutorialCoordinator)._process(0.0)
	_expect((bow_only["view"] as SundownWeaponTutorialView).is_showing(), "bow without ammunition suppressed the sundown warning")
	await _destroy_fixture(bow_only)
	var armed := await _create_fixture(16.9, &"bow", &"stone_arrow")
	var armed_time := armed["time"] as Array
	armed_time[0] = 17.0
	(armed["coordinator"] as SundownWeaponTutorialCoordinator)._process(0.0)
	_expect((armed["progress"] as TutorialProgress).is_sundown_weapon_tip_completed(), "bow and arrows did not resolve the sundown warning")
	_expect(not (armed["view"] as SundownWeaponTutorialView).is_showing(), "player with a bow and arrows received the sundown warning")
	var armed_inventory := armed["inventory"] as InventoryModel
	var bow_action := armed_inventory.item_catalog.get_definition(&"bow").primary_action as BowDrawActionDefinition
	bow_action.ammunition = [armed_inventory.item_catalog.get_definition(&"copper_arrow") as ArrowItemDefinition]
	_expect(not CombatInventoryRules.has_ready_weapon(armed_inventory), "unlisted ammunition made an authored bow usable")
	_expect(InventoryTestFixture.restore_slot(armed_inventory, InventoryModel.HOTBAR_SIZE + 1, InventoryStack.new(&"copper_arrow", 10)), "authored ammunition fixture could not add copper arrows")
	_expect(CombatInventoryRules.has_ready_weapon(armed_inventory), "authored bow ammunition did not make the weapon usable")
	await _destroy_fixture(armed)

func _create_fixture(initial_time: float, weapon_id: StringName = &"", ammunition_id: StringName = &"") -> Dictionary:
	var holder := Node.new()
	root.add_child(holder)
	var item_catalog := (load("res://items/item_catalog.tres") as ItemCatalog).duplicate(true) as ItemCatalog
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	inventory.setup_empty()
	if not weapon_id.is_empty():
		_expect(InventoryTestFixture.restore_slot(inventory, 0, InventoryStack.new(weapon_id, 1, inventory.equipment_instance_factory.create(weapon_id))), "sundown fixture weapon could not be restored")
	if not ammunition_id.is_empty():
		_expect(InventoryTestFixture.restore_slot(inventory, InventoryModel.HOTBAR_SIZE, InventoryStack.new(ammunition_id, 10)), "sundown fixture ammunition could not be restored")
	var view := SundownWeaponTutorialView.new()
	holder.add_child(view)
	var coordinator := SundownWeaponTutorialCoordinator.new()
	holder.add_child(coordinator)
	var progress := TutorialProgress.new()
	_expect(progress.restore({
		"mining_tip_completed": true,
		"food_tip_completed": true,
		"crafting_tip_completed": true,
		"crafting_ingredients_tip_completed": true,
		"copper_mining_tip_completed": true,
		"sundown_weapon_tip_completed": false, "damage_affinity_tip_completed": false,
	}), "sundown tutorial progress setup failed")
	var arbiter := TutorialCalloutArbiter.new()
	var time := [initial_time]
	await process_frame
	coordinator.setup(inventory, view, progress, arbiter, func() -> float: return float(time[0]))
	coordinator.set_process(false)
	view.set_process(false)
	return {
		"holder": holder,
		"inventory": inventory,
		"view": view,
		"coordinator": coordinator,
		"progress": progress,
		"arbiter": arbiter,
		"time": time,
	}

func _destroy_fixture(fixture: Dictionary) -> void:
	(fixture["holder"] as Node).free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[sundown_weapon_tutorial_integration] FAIL: %s" % message)
