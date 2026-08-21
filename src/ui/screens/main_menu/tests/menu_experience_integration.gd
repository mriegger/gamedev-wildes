extends SceneTree

var _errors: Array[String] = []
var _menu: MenuExperience

const EXPECTED_ACTOR_COUNT := 14

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var saves_before := _snapshot_saves()
	var menu_scene := load("res://ui/screens/main_menu/menu_experience.tscn") as PackedScene
	_expect(menu_scene != null, "menu experience scene did not load")
	if menu_scene == null:
		_finish()
		return
	var settings := GameSettings.new()
	_menu = menu_scene.instantiate() as MenuExperience
	menu_scene = null
	_menu.setup(settings, MenuExperience.EntryMode.FIRST_LAUNCH)
	root.add_child(_menu)
	await process_frame
	_expect(is_equal_approx(_menu.world_cover.modulate.a, 1.0), "startup did not begin on black")
	_expect(is_zero_approx(_menu.main_menu.logo.modulate.a), "startup logo was visible on the first frame")
	_expect(is_zero_approx(_menu.main_menu.loading_bar.modulate.a), "startup loading bar was visible before the logo")
	_expect(not _menu.main_menu.loading_bar.visible, "startup loading bar was accessible before the logo")
	_expect(not _menu.main_menu.loading_bar.show_percentage, "startup loading bar displayed percentage text")
	for button in [_menu.main_menu.play_button, _menu.main_menu.settings_button]:
		_expect(button.disabled, "%s was enabled during startup" % button.name)
		_expect(button.get_theme_stylebox(&"disabled") is StyleBoxEmpty, "%s displayed a disabled background during its fade" % button.name)
		_expect(button.get_theme_color(&"font_disabled_color").is_equal_approx(button.get_theme_color(&"font_color")), "%s changed text color when the intro enabled it" % button.name)
	var expected_bar_width := minf(
		clampf(
			_menu.main_menu.size.x * MainMenu.LOADING_BAR_WIDTH_RATIO,
			MainMenu.LOADING_BAR_MIN_WIDTH,
			MainMenu.LOADING_BAR_MAX_WIDTH,
		),
		maxf(_menu.main_menu.size.x - MainMenu.LOADING_BAR_HORIZONTAL_MARGIN, 4.0),
	)
	_expect(is_equal_approx(_menu.main_menu.loading_bar.size.x, expected_bar_width), "startup loading bar width was not responsive")
	_expect(_menu.main_menu.loading_bar.size.y <= 4.0, "startup loading bar was not thin")
	_expect(
		is_equal_approx(_menu.main_menu.loading_bar.get_global_rect().get_center().x, _menu.main_menu.logo.get_global_rect().get_center().x),
		"startup loading bar was not centered beneath the logo",
	)
	_expect(
		_menu.main_menu.loading_bar.global_position.y > _menu.main_menu.logo.get_global_rect().end.y,
		"startup loading bar was not below the logo",
	)
	_expect(not _menu.is_ready_for_input(), "startup controls were enabled too early")
	var music_deadline := Time.get_ticks_msec() + 500
	while not _menu.is_music_playing() and Time.get_ticks_msec() < music_deadline:
		await process_frame
	_expect(_menu.is_music_playing(), "menu music did not start over black")
	_expect(_menu.music_player.bus == &"Music", "menu music did not use the Music bus")
	_expect(not _contains_gameplay_node(_menu), "menu instantiated gameplay-only nodes")
	var logo_deadline := Time.get_ticks_msec() + 3000
	while _menu.main_menu.logo.modulate.a <= 0.0 and Time.get_ticks_msec() < logo_deadline:
		await process_frame
	_expect(_menu.main_menu.logo.modulate.a > 0.0, "logo fade never started")
	_expect(_menu.main_menu.loading_bar.modulate.a > 0.0, "loading bar did not fade in with the logo")
	_expect(_menu.main_menu.loading_bar.visible, "loading bar was hidden while the logo faded in")
	_expect(
		is_equal_approx(_menu.main_menu.loading_bar.modulate.a, _menu.main_menu.logo.modulate.a),
		"loading bar and logo fades diverged",
	)
	var skip_event := InputEventKey.new()
	skip_event.keycode = KEY_SPACE
	skip_event.pressed = true
	root.push_input(skip_event)
	await process_frame
	if not bool(_menu.get("_world_ready")):
		_expect(is_equal_approx(_menu.world_cover.modulate.a, 1.0), "skip exposed the world before generation completed")
	var cinematic_started_during_skip_reveal := false
	var ready_deadline := Time.get_ticks_msec() + 60000
	while not _menu.is_ready_for_input() and Time.get_ticks_msec() < ready_deadline:
		await process_frame
		if _menu.world_cover.modulate.a < 1.0 and _menu.world_cover.modulate.a > 0.0:
			cinematic_started_during_skip_reveal = (
				_menu.is_processing()
				and _menu.population.is_physics_processing()
				and not _menu.population.is_processing()
				and float(_menu.get("_shot_elapsed")) > 0.0
			)
	_expect(_menu.is_ready_for_input(), "menu did not become interactive")
	if not _menu.is_ready_for_input():
		await _teardown_and_finish()
		return
	_expect(is_zero_approx(_menu.world_cover.modulate.a), "world remained covered after the intro")
	_expect(cinematic_started_during_skip_reveal, "skipped intro did not animate during its world reveal")
	_expect(is_equal_approx(_menu.main_menu.loading_bar.value, 100.0), "startup loading bar did not complete")
	_expect(is_zero_approx(_menu.main_menu.loading_bar.modulate.a), "startup loading bar remained over the cinematic")
	_expect(not _menu.main_menu.loading_bar.visible, "completed startup loading bar remained accessible")
	_expect(is_equal_approx(_menu.main_menu.controls.modulate.a, 1.0), "menu controls did not finish fading in")
	_expect(is_equal_approx(_menu.main_menu.logo_shadow.modulate.a, 1.0), "logo shadow did not fade with the logo")
	_expect(not _menu.main_menu.play_button.has_theme_constant_override(&"outline_size"), "Play retained a text outline")
	_expect(not _menu.main_menu.settings_button.has_theme_constant_override(&"outline_size"), "Settings retained a text outline")
	_expect(not _menu.main_menu.credits.has_theme_constant_override(&"outline_size"), "team credit retained a text outline")
	_expect(_menu.main_menu.credits.text == "Justin Soberano-Borbonio     Fatai Fakoya     Michael Riegger     Daniel Dakev     Jason Jahn", "menu team credit changed")
	_expect(_menu.get_current_shot_id() == &"sunrise_meadow", "menu did not start on the first authored shot")
	_expect(_menu.population.get_runtime().get_active_count() == EXPECTED_ACTOR_COUNT, "curated population count changed")
	_expect(_menu.population.get_runtime().get_population_cost() <= MenuCinematicProfile.MAX_TOTAL_POPULATION_COST, "curated population exceeded its cost bound")
	for actor in _menu.population.get_runtime().get_active_actors():
		_expect(is_equal_approx(actor.get_visual_opacity(), 1.0), "%s was not fully visible when the world reveal finished" % actor.definition.id)
	_expect_presentation_only_actors()
	await _verify_settings(settings)
	await _verify_shot_transition()
	await _verify_play_and_resume()
	_expect(_snapshot_saves() == saves_before, "menu lifecycle mutated save data")
	await _teardown_and_finish()

func _verify_settings(settings: GameSettings) -> void:
	var settings_emissions := [0]
	_menu.settings_changed.connect(func(_updated: GameSettings): settings_emissions[0] += 1)
	_menu.main_menu.settings_button.pressed.emit()
	await process_frame
	_expect(_menu.settings_layer.visible, "Settings did not open as a menu overlay")
	_expect(_menu.is_music_playing(), "opening Settings interrupted the song")
	_expect(root.gui_get_focus_owner() == _menu.settings_screen.frame_rate, "Settings did not focus its first control")
	var keyboard_down := InputEventKey.new()
	keyboard_down.keycode = KEY_DOWN
	keyboard_down.pressed = true
	root.push_input(keyboard_down)
	await process_frame
	_expect(root.gui_get_focus_owner() != _menu.settings_screen.frame_rate, "keyboard focus did not traverse Settings")
	keyboard_down.pressed = false
	root.push_input(keyboard_down)
	for _index in 12:
		if root.gui_get_focus_owner() == _menu.settings_screen.music_volume:
			break
		var controller_down := InputEventJoypadButton.new()
		controller_down.button_index = JOY_BUTTON_DPAD_DOWN
		controller_down.pressed = true
		root.push_input(controller_down)
		await process_frame
		controller_down.pressed = false
		root.push_input(controller_down)
	_expect(root.gui_get_focus_owner() == _menu.settings_screen.music_volume, "controller focus could not reach Music volume")
	_menu.settings_screen.music_volume.value = 0.42
	await process_frame
	_expect(is_equal_approx(settings.music_volume, 0.42), "Music slider did not update settings")
	_expect(settings_emissions[0] == 1, "Music slider did not emit one settings change")
	_expect(is_equal_approx(_menu.music_player.volume_db, linear_to_db(0.42)), "Music slider did not update playback volume")
	_menu.settings_screen.back_button.pressed.emit()
	await process_frame
	_expect(not _menu.settings_layer.visible, "Settings overlay did not close")
	_expect(_menu.main_menu.settings_button.has_focus(), "focus did not return to Settings")

func _verify_shot_transition() -> void:
	_menu.set("_shot_elapsed", _menu.profile.shots[0].duration_seconds)
	_menu.call("_process", 0.01)
	var outgoing_position := _menu.camera_rig.global_position
	var deadline := Time.get_ticks_msec() + 3000
	while _menu.world_cover.modulate.a <= 0.0 and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame
	_expect(not _menu.camera_rig.global_position.is_equal_approx(outgoing_position), "outgoing camera stopped during the fade to black")
	while _menu.get_current_shot_id() == &"sunrise_meadow" and Time.get_ticks_msec() < deadline:
		await process_frame
	_expect(_menu.get_current_shot_id() == &"forest_water", "cinematic reel did not advance deterministically")
	var next_shot := _menu.profile.shots[1]
	var next_origin := Vector3(float(next_shot.anchor.x) + 0.5, _menu.camera_rig.global_position.y, float(next_shot.anchor.y) + 0.5)
	_expect(_menu.camera_rig.global_position.distance_to(next_origin) < 0.25, "incoming camera did not restart near its authored origin")
	var incoming_position := _menu.camera_rig.global_position
	await process_frame
	await process_frame
	_expect(not _menu.camera_rig.global_position.is_equal_approx(incoming_position), "incoming camera stopped during the fade from black")
	while bool(_menu.get("_shot_transitioning")) and Time.get_ticks_msec() < deadline:
		await process_frame

func _expect_presentation_only_actors() -> void:
	var runtime := _menu.population.get_runtime()
	for actor in runtime.get_active_actors():
		_expect(not actor.is_audio_enabled(), "menu actor audio was enabled")
		_expect(actor.health_bar == null, "menu actor created gameplay health presentation")
		_expect(runtime.try_apply_damage(actor.runtime_id, 1.0) == null, "menu actor accepted combat damage")

func _verify_play_and_resume() -> void:
	var play_emissions := [0]
	_menu.play_requested.connect(func(): play_emissions[0] += 1)
	_menu.play_requested.connect(func(): _menu.set_primary_menu_visible(false))
	var shot_elapsed_before := float(_menu.get("_shot_elapsed"))
	_menu.main_menu.play_button.pressed.emit()
	await process_frame
	_expect(play_emissions[0] == 1, "Play did not emit exactly one navigation request")
	_expect(not _menu.main_menu.visible, "main-menu controls remained over world selection")
	_expect(not _menu.is_ready_for_input(), "hidden primary menu retained input")
	_expect(_menu.is_music_playing(), "Play interrupted music before a world was selected")
	_expect(is_zero_approx(_menu.full_fade.modulate.a), "Play faded black before a world was selected")
	await create_timer(0.1).timeout
	_expect(float(_menu.get("_shot_elapsed")) > shot_elapsed_before, "cinematic stopped while world selection was open")
	_menu.set_primary_menu_visible(true)
	_expect(_menu.main_menu.visible, "Back did not restore the main menu")
	_expect(_menu.is_ready_for_input(), "Back did not restore menu input")
	_expect(_menu.is_music_playing(), "Back interrupted or restarted menu playback")
	var current_shot := _menu.profile.shots[int(_menu.get("_shot_index"))]
	_menu.set("_shot_elapsed", current_shot.duration_seconds)
	_menu.call("_process", 0.01)
	await process_frame
	_expect(bool(_menu.get("_shot_transitioning")), "crossfade cancellation fixture did not start a shot transition")
	_menu.main_menu.play_button.pressed.emit()
	await process_frame
	await _menu.fade_out_for_session()
	_expect(_menu.is_session_transitioning(), "world selection did not begin the session transition")
	_expect(is_equal_approx(_menu.full_fade.modulate.a, 1.0), "world selection did not finish on black")
	_expect(is_zero_approx(_menu.world_cover.modulate.a), "shot crossfade competed with the session fade")
	_expect(not _menu.is_music_playing(), "world selection did not fade out the music")

func _contains_gameplay_node(node: Node) -> bool:
	if node is PlayerMotor or node is HUD or node is GameSession or node is MeleeCombatCoordinator:
		return true
	for child in node.get_children():
		if _contains_gameplay_node(child):
			return true
	return false

func _snapshot_saves() -> Dictionary:
	var snapshot: Dictionary = {}
	if not DirAccess.dir_exists_absolute(SaveManager.SAVE_DIR):
		return snapshot
	for file_name in DirAccess.get_files_at(SaveManager.SAVE_DIR):
		var path := SaveManager.SAVE_DIR.path_join(file_name)
		snapshot[file_name] = FileAccess.get_file_as_bytes(path)
	return snapshot

func _teardown_and_finish() -> void:
	_menu.shutdown()
	_menu.queue_free()
	_menu = null
	await process_frame
	await process_frame
	await create_timer(0.25).timeout
	call_deferred("_finish")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)

func _finish() -> void:
	if _errors.is_empty():
		print("MENU_EXPERIENCE PASS")
		quit(0)
	else:
		for message in _errors:
			push_error(message)
		quit(1)
