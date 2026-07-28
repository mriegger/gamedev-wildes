extends SceneTree

func _init():
	print("[NightRestore] Testing night time restore - user left at 21.5 should not start at 6am")
	SaveManager.ensure_save_dir()
	SaveManager.delete_slot(0)
	var data = SaveManager.create_new_world(0, 999999, "NightWorld")
	# Save at night
	SaveManager.save_world_state(0, VoxelWorld.new(), null, null, 0.0, 21.5)

	var session = {"slot_id": 0, "seed": 999999, "world_name": "NightWorld", "time_of_day": 21.5}
	var f = FileAccess.open("user://current_session.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(session))
	f.close()

	# Now instantiate Game - it should restore 21.5
	var game_scene = load("res://game/game.tscn") as PackedScene
	var game = game_scene.instantiate() as Game
	game.current_slot_id = 0
	game.current_save_data = SaveManager.load_slot(0)
	root.add_child(game)
	await create_timer(0.5).timeout

	print("[NightRestore] Game clock time: %.2f expected 21.5 formatted %s" % [game.game_clock.get_time_of_day(), game.game_clock.get_formatted()])
	var diff = abs(game.game_clock.get_time_of_day() - 21.5)
	if diff < 0.1:
		print("[NightRestore] PASS - Time of day restored to night (%.2f), not 6am. Diff %.3f < 0.1" % [game.game_clock.get_time_of_day(), diff])
		print("[NightRestore] Phase: %s is_day=%s" % [game.game_clock.get_phase(), game.game_clock.is_day()])
		quit(0)
	else:
		print("[NightRestore] FAIL - Time is %.2f not 21.5 diff %.3f" % [game.game_clock.get_time_of_day(), diff])
		quit(1)
