extends Control
class_name SaveSlotScreen

## SaveSlotScreen - Shows 3 save slots for world selection / creation
## Enhanced with creation dialog handling random seed, naming, and visible stats

signal slot_selected(slot_id: int, data: Dictionary)
signal back_requested

@onready var slots_container: VBoxContainer = $CenterContainer/Panel/VBox/SlotsContainer
@onready var back_button: WildesButton = $TopBar/BackButton
@onready var create_dialog: Control = $CreateDialog
@onready var create_dialog_panel: Panel = $CreateDialog/CenterContainer/Panel
@onready var dialog_name_edit: LineEdit = $CreateDialog/CenterContainer/Panel/VBox/NameEdit
@onready var dialog_seed_edit: LineEdit = $CreateDialog/CenterContainer/Panel/VBox/HBoxSeed/SeedEdit
@onready var dialog_randomize_button: WildesButton = $CreateDialog/CenterContainer/Panel/VBox/HBoxSeed/RandomizeButton
@onready var dialog_confirm_button: WildesButton = $CreateDialog/CenterContainer/Panel/VBox/HBoxActions/ConfirmButton
@onready var dialog_cancel_button: WildesButton = $CreateDialog/CenterContainer/Panel/VBox/HBoxActions/CancelButton
@onready var delete_hold_screen: DeleteHoldScreen = $DeleteHoldScreen

var slot_item_scene: PackedScene = preload("res://ui/main_menu/save_slot_item.tscn")
var slot_instances: Array[SaveSlotItem] = []

var _pending_creation_slot: int = -1
var _pending_creation_seed: int = 0
var _pending_delete_slot: int = -1

func _ready():
	print("[SaveSlotScreen] Ready - %d slots click-to-play/create hold-to-delete + frosted blur" % SaveManager.SLOT_COUNT)
	SaveManager.ensure_save_dir()

	# Apply very dim low opacity border to panels for frosted glass legibility
	_apply_frosted_panel_styles()

	if back_button:
		back_button.button_text = "< BACK"
		back_button.text = "< BACK"
		if not back_button.pressed.is_connected(_on_back_pressed):
			back_button.pressed.connect(_on_back_pressed)

	if create_dialog:
		create_dialog.visible = false
	if dialog_randomize_button and not dialog_randomize_button.pressed.is_connected(_on_randomize_seed):
		dialog_randomize_button.pressed.connect(_on_randomize_seed)
	if dialog_confirm_button and not dialog_confirm_button.pressed.is_connected(_on_confirm_create):
		dialog_confirm_button.pressed.connect(_on_confirm_create)
		dialog_confirm_button.button_text = "CREATE"
		dialog_confirm_button.text = "CREATE"
	if dialog_cancel_button and not dialog_cancel_button.pressed.is_connected(_on_cancel_create):
		dialog_cancel_button.pressed.connect(_on_cancel_create)

	if delete_hold_screen:
		if not delete_hold_screen.delete_confirmed.is_connected(_on_delete_hold_confirmed):
			delete_hold_screen.delete_confirmed.connect(_on_delete_hold_confirmed)
		if not delete_hold_screen.cancel_requested.is_connected(_on_delete_hold_cancel):
			delete_hold_screen.cancel_requested.connect(_on_delete_hold_cancel)

	_refresh_slots()

func _apply_frosted_panel_styles():
	var panel = $CenterContainer/Panel as Panel
	var dialog = $CreateDialog/CenterContainer/Panel as Panel
	var back = $TopBar/BackButton as Button

	if panel:
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.13, 0.16, 0.24)
		sb.corner_radius_top_left = 16
		sb.corner_radius_top_right = 16
		sb.corner_radius_bottom_left = 16
		sb.corner_radius_bottom_right = 16
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(1, 1, 1, 0.22)
		panel.add_theme_stylebox_override("panel", sb)
	if dialog:
		var sb2 = StyleBoxFlat.new()
		sb2.bg_color = Color(0.14, 0.15, 0.18, 0.32)
		sb2.corner_radius_top_left = 14
		sb2.corner_radius_top_right = 14
		sb2.corner_radius_bottom_left = 14
		sb2.corner_radius_bottom_right = 14
		sb2.border_width_left = 1
		sb2.border_width_right = 1
		sb2.border_width_top = 1
		sb2.border_width_bottom = 1
		sb2.border_color = Color(1, 1, 1, 0.20)
		dialog.add_theme_stylebox_override("panel", sb2)
	# Back is now WildesButton with its own frosted blur (true iOS - blur behind button element)
	# Keep its dim border as set by WildesButton itself (0.10 alpha) - no extra override needed

func _refresh_slots():
	for child in slots_container.get_children():
		child.queue_free()
	slot_instances.clear()

	var all = SaveManager.get_all_slots()
	for slot_id in range(SaveManager.SLOT_COUNT):
		var data = {}
		if slot_id < all.size():
			data = all[slot_id]
		else:
			data = SaveManager.get_slot_info(slot_id)

		var instance = slot_item_scene.instantiate() as SaveSlotItem
		instance.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		instance.size_flags_vertical = 0
		slots_container.add_child(instance)
		instance.setup(slot_id, data)

		if not instance.slot_play_requested.is_connected(_on_slot_play):
			instance.slot_play_requested.connect(_on_slot_play)
		if not instance.slot_delete_requested.is_connected(_on_slot_delete):
			instance.slot_delete_requested.connect(_on_slot_delete)
		if not instance.slot_create_requested.is_connected(_on_slot_create_dialog):
			instance.slot_create_requested.connect(_on_slot_create_dialog)

		slot_instances.append(instance)

func _on_slot_play(slot_id: int):
	var data = SaveManager.load_slot(slot_id)
	if not data.get("exists", false):
		print("[SaveSlotScreen] Slot %d missing, opening create dialog" % slot_id)
		_on_slot_create_dialog(slot_id)
		return
	print("[SaveSlotScreen] Play slot %d seed %d name=%s" % [slot_id, data.get("seed", 0), data.get("world_name", "")])
	_launch_game(slot_id, data)

func _on_slot_create_dialog(slot_id: int):
	print("[SaveSlotScreen] Create dialog for slot %d - seed editable" % slot_id)
	_pending_creation_slot = slot_id
	_pending_creation_seed = SaveManager.generate_random_seed()
	if dialog_name_edit:
		dialog_name_edit.text = "World %d" % (slot_id + 1)
		dialog_name_edit.select_all()
	if dialog_seed_edit:
		dialog_seed_edit.text = str(_pending_creation_seed)
		dialog_seed_edit.placeholder_text = "Leave empty for random, or type custom seed"
	if create_dialog:
		create_dialog.visible = true
		if dialog_name_edit:
			dialog_name_edit.grab_focus()

func _on_randomize_seed():
	_pending_creation_seed = SaveManager.generate_random_seed()
	if dialog_seed_edit:
		dialog_seed_edit.text = str(_pending_creation_seed)
	print("[SaveSlotScreen] Re-rolled seed to %d (editable)" % _pending_creation_seed)

func _parse_seed_input() -> int:
	if dialog_seed_edit == null:
		return _pending_creation_seed
	var txt = dialog_seed_edit.text.strip_edges()
	if txt == "":
		# Empty -> random
		return SaveManager.generate_random_seed()
	# Try parse as int
	if txt.is_valid_int():
		return int(txt)
	# Allow seed as string -> hash to int for custom world names as seeds
	var hashed = txt.hash()
	# Make positive and within range
	if hashed < 0:
		hashed = -hashed
	if hashed == 0:
		hashed = _pending_creation_seed
	return hashed % 2147483646 + 1

func _on_confirm_create():
	if _pending_creation_slot == -1:
		return
	var name_text = "World %d" % (_pending_creation_slot + 1)
	if dialog_name_edit and dialog_name_edit.text.strip_edges() != "":
		name_text = dialog_name_edit.text.strip_edges()

	var final_seed = _parse_seed_input()
	print("[SaveSlotScreen] Creating new world slot %d seed %d (custom input) name='%s' (random terrain)" % [_pending_creation_slot, final_seed, name_text])
	var new_data = SaveManager.create_new_world(_pending_creation_slot, final_seed, name_text)
	if create_dialog:
		create_dialog.visible = false
	_pending_creation_slot = -1
	_launch_game(new_data["slot_id"], new_data)

func _on_cancel_create():
	if create_dialog:
		create_dialog.visible = false
	_pending_creation_slot = -1

func _on_slot_delete(slot_id: int):
	print("[SaveSlotScreen] Delete requested slot %d - show hold-to-delete screen" % slot_id)
	_pending_delete_slot = slot_id
	var info = SaveManager.get_slot_info(slot_id)
	var world_name = info.get("world_name", "World %d" % (slot_id + 1))
	if delete_hold_screen:
		delete_hold_screen.show_for_slot(slot_id, world_name)
	else:
		# Fallback immediate delete if hold screen missing
		var deleted = SaveManager.delete_slot(slot_id)
		if deleted:
			_refresh_slots()

func _on_delete_hold_confirmed(slot_id: int):
	print("[SaveSlotScreen] Hold confirmed - deleting slot %d" % slot_id)
	var deleted = SaveManager.delete_slot(slot_id)
	if deleted:
		print("[SaveSlotScreen] Slot %d deleted after 3s hold" % slot_id)
		_refresh_slots()
	_pending_delete_slot = -1

func _on_delete_hold_cancel():
	print("[SaveSlotScreen] Delete hold cancelled")
	_pending_delete_slot = -1

func _on_back_pressed():
	print("[SaveSlotScreen] Back -> main menu")
	back_requested.emit()
	var parent = get_parent()
	if parent == null:
		parent = get_tree().root
	var has_main_menu = false
	for child in parent.get_children():
		if child is MainMenu and child != self:
			has_main_menu = true
			break
	if not has_main_menu:
		var main_menu_scene = load("res://ui/main_menu/main_menu.tscn") as PackedScene
		if main_menu_scene:
			var main_menu = main_menu_scene.instantiate()
			parent.add_child(main_menu)
			get_tree().current_scene = main_menu
			print("[SaveSlotScreen] Back created MainMenu and set as current_scene")
	queue_free()

var loading_screen_scene: PackedScene = preload("res://ui/main_menu/loading_screen.tscn")

func _launch_game(slot_id: int, data: Dictionary):
	print("[SaveSlotScreen] Launching game via LoadingScreen for slot %d seed %d" % [slot_id, data.get("seed", 0)])
	slot_selected.emit(slot_id, data)
	# Always start loading — previous has_main_menu check prevented re-join after Game->MainMenu->Play
	# because MainMenu is still queued for deletion (queue_free deferred) when slot is clicked quickly
	_start_game_with_loading(slot_id, data)

func _start_game_with_loading(slot_id: int, data: Dictionary):
	var parent = get_parent()
	if parent == null:
		parent = get_tree().root

	var loading_screen = loading_screen_scene.instantiate() as LoadingScreen
	parent.add_child(loading_screen)
	# Keep this screen until loading screen takes over? Loading screen will free others when done
	loading_screen.start_loading(slot_id, data)

	# Free save slot screen after starting loading (loading screen persists)
	queue_free()

func _start_game(slot_id: int, data: Dictionary):
	# Legacy direct start without loading screen (headless tests)
	var game_scene = load("res://game/game.tscn") as PackedScene
	if game_scene == null:
		push_error("[SaveSlotScreen] Failed to load game.tscn")
		return
	var game_instance = game_scene.instantiate() as Game
	game_instance.current_slot_id = slot_id
	game_instance.current_save_data = data

	var parent = get_parent()
	if parent == null:
		parent = get_tree().root
	parent.add_child(game_instance)
	get_tree().current_scene = game_instance

	for child in parent.get_children():
		if child != game_instance and child is Control:
			child.queue_free()
