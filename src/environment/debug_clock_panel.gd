extends CanvasLayer
class_name DebugClockPanel

## DebugClockPanel - dev controls for game time, canonical, no compatibility wrappers

var clock: GameClock = null
var values: DayNightValues = null

var time_slider: HSlider
var time_label: Label
var phase_label: Label
var pause_button: Button
var energy_label: Label
var panel: Panel
var _dragging: bool = false
var _visible_debug: bool = false


func _ready():
	layer = 20
	visible = false
	_build_ui()
	_update_ui()


func _build_ui():
	if panel != null:
		return
	panel = Panel.new()
	panel.name = "DebugPanel"
	panel.custom_minimum_size = Vector2(380, 200)
	panel.size = Vector2(380, 210)
	panel.position = Vector2(12, 12)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.10, 0.88)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.4, 0.4, 0.5, 0.6)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.position = Vector2(14, 14)
	vbox.size = Vector2(352, 182)
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "Day/Night Debug (= to toggle)"
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	time_label = Label.new()
	time_label.text = "Time: 06:00"
	vbox.add_child(time_label)

	phase_label = Label.new()
	phase_label.text = "Phase: Sunrise"
	vbox.add_child(phase_label)

	energy_label = Label.new()
	energy_label.text = "Sun: 1.0"
	vbox.add_child(energy_label)

	time_slider = HSlider.new()
	time_slider.min_value = 0.0
	time_slider.max_value = 24.0
	time_slider.step = 0.01
	time_slider.value = clock.time_of_day if clock else 6.0
	time_slider.custom_minimum_size = Vector2(0, 22)
	time_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(time_slider)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	pause_button = Button.new()
	pause_button.text = "Pause"
	pause_button.toggle_mode = true
	pause_button.custom_minimum_size = Vector2(80, 28)
	hbox.add_child(pause_button)

	var reset_btn = Button.new()
	reset_btn.text = "Sunrise (6AM)"
	reset_btn.custom_minimum_size = Vector2(110, 28)
	hbox.add_child(reset_btn)

	var midnight_btn = Button.new()
	midnight_btn.text = "Midnight"
	midnight_btn.custom_minimum_size = Vector2(80, 28)
	hbox.add_child(midnight_btn)

	var help = Label.new()
	help.text = "Cycle: 20 min (10 day +10 night). Slider controls time."
	help.add_theme_font_size_override("font_size", 10)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(help)

	time_slider.value_changed.connect(_on_slider_value_changed)
	time_slider.drag_started.connect(_on_slider_drag_started)
	time_slider.drag_ended.connect(_on_slider_drag_ended)
	pause_button.toggled.connect(_on_pause_toggled)
	reset_btn.pressed.connect(_on_reset_sunrise)
	midnight_btn.pressed.connect(_on_reset_midnight)


func _on_slider_value_changed(v: float):
	if clock:
		clock.set_time_of_day(v)

func _on_slider_drag_started():
	_dragging = true
	if clock:
		clock.set_dragging(true)

func _on_slider_drag_ended(_value_changed: bool):
	_dragging = false
	if clock:
		clock.set_dragging(false)

func _on_pause_toggled(pressed: bool):
	if clock:
		clock.set_paused(pressed)
	pause_button.text = "Resume" if pressed else "Pause"

func _on_reset_sunrise():
	if clock:
		clock.set_time_of_day(6.0)
		time_slider.value = clock.time_of_day
		clock.set_paused(false)
		pause_button.button_pressed = false

func _on_reset_midnight():
	if clock:
		clock.set_time_of_day(0.0)
		time_slider.value = clock.time_of_day

func _on_clock_time_changed(_t: float):
	_update_ui()

func _process(_delta):
	_update_ui()

func _update_ui():
	if time_slider == null or clock == null:
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
			_visible_debug = !_visible_debug
			visible = _visible_debug

func inject(clock_node: GameClock, values_node: DayNightValues = null):
	clock = clock_node
	values = values_node
	if clock:
		if clock.has_signal("time_changed") and not clock.time_changed.is_connected(_on_clock_time_changed):
			clock.time_changed.connect(_on_clock_time_changed)
		if time_slider:
			time_slider.value = clock.time_of_day
	_update_ui()
