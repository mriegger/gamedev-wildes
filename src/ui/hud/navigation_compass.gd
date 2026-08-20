extends Control

const HALF_VIEW_DEGREES: float = 90.0
const EDGE_INSET: float = 18.0
const RULER_Y: float = 31.0
const MENU_FADE_SECONDS: float = 0.08
const LABELS: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

var _camera: Camera3D
var _tracked_position: Node3D
var _target_position: Vector3
var _has_target: bool = false
var _menu_open: bool = false
var _available: bool = true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)

func setup(camera: Camera3D, tracked_position: Node3D) -> void:
	assert(camera != null and tracked_position != null)
	assert(_camera == null and _tracked_position == null)
	_camera = camera
	_tracked_position = tracked_position
	visible = true
	set_process(true)
	queue_redraw()

func set_target_position(target_position: Vector3) -> void:
	_target_position = target_position
	_has_target = true
	queue_redraw()

func clear_target() -> void:
	_has_target = false
	queue_redraw()

func set_menu_open(open: bool) -> void:
	_menu_open = open

func set_available(available: bool) -> void:
	_available = available

func _process(delta: float) -> void:
	var target_alpha := 1.0 if _available and not _menu_open else 0.0
	self_modulate.a = move_toward(self_modulate.a, target_alpha, delta / MENU_FADE_SECONDS)
	queue_redraw()

func _draw() -> void:
	if _camera == null or _tracked_position == null:
		return
	var width := size.x
	var usable_width := maxf(width - EDGE_INSET * 2.0, 1.0)
	var center_x := width * 0.5
	draw_line(Vector2(EDGE_INSET, RULER_Y), Vector2(width - EDGE_INSET, RULER_Y), Color.BLACK, 3.0)
	draw_line(Vector2(EDGE_INSET, RULER_Y), Vector2(width - EDGE_INSET, RULER_Y), Color.WHITE, 1.0)
	var heading := _get_heading_degrees()
	var font := get_theme_default_font()
	for bearing in range(0, 360, 15):
		var relative := wrapf(float(bearing) - heading, -180.0, 180.0)
		if absf(relative) > HALF_VIEW_DEGREES:
			continue
		var x := center_x + relative / HALF_VIEW_DEGREES * usable_width * 0.5
		var major := bearing % 45 == 0
		var tick_height := 8.0 if major else 4.0
		draw_line(Vector2(x, RULER_Y - tick_height * 0.5), Vector2(x, RULER_Y + tick_height * 0.5), Color.BLACK, 3.0)
		draw_line(Vector2(x, RULER_Y - tick_height * 0.5), Vector2(x, RULER_Y + tick_height * 0.5), Color.WHITE, 1.0)
		if major:
			var label := LABELS[roundi(float(bearing) / 45.0)]
			var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string_outline(font, Vector2(x - label_width * 0.5, 18.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 2, Color.BLACK)
			draw_string(font, Vector2(x - label_width * 0.5, 18.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	draw_colored_polygon(PackedVector2Array([
		Vector2(center_x - 6.0, 49.0),
		Vector2(center_x + 6.0, 49.0),
		Vector2(center_x, 40.0),
	]), Color.BLACK)
	draw_colored_polygon(PackedVector2Array([
		Vector2(center_x - 4.0, 48.0),
		Vector2(center_x + 4.0, 48.0),
		Vector2(center_x, 42.0),
	]), Color.WHITE)
	if _has_target:
		_draw_target_marker(center_x, usable_width, font)

func _draw_target_marker(center_x: float, usable_width: float, font: Font) -> void:
	var relative := _get_target_relative_bearing()
	var x := center_x + clampf(relative, -HALF_VIEW_DEGREES, HALF_VIEW_DEGREES) / HALF_VIEW_DEGREES * usable_width * 0.5
	var color := Color(1.0, 0.72, 0.16, 1.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(x, RULER_Y - 7.0),
		Vector2(x + 7.0, RULER_Y),
		Vector2(x, RULER_Y + 7.0),
		Vector2(x - 7.0, RULER_Y),
	]), Color.BLACK)
	draw_colored_polygon(PackedVector2Array([
		Vector2(x, RULER_Y - 5.0),
		Vector2(x + 5.0, RULER_Y),
		Vector2(x, RULER_Y + 5.0),
		Vector2(x - 5.0, RULER_Y),
	]), color)
	var label_width := font.get_string_size("D", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string_outline(font, Vector2(x - label_width * 0.5, 58.0), "D", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 2, Color.BLACK)
	draw_string(font, Vector2(x - label_width * 0.5, 58.0), "D", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)

func _get_heading_degrees() -> float:
	var forward := -_camera.global_transform.basis.z
	forward.y = 0.0
	if forward.is_zero_approx():
		return 0.0
	forward = forward.normalized()
	return fposmod(rad_to_deg(atan2(forward.x, -forward.z)), 360.0)

func _get_target_relative_bearing() -> float:
	var direction := _target_position - _tracked_position.global_position
	direction.y = 0.0
	if direction.is_zero_approx():
		return 0.0
	var target_bearing := fposmod(rad_to_deg(atan2(direction.x, -direction.z)), 360.0)
	return wrapf(target_bearing - _get_heading_degrees(), -180.0, 180.0)
