extends SceneTree

var _failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_resistant_hit_pauses_with_dynamic_dialog()
	await _test_resistant_projectile_hit_pauses()
	await _test_non_resistant_and_completed_hits_are_ignored()
	if _failures == 0:
		print("COMBAT_AFFINITY_TUTORIAL PASS")
		quit(0)
	else:
		print("COMBAT_AFFINITY_TUTORIAL FAIL failures=%d" % _failures)
		quit(1)

func _test_resistant_hit_pauses_with_dynamic_dialog() -> void:
	var fixture := await _create_fixture(false)
	var combat := fixture["combat"] as MeleeCombatCoordinator
	var coordinator := fixture["coordinator"] as CombatAffinityTutorialCoordinator
	var view := fixture["view"] as CombatAffinityTutorialView
	var progress := fixture["progress"] as TutorialProgress
	var arbiter := fixture["arbiter"] as TutorialCalloutArbiter
	var paused := fixture["paused"] as Array
	var other_owner := Node.new()
	(fixture["holder"] as Node).add_child(other_owner)
	var other_dismissed := [false]
	_expect(arbiter.try_acquire(other_owner, func() -> void:
		other_dismissed[0] = true
		arbiter.release(other_owner)
	), "affinity fixture could not acquire the initial callout")
	combat.melee_outcome_committed.emit(_make_outcome(&"skeleton", DamageAffinityDefinition.Response.RESISTANT))
	coordinator._process(0.0)
	_expect(bool(other_dismissed[0]), "resistance dialog did not dismiss the active callout")
	_expect(view.is_showing() and bool(paused[0]), "resistance dialog did not show and pause gameplay")
	_expect(progress.is_damage_affinity_tip_completed(), "shown resistance dialog was not persisted")
	var panel := view.get_node("Content/DialogPanel") as Panel
	var content := view.get_node("Content/DialogPanel/Content") as VBoxContainer
	var text := view.get_node("Content/DialogPanel/Content/Instructions") as RichTextLabel
	var ok_button := view.get_node("Content/DialogPanel/Content/OkButton") as WildesButton
	var viewport_size := root.get_visible_rect().size
	_expect(is_equal_approx(panel.position.x + panel.size.x * 0.5, viewport_size.x * 0.5), "resistance dialog is not horizontally centered")
	_expect(panel.position.y + panel.size.y < viewport_size.y * 0.5 + 1.0, "resistance dialog obscures the center of the screen")
	var weakness_color := CombatPresentationPalette.WEAK_DAMAGE_COLOR.to_html(false)
	var resistance_color := CombatPresentationPalette.RESISTANT_DAMAGE_COLOR.to_html(false)
	_expect(text.text.begins_with("[center]") and text.text.ends_with("[/center]"), "resistance dialog text is not center aligned")
	_expect("[b][color=#%s]weakness[/color][/b]" % weakness_color in text.text, "weakness explanation is not bold and color coded")
	_expect("[b][color=#%s]resistance[/color][/b]" % resistance_color in text.text, "resistance explanation is not bold and color coded")
	_expect("For example, Skeletons are resistant to [b][color=#%s]slash[/color][/b] damage, but weak to [b][color=#%s]blunt[/color][/b] damage." % [resistance_color, weakness_color] in text.text, "skeleton affinity explanation does not lead with the triggering resistance")
	_expect("Neutral attacks show white numbers." not in text.text, "removed neutral-damage sentence is still present")
	_expect("Try experimenting with different weapon types against different enemies.[/center]" in text.text, "resistance dialog closing sentence changed")
	_expect(ok_button.custom_minimum_size == Vector2(120.0, 40.0) and ok_button.button_font_size == 15, "resistance dialog OK button size changed")
	_expect(is_zero_approx((view.get_node("Content") as Control).modulate.a), "resistance dialog did not begin transparent")
	view._process(CombatAffinityTutorialView.FADE_DURATION)
	_expect(is_equal_approx((view.get_node("Content") as Control).modulate.a, 1.0), "resistance dialog did not fade in")
	await process_frame
	_expect(text.fit_content and text.size_flags_vertical == Control.SIZE_SHRINK_BEGIN, "resistance instructions retained an expanding empty text area")
	var expected_button_gap := roundi(WildesStyle.REGULAR_FONT.get_height(16))
	_expect(content.get_theme_constant("separation") == expected_button_gap, "resistance dialog text-to-button gap does not match one line of text")
	_expect(is_equal_approx(ok_button.position.y - (text.position.y + text.size.y), float(expected_button_gap)), "resistance dialog text-to-button gap does not match its authored spacing")
	_expect(is_equal_approx(content.offset_left, CombatAffinityTutorialView.HORIZONTAL_PADDING) and is_equal_approx(content.offset_top, CombatAffinityTutorialView.VERTICAL_PADDING), "resistance dialog content padding changed")
	_expect(is_equal_approx(panel.size.y, text.size.y + float(expected_button_gap) + ok_button.size.y + CombatAffinityTutorialView.VERTICAL_PADDING * 2.0), "resistance dialog retained empty space below the OK button")
	var original_window_size := root.size
	var original_content_scale_size := root.content_scale_size
	root.content_scale_size = Vector2i(640, 480)
	root.size = Vector2i(640, 480)
	await process_frame
	_expect(panel.position.x >= CombatAffinityTutorialView.SCREEN_MARGIN - 0.1, "resistance dialog clips the left edge at 640px")
	_expect(panel.position.x + panel.size.x * panel.scale.x <= 640.0 - CombatAffinityTutorialView.SCREEN_MARGIN + 0.1, "resistance dialog clips the right edge at 640px")
	_expect(panel.scale.x < 1.0 and is_equal_approx(panel.scale.x, panel.scale.y), "short viewport did not scale the resistance dialog uniformly")
	_expect(panel.position.y + panel.size.y * panel.scale.y <= 240.0 - CombatAffinityTutorialView.SCREEN_MARGIN + 0.1, "resistance dialog obscures the center at 480px height")
	root.content_scale_size = original_content_scale_size
	root.size = original_window_size
	await process_frame
	view._on_ok_pressed()
	_expect(not view.is_showing() and bool(paused[0]), "OK resumed gameplay before the resistance dialog faded out")
	view._process(CombatAffinityTutorialView.FADE_DURATION)
	_expect(not (view.get_node("Content") as Control).visible and not bool(paused[0]), "resistance dialog did not fade out and resume gameplay")
	_expect(arbiter.is_available(other_owner), "resistance dialog did not release the shared callout")
	other_owner.queue_free()
	await _destroy_fixture(fixture)

func _test_non_resistant_and_completed_hits_are_ignored() -> void:
	var fixture := await _create_fixture(false)
	var combat := fixture["combat"] as MeleeCombatCoordinator
	var view := fixture["view"] as CombatAffinityTutorialView
	var paused := fixture["paused"] as Array
	combat.melee_outcome_committed.emit(_make_outcome(&"zombie", DamageAffinityDefinition.Response.WEAK))
	_expect(not view.is_showing() and not bool(paused[0]), "weak hit showed the resistance tutorial")
	combat.melee_outcome_committed.emit(_make_outcome(&"skeleton", DamageAffinityDefinition.Response.RESISTANT, 8))
	_expect(not view.is_showing() and not bool(paused[0]), "enemy attack showed the resistance tutorial")
	await _destroy_fixture(fixture)
	var completed_fixture := await _create_fixture(true)
	(completed_fixture["combat"] as MeleeCombatCoordinator).melee_outcome_committed.emit(_make_outcome(&"skeleton", DamageAffinityDefinition.Response.RESISTANT))
	_expect(not (completed_fixture["view"] as CombatAffinityTutorialView).is_showing(), "completed resistance tutorial appeared again")
	var golem := (completed_fixture["entity_catalog"] as EntityCatalog).get_definition(&"stone_golem")
	var text := CombatAffinityTutorialCoordinator.build_dialog_text(golem)
	_expect("For example, Stone Golems are resistant to" in text and "weak to" not in text, "enemy without weaknesses received an incorrect example sentence")
	_expect("slash" in text and "pierce" in text, "multiple stone golem resistances were omitted")
	await _destroy_fixture(completed_fixture)

func _test_resistant_projectile_hit_pauses() -> void:
	var fixture := await _create_fixture(false)
	var combat := fixture["combat"] as MeleeCombatCoordinator
	combat.projectile_outcome_committed.emit(_make_projectile_outcome(&"stone_golem", DamageAffinityDefinition.Response.RESISTANT))
	_expect((fixture["view"] as CombatAffinityTutorialView).is_showing(), "resistant projectile hit did not show the affinity tutorial")
	_expect(bool((fixture["paused"] as Array)[0]), "resistant projectile hit did not pause gameplay")
	await _destroy_fixture(fixture)

func _create_fixture(completed: bool) -> Dictionary:
	var holder := Node.new()
	root.add_child(holder)
	var combat := MeleeCombatCoordinator.new()
	holder.add_child(combat)
	var view := CombatAffinityTutorialView.new()
	holder.add_child(view)
	var coordinator := CombatAffinityTutorialCoordinator.new()
	holder.add_child(coordinator)
	var progress := TutorialProgress.new()
	_expect(progress.restore({
		"mining_tip_completed": true,
		"food_tip_completed": true,
		"crafting_tip_completed": true,
		"crafting_ingredients_tip_completed": true,
		"copper_mining_tip_completed": true,
		"sundown_weapon_tip_completed": true,
		"damage_affinity_tip_completed": completed,
	}), "combat affinity tutorial progress setup failed")
	var entity_catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	var arbiter := TutorialCalloutArbiter.new()
	var paused := [false]
	await process_frame
	coordinator.setup(
		combat,
		entity_catalog,
		view,
		progress,
		arbiter,
		func() -> void: paused[0] = true,
		func() -> void: paused[0] = false,
	)
	coordinator.set_process(false)
	return {
		"holder": holder,
		"combat": combat,
		"view": view,
		"coordinator": coordinator,
		"progress": progress,
		"entity_catalog": entity_catalog,
		"arbiter": arbiter,
		"paused": paused,
	}

func _make_outcome(target_definition_id: StringName, response: int, source_runtime_id: int = MeleeCombatCoordinator.PLAYER_RUNTIME_ID) -> MeleeOutcome:
	var contact := MeleeContact.new(
		source_runtime_id,
		&"player" if source_runtime_id == MeleeCombatCoordinator.PLAYER_RUNTIME_ID else &"skeleton",
		12,
		target_definition_id,
		&"test_attack",
		Vector3.ZERO,
		Vector3.FORWARD,
	)
	return MeleeOutcome.new(contact, &"copper_sword", 5.0, false, response)

func _make_projectile_outcome(target_definition_id: StringName, response: int) -> ProjectileOutcome:
	var contact := ProjectileContact.new(12, target_definition_id, Vector3.ZERO, Vector3.FORWARD)
	return ProjectileOutcome.new(contact, &"stone_arrow", 5.0, false, response)

func _destroy_fixture(fixture: Dictionary) -> void:
	(fixture["holder"] as Node).free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[combat_affinity_tutorial_integration] FAIL: %s" % message)
