extends CanvasLayer
class_name DebugClockPanel

var clock: GameClock
var values: DayNightValues

@onready var panel: Panel = $DebugPanel
@onready var time_slider: HSlider = $DebugPanel/VBox/TimeSlider
@onready var time_label: Label = $DebugPanel/VBox/TimeLabel
@onready var phase_label: Label = $DebugPanel/VBox/PhaseLabel
@onready var pause_button: Button = $DebugPanel/VBox/Controls/PauseButton
@onready var energy_label: Label = $DebugPanel/VBox/EnergyLabel
@onready var reset_button: Button = $DebugPanel/VBox/Controls/SunriseButton
@onready var midnight_button: Button = $DebugPanel/VBox/Controls/MidnightButton
var _dragging: bool = false

func _ready():
	set_process_unhandled_input(false)
	var style = WildesStyle.make_panel(Color(0.08, 0.08, 0.10, 0.88), 8, Color(0.4, 0.4, 0.5, 0.6), 1)
	panel.add_theme_stylebox_override("panel", style)
	time_slider.value_changed.connect(_on_slider_value_changed)
	time_slider.drag_started.connect(_on_slider_drag_started)
	time_slider.drag_ended.connect(_on_slider_drag_ended)
	pause_button.toggled.connect(_on_pause_toggled)
	reset_button.pressed.connect(_on_reset_sunrise)
	midnight_button.pressed.connect(_on_reset_midnight)

func _on_slider_value_changed(v: float):
	clock.set_time_of_day(v)

func _on_slider_drag_started():
	_dragging = true
	clock.set_dragging(true)

func _on_slider_drag_ended(_value_changed: bool):
	_dragging = false
	clock.set_dragging(false)

func _on_pause_toggled(pressed: bool):
	clock.set_paused(pressed)
	pause_button.text = "Resume" if pressed else "Pause"

func _on_reset_sunrise():
	clock.set_time_of_day(6.0)
	time_slider.value = clock.time_of_day
	clock.set_paused(false)
	pause_button.button_pressed = false

func _on_reset_midnight():
	clock.set_time_of_day(0.0)
	time_slider.value = clock.time_of_day

func _on_clock_time_changed(_t: float):
	_update_ui()

func _update_ui():
	if not visible:
		return
	if not _dragging:
		time_slider.value = clock.time_of_day
	var h = int(clock.time_of_day)
	var m = int((clock.time_of_day - h) * 60.0)
	time_label.text = "Time: %02d:%02d (%.2f h)" % [h, m, clock.time_of_day]
	phase_label.text = "Phase: %s" % clock.get_phase()
	if values and values.sun_light and values.env:
		energy_label.text = "Sun/Moon E: %.2f | Ambient E: %.2f | Shadows: %.2f" % [values.sun_light.light_energy, values.env.ambient_light_energy, values.sun_light.shadow_opacity]
	else:
		energy_label.text = "Norm: %.3f | Paused: %s" % [clock.get_normalized(), clock.is_paused()]

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_EQUAL or "=" in event.as_text():
			if visible:
				visible = false
				clock.time_changed.disconnect(_on_clock_time_changed)
			else:
				clock.time_changed.connect(_on_clock_time_changed)
				visible = true
				_update_ui()

func inject(clock_node: GameClock, values_node: DayNightValues):
	clock = clock_node
	values = values_node
	set_process_unhandled_input(true)
