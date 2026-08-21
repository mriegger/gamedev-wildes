extends Control
class_name SaveSlotScreen

signal back_requested
signal session_requested(slot_id: int, save_data: Dictionary)

const REGULAR_FONT: FontFile = preload("res://assets/fonts/RobotoSlab-Regular.ttf")
const BOLD_FONT: FontFile = preload("res://assets/fonts/RobotoSlab-Bold.ttf")

@onready var slots_container: VBoxContainer = $CenterContainer/Panel/VBox/SlotsContainer
@onready var back_button: Button = $TopBar/BackButton
@onready var main_panel: Panel = $CenterContainer/Panel
@onready var create_dialog: Control = $CreateDialog
@onready var create_dialog_panel: Panel = $CreateDialog/CenterContainer/Panel
@onready var dialog_name_edit: LineEdit = $CreateDialog/CenterContainer/Panel/VBox/NameEdit
@onready var dialog_seed_edit: LineEdit = $CreateDialog/CenterContainer/Panel/VBox/HBoxSeed/SeedEdit
@onready var dialog_randomize_button: WildesButton = $CreateDialog/CenterContainer/Panel/VBox/HBoxSeed/RandomizeButton
@onready var dialog_confirm_button: WildesButton = $CreateDialog/CenterContainer/Panel/VBox/HBoxActions/ConfirmButton
@onready var dialog_cancel_button: WildesButton = $CreateDialog/CenterContainer/Panel/VBox/HBoxActions/CancelButton
@onready var delete_hold_screen: DeleteHoldScreen = $DeleteHoldScreen
@onready var load_error_dialog: AcceptDialog = $LoadErrorDialog

var slot_item_scene: PackedScene = preload("res://ui/screens/world_select/save_slot_item.tscn")
var slot_instances: Array[SaveSlotItem] = []

var _pending_creation_slot: int = -1
var _pending_creation_seed: int = 0
var _item_catalog: ItemCatalog

func setup(item_catalog: Resource) -> void:
	assert(item_catalog is ItemCatalog)
	assert(_item_catalog == null)
	_item_catalog = item_catalog as ItemCatalog

func _ready():
	assert(_item_catalog != null)
	_apply_panel_styles()
	_setup_back_button()

	back_button.pressed.connect(_on_back_pressed)
	create_dialog.visible = false
	dialog_randomize_button.pressed.connect(_on_randomize_seed)
	dialog_confirm_button.pressed.connect(_on_confirm_create)
	dialog_cancel_button.pressed.connect(_on_cancel_create)
	delete_hold_screen.delete_confirmed.connect(_on_delete_hold_confirmed)

	_refresh_slots()

func _apply_panel_styles() -> void:
	WildesStyle.apply_frosted_panel(main_panel, WildesStyle.make_modal(), 4.5, false)
	WildesStyle.apply_frosted_panel(create_dialog_panel, WildesStyle.make_modal(), 4.5, false)

func _setup_back_button() -> void:
	back_button.add_theme_font_override(&"font", REGULAR_FONT)
	back_button.mouse_entered.connect(_refresh_back_button_font)
	back_button.mouse_exited.connect(_refresh_back_button_font)
	back_button.focus_entered.connect(_refresh_back_button_font)
	back_button.focus_exited.connect(_refresh_back_button_font)

func _refresh_back_button_font() -> void:
	var emphasized := back_button.is_hovered() or back_button.has_focus()
	back_button.add_theme_font_override(&"font", BOLD_FONT if emphasized else REGULAR_FONT)

func _refresh_slots():
	for child in slots_container.get_children():
		child.queue_free()
	slot_instances.clear()

	var all = SaveManager.get_all_slots(_item_catalog)
	for slot_id in range(SaveManager.SLOT_COUNT):
		var data = all[slot_id]

		var instance = slot_item_scene.instantiate() as SaveSlotItem
		instance.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		instance.size_flags_vertical = 0
		slots_container.add_child(instance)
		instance.setup(slot_id, data)

		instance.slot_play_requested.connect(_on_slot_play)
		instance.slot_delete_requested.connect(_on_slot_delete)
		instance.slot_create_requested.connect(_on_slot_create_dialog)

		slot_instances.append(instance)
	_configure_focus_navigation()

func _configure_focus_navigation() -> void:
	if slot_instances.is_empty():
		back_button.call_deferred("grab_focus")
		return
	var first_button := slot_instances[0].click_area
	var last_button := slot_instances[slot_instances.size() - 1].click_area
	back_button.focus_neighbor_top = back_button.get_path_to(last_button)
	back_button.focus_neighbor_bottom = back_button.get_path_to(first_button)
	for index in slot_instances.size():
		var slot := slot_instances[index]
		var primary := slot.click_area
		var previous: Button = back_button if index == 0 else slot_instances[index - 1].click_area
		var next: Button = back_button if index == slot_instances.size() - 1 else slot_instances[index + 1].click_area
		primary.focus_neighbor_top = primary.get_path_to(previous)
		primary.focus_neighbor_bottom = primary.get_path_to(next)
		if slot.delete_button.visible:
			primary.focus_neighbor_right = primary.get_path_to(slot.delete_button)
			slot.delete_button.focus_neighbor_left = slot.delete_button.get_path_to(primary)
			slot.delete_button.focus_neighbor_top = slot.delete_button.get_path_to(previous)
			slot.delete_button.focus_neighbor_bottom = slot.delete_button.get_path_to(next)
	first_button.call_deferred("grab_focus")

func _on_slot_play(slot_id: int):
	var data = slot_instances[slot_id].slot_data
	_request_session(slot_id, data)

func _on_slot_create_dialog(slot_id: int):
	_pending_creation_slot = slot_id
	_pending_creation_seed = SaveManager.generate_random_seed()
	dialog_name_edit.text = "World %d" % (slot_id + 1)
	dialog_name_edit.select_all()
	dialog_seed_edit.text = str(_pending_creation_seed)
	dialog_seed_edit.placeholder_text = "Leave empty for random, or type custom seed"
	create_dialog.visible = true
	dialog_name_edit.grab_focus()

func _on_randomize_seed():
	_pending_creation_seed = SaveManager.generate_random_seed()
	dialog_seed_edit.text = str(_pending_creation_seed)

func _parse_seed_input() -> int:
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
	if dialog_name_edit.text.strip_edges() != "":
		name_text = dialog_name_edit.text.strip_edges()

	var final_seed = _parse_seed_input()
	var new_data = SaveManager.create_new_world(_pending_creation_slot, final_seed, name_text)
	create_dialog.visible = false
	_pending_creation_slot = -1
	_request_session(new_data["slot_id"], new_data)

func _on_cancel_create():
	create_dialog.visible = false
	_pending_creation_slot = -1

func _on_slot_delete(slot_id: int):
	var info = slot_instances[slot_id].slot_data
	var world_name = info.get("world_name", "World %d" % (slot_id + 1))
	delete_hold_screen.show_for_slot(slot_id, world_name)

func _on_delete_hold_confirmed(slot_id: int):
	var deleted = SaveManager.delete_slot(slot_id)
	if deleted:
		_refresh_slots()

func _on_back_pressed():
	back_requested.emit()

func show_load_error(message: String) -> void:
	load_error_dialog.dialog_text = message
	load_error_dialog.popup_centered()

func _request_session(slot_id: int, data: Dictionary):
	session_requested.emit(slot_id, data)
