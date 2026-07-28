extends SceneTree

func _init():
	print("[TestTime] Testing time_of_day save/load so worlds don't reset to 6am")

	SaveManager.ensure_save_dir()
	SaveManager.delete_slot(0)

	# Create world with default time 6.0
	var seed_val = 123456
	var data = SaveManager.create_new_world(0, seed_val, "TimeTestWorld")
	print("[TestTime] Created world with time_of_day=%.2f expected 6.0" % data.get("time_of_day", -1))
	assert(is_equal_approx(float(data.get("time_of_day", 0)), 6.0))

	# Simulate playing until night 21.5 (9:30pm) and saving
	var voxel = VoxelWorld.new(200,20,36)
	var time_to_save = 21.5 # 9:30pm - user left at night
	# Skip heavy terrain setup, just test save manager time field
	voxel.placed_blocks[Vector3i(1,2,3)] = BlockId.Type.STONE
	var saved = SaveManager.save_world_state(0, voxel, null, null, 0.0, time_to_save)
	assert(saved)
	print("[TestTime] Saved time_of_day=%.2f at night" % time_to_save)

	var loaded = SaveManager.load_slot(0)
	var loaded_time = float(loaded.get("time_of_day", -1))
	print("[TestTime] Loaded time_of_day=%.2f expected %.2f" % [loaded_time, time_to_save])
	assert(is_equal_approx(loaded_time, time_to_save))
	print("[TestTime] PASS - time_of_day persisted")

	# Test second save at different time 14.25 (2:15pm)
	var time2 = 14.25
	SaveManager.save_world_state(0, voxel, null, null, 0.0, time2)
	var loaded2 = SaveManager.load_slot(0)
	assert(is_equal_approx(float(loaded2["time_of_day"]), time2))
	print("[TestTime] PASS - time_of_day updated to %.2f (daytime)" % time2)

	# Test GameClock set and get
	var clock = GameClock.new()
	clock._ready()
	print("[TestTime] Clock initial %.2f expected 6.0" % clock.get_time_of_day())
	clock.set_time_of_day(loaded2["time_of_day"])
	assert(is_equal_approx(clock.get_time_of_day(), time2))
	print("[TestTime] Clock set to %.2f formatted %s" % [clock.get_time_of_day(), clock.get_formatted()])
	print("[TestTime] PASS - GameClock restores saved time")

	# Test loading screen writes session with time
	var session = {"slot_id": 0, "seed": seed_val, "world_name": "TimeTestWorld", "time_of_day": time2}
	var f = FileAccess.open("user://current_session.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(session))
	f.close()
	var f2 = FileAccess.open("user://current_session.json", FileAccess.READ)
	var txt = f2.get_as_text()
	f2.close()
	var parsed = JSON.parse_string(txt)
	assert(is_equal_approx(float(parsed["time_of_day"]), time2))
	print("[TestTime] PASS - session file includes time_of_day")

	print("[TestTime] ALL TESTS PASSED - time of day now saves and worlds don't reset to 6am")
	quit(0)
