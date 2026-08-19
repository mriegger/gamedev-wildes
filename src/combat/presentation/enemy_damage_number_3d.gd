extends Label3D
class_name EnemyDamageNumber3D

const DURATION_SECONDS: float = 0.8
const RISE_DISTANCE: float = 0.8
const PIXEL_SIZE: float = 0.02
const OUTLINE_COLOR: Color = Color(0.02, 0.02, 0.025, 0.95)

var _active: bool = false
var _elapsed: float = 0.0
var _start_position: Vector3 = Vector3.ZERO
var _base_color: Color = Color.WHITE

func _init() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	double_sided = true
	fixed_size = false
	no_depth_test = true
	render_priority = 2
	shaded = false
	font_size = 24
	outline_size = 4
	outline_modulate = OUTLINE_COLOR
	modulate = Color.WHITE
	pixel_size = PIXEL_SIZE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	visible = false

func play(world_position: Vector3, damage: float, color: Color) -> void:
	assert(world_position.is_finite())
	assert(is_finite(damage) and damage > 0.0)
	assert(is_finite(color.r) and is_finite(color.g) and is_finite(color.b) and is_finite(color.a))
	_active = true
	_elapsed = 0.0
	_start_position = world_position
	_base_color = color
	global_position = world_position
	text = _format_damage(damage)
	modulate = _base_color
	outline_modulate = OUTLINE_COLOR
	visible = true

func advance(delta: float, zoom_visible: bool) -> bool:
	assert(is_finite(delta) and delta >= 0.0)
	if not _active:
		return false
	_elapsed = minf(_elapsed + delta, DURATION_SECONDS)
	var progress := _elapsed / DURATION_SECONDS
	var alpha := 1.0 - smoothstep(0.0, 1.0, progress)
	global_position = _start_position + Vector3.UP * (RISE_DISTANCE * progress)
	modulate = Color(_base_color.r, _base_color.g, _base_color.b, _base_color.a * alpha)
	outline_modulate = Color(OUTLINE_COLOR.r, OUTLINE_COLOR.g, OUTLINE_COLOR.b, OUTLINE_COLOR.a * alpha)
	visible = zoom_visible and _elapsed < DURATION_SECONDS
	if _elapsed >= DURATION_SECONDS:
		_active = false
	return _active

func is_active() -> bool:
	return _active

func reset() -> void:
	_active = false
	_elapsed = 0.0
	_base_color = Color.WHITE
	modulate = Color.WHITE
	outline_modulate = OUTLINE_COLOR
	visible = false

func _format_damage(damage: float) -> String:
	return str(roundi(damage))
