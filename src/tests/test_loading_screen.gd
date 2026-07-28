extends SceneTree

func _init():
	print("[TestLoading] Testing LoadingScreen with progress bar")
	SaveManager.ensure_save_dir()
	SaveManager.delete_slot(2)
	var seed_val = SaveManager.generate_random_seed()
	var data = SaveManager.create_new_world(2, seed_val, "LoadingTestWorld")
	print("[TestLoading] Created slot 2 seed %d" % seed_val)

	# Instantiate LoadingScreen
	var ls_scene = load("res://ui/main_menu/loading_screen.tscn") as PackedScene
	var ls = ls_scene.instantiate() as LoadingScreen
	root.add_child(ls)
	await create_timer(0.1).timeout

	# Start loading
	ls.start_loading(2, data)
	await create_timer(0.2).timeout

	# Let it run for some time, monitor progress
	var max_wait = 20.0
	var elapsed = 0.0
	while elapsed < max_wait:
		await create_timer(0.5).timeout
		elapsed += 0.5
		if not is_instance_valid(ls):
			print("[TestLoading] LoadingScreen freed - game should be loaded")
			break
		if ls.progress_bar:
			print("[TestLoading] Progress: %.0f%% Status: %s" % [ls.progress_bar.value, ls.status_label.text if ls.status_label else ""])

	# Check if game exists
	var game_found = false
	for child in root.get_children():
		if child is Game:
			game_found = true
			print("[TestLoading] Game found: slot=%d seed=%d chunks=%d" % [child.current_slot_id, child.world.seed_value if child.world else 0, child.world.chunk_renderer.chunk_instances.size() if child.world and child.world.chunk_renderer else 0])
			break

	if game_found:
		print("[TestLoading] PASS - LoadingScreen with progress bar worked, world loaded")
		quit(0)
	else:
		print("[TestLoading] FAIL - Game not found after loading")
		quit(1)
