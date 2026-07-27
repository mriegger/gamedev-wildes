extends Node3D
# Day and Night Cycle — 20 min total (10 day / 10 night approx) mapped to 24h
# Schedule: 19-6 Night, 6-8 Sunrise, 8-17 Day, 17-19 Sundown. Starts at 6AM sunrise.
# Continuous real-time shadows: single directional light rotates 360 deg, always above horizon
# (moon uses same path at night for continuity, avoiding double shadows / jumps)
# Debug panel toggled with "="

@export var cycle_duration_minutes: float = 20.0 # 10+10 = 20
@export var start_hour: float = 6.0
@export var enable_cycle: bool = true
@export var pause_at_start: bool = false

var cycle_duration_seconds: float:
	get:
		return cycle_duration_minutes * 60.0

var time_of_day: float = 6.0 # 0..24
var _paused_debug: bool = false
var _dragging: bool = false
var _debug_visible: bool = false

var sun_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var world_env_node: WorldEnvironment
var env: Environment

# Debug UI
var debug_layer: CanvasLayer
var time_slider: HSlider
var time_label: Label
var phase_label: Label
var pause_button: Button
var energy_label: Label

var _keys: Array = [] # array of dicts

func _ready():
	time_of_day = start_hour
	_paused_debug = pause_at_start
	_setup_keys()
	_test_find_nodes()
	_duplicate_environment()
	_apply_initial_light_setup()
	_create_debug_ui()
	update_lighting(0.0)
	print("[DayNight] Ready - cycle %.1f min (%.0f sec), start %.1fh" % [cycle_duration_minutes, cycle_duration_seconds, start_hour])

func _setup_keys():
	# FIX: still blown out. Reduce even further, keep saturation.
	# Noon now 0.32 ambient +0.38 sun = 0.70 total vs original 2.9. Shader 0.88*0.85 top.
	_keys = [
		{
			"time": 0.0, # midnight -0.05 darker
			"sky": Color(0.008, 0.010, 0.032),
			"ambient_col": Color(0.56, 0.64, 0.84),
			"ambient_energy": 0.13,
			"sun_col": Color(0.58, 0.66, 0.84),
			"sun_energy": 0.05,
			"shadow_opacity": 0.52,
			"fill_energy": 0.015,
		},
		{
			"time": 5.0, # pre-dawn -0.05
			"sky": Color(0.014, 0.022, 0.055),
			"ambient_col": Color(0.58, 0.64, 0.84),
			"ambient_energy": 0.15,
			"sun_col": Color(0.60, 0.68, 0.86),
			"sun_energy": 0.07,
			"shadow_opacity": 0.50,
			"fill_energy": 0.018,
		},
		{
			"time": 6.0,
			"sky": Color(0.06, 0.07, 0.12),
			"ambient_col": Color(0.72, 0.66, 0.72),
			"ambient_energy": 0.24,
			"sun_col": Color(1.0, 0.52, 0.30),
			"sun_energy": 0.20,
			"shadow_opacity": 0.44,
			"fill_energy": 0.035,
		},
		{
			"time": 7.0,
			"sky": Color(0.28, 0.20, 0.18),
			"ambient_col": Color(0.80, 0.68, 0.60),
			"ambient_energy": 0.30,
			"sun_col": Color(1.0, 0.64, 0.40),
			"sun_energy": 0.30,
			"shadow_opacity": 0.46,
			"fill_energy": 0.05,
		},
		{
			"time": 8.0, # day start +5% golden ambient
			"sky": Color(0.33, 0.48, 0.60),
			"ambient_col": Color(0.867, 0.88, 0.9205),
			"ambient_energy": 0.54,
			"sun_col": Color(1.0, 0.92, 0.78),
			"sun_energy": 0.56,
			"shadow_opacity": 0.46,
			"fill_energy": 0.10,
		},
		{
			"time": 12.0, # noon +5% golden
			"sky": Color(0.42, 0.56, 0.68),
			"ambient_col": Color(0.905, 0.918, 0.9395),
			"ambient_energy": 0.52,
			"sun_col": Color(1.0, 0.96, 0.88),
			"sun_energy": 0.58,
			"shadow_opacity": 0.48,
			"fill_energy": 0.11,
		},
		{
			"time": 17.0, # sundown start +5% golden
			"sky": Color(0.33, 0.48, 0.60),
			"ambient_col": Color(0.867, 0.88, 0.9205),
			"ambient_energy": 0.54,
			"sun_col": Color(1.0, 0.92, 0.78),
			"sun_energy": 0.56,
			"shadow_opacity": 0.46,
			"fill_energy": 0.10,
		},
		{
			"time": 18.0,
			"sky": Color(0.32, 0.22, 0.16),
			"ambient_col": Color(0.80, 0.66, 0.54),
			"ambient_energy": 0.28,
			"sun_col": Color(1.0, 0.56, 0.30),
			"sun_energy": 0.28,
			"shadow_opacity": 0.46,
			"fill_energy": 0.04,
		},
		{
			"time": 19.0, # night start -0.05
			"sky": Color(0.028, 0.036, 0.08),
			"ambient_col": Color(0.58, 0.64, 0.84),
			"ambient_energy": 0.17,
			"sun_col": Color(0.60, 0.68, 0.84),
			"sun_energy": 0.09,
			"shadow_opacity": 0.50,
			"fill_energy": 0.02,
		},
		{
			"time": 22.0, # late night -0.05
			"sky": Color(0.010, 0.014, 0.035),
			"ambient_col": Color(0.54, 0.60, 0.78),
			"ambient_energy": 0.14,
			"sun_col": Color(0.58, 0.64, 0.82),
			"sun_energy": 0.06,
			"shadow_opacity": 0.52,
			"fill_energy": 0.015,
		},
		{
			"time": 24.0, # wrap midnight -0.05
			"sky": Color(0.008, 0.010, 0.032),
			"ambient_col": Color(0.56, 0.64, 0.84),
			"ambient_energy": 0.13,
			"sun_col": Color(0.58, 0.66, 0.84),
			"sun_energy": 0.05,
			"shadow_opacity": 0.52,
			"fill_energy": 0.015,
		},
	]

func _test_find_nodes():
	# Called from _ready, also lazy in case scene not yet fully ready
	sun_light = get_node_or_null("../Sun") as DirectionalLight3D
	if sun_light == null:
		sun_light = get_tree().get_first_node_in_group("sun_light") as DirectionalLight3D
		if sun_light == null:
			# search by name in parent
			var parent = get_parent()
			if parent:
				sun_light = parent.get_node_or_null("Sun") as DirectionalLight3D
	fill_light = get_node_or_null("../SunFill") as DirectionalLight3D
	if fill_light == null:
		var parent = get_parent()
		if parent:
			fill_light = parent.get_node_or_null("SunFill") as DirectionalLight3D
	world_env_node = get_node_or_null("../WorldEnvironment") as WorldEnvironment
	if world_env_node == null:
		var parent = get_parent()
		if parent:
			world_env_node = parent.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if world_env_node == null:
			world_env_node = get_tree().get_first_node_in_group("world_env") as WorldEnvironment

func _find_nodes_if_needed():
	if sun_light == null or fill_light == null or world_env_node == null:
		_test_find_nodes()

func _duplicate_environment():
	if world_env_node and world_env_node.environment:
		# duplicate so we don't overwrite the .tres file resource
		env = world_env_node.environment.duplicate()
		world_env_node.environment = env
	else:
		# create fallback environment
		env = Environment.new()
		env.background_mode = Environment.BG_COLOR
		if world_env_node:
			world_env_node.environment = env

func _apply_initial_light_setup():
	_find_nodes_if_needed()
	if sun_light:
		sun_light.shadow_enabled = true
		sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun_light.directional_shadow_split_1 = 0.15
		sun_light.directional_shadow_split_2 = 0.35
		sun_light.directional_shadow_split_3 = 0.70
		sun_light.directional_shadow_blend_splits = true
		sun_light.shadow_bias = 0.05
		sun_light.shadow_normal_bias = 1.2
		sun_light.shadow_blur = 1.2
		sun_light.directional_shadow_max_distance = 220.0
		sun_light.directional_shadow_fade_start = 0.85
		sun_light.shadow_reverse_cull_face = true
	if fill_light:
		fill_light.shadow_enabled = false
		fill_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS

func _process(delta):
	_find_nodes_if_needed()
	# clock advances only during active play (not paused, not debug paused)
	if enable_cycle and not _paused_debug and not get_tree().paused:
		# only advance if not dragging slider (to allow precise manual control)
		if not _dragging:
			var hours_per_sec = 24.0 / cycle_duration_seconds
			time_of_day += delta * hours_per_sec
			if time_of_day >= 24.0:
				time_of_day -= 24.0
			elif time_of_day < 0.0:
				time_of_day += 24.0
	update_lighting(delta)
	_update_debug_ui()

func update_lighting(_delta: float):
	_find_nodes_if_needed()
	if sun_light == null or env == null:
		return

	# --- Compute azimuth and elevation ---
	# Day: 6-19 = 13h maps 0..PI, Night: 19-30 (19-24 + 0-6) maps PI..TAU
	var is_day = time_of_day >= 6.0 and time_of_day < 19.0
	var azimuth_rad: float
	var elev_factor: float # 0..1 low->high

	if is_day:
		var day_progress = (time_of_day - 6.0) / 13.0 # 0..1
		day_progress = clamp(day_progress, 0.0, 1.0)
		azimuth_rad = day_progress * PI # 0..180 deg east->west
		elev_factor = sin(day_progress * PI) # 0->1->0
	else:
		var nt = time_of_day
		if nt < 6.0:
			nt += 24.0
		var night_progress = (nt - 19.0) / 11.0 # 0..1
		night_progress = clamp(night_progress, 0.0, 1.0)
		azimuth_rad = PI + night_progress * PI # 180..360 deg west->east via north
		elev_factor = sin(night_progress * PI) # 0->1->0

	var elev_low_deg = 4.5
	var elev_high_day = 58.0
	var elev_high_night = 38.0
	var high = elev_high_day if is_day else elev_high_night
	var elev_deg = lerp(elev_low_deg, high, elev_factor)
	var elev_rad = deg_to_rad(elev_deg)

	# sun position vector from origin to sun/moon (above horizon Y>0)
	var cos_e = cos(elev_rad)
	var sin_e = sin(elev_rad)
	var cos_az = cos(azimuth_rad)
	var sin_az = sin(azimuth_rad)

	# X east, Z south (arbitrary but consistent)
	var sun_pos = Vector3(cos_az * cos_e, sin_e, sin_az * cos_e)
	# light direction is from sun to scene = -sun_pos
	var sun_dir = -sun_pos.normalized()
	# Ensure Y is negative (shining down). sun_pos Y positive => sun_dir Y negative
	# sun_pos should always have Y >0 because elev 4..58 >0, so sun_dir Y negative good.

	_set_light_direction(sun_light, sun_dir)

	# Shadow softness based on elevation: lower sun => softer, slightly higher bias to avoid acne
	var blur = 1.0 + (1.0 - elev_factor) * 0.9 # 1.0 noon -> 1.9 horizon
	var bias = 0.03 + (1.0 - elev_factor) * 0.09
	sun_light.shadow_blur = blur
	sun_light.shadow_bias = bias
	# Keep normal bias a bit high for voxel terrain
	sun_light.shadow_normal_bias = 1.0 + (1.0 - elev_factor) * 0.6

	# Fill light opposite side, same elevation but lower, to provide subtle fill without double shadows
	if fill_light:
		# Fill position opposite horizontally, half elevation
		var fill_pos = Vector3(-cos_az * cos_e * 0.8, sin_e * 0.55, -sin_az * cos_e * 0.8)
		var fill_dir = -fill_pos.normalized()
		_set_light_direction(fill_light, fill_dir)

	# --- Interpolate colors ---
	var state = _get_interpolated_state(time_of_day)

	# Environment - FIX blown noon: use COLOR source for precise control, not BG which adds sky wash
	env.background_mode = Environment.BG_COLOR
	env.background_color = state["sky"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = state["ambient_col"]
	env.ambient_light_energy = state["ambient_energy"]
	# Keep sky contribution very low to avoid washed colors
	var sky_contrib = 0.08 if not is_day else lerp(0.08, 0.15, elev_factor)
	env.ambient_light_sky_contribution = sky_contrib
	# In Godot 4, sun contribution to ambient is handled via sky_contribution + ambient source,
	# so we modulate it via sky_contrib (lower at night for cool look already accounted)

	# Sun light
	sun_light.light_color = state["sun_col"]
	sun_light.light_energy = state["sun_energy"]
	sun_light.shadow_opacity = state["shadow_opacity"]

	# Fill light - subtle opposite fill, slightly cooler/bluer at night
	if fill_light:
		# Fill color slightly mixed with ambient
		var fill_col = state["ambient_col"].lerp(state["sky"], 0.28)
		fill_light.light_color = fill_col
		fill_light.light_energy = state["fill_energy"]

	# Ensure no double shadows, no flicker - SunFill never casts shadow
	if fill_light:
		fill_light.shadow_enabled = false

func _set_light_direction(light: DirectionalLight3D, dir: Vector3):
	if light == null:
		return
	dir = dir.normalized()
	# Avoid degenerate when dir almost straight down/up
	var up = Vector3.UP
	if abs(dir.dot(up)) > 0.9995:
		up = Vector3.FORWARD
	# Use look_at: light's -Z points to target, so target = origin + dir
	var origin = light.global_transform.origin
	# If light at zero, give it some offset to avoid zero transform issues
	if origin == Vector3.ZERO:
		origin = Vector3(0, 25, 0)
		light.global_transform.origin = origin
	# look_at will set rotation so -Z = dir
	light.look_at(origin + dir, up)

func _get_interpolated_state(t: float) -> Dictionary:
	t = fmod(t, 24.0)
	if t < 0:
		t += 24.0
	# Find bracketing keys
	for i in range(_keys.size() - 1):
		var k0 = _keys[i]
		var k1 = _keys[i + 1]
		if t >= k0["time"] and t < k1["time"]:
			var span = k1["time"] - k0["time"]
			var f = 0.0
			if span > 0.001:
				f = (t - k0["time"]) / span
			return _lerp_state(k0, k1, f)
	# Wrap case: after last key before 24 handled by last key entry at 24 == first
	# fallback to first
	return _lerp_state(_keys[0], _keys[0], 0.0)

func _lerp_state(a: Dictionary, b: Dictionary, f: float) -> Dictionary:
	# smoothstep for softer transitions, avoid hard edges
	var sf = f # could use smoothstep if desired: f*f*(3-2*f)
	# Use cubic smoothing only near sunrise/sunset to avoid seams? Keep linear for simplicity but smoothstep helps
	sf = sf * sf * (3.0 - 2.0 * sf)
	return {
		"sky": a["sky"].lerp(b["sky"], sf),
		"ambient_col": a["ambient_col"].lerp(b["ambient_col"], sf),
		"ambient_energy": lerp(a["ambient_energy"], b["ambient_energy"], sf),
		"sun_col": a["sun_col"].lerp(b["sun_col"], sf),
		"sun_energy": lerp(a["sun_energy"], b["sun_energy"], sf),
		"shadow_opacity": lerp(a["shadow_opacity"], b["shadow_opacity"], sf),
		"fill_energy": lerp(a["fill_energy"], b["fill_energy"], sf),
	}

func _get_phase_name(t: float) -> String:
	if t >= 19.0 or t < 6.0:
		return "Night (7PM-6AM)"
	elif t >= 6.0 and t < 8.0:
		return "Sunrise (6AM-8AM)"
	elif t >= 8.0 and t < 17.0:
		return "Daytime (8AM-5PM)"
	else:
		return "Sundown (5PM-7PM)"

# ---------------- Debug UI ----------------

func _create_debug_ui():
	if debug_layer != null:
		return
	debug_layer = CanvasLayer.new()
	debug_layer.name = "DebugTimeLayer"
	debug_layer.layer = 20
	debug_layer.visible = false
	add_child(debug_layer)

	var panel = Panel.new()
	panel.name = "DebugPanel"
	panel.custom_minimum_size = Vector2(380, 200)
	panel.size = Vector2(380, 210)
	panel.position = Vector2(12, 12)
	# semi-transparent dark
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
	debug_layer.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.position = Vector2(14, 14)
	vbox.size = Vector2(352, 182)
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "Day/Night Debug (= to toggle)"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	vbox.add_child(title)

	time_label = Label.new()
	time_label.text = "Time: 06:00"
	time_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(time_label)

	phase_label = Label.new()
	phase_label.text = "Phase: Sunrise"
	phase_label.add_theme_font_size_override("font_size", 12)
	phase_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	vbox.add_child(phase_label)

	energy_label = Label.new()
	energy_label.text = "Sun: 1.0"
	energy_label.add_theme_font_size_override("font_size", 11)
	energy_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	vbox.add_child(energy_label)

	time_slider = HSlider.new()
	time_slider.name = "TimeSlider"
	time_slider.min_value = 0.0
	time_slider.max_value = 24.0
	time_slider.step = 0.01
	time_slider.value = time_of_day
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
	help.add_theme_color_override("font_color", Color(0.6,0.6,0.65))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(help)

	# Connections
	time_slider.value_changed.connect(_on_slider_value_changed)
	time_slider.drag_started.connect(_on_slider_drag_started)
	time_slider.drag_ended.connect(_on_slider_drag_ended)
	pause_button.toggled.connect(_on_pause_toggled)
	reset_btn.pressed.connect(_on_reset_sunrise)
	midnight_btn.pressed.connect(_on_reset_midnight)

func _on_slider_value_changed(v: float):
	time_of_day = v
	# update lighting immediately
	update_lighting(0.0)

func _on_slider_drag_started():
	_dragging = true

func _on_slider_drag_ended(_value_changed: bool):
	_dragging = false

func _on_pause_toggled(pressed: bool):
	_paused_debug = pressed
	if pressed:
		pause_button.text = "Resume"
	else:
		pause_button.text = "Pause"

func _on_reset_sunrise():
	time_of_day = 6.0
	time_slider.value = time_of_day
	_paused_debug = false
	pause_button.button_pressed = false
	pause_button.text = "Pause"

func _on_reset_midnight():
	time_of_day = 0.0
	time_slider.value = time_of_day

func _update_debug_ui():
	if debug_layer == null or time_slider == null:
		return
	if not _dragging:
		time_slider.value = time_of_day
	if time_label:
		var h = int(time_of_day)
		var m = int((time_of_day - h) * 60.0)
		time_label.text = "Time: %02d:%02d (%.2f h)" % [h, m, time_of_day]
	if phase_label:
		phase_label.text = "Phase: %s" % _get_phase_name(time_of_day)
	if energy_label and sun_light:
		energy_label.text = "Sun/Moon E: %.2f | Ambient E: %.2f | Shadows: %.2f" % [sun_light.light_energy, env.ambient_light_energy if env else 0.0, sun_light.shadow_opacity]

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		# "=" key is KEY_EQUAL (61). Also handle plus and keypad equal for convenience
		var is_equal = false
		if event.keycode == KEY_EQUAL or event.keycode == KEY_PLUS or event.keycode == KEY_KP_ADD:
			is_equal = true
		# also check unicode: "=" is 61
		if event.unicode == 61:
			is_equal = true
		# fallback: as_text contains "="
		if "=" in event.as_text() or event.as_text() == "Equal":
			is_equal = true
		if is_equal:
			_debug_visible = !_debug_visible
			if debug_layer:
				debug_layer.visible = _debug_visible
			print("[DayNight] Debug panel %s" % ("visible" if _debug_visible else "hidden"))
			get_viewport().set_input_as_handled()

func get_time_of_day() -> float:
	return time_of_day

func set_time_of_day(h: float):
	time_of_day = fmod(h, 24.0)
	if time_of_day < 0:
		time_of_day += 24.0

func get_phase() -> String:
	return _get_phase_name(time_of_day)
