extends Control
class_name DeleteHoldScreen

## Delete confirmation: user must hold button for 3 seconds to delete world
## Frosted glass blur like other menus

signal delete_confirmed(slot_id: int)
signal cancel_requested

@onready var title_label: Label = $CenterContainer/Panel/VBox/TitleLabel
@onready var world_name_label: Label = $CenterContainer/Panel/VBox/WorldNameLabel
@onready var instruction_label: Label = $CenterContainer/Panel/VBox/InstructionLabel
@onready var progress_bar: ProgressBar = $CenterContainer/Panel/VBox/ProgressBar
@onready var hold_button: WildesButton = $CenterContainer/Panel/VBox/HBox/HoldButton
@onready var cancel_button: WildesButton = $CenterContainer/Panel/VBox/HBox/CancelButton

var slot_id: int = -1
var _holding: bool = false
var _hold_time: float = 0.0
const HOLD_DURATION: float = 3.0

func _ready():
	visible = false
	if progress_bar:
		progress_bar.min_value = 0
		progress_bar.max_value = 100
		progress_bar.value = 0
	if hold_button:
		if not hold_button.button_down.is_connected(_on_hold_down):
			hold_button.button_down.connect(_on_hold_down)
		if not hold_button.button_up.is_connected(_on_hold_up):
			hold_button.button_up.connect(_on_hold_up)
		hold_button.text = "HOLD TO DELETE"
	if cancel_button and not cancel_button.pressed.is_connected(_on_cancel):
		cancel_button.pressed.connect(_on_cancel)

	mouse_filter = Control.MOUSE_FILTER_STOP

func show_for_slot(p_slot_id: int, world_name: String):
	slot_id = p_slot_id
	_holding = false
	_hold_time = 0.0
	if progress_bar:
		progress_bar.value = 0
	if world_name_label:
		world_name_label.text = world_name
	if title_label:
		title_label.text = "Delete World?"
	if instruction_label:
		instruction_label.text = "Hold the button for 3 seconds to permanently delete this world. This cannot be undone."
	visible = true
	print("[DeleteHold] Showing for slot %d name=%s" % [slot_id, world_name])

func _on_hold_down():
	_holding = true
	_hold_time = 0.0
	print("[DeleteHold] Hold started slot %d" % slot_id)

func _on_hold_up():
	if _holding and _hold_time < HOLD_DURATION:
		print("[DeleteHold] Hold released early %.2fs / %.2fs" % [_hold_time, HOLD_DURATION])
	_holding = false
	_hold_time = 0.0
	if progress_bar:
		progress_bar.value = 0

func _process(delta):
	if not visible:
		return
	if _holding:
		_hold_time += delta
		var pct = (_hold_time / HOLD_DURATION) * 100.0
		if progress_bar:
			progress_bar.value = pct
		if hold_button:
			hold_button.text = "HOLDING... %.1fs / 3s" % _hold_time
		if _hold_time >= HOLD_DURATION:
			_holding = false
			print("[DeleteHold] Hold completed - deleting slot %d" % slot_id)
			delete_confirmed.emit(slot_id)
			visible = false
			if progress_bar:
				progress_bar.value = 0
			if hold_button:
				hold_button.text = "HOLD TO DELETE"

func _on_cancel():
	print("[DeleteHold] Cancel")
	_holding = false
	_hold_time = 0.0
	if progress_bar:
		progress_bar.value = 0
	if hold_button:
		hold_button.text = "HOLD TO DELETE"
	visible = false
	cancel_requested.emit()

func _unhandled_input(event):
	if visible and event.is_action_pressed("ui_cancel"):
		_on_cancel()
