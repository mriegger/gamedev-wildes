extends Control
class_name SaveSlotItem

signal slot_play_requested(slot_id: int)
signal slot_delete_requested(slot_id: int)
signal slot_create_requested(slot_id: int)

var slot_id: int = 0
var slot_data: Dictionary = {}

@onready var name_label: Label = $Panel/VBox/NameLabel
@onready var detail_label: Label = $Panel/VBox/DetailLabel
@onready var status_label: Label = $Panel/VBox/StatusLabel
@onready var delete_button: WildesButton = $Panel/VBox/Actions/DeleteButton
@onready var click_area: Button = $ClickArea
@onready var panel: Panel = $Panel

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	delete_button.pressed.connect(_on_delete_pressed)
	click_area.pressed.connect(_on_click_area_pressed)

	_apply_borders()

func _apply_borders():
	var style = WildesStyle.make_modal()
	WildesStyle.apply_frosted_panel(panel, style, 4.5, false)

func setup(p_slot_id: int, data: Dictionary):
	slot_id = p_slot_id
	slot_data = data

	var exists = data.get("exists", false)

	for lbl in [name_label, detail_label, status_label]:
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if exists:
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
		delete_button.button_text = "Delete"
	else:
		name_label.text = "Empty Slot %d" % (slot_id + 1)
		name_label.visible = true
		detail_label.visible = false
		status_label.visible = false
		delete_button.visible = false

func _on_click_area_pressed():
	if slot_data.get("exists", false):
		slot_play_requested.emit(slot_id)
	else:
		slot_create_requested.emit(slot_id)

func _on_delete_pressed():
	slot_delete_requested.emit(slot_id)
