extends SceneTree

var _errors: Array[String] = []
var _slot_id: int
var _save_path: String

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_slot_id = 1100000000 + OS.get_process_id()
	while SaveManager.slot_exists(_slot_id):
		_slot_id += 1
	_save_path = SaveManager.get_slot_path(_slot_id)
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var game_scene := load("res://game/game.tscn") as PackedScene
	var app_scene := load("res://app/app.tscn") as PackedScene
	_expect(item_catalog != null, "item catalog did not load")
	_expect(game_scene != null, "game scene did not load")
	_expect(app_scene != null, "app scene did not load")
	if item_catalog == null or game_scene == null or app_scene == null:
		_finish()
		return
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	inventory.setup_empty()
	var encoded_inventory := inventory.to_dict()
	encoded_inventory["regions"]["backpack"][0] = {
		"item_id": "retired_test_item",
		"count": 1,
		"equipment_instance": null,
	}
	var save_data := {
		"slot_id": _slot_id,
		"exists": true,
		"seed": 17391,
		"world_name": "Invalid Inventory Safety",
		"created_at": "2000-01-01 00:00",
		"last_played": "2000-01-01 00:00",
		"version": SaveManager.CURRENT_SAVE_VERSION,
		"placed_blocks": {},
		"removed_blocks": {},
		"torch_attachments": {},
		"emplacements": {},
		"chests": {},
		"player_position": null,
		"player_stats": null,
		"player_perks": {"allocations": {}},
		"item_proficiency": {},
		"tutorial_progress": {"mining_tip_completed": false, "food_tip_completed": false, "crafting_tip_completed": false, "crafting_ingredients_tip_completed": false, "copper_mining_tip_completed": false, "sundown_weapon_tip_completed": false, "damage_affinity_tip_completed": false},
		"inventory": encoded_inventory,
		"next_equipment_instance_id": 1,
		"world_loot": {"next_entry_id": 1, "entries": []},
		"dungeon_progress": DungeonProgressState.new().snapshot(),
		"playtime_seconds": 0.0,
		"time_of_day": 6.0,
		"pumpkin_patch": null,
		"apple_trees": AppleTreeState.new().snapshot(),
	}
	var original_text := JSON.stringify(save_data, "\t")
	SaveManager.ensure_save_dir()
	var save_file := FileAccess.open(_save_path, FileAccess.WRITE)
	_expect(save_file != null, "test save could not be created")
	if save_file == null:
		_finish()
		return
	save_file.store_string(original_text)
	save_file.close()
	var loaded := SaveManager.load_slot(_slot_id, item_catalog)
	var loaded_before := loaded.duplicate(true)
	_expect(not bool(loaded.get("incompatible", false)), "current-version test save was rejected before domain restore")
	await _verify_game_failure(game_scene, loaded, loaded_before, original_text)
	await _verify_app_recovery(app_scene, loaded, original_text)
	_finish()

func _verify_game_failure(game_scene: PackedScene, loaded: Dictionary, loaded_before: Dictionary, original_text: String) -> void:
	var game := game_scene.instantiate() as Game
	var failure_messages: Array[String] = []
	var ready_emissions := [0]
	game.configure_session(_slot_id, loaded, GameSettings.new())
	game.session_start_failed.connect(func(message: String): failure_messages.append(message))
	game.session_ready.connect(func(): ready_emissions[0] += 1)
	root.add_child(game)
	await process_frame
	_expect(failure_messages.size() == 1, "invalid inventory did not emit one startup failure")
	_expect(not failure_messages.is_empty() and failure_messages[0].contains("inventory"), "startup failure did not identify inventory state")
	_expect(ready_emissions[0] == 0, "invalid inventory emitted session_ready")
	_expect(game.game_session.slot_id == -1 and not game.game_session.is_processing(), "invalid inventory enabled GameSession writes")
	_expect(loaded == loaded_before, "Game mutated the caller-owned loaded save")
	_expect(FileAccess.get_file_as_string(_save_path) == original_text, "Game startup failure changed save bytes")
	game.queue_free()
	await process_frame

func _verify_app_recovery(app_scene: PackedScene, loaded: Dictionary, original_text: String) -> void:
	var app := app_scene.instantiate()
	root.add_child(app)
	await process_frame
	var original_menu := app.get("_menu_experience") as MenuExperience
	_expect(original_menu != null, "App did not create the menu before session recovery")
	if original_menu == null:
		app.queue_free()
		await process_frame
		return
	var logo_deadline := Time.get_ticks_msec() + 3000
	while original_menu.main_menu.logo.modulate.a <= 0.0 and Time.get_ticks_msec() < logo_deadline:
		await process_frame
	var skip_event := InputEventKey.new()
	skip_event.keycode = KEY_ENTER
	skip_event.pressed = true
	root.push_input(skip_event)
	var ready_deadline := Time.get_ticks_msec() + 20000
	while not original_menu.is_ready_for_input() and Time.get_ticks_msec() < ready_deadline:
		await process_frame
	_expect(original_menu.is_ready_for_input(), "App menu did not become ready for recovery navigation")
	if not original_menu.is_ready_for_input():
		app.queue_free()
		await process_frame
		return
	original_menu.main_menu.play_button.pressed.emit()
	var select_deadline := Time.get_ticks_msec() + 3000
	while not (app.get("_screen") is SaveSlotScreen) and Time.get_ticks_msec() < select_deadline:
		await process_frame
	var selected_screen := app.get("_screen") as SaveSlotScreen
	_expect(selected_screen != null, "App did not open world selection before session recovery")
	if selected_screen == null:
		app.queue_free()
		await process_frame
		return
	var screen_root := app.get_node("ScreenRoot") as CanvasLayer
	_expect(screen_root != null and screen_root.layer == 15, "App screen root did not own world selection")
	_expect(selected_screen.get_parent() == screen_root, "world selection was not mounted over the cinematic")
	var background := selected_screen.get_node("Background") as ColorRect
	_expect(background != null and is_zero_approx(background.color.a), "world selection obscured the cinematic with an opaque background")
	var original_menu_id := original_menu.get_instance_id()
	selected_screen.session_requested.emit(_slot_id, loaded)
	await process_frame
	_expect(is_instance_valid(original_menu), "App destroyed the menu before the session fade completed")
	_expect(original_menu.is_session_transitioning(), "world selection did not start the session fade")
	var recovery_deadline := Time.get_ticks_msec() + 5000
	while (
		is_instance_valid(original_menu)
		or app.get("_game") != null
		or not (app.get("_screen") is SaveSlotScreen)
		or not (app.get("_menu_experience") is MenuExperience)
	) and Time.get_ticks_msec() < recovery_deadline:
		await process_frame
	var screen := app.get("_screen") as SaveSlotScreen
	var recovered_menu := app.get("_menu_experience") as MenuExperience
	_expect(not is_instance_valid(original_menu), "App retained the original menu after the session fade")
	_expect(app.get("_game") == null, "App retained a failed Game instance")
	_expect(screen != null, "App did not return to world selection")
	_expect(recovered_menu != null, "App did not rebuild a menu experience after startup failure")
	if recovered_menu != null:
		_expect(recovered_menu.get_instance_id() != original_menu_id, "App reused the menu destroyed for gameplay startup")
		_expect(recovered_menu.visible, "recovered menu was not visible behind world selection")
		_expect(not recovered_menu.main_menu.visible, "recovered main menu obscured world selection")
		if screen != null:
			_expect(screen.get_parent() == screen_root, "recovered world selection was mounted outside the App screen root")
		var music_deadline := Time.get_ticks_msec() + 1000
		while not recovered_menu.is_music_playing() and Time.get_ticks_msec() < music_deadline:
			await process_frame
		_expect(recovered_menu.is_music_playing(), "recovered menu music did not start")
	if screen != null:
		var error_dialog := screen.load_error_dialog
		_expect(error_dialog.visible, "world selection did not show the startup error")
		_expect(error_dialog.dialog_text.contains("inventory"), "world selection error omitted the failure reason")
	_expect(FileAccess.get_file_as_string(_save_path) == original_text, "App recovery changed save bytes")
	app.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.25).timeout

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)

func _finish() -> void:
	var cleanup_error := OK
	if not _save_path.is_empty() and FileAccess.file_exists(_save_path):
		cleanup_error = DirAccess.remove_absolute(_save_path)
	_expect(cleanup_error == OK and (_save_path.is_empty() or not FileAccess.file_exists(_save_path)), "temporary save cleanup failed")
	if _errors.is_empty():
		print("SESSION_START_FAILURE PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)
