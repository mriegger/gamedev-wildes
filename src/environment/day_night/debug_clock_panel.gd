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
@onready var shadow_enabled: CheckButton = $DebugPanel/VBox/ShadowToggles/ShadowEnabled
@onready var reverse_cull: CheckButton = $DebugPanel/VBox/ShadowToggles/ReverseCull
@onready var reset_shadows: Button = $DebugPanel/VBox/ShadowToggles/ResetShadows
@onready var opacity_slider: HSlider = $DebugPanel/VBox/ShadowGrid/OpacitySlider
@onready var opacity_value: Label = $DebugPanel/VBox/ShadowGrid/OpacityValue
@onready var bias_slider: HSlider = $DebugPanel/VBox/ShadowGrid/BiasSlider
@onready var bias_value: Label = $DebugPanel/VBox/ShadowGrid/BiasValue
@onready var normal_bias_slider: HSlider = $DebugPanel/VBox/ShadowGrid/NormalBiasSlider
@onready var normal_bias_value: Label = $DebugPanel/VBox/ShadowGrid/NormalBiasValue
@onready var blur_slider: HSlider = $DebugPanel/VBox/ShadowGrid/BlurSlider
@onready var blur_value: Label = $DebugPanel/VBox/ShadowGrid/BlurValue
@onready var distance_slider: HSlider = $DebugPanel/VBox/ShadowGrid/DistanceSlider
@onready var distance_value: Label = $DebugPanel/VBox/ShadowGrid/DistanceValue
@onready var fade_slider: HSlider = $DebugPanel/VBox/ShadowGrid/FadeSlider
@onready var fade_value: Label = $DebugPanel/VBox/ShadowGrid/FadeValue
var _dragging: bool = false
var _syncing_shadows: bool = false
var _input_enabled: bool = false

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
	shadow_enabled.toggled.connect(_on_shadow_enabled_toggled)
	reverse_cull.toggled.connect(_on_reverse_cull_toggled)
	reset_shadows.pressed.connect(_on_reset_shadows)
	opacity_slider.value_changed.connect(_on_opacity_changed)
	bias_slider.value_changed.connect(_on_bias_changed)
	normal_bias_slider.value_changed.connect(_on_normal_bias_changed)
	blur_slider.value_changed.connect(_on_blur_changed)
	distance_slider.value_changed.connect(_on_distance_changed)
	fade_slider.value_changed.connect(_on_fade_changed)

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
	time_slider.set_value_no_signal(clock.time_of_day)
	clock.set_paused(false)
	pause_button.button_pressed = false

func _on_reset_midnight():
	clock.set_time_of_day(0.0)
	time_slider.set_value_no_signal(clock.time_of_day)

func _on_shadow_enabled_toggled(enabled: bool):
	if not _syncing_shadows:
		values.set_shadow_enabled(enabled)

func _on_reverse_cull_toggled(enabled: bool):
	if not _syncing_shadows:
		values.set_shadow_reverse_cull(enabled)

func _on_reset_shadows():
	values.reset_shadow_values(clock.time_of_day)
	_sync_shadow_controls()

func _on_opacity_changed(value: float):
	opacity_value.text = "%.2f" % value
	if not _syncing_shadows:
		values.set_shadow_opacity(value)

func _on_bias_changed(value: float):
	bias_value.text = "%.3f" % value
	if not _syncing_shadows:
		values.set_shadow_bias(value)

func _on_normal_bias_changed(value: float):
	normal_bias_value.text = "%.2f" % value
	if not _syncing_shadows:
		values.set_shadow_normal_bias(value)

func _on_blur_changed(value: float):
	blur_value.text = "%.2f" % value
	if not _syncing_shadows:
		values.set_shadow_blur(value)

func _on_distance_changed(value: float):
	distance_value.text = "%.0f" % value
	if not _syncing_shadows:
		values.set_shadow_max_distance(value)

func _on_fade_changed(value: float):
	fade_value.text = "%.2f" % value
	if not _syncing_shadows:
		values.set_shadow_fade_start(value)

func _sync_shadow_controls():
	if values == null or values.sun_light == null:
		return
	_syncing_shadows = true
	var light := values.sun_light
	shadow_enabled.button_pressed = light.shadow_enabled
	reverse_cull.button_pressed = light.shadow_reverse_cull_face
	opacity_slider.value = light.shadow_opacity
	bias_slider.value = light.shadow_bias
	normal_bias_slider.value = light.shadow_normal_bias
	blur_slider.value = light.shadow_blur
	distance_slider.value = light.directional_shadow_max_distance
	fade_slider.value = light.directional_shadow_fade_start
	opacity_value.text = "%.2f" % light.shadow_opacity
	bias_value.text = "%.3f" % light.shadow_bias
	normal_bias_value.text = "%.2f" % light.shadow_normal_bias
	blur_value.text = "%.2f" % light.shadow_blur
	distance_value.text = "%.0f" % light.directional_shadow_max_distance
	fade_value.text = "%.2f" % light.directional_shadow_fade_start
	_syncing_shadows = false

func _on_clock_time_changed(_t: float):
	_update_ui()

func _update_ui():
	if not visible:
		return
	if not _dragging:
		time_slider.set_value_no_signal(clock.time_of_day)
	var h = int(clock.time_of_day)
	var m = int((clock.time_of_day - h) * 60.0)
	time_label.text = "Time: %02d:%02d (%.2f h)" % [h, m, clock.time_of_day]
	phase_label.text = "Phase: %s" % clock.get_phase()
	if values and values.sun_light and values.env:
		energy_label.text = "Sun/Moon E: %.2f | Ambient E: %.2f | Shadows: %.2f" % [values.sun_light.light_energy, values.env.ambient_light_energy, values.sun_light.shadow_opacity]
		_sync_shadow_controls()
	else:
		energy_label.text = "Norm: %.3f | Paused: %s" % [clock.get_normalized(), clock.is_paused()]

func _unhandled_input(event):
	if not _input_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_EQUAL or "=" in event.as_text():
			if visible:
				hide_panel()
			else:
				show_panel()

func show_panel():
	assert(clock != null)
	if not clock.time_changed.is_connected(_on_clock_time_changed):
		clock.time_changed.connect(_on_clock_time_changed)
	visible = true
	_update_ui()

func hide_panel():
	visible = false
	if clock == null:
		return
	if _dragging:
		_dragging = false
		clock.set_dragging(false)
	if clock.time_changed.is_connected(_on_clock_time_changed):
		clock.time_changed.disconnect(_on_clock_time_changed)

func is_open() -> bool:
	return visible

func is_input_enabled() -> bool:
	return _input_enabled

func disable_input():
	hide_panel()
	_input_enabled = false
	set_process_unhandled_input(false)

func enable_input():
	_input_enabled = true
	set_process_unhandled_input(true)

func inject(clock_node: GameClock, values_node: DayNightValues):
	clock = clock_node
	values = values_node
	_sync_shadow_controls()
	enable_input()
