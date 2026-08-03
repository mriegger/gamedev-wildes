extends Control
class_name SaveSlotScreen

@onready var slots_container: VBoxContainer = $CenterContainer/Panel/VBox/SlotsContainer
@onready var back_button: WildesButton = $TopBar/BackButton
@onready var create_dialog: Control = $CreateDialog
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

func _ready():
	SaveManager.ensure_save_dir()

	_apply_frosted_panel_styles()

	if back_button:
		back_button.button_text = "< BACK"
		if not back_button.pressed.is_connected(_on_back_pressed):
			back_button.pressed.connect(_on_back_pressed)

	if create_dialog:
		create_dialog.visible = false
	if dialog_randomize_button and not dialog_randomize_button.pressed.is_connected(_on_randomize_seed):
		dialog_randomize_button.pressed.connect(_on_randomize_seed)
	if dialog_confirm_button and not dialog_confirm_button.pressed.is_connected(_on_confirm_create):
		dialog_confirm_button.pressed.connect(_on_confirm_create)
		dialog_confirm_button.button_text = "CREATE"
	if dialog_cancel_button and not dialog_cancel_button.pressed.is_connected(_on_cancel_create):
		dialog_cancel_button.pressed.connect(_on_cancel_create)

	if delete_hold_screen:
		if not delete_hold_screen.delete_confirmed.is_connected(_on_delete_hold_confirmed):
			delete_hold_screen.delete_confirmed.connect(_on_delete_hold_confirmed)

	_refresh_slots()

func _apply_frosted_panel_styles():
	var panel = $CenterContainer/Panel as Panel
	var dialog = $CreateDialog/CenterContainer/Panel as Panel

	if panel:
		var sb = WildesStyle.make_modal()
		WildesStyle.apply_frosted_panel(panel, sb, 4.5, false)
	if dialog:
		var sb2 = WildesStyle.make_modal()
		WildesStyle.apply_frosted_panel(dialog, sb2, 4.5, false)

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
		_on_slot_create_dialog(slot_id)
		return
	_launch_game(slot_id, data)

func _on_slot_create_dialog(slot_id: int):
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

func _parse_seed_input() -> int:
	if dialog_seed_edit == null:
		return _pending_creation_seed
	var txt = dialog_seed_edit.text.strip_edges()
	if txt == "":
		return SaveManager.generate_random_seed()
	if txt.is_valid_int():
		return int(txt)
	var hashed = txt.hash()
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
	var info = SaveManager.get_slot_info(slot_id)
	var world_name = info.get("world_name", "World %d" % (slot_id + 1))
	if delete_hold_screen:
		delete_hold_screen.show_for_slot(slot_id, world_name)
	else:
		var deleted = SaveManager.delete_slot(slot_id)
		if deleted:
			_refresh_slots()

func _on_delete_hold_confirmed(slot_id: int):
	var deleted = SaveManager.delete_slot(slot_id)
	if deleted:
		_refresh_slots()

func _on_back_pressed():
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
	queue_free()

var loading_screen_scene: PackedScene = preload("res://ui/main_menu/loading_screen.tscn")

func _launch_game(slot_id: int, data: Dictionary):
	_start_game_with_loading(slot_id, data)

func _start_game_with_loading(slot_id: int, data: Dictionary):
	var parent = get_parent()
	if parent == null:
		parent = get_tree().root

	var loading_screen = loading_screen_scene.instantiate() as LoadingScreen
	parent.add_child(loading_screen)
	loading_screen.start_loading(slot_id, data)

	queue_free()
