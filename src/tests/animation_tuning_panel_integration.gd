extends SceneTree

var _errors: Array[String] = []

func _init():
	print("[animation_tuning] starting")
	call_deferred("_run")

func _run():
	var player_scene = load("res://player/player.tscn") as PackedScene
	var panel_scene = load("res://player/debug/animation_tuning_panel.tscn") as PackedScene
	var player = player_scene.instantiate() as PlayerMotor
	var panel = panel_scene.instantiate() as AnimationTuningPanel
	root.add_child(player)
	root.add_child(panel)
	await process_frame
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var inventory := InventoryModel.new(item_catalog)
	inventory.setup_starter()
	player.held_item_view.setup(inventory)
	player.animation_driver.setup(player, player.interactor)
	panel.setup(player)
	panel.show_panel()
	var attack_action: MeleeAttackActionDefinition = player.animation_driver.get_attack_preview_action()
	var panel_control = panel.get_node("Panel") as Panel
	_expect(panel_control.size.x <= 420.0, "animation panel is too wide to keep the character visible")
	var profile = player.animation_driver.animator.profile
	_expect(is_equal_approx(player.gravity, 30.0), "exported gravity was not adopted as the default")
	_expect(is_equal_approx(profile.walk_cycle_seconds, 0.65), "exported walk cycle was not adopted as the default")
	_expect(is_equal_approx(profile.walk_leg_lift, 0.18), "exported walk leg lift was not adopted as the default")
	_expect(is_equal_approx(profile.sprint_leg_lift, 0.40), "exported sprint leg lift was not adopted as the default")
	_expect(is_equal_approx(profile.sprint_lean_degrees, 8.0), "exported sprint lean was not adopted as the default")
	_expect(is_equal_approx(profile.attack_windup_degrees, 52.0), "exported attack windup was not adopted as the default")
	_expect(is_equal_approx(profile.attack_follow_through_degrees, 76.0), "exported attack follow-through was not adopted as the default")
	_expect(is_equal_approx(profile.attack_right_arm_pitch_degrees, -120.0), "exported attack arm pitch was not adopted as the default")
	_expect(is_equal_approx(profile.attack_body_lean_degrees, 0.0), "exported attack body lean was not adopted as the default")
	_expect(is_equal_approx(profile.attack_body_twist_degrees, 60.0), "exported attack body twist was not adopted as the default")
	_expect(is_equal_approx(profile.attack_leg_brace_degrees, 0.0), "exported attack leg brace was not adopted as the default")
	_expect(is_equal_approx(profile.attack_crouch_depth, 0.0), "exported attack crouch was not adopted as the default")
	_expect(attack_action.held_position_offset.is_equal_approx(Vector3(0.0, 0.1125, 0.0)), "exported attack item position was not adopted as the default")
	_expect(attack_action.held_rotation_degrees.is_equal_approx(Vector3(0.0, -113.6, 0.0)), "exported attack item rotation was not adopted as the default")
	var input_buffer = InputBuffer.new()
	player._input_buffer = input_buffer
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	player.voxel_world = VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
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
	var default_attack_position: Vector3 = attack_action.held_position_offset
	var default_attack_rotation: Vector3 = attack_action.held_rotation_degrees
	var attack_position_x = panel.get_node("Panel/VBox/Tabs/Attack/VBox/TransformGrid/PositionX") as SpinBox
	var attack_position_y = panel.get_node("Panel/VBox/Tabs/Attack/VBox/TransformGrid/PositionY") as SpinBox
	var attack_position_z = panel.get_node("Panel/VBox/Tabs/Attack/VBox/TransformGrid/PositionZ") as SpinBox
	var attack_position_slider_x = panel.get_node("Panel/VBox/Tabs/Attack/VBox/PositionSliderGrid/PositionXSlider") as HSlider
	var attack_position_slider_y = panel.get_node("Panel/VBox/Tabs/Attack/VBox/PositionSliderGrid/PositionYSlider") as HSlider
	var attack_position_slider_z = panel.get_node("Panel/VBox/Tabs/Attack/VBox/PositionSliderGrid/PositionZSlider") as HSlider
	var attack_rotation_x = panel.get_node("Panel/VBox/Tabs/Attack/VBox/TransformGrid/RotationX") as SpinBox
	var attack_rotation_y = panel.get_node("Panel/VBox/Tabs/Attack/VBox/TransformGrid/RotationY") as SpinBox
	var attack_rotation_z = panel.get_node("Panel/VBox/Tabs/Attack/VBox/TransformGrid/RotationZ") as SpinBox
	var attack_rotation_slider_x = panel.get_node("Panel/VBox/Tabs/Attack/VBox/RotationSliderGrid/RotationXSlider") as HSlider
	var attack_rotation_slider_y = panel.get_node("Panel/VBox/Tabs/Attack/VBox/RotationSliderGrid/RotationYSlider") as HSlider
	var attack_rotation_slider_z = panel.get_node("Panel/VBox/Tabs/Attack/VBox/RotationSliderGrid/RotationZSlider") as HSlider
	attack_position_slider_x.value = default_attack_position.x + 0.075
	attack_position_slider_y.value = default_attack_position.y + 0.025
	attack_position_slider_z.value = default_attack_position.z - 0.04
	_expect(is_equal_approx(attack_position_x.value, attack_position_slider_x.value), "attack position X slider did not update its numeric field")
	_expect(is_equal_approx(attack_position_y.value, attack_position_slider_y.value), "attack position Y slider did not update its numeric field")
	_expect(is_equal_approx(attack_position_z.value, attack_position_slider_z.value), "attack position Z slider did not update its numeric field")
	attack_position_z.value = default_attack_position.z - 0.03
	_expect(is_equal_approx(attack_position_slider_z.value, attack_position_z.value), "attack position numeric field did not update its slider")
	attack_rotation_slider_x.value = -12.0
	attack_rotation_slider_y.value = 18.0
	attack_rotation_slider_z.value = 24.0
	_expect(is_equal_approx(attack_rotation_x.value, attack_rotation_slider_x.value), "attack rotation X slider did not update its numeric field")
	_expect(is_equal_approx(attack_rotation_y.value, attack_rotation_slider_y.value), "attack rotation Y slider did not update its numeric field")
	_expect(is_equal_approx(attack_rotation_z.value, attack_rotation_slider_z.value), "attack rotation Z slider did not update its numeric field")
	attack_rotation_z.value = 20.0
	_expect(is_equal_approx(attack_rotation_slider_z.value, attack_rotation_z.value), "attack rotation numeric field did not update its slider")
	_expect(attack_action.held_position_offset.is_equal_approx(Vector3(default_attack_position.x + 0.075, default_attack_position.y + 0.025, default_attack_position.z - 0.03)), "attack XYZ sliders did not update the sword position live")
	_expect(attack_action.held_rotation_degrees.is_equal_approx(Vector3(-12.0, 18.0, 20.0)), "attack XYZ sliders did not update the sword rotation live")
	player.animation_driver.set_process(false)
	var attack_preview_index: int = preview_selector.item_count - 1
	_expect(preview_selector.get_item_text(attack_preview_index) == String(PlayerAnimationDriver.PREVIEW_ATTACK), "attack preview is missing from the selector")
	preview_selector.select(attack_preview_index)
	preview_selector.item_selected.emit(attack_preview_index)
	var tabs = panel.get_node("Panel/VBox/Tabs") as TabContainer
	_expect(tabs.get_tab_title(tabs.current_tab) == "Attack", "attack preview did not open its tuning screen")
	_expect(player.held_item_view.held_node is PixelExtrudedItem, "attack preview did not display a held sword")
	var preview_sword := player.held_item_view.held_node as PixelExtrudedItem
	_expect(preview_sword.texture == panel.attack_preview_item.icon, "attack preview displayed the wrong held item")
	var resting_socket_position: Vector3 = player.held_item_view._rest_position
	var resting_socket_rotation: Vector3 = player.held_item_view._rest_rotation
	var pause_button := panel.get_node("Panel/VBox/Tabs/Attack/VBox/PlaybackRow/PauseButton") as CheckButton
	var progress_slider := panel.get_node("Panel/VBox/Tabs/Attack/VBox/PlaybackRow/ProgressSlider") as HSlider
	var progress_label := panel.get_node("Panel/VBox/Tabs/Attack/VBox/PlaybackRow/ProgressLabel") as Label
	_expect(not pause_button.disabled and progress_slider.editable, "attack playback controls were not enabled")
	progress_slider.value = 0.5
	_expect(pause_button.button_pressed and player.animation_driver._attack_preview_paused, "scrubbing did not pause the attack preview")
	_expect(is_equal_approx(player.animation_driver.get_attack_preview_progress(), 0.5), "attack preview did not seek to the slider position")
	_expect(progress_label.text == "50%", "attack progress label did not show the paused point")
	_expect(player.animation_driver.animator.attack_pose_weight > 0.99, "attack preview did not reach the middle of the swing")
	_expect(player.held_item_view.position.is_equal_approx(resting_socket_position + attack_action.held_position_offset), "attack preview did not apply the tuned sword position")
	_expect(is_equal_approx(player.held_item_view.rotation.y, resting_socket_rotation.y + deg_to_rad(18.0)), "attack preview did not apply the tuned sword rotation")
	var paused_arm_rotation: Vector3 = player.animation_driver.animator.right_arm_action.rotation
	player.animation_driver._process(0.2)
	_expect(is_equal_approx(player.animation_driver.get_attack_preview_progress(), 0.5), "paused attack preview advanced")
	_expect(player.animation_driver.animator.right_arm_action.rotation.is_equal_approx(paused_arm_rotation), "paused attack pose changed")
	pause_button.set_pressed_no_signal(false)
	pause_button.toggled.emit(false)
	player.animation_driver._process(attack_action.attack_duration * 0.5 + 0.01)
	_expect(player.animation_driver.animator._attack_direction == 1, "attack preview did not alternate swing directions")
	preview_selector.select(3)
	preview_selector.item_selected.emit(3)
	_expect(pause_button.disabled and not progress_slider.editable, "attack playback controls stayed enabled outside attack preview")
	_expect(player.held_item_view.held_node is PixelExtrudedItem, "leaving attack preview did not restore the selected held item")
	var restored_pickaxe := player.held_item_view.held_node as PixelExtrudedItem
	_expect(restored_pickaxe.texture == item_catalog.get_definition(&"copper_pickaxe").icon, "leaving attack preview did not restore the pickaxe")
	_expect(player.held_item_view.position.is_equal_approx(resting_socket_position), "leaving attack preview did not restore the held-item position")
	_expect(player.held_item_view.rotation.is_equal_approx(resting_socket_rotation), "leaving attack preview did not restore the held-item rotation")
	var export_path = ProjectSettings.globalize_path("user://animation_tuning_panel_test.json")
	var export_error = panel.export_values_to_path(export_path)
	_expect(export_error == OK, "panel export failed")
	if export_error == OK:
		var export_file = FileAccess.open(export_path, FileAccess.READ)
		var exported = JSON.parse_string(export_file.get_as_text()) as Dictionary
		_expect(exported.get("format", "") == "wildes_player_animation", "export format identifier missing")
		_expect(int(exported.get("version", 0)) == 2, "attack tuning export version changed")
		_expect(is_equal_approx(float((exported["animation"] as Dictionary)["sprint_bob_height"]), default_bob + 0.123), "exported animation value was not exact")
		var exported_attack = exported["held_item_attack"] as Dictionary
		_expect(is_equal_approx(float((exported_attack["position_offset"] as Array)[0]), default_attack_position.x + 0.075), "exported attack sword position was not exact")
		_expect(is_equal_approx(float((exported_attack["rotation_degrees"] as Array)[1]), 18.0), "exported attack sword rotation was not exact")
		var exported_arm = (exported["parts"] as Dictionary)["Left Arm"] as Dictionary
		_expect(is_equal_approx(float((exported_arm["position"] as Array)[0]), 0.125), "exported arm transform was not exact")
		DirAccess.remove_absolute(export_path)
	var reset_button = panel.get_node("Panel/VBox/Footer/ResetButton") as Button
	reset_button.pressed.emit()
	_expect(is_equal_approx(profile.sprint_bob_height, default_bob), "reset did not restore animation defaults")
	arm_transform = player.animation_driver.animator.get_tuning_transform(BlockyHumanoidAnimator.TUNING_LEFT_ARM)
	_expect((arm_transform["position"] as Vector3).is_zero_approx(), "reset did not restore part transforms")
	_expect(attack_action.held_position_offset.is_equal_approx(default_attack_position), "reset did not restore attack sword position")
	_expect(attack_action.held_rotation_degrees.is_equal_approx(default_attack_rotation), "reset did not restore attack sword rotation")
	_expect(is_equal_approx(attack_position_slider_x.value, default_attack_position.x) and is_equal_approx(attack_position_slider_y.value, default_attack_position.y) and is_equal_approx(attack_position_slider_z.value, default_attack_position.z), "reset did not restore attack position sliders")
	_expect(is_equal_approx(attack_rotation_slider_x.value, default_attack_rotation.x) and is_equal_approx(attack_rotation_slider_y.value, default_attack_rotation.y) and is_equal_approx(attack_rotation_slider_z.value, default_attack_rotation.z), "reset did not restore attack rotation sliders")
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
