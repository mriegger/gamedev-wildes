extends Control
class_name DeleteHoldScreen

signal delete_confirmed(slot_id: int)

@onready var world_name_label: Label = $CenterContainer/Panel/VBox/WorldNameLabel
@onready var progress_bar: ProgressBar = $CenterContainer/Panel/VBox/ProgressBar
@onready var hold_button: WildesButton = $CenterContainer/Panel/VBox/HBox/HoldButton
@onready var cancel_button: WildesButton = $CenterContainer/Panel/VBox/HBox/CancelButton

var slot_id: int = -1
var _hold_time: float = 0.0
const HOLD_DURATION: float = 3.0

func _ready():
	set_process(false)
	hold_button.button_down.connect(_on_hold_down)
	hold_button.button_up.connect(_on_hold_up)
	cancel_button.pressed.connect(_on_cancel)

	mouse_filter = Control.MOUSE_FILTER_STOP

func show_for_slot(p_slot_id: int, world_name: String):
	slot_id = p_slot_id
	_hold_time = 0.0
	progress_bar.value = 0
	world_name_label.text = world_name
	hold_button.button_text = "HOLD TO DELETE"
	visible = true
	hold_button.call_deferred("focus_button")

func _on_hold_down():
	_hold_time = 0.0
	set_process(true)

func _on_hold_up():
	_hold_time = 0.0
	set_process(false)
	progress_bar.value = 0
	hold_button.button_text = "HOLD TO DELETE"

func _process(delta):
	_hold_time += delta
	progress_bar.value = (_hold_time / HOLD_DURATION) * 100.0
	hold_button.button_text = "HOLDING... %.1fs / 3s" % _hold_time
	if _hold_time >= HOLD_DURATION:
		set_process(false)
		delete_confirmed.emit(slot_id)
		visible = false
		progress_bar.value = 0
		hold_button.button_text = "HOLD TO DELETE"

func _on_cancel():
	_hold_time = 0.0
	set_process(false)
	progress_bar.value = 0
	hold_button.button_text = "HOLD TO DELETE"
	visible = false

func _unhandled_input(event):
	if visible and event.is_action_pressed("ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()
