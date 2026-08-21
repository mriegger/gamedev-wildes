extends Control
class_name SaveSlotItem

signal slot_play_requested(slot_id: int)
signal slot_delete_requested(slot_id: int)
signal slot_create_requested(slot_id: int)

const REGULAR_FONT: FontFile = preload("res://assets/fonts/RobotoSlab-Regular.ttf")
const BOLD_FONT: FontFile = preload("res://assets/fonts/RobotoSlab-Bold.ttf")

var slot_id: int = 0
var slot_data: Dictionary = {}

@onready var name_label: Label = $Panel/VBox/NameLabel
@onready var detail_label: Label = $Panel/VBox/DetailLabel
@onready var status_label: Label = $Panel/VBox/StatusLabel
@onready var delete_button: Button = $Panel/VBox/Actions/DeleteButton
@onready var click_area: Button = $ClickArea
@onready var panel: Panel = $Panel

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	delete_button.pressed.connect(_on_delete_pressed)
	click_area.pressed.connect(_on_click_area_pressed)
	_apply_panel_style()
	_setup_text_emphasis()

func _apply_panel_style() -> void:
	WildesStyle.apply_frosted_panel(panel, WildesStyle.make_modal(), 4.5, false)

func _setup_text_emphasis() -> void:
	name_label.add_theme_font_override(&"font", REGULAR_FONT)
	detail_label.add_theme_font_override(&"font", REGULAR_FONT)
	status_label.add_theme_font_override(&"font", REGULAR_FONT)
	delete_button.add_theme_font_override(&"font", REGULAR_FONT)
	click_area.mouse_entered.connect(_refresh_text_emphasis)
	click_area.mouse_exited.connect(_refresh_text_emphasis)
	click_area.focus_entered.connect(_refresh_text_emphasis)
	click_area.focus_exited.connect(_refresh_text_emphasis)
	delete_button.mouse_entered.connect(_refresh_text_emphasis)
	delete_button.mouse_exited.connect(_refresh_text_emphasis)
	delete_button.focus_entered.connect(_refresh_text_emphasis)
	delete_button.focus_exited.connect(_refresh_text_emphasis)

func _refresh_text_emphasis() -> void:
	var row_emphasized := click_area.is_hovered() or click_area.has_focus()
	var delete_emphasized := delete_button.is_hovered() or delete_button.has_focus()
	name_label.add_theme_font_override(&"font", BOLD_FONT if row_emphasized else REGULAR_FONT)
	delete_button.add_theme_font_override(&"font", BOLD_FONT if delete_emphasized else REGULAR_FONT)

func setup(p_slot_id: int, data: Dictionary):
	slot_id = p_slot_id
	slot_data = data

	var exists = data.get("exists", false)

	for lbl in [name_label, detail_label, status_label]:
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if exists and data.get("incompatible", false):
		name_label.text = data.get("world_name", "World %d" % (slot_id + 1))
		name_label.visible = true
		detail_label.text = "Save version %d" % int(data.get("version", 0))
		detail_label.visible = true
		status_label.text = "Incompatible save"
		status_label.visible = true
		delete_button.visible = true
	elif exists:
		var world_name = data.get("world_name", "World %d" % (slot_id + 1))
		var seed_val = data.get("seed", 0)
		var last_played = data.get("last_played", "Unknown")

		name_label.text = world_name
		name_label.visible = true
		detail_label.text = "Seed: %d" % seed_val
		detail_label.visible = true
		status_label.text = "Last: %s" % last_played
		status_label.visible = true
		delete_button.visible = true
	else:
		name_label.text = "Empty Slot %d" % (slot_id + 1)
		name_label.visible = true
		detail_label.visible = false
		status_label.visible = false
		delete_button.visible = false

func _on_click_area_pressed():
	if slot_data.get("incompatible", false):
		return
	if slot_data.get("exists", false):
		slot_play_requested.emit(slot_id)
	else:
		slot_create_requested.emit(slot_id)

func _on_delete_pressed():
	slot_delete_requested.emit(slot_id)
