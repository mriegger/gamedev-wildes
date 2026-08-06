extends SceneTree

var _errors: Array[String] = []

func _init():
	print("[animation_tuning] starting")
	call_deferred("_run")

func _run():
	var player_scene = load("res://player/player.tscn") as PackedScene
	var panel_scene = load("res://player/debug/animation_tuning_panel.tscn") as PackedScene
	var player = player_scene.instantiate() as PlayerMotor
	var panel = panel_scene.instantiate()
	root.add_child(player)
	root.add_child(panel)
	await process_frame
	player.animation_driver.setup(player, player.interactor)
	panel.setup(player)
	panel.show_panel()
	var panel_control = panel.get_node("Panel") as Panel
	_expect(panel_control.size.x <= 420.0, "animation panel is too wide to keep the character visible")
	var profile = player.animation_driver.animator.profile
	_expect(is_equal_approx(player.gravity, 30.0), "exported gravity was not adopted as the default")
	_expect(is_equal_approx(profile.walk_cycle_seconds, 0.65), "exported walk cycle was not adopted as the default")
	_expect(is_equal_approx(profile.walk_leg_lift, 0.18), "exported walk leg lift was not adopted as the default")
	_expect(is_equal_approx(profile.sprint_leg_lift, 0.40), "exported sprint leg lift was not adopted as the default")
	_expect(is_equal_approx(profile.sprint_lean_degrees, 8.0), "exported sprint lean was not adopted as the default")
	var input_buffer = InputBuffer.new()
	player._input_buffer = input_buffer
	player.on_ground = true
	input_buffer.jump_just = true
	for _frame in range(12):
		player._handle_movement(1.0 / 60.0)
	_expect(player.velocity.y <= 0.0 and player._jump_windup_remaining <= 0.0 and not player._jump_ready, "jump windup launched after grounding was lost")
	player.velocity = Vector3.ZERO
	var default_bob = profile.sprint_bob_height
	var move_speed_control = panel.find_child("character__move_speed", true, false) as SpinBox
	var gait_hold_control = panel.find_child("animation__gait_contact_hold", true, false) as SpinBox
	_expect(move_speed_control.min_value > 0.0 and not move_speed_control.allow_lesser, "movement speed control permits an invalid zero divisor")
	_expect(not gait_hold_control.allow_greater, "declared animation ranges are not enforced by the tuner")
	var sprint_bob_control = panel.find_child("animation__sprint_bob_height", true, false) as SpinBox
	_expect(sprint_bob_control != null, "sprint bob control was not generated")
	if sprint_bob_control != null:
		sprint_bob_control.value = default_bob + 0.123
		_expect(is_equal_approx(profile.sprint_bob_height, default_bob + 0.123), "animation value did not update live")
	var part_selector = panel.get_node("Panel/VBox/Tabs/Parts/VBox/PartSelector") as OptionButton
	part_selector.select(3)
	part_selector.item_selected.emit(3)
	var position_x = panel.get_node("Panel/VBox/Tabs/Parts/VBox/TransformGrid/PositionX") as SpinBox
	position_x.value = 0.125
	var arm_transform = player.animation_driver.animator.get_tuning_transform(BlockyHumanoidAnimator.TUNING_LEFT_ARM)
	_expect(is_equal_approx((arm_transform["position"] as Vector3).x, 0.125), "left arm position did not update live")
	var preview_selector = panel.get_node("Panel/VBox/PreviewRow/PreviewSelector") as OptionButton
	preview_selector.select(3)
	preview_selector.item_selected.emit(3)
	for _frame in range(24):
		await process_frame
	_expect(player.animation_driver.animator.get_current_state() == BlockyHumanoidAnimator.SPRINT, "sprint preview did not play selected=%s driver=%s current=%s" % [preview_selector.get_item_text(preview_selector.selected), String(player.animation_driver._preview_state), String(player.animation_driver.animator.get_current_state())])
	_expect(is_equal_approx(player.animation_driver.animator.left_arm_action.position.x, 0.125), "left arm tuning did not reach the rendered rig")
	var export_path = ProjectSettings.globalize_path("user://animation_tuning_panel_test.json")
	var export_error = panel.export_values_to_path(export_path)
	_expect(export_error == OK, "panel export failed")
	if export_error == OK:
		var export_file = FileAccess.open(export_path, FileAccess.READ)
		var exported = JSON.parse_string(export_file.get_as_text()) as Dictionary
		_expect(exported.get("format", "") == "wildes_player_animation", "export format identifier missing")
		_expect(is_equal_approx(float((exported["animation"] as Dictionary)["sprint_bob_height"]), default_bob + 0.123), "exported animation value was not exact")
		var exported_arm = (exported["parts"] as Dictionary)["Left Arm"] as Dictionary
		_expect(is_equal_approx(float((exported_arm["position"] as Array)[0]), 0.125), "exported arm transform was not exact")
		DirAccess.remove_absolute(export_path)
	var reset_button = panel.get_node("Panel/VBox/Footer/ResetButton") as Button
	reset_button.pressed.emit()
	_expect(is_equal_approx(profile.sprint_bob_height, default_bob), "reset did not restore animation defaults")
	arm_transform = player.animation_driver.animator.get_tuning_transform(BlockyHumanoidAnimator.TUNING_LEFT_ARM)
	_expect((arm_transform["position"] as Vector3).is_zero_approx(), "reset did not restore part transforms")
	panel.hide_panel()
	_expect(not panel.visible, "panel did not close")
	_expect(player.animation_driver._preview_state == PlayerAnimationDriver.PREVIEW_LIVE, "closing panel did not restore live preview")
	panel.queue_free()
	player.queue_free()
	await process_frame
	await process_frame
	var orphan_count = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "orphan count ended at %d" % orphan_count)
	if _errors.is_empty():
		print("ANIMATION_TUNING PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("ANIMATION_TUNING FAIL %s" % str(_errors))
		quit(1)

func _expect(condition: bool, message: String):
	if not condition:
		print("[animation_tuning] ERROR: %s" % message)
		print("FAIL: %s" % message)
		_errors.append(message)
