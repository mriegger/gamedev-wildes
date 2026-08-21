extends SceneTree

var _errors: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var saves_before := _snapshot_saves()
	var app_scene := load("res://app/app.tscn") as PackedScene
	_expect(app_scene != null, "App scene did not load")
	if app_scene == null:
		_finish()
		return
	var app := app_scene.instantiate()
	root.add_child(app)
	await process_frame
	var menu := app.get("_menu_experience") as MenuExperience
	_expect(menu != null, "App did not create the launch menu")
	if menu == null:
		app.queue_free()
		await process_frame
		_finish()
		return
	var screen_root := app.get_node("ScreenRoot") as CanvasLayer
	var world_cover_layer := menu.world_cover.get_parent() as CanvasLayer
	var interface_layer := menu.get_node("Interface") as CanvasLayer
	_expect(screen_root != null and screen_root.layer == 15, "App screen root did not own the overlay canvas")
	_expect(world_cover_layer != null and world_cover_layer.layer == 10, "cinematic world cover was not below App screens")
	_expect(interface_layer != null and interface_layer.layer == 20, "menu interface was not above App screens")
	_expect(menu.full_fade.get_parent() == interface_layer, "session fade was not kept above App screens")
	var logo_deadline := Time.get_ticks_msec() + 3000
	while menu.main_menu.logo.modulate.a <= 0.0 and Time.get_ticks_msec() < logo_deadline:
		await process_frame
	var skip_event := InputEventKey.new()
	skip_event.keycode = KEY_ENTER
	skip_event.pressed = true
	root.push_input(skip_event)
	var ready_deadline := Time.get_ticks_msec() + 60000
	while not menu.is_ready_for_input() and Time.get_ticks_msec() < ready_deadline:
		await process_frame
	_expect(menu.is_ready_for_input(), "App menu did not finish loading")
	if not menu.is_ready_for_input():
		app.queue_free()
		await process_frame
		_finish()
		return
	menu.main_menu.play_button.pressed.emit()
	var select_deadline := Time.get_ticks_msec() + 3000
	while not (app.get("_screen") is SaveSlotScreen) and Time.get_ticks_msec() < select_deadline:
		await process_frame
	var world_select := app.get("_screen") as SaveSlotScreen
	_expect(world_select != null, "Play did not open world selection")
	_expect(app.get("_menu_experience") == menu, "world selection rebuilt the menu experience")
	_expect(menu.visible, "world selection hid the cinematic")
	_expect(not menu.main_menu.visible, "main menu remained visible behind world selection")
	_expect(menu.is_music_playing(), "world selection interrupted menu music")
	_expect(menu.is_processing(), "world selection stopped the cinematic reel")
	_expect(not menu.world.is_suspended(), "world selection suspended cinematic world streaming")
	_expect(menu.population.is_physics_processing(), "world selection suspended cinematic population")
	_expect(not menu.population.is_processing(), "cinematic population retained render-frame processing")
	_expect(is_zero_approx(menu.full_fade.modulate.a), "world selection started the session fade before a world was selected")
	if world_select != null:
		_expect(world_select.get_parent() == screen_root, "world selection was not mounted in the App screen root")
		var background := world_select.get_node("Background") as ColorRect
		_expect(background != null and is_zero_approx(background.color.a), "world selection has an opaque background over the cinematic")
		var dim_overlay := world_select.get_node("DimOverlay") as ColorRect
		_expect(dim_overlay != null and dim_overlay.color.a > 0.0 and dim_overlay.color.a < 1.0, "world selection dim overlay is not translucent")
		_expect(world_select.main_panel.material is ShaderMaterial, "world selection panel is not frosted")
		for slot in world_select.slot_instances:
			_expect(slot.panel.material is ShaderMaterial, "world selection slot is not frosted")
		app.call("_show_world_select")
		_expect(app.get("_screen") == world_select, "duplicate Play replaced the active world selection")
		_expect(screen_root.get_child_count() == 1, "duplicate Play mounted another world selection")
	var shot_elapsed_before := float(menu.get("_shot_elapsed"))
	await process_frame
	await process_frame
	_expect(float(menu.get("_shot_elapsed")) > shot_elapsed_before, "cinematic reel did not continue behind world selection")
	var music_position_before_back := menu.music_player.get_playback_position()
	if world_select != null:
		world_select.back_requested.emit()
	await create_timer(0.05).timeout
	_expect(app.get("_screen") == null, "Back did not close world selection")
	_expect(app.get("_menu_experience") == menu, "Back rebuilt the cached menu")
	_expect(menu.main_menu.visible, "Back did not restore the main menu")
	_expect(menu.is_music_playing(), "Back interrupted menu music")
	_expect(menu.music_player.get_playback_position() >= music_position_before_back, "Back restarted menu music")
	_expect(menu.is_ready_for_input(), "Back did not restore menu input")
	menu.main_menu.play_button.pressed.emit()
	select_deadline = Time.get_ticks_msec() + 3000
	while not (app.get("_screen") is SaveSlotScreen) and Time.get_ticks_msec() < select_deadline:
		await process_frame
	world_select = app.get("_screen") as SaveSlotScreen
	_expect(world_select != null, "Play did not reopen world selection")
	var original_menu_id := menu.get_instance_id()
	if world_select != null:
		world_select.session_requested.emit(0, {})
	await process_frame
	_expect(is_instance_valid(menu), "world selection destroyed the menu before its session fade")
	_expect(menu.is_session_transitioning(), "world selection did not start the session fade")
	_expect(menu.full_fade.modulate.a > 0.0, "session selection did not begin fading to black")
	var recovery_deadline := Time.get_ticks_msec() + 5000
	while (
		is_instance_valid(menu)
		or app.get("_game") != null
		or not (app.get("_screen") is SaveSlotScreen)
		or not (app.get("_menu_experience") is MenuExperience)
	) and Time.get_ticks_msec() < recovery_deadline:
		await process_frame
	_expect(not is_instance_valid(menu), "menu world was not torn down before gameplay startup")
	_expect(app.get("_game") == null, "invalid session recovery retained a Game instance")
	world_select = app.get("_screen") as SaveSlotScreen
	var recovered_menu := app.get("_menu_experience") as MenuExperience
	_expect(world_select != null, "invalid session recovery did not return to world selection")
	_expect(recovered_menu != null, "invalid session recovery did not rebuild the menu experience")
	if recovered_menu != null:
		_expect(recovered_menu.get_instance_id() != original_menu_id, "invalid session recovery reused the torn-down menu")
		_expect(recovered_menu.visible, "recovered menu is not visible behind world selection")
		_expect(not recovered_menu.main_menu.visible, "recovered main menu obscured world selection")
		if world_select != null:
			_expect(world_select.get_parent() == screen_root, "recovered world selection was mounted outside the App screen root")
		var music_deadline := Time.get_ticks_msec() + 1000
		while not recovered_menu.is_music_playing() and Time.get_ticks_msec() < music_deadline:
			await process_frame
		_expect(recovered_menu.is_music_playing(), "recovered menu music did not restart")
		_expect(int(recovered_menu.get("_entry_mode")) == MenuExperience.EntryMode.RECOVERY, "startup failure used the gameplay-return menu mode")
		var intro_deadline := Time.get_ticks_msec() + 60000
		while bool(recovered_menu.get("_intro_running")) and Time.get_ticks_msec() < intro_deadline:
			await process_frame
		_expect(not bool(recovered_menu.get("_intro_running")), "recovered menu intro did not finish")
		_expect(not recovered_menu.main_menu.visible, "intro completion restored controls behind world selection")
		_expect(not recovered_menu.is_ready_for_input(), "intro completion enabled controls behind world selection")
	_expect(_snapshot_saves() == saves_before, "menu navigation mutated save data")
	await _verify_loading_reveal()
	app.call("_clear_screen")
	app.call("_destroy_menu_experience")
	app.call("_on_game_main_menu_requested")
	await process_frame
	await process_frame
	var returned_menu := app.get("_menu_experience") as MenuExperience
	_expect(returned_menu != null, "gameplay return did not rebuild the menu experience")
	if returned_menu != null:
		_expect(int(returned_menu.get("_entry_mode")) == MenuExperience.EntryMode.GAMEPLAY_RETURN, "gameplay return used the wrong menu mode")
		_expect(not returned_menu.is_music_playing(), "gameplay return restarted menu music")
		_expect(is_equal_approx(returned_menu.main_menu.logo.modulate.a, 1.0), "gameplay return replayed the logo fade")
		_expect(is_equal_approx(returned_menu.main_menu.controls.modulate.a, 1.0), "gameplay return replayed the controls fade")
		_expect(returned_menu.main_menu.loading_bar.visible, "gameplay return omitted loading feedback")
		_expect(returned_menu.main_menu.loading_bar.accessibility_name == "Loading main menu", "gameplay return loading feedback was mislabeled")
	app.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.25).timeout
	_finish()

func _verify_loading_reveal() -> void:
	var loading_scene := load("res://ui/screens/loading/loading_screen.tscn") as PackedScene
	var loading := loading_scene.instantiate() as LoadingScreen
	loading.setup(0, {"world_name": "Reveal Test"})
	root.add_child(loading)
	await process_frame
	var background := loading.get_node("Control/Background") as ColorRect
	var progress_bar := loading.get_node("Control/CenterContainer/ProgressBar") as ProgressBar
	_expect(background.color == Color.BLACK, "loading screen background was not opaque black")
	_expect(loading.find_child("Logo", true, false) == null, "loading screen retained a visible logo")
	_expect(loading.find_child("FrostedPanel", true, false) == null, "loading screen retained a panel")
	_expect(loading.find_child("WorldNameLabel", true, false) == null, "loading screen retained a world label")
	_expect(loading.find_child("StatusLabel", true, false) == null, "loading screen retained a status label")
	_expect(is_zero_approx(progress_bar.value), "loading progress did not start at zero")
	_expect(not progress_bar.show_percentage, "loading progress displayed percentage text")
	_expect(progress_bar.size.y <= LoadingScreen.BAR_HEIGHT, "loading progress bar was not thin")
	var viewport_width := root.get_visible_rect().size.x
	var expected_width := minf(
		clampf(viewport_width * LoadingScreen.BAR_WIDTH_RATIO, LoadingScreen.MIN_BAR_WIDTH, LoadingScreen.MAX_BAR_WIDTH),
		maxf(viewport_width - LoadingScreen.BAR_HORIZONTAL_MARGIN, LoadingScreen.BAR_HEIGHT),
	)
	_expect(is_equal_approx(progress_bar.size.x, expected_width), "loading progress bar did not use its responsive width")
	_expect(progress_bar.get_global_rect().get_center().distance_to(root.get_visible_rect().get_center()) <= 1.0, "loading progress bar was not centered")
	var track := progress_bar.get_theme_stylebox("background") as StyleBoxFlat
	var fill := progress_bar.get_theme_stylebox("fill") as StyleBoxFlat
	_expect(
		track != null
		and fill != null
		and fill.bg_color.get_luminance() * fill.bg_color.a > track.bg_color.get_luminance() * track.bg_color.a,
		"loading progress bar did not use a subtle track and high-contrast fill",
	)
	_expect(progress_bar.accessibility_name.contains("Reveal Test"), "loading progress accessibility name omitted the world name")
	_expect(progress_bar.accessibility_description == "Preparing world", "loading progress omitted its initial accessible status")
	loading.update_progress("terrain", 0.4, "Generating terrain")
	_expect(is_equal_approx(progress_bar.value, 40.0), "loading progress did not map normalized progress")
	_expect(progress_bar.accessibility_description == "Terrain: Generating terrain", "loading progress did not expose its current status")
	loading.update_progress("config", 0.1, "Late update")
	_expect(is_equal_approx(progress_bar.value, 40.0), "loading progress regressed")
	loading.update_progress("done", 2.0, "Ready")
	_expect(is_equal_approx(progress_bar.value, 100.0), "loading progress did not clamp to its maximum")
	await loading.fade_into_game()
	_expect(is_zero_approx((loading.get_node("Control") as Control).modulate.a), "loading screen did not fade into gameplay")
	loading.queue_free()
	await process_frame

func _snapshot_saves() -> Dictionary:
	var snapshot: Dictionary = {}
	if not DirAccess.dir_exists_absolute(SaveManager.SAVE_DIR):
		return snapshot
	for file_name in DirAccess.get_files_at(SaveManager.SAVE_DIR):
		var path := SaveManager.SAVE_DIR.path_join(file_name)
		snapshot[file_name] = FileAccess.get_file_as_bytes(path)
	return snapshot

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)

func _finish() -> void:
	if _errors.is_empty():
		print("APP_MENU_NAVIGATION PASS")
		quit(0)
	else:
		for message in _errors:
			push_error(message)
		quit(1)
