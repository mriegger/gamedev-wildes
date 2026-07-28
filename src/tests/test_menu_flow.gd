extends SceneTree

func _init():
	print("[MenuFlow] Testing MainMenu -> SaveSlotScreen -> LoadingScreen -> Game with progress bar")

	SaveManager.ensure_save_dir()

	var main_menu_scene = load("res://ui/main_menu/main_menu.tscn") as PackedScene
	var main_menu = main_menu_scene.instantiate() as MainMenu
	root.add_child(main_menu)
	await create_timer(0.2).timeout

	print("[MenuFlow] MainMenu loaded, simulating PLAY press")
	# Simulate PLAY button press
	if main_menu.has_method("_on_play_pressed"):
		main_menu._on_play_pressed()
	await create_timer(0.5).timeout

	# Find SaveSlotScreen
	var slot_screen: SaveSlotScreen = null
	for child in root.get_children():
		if child is SaveSlotScreen:
			slot_screen = child
			break

	if slot_screen == null:
		print("[MenuFlow] FAIL - SaveSlotScreen not found after PLAY")
		quit(1)
		return

	print("[MenuFlow] SaveSlotScreen found, slots=%d" % slot_screen.slot_instances.size())

	# Simulate creating world in empty slot if available, else play first
	var empty_slot = -1
	for inst in slot_screen.slot_instances:
		if not inst.slot_data.get("exists", false):
			empty_slot = inst.slot_id
			break

	if empty_slot == -1:
		empty_slot = 0
		print("[MenuFlow] No empty slot, reusing slot 0 and deleting first")
		SaveManager.delete_slot(empty_slot)
		slot_screen._refresh_slots()
		await create_timer(0.3).timeout

	print("[MenuFlow] Creating world in slot %d via dialog flow" % empty_slot)
	slot_screen._on_slot_create_dialog(empty_slot)
	await create_timer(0.3).timeout
	# Set name and confirm
	if slot_screen.dialog_name_edit:
		slot_screen.dialog_name_edit.text = "FlowTestWorld"
	slot_screen._on_confirm_create()
	await create_timer(0.5).timeout

	# Now LoadingScreen should be present
	var loading: LoadingScreen = null
	var attempts = 0
	while attempts < 20:
		for child in root.get_children():
			if child is LoadingScreen:
				loading = child
				break
		if loading:
			break
		await create_timer(0.5).timeout
		attempts += 1

	if loading == null:
		print("[MenuFlow] FAIL - LoadingScreen not found after create confirm")
		quit(1)
		return

	print("[MenuFlow] LoadingScreen found, monitoring progress bar")

	var max_wait = 30.0
	var elapsed = 0.0
	while elapsed < max_wait and is_instance_valid(loading):
		await create_timer(0.5).timeout
		elapsed += 0.5
		if loading.progress_bar:
			print("[MenuFlow] Progress %.0f%% - %s" % [loading.progress_bar.value, loading.status_label.text])

	if is_instance_valid(loading):
		print("[MenuFlow] FAIL - LoadingScreen still alive after %ds" % max_wait)
		quit(1)
		return

	# Game should be present
	var game_found = false
	for child in root.get_children():
		if child is Game:
			game_found = true
			print("[MenuFlow] Game found! slot=%d seed=%d chunks=%d" % [child.current_slot_id, child.world.seed_value if child.world else 0, child.world.chunk_renderer.chunk_instances.size() if child.world else 0])
			break

	if game_found:
		print("[MenuFlow] PASS - Full flow with progress bar works: MainMenu PLAY -> Select World (background) -> Loading with ProgressBar -> Game")
		quit(0)
	else:
		print("[MenuFlow] FAIL - Game not found")
		quit(1)
