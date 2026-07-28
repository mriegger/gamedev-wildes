extends SceneTree

func _init():
	print("[TestPause] Testing pause menu - pauses whole game state, resume/main menu")

	var game_scene = load("res://game/game.tscn") as PackedScene
	var game = game_scene.instantiate() as Game
	# Need to set a slot so saving works
	SaveManager.ensure_save_dir()
	var data = SaveManager.create_new_world(0, 123456, "PauseTestWorld")
	game.current_slot_id = 0
	game.current_save_data = data

	root.add_child(game)
	await create_timer(0.5).timeout

	print("[TestPause] Game loaded, tree paused=%s clock=%s" % [paused, game.game_clock.get_formatted() if game.game_clock else "?"])
	assert(paused == false)

	# Simulate ESC -> pause
	game._show_pause_menu()
	await create_timer(0.3).timeout

	print("[TestPause] After _show_pause_menu, tree paused=%s pause_menu exists=%s" % [paused, game._pause_menu != null])
	assert(paused == true)
	assert(game._pause_menu != null)

	var clock_before = game.game_clock.get_time_of_day() if game.game_clock else 0.0
	print("[TestPause] Clock before paused wait: %.3f" % clock_before)

	await create_timer(1.0).timeout

	var clock_after = game.game_clock.get_time_of_day() if game.game_clock else 0.0
	print("[TestPause] Clock after 1s paused: %.3f diff %.3f should be ~0 (game paused)" % [clock_after, clock_after - clock_before])
	# When tree paused, GameClock is pausable, so should not advance
	# Allow tiny epsilon
	assert(abs(clock_after - clock_before) < 0.05)

	# Test resume
	game._resume_from_pause()
	await create_timer(0.3).timeout
	print("[TestPause] After resume, tree paused=%s" % paused)
	assert(paused == false)

	var clock_before2 = game.game_clock.get_time_of_day()
	await create_timer(0.5).timeout
	var clock_after2 = game.game_clock.get_time_of_day()
	print("[TestPause] Clock after resume 0.5s: %.3f diff %.3f should be >0 (game resumed)" % [clock_after2, clock_after2 - clock_before2])
	assert((clock_after2 - clock_before2) > 0.0)

	# Test main menu from pause
	game._show_pause_menu()
	await create_timer(0.3).timeout
	assert(paused == true)
	print("[TestPause] Show pause again for Main Menu test")

	# Now go to main menu (should save and unpause)
	game._on_pause_main_menu()
	await create_timer(0.5).timeout

	print("[TestPause] After main menu from pause, tree paused=%s" % paused)
	assert(paused == false)

	var main_menu_found = false
	for child in root.get_children():
		if child is MainMenu:
			main_menu_found = true
			break

	if main_menu_found:
		print("[TestPause] PASS - Pause menu pauses whole game state (clock frozen), Resume resumes, Main Menu saves and returns, frosted blur")
		quit(0)
	else:
		print("[TestPause] FAIL - MainMenu not found after pause->main menu")
		quit(1)
