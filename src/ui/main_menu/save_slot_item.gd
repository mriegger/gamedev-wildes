extends Control
class_name SaveSlotItem

## SaveSlotItem - click anywhere to play/create, no PLAY/CREATE buttons visible
## Center aligned: Empty -> only "Empty Slot X", Existing -> World name + Seed + Last played

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
	if panel:
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if delete_button and not delete_button.pressed.is_connected(_on_delete_pressed):
		delete_button.pressed.connect(_on_delete_pressed)
	if click_area and not click_area.pressed.is_connected(_on_click_area_pressed):
		click_area.pressed.connect(_on_click_area_pressed)

	# Apply very dim low opacity border but also slightly visible outline for SELECT WORLD
	_apply_borders()

func _apply_borders():
	if panel:
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.14, 0.15, 0.19, 0.26)
		sb.corner_radius_top_left = 12
		sb.corner_radius_top_right = 12
		sb.corner_radius_bottom_left = 12
		sb.corner_radius_bottom_right = 12
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(1, 1, 1, 0.22) # more visible outline for SELECT WORLD slots
		panel.add_theme_stylebox_override("panel", sb)

func setup(p_slot_id: int, data: Dictionary):
	slot_id = p_slot_id
	slot_data = data

	var exists = data.get("exists", false)

	# Center align all labels
	for lbl in [name_label, detail_label, status_label]:
		if lbl:
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if exists:
		var world_name = data.get("world_name", "World %d" % (slot_id + 1))
		var seed_val = data.get("seed", 0)
		var last_played = data.get("last_played", "Unknown")

		if name_label:
			name_label.text = world_name
			name_label.visible = true
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if detail_label:
			detail_label.text = "Seed: %d" % seed_val
			detail_label.visible = true
			detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if status_label:
			status_label.text = "Last: %s" % last_played
			status_label.visible = true
			status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		if delete_button:
			delete_button.visible = true
			delete_button.text = "Delete"
	else:
		# Empty slot - only keep Empty Slot X, center aligned, no random terrain text
		if name_label:
			name_label.text = "Empty Slot %d" % (slot_id + 1)
			name_label.visible = true
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if detail_label:
			detail_label.visible = false
		if status_label:
			status_label.visible = false
		if delete_button:
			delete_button.visible = false

func _on_click_area_pressed():
	if slot_data.get("exists", false):
		print("[SaveSlotItem] Click existing %d -> PLAY" % slot_id)
		slot_play_requested.emit(slot_id)
	else:
		print("[SaveSlotItem] Click empty %d -> CREATE" % slot_id)
		slot_create_requested.emit(slot_id)

func _on_delete_pressed():
	print("[SaveSlotItem] Delete slot %d" % slot_id)
	slot_delete_requested.emit(slot_id)
