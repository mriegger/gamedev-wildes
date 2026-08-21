extends SceneTree

var _errors: Array[String] = []
var _menu: MenuExperience

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var menu_scene := load("res://ui/screens/main_menu/menu_experience.tscn") as PackedScene
	_expect(menu_scene != null, "menu experience scene did not load")
	if menu_scene == null:
		_finish()
		return
	_menu = menu_scene.instantiate() as MenuExperience
	menu_scene = null
	_menu.setup(GameSettings.new(), MenuExperience.EntryMode.FIRST_LAUNCH)
	root.add_child(_menu)
	await process_frame
	var elapsed := 0.0
	var logo_visible_at := -1.0
	var world_ready_at := -1.0
	var world_reveal_at := -1.0
	var camera_position_at_ready := Vector3.ZERO
	var actor_positions_at_ready: Dictionary = {}
	var camera_moved_during_intro := false
	var actor_moved_during_intro := false
	var last_loading_progress := 0.0
	var loading_progress_advanced := false
	var loading_bar_faded_with_logo := false
	var deadline := Time.get_ticks_msec() + 60000
	while not _menu.is_ready_for_input() and Time.get_ticks_msec() < deadline:
		await process_frame
		elapsed += root.get_process_delta_time()
		var loading_progress := _menu.main_menu.loading_bar.value
		_expect(loading_progress >= last_loading_progress, "startup loading progress regressed")
		loading_progress_advanced = loading_progress_advanced or loading_progress > last_loading_progress
		last_loading_progress = loading_progress
		if logo_visible_at < 0.0 and _menu.main_menu.logo.modulate.a > 0.0:
			logo_visible_at = elapsed
			loading_bar_faded_with_logo = (
				_menu.main_menu.loading_bar.modulate.a > 0.0
				and is_equal_approx(_menu.main_menu.loading_bar.modulate.a, _menu.main_menu.logo.modulate.a)
			)
		if world_ready_at < 0.0 and bool(_menu.get("_world_ready")):
			world_ready_at = elapsed
			_expect(is_equal_approx(_menu.world_cover.modulate.a, 1.0), "showcase world became visible before its actors were prepared")
			camera_position_at_ready = _menu.camera_rig.global_position
			for actor in _menu.population.get_runtime().get_active_actors():
				_expect(
					is_equal_approx(actor.get_visual_opacity(), 1.0),
					"%s was transparent when the showcase world became ready" % actor.definition.id,
				)
				actor_positions_at_ready[actor.runtime_id] = actor.global_position
		if not bool(_menu.get("_world_ready")):
			_expect(loading_progress <= 90.0, "world generation consumed the reserved preparation progress")
		if world_reveal_at < 0.0 and _menu.world_cover.modulate.a < 1.0:
			world_reveal_at = elapsed
			_expect(_menu.is_processing(), "cinematic camera did not start with the world reveal")
			_expect(_menu.population.is_physics_processing(), "ambient population did not start with the world reveal")
			_expect(not _menu.population.is_processing(), "ambient population retained render-frame processing")
			_expect(float(_menu.get("_shot_elapsed")) > 0.0, "cinematic elapsed time did not advance with the world reveal")
		if world_ready_at >= 0.0 and _menu.world_cover.modulate.a > 0.0:
			camera_moved_during_intro = (
				camera_moved_during_intro
				or not _menu.camera_rig.global_position.is_equal_approx(camera_position_at_ready)
			)
			for actor in _menu.population.get_runtime().get_active_actors():
				if (
					actor_positions_at_ready.has(actor.runtime_id)
					and not actor.global_position.is_equal_approx(actor_positions_at_ready[actor.runtime_id])
				):
					actor_moved_during_intro = true
	_expect(_menu.is_ready_for_input(), "unskipped menu intro did not complete")
	_expect(not bool(_menu.get("_skip_requested")), "normal intro unexpectedly entered the skip path")
	_expect(logo_visible_at >= _menu.profile.logo_delay_seconds - 0.1, "logo appeared before its authored delay")
	_expect(world_ready_at >= 0.0, "showcase world never became ready")
	_expect(loading_progress_advanced, "startup loading progress never advanced")
	_expect(loading_bar_faded_with_logo, "startup loading bar did not fade in with the logo")
	_expect(is_equal_approx(_menu.main_menu.loading_bar.value, 100.0), "startup loading progress did not complete")
	_expect(is_zero_approx(_menu.main_menu.loading_bar.modulate.a), "startup loading bar remained visible after completion")
	_expect(world_reveal_at >= maxf(_menu.profile.logo_delay_seconds + _menu.profile.logo_fade_seconds, world_ready_at) - 0.1, "world reveal did not adapt to generation readiness")
	var minimum_ready_time := maxf(_menu.profile.logo_delay_seconds + _menu.profile.logo_fade_seconds, world_ready_at) + _menu.profile.world_fade_seconds + _menu.profile.controls_fade_seconds
	_expect(elapsed >= minimum_ready_time - 0.15, "controls enabled before the normal intro completed")
	_expect(elapsed >= 5.85, "normal intro enabled input before the intended six-second mark")
	_expect(camera_moved_during_intro, "cinematic camera remained stationary throughout the world reveal")
	_expect(actor_moved_during_intro, "ambient actors remained stationary throughout the world reveal")
	_expect(_menu.is_processing(), "cinematic reel did not start after the intro")
	_expect(_menu.population.is_physics_processing(), "ambient population did not start after the intro")
	_expect(not _menu.population.is_processing(), "ambient population retained render-frame processing after the intro")
	await _teardown()
	await _verify_gameplay_return()
	call_deferred("_finish")

func _verify_gameplay_return() -> void:
	var menu_scene := load("res://ui/screens/main_menu/menu_experience.tscn") as PackedScene
	_menu = menu_scene.instantiate() as MenuExperience
	menu_scene = null
	_menu.setup(GameSettings.new(), MenuExperience.EntryMode.GAMEPLAY_RETURN)
	root.add_child(_menu)
	var observed_generation_updates := [0]
	var observed_generation_progress := [0.0]
	_menu.world.generation_progress.connect(func(_stage: String, percent: float, _details: String) -> void:
		observed_generation_progress[0] = maxf(observed_generation_progress[0], clampf(percent, 0.0, 1.0) * 90.0)
		observed_generation_updates[0] += 1
	)
	await process_frame
	_expect(is_equal_approx(_menu.full_fade.modulate.a, 1.0), "gameplay return did not begin behind black")
	_expect(is_zero_approx(_menu.world_cover.modulate.a), "gameplay return retained the launch-only world cover")
	_expect(is_equal_approx(_menu.main_menu.logo.modulate.a, 1.0), "gameplay return replayed the logo fade")
	_expect(is_equal_approx(_menu.main_menu.controls.modulate.a, 1.0), "gameplay return replayed the controls fade")
	_expect(is_equal_approx(_menu.main_menu.loading_bar.modulate.a, 1.0), "gameplay return did not show its loading bar")
	_expect(_menu.main_menu.loading_bar.visible, "gameplay return loading bar was not accessible")
	_expect(_menu.main_menu.loading_bar.z_index > _menu.full_fade.z_index, "gameplay return loading bar was behind black")
	_expect(_menu.main_menu.loading_bar.accessibility_name == "Loading main menu", "gameplay return loading bar had the wrong accessible name")
	_expect(not _menu.main_menu.loading_bar.accessibility_description.is_empty(), "gameplay return loading bar omitted its accessible status")
	_expect(
		absf(_menu.main_menu.loading_bar.get_global_rect().get_center().y - root.get_visible_rect().get_center().y) <= 1.0,
		"gameplay return loading bar was not vertically centered",
	)
	_expect(not _menu.is_music_playing(), "gameplay return started music on its first frame")
	_expect(not _menu.is_ready_for_input(), "gameplay return enabled input before its world was ready")
	var reveal_elapsed := 0.0
	var world_ready := false
	var last_loading_progress := 0.0
	var loading_progress_advanced := false
	var deadline := Time.get_ticks_msec() + 60000
	while not _menu.is_ready_for_input() and Time.get_ticks_msec() < deadline:
		await process_frame
		_expect(not _menu.is_music_playing(), "gameplay return started music while rebuilding")
		var loading_progress := _menu.main_menu.loading_bar.value
		_expect(loading_progress >= last_loading_progress, "gameplay return loading progress regressed")
		_expect(loading_progress + 0.01 >= observed_generation_progress[0], "gameplay return loading bar did not follow world generation")
		loading_progress_advanced = loading_progress_advanced or loading_progress > last_loading_progress
		last_loading_progress = loading_progress
		if not bool(_menu.get("_world_ready")):
			_expect(loading_progress <= 90.0, "gameplay return generation consumed its preparation reserve")
			_expect(is_equal_approx(_menu.full_fade.modulate.a, 1.0), "gameplay return revealed the menu before it was ready")
		if bool(_menu.get("_world_ready")):
			world_ready = true
			reveal_elapsed += root.get_process_delta_time()
	_expect(world_ready, "gameplay return showcase world never became ready")
	_expect(observed_generation_updates[0] > 0, "gameplay return loading bar received no world generation updates")
	_expect(loading_progress_advanced, "gameplay return loading progress never advanced")
	_expect(is_equal_approx(_menu.main_menu.loading_bar.value, 100.0), "gameplay return loading progress did not complete")
	_expect(_menu.is_ready_for_input(), "gameplay return did not enable menu input")
	_expect(
		reveal_elapsed <= MenuExperience.RETURN_LOADING_BAR_FADE_SECONDS + MenuExperience.QUICK_REVEAL_SECONDS + 0.15,
		"gameplay return retained the delayed world fade",
	)
	_expect(is_zero_approx(_menu.full_fade.modulate.a), "gameplay return did not reveal the complete menu")
	_expect(is_zero_approx(_menu.main_menu.loading_bar.modulate.a), "gameplay return loading bar remained over the menu")
	_expect(not _menu.main_menu.loading_bar.visible, "completed gameplay return loading bar remained accessible")
	_expect(_menu.is_processing(), "gameplay return did not start the cinematic")
	_expect(_menu.population.is_physics_processing(), "gameplay return did not start ambient movement")
	_expect(not _menu.population.is_processing(), "gameplay return retained render-frame population processing")
	_expect(not _menu.is_music_playing(), "gameplay return started menu music after its reveal")
	await _teardown()

func _teardown() -> void:
	_menu.shutdown()
	_menu.queue_free()
	_menu = null
	await process_frame
	await process_frame
	await create_timer(0.25).timeout

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)

func _finish() -> void:
	if _errors.is_empty():
		print("MENU_INTRO_TIMING PASS")
		quit(0)
	else:
		for message in _errors:
			push_error(message)
		quit(1)
